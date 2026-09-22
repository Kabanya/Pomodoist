#!/usr/bin/env python3
import base64
import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"TestFlight config error: {message}", file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 2:
    fail("expected a path to the TestFlight env file")

path = Path(sys.argv[1])
if not path.is_file():
    fail(f"missing {path}")

values: dict[str, str] = {}
for line in path.read_text(encoding="utf-8").splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if "=" not in stripped:
        fail(f"invalid line for {stripped.split()[0]}")
    name, value = stripped.split("=", 1)
    if name in values:
        fail(f"duplicate {name}")
    values[name] = value

environments = {
    "production": {
        "WEB_APP_URL": "https://app.pomodoist.com",
        "POMODOIST_REGISTRATION_URL": "https://app.pomodoist.com/auth/challenge",
        "SUPABASE_URL": "https://ewauihswbwduvklrozke.supabase.co",
    },
    "staging": {
        "WEB_APP_URL": "https://app-test.pomodoist.com",
        "POMODOIST_REGISTRATION_URL": "https://app-test.pomodoist.com/auth/challenge",
        "SUPABASE_URL": "https://supabase-test.pomodoist.com",
    },
}
environment = values.get("POMODOIST_ENVIRONMENT")
expected = environments.get(environment)
if expected is None:
    fail("POMODOIST_ENVIRONMENT must be production or staging")
for name, value in expected.items():
    if values.get(name) != value:
        fail(f"{name} must be {value} for {environment}")

for name in ("SUPABASE_ANON_KEY", "TURNSTILE_SITE_KEY"):
    if not values.get(name):
        fail(f"{name} must not be empty")
if "SENTRY_DSN" not in values:
    fail("SENTRY_DSN must be present (it may be empty)")


def flag_state(name: str) -> str:
    """Return whether an optional boolean dart-define is unset, off or on."""
    raw = values.get(name)
    if raw is None:
        return "unset"
    normalized = raw.strip().lower()
    if normalized in ("", "0", "false"):
        return "off"
    if normalized in ("1", "true"):
        return "on"
    fail(f"{name} must be empty, 0, 1, true or false")


# Staging TestFlight uses the local store; production stays on the remote App
# Store server.
dev_unlock = flag_state("POMODOIST_DEV_UNLOCK")
local_storekit = flag_state("POMODOIST_LOCAL_STOREKIT")
if environment == "staging":
    if dev_unlock == "off":
        fail("POMODOIST_DEV_UNLOCK must not be disabled for staging")
else:
    if dev_unlock == "on":
        fail("POMODOIST_DEV_UNLOCK must not be enabled for production")
    if local_storekit == "on":
        fail("POMODOIST_LOCAL_STOREKIT must not be enabled for production")

for name, value in values.items():
    if name.startswith(("SUPABASE_SERVICE_ROLE", "SUPABASE_SECRET")):
        fail(f"{name} is forbidden in a client build")
    if value.startswith("sb_secret_"):
        fail(f"secret Supabase key found in {name}")

key = values["SUPABASE_ANON_KEY"]
if key.startswith("sb_publishable_"):
    raise SystemExit(0)

parts = key.split(".")
if len(parts) != 3:
    fail("SUPABASE_ANON_KEY must be an anon JWT or publishable key")
try:
    padding = "=" * (-len(parts[1]) % 4)
    payload = json.loads(base64.urlsafe_b64decode(parts[1] + padding))
except (ValueError, json.JSONDecodeError):
    fail("SUPABASE_ANON_KEY is not a valid JWT")
if payload.get("role") != "anon":
    fail("SUPABASE_ANON_KEY JWT role must be anon")
