begin;
\ir hosted-mode.inc

select plan(50);

create function pg_temp.oauth_claims_for_issuer(p_issuer text)
returns jsonb language sql as $$
  select private.pomodoist_mcp_access_token_hook(jsonb_build_object(
    'user_id', '11111111-1111-4111-8111-111111111111',
    'claims', jsonb_build_object(
      'iss', p_issuer, 'client_id', '22222222-2222-4222-8222-222222222222'
    )
  ));
$$;
select is(pg_temp.oauth_claims_for_issuer('http://localhost:8000/auth/v1') #>> '{claims,aud}',
  'http://localhost:8000/functions/v1/pomodoist-mcp', 'MCP OAuth permits exact loopback host http://localhost:8000');
select is(pg_temp.oauth_claims_for_issuer('http://127.0.0.1:8000/auth/v1') #>> '{claims,aud}',
  'http://127.0.0.1:8000/functions/v1/pomodoist-mcp', 'MCP OAuth permits exact loopback host http://127.0.0.1:8000');
select is(pg_temp.oauth_claims_for_issuer('http://[::1]:8000/auth/v1') #>> '{claims,aud}',
  'http://[::1]:8000/functions/v1/pomodoist-mcp', 'MCP OAuth permits exact loopback host http://[::1]:8000');
select throws_ok($$select pg_temp.oauth_claims_for_issuer('http://remote.example.test/auth/v1')$$,
  '22023', 'Invalid OAuth issuer', 'MCP OAuth rejects http://remote.example.test');
select throws_ok($$select pg_temp.oauth_claims_for_issuer('http://localhost.evil.test/auth/v1')$$,
  '22023', 'Invalid OAuth issuer', 'MCP OAuth rejects http://localhost.evil.test');
select throws_ok($$select pg_temp.oauth_claims_for_issuer('http://127.0.0.10/auth/v1')$$,
  '22023', 'Invalid OAuth issuer', 'MCP OAuth rejects http://127.0.0.10');
select throws_ok($$select pg_temp.oauth_claims_for_issuer('http://[::1].evil.test/auth/v1')$$,
  '22023', 'Invalid OAuth issuer', 'MCP OAuth rejects http://[::1].evil.test');


insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '11111111-1111-4111-8111-111111111111',
  'mcp-policy-test@example.com',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into auth.oauth_clients (
  id,
  registration_type,
  redirect_uris,
  grant_types,
  client_name,
  client_type,
  token_endpoint_auth_method
)
values (
  '22222222-2222-4222-8222-222222222222',
  'dynamic',
  '["https://client.example/callback"]',
  '["authorization_code","refresh_token"]',
  'Pomodoist MCP policy test',
  'public',
  'none'
);

insert into auth.sessions (
  id,
  user_id,
  created_at,
  updated_at,
  not_after,
  oauth_client_id,
  scopes
)
values
  (
    '33333333-3333-4333-8333-333333333333',
    '11111111-1111-4111-8111-111111111111',
    now(),
    now(),
    now() + interval '1 hour',
    '22222222-2222-4222-8222-222222222222',
    'email'
  ),
  (
    '44444444-4444-4444-8444-444444444444',
    '11111111-1111-4111-8111-111111111111',
    now(),
    now(),
    now() - interval '1 second',
    '22222222-2222-4222-8222-222222222222',
    'email'
  ),
  (
    '55555555-5555-4555-8555-555555555555',
    '11111111-1111-4111-8111-111111111111',
    now(),
    now(),
    now() + interval '1 hour',
    '22222222-2222-4222-8222-222222222222',
    'email'
  );

create temporary table mcp_hook_test (
  ordinary_claims jsonb not null,
  oauth_claims jsonb not null
) on commit drop;

