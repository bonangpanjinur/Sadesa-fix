#!/usr/bin/env python3
"""Validate that the repository uses one consistent pnpm version."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_JSON = ROOT / "package.json"
LOCKFILE = ROOT / "pnpm-lock.yaml"
WORKFLOWS = ROOT / ".github" / "workflows"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)


def main() -> int:
    errors: list[str] = []

    try:
        package = json.loads(PACKAGE_JSON.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {PACKAGE_JSON.relative_to(ROOT)}: {exc}")
        return 1

    package_manager = package.get("packageManager")
    match = re.fullmatch(r"pnpm@(\d+\.\d+\.\d+)", str(package_manager or ""))
    if not match:
        errors.append("package.json must define packageManager as an exact pnpm version, e.g. pnpm@9.15.9")
        expected_version = None
    else:
        expected_version = match.group(1)

    if not LOCKFILE.exists():
        errors.append("pnpm-lock.yaml is missing")
    else:
        lock_text = LOCKFILE.read_text(encoding="utf-8")
        lockfile_match = re.search(r"^lockfileVersion:\s*['\"]?(\d+)\.", lock_text, re.MULTILINE)
        if not lockfile_match:
            errors.append("pnpm-lock.yaml does not expose a supported lockfileVersion")
        elif expected_version:
            expected_major = int(expected_version.split(".", 1)[0])
            lock_major = int(lockfile_match.group(1))
            if expected_major != 9 and lock_major == 9:
                errors.append(
                    f"pnpm-lock.yaml uses lockfile major {lock_major}, but packageManager requests pnpm {expected_version}"
                )

    setup_versions: list[tuple[Path, int, str]] = []
    setup_pattern = re.compile(
        r"uses:\s*pnpm/action-setup@[^\n]+\n"
        r"(?P<with_indent>\s+)with:\s*\n"
        r"(?P=with_indent)\s+version:\s*['\"]?([^'\"#\s]+)",
        re.MULTILINE,
    )
    if WORKFLOWS.exists():
        for workflow in sorted(WORKFLOWS.glob("*.y*ml")):
            workflow_text = workflow.read_text(encoding="utf-8")
            setup_lines = [
                index + 1
                for index, line in enumerate(workflow_text.splitlines())
                if "uses: pnpm/action-setup@" in line
            ]
            matches = list(setup_pattern.finditer(workflow_text))
            if len(matches) != len(setup_lines):
                errors.append(
                    f"{workflow.relative_to(ROOT)} has {len(setup_lines)} pnpm/action-setup declaration(s), "
                    f"but only {len(matches)} explicit version block(s)"
                )
            for match in matches:
                version = match.group(2)
                line_number = workflow_text[: match.start()].count("\n") + 1
                setup_versions.append((workflow, line_number, version))
                if expected_version and version != expected_version:
                    errors.append(
                        f"{workflow.relative_to(ROOT)}:{line_number} uses pnpm {version}; expected {expected_version}"
                    )

    if not setup_versions:
        errors.append("no pnpm/action-setup declaration found in .github/workflows")

    if errors:
        for error in errors:
            fail(error)
        return 1

    print(f"packageManager alignment OK: pnpm@{expected_version}")
    print(f"Validated {len(setup_versions)} pnpm/action-setup declaration(s) and pnpm-lock.yaml")
    return 0


if __name__ == "__main__":
    sys.exit(main())


definitely_not_reached = None
