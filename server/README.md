# Self-hosting Pomodoist

This directory runs a private Pomodoist server and web client with Docker Compose. It includes PostgreSQL, Auth, REST, Realtime, Edge Functions, a Kong API gateway, and the Flutter web app. Data stays in named Docker volumes. Optional AI, calendar, Telegram, Stripe, CAPTCHA, and Sentry integrations remain disabled until you add their credentials.

## Requirements

- Docker Engine or Docker Desktop with Compose v2
- `make`, `bash`, `openssl`, `curl`, and `jq`
- Node.js 16 or newer; when it is absent, setup uses a temporary `node:22-alpine` Docker container
- 4 GB RAM and 40 GB free disk as a practical minimum

## Local setup

From this directory:

```sh
make setup
make up
```

`make setup` creates `.env` with fresh database, API, encryption, and ES256 Auth signing keys. It keeps legacy HS256 API keys for client compatibility while Auth signs account sessions asymmetrically, so the MCP server can verify sessions through Auth's public JWKS endpoint. Setup never prints the secrets and refuses to replace an existing `.env`. Keep that file private and backed up separately.

The default endpoints are:

- Web app: `http://localhost:58080`
- API: `http://localhost:55421`

Create accounts in the web app. Local email accounts are auto-confirmed by default, so an SMTP server is not required for initial setup. Set `ENABLE_EMAIL_AUTOCONFIRM=false` and configure the `SMTP_*` values before requiring email verification.

The startup migration enables local Pomodoist access for this independent instance. The setting lives in a private schema, and account ownership and row-level isolation remain enforced.

Useful commands:

```sh
make status
make logs                 # or: make logs SERVICE=auth
make migrate
make test-db              # database contract against the running local DB
make test-smoke           # registration, login, sync, and tenant-isolation checks
make backup
make down                 # preserves all data
```

`make core-up` starts the API and function services without building the Flutter web image.

## Configuration

Edit `.env` before the first `make up` when changing ports or public URLs. Core startup does not require provider keys.

For Google sign-in, set `GOOGLE_AUTH_ENABLED=true`, its client ID and secret, and register `${API_EXTERNAL_URL}/callback` with Google. Google Calendar, Telegram, AI providers, CAPTCHA, monitoring, and Stripe each use the matching optional variables in `.env`. Stripe checkout stays disabled unless `STRIPE_CHECKOUT_ENABLED=true` and its required Stripe values are configured.

The browser receives only `ANON_KEY`; `SERVICE_ROLE_KEY`, the database password, and provider secrets stay in server containers. The database schema enforces account ownership and row-level isolation.

## HTTPS and a custom hostname

Plain HTTP is intended only for loopback. For a server, point DNS at the host and terminate TLS in a reverse proxy. Keep `BIND_ADDRESS=127.0.0.1`, then proxy two hostnames to the local ports. A minimal Caddy configuration is:

```caddyfile
api.example.com {
  reverse_proxy 127.0.0.1:55421
}

tasks.example.com {
  reverse_proxy 127.0.0.1:58080
}
```

Set these values in `.env` before recreating the services:

```dotenv
SUPABASE_PUBLIC_URL=https://api.example.com
API_EXTERNAL_URL=https://api.example.com/auth/v1
SITE_URL=https://tasks.example.com
ADDITIONAL_REDIRECT_URLS=https://tasks.example.com/login-callback,https://tasks.example.com/auth/challenge,pomodoist://login-callback,pomodoist://captcha-callback
POMODOIST_MCP_ALLOWED_ORIGINS=https://tasks.example.com
```

Then run `make up`. The proxy must forward `X-Forwarded-*` headers and WebSocket upgrades. Caddy does both automatically. Open ports 80 and 443 to the proxy; do not expose PostgreSQL or container-internal service ports.

## Backup and restore

`make backup` writes a compressed archive under `server/backups`. It captures application, Auth, and Vault data in one database snapshot, along with the instance's Vault encryption key. Treat it as sensitive. Keep a separate protected copy of `.env` as well. To choose another directory:

```sh
make backup BACKUP_DIR=/srv/pomodoist-backups
```

Test and copy backups off the server. Restore replaces the current database contents, so it requires both an exact file and an explicit confirmation token:

```sh
make restore \
  BACKUP=/srv/pomodoist-backups/pomodoist-20260906T120000Z.tar.gz \
  CONFIRM=--replace-current-database
```

Restore stops client-facing services, loads the dump in one transaction, and starts the stack again. It refuses a backup made from a different migration set, because data-only restores require the same server release. If database loading fails, it rolls the database transaction back and restores the previous Vault key before reporting failure.

## Updates

Container versions are pinned in `compose.yaml` and the Dockerfiles. Read the upstream self-hosting changelog before changing them. PostgreSQL major versions require a documented database upgrade; changing the image tag alone cannot upgrade an existing data volume. Make a verified backup before any version update.

This package intentionally omits Studio, Storage, image transformation, connection pooling, and log analytics because Pomodoist core does not need them. Add a service only when a deployed feature requires it.
