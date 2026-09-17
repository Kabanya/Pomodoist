begin;
\ir hosted-mode.inc
select no_plan();

insert into auth.users (id,email,aud,role,created_at,updated_at,email_confirmed_at) values
  ('c1000000-0000-4000-8000-000000000001','collab-owner@example.test','authenticated','authenticated',now(),now(),now()),
  ('c1000000-0000-4000-8000-000000000002','collab-member@example.test','authenticated','authenticated',now(),now(),now()),
  ('c1000000-0000-4000-8000-000000000003','collab-stranger@example.test','authenticated','authenticated',now(),now(),now()),
  ('c1000000-0000-4000-8000-000000000004','collab-observer@example.test','authenticated','authenticated',now(),now(),now()),
  ('c1000000-0000-4000-8000-000000000005','collab-unconfirmed@example.test','authenticated','authenticated',now(),now(),null);

insert into auth.sessions (id,user_id,created_at,updated_at,not_after) values
  ('d1000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
  ('d1000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 hour'),
  ('d1000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000003',now(),now(),now()+interval '1 hour'),
  ('d1000000-0000-4000-8000-000000000004','c1000000-0000-4000-8000-000000000004',now(),now(),now()+interval '1 hour'),
  ('d1000000-0000-4000-8000-000000000005','c1000000-0000-4000-8000-000000000005',now(),now(),now()+interval '1 hour');

create function pg_temp.act_as(p_user uuid,p_session uuid) returns void language sql as $$
select set_config('request.jwt.claims',
  jsonb_build_object('sub',p_user,'session_id',p_session,'role','authenticated')::text, true);
$$;
create function pg_temp.collab(p_request jsonb) returns jsonb language sql as $$
select private.pomodoist_collaboration(p_request);
$$;
create function pg_temp.call_op(p_scope uuid,p_op jsonb) returns jsonb language sql as $$
select pg_temp.collab(jsonb_build_object('action','push','scopeId',p_scope,'operations',jsonb_build_array(p_op)));
$$;
create function pg_temp.shared_task_op(p_id text,p_content text) returns jsonb language sql as $$
select jsonb_build_object('opId','op-'||p_id,'entityType','task','entityId',p_id,'operation','upsert',
  'payload',jsonb_build_object('id',p_id,'content',p_content,'projectId','project-a','status','open'),
  'baseRevision',0,'clientUpdatedAt','2026-09-14T12:00:00Z');
$$;

select ok(not has_schema_privilege('anon','private','usage')
  and not has_function_privilege('anon','private.pomodoist_collaboration(jsonb)','execute')
  and not has_function_privilege('anon','public.pomodoist_collaboration(jsonb)','execute'),
  'anon cannot reach collaboration entrypoints');
select ok(has_function_privilege('authenticated','private.pomodoist_collaboration(jsonb)','execute')
  and has_function_privilege('service_role','public.pomodoist_collaboration(jsonb)','execute'),
  'authenticated and service roles can execute collaboration');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');

select public.push_changes('pomodoist','collab-device',jsonb_build_array(
  jsonb_build_object('opId','seed-project','entityType','project','entityId','project-a','operation','upsert',
    'payload',jsonb_build_object('id','project-a','userId','local-user','name','Project A','orderKey','0'),
    'clientUpdatedAt','2026-09-14T10:00:00Z'),
  jsonb_build_object('opId','seed-task','entityType','task','entityId','task-a','operation','upsert',
    'payload',jsonb_build_object('id','task-a','userId','local-user','content','Seed task','projectId','project-a',
      'status','open','priority',2,'estimatedFocusIntervals',3),
    'clientUpdatedAt','2026-09-14T10:00:01Z')));

create temporary table owner_revision as
  select coalesce(max(server_revision),0) as revision from public.sync_entities
  where user_id='c1000000-0000-4000-8000-000000000001'::uuid;

select is(
  (select pg_temp.collab(jsonb_build_object('action','state'))->>'personalRevision'),
  (select revision::text from owner_revision),
  'state exposes the personal revision a client shares against');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');

select throws_ok($$select pg_temp.collab(jsonb_build_object('action','share','rootProjectId','inbox','expectedRevision',0))$$,
  '22023','Inbox cannot be shared','inbox cannot be shared');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','share','rootProjectId','project-a','expectedRevision',999999)::text),
  '22023','Complete personal sync before sharing','stale revision rejects share');

