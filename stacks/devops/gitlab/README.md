# GitLab CE

Self-hosted GitLab Community Edition (Omnibus image): Git hosting, merge requests, issues, CI/CD
and an optional container registry, published through Traefik.

| | |
|---|---|
| Image | `docker.io/gitlab/gitlab-ce:19.4.1-ce.0` |
| Exposed | Web UI via Traefik (`GITLAB_HOST`), Git SSH on 2424/tcp (all interfaces), registry via Traefik (optional) |
| Requirements | 4 vCPU and 8 GB RAM recommended (4 GB minimum with the `homelab` preset) |

## Quick start

```bash
cp .env.example .env && vi .env                 # set GITLAB_HOST, GITLAB_ROOT_EMAIL
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/gitlab_root_password
chmod 444 secrets/*                             # dir stays 700
docker compose up -d
docker compose logs -f gitlab                   # first boot (reconfigure) takes several minutes
```

Log in as `root` with the password from `secrets/gitlab_root_password`. It is only applied on the
first initialization; change it in the UI afterwards and enable 2FA.

### Optional features

Combine overrides as needed:

```bash
# Container registry on GITLAB_REGISTRY_HOST
docker compose -f compose.yaml -f compose.registry.yaml up -d
# SMTP (needs secrets/gitlab_smtp_password)
printf '%s' 'SMTP_PASSWORD' > secrets/gitlab_smtp_password && chmod 444 secrets/gitlab_smtp_password
docker compose -f compose.yaml -f compose.smtp.yaml up -d
# OpenID Connect SSO, e.g. Authentik (needs secrets/gitlab_oidc_client_secret)
docker compose -f compose.yaml -f compose.oidc.yaml up -d
```

All settings live in `config/gitlab.rb`, which reads values from the environment (`.env`) and from
`/run/secrets`. It holds no secrets itself, so it can be committed. After changing it, run
`docker compose restart gitlab` (reconfigure runs on start).

### Upgrading

- The source template used 18.11.x. GitLab 19 has **required upgrade stops** (19.2, 19.5, 19.8,
  19.11): upgrade 18.11 → 19.0/19.2 first, let background migrations finish, then go to 19.4.1.
- GitLab 19 requires PostgreSQL 17. The bundled database is upgraded by the package, but check
  `gitlab-ctl pg-upgrade` output in the logs. Bundled Mattermost and Spamcheck are removed in 19.0,
  so any `mattermost[...]` keys must be removed from `gitlab.rb` (this file has none).
- Always back up before upgrading. See the
  [GitLab 19 upgrade notes](https://docs.gitlab.com/update/versions/gitlab_19_changes/).

## Security notes

- **Exception (runs as root, no read-only FS):** Omnibus is a runit-supervised multi-process image
  (nginx, Puma, Sidekiq, Gitaly, PostgreSQL, Redis, sshd) that must start as root and drop to
  per-service users. All capabilities are dropped, and only these are added back: `CHOWN`,
  `DAC_OVERRIDE`, `FOWNER`, `FSETID`, `SETUID`, `SETGID`, `KILL`, `NET_BIND_SERVICE` (nginx :80,
  sshd :22), `SYS_CHROOT` (sshd privilege separation) and `AUDIT_WRITE`. Compared with Docker's
  default set this removes `MKNOD`, `NET_RAW`, `SETPCAP` and `SETFCAP`. `no-new-privileges` is on.
- `package['modify_kernel_parameters'] = false`, so reconfigure never tries to set host sysctls.
- TLS terminates at Traefik. The bundled nginx listens on HTTP inside the container only, and no
  HTTP port is published. Client IPs are taken from `X-Forwarded-For` only for
  `GITLAB_TRUSTED_PROXIES`.
- The root, SMTP and OIDC secrets are Docker secrets that `gitlab.rb` reads from `/run/secrets`,
  so they never appear in the environment or `docker inspect`. GitLab stores its own generated
  secrets in `gitlab-secrets.json` in the `gitlab-config` volume.
- OIDC defaults to `uid_field: sub` (stable subject) instead of the template's `email`, and blocks
  auto-created users until an admin approves them (`GITLAB_OIDC_BLOCK_AUTO_CREATED_USERS`).
- Product usage data is off by default. The bundled Prometheus is off by default and, when
  enabled, stays inside the container.
- **Exception:** the Git SSH port binds `0.0.0.0` by default (`SSH_BIND_ADDRESS`), because Git
  clients must reach it. Restrict it with a host firewall or set a specific interface IP.
- The high `pids_limit` (4096) is intentional: GitLab's services together run thousands of threads.

## Backup

```bash
# Application data (repositories, DB, uploads, CI artifacts...)
docker compose exec -T gitlab gitlab-backup create STRATEGY=copy
# Written to /var/opt/gitlab/backups in the gitlab-data volume. Copy it off the host.
# The config and secrets are NOT included; back them up separately:
docker compose exec -T gitlab tar czf - -C /etc/gitlab gitlab-secrets.json > gitlab-secrets-$(date +%F).tgz
```

Without `gitlab-secrets.json`, encrypted data (CI variables, 2FA, runner tokens) cannot be restored.
Store it and `secrets/` in your secret manager.
