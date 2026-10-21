begin;
\ir hosted-mode.inc

select plan(5);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values ('a7d71236-94bd-4a86-98b4-c04df381096d', 'account-delete@example.invalid',
  'authenticated', 'authenticated', now(), now());

insert into public.sync_entities (
  user_id, app_id, entity_type, entity_id, server_revision,
  client_updated_at, data, field_clock
) values
  ('a7d71236-94bd-4a86-98b4-c04df381096d', 'pomodoist', 'task', 'ordinary-delete',
    nextval('public.sync_revision_seq'), '2026-09-10 10:00:00+00',
    '{"id":"ordinary-delete","dueJson":"{\"date\":\"2026-09-11\"}"}', '{}'),
  ('a7d71236-94bd-4a86-98b4-c04df381096d', 'pomodoist', 'task', 'account-cascade',
    nextval('public.sync_revision_seq'), '2026-09-10 10:01:00+00',
    '{"id":"account-cascade","dueJson":"{\"date\":\"2026-09-12\"}"}', '{}');

delete from private.pomodoist_calendar_task_state
where user_id = 'a7d71236-94bd-4a86-98b4-c04df381096d'
  and task_id = 'ordinary-delete';

delete from public.sync_entities
where user_id = 'a7d71236-94bd-4a86-98b4-c04df381096d'
  and entity_type = 'task' and entity_id = 'ordinary-delete';

select ok(
  exists (
    select 1 from private.pomodoist_calendar_task_state
    where user_id = 'a7d71236-94bd-4a86-98b4-c04df381096d'
      and task_id = 'ordinary-delete'
      and incarnation = 1
  ),
  'ordinary task deletion preserves calendar reconciliation state'
);

select lives_ok(
  $$delete from auth.users where id = 'a7d71236-94bd-4a86-98b4-c04df381096d'$$,
  'deleting an auth user with synchronized tasks succeeds'
);

select is(
  (select count(*) from public.profiles where id = 'a7d71236-94bd-4a86-98b4-c04df381096d'),
  0::bigint,
  'account deletion removes the profile'
);

select is(
  (select count(*) from public.sync_entities where user_id = 'a7d71236-94bd-4a86-98b4-c04df381096d'),
  0::bigint,
  'account deletion removes synchronized entities'
);

select is(
  (select count(*) from private.pomodoist_calendar_task_state where user_id = 'a7d71236-94bd-4a86-98b4-c04df381096d'),
  0::bigint,
  'account deletion removes calendar task state'
);

select * from finish();
rollback;
