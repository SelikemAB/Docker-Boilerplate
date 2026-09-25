# Renovate CE

Mend Renovate Community Edition: a self-hosted Renovate server and worker that opens dependency
update merge requests on GitLab, triggered by webhooks and a schedule.

| | |
|---|---|
| Image | `ghcr.io/mend/renovate-ce:15.6.0-full` |
| Exposed | `https://RENOVATE_HOST/webhook` via Traefik (public); everything else internal-only |

## Quick start

1. Create a GitLab bot user and a PAT with the `api`, `read_user` and `write_repository` scopes.
2. Get a free Community Edition license key at <https://www.mend.io/renovate-community/>.

```bash
cp .env.example .env && chmod 600 .env
openssl rand -hex 32                            # use as MEND_RNV_WEBHOOK_SECRET
vi .env                                         # accept TOS, license key, PAT, webhook secret, endpoint
docker compose up -d
```

3. In GitLab, add a webhook (per project or group) to `https://RENOVATE_HOST/webhook` with the same
   secret token, for *Push*, *Merge request* and *Issue* events. Invite the bot user to the projects
   Renovate should manage (or set `RENOVATE_AUTODISCOVER=true`).

## Security notes

- Runs as the image's unprivileged user (UID 12021, GID 0) with all capabilities dropped. A
  one-shot `init-perms` job (only `CHOWN`, no network) makes the `/db` and `/logs` volumes writable.
- **Exception (read-only root FS not enabled):** the `-full` image's containerbase tooling writes
  caches and tool data to the home directory and `/tmp` at runtime.
- **Exception (secrets in `.env`):** Renovate CE reads `MEND_RNV_LICENSE_KEY`,
  `MEND_RNV_GITLAB_PAT` and `MEND_RNV_WEBHOOK_SECRET` only from plain environment variables (no
  `*_FILE` support). Keep `.env` at `chmod 600`, and note that the values are visible in
  `docker inspect` to anyone with Docker access. Compose refuses to start while any of them is
  empty, and the Terms of Service must be accepted explicitly (the template accepted them silently).
- Traefik exposes only `/webhook` publicly, and webhooks are authenticated with the shared secret.
  Other paths (`/health`, and the admin/reporting APIs if you enable them with
  `MEND_RNV_ADMIN_API_ENABLED` + `MEND_RNV_SERVER_API_SECRET`) are restricted by
  `internal-only@file`. No host port is published.
- Give the bot PAT the minimum scopes and an expiry date, and rotate it regularly.
- The container is on the `proxy` network, which also provides the egress it needs (GitLab API,
  package registries, changelog sources).

## Backup

The `renovate-db` volume holds the job queue and repository state, and `renovate-logs` holds job
logs. Both can be rebuilt, since Renovate rediscovers repositories. To keep history:

```bash
docker compose stop renovate
docker run --rm -v renovate_renovate-db:/db:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/renovate-db-$(date +%F).tar.gz -C /db .
docker compose start renovate
```

Keep `.env` in your secret manager.
