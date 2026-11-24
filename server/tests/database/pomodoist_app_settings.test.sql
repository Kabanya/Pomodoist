begin;
select no_plan();
-- Assert-based integration checks also run on plain PostgreSQL without pgTAP.
insert into auth.users(id,email) values ('11111111-1111-4111-8111-111111111111','settings-a@example.test'), ('66666666-6666-4666-8666-666666666666','settings-b@example.test');
insert into auth.oauth_clients(id,registration_type,redirect_uris,grant_types,client_name,client_type,token_endpoint_auth_method)
values ('22222222-2222-4222-8222-222222222222','dynamic','["http://localhost/callback"]','["authorization_code"]','Settings test','public','none');
insert into auth.sessions(id,user_id,oauth_client_id,not_after,created_at,updated_at) values
('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',now()+interval '1 hour',now(),now()),
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111',null,now()+interval '1 hour',now(),now());
create function pg_temp.agent(command jsonb) returns jsonb language sql as $$ select public.pomodoist_app_settings_agent(private.pomodoist_mcp_subject('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'),'33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222',command); $$;
create function pg_temp.device(command jsonb) returns jsonb language sql as $$ select api_v1.pomodoist_app_settings_device('{"deviceId":"44444444-4444-4444-8444-444444444444","instanceId":"55555555-5555-4555-8555-555555555555"}'::jsonb || command); $$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","session_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',true);
do $model$
declare
 actor uuid := auth.uid();
 command jsonb := '{"action":"request","operation":"customModel","setting":"customModel","expected_version":"default",
  "request_id":"cad00000-0000-4000-8000-000000000001","device_id":"44444444-4444-4444-8444-444444444444",
  "value":{"enabled":true,"baseUrl":"http://localhost:11434/v1","normalModel":"fast","apiKey":"fixture-only"}}';
 rid uuid := (command->>'request_id')::uuid;
 secret_id uuid;
 claim jsonb;
 result jsonb := '{"status":"applied","setting":"customModel","version":"v2","value":{"enabled":true,
  "baseUrl":"http://localhost:11434/v1","normalModel":"fast","smartModel":"","hasKey":true}}';
