# Open WebUI

A self-hosted, multi-user chat interface for local models (Ollama) and OpenAI-compatible APIs,
with RAG, model management and user administration.

| | |
|---|---|
| Image | `ghcr.io/open-webui/open-webui:v0.11.4` |
| Optional | `docker.io/ollama/ollama:0.34.4` (`compose.ollama.yaml`) |
| Exposed | Nothing directly. HTTPS through Traefik at `OPENWEBUI_HOST` |

## Quick start

Requires the `traefik` stack (and its `proxy` network) to be running.

```bash
cp .env.example .env && chmod 600 .env && vi .env   # set OPENWEBUI_HOST, OLLAMA_BASE_URL
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 32 | tr -d '\n' > secrets/webui_secret_key     # signs sessions/JWTs
chmod 444 secrets/*
docker compose up -d                                        # external Ollama/OpenAI API
# or, with a bundled Ollama:
docker compose -f compose.yaml -f compose.ollama.yaml up -d
docker compose -f compose.yaml -f compose.ollama.yaml exec ollama ollama pull llama3.2
```

Open `https://<OPENWEBUI_HOST>` right away and register. **The first account becomes the
admin.** Then turn off sign-up (**Admin Panel → Settings → General**) or leave new users
`pending` for approval. `ENABLE_SIGNUP` and `DEFAULT_USER_ROLE` are stored in the database after
the first start, so changing `.env` later has no effect. Use the admin UI instead.

### Overrides

| File | Purpose |
|---|---|
| `compose.ollama.yaml` | Runs Ollama on a stack-local network. Its API is never published or put on `proxy`. Uncomment the GPU reservation for NVIDIA. |
| `compose.oidc.yaml` | OIDC login (authentik or any provider). Redirect URI: `https://<OPENWEBUI_HOST>/oauth/oidc/callback`. |

Combine them as needed: `docker compose -f compose.yaml -f compose.ollama.yaml -f compose.oidc.yaml up -d`.

## Security notes

- All capabilities are dropped and `no-new-privileges` is set. The image is built for UID 0.
  At runtime it writes into image paths (static assets, `pip install` of requirements for
  admin-installed Tools/Functions), so there is no `user:` override and no read-only root
  filesystem. Without capabilities, root in the container can't bypass file permissions, bind
  privileged ports or change ownership.
- `WEBUI_SECRET_KEY` comes from a Docker secret through the upstream `WEBUI_SECRET_KEY_FILE`
  support, so the image doesn't generate and store a key in its own filesystem. Keep the
  secret stable. Rotating it logs everyone out.
- Session and auth cookies are `Secure` (TLS terminates at Traefik), `SameSite=Lax`.
- No host ports are published. Only Traefik reaches the UI. `FORWARDED_ALLOW_IPS=*` is safe
  only because of that. Don't publish port 8080 directly with this setting.
- The optional Ollama API has no authentication. It stays on the stack-local `llm` network
  (not `proxy`), with no published port. It also runs as root with all capabilities dropped.
- Anonymous telemetry (Chroma, Scarf) is off.
- The OIDC client secret (optional override) has to be in `.env`, because Open WebUI can't read it
  from a file. Keep `.env` at `chmod 600`. OpenAI/API keys you enter in the admin UI are stored
  in the database in the data volume.
- Tools/Functions run arbitrary Python inside the container. Only admins can install them, so
  review them like code.
- No HARDENING-EXCEPTIONs.

## Backup

The `openwebui-data` volume holds everything: `webui.db` (users, chats, settings, API keys),
uploads, the vector DB and cached embedding models.

```bash
docker compose stop openwebui
docker compose run --rm -T --no-deps --entrypoint tar openwebui czf - -C /app/backend/data . > openwebui-data-$(date +%F).tar.gz
docker compose start openwebui
```

With `compose.ollama.yaml`, `ollama-models` can be re-downloaded and usually doesn't need a
backup. `secrets/` must be stored in your secret manager.
