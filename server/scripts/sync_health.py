#!/usr/bin/env python3
"""Read-only sync health gate for the existing self-hosted upgrade workflow."""
import argparse
import datetime as dt
import json
from pathlib import Path
import re
import subprocess
import time

REQUIRED = {
    'task': ['id', 'userId', 'content', 'projectId', 'priority', 'status',
             'completedFocusIntervals', 'totalFocusSeconds', 'orderKey',
             'isCollapsed', 'isDeleted', 'createdAt', 'updatedAt'],
    'project': ['id', 'userId', 'name', 'viewStyle', 'isFavorite', 'isArchived',
                'isDeleted', 'orderKey', 'createdAt', 'updatedAt'],
}
VALIDATION_ERROR = re.compile(r'ERROR:\s+(?:Invalid (?:habit|check-in)|Incomplete (?:task|project) entity)')


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=30)
    if result.returncode:
        # Database/log output can contain user data. Never include it in CI logs.
        raise RuntimeError('Sync health source unavailable')
    return result.stdout


def snapshot(container, since, *, allow_new=False):
    now = dt.datetime.now(dt.timezone.utc)
    containers = run('docker', 'ps', '--all', '--format', '{{.Names}}').splitlines()
    if container not in containers and allow_new:
        return {'at': now.isoformat(), 'malformed': 0, 'errors_per_minute': 0, 'existing': False}
    schema = run('docker', 'exec', container, 'psql', '-X', '-qAt',
                 '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres',
                 '-c', "SELECT to_regclass('public.sync_entities')").strip()
    if not schema:
        if not allow_new:
            raise RuntimeError('Sync schema unavailable after deployment')
        return {'at': now.isoformat(), 'malformed': 0, 'errors_per_minute': 0, 'existing': False}
    predicates = []
    for entity, keys in REQUIRED.items():
        missing = ' OR '.join(f"data->'{key}' IS NULL OR data->'{key}' = 'null'::jsonb" for key in keys)
        predicates.append(f"(entity_type = '{entity}' AND ({missing}))")
    sql = ("BEGIN READ ONLY; SELECT count(*) FROM public.sync_entities "
           "WHERE app_id = 'pomodoist' AND deleted_at IS NULL "
           "AND coalesce(data->>'isDeleted', 'false') <> 'true' AND ("
           + ' OR '.join(predicates) + "); COMMIT;")
    count = int(run('docker', 'exec', container, 'psql', '-X', '-qAt',
                    '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres', '-c', sql).strip())
    logs = subprocess.run(['docker', 'logs', '--since', since.isoformat(), '--until', now.isoformat(), container],
                          text=True, capture_output=True, timeout=30)
    if logs.returncode:
        raise RuntimeError('Sync validation logs unavailable')
    errors = sum(bool(VALIDATION_ERROR.search(line)) for line in (logs.stdout + logs.stderr).splitlines())
    minutes = max((now - since).total_seconds(), 1) / 60
    return {'at': now.isoformat(), 'malformed': count, 'errors_per_minute': errors / minutes, 'existing': True}


def regressions(before, after):
    return [key for key in ('malformed', 'errors_per_minute') if after[key] > before[key]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['capture', 'check'])
    parser.add_argument('container')
    parser.add_argument('baseline', type=Path)
    args = parser.parse_args()
    now = dt.datetime.now(dt.timezone.utc)
    if args.mode == 'capture':
        before = snapshot(args.container, now - dt.timedelta(minutes=5), allow_new=True)
        args.baseline.write_text(json.dumps(before) + '\n')
        return
    before = json.loads(args.baseline.read_text())
    since = now
    # Observe a real post-upgrade window, rather than claiming health at startup.
    time.sleep(30)
    after = snapshot(args.container, since)
    failed = regressions(before, after)
    print(json.dumps({'before': before, 'after': after, 'regressions': failed, 'passed': not failed}))
    if failed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
