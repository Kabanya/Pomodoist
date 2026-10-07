SHELL := /bin/sh
export COMPOSE_OVERLAYS
COMPOSE := docker compose --project-directory . --env-file .env -f compose.yaml $(foreach overlay,$(COMPOSE_OVERLAYS),-f $(overlay))

.PHONY: setup validate up core-up down status logs migrate backup restore test-db test-smoke test-sessions test-openclaw test-openclaw-native

setup:
	sh scripts/bootstrap.sh
	$(MAKE) validate

validate:
	sh scripts/validate.sh

up:
	@test -f .env || (echo 'Run make setup first.' >&2; exit 1)
	@sh scripts/refresh-release.sh
	$(COMPOSE) up -d --no-deps --wait db
	@baseline=$$(mktemp); trap 'rm -f "$$baseline"' EXIT HUP INT TERM; \
	  python3 scripts/sync_health.py capture pomodoist-selfhost-db "$$baseline" && \
	  $(COMPOSE) up -d --build --wait && \
	  python3 scripts/sync_health.py check pomodoist-selfhost-db "$$baseline"
	sh scripts/status.sh

core-up:
	@test -f .env || (echo 'Run make setup first.' >&2; exit 1)
	$(COMPOSE) up -d --build --wait db auth rest realtime migrate gateway functions

down:
	$(COMPOSE) down

status:
	sh scripts/status.sh

logs:
	$(COMPOSE) logs -f $(SERVICE)

migrate:
	$(COMPOSE) run --rm --name pomodoist-selfhost-migrate-manual migrate

backup:
	sh scripts/backup.sh $(BACKUP_DIR)

restore:
	sh scripts/restore.sh "$(BACKUP)" "$(CONFIRM)"

test-db:
	@test -f .env || (echo 'Run make setup first.' >&2; exit 1)
	@PGPASSWORD=$$(sed -n 's/^POSTGRES_PASSWORD=//p' .env) bash tests/database/run.sh pomodoist-selfhost-db

test-smoke:
	sh scripts/smoke-test.sh

test-sessions:
	node tests/session-revocation.mjs --local

test-openclaw:
	node tests/openclaw-smoke.mjs --local

test-openclaw-native:
	node tests/openclaw-native.mjs --local
