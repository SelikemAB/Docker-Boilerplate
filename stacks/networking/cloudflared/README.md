# Cloudflared

Cloudflare Tunnel connector. It publishes private services through Cloudflare Zero Trust
over outbound-only connections, so no inbound ports or public IP are needed.

| | |
|---|---|
| Image | `docker.io/cloudflare/cloudflared:2026.9.3` |
| Exposed | Nothing (outbound 7844/udp+tcp to Cloudflare) |

## Quick start

1. In the Zero Trust dashboard, go to **Networks → Tunnels → Create a tunnel**
   (type *Cloudflared*) and copy the token from the install command.
2. Deploy:

```bash
cp .env.example .env
mkdir -p secrets && chmod 700 secrets
printf '%s' 'YOUR_TUNNEL_TOKEN' > secrets/tunnel_token
chmod 444 secrets/*                    # readable by the nonroot container user; dir stays 700
docker compose up -d
docker compose ps                      # becomes "healthy" once connected to the edge
```

3. Add **public hostnames** in the dashboard. The container is on the `proxy` network, so a
   service URL can be any container name on it, e.g. `http://whoami:8080`, or
   `https://traefik:8443` (enable *No TLS Verify* or set *Origin Server Name*) to reuse Traefik
   routing.

## Security notes

- Distroless image running as `nonroot` (65532) with all capabilities dropped and a read-only
  root filesystem. Publishes no ports.
- The tunnel token is a Docker secret, read through `TUNNEL_TOKEN_FILE` (cloudflared
  ≥ 2025.4). It never appears in `docker inspect` or the process list.
- Auto-update is disabled by the image entrypoint (`--no-autoupdate`). Updates come through
  Renovate.
- The metrics and readiness endpoint is bound to the container loopback (`127.0.0.1:2000`).
  The healthcheck uses the built-in `cloudflared tunnel ready` probe, which fails until the
  tunnel has an active edge connection.
- Anyone who holds the token can run a connector for your tunnel. Rotate it in the dashboard if
  it leaks.
- Put Cloudflare Access policies in front of internal applications. The tunnel only provides
  transport.

## Backup

Stateless. The tunnel configuration lives in Cloudflare. Keep `secrets/tunnel_token` in your
secret manager.
