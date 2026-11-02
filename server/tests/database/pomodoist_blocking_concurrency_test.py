#!/usr/bin/env python3
"""Assert that two devices cannot commit a dependency cycle on a disposable DB."""
import concurrent.futures
import json
import os
import re
import subprocess
import uuid
from urllib.parse import urlparse


def main():
    url = os.environ.get("POMODOIST_TEST_DATABASE_URL", "")
    container = os.environ.get("POMODOIST_TEST_DB", "")
    if container:
        if url or not re.fullmatch(r"pomodoist-selfhost-[a-zA-Z0-9_-]+", container):
            raise SystemExit("Expected an explicit disposable pomodoist-selfhost-* container")
        connection = ["docker", "exec", "-i", container, "psql", "-U", "postgres", "-d", "postgres"]
    else:
        if urlparse(url).hostname not in ("localhost", "127.0.0.1", "::1"):
            raise SystemExit("Expected a disposable loopback database URL")
        connection = [os.environ.get("PSQL", "psql"), url]
    actor = str(uuid.uuid4())

    def sql(statement, check=True):
        result = subprocess.run(connection + ["-XqAt", "-v", "ON_ERROR_STOP=1"], input=statement,
                                text=True, capture_output=True, timeout=20)
        if check and result.returncode:
            raise AssertionError("Disposable blocking database assertion failed: " + result.stderr)
        return result

    sql(f"insert into auth.users(id,email) values('{actor}','{actor}@blocking.test');")
    try:
        for trial in range(5):
            ids = [f"blocking-{actor}-{trial}-{n}" for n in range(2)]
            for task in ids:
                data = json.dumps({"id": task, "content": task, "projectId": "inbox", "status": "open", "prerequisiteIdsJson": "[]"})
                sql(f"insert into public.sync_entities(user_id,app_id,entity_type,entity_id,data,server_revision,client_updated_at) values('{actor}','pomodoist','task','{task}','{data}',1,now());")

            def update(index):
                needs = json.dumps([ids[1-index]])
                return sql(f"begin; set local lock_timeout='5s'; update public.sync_entities set data=jsonb_set(data,'{{prerequisiteIdsJson}}',to_jsonb('{needs}'::text)) where user_id='{actor}' and app_id='pomodoist' and entity_type='task' and entity_id='{ids[index]}'; select pg_sleep(0.05); commit;", check=False)

            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(update, range(2)))
            assert sum(r.returncode == 0 for r in results) == 1, [r.stderr for r in results]
            assert any("cycles or ancestor links" in r.stderr for r in results), [r.stderr for r in results]
            sql(f"select private.pomodoist_blocking_validate_graph(private.pomodoist_blocking_graph('{actor}')); ")
        print("Passed: concurrent dependency edits serialize and reject cycles (5 races)")
    finally:
        sql(f"delete from public.sync_entities where user_id='{actor}'; delete from auth.users where id='{actor}';")


if __name__ == "__main__":
    main()
