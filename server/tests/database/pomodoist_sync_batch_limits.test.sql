begin;
-- Exercise the deferred release migration without enabling it outside this test.
\ir ../../database/pending-migrations/20260913210628_pomodoist_core_client_sync_batch_limits.sql
select no_plan();
insert into auth.users(id,email,aud,role,created_at,updated_at)
values('ac000000-0000-4000-8000-000000000002','sync-limits@example.test','authenticated','authenticated',now(),now());
set local request.jwt.claim.sub='ac000000-0000-4000-8000-000000000002';
set local request.jwt.claims='{"sub":"ac000000-0000-4000-8000-000000000002","role":"authenticated"}';
create function pg_temp.ops(p_count integer) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('opId','size-'||i,'entityType','task','entityId','size-'||i))
  from generate_series(1,p_count) i;
$$;
select lives_ok($$select public.push_changes('pomodoist','size',pg_temp.ops(1000))$$,'1000 operations accepted');
select throws_ok($$select public.push_changes('pomodoist','size',pg_temp.ops(1001))$$,
  'PT413','Sync batch exceeds server limits','1001 operations rejected');
select lives_ok($$select private.push_changes_for_user(auth.uid(),'pomodoist','integration',pg_temp.ops(1001))$$,
  'trusted integrations retain larger atomic batches');

create function pg_temp.byte_batch(p_bytes integer) returns jsonb language plpgsql as $$
declare
  v_batch jsonb := '[{"opId":"utf8","entityType":"task","entityId":"utf8","payload":{"content":"Привет"}}]';
begin
  return jsonb_set(v_batch,'{0,payload,content}',to_jsonb('Привет' || repeat('a',p_bytes-octet_length(v_batch::text))));
end;
$$;
select is(octet_length(pg_temp.byte_batch(8388608)::text),8388608,'byte boundary includes multibyte UTF-8 content');
select lives_ok($$select public.push_changes('pomodoist','size',pg_temp.byte_batch(8388608))$$,'exactly 8 MiB accepted');
select throws_ok($$select public.push_changes('pomodoist','size',pg_temp.byte_batch(8388609))$$,
  'PT413','Sync batch exceeds server limits','one byte above 8 MiB rejected');
select lives_ok($$select public.push_changes('pomodoist','size',null)$$,'legacy empty request remains valid');
select throws_ok($$select public.push_changes('pomodoist','size','{}')$$,
  '22023','Invalid sync batch: expected an array','invalid shape has a validation error, not 413');
select * from finish();
rollback;
