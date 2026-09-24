#!/usr/bin/env python3
"""Automatic fresh-install/legacy-upgrade checks in a disposable local container."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

SERVER = Path(__file__).resolve().parents[2]
SOURCE = sys.argv[1] if len(sys.argv) > 1 else 'pomodoist-selfhost-db'
assert SOURCE.startswith('pomodoist-selfhost-'), 'Local self-hosted source only'
TARGET = f'pomodoist-selfhost-baseline-check-{os.getpid()}'
PASSWORD = 'baseline-local-test-only'


def run(*args, data=None, check=True):
    result = subprocess.run(args, input=data, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f'{args[0]} failed: {result.stderr[-4000:]}\n{result.stdout[-1000:]}')
    return result


def sql(text, check=True, user='postgres'):
    return run('docker', 'exec', '-i', TARGET, 'psql', '-X', '-qAt', '-U', user,
               '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', data=text, check=check)


def migrate(check=True):
    return run('docker', 'exec', '--env', 'PGHOST=/var/run/postgresql', '--env', f'PGPASSWORD={PASSWORD}', TARGET,
               'sh', '/opt/pomodoist/migrate.sh', check=check)


def fingerprint():
    return sql((SERVER / 'database/application-fingerprint.sql').read_text()).stdout.strip()


try:
    image = run('docker', 'inspect', '--format', '{{.Config.Image}}', SOURCE).stdout.strip()
    managed = run('docker', 'exec', SOURCE, 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres',
                  '--schema-only', '--schema', 'auth', '--schema', 'realtime', '--schema', 'storage').stdout
    # Application bindings are restored by the baseline, after its dependencies.
    sections = re.split(r'(?=--\n-- Name:)', managed)
    managed = ''.join(s for s in sections if not (
        re.search(r'Type: (TRIGGER|POLICY);', s.split('\n\n')[0]) and
        ('pomodoist' in s or 'on_auth_user_created' in s or 'public.apps' in s)))
    mounts = []
    for source, dest in [('scripts/migrate.sh', 'migrate.sh'),
                         ('supabase/migrations', 'migrations'), ('supabase/legacy', 'legacy'),
                         ('database/application-fingerprint.sql', 'application-fingerprint.sql'),
                         ('database/enable-selfhost.sql', 'enable-selfhost.sql')]:
        mounts += ['--volume', f'{SERVER / source}:/opt/pomodoist/{dest}:ro']
    run('docker', 'run', '--detach', '--name', TARGET, '--add-host', 'db:127.0.0.1', '--env', f'POSTGRES_PASSWORD={PASSWORD}',
        '--env', 'JWT_SECRET=baseline-local-test-only-at-least-32-characters',
        '--env', 'POSTGRES_HOST=/var/run/postgresql', '--env', 'PGPORT=5432',
        *mounts, image, 'postgres', '-c', 'config_file=/etc/postgresql/postgresql.conf',
        '-c', 'cron.launch_active_jobs=off')
    for _ in range(120):
        if ('init process complete' in run('docker', 'logs', TARGET, check=False).stdout and
                run('docker', 'exec', TARGET, 'pg_isready', '-U', 'postgres', check=False).returncode == 0):
            break
        time.sleep(0.5)
    else:
        raise RuntimeError('Disposable database did not start')
    sql('''drop schema auth,storage,realtime cascade;
      do $$ begin if not exists(select from pg_roles where rolname='supabase_realtime_admin') then
        create role supabase_realtime_admin nologin; end if; end $$;
      create extension if not exists pgcrypto with schema extensions;
      create extension if not exists "uuid-ossp" with schema extensions;
      create extension if not exists pg_cron;
      create extension if not exists pg_net with schema extensions;''', user='supabase_admin')
    sql(managed, user='supabase_admin')
    if len(sys.argv) > 2:
        baseline_dir = Path(sys.argv[2]).resolve()
        sql((baseline_dir / 'production-v0.sql').read_text(), user='supabase_admin')
        expected = json.loads((baseline_dir / 'production-v0.json').read_text())['catalogFingerprint']
        assert fingerprint() == expected, 'Production catalog differs after restoration'
        assert sql("select to_regprocedure('public.pomodoist_collaboration(jsonb)') is null;").stdout.strip() == 't'
        sql('begin;\n' + (SERVER / 'supabase/migrations/20260922162925_pomodoist_core_api_v1.sql').read_text() + '\ncommit;')
        sql('create extension if not exists pgtap with schema extensions;', user='supabase_admin')
        result = run('docker', 'run', '--rm', '--network', f'container:{TARGET}', '--env', f'PGPASSWORD={PASSWORD}',
                     '--volume', f'{SERVER / "tests/database"}:/tests:ro',
                     'public.ecr.aws/supabase/pg_prove:3.36', 'pg_prove', '-h', '127.0.0.1', '-U', 'postgres',
                     '-d', 'postgres', '/tests/pomodoist_api_v1.test.sql')
        assert sql((baseline_dir / 'production-v0.sql').read_text(), check=False, user='supabase_admin').returncode != 0
        assert fingerprint() == expected, 'Rejected baseline replay changed the catalog'
        print(result.stdout, flush=True)
        print('Production snapshot, v1 parity and baseline replay rejection passed.', flush=True)
        sys.exit(0)
    # Core-only images omit Storage tables; exercise its optional bucket seed too.
    sql('''create table if not exists storage.buckets (
      id text primary key, name text not null, public boolean not null,
      file_size_limit bigint);
      grant all on storage.buckets to postgres;''', user='supabase_admin')
    sql('''create schema pomodoist_meta;
      create table pomodoist_meta.schema_migrations(version text primary key,checksum text not null,
        applied_at timestamptz not null default now());''')
    for migration in sorted((SERVER / 'supabase/legacy').glob('*.sql')):
        sql(migration.read_text())
        digest = hashlib.sha256(migration.read_bytes()).hexdigest()
        sql(f"insert into pomodoist_meta.schema_migrations values ('{migration.stem}','{digest}',now());")
    diagnostic = SERVER.parent / '.superpowers/api-v1'
    diagnostic.mkdir(parents=True, exist_ok=True)
    (diagnostic / 'clean-schema.sql').write_text(run('docker', 'exec', TARGET, 'pg_dump', '-U', 'postgres', '-d', 'postgres', '--schema-only', '--schema', 'public', '--schema', 'private').stdout)
    (diagnostic / 'clean-seed.sql').write_text(run('docker', 'exec', TARGET, 'pg_dump', '-U', 'postgres', '-d', 'postgres', '--data-only', '--column-inserts', '--table', 'public.apps', '--table', 'public.products', '--table', 'public.quota_definitions', '--table', 'private.pomodoist_instance_settings', '--table', 'storage.buckets').stdout)
    (diagnostic / 'clean-schema.md5').write_text(fingerprint() + '\n')
    assert fingerprint() == (SERVER / 'supabase/legacy/schema.md5').read_text().strip(), 'Legacy schema drift'
    sql('''insert into auth.users(id,email,aud,role,created_at,updated_at)
      values('b2000000-0000-4000-8000-000000000001','baseline@example.test','authenticated','authenticated',now(),now());
      set request.jwt.claims='{"sub":"b2000000-0000-4000-8000-000000000001","role":"authenticated"}';
      select public.push_changes('pomodoist','baseline-test','[{"opId":"kept-op","entityType":"task","entityId":"kept-task","payload":{"title":"Kept"}}]');''')
    preserved_query = "select md5(row_to_json(s)::text) from public.sync_entities s where entity_id='kept-task';"
    before = sql(preserved_query).stdout
    sql('create table public.unexpected_baseline_drift(id integer);')
    assert migrate(check=False).returncode != 0, 'Unexpected schema drift was adopted'
    sql('drop table public.unexpected_baseline_drift;')
    sql('''create function pomodoist_meta.reject_api_record() returns trigger language plpgsql as $$
      begin if new.version like '%api_v1' then raise exception 'Simulated ledger failure'; end if;
      return new; end $$;
      create trigger reject_api_record before insert on pomodoist_meta.schema_migrations
      for each row execute function pomodoist_meta.reject_api_record();''')
    assert migrate(check=False).returncode != 0, 'Simulated ledger failure was ignored'
    assert sql("select to_regnamespace('api_v1') is null;").stdout.strip() == 't', 'Migration committed without its ledger record'
    sql('drop trigger reject_api_record on pomodoist_meta.schema_migrations; drop function pomodoist_meta.reject_api_record();')
    migrate()
    assert sql(preserved_query).stdout == before, 'Upgrade changed user data'
    # Forward migrations may intentionally change the application schema.
    # Compare the fresh install below with this upgraded schema, not the frozen legacy baseline.
    upgraded_fingerprint = fingerprint()
    migration_count = len(list((SERVER / 'supabase/migrations').glob('*.sql')))
    assert sql('select count(*) from pomodoist_meta.schema_migrations;').stdout.strip() == str(migration_count)
    migrate()  # Rerun must not replay the baseline.
    sql("update pomodoist_meta.schema_migrations set checksum='bad' where version like '%initial';")
    assert migrate(check=False).returncode != 0, 'Changed applied migration was accepted'
    assert sql(preserved_query).stdout == before
    print('Legacy upgrade, retry and checksum rejection passed.', flush=True)
    sql("drop schema api_v1,private,public,pomodoist_meta cascade; create schema public authorization pg_database_owner; grant usage on schema public to public; delete from auth.users; do $$ begin if to_regclass('storage.buckets') is not null then delete from storage.buckets; end if; end $$;", user='supabase_admin')
    migrate()
    assert fingerprint() == upgraded_fingerprint, 'Fresh install differs from upgraded schema'
    assert sql("select count(*) from storage.buckets where id='pomodoist-shared' and not public and file_size_limit=20000000;").stdout.strip() == '1', 'Fresh baseline omitted the private Storage bucket'
    # Exercise the data-only restore strategy used by backup.sh/restore.sh.
    sql("""insert into auth.users(id,email,aud,role,created_at,updated_at)
      values('b2000000-0000-4000-8000-000000000001','backup@example.test','authenticated','authenticated',now(),now());
      set request.jwt.claims='{"sub":"b2000000-0000-4000-8000-000000000001","role":"authenticated"}';
      select public.push_changes('pomodoist','baseline-test','[{"opId":"kept-op","entityType":"task","entityId":"kept-task","payload":{"title":"Kept"}}]');""")
    before = sql(preserved_query).stdout
    backup = run('docker', 'exec', TARGET, 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres',
                 '--data-only', '--disable-triggers', '--schema=auth', '--schema=public',
                 '--schema=private', '--schema=pomodoist_meta', '--schema=vault').stdout
    sql("update public.sync_entities set data='{}' where entity_id='kept-task';")
    assert sql(preserved_query).stdout != before
    sql("""begin; do $$ declare tables text; begin
      select string_agg(format('%I.%I',n.nspname,c.relname),',') into tables
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where c.relkind in ('r','p') and not c.relispartition and
        (n.nspname in ('auth','public','private','pomodoist_meta') or
          (n.nspname='vault' and c.relname='secrets'));
      execute 'truncate table '||tables||' restart identity cascade';
      end $$;\n""" + backup + '\ncommit;', user='supabase_admin')
    assert sql(preserved_query).stdout == before, 'Backup did not restore user data'
    migrate()  # Restored ledger still agrees with the checked-in release.
    print('Data-only backup/restore and restored ledger passed.', flush=True)
    sql('create extension if not exists pgtap with schema extensions;', user='supabase_admin')
    result = run('docker', 'run', '--rm', '--network', f'container:{TARGET}', '--env', f'PGPASSWORD={PASSWORD}',
                 '--volume', f'{SERVER / "tests/database"}:/tests:ro',
                 '--volume', f'{SERVER / "database"}:/database:ro',
                 'public.ecr.aws/supabase/pg_prove:3.36', 'pg_prove', '-h', '127.0.0.1',
                 '-U', 'postgres', '-d', 'postgres', '--ext', '.sql', '-r', '/tests')
    print(result.stdout[-2000:], flush=True)
    print('Fresh baseline and all database contracts passed.', flush=True)
finally:
    run('docker', 'rm', '--force', '--volumes', TARGET, check=False)
