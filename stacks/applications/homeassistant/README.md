# Home Assistant

Open-source home automation that puts local control and privacy first, with thousands of device
integrations.

| | |
|---|---|
| Image | `ghcr.io/home-assistant/home-assistant:2026.9.3` |
| Exposed | Nothing directly. HTTPS through Traefik at `HA_HOST` (host variant: 8123/tcp on the host) |

## Quick start

Requires the `traefik` stack (and its `proxy` network) to be running.

```bash
cp .env.example .env && vi .env                 # set HA_HOST, check HA_TRUSTED_PROXIES
docker network inspect proxy -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'   # must be inside HA_TRUSTED_PROXIES
docker compose up -d
docker compose logs -f homeassistant            # first start takes a few minutes
```

Open `https://<HA_HOST>` and complete onboarding (create the owner account right away). No
secrets are used, so there is no `secrets/` directory. Credentials live in HA's own auth store.

On first start the `init-config` job copies `config/configuration.yaml` into the volume, but
only if no `configuration.yaml` exists yet. The seed is HA's default config plus an `http:`
block that trusts the reverse proxy (`use_x_forwarded_for`, `trusted_proxies`). Without that
block HA rejects proxied requests with `400 Bad Request`. If you migrate an existing config,
add the block yourself.

## Variants (opt-in)

| File | Use | Command |
|---|---|---|
| `compose.host-network.yaml` | LAN discovery (mDNS/zeroconf, SSDP, DHCP, HomeKit, Chromecast/Sonos, Matter) and Bluetooth via host D-Bus | `docker compose -f compose.host-network.yaml up -d` |
| `compose.devices.yaml` | Zigbee/Z-Wave/Thread USB sticks, mapped individually | add `-f compose.devices.yaml` to either command |
| `compose.privileged.yaml` | Last resort for hardware that can't be mapped (GPIO, I2C, arbitrary hot-plug) | `-f compose.host-network.yaml -f compose.privileged.yaml` |

`compose.host-network.yaml` is a **standalone** file, not an override. Use it *instead of*
`compose.yaml`, because Compose can't remove the `proxy` network from a service with an
override. It uses the same volume, so you can switch back and forth. In host mode HA listens
directly on `<host>:8123` and Traefik can't reach it through the `proxy` network. Either open
it directly (firewall the port to your LAN) or add a Traefik file-provider route to the host IP.

For USB sticks, set `HA_SERIAL_DEVICE` to the stable path from `ls -l /dev/serial/by-id/`. The
device appears as `/dev/ttyACM0` in the container. Configure ZHA/Z-Wave with that path.

Integrations that need their own companion services (Mosquitto, Z-Wave JS UI, Zigbee2MQTT,
Matter Server, Piper/Whisper) aren't part of this stack. Run them as separate stacks on a
shared network.

## Security notes

- The image runs s6-overlay as root, so `user:` can't be set. All capabilities are dropped and
  only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID` and `SETGID` are added back for the init
  system. `no-new-privileges` is on. The host variant also adds `NET_RAW` and `NET_ADMIN` for DHCP
  discovery and Bluetooth.
- The root filesystem isn't read-only, because HA installs Python packages for integrations
  at runtime.
- By default there is no host networking, no privileged mode, no D-Bus mount and no device
  access. No host ports are published. Everything goes through Traefik (TLS and security
  headers). HA's own login protects the UI. `ip_ban_enabled` bans an IP after 10 failed logins.
  No `internal-only@file` allow-list is applied, so the mobile app works remotely. Add it with
  `traefik.http.routers.homeassistant.middlewares: internal-only@file` if you only use HA on the
  LAN or over a VPN.
- `trusted_proxies` is limited to the Docker proxy subnet and loopback, so clients can't spoof
  `X-Forwarded-For` from elsewhere.
- **Exception (host network):** `compose.host-network.yaml` uses `network_mode: host`, because
  multicast/broadcast discovery and Bluetooth don't work across a Docker bridge. HA and
  go2rtc (ports 8123, 1984, 8554, 8555) are then reachable on all host interfaces. Firewall them.
- **Exception (privileged):** `compose.privileged.yaml` sets `privileged: true` for hardware
  that can't be passed through with `devices:`. Prefer `compose.devices.yaml`, which maps
  only the named device nodes.

## Backup

Everything lives in the `homeassistant-config` volume (configuration, `.storage/` auth and
integration data, and the `home-assistant_v2.db` recorder database). Use HA's built-in backup
(**Settings → System → Backups**, stored in `/config/backups`) and copy the archives off the
host, or take a cold copy:

```bash
docker compose stop homeassistant
docker compose run --rm -T --no-deps --entrypoint tar init-config czf - -C /config . > ha-config-$(date +%F).tar.gz
docker compose start homeassistant
```

The backup contains long-lived access tokens and integration credentials. Store it encrypted.
