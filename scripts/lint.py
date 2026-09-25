#!/usr/bin/env python3
"""Enforce the machine-checkable rules of docs/HARDENING.md on every stack.

Usage: python scripts/lint.py [stacks/...]
Exit code is non-zero when any rule is violated.
"""
import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
TAG_OK = re.compile(r"^[a-z0-9.\-]+(:\d+)?(/[a-z0-9._\-]+)+:[^:@\s]*\d+\.\d+[^:@\s]*(@sha256:[a-f0-9]{64})?$")
FORBIDDEN_TAGS = re.compile(r":(latest|stable|edge|main|master|nightly)(@|$)")

class ComposeLoader(yaml.SafeLoader):
    """SafeLoader that understands Compose's merge tags (!reset, !override)."""


def _compose_tag(loader, _suffix, node):
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node, deep=True)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    return loader.construct_scalar(node)


ComposeLoader.add_multi_constructor("!reset", _compose_tag)
ComposeLoader.add_multi_constructor("!override", _compose_tag)

SECRET_HINT = re.compile(r"(?i)(password|secret|token|api_?key|private_?key)\s*=\s*(?!$|change-?me|<|your|\$\{|replace|generate|example|xxx)(\S{6,})")


def exceptions(text):
    return {m.group(1).strip().lower() for m in re.finditer(r"#\s*HARDENING-EXCEPTION:\s*([^\n]+)", text)}


def has_exception(text, *words):
    return any(w in e for e in exceptions(text) for w in words)


def lint_compose(path: pathlib.Path):
    errors = []
    text = path.read_text(encoding="utf-8")
    # Standalone variants (marked STANDALONE in their header) are linted like a base file.
    is_override = path.name != "compose.yaml" and "STANDALONE" not in "".join(text.splitlines(True)[:3])
    try:
        doc = yaml.load(text, Loader=ComposeLoader) or {}
    except yaml.YAMLError as e:
        return [f"{path}: invalid YAML: {e}"]

    for name, svc in (doc.get("services") or {}).items():
        where = f"{path.relative_to(ROOT)}:{name}"
        img = svc.get("image")
        if img:
            if FORBIDDEN_TAGS.search(img) or not TAG_OK.match(img):
                errors.append(f"{where}: image '{img}' is not a fully-qualified, fully-pinned tag")
        if is_override:
            # Overrides only need to not weaken things silently.
            if svc.get("privileged") and not has_exception(text, "privileged"):
                errors.append(f"{where}: privileged without HARDENING-EXCEPTION")
            continue

        job = svc.get("restart") in ("no", "on-failure") or svc.get("profiles")
        if "no-new-privileges:true" not in (svc.get("security_opt") or []):
            if not has_exception(text, "no-new-privileges"):
                errors.append(f"{where}: missing security_opt no-new-privileges:true")
        if "ALL" not in (svc.get("cap_drop") or []) and not has_exception(text, "cap_drop"):
            errors.append(f"{where}: missing cap_drop: [ALL]")
        if svc.get("privileged") and not has_exception(text, "privileged"):
            errors.append(f"{where}: privileged: true without HARDENING-EXCEPTION")
        if svc.get("network_mode") == "host" and not has_exception(text, "host network"):
            errors.append(f"{where}: network_mode: host in base file (move to an override)")
        limits = ((svc.get("deploy") or {}).get("resources") or {}).get("limits") or {}
        if not ({"cpus", "memory", "pids"} <= set(limits)):
            errors.append(f"{where}: missing deploy.resources.limits cpus/memory/pids")
        if "pids_limit" in svc:
            # Current Compose rejects pids_limit alongside deploy.resources.limits.
            errors.append(f"{where}: use deploy.resources.limits.pids instead of pids_limit")
        log = svc.get("logging") or {}
        if log.get("driver") not in ("json-file", "local") or "max-size" not in (log.get("options") or {}):
            errors.append(f"{where}: missing rotated logging (json-file/local + max-size)")
        if svc.get("restart") not in ("unless-stopped", "always", "on-failure", "no"):
            errors.append(f"{where}: restart policy must be unless-stopped/always/on-failure (or \"no\" for one-shot jobs)")
        if not job and "healthcheck" not in svc and not has_exception(text, "healthcheck"):
            errors.append(f"{where}: missing healthcheck")
        for p in svc.get("ports") or []:
            spec = p if isinstance(p, str) else str(p.get("host_ip", "")) + ":" + str(p.get("published", ""))
            if isinstance(p, dict):
                if not p.get("host_ip") and not has_exception(text, "port"):
                    errors.append(f"{where}: port {p} has no host_ip binding")
            elif not spec.startswith("${") and not re.match(r"^\d+\.\d+\.\d+\.\d+:", spec):
                if not has_exception(text, "port"):
                    errors.append(f"{where}: port '{spec}' must bind an address (e.g. ${{BIND_ADDRESS:-127.0.0.1}}:...)")
        # A ':ro' bind does NOT restrict the Docker API, so only a filtered, read-only
        # socket proxy may mount the socket without a documented exception.
        is_proxy = "docker-socket-proxy" in (img or "")
        env = svc.get("environment") or {}
        if isinstance(env, list):
            env = dict(e.split("=", 1) if "=" in e else (e, "") for e in env)
        proxy_writes = str(env.get("POST", "0")).strip() not in ("0", "false", "")
        for v in svc.get("volumes") or []:
            spec = v if isinstance(v, str) else f"{v.get('source')}:{v.get('target')}"
            if "docker.sock" not in spec or has_exception(text, "docker socket", "docker.sock"):
                continue
            if not is_proxy:
                errors.append(f"{where}: docker socket mounted directly (use a socket proxy or add HARDENING-EXCEPTION)")
            elif proxy_writes:
                errors.append(f"{where}: socket proxy allows POST without HARDENING-EXCEPTION")
    return errors


def lint_stack(stack: pathlib.Path):
    errors = []
    rel = stack.relative_to(ROOT)
    for required in ("compose.yaml", "README.md"):
        if not (stack / required).is_file():
            errors.append(f"{rel}: missing {required}")
    env_example = stack / ".env.example"
    if not env_example.is_file():
        errors.append(f"{rel}: missing .env.example")
    else:
        for i, line in enumerate(env_example.read_text(encoding="utf-8").splitlines(), 1):
            if not line.lstrip().startswith("#") and SECRET_HINT.search(line):
                errors.append(f"{rel}/.env.example:{i}: looks like a real secret value, use a placeholder")
    if (stack / ".env").exists():
        errors.append(f"{rel}: .env must not be committed")
    secrets_dir = stack / "secrets"
    if secrets_dir.is_dir():
        for f in secrets_dir.iterdir():
            if f.name != ".gitkeep":
                errors.append(f"{rel}/secrets/{f.name}: secret files must not be committed")
    for f in sorted(stack.glob("compose*.yaml")):
        errors += lint_compose(f)
    return errors


def main(argv):
    targets = [pathlib.Path(a).resolve() for a in argv] or [ROOT / "stacks"]
    stacks = sorted({p.parent for t in targets for p in (t.rglob("compose.yaml") if t.is_dir() else [t])})
    errors = [e for s in stacks for e in lint_stack(s)]
    for e in errors:
        print(f"ERROR {e}")
    print(f"\nChecked {len(stacks)} stacks: {len(errors)} error(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
