#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${LOAD_TEST_BASE_URL:-}"
REQUESTS="${LOAD_TEST_REQUESTS:-60}"
CONCURRENCY="${LOAD_TEST_CONCURRENCY:-10}"
TIMEOUT="${LOAD_TEST_TIMEOUT_SECONDS:-10}"
CONFIRM="${LOAD_TEST_CONFIRM_STAGING:-}"

if [[ -z "$BASE_URL" ]]; then
  echo "Set LOAD_TEST_BASE_URL to a staging Supabase URL" >&2
  exit 1
fi
if [[ "$CONFIRM" != "YES_I_CONFIRM_STAGING" ]]; then
  echo "Refusing load test: set LOAD_TEST_CONFIRM_STAGING=YES_I_CONFIRM_STAGING" >&2
  exit 1
fi
if [[ "$BASE_URL" =~ (production|prod\.supabase\.co|\.railway\.app$) ]] && [[ "${ALLOW_EXPLICIT_STAGING_HOST:-0}" != "1" ]]; then
  echo "Refusing ambiguous/non-staging host: $BASE_URL" >&2
  exit 1
fi
if ! [[ "$REQUESTS" =~ ^[1-9][0-9]*$ && "$CONCURRENCY" =~ ^[1-9][0-9]*$ ]]; then
  echo "REQUESTS and CONCURRENCY must be positive integers" >&2
  exit 1
fi
if (( CONCURRENCY > REQUESTS )); then CONCURRENCY="$REQUESTS"; fi

endpoints=(
  "/functions/v1/xendit-webhook"
  "/functions/v1/process-notification-queue"
  "/functions/v1/process-subscription-events"
  "/functions/v1/admin-create-user"
)
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

run_one() {
  local endpoint="$1" index="$2" url="$BASE_URL$endpoint" out="$workdir/$index"
  local result
  result=$(curl -sS -o /dev/null -w '%{http_code} %{time_total}' --max-time "$TIMEOUT" \
    -X POST -H 'content-type: application/json' --data '{}' "$url" 2>&1) || result="000 0 $result"
  printf '%s\t%s\n' "$endpoint" "$result" > "$out"
}
export BASE_URL TIMEOUT workdir
export -f run_one

start="$(date +%s)"
index=0
for endpoint in "${endpoints[@]}"; do
  for ((i=1; i<=REQUESTS; i++)); do
    run_one "$endpoint" "$index" &
    ((index+=1))
    while (( $(jobs -rp | wc -l) >= CONCURRENCY )); do wait -n || true; done
  done
done
wait || true
elapsed=$(( $(date +%s) - start ))

awk -F '\t' '
function bucket(code) { if (code ~ /^2/) return "2xx"; if (code ~ /^3/) return "3xx"; if (code ~ /^4/) return "4xx"; if (code ~ /^5/) return "5xx"; return "transport" }
{ split($2, parts, " "); code=parts[1]; time=parts[2]+0; total[$1]++; classes[$1, bucket(code)]++; sum[$1]+=time; if (time > max[$1]) max[$1]=time; if (code == "000") failures[$1]++ }
END { print "endpoint requests 2xx 3xx 4xx 5xx transport avg_seconds max_seconds transport_failures"; for (endpoint in total) printf "%s %d %d %d %d %d %d %.3f %.3f %d\n", endpoint,total[endpoint],classes[endpoint,"2xx"],classes[endpoint,"3xx"],classes[endpoint,"4xx"],classes[endpoint,"5xx"],classes[endpoint,"transport"],sum[endpoint]/total[endpoint],max[endpoint],failures[endpoint]+0 }
' "$workdir"/* | sort

echo "Elapsed seconds: $elapsed"
echo "This test intentionally sends unauthenticated empty payloads. It validates edge auth/method/error handling and transport behavior, not successful payment or database transactions. Use dedicated staging fixtures for authenticated RPC/load tests."
