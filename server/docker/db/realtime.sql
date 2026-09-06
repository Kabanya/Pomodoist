-- Adapted from Supabase self-hosting templates; modified for Pomodoist.
-- Copyright 2024 Supabase. See docker/NOTICE and docker/LICENSE.supabase.
\set pguser `echo "$POSTGRES_USER"`

create schema if not exists _realtime;
alter schema _realtime owner to :pguser;
