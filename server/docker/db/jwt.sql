-- Adapted from Supabase self-hosting templates; modified for Pomodoist.
-- Copyright 2024 Supabase. See docker/NOTICE and docker/LICENSE.supabase.
\set jwt_secret `echo "$JWT_SECRET"`
\set jwt_exp `echo "$JWT_EXP"`

alter database postgres set "app.settings.jwt_secret" to :'jwt_secret';
alter database postgres set "app.settings.jwt_exp" to :'jwt_exp';
