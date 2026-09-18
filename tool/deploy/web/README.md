# Web image build contract

The web image is built **once** and serves staging, production and self-hosted
deployments. Everything that differs between them arrives as container
environment variables at runtime; the image itself is identical for all three.
Coolify builds this image on its own infrastructure, so the build arguments
live in its dashboard rather than in a workflow file — the two files below are
what makes that arrangement checkable from the repository.

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

## Coolify configuration

The webhook-triggered build must use:

- Dockerfile: `tool/deploy/web/Dockerfile`
- Build context: repository root (the Dockerfile copies `.fvmrc`,
  `apps/flutter/**`, `apps/telegram-mini-app/**` and `tool/deploy/web/**`)
- Build arguments: exactly the two rows above, with `RELEASE_SHA` set to the
  SHA of the commit being deployed

Coolify injects a build argument for **every** environment variable whose
"buildtime" toggle is on, so the seven runtime variables above must be marked
runtime-only in the dashboard. With the toggle on, the next build fails in the
guard instead of producing an image with that environment baked in — a loud
failure, but the setting still has to be right.

The repository cannot read or verify those dashboard values. What it can do is
fail when the code that the dashboard must match drifts: `check_build_contract.py`
below compares the Dockerfile, `build-args.env`, `server/compose.yaml`, the
entrypoint and every in-repository build site against each other.

## Building locally

```sh
tool/deploy/web/build_image.sh [tag]
```

Sources `build-args.env`, takes `RELEASE_SHA` from the environment when the
deployment runner sets it and otherwise from `git rev-parse HEAD`, and tags the
result `pomodoist-web:<RELEASE_SHA>`. This is the same build Coolify performs,
so it is the way to reproduce an image byte-for-byte before a deploy.

`server/compose.yaml` (service `web`) is the self-hosted equivalent: it passes
`POMODOIST_BILLING_CHANNEL: stripe` and `RELEASE_SHA: ${POMODOIST_RELEASE}` and
supplies the runtime environment separately.

## Checking the contract

```sh
python3 tool/deploy/web/check_build_contract.py
python3 -m unittest discover -s tool -p 'test_web_build_contract.py'
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
