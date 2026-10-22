begin;
\ir hosted-mode.inc

select plan(2);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values ('11111111-1111-4111-8111-111111111112', 'calendar-ack@example.com',
  'authenticated', 'authenticated', now(), now());

insert into private.pomodoist_calendar_connections
  (id, user_id, provider, lease, lease_until)
values ('22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111112', 'outlook',
  '33333333-3333-4333-8333-333333333333', now() + interval '5 minutes');

select throws_ok($call$
  select public.pomodoist_calendar_service('save_link',
    '11111111-1111-4111-8111-111111111112', 'outlook',
    '{"guard":{"connectionId":"22222222-2222-4222-8222-222222222222","generation":1,"lease":"33333333-3333-4333-8333-333333333333"},"taskId":"task-ack","revision":7,"link":{"incarnation":1,"eventId":"event-ack"}}');
$call$, 'P0001', 'unprepared_calendar_acknowledgement',
  'an event acknowledgement requires its prepared effect');

insert into private.pomodoist_calendar_effects
  (connection_id, task_id, revision, incarnation, kind, fields)
values ('22222222-2222-4222-8222-222222222222', 'task-ack', 7, 1, 'create', '{}');

select lives_ok($call$
  select public.pomodoist_calendar_service('save_link',
    '11111111-1111-4111-8111-111111111112', 'outlook',
    '{"guard":{"connectionId":"22222222-2222-4222-8222-222222222222","generation":1,"lease":"33333333-3333-4333-8333-333333333333"},"taskId":"task-ack","revision":7,"link":{"incarnation":1,"eventId":"event-ack"}}');
$call$, 'a prepared event acknowledgement saves its link');

select * from finish();
rollback;