insert into mcp_hook_test (ordinary_claims, oauth_claims)
select
  private.pomodoist_mcp_access_token_hook(
    jsonb_build_object(
      'user_id', '11111111-1111-4111-8111-111111111111',
      'claims', jsonb_build_object(
        'iss', 'https://sync.example.test/auth/v1',
        'aud', 'authenticated',
        'exp', 2000000000,
        'iat', 1900000000,
        'sub', '11111111-1111-4111-8111-111111111111',
        'role', 'authenticated',
        'aal', 'aal1',
        'session_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'email', 'flutter@example.com',
        'phone', '+79990000000',
        'is_anonymous', false,
        'app_metadata', jsonb_build_object('provider', 'email'),
        'user_metadata', jsonb_build_object('display_name', 'Flutter User')
      ),
      'authentication_method', 'password'
    )
  )->'claims',
  private.pomodoist_mcp_access_token_hook(
    jsonb_build_object(
      'user_id', '11111111-1111-4111-8111-111111111111',
      'claims', jsonb_build_object(
        'iss', 'https://sync.example.test/auth/v1',
        'aud', 'authenticated',
        'exp', 2000000000,
        'iat', 1900000000,
        'sub', '11111111-1111-4111-8111-111111111111',
        'role', 'authenticated',
        'aal', 'aal1',
        'session_id', '33333333-3333-4333-8333-333333333333',
        'client_id', '22222222-2222-4222-8222-222222222222',
        'scope', 'email',
        'email', 'private@example.com',
        'phone', '+79990000000',
        'is_anonymous', false,
        'app_metadata', jsonb_build_object('provider', 'google', 'plan', 'paid'),
        'user_metadata', jsonb_build_object('name', 'Private Name'),
        'amr', jsonb_build_array(jsonb_build_object('method', 'oauth')),
        'jti', 'personal-token-id'
      ),
      'authentication_method', 'oauth'
    )
  )->'claims';

select is(
  ordinary_claims,
  jsonb_build_object(
    'iss', 'https://sync.example.test/auth/v1',
    'aud', 'authenticated',
    'exp', 2000000000,
    'iat', 1900000000,
    'sub', '11111111-1111-4111-8111-111111111111',
    'role', 'authenticated',
    'aal', 'aal1',
    'session_id', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'email', 'flutter@example.com',
    'phone', '+79990000000',
    'is_anonymous', false,
    'app_metadata', jsonb_build_object('provider', 'email'),
    'user_metadata', jsonb_build_object('display_name', 'Flutter User')
  ),
  'ordinary Flutter claims are unchanged'
) from mcp_hook_test;

select is(
  private.pomodoist_mcp_subject(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  'd8fbd65d-9859-51ed-992b-8e7bec31fc58'::uuid,
  'pseudonym uses the stable reviewed UUIDv5 input'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'private.pomodoist_mcp_subject(uuid,uuid)'::regprocedure
  ),
  true,
  'pseudonym helper can use UUIDv5 without granting Auth the extensions schema'
);

