# Twingate Connector

Twingate Connector for zero-trust access to private Resources. It makes outbound-only
connections to Twingate, so no inbound ports are opened.

| | |
|---|---|
| Image | `docker.io/twingate/connector:1.93.0` |
| Exposed | Nothing (outbound only) |

## Quick start

1. In the Admin Console, go to **Remote Networks → your network → Deploy Connector → Docker**
   and generate tokens.
2. Deploy:

```bash
cp .env.example .env && chmod 600 .env
vi .env                                # TWINGATE_NETWORK, TWINGATE_ACCESS_TOKEN, TWINGATE_REFRESH_TOKEN
docker compose up -d
docker compose ps                      # "healthy" once the connector service runs
```

Deploy at least two connectors per Remote Network (on different hosts) for high availability.

For Resources that are other containers, attach the connector to their networks by adding them
under `networks:`. It reaches LAN Resources through the host's default route.

For a custom DNS resolver, add `TWINGATE_DNS: <ip>` to the environment in `compose.yaml`.

## Security notes

- Distroless vendor image running as `nonroot` (65532) with **all capabilities dropped**. Ping
  to Resources works through the namespaced sysctl `net.ipv4.ping_group_range`
  (unprivileged ICMP sockets) instead of `NET_RAW`.
- Publishes no ports.
- **Secrets in `.env`:** the image has no `*_FILE` support, so the access and refresh tokens
  are passed as environment variables from `.env` (git-ignored, `chmod 600`). They are visible
  to anyone who can run `docker inspect` on the host. Revoke them in the Admin Console if they
  leak.
- **Root FS not read-only:** the connector writes its control socket and crash-report
  directory under `/var/run/twingate`, which the image ships pre-created and owned by
  `nonroot`. A `tmpfs` over it would lose the ownership and layout, so `read_only` is not set.
- The healthcheck (`/connectorctl health`) only checks that the connector service is running.
  It doesn't check connectivity to Twingate. Watch the connector status in the Admin Console.

## Backup

Stateless. Re-deploying only needs new tokens from the Admin Console.
