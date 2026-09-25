# BIND 9

Authoritative and recursive DNS server. It ships with an example primary zone (`home.arpa`), TSIG
authentication for zone transfers and dynamic updates, and automatic DNSSEC signing.

| | |
|---|---|
| Image | `docker.io/ubuntu/bind9:9.20-26.04_edge` (Canonical's versioning, not a floating `edge` tag) |
| Exposed | 53/tcp+udp (all interfaces) |

## Quick start

```bash
cp .env.example .env
mkdir -p secrets && chmod 700 secrets
# TSIG key (HMAC-SHA256, 256-bit). The key name must stay "tsig-transfer-key".
printf 'key "tsig-transfer-key" {\n    algorithm hmac-sha256;\n    secret "%s";\n};\n' \
  "$(openssl rand -base64 32)" > secrets/bind_tsig_key
chmod 444 secrets/*                             # readable by the non-root bind user; dir stays 700
docker compose up -d
dig @127.0.0.1 ns1.home.arpa                    # test
```

To use your own domain, replace `home.arpa` in `config/named.conf.zones` and
`config/zones/db.primary.zone` before the first start. Set the `ns1` A record to the server's real
address. The zone file is copied into the `bind9-zones` volume on first start only. After that,
edit it there (and bump the serial), or update it dynamically:

```bash
nsupdate -k secrets/bind_tsig_key <<'EOF'
server 127.0.0.1 53
zone home.arpa
update add nas.home.arpa 3600 A 192.168.1.10
send
EOF
```

After editing files in `config/`, run `docker compose restart bind9`.

If port 53 is taken on the host (`systemd-resolved`), set `DNSStubListener=no` in
`/etc/systemd/resolved.conf` and restart `systemd-resolved`.

### Variants

| File | Use |
|---|---|
| `compose.macvlan.yaml` | Own LAN IP. named listens on 53 inside the container |
| `compose.host-network.yaml` | Host networking. named starts as root, binds 53 and drops to `bind` |

## Security notes

- Runs as the unprivileged `bind` user with **all capabilities dropped** and a read-only root
  filesystem. named listens on 5053 inside the container, and the host maps 53 to it, so no
  `NET_BIND_SERVICE` is needed. BIND 9.20 skips capability handling when started as non-root.
- All configuration is mounted read-only. Only the zone and cache volumes, `/run/named` and
  `/tmp` are writable.
- Recursion and cache access are limited to the `trusted` ACL (RFC 1918 and loopback), so this
  is not an open resolver. Authoritative answers are public. Response rate limiting
  (20 responses/s) blunts reflection attacks.
- Zone transfers and dynamic updates are refused unless signed with the TSIG key. The key is a
  Docker secret that is included directly from `/run/secrets`.
- DNSSEC: validation of upstream answers (`dnssec-validation auto`) and automatic signing of the
  primary zone (`dnssec-policy default`). Keys are stored in the `bind9-cache` volume.
- Version, hostname and server ID are hidden. No rndc control channel is opened (`controls { };`).
  The image has no `dig`, so the healthcheck only checks that named accepts TCP on its DNS port.
- **Exception (port):** DNS binds `0.0.0.0:53` by default, because that is the purpose of a DNS
  server. Set `DNS_BIND_ADDRESS` to restrict it.
- **Exception (host network, override only):** `compose.host-network.yaml` uses
  `network_mode: host`. It adds `NET_BIND_SERVICE`, `SETUID` and `SETGID`, so named can bind 53
  as root and then switch to `bind`.
- `init-zones` is a one-shot job with no network. It needs `CHOWN` and `DAC_OVERRIDE` to seed
  the zone and hand the volumes to `bind`.

## Backup

Back up `secrets/bind_tsig_key` (in your secret manager) and the two volumes. `bind9-zones` holds
zone files and journals. `bind9-cache` holds the DNSSEC keys, and losing them means a key
rollover at the parent.

```bash
docker run --rm -v bind9_bind9-zones:/zones:ro -v bind9_bind9-cache:/cache:ro -v "$PWD":/backup \
  docker.io/library/alpine:3.24.2 tar czf /backup/bind9-$(date +%F).tar.gz -C / zones cache
```

The archive includes the `.jnl` journals, so dynamic updates are preserved. named merges journals
into the zone files when it stops.
