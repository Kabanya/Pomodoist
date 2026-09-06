#!/bin/sh
set -eu

server_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
repository_dir=$(CDPATH= cd -- "$server_dir/.." && pwd)
env_file="$server_dir/.env"

[ -f "$env_file" ] || {
  echo "Run make setup first" >&2
  exit 1
}

release_count=$(grep -c '^POMODOIST_RELEASE=' "$env_file" || true)
[ "$release_count" -eq 1 ] || {
  echo "server/.env must contain exactly one POMODOIST_RELEASE value" >&2
  exit 1
}
current_release=$(sed -n 's/^POMODOIST_RELEASE=//p' "$env_file")

release=
if [ -e "$repository_dir/.git" ] && command -v git >/dev/null 2>&1; then
  release=$(git -C "$repository_dir" rev-parse --verify HEAD 2>/dev/null || true)
fi
if ! printf '%s' "$release" | grep -Eq '^[0-9a-f]{40}$'; then
  release=$current_release
fi
printf '%s' "$release" | grep -Eq '^[0-9a-f]{40}$' || {
  echo "POMODOIST_RELEASE must be a full lowercase Git revision" >&2
  exit 1
}

tmp_file=$(mktemp "$env_file.tmp.XXXXXX")
trap 'rm -f "$tmp_file"' EXIT HUP INT TERM
umask 077
awk -v release="$release" '
  /^POMODOIST_RELEASE=/ { print "POMODOIST_RELEASE=" release; next }
  { print }
' "$env_file" > "$tmp_file"
chmod 600 "$tmp_file"
mv "$tmp_file" "$env_file"
trap - EXIT HUP INT TERM

echo "Updated server release metadata."
