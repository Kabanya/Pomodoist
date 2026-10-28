#!/usr/bin/env python3
"""Real multi-connection checks against a disposable local Docker or loopback DB."""
import concurrent.futures
from contextlib import contextmanager
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
        connection = ["docker", "exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres"]
    else:
        if urlparse(database_url).hostname not in ("localhost", "127.0.0.1", "::1"):
            raise SystemExit("POMODOIST_TEST_DATABASE_URL must name a disposable loopback database")
        connection = [os.environ.get("PSQL", "psql"), database_url]
    user_id, session_id = str(uuid.uuid4()), str(uuid.uuid4())
    other_user, other_session, scope_id = (str(uuid.uuid4()) for _ in range(3))
    claims = json.dumps({"sub": user_id, "session_id": session_id, "role": "authenticated"})
    other_claims = json.dumps({"sub": other_user, "session_id": other_session, "role": "authenticated"})

    def sql(statement, authenticated=False):
        prefix = f"set role authenticated; set request.jwt.claims='{claims if authenticated is True else authenticated}';" if authenticated else ""
        try:
            return subprocess.run(connection + ["-qAtX", "-v", "ON_ERROR_STOP=1", "-c", prefix + statement], check=True, text=True, capture_output=True, timeout=60).stdout.strip()
        except (subprocess.SubprocessError, OSError):
            # CalledProcessError includes argv, which may contain the optional
            # local URL password. Never expose connection arguments on failure.
            raise SystemExit("Disposable local Focus database command failed") from None

    def command(value, authenticated=True):
        body = json.dumps(value).replace("'", "''")
        return json.loads(sql(f"select public.pomodoist_focus('{body}'::jsonb);", authenticated))

    def race(values):
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(values)) as pool:
            return list(pool.map(command, values))

    @contextmanager
    def held(statement):
        process = subprocess.Popen(connection + ["-qAtX", "-v", "ON_ERROR_STOP=1"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            process.stdin.write(f"begin; {statement}; select 'lock-held';\n")
            process.stdin.flush()
            while process.stdout.readline().strip() != "lock-held":
                if process.poll() is not None:
                    raise AssertionError("Could not hold the disposable test transaction")
            yield
        finally:
            process.communicate("rollback;\n", timeout=10)

    sql(f"insert into auth.users(id,email,aud,role,created_at,updated_at) values('{user_id}','{user_id}@focus.test','authenticated','authenticated',now(),now()); insert into auth.sessions(id,user_id,created_at,updated_at) values('{session_id}','{user_id}',now(),now());")
    sql(f"insert into auth.users(id,email,aud,role,created_at,updated_at) values('{other_user}','{other_user}@focus.test','authenticated','authenticated',now(),now()); insert into auth.sessions(id,user_id,created_at,updated_at) values('{other_session}','{other_user}',now(),now());")
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
        results = race([{"action": "pause", "requestId": f"old-{n}", "expectedRevision": 0, "deviceId": "bounded-cache"} for n in range(8)])
        assert all(r.get("code") == "revision_conflict" for r in results)
        assert sql(f"select count(*) from private.pomodoist_focus_requests where user_id='{user_id}' and command->>'deviceId'='bounded-cache';") == "5"
        results = race([{
            "action": "profileUpsert", "requestId": f"settings-{n}", "deviceId": f"desktop-{n}",
            "expectedSettingsRevision": 1,
            "payload": {"profile": {"id": "custom", "name": f"Profile {n}", "blockedCategories": [], "overrides": []}},
        } for n in range(2)])
        assert sorted(r.get("code", "ok") for r in results) == ["ok", "revision_conflict"]
        assert sql(f"select settings_revision from private.pomodoist_focus_accounts where user_id='{user_id}';") == "2"
        other_start = json.dumps({"action": "start", "deviceId": "other", "requestId": "other-start", "expectedRevision": 0, "payload": {"preset": preset}})
        sql(f"select public.pomodoist_focus('{other_start}');", other_claims)
        with held(f"set role authenticated; set request.jwt.claims='{claims}'; select public.pomodoist_focus('{{\"action\":\"read\",\"deviceId\":\"desktop-0\"}}')"):
            for value in [{"action": "read", "deviceId": "other"}, {"action": "registerDevice", "deviceId": "other", "requestId": "heartbeat", "payload": {"platform": "macos"}}]:
                response = json.loads(sql(f"set statement_timeout='500ms'; select public.pomodoist_focus('{json.dumps(value)}');", other_claims))
                assert response["session"]["interval"]["status"] == "running"
            sql(f"update private.pomodoist_focus_accounts set deadline=clock_timestamp()-interval '1 second' where user_id='{other_user}';")
            response = json.loads(sql("set statement_timeout='500ms'; select public.pomodoist_focus('{\"action\":\"read\",\"deviceId\":\"other\"}');", other_claims))
            assert response["session"]["interval"]["status"] == "ready", "another account's expiry must also proceed"
        with held("select pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0))"):
            try:
                sql("set statement_timeout='100ms'; select public.pomodoist_focus('{\"action\":\"read\",\"deviceId\":\"other\"}');", other_claims)
            except SystemExit:
                pass
            else:
                raise AssertionError("Focus must still respect exclusive file/account lifecycle work")
        sql(f"""insert into private.pomodoist_scopes(id,root_project_id,owner_id) values('{scope_id}','shared-project','{user_id}');
            insert into private.pomodoist_members(scope_id,user_id,role) values('{scope_id}','{user_id}','administrator'),('{scope_id}','{other_user}','member');
            select private.pomodoist_shared_put('{scope_id}','project','shared-project','{{"id":"shared-project","name":"Shared project"}}');
            select private.pomodoist_shared_put('{scope_id}','task','shared-task','{{"id":"shared-task","content":"Shared task","status":"open","projectId":"shared-project"}}');""")
        for identity in [True, other_claims]:
            current = command({"action": "read", "deviceId": "shared"}, identity)
            stopped = command({"action": "requestStop", "deviceId": "shared", "requestId": "stop", "expectedRevision": current["session"]["revision"]}, identity)
            started = command({"action": "start", "deviceId": "shared", "requestId": "shared-start", "expectedRevision": stopped["session"]["revision"], "payload": {"taskId": "shared-task", "preset": preset}}, identity)
            assert started["session"]["interval"]["status"] == "running"
        sql(f"""update private.pomodoist_focus_accounts set session=jsonb_set(session,'{{interval,startedAt}}',to_jsonb(t.stamp-interval '60 seconds')),deadline=t.stamp
            from (select clock_timestamp()-interval '1 second' stamp) t where user_id in ('{user_id}','{other_user}');""")
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(command, {"action": "read", "deviceId": "shared"}, identity) for identity in [True, other_claims]]
            assert all(f.result()["session"]["interval"]["status"] == "ready" for f in futures)
        assert json.loads(sql(f"select data from private.pomodoist_shared_entities where scope_id='{scope_id}' and entity_type='task' and entity_id='shared-task';"))["totalFocusSeconds"] == 120
        assert sql(f"select count(*) from private.pomodoist_shared_entities where scope_id='{scope_id}' and entity_type='focus_interval';") == "2"
        print("PASS: concurrent commands, bounded receipts, settings conflicts, independent account reads/heartbeats/expiry, lifecycle exclusion, concurrent shared-task credits")
    finally:
        sql(f"delete from private.pomodoist_scopes where id='{scope_id}'; delete from auth.users where id in ('{user_id}','{other_user}');")


if __name__ == "__main__":
    main()
