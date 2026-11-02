-- Standalone assertions also run on a disposable PostgreSQL fixture without pgTAP.
begin;
select '1..1';
create function pg_temp.assert_true(value boolean,label text) returns void language plpgsql as $$begin if value is distinct from true then raise exception 'Assertion failed: %',label; end if; end$$;
create function pg_temp.task(id text,needs jsonb default '[]',priority integer default 4,day date default null,scope text default null,project text default 'inbox',assignees jsonb default '[]') returns jsonb language sql as $$
 select jsonb_build_object('id',id,'content',id,'status','open','projectId',project,'priority',priority,'scopeId',scope,'assigneeIds',assignees,'prerequisiteIdsJson',needs::text,'dueJson',case when day is null then null else jsonb_build_object('date',day)::text end)
$$;
-- Missing policy is the RED state before applying the migration.
select pg_temp.assert_true(to_regprocedure('private.pomodoist_task_availability(jsonb,jsonb,text,text,text[])') is not null,'blocking policy is installed');
select pg_temp.assert_true(private.pomodoist_mcp_task_json('legacy','{}')->>'prerequisiteIdsJson'='[]','legacy MCP tasks expose empty dependencies');
do $$declare g jsonb; prefs jsonb; answer jsonb; begin
 g:=jsonb_build_object('a',pg_temp.task('a'),'b',pg_temp.task('b','["a"]'));
 answer:=private.pomodoist_task_availability(g,'{}','me','b');
 perform pg_temp.assert_true(answer->>'allowed'='false' and answer->'blockingTaskIds' ? 'a','unfinished predecessor blocks');
 answer:=private.pomodoist_task_availability(g,'{}','me','b',array['a','b']);
 perform pg_temp.assert_true(answer->>'allowed'='true','internal dependencies may complete together');
 g:=jsonb_set(g,'{a,status}','"completed"');
 perform pg_temp.assert_true(private.pomodoist_task_availability(g,'{}','me','b')->>'allowed'='true','completed predecessor releases');
 g:=jsonb_set(g,'{a,status}','"open"');
 g:=jsonb_set(g,'{a,prerequisiteIdsJson}',to_jsonb('["b"]'::text));
 begin perform private.pomodoist_blocking_validate_graph(g); raise exception 'cycle accepted'; exception when sqlstate '22023' then null; end;
 g:=jsonb_build_object('a',pg_temp.task('a'),'b',pg_temp.task('b'));
 prefs:='{"settings":{"timeZone":"UTC"},"personal":{"taskId":"a","repeatWithSeries":true}}';
 perform pg_temp.assert_true(private.pomodoist_task_availability(g,prefs,'me','b')->>'allowed'='false','personal urgent blocks other tasks');
 perform pg_temp.assert_true(private.pomodoist_task_availability(g,prefs,'me',null)->>'allowed'='false','personal urgent blocks taskless Focus');
 g:=jsonb_set(g,'{a,dueJson}',to_jsonb(jsonb_build_object('date',current_date+1)::text));
 perform pg_temp.assert_true(private.pomodoist_task_availability(g,prefs,'me','b')->>'allowed'='true','future urgent stays dormant');
 g:=jsonb_build_object('p1',pg_temp.task('p1','["step"]',1,current_date),'step',pg_temp.task('step'),'p2',pg_temp.task('p2','[]',2,current_date));
 prefs:='{"settings":{"timeZone":"UTC","priorityCascadeEnabled":true}}';
 perform pg_temp.assert_true(private.pomodoist_task_availability(g,prefs,'me','step')->>'allowed'='true','P4 predecessor inherits P1 availability');
 perform pg_temp.assert_true(private.pomodoist_task_availability(g,prefs,'me','p2')->>'allowed'='false','P2 waits for available P1 step');
 g:=jsonb_build_object('p1',pg_temp.task('p1','["step"]',1,current_date,'s','work','["me"]'),'step',pg_temp.task('step','[]',4,null,'s','work','["them"]'),'p2',pg_temp.task('p2','[]',2,current_date,'s','work','["me"]'));
 perform pg_temp.assert_true(private.pomodoist_task_availability(g,prefs,'me','p2')->>'allowed'='true','cascade skips waiting on colleague');
 prefs:='{"settings":{"timeZone":"UTC"},"project:work":{"taskId":"p1","repeatWithSeries":true}}';
 perform pg_temp.assert_true(private.pomodoist_task_availability(g,prefs,'me','p2')->>'allowed'='false','urgent remains strict while waiting');
 perform pg_temp.assert_true(private.pomodoist_task_availability(g,prefs,'them','p2')->>'allowed'='true','urgent is not enforced against another actor');
