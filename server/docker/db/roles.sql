-- Adapted from Supabase self-hosting templates; modified for Pomodoist.
-- Copyright 2024 Supabase. See docker/NOTICE and docker/LICENSE.supabase.
\set pgpass `echo "$POSTGRES_PASSWORD"`

alter user authenticator with password :'pgpass';
alter user supabase_auth_admin with password :'pgpass';
alter user supabase_admin with password :'pgpass';
