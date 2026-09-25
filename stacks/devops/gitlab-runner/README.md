# GitLab Runner

GitLab CI/CD runner using the Docker executor: it picks up jobs from a GitLab instance and runs each
one in a fresh container on this host.

| | |
|---|---|
| Image | `docker.io/gitlab/gitlab-runner:alpine-v19.4.1` |
| Default job image | `docker.io/library/alpine:3.24.2` |
| Exposed | Nothing (outbound HTTPS to GitLab only) |

> **Warning: this stack gives the runner full control of the host's Docker daemon.** Anyone who
> can push a `.gitlab-ci.yml` to a project that uses this runner can effectively run code as root
> on the host. **Run it on a dedicated, disposable VM**, not on a host with other stacks or data.
> Register it as a project or group runner (not an instance-wide shared runner) unless you trust
> every project on the instance.

## Quick start

1. In GitLab, create a runner (*Admin* / *Group* / *Project* → *CI/CD* → *Runners* → *New runner*)
   and copy the authentication token (`glrt-...`).
2. On the dedicated runner host:

```bash
cp .env.example .env && vi .env                 # set GITLAB_URL
mkdir -p secrets && chmod 700 secrets
printf '%s' 'glrt-YOUR_RUNNER_TOKEN' > secrets/gitlab_runner_token
chmod 444 secrets/*                             # dir stays 700
docker compose up -d
docker compose logs -f gitlab-runner            # should report "Runner ... is running"
```

`config/config.toml.tmpl` is the runner configuration. At start, `config/render-config.sh` fills
in the URL, name, concurrency, default image, privileged flag and the token, and writes
`/etc/gitlab-runner/config.toml` into the `gitlab-runner-config` volume. Edit the template, not the
rendered file, then `docker compose restart gitlab-runner`.

## Security notes

- **Exception (Docker socket, read-write):** the Docker executor must create, start and remove job
  containers. A socket proxy doesn't help here, because that API access is already root-equivalent.
  This is why the runner belongs on a dedicated host.
- Hardened compared with the source template:
  - Job containers are **not privileged** by default (`RUNNER_PRIVILEGED=false`) and do **not**
    get the Docker socket mounted. Enable either only if you need Docker builds, and prefer
    rootless builders (Buildah, rootless BuildKit) where possible.
  - The default job image is pinned instead of `alpine:latest`.
  - The runner token is a Docker secret, rendered into `config.toml` (mode 600) at start instead of
    being committed in the config file. The Docker Hub credential placeholder from the template was
    removed. Use a masked `DOCKER_AUTH_CONFIG` CI/CD variable instead.
- The runner process runs as root inside the container (to use the root-owned socket), but with
  **all capabilities dropped**, `no-new-privileges` and a read-only root filesystem.
- Metrics (`:9252/metrics`) are used for the healthcheck and are not published.
- The custom CA feature of the image (`/etc/gitlab-runner/certs/ca.crt`) needs a writable root
  FS. If your GitLab uses a private CA, mount the CA bundle read-only over
  `/etc/ssl/certs/ca-certificates.crt` instead, or set `tls-ca-file` in the template.
- `pids_limit` and resource limits apply to the runner manager only. Limit job containers in the
  template (`[runners.docker]` `memory`, `cpus`, `pids_limit`) as needed.

## Backup

Nothing important is stateful: the `gitlab-runner-config` volume holds the rendered config and the
runner's system ID. To rebuild, keep `.env`, `config/` and the token (or create a new runner in
GitLab). Store `secrets/` in your secret manager.
