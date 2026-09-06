FROM public.ecr.aws/supabase/postgres:17.6.1.127

COPY docker/NOTICE docker/LICENSE.supabase /usr/share/licenses/pomodoist/

COPY docker/db/realtime.sql /docker-entrypoint-initdb.d/migrations/99-realtime.sql
COPY docker/db/roles.sql /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
COPY docker/db/jwt.sql /docker-entrypoint-initdb.d/init-scripts/99-jwt.sql
