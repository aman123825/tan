# Deploying the HearBloom research API (J1)

Research software — **not a medical device**. The backend stores research
consent records and per-trial data; treat any host as holding personal data
and secure it accordingly.

## One-machine deployment (Docker)

```bash
docker build -t hearbloom-api .
docker run -d --name hearbloom \
  -p 8000:8000 \
  -v hearbloom-data:/app/data \
  -e HEARBLOOM_AUTH_KEY="$(openssl rand -hex 32)" \
  -e HEARBLOOM_CONTENT_KEY="$(openssl rand -hex 32)" \
  -e HEARBLOOM_CORS_ORIGINS="https://your-app-origin.example" \
  hearbloom-api
```

`docker compose up` still works for development (it pip-installs into a bare
python image and reloads from the working tree).

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `HEARBLOOM_DB` | `<repo>/data/hearbloom.db` | SQLite path. Point at a mounted volume in production. |
| `HEARBLOOM_AUTH_KEY` | dev key | **Must be overridden in production.** Signs account bearer tokens (HMAC-SHA256). Rotating it invalidates all sessions. |
| `HEARBLOOM_CONTENT_KEY` | dev key | Signs the `/content/manifest` integrity manifest. |
| `HEARBLOOM_TOKEN_TTL` | `2592000` (30 d) | Token lifetime in seconds. |
| `HEARBLOOM_CORS_ORIGINS` | `*` | Comma-separated allowed origins. Restrict to the web app's origin in production. |

## Checklist before going live

1. **TLS**: put the container behind a reverse proxy (Caddy/nginx/Traefik)
   that terminates HTTPS. Bearer tokens must never travel over plain HTTP.
2. **Keys**: set real `HEARBLOOM_AUTH_KEY` / `HEARBLOOM_CONTENT_KEY` values
   (32+ random bytes) and store them in your secret manager.
3. **Backups**: the SQLite file under `/app/data` is the entire datastore;
   snapshot the volume. For multi-instance deployments move to a
   client/server database first — SQLite is single-writer.
4. **CORS**: set `HEARBLOOM_CORS_ORIGINS` to the exact web-app origin(s).
5. **Consent**: serve the app only with the consent flow enabled (the client
   records consent via `POST /profiles/{id}/consent`; see `docs/CONSENT.md`).
   Bump `CONSENT_VERSION` in `services/api/main.py` whenever the consent
   text changes.
6. **Erasure requests**: `DELETE /profiles/{id}` (anonymous, id-as-capability)
   and `DELETE /accounts/me` (token) remove all associated sessions/trials.
   `GET /profiles/{id}/export.json|.csv` covers data-portability requests.
7. **Health/monitoring**: `GET /health` is unauthenticated and cheap; the
   Docker image ships a HEALTHCHECK against it.

## Endpoint summary (added for J5/J8)

- `POST /accounts/register` `{email, password}` → `{id, email, token}`
- `POST /accounts/login` → `{token}` (401 on bad credentials)
- `GET /accounts/me` (Bearer) → account + linked profile ids
- `POST /profiles/{id}/link` (Bearer) → attach an anonymous profile
- `POST /profiles/{id}/consent` `{consented, consent_version}` → stored record
- `DELETE /profiles/{id}` → cascade-delete profile + sessions + trials
- `DELETE /accounts/me` (Bearer) → delete account + every linked profile

All pre-existing endpoints remain anonymous-capable: accounts are an opt-in
convenience for reconnecting and erasing data, never a wall in front of the
research app.
