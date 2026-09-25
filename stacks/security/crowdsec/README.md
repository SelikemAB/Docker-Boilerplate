# CrowdSec

Security engine that parses host and reverse-proxy logs, detects attacks, shares signals with the
CrowdSec community blocklist, and serves decisions to bouncers such as the Traefik plugin.

| | |
|---|---|
| Image | `docker.io/crowdsecurity/crowdsec:v1.8.1` |
| Optional helper | `docker.io/tecnativa/docker-socket-proxy:v0.5.0` (`compose.docker-logs.yaml`) |
| Exposed | Nothing. LAPI `8080` and AppSec `7422` are reachable on the `proxy` network only |

## Quick start

```bash
docker network create proxy                     # once per host (normally done by the traefik stack)
cp .env.example .env && vi .env
mkdir -p secrets && chmod 700 secrets
openssl rand -hex 32 | tr -d '\n' > secrets/bouncer_key_traefik
chmod 444 secrets/*
docker compose up -d
docker compose exec crowdsec cscli bouncers list    # "traefik" is registered from the secret
```

Give the Traefik bouncer plugin the same key and `crowdsecLapiHost: crowdsec:8080`. To add more
bouncers, add a secret named `bouncer_key_<name>` to the `crowdsec` service. The entrypoint
registers each one on start.

## Log sources

| Source | How to enable |
|---|---|
| Host `auth.log` / `syslog` | On by default (`config/acquis.yaml`). Adjust the file names for RHEL-like systems. |
| Container logs (e.g. Traefik JSON access log on stdout) | `cp config/optional/docker.yaml config/acquis.d/` and add `-f compose.docker-logs.yaml` |
| Traefik access log file on the host | `cp config/optional/traefik-file.yaml config/acquis.d/` and add `-f compose.traefik-logfile.yaml` |
| AppSec / WAF for the Traefik plugin | `cp config/optional/appsec.yaml config/acquis.d/` and add the AppSec collections to `CROWDSEC_COLLECTIONS` |

`compose.expose-ports.yaml` publishes LAPI and AppSec on `127.0.0.1` for bouncers running
outside Docker, such as the host firewall bouncer.

## Security notes

- All capabilities are dropped and `no-new-privileges` is set. The container keeps
  `DAC_READ_SEARCH` so it can read host logs owned by other users. The host log directory is
  mounted read-only.
- **Exception: runs as root.** The upstream entrypoint populates `/etc/crowdsec`, registers the
  local agent and installs hub content as root, and the host logs are root/adm-owned. No `user:`
  is set, and the root filesystem stays writable because the entrypoint symlinks staged data files
  and edits configuration at start.
- The bouncer key is a Docker secret (`/run/secrets/bouncer_key_traefik`), which the entrypoint
  reads natively.
- **Exception: `.env` secret.** `CROWDSEC_ENROLL_KEY` goes through `.env`, because the entrypoint
  has no `_FILE` variant for it. It's only needed once, so clear it after enrollment.
- No ports are published. LAPI and AppSec are reachable only from containers on the `proxy`
  network. The stack-local `crowdsec` network provides egress to the Central API and the hub.
- No Docker socket is mounted by default. `compose.docker-logs.yaml` uses a socket proxy with
  read-only access to containers and events (`POST=0`) on an `internal` network.
- Enrolling in the Console or using the Central API shares attack signals (attacker IP, scenario,
  timestamp) with CrowdSec. Review this against your data-protection requirements.

## Backup

Back up the `crowdsec-config` volume (machine and CAPI credentials, hub state, local customisations)
and the `crowdsec-data` volume (SQLite database with decisions, alerts and registered bouncers),
plus `config/` and `secrets/`:

```bash
docker compose exec -T crowdsec tar czf - -C /etc/crowdsec . > crowdsec-config-$(date +%F).tgz
docker compose exec -T crowdsec tar czf - -C /var/lib/crowdsec/data . > crowdsec-data-$(date +%F).tgz
```

For a fully consistent SQLite copy, run `docker compose stop` first and archive the volumes from
the host.
