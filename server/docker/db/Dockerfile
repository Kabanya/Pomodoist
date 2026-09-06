FROM docker.io/supabase/postgres:17.6.1.127@sha256:be60aee15997daca475b710b734bc6bfe52cd544dcd7e9fd2ff58210b6747d83

COPY docker/NOTICE docker/LICENSE.supabase /usr/share/licenses/pomodoist/

COPY docker/db/realtime.sql /docker-entrypoint-initdb.d/migrations/99-realtime.sql
COPY docker/db/roles.sql /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
COPY docker/db/jwt.sql /docker-entrypoint-initdb.d/init-scripts/99-jwt.sql
