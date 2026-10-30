# Web image build contract

The web image is built **once** and serves staging, production and self-hosted
deployments. Everything that differs between them arrives as container
environment variables at runtime; the image itself is identical for all three.
GitHub Actions builds and smoke-tests the image on `ubuntu-24.04` for
`linux/amd64`, then publishes a private GHCR image. Coolify pulls and runs it on
the existing VPS. Environment configuration and domains stay in Coolify.

## Backend separation and release prerequisite

Production uses `https://pomodoist.supabase.co` with that Cloud
project's public key. This free vanity subdomain was confirmed active for
project `ewauihswbwduvklrozke` on 2026-10-30; it requires no paid Custom Domain
add-on or changes to the `pomodoist.com` DNS zone. HTTPS settings and Google/Apple
OAuth authorize redirects respond successfully through the vanity hostname;
a complete signed-in callback still needs device/browser verification.
The OAuth server metadata continues to declare
`https://ewauihswbwduvklrozke.supabase.co/auth/v1` as its issuer, so MCP token
validation must retain that canonical issuer. Staging alone uses Xubuntu at
`https://supabase-test.pomodoist.com` with its own public key. Native production
releases use the Cloud pair when no explicit pair is supplied. Official web,
Chrome and Telegram configurations reject the other environment's backend;
custom self-hosted endpoints remain supported. Local development profiles do
not connect to Xubuntu.

Keep `.env.setup` and its generated production profiles consistent. Empty
values in `.env.setup` do not clear existing generated values: when removing a
development backend, clear both `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the
existing local profile as well. Never commit private configuration files.

Cloud was upgraded on **2026-10-30** from migration `20261022080300` through
`20261029081042`. These five repository migrations were applied in order using
a temporary migration directory assembled from the actual Cloud history. The
self-hosted baseline was excluded; no migration-history repair was performed:

| Applied migration (under `server/supabase/migrations/`) | Installed behavior |
| --- | --- |
| `20261026081733_pomodoist_core_distraction_blocking_focus.sql` | Shared Focus authority and resource classification/cache RPCs |
| `20261028161223_pomodoist_core_focus_receipt_limit.sql` | Bounded Focus command receipts |
| `20261028162356_pomodoist_core_focus_transitions_and_locks.sql` | Concurrent Focus transitions and lifecycle locking |
| `20261028164545_pomodoist_core_focus_open_pause.sql` | Correct credit for an open pause at completion |
| `20261029081042_pomodoist_core_app_settings.sql` | Agent/device settings RPCs and private request metadata |

Post-upgrade inspection confirmed these SQL entrypoints and their role grants:
`public.pomodoist_focus(jsonb)`,
`public.pomodoist_resource_classification(jsonb)`,
`public.pomodoist_resource_cache_store(jsonb)`,
`public.pomodoist_app_settings_agent(uuid,uuid,uuid,jsonb)` and
`api_v1.pomodoist_app_settings_device(jsonb)`. Their private implementations,
permissions and tables were installed by the migrations above. Check the
`pomodoist-ai` and `pomodoist-mcp` Edge Functions against the selected release
as part of that deployment; the classification and app-settings consumers
require the corresponding SQL contracts.

The upgrade preserved all 214 accounts and profiles, 12,917 sync entities and
1,225 sync operation receipts. Per-entity-type row counts and checksums matched
before and after the migrations; the shared entity count remained 579. No
Xubuntu data was copied and no accounts or local SQLite databases were reset.
A completed Cloud physical backup was available before the upgrade.

The SQL migration prerequisite is satisfied. This is not a claim that the
complete production release has passed acceptance: the Cloud `pomodoist-ai`
and `pomodoist-mcp` Edge Functions still need release compatibility checks,
and authenticated device/browser flows need verification. Do not replay the
initial self-hosted baseline against the existing Cloud database.

Production runtime URL and public key in Coolify were updated together to the
Cloud vanity pair for the next image rollout; staging variables were retained.
Native build publication remains a separate release step.

## What the image accepts

Only two build arguments exist (`tool/deploy/web/Dockerfile`):

| Build argument | Value | Where it comes from |
| --- | --- | --- |
| `POMODOIST_BILLING_CHANNEL` | `stripe` | `tool/deploy/web/build-args.env` |
| `RELEASE_SHA` | full lowercase 40-character Git SHA | the commit being deployed |

`RELEASE_SHA` is deliberately absent from `build-args.env`: the builder
resolves it from the deployed commit, and the entrypoint then refuses to start
unless the container's `POMODOIST_RELEASE` matches the SHA baked into the image
(`tool/deploy/web/entrypoint.sh:33-38`). That equality is what ties a running
container back to a commit.

Everything else — `POMODOIST_ENVIRONMENT`, `POMODOIST_RELEASE`,
`POMODOIST_WEB_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `TURNSTILE_SITE_KEY`,
`SENTRY_DSN` — must **not** appear as a build argument. Passing one of them
freezes an environment into the image and silently breaks the "one image plus
runtime environment" rule.

