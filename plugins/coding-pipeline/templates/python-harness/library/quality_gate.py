#!/usr/bin/env python3
"""Project-owned, dependency-free Python quality gates."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, NoReturn

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - the generated project requires 3.11+
    print("quality_gate.py requires Python 3.11 or newer", file=sys.stderr)
    raise SystemExit(2)


ROOT = Path(__file__).resolve().parent


def fail(message: str) -> "NoReturn":
    print(f"quality_gate: {message}", file=sys.stderr)
    raise SystemExit(2)


def paths(value: Any, name: str) -> list[str]:
    if not isinstance(value, list) or not value or any(
        not isinstance(item, str) or not item or Path(item).is_absolute() or ".." in Path(item).parts
        for item in value
    ):
        fail(f"{name} must be a non-empty list of relative paths")
    result = [str(Path(item)) for item in value]
    if any(not (ROOT / item).exists() for item in result):
        fail(f"{name} contains a missing path")
    return result


def load_config() -> tuple[list[str], list[str], int, str, list[list[str]]]:
    document: dict[str, Any]
    try:
        with (ROOT / "pyproject.toml").open("rb") as stream:
            document = tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        fail(f"cannot read pyproject.toml: {exc}")
    tool = document.get("tool", {})
    harness = tool.get("harness", {}) if isinstance(tool, dict) else {}
    config = harness.get("quality_gate", {}) if isinstance(harness, dict) else {}
    if not isinstance(config, dict):
        fail("[tool.harness.quality_gate] must be a table")
    source = paths(config.get("source_paths"), "source_paths")
    tests = paths(config.get("test_paths"), "test_paths")
    threshold = config.get("coverage_floor", 85)
    if not isinstance(threshold, int) or isinstance(threshold, bool) or not 0 <= threshold <= 100:
        fail("coverage_floor must be an integer from 0 to 100")
    lockfile = config.get("lockfile", "uv.lock")
    if not isinstance(lockfile, str) or not lockfile or Path(lockfile).is_absolute() or ".." in Path(lockfile).parts:
        fail("lockfile must be a relative path")
    lock = ROOT / lockfile
    if not lock.is_file() or lock.is_symlink() or not os.access(lock, os.R_OK):
        fail(f"lockfile is missing, unreadable, or symlinked: {lockfile}")
    architecture = config.get("architecture_commands", [])
    if not isinstance(architecture, list) or any(
        not isinstance(command, list) or not command or any(not isinstance(arg, str) for arg in command)
        for command in architecture
    ):
        fail("architecture_commands must be a list of non-empty argument lists")
    return source, tests, threshold, lockfile, architecture


def run(command: list[str]) -> None:
    completed = subprocess.run(command, cwd=ROOT, check=False)
    if completed.returncode:
        # subprocess uses negative values for signals; expose the conventional
        # shell status while preserving ordinary tool statuses exactly.
        raise SystemExit(
            128 + (-completed.returncode)
            if completed.returncode < 0
            else completed.returncode
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("fast", "full", "ci", "architecture"))
    args = parser.parse_args()
    source, tests, threshold, _lockfile, architecture = load_config()
    run(["uv", "lock", "--check"])
    if args.mode == "architecture":
        for command in architecture:
            run(command)
        return
    run(["uv", "run", "--frozen", "ruff", "format", "--check", *source])
    run(["uv", "run", "--frozen", "ruff", "check", *source])
    run(["uv", "run", "--frozen", "mypy", *source])
    if args.mode == "fast":
        return
    run(["uv", "run", "--frozen", "pytest", "--cov", *source, "--cov-branch", f"--cov-fail-under={threshold}", *tests])
    run(["uv", "run", "--frozen", "bandit", "-r", *source])
    run(["uv", "run", "--frozen", "pip-audit", "--local"])


if __name__ == "__main__":
    main()
