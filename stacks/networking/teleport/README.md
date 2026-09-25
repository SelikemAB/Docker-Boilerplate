# Teleport

Identity-aware access proxy for SSH, Kubernetes, databases, applications and desktops. This
stack runs a single-node cluster (Auth and Proxy services) behind the `traefik` stack.

| | |
|---|---|
| Image | `public.ecr.aws/gravitational/teleport-distroless:18.10.0` |
| Exposed | Nothing directly. Web UI, `tsh` and agent traffic go through Traefik on 443 (multiplexed) |

## Prerequisites

- The `traefik` stack is running. DNS for `TELEPORT_PUBLIC_HOST`, plus `*.TELEPORT_PUBLIC_HOST`
  for Application Access, points at the host. The traefik stack uses DNS-01, so the wildcard
  certificate is issued automatically.
- **ServersTransport drop-in:** Traefik re-encrypts to Teleport's self-signed listener. Copy the
  transport definition into the traefik stack once:
  ```bash
  cp traefik-dynamic/teleport.yaml ../traefik/config/dynamic/teleport.yaml
  ```

## Quick start

```bash
cp .env.example .env && vi .env        # TELEPORT_PUBLIC_HOST
# Set cluster_name, rp_id and public_addr (and nodename) in config/teleport.yaml.
# cluster_name can't be changed after the first start.
sed -i "s/teleport.example.com/$(. ./.env; echo "$TELEPORT_PUBLIC_HOST")/g" config/teleport.yaml
docker compose up -d
# Create the first admin (prints a one-time sign-up link):
docker compose exec teleport tctl users add admin --roles=editor,access --logins=root
```

No Docker secrets are needed. Teleport generates its CA and host keys in the data volume on
first start.

### Direct listeners (optional)

`compose.expose-ports.yaml` publishes the web/proxy port (3080) and the auth port (3025) on
`BIND_ADDRESS` (loopback by default). Use it for agents that join through the auth service, or
to bypass the L7 proxy:

```bash
docker compose -f compose.yaml -f compose.expose-ports.yaml up -d
```

## Security notes

- Distroless image (no shell or package manager) with **all capabilities dropped** and a
  read-only root filesystem. Only `/var/lib/teleport` (named volume) and `/tmp` (tmpfs) are
  writable, and the config is mounted read-only.
- **Runs as root (UID 0):** the vendor image is built to run as root. With no capabilities,
  `no-new-privileges`, only unprivileged listener ports and the SSH service disabled, root here
  can only write to its own data volume. `user:` is not overridden, because the data directory
  and the keys in it are owned by root.
- MFA is always required (`second_factors: [webauthn, otp]`) and passwordless WebAuthn is the
  default connector. Local users only. Add an SSO connector for enterprise IdPs.
- Public TLS terminates at Traefik (TLS 1.2+, HSTS). The Traefik-to-Teleport hop uses HTTPS
  with certificate verification disabled (`teleport-transport@file`). It stays on the Docker
  `proxy` network. `trust_x_forwarded_for` is enabled, so audit logs show real client IPs.
- The source template published 3080/3023/3024/3025 on all interfaces. In multiplex mode
  everything goes through the web port, so this stack publishes nothing by default. The direct
  ports are opt-in and loopback-bound.
- Healthcheck: the image has no HTTP client, so `tctl status` checks the local auth service
  through the node's admin identity.
- Data moved from the `./data` bind path to the named volume `teleport-data`.

## Backup

The `teleport-data` volume holds the cluster state (SQLite backend), the **CA private keys**,
the audit log and session recordings. Losing it means re-enrolling every user and agent. Stop
the container and archive the volume, encrypted:

```bash
docker compose stop teleport
docker run --rm -v teleport_teleport-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/teleport-data-$(date +%F).tar.gz -C /data .
docker compose start teleport
```

Keep `config/teleport.yaml` in version control. For production scale, move the backend and
session recordings to external storage (DynamoDB/etcd/Postgres and S3).
