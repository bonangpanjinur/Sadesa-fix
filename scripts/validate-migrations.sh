#!/usr/bin/env bash
set -euo pipefail

MIGRATIONS_DIR="${1:-supabase/bootstrap}"
if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "Migration directory not found: $MIGRATIONS_DIR" >&2
  exit 1
fi

mapfile -t files < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -printf '%f\n' | sort)
if (( ${#files[@]} == 0 )); then
  echo "No SQL migrations found" >&2
  exit 1
fi

failed=0
for file in "${files[@]}"; do
  if [[ "$MIGRATIONS_DIR" == "supabase/bootstrap" ]]; then
    valid_name='^[0-9]+_[0-9]{8}.*\.sql$'
  else
    valid_name='^[0-9]{8}([0-9]{6})?_[a-z0-9][a-z0-9_-]*\.sql$'
  fi
  if [[ ! "$file" =~ $valid_name ]]; then
    echo "ERROR invalid migration filename: $file" >&2
    failed=1
  fi
  if grep -nE '(^|[[:space:]])DROP[[:space:]]+(TABLE|SCHEMA|DATABASE)|TRUNCATE[[:space:]]' "$MIGRATIONS_DIR/$file" >/dev/null; then
    echo "ERROR destructive statement requires explicit review: $file" >&2
    grep -nE 'DROP[[:space:]]+(TABLE|SCHEMA|DATABASE)|TRUNCATE[[:space:]]' "$MIGRATIONS_DIR/$file" >&2 || true
    failed=1
  fi
done

if [[ "$MIGRATIONS_DIR" == "supabase/bootstrap" ]]; then
  duplicates=$(printf '%s\n' "${files[@]}" | sed -E 's/^([0-9]+)_.*/\1/' | sort | uniq -d || true)
else
  duplicates=$(printf '%s\n' "${files[@]}" | sed -E 's/^([0-9]{8})([0-9]{6})?_.*/\1\2/' | sort | uniq -d || true)
fi
if [[ -n "$duplicates" ]]; then
  echo "WARN duplicate timestamps (full filename order remains deterministic):" >&2
  while read -r stamp; do
    [[ -z "$stamp" ]] && continue
    printf '  %s\n' "$stamp"
    printf '%s\n' "${files[@]}" | grep -E "^${stamp}_" | sed 's/^/    /' >&2
  done <<< "$duplicates"
fi

if (( failed != 0 )); then
  exit 1
fi

echo "Validated ${#files[@]} SQL deployment files in lexical deployment order."