create temporary table shared_scope as select pg_temp.collab(
  jsonb_build_object('action','share','rootProjectId','project-a','expectedRevision',(select revision from owner_revision))) as value;
select is((select value->'scope'->>'role' from shared_scope),'administrator','owner becomes administrator of the new scope');
select is((select value->'scope'->>'rootProjectId' from shared_scope),'project-a','scope exposes its shared root');
create temporary table scope_id as
  select (select value->'scope'->>'id' from shared_scope)::uuid as id;

reset role;
select ok((select deleted_at is not null from public.sync_entities
    where user_id='c1000000-0000-4000-8000-000000000001' and entity_type='project' and entity_id='project-a'),
  'personal project tombstoned after sharing');
select is((select count(*) from private.pomodoist_transferred_entities
    where user_id='c1000000-0000-4000-8000-000000000001' and entity_id in ('project-a','task-a')),2::bigint,
  'transferred personal entities recorded');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select throws_ok($$select public.push_changes('pomodoist','collab-device',jsonb_build_array(
  jsonb_build_object('opId','guard-task','entityType','task','entityId','task-late','operation','upsert',
    'payload',jsonb_build_object('id','task-late','userId','local-user','content','late','projectId','project-a'),
    'clientUpdatedAt','2026-09-14T10:05:00Z')))$$,
  '42501','Personal writes cannot target shared projects','personal sync cannot create content in a shared project');
select lives_ok($$select pg_temp.collab(jsonb_build_object('action','state'))$$,
  'owner state stays readable after sharing');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000003');
select is(jsonb_array_length((select pg_temp.collab(jsonb_build_object('action','state'))->'scopes')),0,
  'strangers see no shared scopes');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','pull','scopeId',(select id from scope_id))::text),
  '42501','Shared scope is inaccessible','strangers cannot pull a shared scope');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','invite','scopeId',(select id from scope_id),'email','collab-member@example.test')),
  '42501','Shared scope is inaccessible','strangers cannot invite into a shared scope');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','invite','scopeId',(select id from scope_id),'email','collab-member@example.test','role','administrator')::text),
  '22023','Invitation role must be member or observer','administrator invitations are rejected');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','invite','scopeId',(select id from scope_id),'email','not-an-email','role','member')::text),
  '22023','Invalid invitation email','malformed invitation email rejected');
create temporary table observer_invite as select pg_temp.collab(format(
  '{"action":"invite","scopeId":%s,"email":"collab-observer@example.test","role":"observer"}',
  to_json((select id from scope_id))::text)::jsonb) as value;
select is((select value->>'role' from observer_invite),'observer','invitation keeps the requested role');
create temporary table member_invite as select pg_temp.collab(format(
  '{"action":"invite","scopeId":%s,"email":"collab-member@example.test","role":"member"}',
  to_json((select id from scope_id))::text)::jsonb) as value;

select pg_temp.act_as('c1000000-0000-4000-8000-000000000005','d1000000-0000-4000-8000-000000000005');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','accept','token',(select value->>'token' from observer_invite))::text),
  '42501','Invitation is unavailable for this account','unconfirmed emails cannot accept invitations');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000004');
select throws_ok($$select pg_temp.collab(jsonb_build_object('action','accept','token',repeat('f',64)))$$,
  '42501','Shared scope is inaccessible','unknown invitation tokens are rejected');
create temporary table observer_accept as select pg_temp.collab(
  jsonb_build_object('action','accept','token',(select value->>'token' from observer_invite))) as value;
select is((select value->'scope'->>'role' from observer_accept),'observer','invitation grants the invited role');
select lives_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','accept','token',(select value->>'token' from observer_invite))::text),
  'accepted invitations remain replayable for the same account only');

select is(jsonb_array_length((select (pg_temp.call_op((select id from scope_id),pg_temp.shared_task_op('task-from-observer','Observer task')))->'rejected')),1,
  'observer mutations are rejected');
select is((select (pg_temp.call_op((select id from scope_id),pg_temp.shared_task_op('task-from-observer','Observer task')))->'rejected'->0->>'code'),'42501',
  'observer mutations report a privilege failure');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','invite','scopeId',(select id from scope_id),'email','collab-member@example.test')::text),
  '42501','Administrator role required','observers cannot invite');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','role','scopeId',(select id from scope_id),'userId','c1000000-0000-4000-8000-000000000004','role','owner')::text),
  '22023','Invalid role','unknown roles are rejected');