The Dockerfile no longer relies on nobody passing them: it declares each name
and then fails the build when any of them arrives with a non-empty value
(`build argument SUPABASE_URL must stay a runtime environment variable`). The
guard is what makes the rule hold against a builder that injects build
arguments on its own.

## Per-environment identity at runtime

`config.js` is not the only thing that differs between environments. Two more
pieces are resolved when the container starts, so the image stays identical:

**Apple App Site Association.** The image ships the production association and
`tool/deploy/web/generate_aasa.sh` overwrites it before nginx starts (called from
`tool/deploy/web/entrypoint.sh`). The Apple team id is `4VK836929S`:

| `POMODOIST_ENVIRONMENT` | Associated app id |
| --- | --- |
| `production` | `4VK836929S.com.finchforge.pomodoist` |
| `staging` | `4VK836929S.com.finchforge.pomodoist.stg` |
| `selfhosted`, `development` | none — an empty association is written |

Self-hosted deployments serve a domain no app declares as an associated domain,
so they publish no app ids rather than claiming the production ones.

**Flavor assets.** `apps/flutter/web/index.html` reads `config.js` in `<head>`
and swaps the manifest link, favicon, apple-touch-icon, theme colour and display
name before the first paint, so one image carries all three icon sets. The names
below are the contract with the icon pipeline, and each flavor's manifest is
authoritative for its `icons`, `theme_color` and `name`:

| Flavor | Environment | Manifest | Fallback icon / favicon |
| --- | --- | --- | --- |
| development | `local` | `manifest-development.json` | `icons/development/Icon-192.png`, `icons/development/favicon.png` |
| staging | `staging` | `manifest-staging.json` | `icons/staging/Icon-192.png`, `icons/staging/favicon.png` |
| production | `production`, `selfhosted` | `manifest.json` | `icons/Icon-192.png`, `favicon.png` |

The production flavor is the identity already written into `index.html`, so it
needs no fetch and no DOM change: a production deployment renders exactly the
markup the build emitted. Every other flavor adopts its manifest first and falls
back to the production identity when an asset is missing or unreadable, instead
of leaving the page without an icon.

## GitHub Actions and Coolify configuration

`Deploy` starts directly on `develop` pushes and waits up to 30 minutes for a
successful `Validate` of that exact SHA before publishing staging. This works
before the image workflow reaches the default branch, where GitHub resolves
`workflow_run` subscriptions. Production wakes after a completed `Validate` on
`main`. Only successful **push** validations from `Kabanya/Pomodoist` qualify.
Manual dispatch requires an explicit full SHA and independently checks that
same branch/SHA has a successful push `Validate`. Deployments always require
that SHA to still be the branch head. To republish/redeploy the current head,
run `Deploy` manually; leave `deploy=false` for publication-only recovery.

The image is `ghcr.io/kabanya/pomodoist-web:<full-SHA>`. An existing tag is
pulled, checked and reused, never overwritten. CI serializes publishers per
SHA, waits 30 seconds before starting, and checks branch freshness before
building, publishing and immediately before modifying Coolify. The build job
has a 60-minute limit. Only `POMODOIST_BILLING_CHANNEL=stripe` and `RELEASE_SHA`
are build arguments. No runtime credentials or environment config enter the
build, and runtime image source maps are removed and blocked by nginx.

