#!/usr/bin/env python3
"""Real multi-connection checks against a disposable local Docker or loopback DB."""
import concurrent.futures
import json
import os
import re
import subprocess
from urllib.parse import urlparse
import uuid


def main():
    database_url = os.environ.get("POMODOIST_TEST_DATABASE_URL", "")
    container = os.environ.get("POMODOIST_TEST_DB", "")
    if container:
        if database_url or not re.fullmatch(r"pomodoist-selfhost-[a-zA-Z0-9_-]+", container):
            raise SystemExit("POMODOIST_TEST_DB must name one explicit disposable local pomodoist-selfhost-* container")
        # Reuse the CI-created database and its internal PGPASSWORD; no secret
        # is read from .env or placed in the process arguments or workflow log.
        connection = ["docker", "exec", container, "psql", "-U", "postgres", "-d", "postgres"]
    else:
        if urlparse(database_url).hostname not in ("localhost", "127.0.0.1", "::1"):
            raise SystemExit("POMODOIST_TEST_DATABASE_URL must name a disposable loopback database")
        connection = [os.environ.get("PSQL", "psql"), database_url]
    user_id, session_id = str(uuid.uuid4()), str(uuid.uuid4())
    claims = json.dumps({"sub": user_id, "session_id": session_id, "role": "authenticated"})

    def sql(statement, authenticated=False):
        prefix = f"set role authenticated; set request.jwt.claims='{claims}';" if authenticated else ""
        try:
            return subprocess.run(connection + ["-qAtX", "-v", "ON_ERROR_STOP=1", "-c", prefix + statement], check=True, text=True, capture_output=True, timeout=60).stdout.strip()
        except (subprocess.SubprocessError, OSError):
            # CalledProcessError includes argv, which may contain the optional
            # local URL password. Never expose connection arguments on failure.
            raise SystemExit("Disposable local Focus database command failed") from None

    def command(value):
        body = json.dumps(value).replace("'", "''")
        return json.loads(sql(f"select public.pomodoist_focus('{body}'::jsonb);", True))

    def race(values):
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(values)) as pool:
            return list(pool.map(command, values))

    sql(f"insert into auth.users(id,email,aud,role,created_at,updated_at) values('{user_id}','{user_id}@focus.test','authenticated','authenticated',now(),now()); insert into auth.sessions(id,user_id,created_at,updated_at) values('{session_id}','{user_id}',now(),now());")
    try:
        preset = {"id": "classic", "workSeconds": 60, "shortBreakSeconds": 60, "longBreakSeconds": 120, "intervalsBeforeLongBreak": 2, "strictMode": False, "allowPause": True}
        starts = [{"action": "start", "requestId": f"start-{n}", "expectedRevision": 0, "deviceId": f"desktop-{n}", "payload": {"preset": preset}} for n in range(2)]
        results = race(starts)
        assert sorted(r.get("code", "ok") for r in results) == ["ok", "revision_conflict"], results
        assert len({r["session"]["id"] for r in results}) == 1
        pause = {"action": "pause", "requestId": "same-pause", "expectedRevision": 1, "deviceId": "desktop-0"}
        results = race([pause, pause])
        assert results[0] == results[1], "simultaneous replay must return one saved response"
        assert results[0]["session"]["revision"] == 2
        results = race([{"action": "resume", "requestId": f"resume-{n}", "expectedRevision": 2, "deviceId": f"desktop-{n}"} for n in range(2)])
        assert sorted(r.get("code", "ok") for r in results) == ["ok", "revision_conflict"]
        sql(f"update private.pomodoist_focus_accounts set deadline=clock_timestamp()-interval '1 minute' where user_id='{user_id}';")
        results = race([{"action": "read", "deviceId": f"desktop-{n}"} for n in range(8)])
        assert {r["session"]["revision"] for r in results} == {4}
        assert all(r["session"]["interval"]["status"] == "ready" for r in results)
        assert sql(f"select count(*) from public.sync_entities where user_id='{user_id}' and entity_type='focus_interval' and data->>'status'='completed';") == "1"
        print("PASS: concurrent starts, duplicate replay, stale revision race, eight concurrent expiry reads")
    finally:
        sql(f"delete from auth.users where id='{user_id}';")


if __name__ == "__main__":
    main()
