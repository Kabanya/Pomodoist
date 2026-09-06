#!/bin/sh
set -eu

server_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
env_file="$server_dir/.env"
example="$server_dir/.env.example"

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required" >&2
  exit 1
}

node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  major=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)
  [ -n "$major" ] && [ "$major" -ge 16 ] 2>/dev/null
}

if [ -e "$env_file" ]; then
  echo ".env already exists; leaving it unchanged" >&2
  exit 1
fi

base64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

random_base64() {
  openssl rand -base64 "$1" | tr -d '\n'
}

jwt_secret=$(openssl rand -hex 32)
now=$(date +%s)
expiry=$((now + 315360000))

make_jwt() {
  role=$1
  header=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | base64url)
  payload=$(printf '{"role":"%s","iss":"pomodoist-selfhost","iat":%s,"exp":%s}' "$role" "$now" "$expiry" | base64url)
  signature=$(printf '%s' "$header.$payload" | openssl dgst -binary -sha256 -hmac "$jwt_secret" | base64url)
  printf '%s.%s.%s' "$header" "$payload" "$signature"
}

postgres_password=$(openssl rand -hex 32)
anon_key=$(make_jwt anon)
service_role_key=$(make_jwt service_role)

key_script='const crypto = require("crypto");
const secret = process.argv[1];
const { privateKey } = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
const key = privateKey.export({ format: "jwk" });
const kid = crypto.randomUUID();
const legacy = { kty: "oct", k: Buffer.from(secret).toString("base64url"), alg: "HS256" };
const common = { kty: "EC", kid, use: "sig", alg: "ES256", ext: true,
  crv: key.crv, x: key.x, y: key.y };
const privateKeys = [{ ...common, key_ops: ["sign", "verify"], d: key.d }, legacy];
const publicKeys = [{ ...common, key_ops: ["verify"] }, legacy];
process.stdout.write("JWT_KEYS=" + JSON.stringify(privateKeys) + "\n");
process.stdout.write("JWT_JWKS=" + JSON.stringify({ keys: publicKeys }) + "\n");'

key_output=$(mktemp "${TMPDIR:-/tmp}/pomodoist-keys.XXXXXX")
trap 'rm -f "$key_output"' EXIT HUP INT TERM
if node_ok; then
  node -e "$key_script" "$jwt_secret" > "$key_output"
else
  command -v docker >/dev/null 2>&1 || {
    echo "Node.js 16+ or Docker is required to generate Auth signing keys" >&2
    exit 1
  }
  docker info >/dev/null 2>&1 || {
    echo "Docker must be running to generate Auth signing keys without Node.js 16+" >&2
    exit 1
  }
  docker pull node:22-alpine >/dev/null
  docker run --rm --name "pomodoist-selfhost-keygen-$$" node:22-alpine \
    node -e "$key_script" "$jwt_secret" > "$key_output"
fi
jwt_keys=$(sed -n 's/^JWT_KEYS=//p' "$key_output")
jwt_jwks=$(sed -n 's/^JWT_JWKS=//p' "$key_output")
[ -n "$jwt_keys" ] && [ -n "$jwt_jwks" ] || {
  echo "Failed to generate Auth signing keys" >&2
  exit 1
}
secret_key_base=$(random_base64 48)
realtime_db_enc_key=$(openssl rand -hex 8)
if [ -e "$server_dir/../.git" ] &&
  release=$(git -C "$server_dir/.." rev-parse --verify HEAD 2>/dev/null) &&
  printf '%s' "$release" | grep -Eq '^[0-9a-f]{40}$'; then
  :
else
  release=$(openssl rand -hex 20)
fi

tmp_file="$env_file.tmp.$$"
trap 'rm -f "$tmp_file"' EXIT HUP INT TERM
umask 077
awk \
  -v postgres_password="$postgres_password" \
  -v jwt_secret="$jwt_secret" \
  -v jwt_keys="$jwt_keys" \
  -v jwt_jwks="$jwt_jwks" \
  -v anon_key="$anon_key" \
  -v service_role_key="$service_role_key" \
  -v secret_key_base="$secret_key_base" \
  -v realtime_db_enc_key="$realtime_db_enc_key" \
  -v release="$release" '
  /^POSTGRES_PASSWORD=/ { print "POSTGRES_PASSWORD=" postgres_password; next }
  /^JWT_SECRET=/ { print "JWT_SECRET=" jwt_secret; next }
  /^JWT_KEYS=/ { print "JWT_KEYS=" jwt_keys; next }
  /^JWT_JWKS=/ { print "JWT_JWKS=" jwt_jwks; next }
  /^ANON_KEY=/ { print "ANON_KEY=" anon_key; next }
  /^SERVICE_ROLE_KEY=/ { print "SERVICE_ROLE_KEY=" service_role_key; next }
  /^SECRET_KEY_BASE=/ { print "SECRET_KEY_BASE=" secret_key_base; next }
  /^REALTIME_DB_ENC_KEY=/ { print "REALTIME_DB_ENC_KEY=" realtime_db_enc_key; next }
  /^POMODOIST_RELEASE=/ { print "POMODOIST_RELEASE=" release; next }
  { print }
' "$example" > "$tmp_file"
mv "$tmp_file" "$env_file"
rm -f "$key_output"
trap - EXIT HUP INT TERM

echo "Created server/.env with fresh secrets (mode 600)."