begin
 perform pg_temp.device('{"action":"register","name":"Test","platform":"web","capabilities":{"operations":["read","customModel"]}}');
 assert not (pg_temp.agent('{"action":"list"}')#>'{devices,0,capabilities,operations}' ? 'customModel');
 begin perform pg_temp.agent(command); raise exception 'Expected unpaid access rejection'; exception when insufficient_privilege then null; end;
 perform public.link_pomodoist_stripe_customer(actor,'cus_settings');
 perform public.record_pomodoist_stripe_event('evt_settings','invoice.paid',now(),'sub_settings','cus_settings',actor,
   'pomodoist.pro.annual','subscription','active',now(),now()+interval '1 month',false,'{}');
 perform public.record_pomodoist_custom_model_stripe_payment('sub_settings','settings-year','pomodoist.pro.annual',now()-interval '1 year',false);
 assert pg_temp.agent(command)->>'status'='pending';
 assert pg_temp.agent(command)->>'status'='pending';
 select credential_id into strict secret_id from private.pomodoist_app_settings_requests
 where request_id=rid and not value?'apiKey';
 assert secret_id is not null;
 assert exists (select 1 from vault.decrypted_secrets where id=secret_id and decrypted_secret='fixture-only');
 claim:=pg_temp.device('{"action":"claim"}');
 assert claim#>>'{commands,0,value,apiKey}'='fixture-only';
 assert pg_temp.device('{"action":"claim"}')=claim;
 begin
  perform pg_temp.device(jsonb_build_object('action','finish','requestId',rid,'result',jsonb_set(result,'{value,apiKey}','"fixture-only"')));
  raise exception 'Credential in a receipt';
 exception when invalid_parameter_value then null; end;
 perform pg_temp.device(jsonb_build_object('action','finish','requestId',rid,'result',result));
 assert pg_temp.agent(command)->>'status'='applied';
 assert position('fixture-only' in pg_temp.agent(command)::text)=0;
 assert not exists (select 1 from vault.secrets where id=secret_id);
 -- An already completed snapshot also follows later entitlement changes.
 perform pg_temp.agent('{"action":"request","operation":"read","device_id":"44444444-4444-4444-8444-444444444444","request_id":"cad00000-0000-4000-8000-000000000003"}');
 perform pg_temp.device('{"action":"claim"}');
 perform pg_temp.device(jsonb_build_object('action','finish','requestId','cad00000-0000-4000-8000-000000000003',
  'result',jsonb_build_object('status','applied','values',jsonb_build_object('customModel',result->'value','theme','classic'),
                              'versions',jsonb_build_object('customModel','v2'),
                              'capabilities',jsonb_build_object('operations',jsonb_build_array('read','customModel')))));
 assert pg_temp.agent('{"action":"status","request_id":"cad00000-0000-4000-8000-000000000003"}')#>>'{result,values,customModel,normalModel}'='fast';
 command:=jsonb_set(command,'{request_id}','"cad00000-0000-4000-8000-000000000002"');
 perform pg_temp.agent(command);
 select credential_id into strict secret_id from private.pomodoist_app_settings_requests where request_id=(command->>'request_id')::uuid;
 perform public.record_pomodoist_custom_model_stripe_payment('sub_settings','settings-year','pomodoist.pro.annual',now(),true);
 assert pg_temp.device('{"action":"claim"}')->'commands'='[]'::jsonb;
 assert not (pg_temp.agent(jsonb_build_object('action','status','request_id',rid))#>'{result}' ? 'value');
 claim:=pg_temp.agent('{"action":"status","request_id":"cad00000-0000-4000-8000-000000000003"}')->'result';
 assert claim->'values'='{"theme":"classic"}' and claim->'versions'='{}' and claim#>'{capabilities,operations}'='["read"]';
 assert not exists(select 1 from vault.secrets where id=secret_id);
end $model$;
select pass('custom model writes enforce payment on admission and delivery, protect keys and clear them after completion or refund');

do $$
declare r jsonb; command jsonb := '{"action":"request","request_id":"77777777-7777-4777-8777-777777777777","device_id":"44444444-4444-4444-8444-444444444444","operation":"appearance","setting":"themeMode","value":"dark","expected_version":"v1"}';
begin
 assert not has_function_privilege('anon','api_v1.pomodoist_app_settings_device(jsonb)','execute');
 assert not has_function_privilege('authenticated','public.pomodoist_app_settings_agent(uuid,uuid,uuid,jsonb)','execute');
 assert not has_table_privilege('authenticated','private.pomodoist_app_settings_requests','select');
 assert (pg_temp.device('{"action":"register","name":"Mac","platform":"macOS","capabilities":{"settings":["themeMode"]}}')->>'registered')::boolean;
 assert pg_temp.device('{"action":"register","instanceId":"88888888-8888-4888-8888-888888888888","name":"Other","platform":"web","capabilities":{}}')->>'code' = 'device_in_use';
 assert jsonb_array_length(pg_temp.agent('{"action":"list"}')->'devices')=1;
 assert pg_temp.agent('{"action":"list"}')#>'{devices,0,online}'='true'::jsonb;
 r := pg_temp.agent(command); assert r->>'status'='pending';
 assert pg_temp.agent(command)=r;
 begin perform pg_temp.agent(command||'{"value":"light"}'); raise exception 'Expected mismatch rejection'; exception when invalid_parameter_value then null; end;
 r:=pg_temp.device('{"action":"claim"}'); assert r#>>'{commands,0,request_id}'=command->>'request_id';
 assert pg_temp.device('{"action":"claim"}')=r; -- Lost claim responses retry within one instance.
 assert pg_temp.device('{"action":"finish","requestId":"77777777-7777-4777-8777-777777777777","result":{"status":"applied","setting":"themeMode","value":"dark","version":"v2"}}')->>'status'='applied';
 assert pg_temp.agent(command)->>'status'='applied';
 assert (select value is null from private.pomodoist_app_settings_requests where request_id=(command->>'request_id')::uuid);
 perform pg_temp.agent(command||'{"request_id":"99999999-9999-4999-8999-999999999999"}');
 delete from auth.sessions where id='33333333-3333-4333-8333-333333333333';
 assert jsonb_array_length(pg_temp.device('{"action":"claim"}')->'commands')=0;
 assert (select status='error' from private.pomodoist_app_settings_requests where request_id='99999999-9999-4999-8999-999999999999');
 begin perform pg_temp.agent('{"action":"list"}'); raise exception 'Expected revoked rejection'; exception when insufficient_privilege then null; end;
end $$;
select pass('device lease, deduplication, serialization, terminal privacy and live OAuth revocation');
-- Restore OAuth for lifecycle cases.
insert into auth.sessions(id,user_id,oauth_client_id,not_after,created_at,updated_at) values ('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',now()+interval '1 hour',now(),now());
do $$
declare command jsonb := '{"action":"request","request_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","device_id":"44444444-4444-4444-8444-444444444444","operation":"read"}';
begin
 perform pg_temp.agent(command); perform pg_temp.device('{"action":"claim"}');
 update private.pomodoist_app_settings_devices set lease_until=clock_timestamp()-interval '1 second';
 assert pg_temp.agent('{"action":"status","request_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}')->>'status'='uncertain';
 perform pg_temp.device('{"action":"register","instanceId":"88888888-8888-4888-8888-888888888888","name":"New","platform":"macOS","capabilities":{}}');
 assert jsonb_array_length(pg_temp.device('{"action":"claim","instanceId":"88888888-8888-4888-8888-888888888888"}')->'commands')=0;
 perform pg_temp.agent(command||'{"request_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}');
 update private.pomodoist_app_settings_requests set claim_deadline=clock_timestamp()-interval '1 second' where status='pending';
 assert pg_temp.agent('{"action":"status","request_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}')->>'status'='expired';
 begin perform pg_temp.agent(command||'{"request_id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","operation":"appearance","setting":"billing","value":"anything","expected_version":"v1"}'); raise exception 'Expected invalid setting'; exception when invalid_parameter_value then null; end;
 begin perform pg_temp.agent(command||'{"request_id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","operation":"appearance","setting":"customTheme","value":{"imagePath":"/private/photo.png"},"expected_version":"v1"}'); raise exception 'Expected invalid private path'; exception when invalid_parameter_value then null; end;
 -- A live heartbeat cannot keep abandoned claimed execution pending forever.
 perform pg_temp.agent(command||'{"request_id":"abababab-abab-4bab-8bab-abababababab"}');
 perform pg_temp.device('{"action":"claim","instanceId":"88888888-8888-4888-8888-888888888888"}');
 update private.pomodoist_app_settings_requests set execution_deadline=clock_timestamp()-interval '1 second' where status='claimed';
 perform pg_temp.device('{"action":"register","instanceId":"88888888-8888-4888-8888-888888888888","name":"New","platform":"macOS","capabilities":{}}');
 assert pg_temp.agent('{"action":"status","request_id":"abababab-abab-4bab-8bab-abababababab"}')->>'status'='uncertain';
 assert jsonb_array_length(pg_temp.device('{"action":"claim","instanceId":"88888888-8888-4888-8888-888888888888"}')->'commands')=0;
 -- A reset must survive command JSON construction unchanged.
 perform pg_temp.agent('{"action":"request","request_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","device_id":"44444444-4444-4444-8444-444444444444","operation":"shortcut","setting":"shortcuts","value":{"command":"quickAdd","binding":null},"expected_version":"v1"}');
 assert pg_temp.device('{"action":"claim","instanceId":"88888888-8888-4888-8888-888888888888"}')#>'{commands,0,value,binding}'='null'::jsonb;
 begin perform pg_temp.device('{"action":"finish","instanceId":"88888888-8888-4888-8888-888888888888","requestId":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","result":{"status":"applied","image_url":"https://secret.example/photo.png"}}'); raise exception 'Expected result source URL rejection'; exception when invalid_parameter_value then null; end;
 perform pg_temp.device('{"action":"finish","instanceId":"88888888-8888-4888-8888-888888888888","requestId":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","result":{"status":"applied","value":{"binding":null}}}');
 assert pg_temp.agent('{"action":"status","request_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}')#>'{result,value,binding}'='null'::jsonb;
 -- Heartbeat extends the lease; another live instance still cannot steal it.
 assert (pg_temp.device('{"action":"register","instanceId":"88888888-8888-4888-8888-888888888888","name":"New","platform":"macOS","capabilities":{}}')->>'registered')::boolean;
 -- Offline errors are durable and never turn into queued changes after reconnect.
 perform pg_temp.device('{"action":"disconnect","instanceId":"88888888-8888-4888-8888-888888888888"}');
 assert jsonb_array_length(pg_temp.agent('{"action":"list"}')->'devices')=1;
 assert pg_temp.agent('{"action":"list"}')#>'{devices,0,online}'='false'::jsonb;
 assert pg_temp.agent(command||'{"request_id":"acacacac-acac-4cac-8cac-acacacacacac"}')->>'status'='error';
 perform pg_temp.device('{"action":"register","instanceId":"88888888-8888-4888-8888-888888888888","name":"New","platform":"macOS","capabilities":{}}');
 assert pg_temp.agent(command||'{"request_id":"acacacac-acac-4cac-8cac-acacacacacac"}')->>'status'='error';
 -- Pending source URLs are accepted but removed on expiry.
 perform pg_temp.agent('{"action":"request","request_id":"adadadad-adad-4dad-8dad-adadadadadad","device_id":"44444444-4444-4444-8444-444444444444","operation":"appearance","setting":"customTheme","expected_version":"v1","value":{"image_url":"https://example.test/photo.png","image_palette":"light","image_zone":"main"}}');
 update private.pomodoist_app_settings_requests set claim_deadline=clock_timestamp()-interval '1 second' where status='pending';
 assert pg_temp.agent('{"action":"status","request_id":"adadadad-adad-4dad-8dad-adadadadadad"}')->>'status'='expired';
 assert (select value is null from private.pomodoist_app_settings_requests where request_id='adadadad-adad-4dad-8dad-adadadadadad');
 -- Terminal receipt and source metadata are bounded on access.
 insert into private.pomodoist_app_settings_requests(user_id,request_id,client_id,subject,session_id,device_id,instance_id,operation,arguments_hash,status,result,created_at,claim_deadline)
 select '11111111-1111-4111-8111-111111111111',gen_random_uuid(),'22222222-2222-4222-8222-222222222222',private.pomodoist_mcp_subject('11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'),'33333333-3333-4333-8333-333333333333','44444444-4444-4444-8444-444444444444','88888888-8888-4888-8888-888888888888','read',repeat('a',64),'applied','{"status":"applied"}',clock_timestamp(),clock_timestamp() from generate_series(1,110);
 perform pg_temp.agent('{"action":"list"}');
 assert (select count(*)<=100 from private.pomodoist_app_settings_requests where user_id='11111111-1111-4111-8111-111111111111');
 update private.pomodoist_app_settings_requests set created_at=clock_timestamp()-interval '25 hours';
 perform pg_temp.agent('{"action":"list"}');
 assert not exists(select 1 from private.pomodoist_app_settings_requests where user_id='11111111-1111-4111-8111-111111111111');
 perform set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',true);
 perform set_config('request.jwt.claims','{"sub":"66666666-6666-4666-8666-666666666666","session_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',true);
 begin perform pg_temp.device('{"action":"claim"}'); raise exception 'Expected account/session isolation'; exception when insufficient_privilege then null; end;
end $$;
select pass('expiry, uncertain outcome, restart isolation, reset nulls, privacy, retention and account isolation');
-- Exercise the public API through its actual unprivileged role.
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"11111111-1111-4111-8111-111111111111","session_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',true);
select api_v1.pomodoist_app_settings_device('{"action":"claim","deviceId":"44444444-4444-4444-8444-444444444444","instanceId":"88888888-8888-4888-8888-888888888888"}');
reset role;
select pass('authenticated invoker wrapper reaches only its account-bound private dispatcher');
select * from finish();
rollback;
