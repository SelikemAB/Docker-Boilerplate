# Semaphore UI

Web UI and scheduler for Ansible playbooks, Terraform/OpenTofu, and shell or Python scripts, with
projects, inventories, access keys and run history, backed by PostgreSQL.

| | |
|---|---|
| Image | `docker.io/semaphoreui/semaphore:v2.19.14` |
| Database | `docker.io/library/postgres:18.6-alpine` |
| Exposed | Web UI via Traefik (`SEMAPHORE_HOST`, internal networks only) |

## Quick start

```bash
cp .env.example .env && vi .env                 # set SEMAPHORE_HOST, admin user/e-mail
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/semaphore_db_password
openssl rand -base64 24 | tr -d '\n' > secrets/semaphore_admin_password
openssl rand -base64 32 | tr -d '\n' > secrets/semaphore_access_key_encryption   # must be base64 of 32 bytes
chmod 444 secrets/*                             # readable by the non-root container users; dir stays 700
docker compose up -d
```

Log in with `SEMAPHORE_ADMIN` and the password from `secrets/semaphore_admin_password`. The admin is
created only on the first start.

## Security notes

- Runs as the image's unprivileged user (UID 1001) with all capabilities dropped.
- **Exception (read-only root FS not enabled):** task runs install Ansible collections and roles,
  Python requirements and tool versions inside the container at runtime.
- The DB password, initial admin password and access-key encryption key are Docker secrets
  consumed through the image's `*_FILE` support (`server-wrapper`). On first start Semaphore writes
  `config.json` (including DB credentials and the encryption key) into the `semaphore-config`
  volume, so treat that volume as sensitive.
- `SEMAPHORE_ACCESS_KEY_ENCRYPTION` encrypts the SSH keys and passwords stored in the database.
  If you lose it, stored credentials can't be decrypted.
- SSH host key checking is **on** by default (`ANSIBLE_HOST_KEY_CHECKING=True`). The image's global
  `ssh_config` disables strict checking for Git operations, but this setting still applies to
  Ansible connections. Set it to `False` only if you understand the MITM risk.
- The UI is an automation control plane with credentials to your fleet, so Traefik restricts it to
  private address ranges (`internal-only@file`). No host port is published.
- PostgreSQL runs as UID 70 with SCRAM-SHA-256, a read-only root FS and no published port, on an
  `internal` network. MySQL 8.1 and SQLite from the original template are replaced by PostgreSQL.
- Semaphore is also on the `proxy` network, which gives it the egress it needs to reach managed
  hosts, Git remotes and Ansible Galaxy.

## Backup

```bash
docker compose exec -T postgres pg_dump -U semaphore -Fc semaphore > semaphore-db-$(date +%F).dump
docker run --rm -v semaphoreui_semaphore-config:/c:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/semaphore-config-$(date +%F).tar.gz -C /c .
```

Store `secrets/` (especially `semaphore_access_key_encryption`) in your secret manager.