select is(
  private.pomodoist_mcp_subject(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  private.pomodoist_mcp_subject(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  'pseudonym is deterministic'
);

select isnt(
  private.pomodoist_mcp_subject(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222'
  ),
  private.pomodoist_mcp_subject(
    '11111111-1111-4111-8111-111111111111',
    '99999999-9999-4999-8999-999999999999'
  ),
  'pseudonym is isolated per OAuth client'
);

select is(oauth_claims->>'role', 'pomodoist_mcp', 'OAuth role is exact')
from mcp_hook_test;
select is(
  oauth_claims->>'aud',
  'https://sync.example.test/functions/v1/pomodoist-mcp',
  'OAuth audience is derived exactly from the issuer'
) from mcp_hook_test;
select is(
  private.pomodoist_mcp_access_token_hook(
    jsonb_build_object(
      'user_id', '11111111-1111-4111-8111-111111111111',
      'claims', jsonb_build_object(
        'iss', 'https://another.example.test/auth/v1',
        'client_id', '22222222-2222-4222-8222-222222222222'
      )
    )
  )->'claims'->>'aud',
  'https://another.example.test/functions/v1/pomodoist-mcp',
  'production OAuth audience uses the operator-controlled MCP origin'
);
select is(
  oauth_claims->>'sub',
  'd8fbd65d-9859-51ed-992b-8e7bec31fc58',
  'OAuth subject is pseudonymous'
) from mcp_hook_test;
select is(
  oauth_claims->>'session_id',
  '33333333-3333-4333-8333-333333333333',
  'signed session ID is preserved'
) from mcp_hook_test;
select is(
  oauth_claims->>'client_id',
  '22222222-2222-4222-8222-222222222222',
  'signed OAuth client ID is preserved'
) from mcp_hook_test;
select is(oauth_claims->>'scope', 'email', 'non-forbidden scope is preserved')
from mcp_hook_test;
select is(oauth_claims->>'email', '', 'required email claim is cleared')
from mcp_hook_test;
select is(oauth_claims->>'phone', '', 'required phone claim is cleared')
from mcp_hook_test;
select ok(
  not oauth_claims ?| array[
    'app_metadata',
    'user_metadata',
    'amr',
    'jti',
    'name',
    'picture',
    'email_verified',
    'phone_number'
  ],
  'optional personal claims are stripped'
) from mcp_hook_test;

select throws_ok(
  $query$
    select private.pomodoist_mcp_access_token_hook(
      '{"user_id":"11111111-1111-4111-8111-111111111111","claims":{"client_id":"22222222-2222-4222-8222-222222222222","iss":"https://example.com/auth/v1","scope":"email openid"}}'
    )
  $query$,
  '22023',
  'MCP OAuth scope is not permitted',
  'openid scope is rejected'
);
select throws_ok(
  $query$
    select private.pomodoist_mcp_access_token_hook(
      '{"user_id":"11111111-1111-4111-8111-111111111111","claims":{"client_id":"22222222-2222-4222-8222-222222222222","iss":"https://example.com/auth/v1","scope":"profile"}}'
    )
  $query$,
  '22023',
  'MCP OAuth scope is not permitted',
  'profile scope is rejected'
);
select throws_ok(
  $query$
    select private.pomodoist_mcp_access_token_hook(
      '{"user_id":"11111111-1111-4111-8111-111111111111","claims":{"client_id":"22222222-2222-4222-8222-222222222222","iss":"https://example.com/auth/v1","scope":"phone"}}'
    )
  $query$,
  '22023',
  'MCP OAuth scope is not permitted',
  'phone scope is rejected'
);
select throws_ok(
  $query$
    select private.pomodoist_mcp_access_token_hook(
      '{"user_id":"11111111-1111-4111-8111-111111111111","claims":{"client_id":"22222222-2222-4222-8222-222222222222","iss":"http://example.com/auth/v1"}}'
    )
  $query$,
  '22023',
  'Invalid OAuth issuer',
  'non-HTTPS issuer is rejected'
);
select throws_ok(
  $query$
    select private.pomodoist_mcp_access_token_hook(
      '{"user_id":"11111111-1111-4111-8111-111111111111","claims":{"client_id":"22222222-2222-4222-8222-222222222222","iss":"https://example.com/auth/v1?tenant=other"}}'
    )
  $query$,
  '22023',
  'Invalid OAuth issuer',
  'issuer with a query suffix is rejected'
);

select ok(exists(
  select 1 from pg_roles
  where rolname = 'pomodoist_mcp'
    and not rolcanlogin
    and not rolinherit
    and not rolsuper
    and not rolcreatedb
    and not rolcreaterole
    and not rolreplication
    and not rolbypassrls
), 'MCP role has only the reviewed NOLOGIN flags');
select ok(
  pg_has_role('authenticator', 'pomodoist_mcp', 'MEMBER'),
  'PostgREST authenticator can select the MCP JWT role'
);
select ok(
  not has_schema_privilege('pomodoist_mcp', 'public', 'USAGE'),
  'MCP role cannot access public RPCs or tables'
);
select ok(
  not has_schema_privilege('pomodoist_mcp', 'private', 'USAGE'),
  'MCP role cannot access private implementation objects'
);
select ok(
  not has_table_privilege('pomodoist_mcp', 'auth.users', 'SELECT'),
  'MCP role cannot read Auth users'
);
select ok(
  not has_table_privilege('pomodoist_mcp', 'public.sync_entities', 'SELECT')
  and not has_table_privilege('pomodoist_mcp', 'public.sync_operations', 'SELECT'),
  'MCP role has no sync table access'
);
select ok(
  not has_schema_privilege('pomodoist_mcp', 'auth', 'USAGE')
  and not has_schema_privilege('pomodoist_mcp', 'storage', 'USAGE')
  and not has_schema_privilege('pomodoist_mcp', 'graphql_public', 'USAGE'),
  'MCP role cannot reach other exposed or Auth schemas'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.resolve_pomodoist_mcp_session(uuid,uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.resolve_pomodoist_mcp_session(uuid,uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.resolve_pomodoist_mcp_session(uuid,uuid,uuid)',
    'EXECUTE'
  ),
  'session resolver is service-role-only'
);
select ok(
  has_function_privilege(
    'service_role',
    'public.consume_pomodoist_mcp_rate_limit(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.consume_pomodoist_mcp_rate_limit(uuid,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.consume_pomodoist_mcp_rate_limit(uuid,uuid)',
    'EXECUTE'
  ),
  'rate-limit RPC is service-role-only'
);

select is(
  public.resolve_pomodoist_mcp_session(
    'd8fbd65d-9859-51ed-992b-8e7bec31fc58',
    '33333333-3333-4333-8333-333333333333',
    '22222222-2222-4222-8222-222222222222'
  ),
  '11111111-1111-4111-8111-111111111111'::uuid,
  'active matching OAuth session resolves the real user'
);
select is(
  public.resolve_pomodoist_mcp_session(
    '99999999-9999-4999-8999-999999999999',
    '33333333-3333-4333-8333-333333333333',
    '22222222-2222-4222-8222-222222222222'
  ),
  null::uuid,
  'subject mismatch resolves no user'
);
select is(
  public.resolve_pomodoist_mcp_session(
    'd8fbd65d-9859-51ed-992b-8e7bec31fc58',
    '99999999-9999-4999-8999-999999999999',
    '22222222-2222-4222-8222-222222222222'
  ),
  null::uuid,
  'session mismatch resolves no user'
);
select is(
  public.resolve_pomodoist_mcp_session(
    'd8fbd65d-9859-51ed-992b-8e7bec31fc58',
    '33333333-3333-4333-8333-333333333333',
    '99999999-9999-4999-8999-999999999999'
  ),
  null::uuid,
  'client mismatch resolves no user'
);
select is(
  public.resolve_pomodoist_mcp_session(
    'd8fbd65d-9859-51ed-992b-8e7bec31fc58',
    '44444444-4444-4444-8444-444444444444',
    '22222222-2222-4222-8222-222222222222'
  ),
  null::uuid,
  'expired session resolves no user'
);

delete from auth.sessions
where id = '55555555-5555-4555-8555-555555555555';

select is(
  public.resolve_pomodoist_mcp_session(
    'd8fbd65d-9859-51ed-992b-8e7bec31fc58',
    '55555555-5555-4555-8555-555555555555',
    '22222222-2222-4222-8222-222222222222'
  ),
  null::uuid,
  'revoked session row resolves no user'
);

create temporary table mcp_rate_results (
  attempt integer not null,
  allowed boolean not null,
  retry_after_seconds integer
) on commit drop;

do $$
begin
  for i in 1..121 loop
    insert into mcp_rate_results
    select i, result.allowed, result.retry_after_seconds
    from public.consume_pomodoist_mcp_rate_limit(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222'
    ) as result;
  end loop;
end;
$$;

select ok(
  (select bool_and(allowed) from mcp_rate_results where attempt < 120),
  'first 119 calls are allowed'
);
select ok(
  (select allowed from mcp_rate_results where attempt = 120),
  '120th call is allowed'
);
select ok(
  not (select allowed from mcp_rate_results where attempt = 121),
  '121st call in 60 seconds is denied'
);
select ok(
  (select retry_after_seconds between 1 and 60
   from mcp_rate_results where attempt = 121),
  'denied call returns bounded retry-after seconds'
);
select is(
  (
    select count(*)::integer
    from private.pomodoist_mcp_rate_limits
    where user_id = '11111111-1111-4111-8111-111111111111'
      and client_id = '22222222-2222-4222-8222-222222222222'
  ),
  1,
  'fixed window keeps one row per user and client'
);

update private.pomodoist_mcp_rate_limits
set window_started_at = now() - interval '60 seconds'
where user_id = '11111111-1111-4111-8111-111111111111'
  and client_id = '22222222-2222-4222-8222-222222222222';

select ok(
  (
    select allowed
    from public.consume_pomodoist_mcp_rate_limit(
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222'
    )
  ),
  'window resets at 60 seconds'
);
select is(
  (
    select call_count
    from private.pomodoist_mcp_rate_limits
    where user_id = '11111111-1111-4111-8111-111111111111'
      and client_id = '22222222-2222-4222-8222-222222222222'
  ),
  1,
  'reset window starts again at one call'
);
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'private.pomodoist_mcp_rate_limits'::regclass
  ),
  'private rate-limit table has RLS defense in depth'
);

select * from finish();
rollback;
