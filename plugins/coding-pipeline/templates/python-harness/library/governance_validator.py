#!/usr/bin/env python3
"""Validate the project-owned Python Harness governance policy without side effects."""
from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import tomllib

ROOT = Path(__file__).resolve().parent
POLICY = ROOT / "python-harness-policy.toml"
PLACEHOLDER = "REPLACE_WITH_PROJECT_OWNER"


def fail(message: str) -> int:
    print(f"governance_validator: {message}", file=sys.stderr)
    return 2


def credential_like(value: Any) -> bool:
    if isinstance(value, dict):
        return any(credential_like(key) or credential_like(item) for key, item in value.items())
    if isinstance(value, list):
        return any(credential_like(item) for item in value)
    if not isinstance(value, str):
        return False
    lowered = value.lower()
    if PLACEHOLDER.lower() in lowered:
        return True
    if "://" in value and "@" in value.split("://", 1)[1].split("/", 1)[0]:
        return True
    return any(
        token in lowered
        for token in (
            "password",
            "passwd",
            "secret",
            "token",
            "api_key",
            "apikey",
        )
    )


def main() -> int:
    try:
        with POLICY.open("rb") as stream:
            policy = tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        return fail(f"cannot read policy: {exc}")
    if credential_like(policy):
        return fail("owner is unresolved or policy contains credential-like data")
    if policy.get("profile") not in {"library", "service"}:
        return fail("profile must be library or service")
    if (
        not isinstance(policy.get("owner"), str)
        or not policy["owner"].strip()
        or policy["owner"] == PLACEHOLDER
    ):
        return fail("owner must be resolved to a non-empty value")
    paths = policy.get("allowed_write_paths")
    if not isinstance(paths, list) or not paths or any(
        not isinstance(item, str)
        or not item
        or Path(item).is_absolute()
        or ".." in Path(item).parts
        for item in paths
    ):
        return fail("allowed_write_paths must be a non-empty list of relative paths")
    if policy.get("required_quality_command") != "python quality_gate.py ci":
        return fail("required_quality_command is invalid")
    for section in ("review", "falsification"):
        if not isinstance(policy.get(section), dict) or policy[section].get("required") is not True:
            return fail(f"{section}.required must be true")
    mcp = policy.get("mcp")
    if not isinstance(mcp, dict) or mcp.get("enabled") is not False:
        return fail("MCP must be disabled by default")
    entries = mcp.get("allowlist")
    if not isinstance(entries, list):
        return fail("MCP allowlist must be a list")
    ids: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict) or not all(isinstance(entry.get(key), str) and entry[key] for key in ("id", "owner", "approval", "classification")):
            return fail("MCP entries require id, owner, approval, and classification")
        if entry["id"] in ids:
            return fail("MCP IDs must be unique")
        ids.add(entry["id"])
        timeout = entry.get("timeout")
        if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout <= 0:
            return fail("MCP timeout must be positive")
    print("governance_validator: valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
