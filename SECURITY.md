# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Use
[GitHub private vulnerability reporting](../../security/advisories/new) on this repository instead.
You should receive an acknowledgement within 5 business days.

This covers the configuration in this repository: insecure defaults, missing hardening, or leaked
example secrets. Vulnerabilities in the upstream software or container images should be reported
to their vendors.

## Supported versions

Only the `main` branch is supported. Image versions are kept current by Renovate. Pull the latest
`main` and redeploy to get fixes.

## Deployment responsibilities

These stacks are secure *starting points*, not a complete security programme. Before production:

1. Review each stack's **Security notes**, especially any `HARDENING-EXCEPTION`.
2. Keep secrets in a secret manager (Vault, Infisical, SOPS, ...) and inject them into `secrets/`
   at deploy time.
3. Harden the Docker host: rootless Docker or userns-remap, an up-to-date kernel, a CIS Docker
   Benchmark scan (`docker-bench-security`), and host firewall rules.
4. Put admin interfaces behind SSO (e.g. the Authentik stack) and the `internal-only` middleware.
5. Ship logs to a central SIEM and scan images regularly (Trivy, Grype, Docker Scout).
6. Test backups and restores.
