#!/bin/sh
set -eu

export LUA_AUTH_EXPR="\$((headers.authorization ~= nil and headers.authorization) or headers.apikey)"
export LUA_RT_WS_EXPR="\$(query_params.apikey)"

awk '{
  result = ""
  rest = $0
  while (match(rest, /\$[A-Za-z_][A-Za-z_0-9]*/)) {
    name = substr(rest, RSTART + 1, RLENGTH - 1)
    result = result substr(rest, 1, RSTART - 1) ENVIRON[name]
    rest = substr(rest, RSTART + RLENGTH)
  }
  print result rest
}' /home/kong/kong.yml.template > "$KONG_DECLARATIVE_CONFIG"

exec /entrypoint.sh kong docker-start
