-- Device settings RPCs use api_v1 on hosted PostgREST as well as local Supabase.
alter role authenticator set pgrst.db_schemas = 'public, graphql_public, api_v1';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';
