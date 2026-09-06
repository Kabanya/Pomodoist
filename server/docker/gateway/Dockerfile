FROM kong/kong:3.9.3

COPY docker/NOTICE docker/LICENSE.supabase /usr/share/licenses/pomodoist/

COPY docker/gateway/kong.yml /home/kong/kong.yml.template
COPY docker/gateway/entrypoint.sh /home/kong/entrypoint.sh
ENTRYPOINT ["/bin/sh", "/home/kong/entrypoint.sh"]