select is((pg_temp.collab(format('{"action":"role","scopeId":%s,"userId":"c1000000-0000-4000-8000-000000000004","role":"member"}',
  to_json((select id from scope_id))::text)::jsonb))->>'ok','true','owners can promote members');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000004');
create temporary table member_push as select pg_temp.call_op((select id from scope_id),pg_temp.shared_task_op('task-from-member','Member task')) as value;
select is(jsonb_array_length((select value->'applied' from member_push)),1,'members can push shared mutations');
create temporary table comment_push as select pg_temp.call_op((select id from scope_id),jsonb_build_object(
  'opId','op-comment','entityType','comment','entityId','comment-from-member','operation','upsert',
  'payload',jsonb_build_object('schemaVersion',1,'id','comment-from-member','taskId','task-from-member',
    'body','Member comment','mentions',jsonb_build_array()),
  'baseRevision',0,'clientUpdatedAt','2026-09-14T12:00:02Z')) as value;
select is(jsonb_array_length((select value->'applied' from comment_push)),1,
  'comments accept the schemaVersion envelope every sync client sends');
select is((select value->'applied'->0->'data'->>'taskId' from comment_push),'task-from-member',
  'an applied comment keeps the task it answers');
create temporary table member_pull as select pg_temp.collab(
  jsonb_build_object('action','pull','scopeId',(select id from scope_id))) as value;
select ok(jsonb_array_length((select value->'changes' from member_pull))>=3,'members pull shared entities');
select ok(((select value->>'nextCursor' from member_pull)::bigint)>0,'pull returns a revision cursor');
select is(jsonb_array_length((pg_temp.collab(format('{"action":"pull","scopeId":%s,"sinceRevision":999999}',
  to_json((select id from scope_id))::text)::jsonb))->'changes'),0,'pull ahead of the cursor returns no changes');
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select ok(exists(select 1 from jsonb_array_elements((pg_temp.collab(jsonb_build_object('action','pull',
  'scopeId',(select id from scope_id)))->'changes')) c where c->>'entityType'='comment'
  and c->'data'->>'createdBy'='c1000000-0000-4000-8000-000000000004' and c->'data'->>'taskId'='task-from-member'
  and c->'data'->>'body'='Member comment'),'another member receives the comment with its task in a pull delta');
select pg_temp.act_as('c1000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000004');
create temporary table member_export as select pg_temp.collab(
  jsonb_build_object('action','export','scopeId',(select id from scope_id))) as value;
select ok((select value ? 'changes' and value ? 'members' from member_export),'export returns scope contents');

select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','publicLink','scopeId',(select id from scope_id),'enabled',true)::text),
  '42501','Administrator role required','members cannot enable public links');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
create temporary table public_link as select pg_temp.collab(
  jsonb_build_object('action','publicLink','scopeId',(select id from scope_id),'enabled',true)) as value;
select is(length((select value->>'token' from public_link)),64,'public links use 64 character tokens');
select is((pg_temp.collab(jsonb_build_object('action','state'))->'scopes'->0->>'publicToken'),
  (select value->>'token' from public_link),'administrators see the current public link token');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000004');
select is((pg_temp.collab(jsonb_build_object('action','state'))->'scopes'->0->>'publicToken'),null,
  'members cannot resolve the public link token');
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');

reset role;
select throws_ok(format('select private.pomodoist_collaboration(%L::jsonb)',
  jsonb_build_object('action','publicRead','token',repeat('f',64))::text),
  '42501','Public link is unavailable','unknown public tokens are rejected');
create temporary table public_read as select private.pomodoist_collaboration(
  jsonb_build_object('action','publicRead','token',(select value->>'token' from public_link))) as value;
select is((select value->>'scopeId' from public_read),(select id::text from scope_id),'public reads expose the scope id');
select ok(not exists(select 1 from jsonb_array_elements((select value->'entities' from public_read)) e
    where e->'data' ? 'userId'),'public reads redact internal author ids');
select ok(not exists(select 1 from jsonb_array_elements((select value->'entities' from public_read)) e
    where e->'data' ? 'estimatedFocusIntervals'),'public reads redact private task fields');
select ok(exists(select 1 from jsonb_array_elements((select value->'entities' from public_read)) e
    where e->'data' ? 'creatorName'),'public reads keep display names');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select is((pg_temp.collab(jsonb_build_object('action','publicLink','scopeId',(select id from scope_id),'enabled',false)))->>'token',null,
  'disabling a public link clears the token');
