# Contributing

## Adding or changing a stack

1. Follow the layout and rules in [`docs/HARDENING.md`](docs/HARDENING.md). Start from a similar
   existing stack; `stacks/networking/traefik` and `stacks/databases/postgres` are the reference
   implementations.
2. Pin images to full version tags with a registry prefix.
3. Document every `# HARDENING-EXCEPTION:` in the stack README under **Security notes**.
4. Run the checks locally:

   ```bash
   pip install pyyaml
   python scripts/lint.py stacks/<category>/<service>
   docker compose --project-directory stacks/<category>/<service> \
     --env-file stacks/<category>/<service>/.env.example config --quiet
   ```

5. Add the stack to the catalogue table in `README.md`.

## Commit style

Use [Conventional Commits](https://www.conventionalcommits.org/), with the stack as the scope:
`feat(grafana): add OIDC login`, `fix(traefik): correct HSTS header`.

## Image updates

Renovate handles version bumps. Review its release-note links for breaking changes before
merging, especially for databases and major versions.
