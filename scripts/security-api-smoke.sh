#!/usr/bin/env bash
set -Eeuo pipefail

# Safe-by-default API security smoke test for Supabase Edge Functions.
# Required: SUPABASE_TEST_URL, SUPABASE_TEST_ANON_KEY, SECURITY_TEST_ALLOWED_ORIGIN
# Optional: SECURITY_TEST_ACCESS_TOKEN, SECURITY_TEST_FUNCTIONS, SECURITY_TEST_REQUESTS

BASE_URL="${SUPABASE_TEST_URL:-}"
ANON_KEY="${SUPABASE_TEST_ANON_KEY:-}"
ALLOWED_ORIGIN="${SECURITY_TEST_ALLOWED_ORIGIN:-}"
BAD_ORIGIN="${SECURITY_TEST_BAD_ORIGIN:-https://security-test-invalid.example}"
ACCESS_TOKEN="${SECURITY_TEST_ACCESS_TOKEN:-}"
REQUESTS="${SECURITY_TEST_REQUESTS:-20}"
REQUIRE_RATE_LIMIT="${SECURITY_TEST_REQUIRE_RATE_LIMIT:-0}"
FUNCTIONS="${SECURITY_TEST_FUNCTIONS:-assign-courier send-push-notification admin-create-user xendit-payment}"

failures=0
warnings=0

log() { printf '[security-api] %s\n' "$*"; }
fail() { log "FAIL: $*"; failures=$((failures + 1)); }
warn() { log "WARN: $*"; warnings=$((warnings + 1)); }
pass() { log "PASS: $*"; }

require_value() {
  local name="$1" value="$2"
  [[ -n "$value" ]] || { log "Missing required variable: $name"; exit 2; }
}

require_value SUPABASE_TEST_URL "$BASE_URL"
require_value SUPABASE_TEST_ANON_KEY "$ANON_KEY"
require_value SECURITY_TEST_ALLOWED_ORIGIN "$ALLOWED_ORIGIN"

BASE_URL="${BASE_URL%/}"
if [[ ! "$BASE_URL" =~ (staging|stage|localhost|127\.0\.0\.1|test) ]]; then
  if [[ "${SECURITY_TEST_ALLOW_NONSTAGING:-0}" != "1" ]]; then
    log "Refusing non-staging target: $BASE_URL"
    log "Use a staging/test URL or explicitly set SECURITY_TEST_ALLOW_NONSTAGING=1."
    exit 2
  fi
  warn "Non-staging target explicitly allowed; do not use production credentials."
fi

[[ "$REQUESTS" =~ ^[1-9][0-9]*$ ]] || { log "SECURITY_TEST_REQUESTS must be a positive integer"; exit 2; }
(( REQUESTS <= 100 )) || { log "SECURITY_TEST_REQUESTS must be <= 100"; exit 2; }

curl_json() {
  local url="$1" method="$2" origin="$3" auth="$4" body="${5:-}"
  local -a args=(--silent --show-error --max-time 15 --connect-timeout 5 -X "$method" "$url"
    -H "apikey: $ANON_KEY" -H "Origin: $origin" -H "Accept: application/json" -D -)
  [[ -n "$auth" ]] && args+=( -H "Authorization: Bearer $auth" )
  [[ -n "$body" ]] && args+=( -H "Content-Type: application/json" --data "$body" )
  curl "${args[@]}"
}

status_code() { awk 'NR==1 { print $2; exit }' <<<"$1"; }
header_value() { awk -F': ' -v key="${2,,}" 'tolower($1)==key {gsub("\r", "", $2); print $2; exit}' <<<"$1"; }

for function_name in $FUNCTIONS; do
  endpoint="$BASE_URL/functions/v1/$function_name"
  log "Testing $function_name"

  preflight="$(curl_json "$endpoint" OPTIONS "$ALLOWED_ORIGIN" '' '')" || { fail "$function_name preflight request failed"; continue; }
  preflight_status="$(status_code "$preflight")"
  preflight_origin="$(header_value "$preflight" access-control-allow-origin)"
  [[ "$preflight_status" == "204" || "$preflight_status" == "200" ]] || fail "$function_name allowed preflight returned HTTP $preflight_status"
  [[ "$preflight_origin" == "$ALLOWED_ORIGIN" ]] || fail "$function_name allowed origin mismatch"
  [[ "$(header_value "$preflight" vary)" == *Origin* ]] || warn "$function_name preflight does not advertise Vary: Origin"

  blocked="$(curl_json "$endpoint" OPTIONS "$BAD_ORIGIN" '' '')" || { fail "$function_name blocked preflight request failed"; continue; }
  blocked_origin="$(header_value "$blocked" access-control-allow-origin)"
  [[ -z "$blocked_origin" || "$blocked_origin" != "$BAD_ORIGIN" ]] || fail "$function_name reflects disallowed origin"

  unauth="$(curl_json "$endpoint" POST "$ALLOWED_ORIGIN" '' '{}')" || { fail "$function_name unauthenticated request failed"; continue; }
  unauth_status="$(status_code "$unauth")"
  [[ "$unauth_status" == "401" || "$unauth_status" == "403" ]] || fail "$function_name unauthenticated request returned HTTP $unauth_status"

  invalid="$(curl_json "$endpoint" POST "$ALLOWED_ORIGIN" 'definitely-invalid-token' '{}')" || { fail "$function_name invalid-token request failed"; continue; }
  invalid_status="$(status_code "$invalid")"
  [[ "$invalid_status" == "401" || "$invalid_status" == "403" ]] || fail "$function_name invalid token returned HTTP $invalid_status"

  if [[ -n "$ACCESS_TOKEN" ]]; then
    authenticated="$(curl_json "$endpoint" POST "$ALLOWED_ORIGIN" "$ACCESS_TOKEN" '{}')" || { fail "$function_name authenticated validation request failed"; continue; }
    authenticated_status="$(status_code "$authenticated")"
    [[ "$authenticated_status" != "500" ]] || fail "$function_name returned internal error for safe invalid payload"
  else
    warn "$function_name authenticated test skipped: SECURITY_TEST_ACCESS_TOKEN is unset"
  fi

done

# Rate-limit observation uses harmless unauthenticated POST requests. A provider or
# gateway may enforce rate limits outside the function; this test only reports what it observes.
rate_endpoint="$BASE_URL/functions/v1/${SECURITY_TEST_RATE_LIMIT_FUNCTION:-assign-courier}"
rate_limited=0
for ((i=1; i<=REQUESTS; i++)); do
  response="$(curl_json "$rate_endpoint" POST "$ALLOWED_ORIGIN" '' '{}')" || continue
  code="$(status_code "$response")"
  if [[ "$code" == "429" ]]; then rate_limited=1; break; fi
done
if (( rate_limited == 1 )); then
  pass "rate limiting observed with HTTP 429"
elif [[ "$REQUIRE_RATE_LIMIT" == "1" ]]; then
  fail "rate limiting was not observed after $REQUESTS harmless requests"
else
  warn "rate limiting was not observed after $REQUESTS requests; set SECURITY_TEST_REQUIRE_RATE_LIMIT=1 to make this a hard failure"
fi

if (( failures > 0 )); then
  log "Completed with $failures failure(s) and $warnings warning(s)."
  exit 1
fi
log "Completed successfully with $warnings warning(s)."
