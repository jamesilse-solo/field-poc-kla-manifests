#!/usr/bin/env bash
# gen-token.sh — mint demo JWTs signed with the demo RSA private key
# Usage: ./gen-token.sh <username>   (alice | bob | charlie | admin)
# Output: JWT token string (stdout)
# Demo-only key pair — do not use in production

set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="${DEMO_DIR}/certs/demo-jwt.key"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "ERROR: Demo key not found at $KEY_FILE. Run 00-preflight.sh first." >&2
  exit 1
fi

USERNAME="${1:-alice}"
NOW=$(date +%s)
EXP=$((NOW + 3600))

case "$USERNAME" in
  alice)
    TIER="premium"
    EMAIL="alice@kla.com"
    NAME="Alice KLA"
    ;;
  bob)
    TIER="standard"
    EMAIL="bob@kla.com"
    NAME="Bob KLA"
    ;;
  charlie)
    TIER="free"
    EMAIL="charlie@kla.com"
    NAME="Charlie KLA"
    ;;
  admin)
    TIER="admin"
    EMAIL="admin@kla.com"
    NAME="Admin KLA"
    ;;
  *)
    echo "ERROR: Unknown user '$USERNAME'. Use alice, bob, charlie, or admin." >&2
    exit 1
    ;;
esac

b64url() {
  echo -n "$1" | base64 | tr '+/' '-_' | tr -d '=\n'
}

HEADER=$(b64url '{"alg":"RS256","typ":"JWT","kid":"kla-demo-key-2026"}')
PAYLOAD=$(b64url "{\"sub\":\"${USERNAME}\",\"iss\":\"http://dex.dex.svc.cluster.local:5556\",\"aud\":\"kla-demo-client\",\"preferred_username\":\"${USERNAME}\",\"email\":\"${EMAIL}\",\"name\":\"${NAME}\",\"org\":\"kla\",\"tier\":\"${TIER}\",\"iat\":${NOW},\"exp\":${EXP}}")

SIG=$(printf '%s' "${HEADER}.${PAYLOAD}" | openssl dgst -sha256 -sign "$KEY_FILE" | base64 | tr '+/' '-_' | tr -d '=\n')

echo "${HEADER}.${PAYLOAD}.${SIG}"
