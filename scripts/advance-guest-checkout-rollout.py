#!/usr/bin/env python3
"""Advance guest checkout rollout by one configured step.

Required environment:
  SUPABASE_URL or VITE_SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

The script is safe to run repeatedly on the same day: it records
_rollout.last_advanced_on in app_settings.value and will not advance twice
for the same UTC date unless --force is supplied.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from typing import NoReturn
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

FLAG_KEY = "guest_checkout_enabled"
DEFAULT_STEPS = (0, 1, 5, 10, 25, 50, 75, 100)


def fail(message: str) -> "NoReturn":
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def request_json(url: str, key: str, method: str = "GET", body: object | None = None) -> object:
    payload = None if body is None else json.dumps(body, separators=(",", ":")).encode()
    request = Request(
        url,
        method=method,
        data=payload,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
    )
    try:
        with urlopen(request, timeout=20) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else None
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:500]
        fail(f"Supabase request failed ({error.code}): {detail}")
    except URLError as error:
        fail(f"Supabase request could not be reached: {error.reason}")


def parse_steps(raw: str) -> tuple[int, ...]:
    try:
        steps = tuple(sorted({int(part.strip()) for part in raw.split(",") if part.strip()}))
    except ValueError:
        fail("--steps must be a comma-separated list of integers")
    if not steps or steps[0] != 0 or any(step < 0 or step > 100 for step in steps):
        fail("--steps must include 0 and contain only values from 0 to 100")
    return steps


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--steps", default=",".join(map(str, DEFAULT_STEPS)), help="ordered rollout percentages")
    parser.add_argument("--max-percent", type=int, default=100, help="maximum percentage this job may reach")
    parser.add_argument("--dry-run", action="store_true", help="show the next change without writing it")
    parser.add_argument("--force", action="store_true", help="allow another advancement on the same UTC date")
    args = parser.parse_args()

    if not 0 <= args.max_percent <= 100:
        fail("--max-percent must be between 0 and 100")
    steps = parse_steps(args.steps)
    allowed_steps = tuple(step for step in steps if step <= args.max_percent)
    if not allowed_steps:
        fail("--max-percent is below the first configured rollout step")

    base_url = (os.environ.get("SUPABASE_URL") or os.environ.get("VITE_SUPABASE_URL") or "").rstrip("/")
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not base_url or not service_key:
        fail("SUPABASE_URL/VITE_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")

    endpoint = f"{base_url}/rest/v1/app_settings?key=eq.{FLAG_KEY}&select=key,value,updated_at"
    rows = request_json(endpoint, service_key)
    if not isinstance(rows, list) or len(rows) != 1:
        fail(f"expected exactly one {FLAG_KEY} setting, got {len(rows) if isinstance(rows, list) else 'invalid response'}")
    row = rows[0]
    current = row.get("value") if isinstance(row, dict) else None
    if not isinstance(current, dict):
        fail("feature flag value must be a JSON object")
    if current.get("enabled") is not True:
        print(f"NOOP: {FLAG_KEY} is disabled; no rollout change was made")
        return 0

    current_percent = current.get("rollout_percent", 0)
    if not isinstance(current_percent, (int, float)) or isinstance(current_percent, bool):
        fail("rollout_percent must be numeric")
    current_percent = int(current_percent)
    if current_percent < 0 or current_percent > 100:
        fail("current rollout_percent must be between 0 and 100")

    today = datetime.now(timezone.utc).date().isoformat()
    metadata = current.get("_rollout") if isinstance(current.get("_rollout"), dict) else {}
    if metadata.get("last_advanced_on") == today and not args.force:
        print(f"NOOP: rollout already advanced on {today} UTC at {current_percent}%")
        return 0

    next_percent = next((step for step in allowed_steps if step > current_percent), current_percent)
    if next_percent == current_percent:
        print(f"NOOP: rollout is already at {current_percent}% (max {args.max_percent}%)")
        return 0

    updated = dict(current)
    updated["rollout_percent"] = next_percent
    updated["_rollout"] = {
        **metadata,
        "last_advanced_on": today,
        "previous_percent": current_percent,
        "actor": "advance-guest-checkout-rollout.py",
    }
    print(json.dumps({"key": FLAG_KEY, "from": current_percent, "to": next_percent, "date": today, "dry_run": args.dry_run}, indent=2))
    if args.dry_run:
        return 0

    update_endpoint = f"{base_url}/rest/v1/app_settings?key=eq.{FLAG_KEY}"
    result = request_json(update_endpoint, service_key, method="PATCH", body={"value": updated})
    if not isinstance(result, list) or len(result) != 1:
        fail("rollout update did not return exactly one updated setting")
    print(f"UPDATED: guest checkout rollout is now {next_percent}%")
    return 0


if __name__ == "__main__":
    main()
