# Checkmk

Infrastructure and application monitoring server (Checkmk Community edition) for hosts,
network devices, services and clouds, with agent-based and SNMP monitoring.

| | |
|---|---|
| Image | `docker.io/checkmk/check-mk-community:2.5.0p14` |
| Exposed | GUI 5000 via Traefik (internal-only); 8000/tcp agent receiver and 162/udp SNMP traps (loopback by default) |

## Quick start

```bash
docker network create proxy                     # once per host (shared with Traefik)
cp .env.example .env && vi .env                 # set CHECKMK_HOST, CMK_BIND_ADDRESS
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/cmk_password
chmod 444 secrets/cmk_password
docker compose up -d
```

First start creates the site, which takes a few minutes. Log in at
`https://<CHECKMK_HOST>/<CMK_SITE_ID>/` as `cmkadmin` with the password from
`secrets/cmk_password`.

Agents register and push to the agent receiver on port 8000, and devices send traps to 162/udp.
Both bind to `127.0.0.1` by default, so set `CMK_BIND_ADDRESS` to the monitoring interface's IP
before you roll out agents. Pull-mode agents (6556/tcp) are reached outbound over the `proxy`
network.

## Security notes

- **Exception: `no-new-privileges` is not set.** Checkmk's ICMP host checks (`check_icmp`),
  `check_dhcp` and the Event Console's trap/syslog helper (`mkeventd_open514`) are setuid-root
  binaries. With `no-new-privileges`, every ping-based host check fails. The setuid helpers
  still only get the reduced capability set below. If you use TCP-only host checks and no SNMP
  traps, restore `security_opt: [no-new-privileges:true]`.
- **Runs as root at start-up.** The upstream entrypoint manages the OMD site (useradd, chown,
  `omd create/update/start`, cron, xinetd) and runs all Checkmk processes as the site user
  (UID 1000). All capabilities are dropped except `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `FSETID`,
  `SETUID`, `SETGID`, `KILL`, `AUDIT_WRITE` and `NET_RAW`. Each has a comment in
  `compose.yaml`.
- The root filesystem is not read-only. The image writes system files (`/etc/passwd`, apache,
  cron, xinetd) at start-up. Site data lives in the `checkmk-data` volume, and the site `tmp`
  is a tmpfs.
- The image has no `*_FILE` support, so the admin password is a Docker secret read by a small
  wrapper entrypoint. It never appears in `docker inspect`, though it is visible in the
  entrypoint's process environment inside the container. It is only used when the site is
  first created. Change it afterwards in the GUI.
- The GUI is published only through Traefik, with the `internal-only@file` allow-list. The
  agent receiver uses its own TLS and needs no proxy.
- `CMK_MAIL_RELAY_HOST` starts postfix inside the container. Postfix also needs
  `SYS_CHROOT` (and `NET_BIND_SERVICE` if it listens on 25), so add them to `cap_add` if you
  enable it, or send notifications through an HTTP/API-based method instead.
- Livestatus TCP (6557) stays disabled.

## Backup

Use Checkmk's own site backup (Setup > Maintenance > Backups) to a mounted target, or archive
the site offline:

```bash
docker compose exec checkmk omd stop cmk
docker run --rm -v checkmk_checkmk-data:/data:ro -v "$PWD":/backup docker.io/library/alpine:3.24.2 \
  tar czf /backup/checkmk-$(date +%F).tar.gz -C /data .
docker compose restart checkmk
```

Upgrades: change the image tag and recreate. The entrypoint runs `omd update` automatically
when the site version no longer matches the image. Back up first.