select throws_ok(format('select private.pomodoist_collaboration(%L::jsonb)',
  jsonb_build_object('action','publicRead','token',(select value->>'token' from public_link))::text),
  '42501','Public link is unavailable','disabled public links stop resolving');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000002');
create temporary table member_accept as select pg_temp.collab(
  jsonb_build_object('action','accept','token',(select value->>'token' from member_invite))) as value;
select is((select value->'scope'->>'role' from member_accept),'member','second members join with the invited role');
select is((pg_temp.collab(format('{"action":"leave","scopeId":%s}',to_json((select id from scope_id))::text)::jsonb))->>'ok','true',
  'members can leave a shared scope');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','pull','scopeId',(select id from scope_id))::text),
  '42501','Shared scope is inaccessible','former members lose access immediately');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','remove','scopeId',(select id from scope_id),'userId','c1000000-0000-4000-8000-000000000001')::text),
  '42501','Owner must transfer ownership or delete the shared root','owners cannot be removed');
select is((pg_temp.collab(format('{"action":"role","scopeId":%s,"userId":"c1000000-0000-4000-8000-000000000004","role":"administrator"}',
  to_json((select id from scope_id))::text)::jsonb))->>'ok','true','owners can promote administrators');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000004');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','transfer','scopeId',(select id from scope_id),'userId','c1000000-0000-4000-8000-000000000004')::text),
  '42501','Only the owner may transfer ownership','administrators cannot seize ownership');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','delete','scopeId',(select id from scope_id))::text),
  '42501','Only the owner may delete the shared root','administrators cannot delete the root');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select is((pg_temp.collab(format('{"action":"transfer","scopeId":%s,"userId":"c1000000-0000-4000-8000-000000000004"}',
  to_json((select id from scope_id))::text)::jsonb))->>'ok','true','owners can transfer ownership');

reset role;
select is((select owner_id from private.pomodoist_scopes where id=(select id from scope_id)),
  'c1000000-0000-4000-8000-000000000004'::uuid,'ownership is persisted on the scope');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','delete','scopeId',(select id from scope_id))::text),
  '42501','Only the owner may delete the shared root','former owners cannot delete the shared root');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000004');
select is((pg_temp.collab(format('{"action":"delete","scopeId":%s}',to_json((select id from scope_id))::text)::jsonb))->>'ok','true',
  'owners can delete the shared root');

reset role;
select ok(not exists(select 1 from private.pomodoist_scopes where id=(select id from scope_id)),'deleted scopes are gone');
select ok(not exists(select 1 from private.pomodoist_shared_entities where scope_id=(select id from scope_id)),'shared entities cascade with the scope');
select throws_ok(format('select private.pomodoist_collaboration(%L::jsonb)',
  jsonb_build_object('action','publicRead','token',(select value->>'token' from public_link))::text),
  '42501','Public link is unavailable','deleted scopes drop their public links');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000099');
select throws_ok($$select pg_temp.collab(jsonb_build_object('action','state'))$$,
  '42501','An active authenticated session is required','revoked sessions cannot use collaboration');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
create temporary table owner_push_b as select public.push_changes('pomodoist','collab-device-b',jsonb_build_array(
  jsonb_build_object('opId','unshare-project','entityType','project','entityId','project-b','operation','upsert',
    'payload',jsonb_build_object('id','project-b','userId','local-user','name','Project B','orderKey','1',
      'isFavorite',true,'viewStyle','board'),
    'clientUpdatedAt','2026-09-17T10:00:00Z'),
  jsonb_build_object('opId','unshare-task','entityType','task','entityId','task-b','operation','upsert',
    'payload',jsonb_build_object('id','task-b','userId','local-user','content','Personal task B','projectId','project-b',
      'status','open','priority',1),
    'clientUpdatedAt','2026-09-17T10:00:01Z'),
  jsonb_build_object('opId','unshare-label','entityType','label','entityId','label-b','operation','upsert',
    'payload',jsonb_build_object('id','label-b','userId','local-user','name','Label B','color','blue'),
    'clientUpdatedAt','2026-09-17T10:00:02Z'),
  jsonb_build_object('opId','unshare-task-label','entityType','task_label','entityId','task-label-b','operation','upsert',
    'payload',jsonb_build_object('id','task-label-b','userId','local-user','taskId','task-b','labelId','label-b'),
    'clientUpdatedAt','2026-09-17T10:00:03Z'))) as value;
