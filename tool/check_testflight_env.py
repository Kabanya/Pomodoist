#!/usr/bin/env python3
import base64
import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"TestFlight config error: {message}", file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 2:
    fail("expected a path to the production env file")

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

expected = {
    "POMODOIST_ENVIRONMENT": "production",
    "WEB_APP_URL": "https://app.pomodoist.com",
    "SUPABASE_URL": "https://ewauihswbwduvklrozke.supabase.co",
}
for name, value in expected.items():
    if values.get(name) != value:
        fail(f"{name} must be {value}")

for name in ("SUPABASE_ANON_KEY", "GOOGLE_WEB_CLIENT_ID", "TURNSTILE_SITE_KEY"):
    if not values.get(name):
        fail(f"{name} must not be empty")
if "SENTRY_DSN" not in values:
    fail("SENTRY_DSN must be present (it may be empty)")

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