Publishing uses `GITHUB_TOKEN` with `packages:write`. GHCR packages start
private; keep package visibility private. After bootstrap, CI requires the existing
package to remain private before building/reusing and immediately before pushing.
A missing or public package fails closed. Give the VPS a separate classic PAT
with **only** `read:packages`, using `docker login ghcr.io --username Kabanya
--password-stdin` for the Coolify server user. Rotate it before its expiry.
Never copy the publisher token or an account token with repo/write permissions
to the VPS. See [GHCR authentication](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

Create two [Docker Image](https://coolify.io/docs/applications/deployments/docker-image)
resources, `Pomodoist Web Staging Image` and `Pomodoist Web Production Image`.
Coolify 4.1.2 cannot convert the original Git resources through its API.
Use port `8080`, HTTP health path `/healthz`, and the existing runtime variables,
networks and domains. Disable Git autodeploy; no source build runs on the VPS.

Repository secrets:

- `COOLIFY_IMAGE_TOKEN`: dedicated API token with read/write/deploy abilities;
  no sensitive read permission is needed.
- Existing `COOLIFY_STAGING_WEBHOOK` / `COOLIFY_PRODUCTION_WEBHOOK`: used only to
  derive the existing public HTTPS API origin, never invoked as webhooks.
  Localhost URLs are rejected. Existing ingress restrictions remain unchanged.

Repository variables:

- `WEB_STAGING_IMAGE_UUID`, `WEB_PRODUCTION_IMAGE_UUID`: new Docker Image UUIDs.
- `WEB_STAGING_IMAGE_DEPLOY_ENABLED`, `WEB_PRODUCTION_IMAGE_DEPLOY_ENABLED`:
  explicitly `true` to allow automatic or manual rollout; absent/false means
  publish only. Enable each after the initial resource/domain migration.

Each environment has a serial rollout group with cancellation disabled. Before
switching, CI records the previous tag, registry digest and observed release in
`web-deployment.json`. The current image/release must form a recoverable pair.
Image tag and `POMODOIST_RELEASE` are both updated **before** starting Coolify.
Coolify must finish, `/healthz` return 200 and `/version.json` contain the exact
SHA within five minutes. Otherwise both previous settings are restored, restarted
and verified with the same deadline; a failed rollback requires an operator.
Reports are retained as workflow artifacts. API error responses and runtime
secrets are never logged. The two PATCH requests are serialized, not atomic;
any partial update triggers restoration before another start.

For an initial migration, keep publication enabled and rollout flags disabled.
Verify a private pull on the VPS, start new resources without working domains,
and check their container-local endpoints. Transfer staging's domain and verify
public health/version before production. If a domain switch fails, return the
domain to the original running resource. Keep old resources stopped, without
domains or Git autodeploy, until another successful automatic update. Do not
prune Docker globally. FinchForge keeps its existing build configuration.

## Building locally

```sh
tool/deploy/web/build_image.sh [tag]
```

Sources `build-args.env`, takes `RELEASE_SHA` from the environment when the
deployment runner sets it and otherwise from `git rev-parse HEAD`, and tags the
result `pomodoist-web:<RELEASE_SHA>`. This uses the same Dockerfile and arguments
as CI; build outputs need not be byte-identical across rebuilds. Deploy the
recorded immutable digest rather than rebuilding an existing release.

`server/compose.yaml` (service `web`) is the self-hosted equivalent: it passes
`POMODOIST_BILLING_CHANNEL: stripe` and `RELEASE_SHA: ${POMODOIST_RELEASE}` and
supplies the runtime environment separately.

## Checking the contract

```sh
python3 tool/deploy/web/check_build_contract.py
python3 -m unittest discover -s tool -p 'test_web_build_contract.py'
python3 -m unittest discover -s tool -p 'test_web_image_ci.py'
```

The checker needs no Docker daemon and no third-party packages. It fails when a
runtime variable stops being declared or drops out of the Dockerfile guard, when
the guard loop disappears, when `RELEASE_SHA` stops being validated as a full
lowercase SHA, when the billing-channel guard disappears, when `build-args.env`
gains or loses a value, when the compose service drops a runtime variable or a
build argument, or when any build site stops passing exactly these two
arguments. The unit test mutates copies of the real files to prove each of those
failures actually fires.

Docker-dependent verification (`tool/test_web_container.sh`,
`tool/test_sentry_artifacts.sh`) still needs a running daemon; the checker only
covers what can be decided from the sources.

CI runs `image_ci.py smoke --sha <SHA>` against the prebuilt image, running it
with both staging and production configuration and rejecting a mismatched SHA.
It checks runtime identity/config, health, absent source maps and denied private
artifacts. The existing full container/Sentry tests remain available outside
the production VPS. Controller tests simulate stale heads, registry failure,
failed deployments, failed health checks, partial writes and verified rollback.