select is(jsonb_array_length((select value->'applied' from owner_push_b)),4,'the owner seeds four personal entities before sharing');

create temporary table owner_revision_b as
  select coalesce(max(server_revision),0) as revision from public.sync_entities
  where user_id='c1000000-0000-4000-8000-000000000001'::uuid;

create temporary table shared_scope_b as select pg_temp.collab(
  jsonb_build_object('action','share','rootProjectId','project-b','expectedRevision',(select revision from owner_revision_b))) as value;
create temporary table scope_b as select (select value->'scope'->>'id' from shared_scope_b)::uuid as id;
select is((select value->'scope'->>'role' from shared_scope_b),'administrator','the owner administrates the second scope');

reset role;
select is((select count(*) from private.pomodoist_transferred_entities where scope_id=(select id from scope_b)),3::bigint,
  'the second scope transfers the project, the task and the task label');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
create temporary table member_invite_b as select pg_temp.collab(
  jsonb_build_object('action','invite','scopeId',(select id from scope_b),'email','collab-member@example.test','role','member')) as value;

select pg_temp.act_as('c1000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000002');
create temporary table member_accept_b as select pg_temp.collab(
  jsonb_build_object('action','accept','token',(select value->>'token' from member_invite_b))) as value;
select is((select value->'scope'->>'role' from member_accept_b),'member','the invited member joins the second scope');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','unshare','scopeId',(select id from scope_b))::text),
  '42501','Only the owner may make the project private','members cannot make a shared root private');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select is((pg_temp.collab(format('{"action":"role","scopeId":%s,"userId":"c1000000-0000-4000-8000-000000000002","role":"administrator"}',
  to_json((select id from scope_b))::text)::jsonb))->>'ok','true','owners can promote a member in the second scope');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000002');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','unshare','scopeId',(select id from scope_b))::text),
  '42501','Only the owner may make the project private','administrators cannot make a shared root private');
create temporary table member_pull_b as select pg_temp.collab(
  jsonb_build_object('action','pull','scopeId',(select id from scope_b))) as value;
create temporary table member_push_b as select pg_temp.call_op((select id from scope_b),jsonb_build_object(
  'opId','unshare-shared-edit','entityType','task','entityId','task-b','operation','upsert',
  'payload',jsonb_build_object('id','task-b','content','Shared task B','projectId','project-b','status','open'),
  'baseRevision',(select (value->>'nextCursor')::bigint from member_pull_b),'clientUpdatedAt','2026-09-17T11:00:00Z')) as value;
select is(jsonb_array_length((select value->'applied' from member_push_b)),1,'members can edit the task after sharing');
select is((select value->'applied'->0->'data'->>'content' from member_push_b),'Shared task B','the shared edit is stored on the shared copy');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
create temporary table unshare_result as select pg_temp.collab(
  jsonb_build_object('action','unshare','scopeId',(select id from scope_b))) as value;
select is((select value->>'ok' from unshare_result),'true','owners can make a shared root personal again');
select is((select value->>'restored' from unshare_result),'3','unshare restores the project, the task and the task label');
select is((select value->>'rootProjectId' from unshare_result),'project-b','unshare reports the restored root');

reset role;
select is((select count(*) from private.pomodoist_transferred_entities where scope_id=(select id from scope_b)),0::bigint,
  'unshare releases every transferred entity');
select ok(not exists(select 1 from private.pomodoist_scopes where id=(select id from scope_b)),'unshared scopes are gone');
select ok(not exists(select 1 from private.pomodoist_shared_entities where scope_id=(select id from scope_b)),
  'shared copies cascade with the unshared scope');
select ok((select deleted_at is null from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and entity_type='project' and entity_id='project-b'),'the personal project is live again');
select ok((select deleted_at is null from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and entity_type='task' and entity_id='task-b'),'the personal task is live again');
select is((select data->>'isFavorite' from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and entity_type='project' and entity_id='project-b'),'true','personal-only project fields survive the round trip');
select is((select data->>'viewStyle' from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and entity_type='project' and entity_id='project-b'),'board','personal view preferences survive the round trip');
select is((select data->>'content' from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and entity_type='task' and entity_id='task-b'),'Shared task B','the newest shared edit wins over the tombstone copy');
select is((select data->>'labelId' from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and entity_type='task_label' and entity_id='task-label-b'),'label-b','unshare strips the scope prefix from the restored label reference');
select is((select data->>'id' from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and entity_type='task_label' and entity_id='task-label-b'),'task-label-b','the restored task label keeps its personal identity');
select ok((select deleted_at is null and data->>'name'='Label B' from public.sync_entities
    where user_id='c1000000-0000-4000-8000-000000000001' and entity_type='label' and entity_id='label-b'),
  'personal labels were never transferred by sharing');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
