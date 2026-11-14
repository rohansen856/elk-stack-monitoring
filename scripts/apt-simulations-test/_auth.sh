#!/bin/bash
# Shared by the API-based simulations. Sourced, not executed.
#
# The /api/v1/security/* endpoints require a bearer token (AUDIT SEC-001), and
# /simulate/* is hard-disabled when ENVIRONMENT=production. These scripts used
# to call them anonymously, so after that fix every request got 401 and the
# simulations silently produced no events.
#
# Token source, in order:
#   1. SENTINEL_TOKEN
#   2. SENTINEL_EMAIL + SENTINEL_PASSWORD (logs in)
#   3. otherwise registers a throwaway simulation account and logs in

sentinel_login() {
  curl -s -X POST "$API_BASE/api/v1/users/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "username=$1" --data-urlencode "password=$2" |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null
}

if [ -z "${SENTINEL_TOKEN:-}" ]; then
  if [ -z "${SENTINEL_EMAIL:-}" ] || [ -z "${SENTINEL_PASSWORD:-}" ]; then
    suffix="$(date +%s)$RANDOM"
    SENTINEL_EMAIL="apt-sim-${suffix}@example.com"
    SENTINEL_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(18))')"
    curl -s -o /dev/null -X POST "$API_BASE/api/v1/users/register" \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$SENTINEL_EMAIL\",\"username\":\"aptsim_${suffix}\",\"password\":\"$SENTINEL_PASSWORD\"}"
  fi
  SENTINEL_TOKEN="$(sentinel_login "$SENTINEL_EMAIL" "$SENTINEL_PASSWORD")"
fi

if [ -z "$SENTINEL_TOKEN" ]; then
  echo "ERROR: could not obtain an API token from $API_BASE." >&2
  echo "       Set SENTINEL_TOKEN, or SENTINEL_EMAIL and SENTINEL_PASSWORD." >&2
  exit 1
fi

AUTH_HEADER="Authorization: Bearer $SENTINEL_TOKEN"
export SENTINEL_TOKEN AUTH_HEADER