end$$;

-- These writes exercise deferred commit checks, not only the pure policy.
do $$declare actor uuid:='bb000000-0000-4000-8000-000000000001'; now_value timestamptz:=now(); begin
 insert into auth.users(id,email) values(actor,'task-blocking@example.test');
 insert into public.sync_entities(user_id,app_id,entity_type,entity_id,data,server_revision,client_updated_at) values
 (actor,'pomodoist','task','block-a',pg_temp.task('block-a'),1,now_value),
 (actor,'pomodoist','task','block-b',pg_temp.task('block-b','["block-a"]'),2,now_value);
 set constraints all immediate;
 set constraints all deferred;
 begin
  update public.sync_entities set data=data||'{"status":"completed"}' where user_id=actor and entity_id='block-b';
  set constraints all immediate;
  raise exception 'external dependency accepted';
 exception when sqlstate '22023' then
  perform pg_temp.assert_true(sqlerrm='task_blocked','structured completion rejection');
 end;
 perform pg_temp.assert_true((select data->>'status'='open' from public.sync_entities where user_id=actor and entity_id='block-b'),'rejected completion rolled back');
 update public.sync_entities set data=data||'{"status":"completed"}' where user_id=actor and entity_type='task';
 set constraints all immediate;
 set constraints all deferred;
 update public.sync_entities set data=data||'{"status":"open"}' where user_id=actor and entity_id='block-a';
 set constraints all immediate;
 perform pg_temp.assert_true((select data->>'status'='completed' from public.sync_entities where user_id=actor and entity_id='block-b'),'reopening does not undo dependents');
 set constraints all deferred;
 insert into public.sync_entities(user_id,app_id,entity_type,entity_id,data,server_revision,client_updated_at) values
 (actor,'pomodoist','task_blocking','settings','{"id":"settings","commandType":"task_blocking.upsert","priorityCascadeEnabled":false,"timeZone":"UTC"}',3,now_value),
 (actor,'pomodoist','task_blocking','personal','{"id":"personal","taskId":"block-a","repeatWithSeries":true}',4,now_value);
 set constraints all immediate;
 set constraints all deferred;
 begin
  insert into public.sync_entities(user_id,app_id,entity_type,entity_id,data,server_revision,client_updated_at) values
   (actor,'pomodoist','focus_interval','blocked-focus','{"type":"work","status":"running"}',5,now_value);
  set constraints all immediate;
  raise exception 'legacy taskless Focus accepted';
 exception when sqlstate '22023' then
  perform pg_temp.assert_true(sqlerrm='task_blocked','legacy clients enforce urgency');
 end;
 set constraints all deferred;
 -- Finishing an urgent occurrence must not be blocked by the next overdue one.
 insert into public.sync_entities(user_id,app_id,entity_type,entity_id,data,server_revision,client_updated_at) values
 (actor,'pomodoist','task','repeat-first',pg_temp.task('repeat-first')||jsonb_build_object('dueJson',jsonb_build_object('date',current_date-2,'recurrence',jsonb_build_object('interval',1,'unit','day','seriesId','repeat'))::text),6,now_value),
 (actor,'pomodoist','task','repeat-next',pg_temp.task('repeat-next')||jsonb_build_object('dueJson',jsonb_build_object('date',current_date-1,'recurrence',jsonb_build_object('interval',1,'unit','day','seriesId','repeat'))::text),7,now_value);
 update public.sync_entities set data='{"taskId":"repeat-first","seriesId":"repeat","repeatWithSeries":true}' where user_id=actor and entity_type='task_blocking' and entity_id='personal';
 set constraints all immediate;
 set constraints all deferred;
 -- Reset only this synthetic transaction's earlier completion snapshot.
 perform set_config('pomodoist.blocking_urgent_snapshot','{}',true);
 perform set_config('pomodoist.blocking_completed_ids','[]',true);
 update public.sync_entities set data=data||'{"status":"completed"}' where user_id=actor and entity_type='task' and entity_id='repeat-first';
 set constraints all immediate;
 perform pg_temp.assert_true(private.pomodoist_blocking_selected(private.pomodoist_blocking_graph(actor),private.pomodoist_blocking_preferences(actor),actor::text,'personal')='repeat-next','urgency follows the next occurrence after atomic completion');
 set constraints all deferred;
end$$;
select 'ok 1 - task blocking policy';
rollback;
