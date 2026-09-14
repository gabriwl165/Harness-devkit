---
name: python-harness-bootstrap
description: Use when asked to "bootstrap Python harness", "initialize Python harness", or scaffold a minimal framework-neutral Python library or service policy with init-python-harness.sh.
---

# Python harness bootstrap

Use `plugins/coding-pipeline/scripts/init-python-harness.sh --profile library|service --target <directory> [--dry-run]`.

The service profile requires an existing regular `<target>/pyproject.toml` and creates only service policy documents. Dry-run is deterministic and writes nothing. Existing destination files are never replaced; application and framework runtime code is deferred.