select lives_ok($$select public.push_changes('pomodoist','collab-device-b',jsonb_build_array(
  jsonb_build_object('opId','unshare-recheck','entityType','task','entityId','task-b-restored','operation','upsert',
    'payload',jsonb_build_object('id','task-b-restored','userId','local-user','content','Back in personal','projectId','project-b'),
    'clientUpdatedAt','2026-09-17T12:00:00Z')))$$,
  'personal writes reach the restored project again');
reset role;
select ok(exists(select 1 from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and entity_type='task' and entity_id='task-b-restored' and deleted_at is null),
  'the restored project accepts new personal tasks');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000002');
select throws_ok(format('select pg_temp.collab(%L::jsonb)',
  jsonb_build_object('action','pull','scopeId',(select id from scope_b))::text),
  '42501','Shared scope is inaccessible','unshared scopes lose every member');
select ok(exists(select 1 from jsonb_array_elements((pg_temp.collab(jsonb_build_object('action','notifications'))->'notifications')) n
    where n->'data'->>'scopeId'=(select id::text from scope_b) and n->>'scopeId' is null and n->>'kind'='access.unshare'),
  'the removed member is notified without keeping a reference to the deleted scope');

select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
create temporary table owner_push_c as select public.push_changes('pomodoist','collab-device-c',jsonb_build_array(
  jsonb_build_object('opId','nested-parent','entityType','project','entityId','project-parent-c','operation','upsert',
    'payload',jsonb_build_object('id','project-parent-c','userId','local-user','name','Parent C','orderKey','3'),
    'clientUpdatedAt','2026-09-17T13:00:00Z'),
  jsonb_build_object('opId','nested-child','entityType','project','entityId','project-nested-c','operation','upsert',
    'payload',jsonb_build_object('id','project-nested-c','userId','local-user','name','Nested C','orderKey','0',
      'parentId','project-parent-c'),
    'clientUpdatedAt','2026-09-17T13:00:01Z'))) as value;
select is(jsonb_array_length((select value->'applied' from owner_push_c)),2,
  'the owner seeds a project nested inside another personal project');

create temporary table owner_revision_c as
  select coalesce(max(server_revision),0) as revision from public.sync_entities
  where user_id='c1000000-0000-4000-8000-000000000001'::uuid;

create temporary table shared_scope_c as select pg_temp.collab(
  jsonb_build_object('action','share','rootProjectId','project-nested-c','expectedRevision',(select revision from owner_revision_c))) as value;
create temporary table scope_c as select (select value->'scope'->>'id' from shared_scope_c)::uuid as id;

reset role;
select is((select data->>'parentId' from private.pomodoist_shared_entities
    where scope_id=(select id from scope_c) and entity_type='project' and entity_id='project-nested-c'),null::text,
  'sharing detaches the shared root from its personal parent');
select is((select data->>'rootParentId' from private.pomodoist_shared_preferences
    where scope_id=(select id from scope_c) and entity_type='scope' and entity_id=(select id::text from scope_c)),
  'project-parent-c','sharing remembers the personal parent of the root');

set local role authenticated;
select pg_temp.act_as('c1000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001');
create temporary table unshare_result_c as select pg_temp.collab(
  jsonb_build_object('action','unshare','scopeId',(select id from scope_c))) as value;
select is((select value->>'restored' from unshare_result_c),'1','a nested shared root restores on its own');

reset role;
select is((select data->>'parentId' from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and app_id='pomodoist' and entity_type='project' and entity_id='project-nested-c'),'project-parent-c',
  'a shared root returns to the personal parent it was nested in');
select ok((select deleted_at is null from public.sync_entities where user_id='c1000000-0000-4000-8000-000000000001'
    and app_id='pomodoist' and entity_type='project' and entity_id='project-nested-c'),
  'the nested personal project is live again');

select * from finish();
rollback;
