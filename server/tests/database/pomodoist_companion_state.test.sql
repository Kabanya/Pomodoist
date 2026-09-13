begin;
select plan(7);
insert into auth.users(id,email,aud,role,created_at,updated_at) values
('95000000-0000-4000-8000-000000000002','companion-a@example.com','authenticated','authenticated',now(),now()),
('95000000-0000-4000-8000-000000000003','companion-b@example.com','authenticated','authenticated',now(),now());
insert into public.sync_entities(user_id,app_id,entity_type,entity_id,server_revision,client_updated_at,data,field_clock)
select '95000000-0000-4000-8000-000000000002','pomodoist','task','child-'||n,
nextval('public.sync_revision_seq'),now(),jsonb_build_object('id','child-'||n,'parentId','root','status','open'),'{}'::jsonb
from generate_series(1,1005) n;
insert into public.sync_entities(user_id,app_id,entity_type,entity_id,server_revision,client_updated_at,data,field_clock) values
('95000000-0000-4000-8000-000000000002','pomodoist','focus_event','history',nextval('public.sync_revision_seq'),now(),'{"id":"history"}','{}'),
('95000000-0000-4000-8000-000000000002','pomodoist','focus_run','old-run',nextval('public.sync_revision_seq'),now(),'{"id":"old-run","status":"completed"}','{}'),
('95000000-0000-4000-8000-000000000003','pomodoist','task','foreign',nextval('public.sync_revision_seq'),now(),'{"id":"foreign"}','{}');
select set_config('request.jwt.claim.sub','95000000-0000-4000-8000-000000000002',true);
create temporary table companion_pages as select public.read_pomodoist_companion_state(0) data;
select is(jsonb_array_length(data->'changes'),1000,'first read is bounded') from companion_pages;
select is((data->>'hasMore')::boolean,true,'all children remain pageable') from companion_pages;
create temporary table companion_second as select public.read_pomodoist_companion_state((data->>'nextCursor')::bigint) data from companion_pages;
select is(jsonb_array_length(data->'changes'),5,'remaining children are preserved') from companion_second;
select is((data->>'hasMore')::boolean,false,'history and other users are excluded') from companion_second;
select ok(not has_function_privilege('anon','public.read_pomodoist_companion_state(bigint)','execute'),'anonymous state RPC revoked');
select ok(not has_function_privilege('anon','public.push_pomodoist_draft_changes(text,text,jsonb)','execute'),'anonymous draft RPC revoked');
select set_config('request.jwt.claim.sub','',true);
select throws_ok('select public.read_pomodoist_companion_state(0)','P0001','Authentication required','state requires authenticated identity');
select * from finish();
rollback;
