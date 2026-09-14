# PR5 specification: Python harness reference bootstrap

**Oracle plan:** ora-2  
**Scope:** PR5 only  
**Freeze date:** 2026-09-13  
**Status:** frozen before implementation  
**Validation owner:** parent orchestrator  
**Evidence:** recorded below after implementation and mutation-based falsification. Tests were
authored after implementation; each listed mutation was applied one at a time, the named assertion
failed for the intended reason, and the implementation was restored before the next check.

## Scope and non-goals

PR5 adds the reference bootstrap interface for creating a minimal Python Harness project in a
caller-selected directory. The interface is:

```text
init-python-harness.sh --profile library|service --target <directory> [--dry-run]
```

The command has two explicit profiles:

- **`library` profile:** creates the framework-neutral package/library scaffold and its library
  metadata and quality-tool configuration. It must not create an application entrypoint, HTTP
  server, deployment manifest, or service-specific runtime files.
- **`service` profile:** creates the framework-neutral service scaffold and its service metadata
  and quality-tool configuration, but only when `<directory>/pyproject.toml` already exists. It
  must not invent or replace the project marker and must not create an application framework,
  HTTP server, deployment manifest, or other application implementation.

Both profiles are limited to deterministic Harness bootstrap artifacts. Dry-run previews the same
planned artifacts without writing them. Generated metadata must be portable and may not contain
machine-specific absolute paths, usernames, home directories, or worktree paths.

This PR does **not** add PR6, PR7, or PR8 behavior, tests, integrations, application generation,
framework selection, dependency installation, virtual environments, lockfiles, CI matrices,
runtime business logic, deployment configuration, or a generic bootstrap refactor. Those phases
are deferred and must not be represented as implemented acceptance criteria here.

## Acceptance criteria

- **AC-PR5-1 Interface:** The executable accepts exactly the documented `library` or `service`
  profile, a target directory, and optional `--dry-run`; invalid or incomplete invocations fail
  clearly and non-zero.
- **AC-PR5-2 Deterministic dry-run:** Repeated dry-runs with the same profile and equivalent target
  state produce byte-for-byte identical planned output and exit successfully when the target is
  valid.
- **AC-PR5-3 No dry-run writes:** A successful dry-run does not create, remove, or modify any file
  or directory under the target.
- **AC-PR5-4 Profile separation:** Library and service profiles produce their explicitly distinct
  scaffolds; neither profile emits artifacts belonging only to the other profile.
- **AC-PR5-5 Existing service marker:** The service profile requires an explicit existing regular
  `<target>/pyproject.toml`; absent, unreadable, or non-regular markers are rejected before any
  write.
- **AC-PR5-6 No application generation:** Neither profile generates application source, an HTTP
  server, framework-specific runtime, deployment manifest, or business logic.
- **AC-PR5-7 Safe target handling:** Existing generated files are never silently overwritten;
  traversal targets and non-directory targets are rejected without writes.
- **AC-PR5-8 Portable metadata:** Generated metadata contains no machine-specific paths and uses
  stable, profile-appropriate values.
- **AC-PR5-9 Shell quality and wiring:** The bootstrap is shellcheck-clean at error severity,
  syntactically valid, executable through its documented wiring, and does not regress the existing
  Harness sensors.

## Frozen test table

Each row is a post-implementation test contract. The precondition and observable result must be
implemented as an external behavior assertion, not as an assertion on a value copied from the
implementation. The mutation in the final column is required falsification evidence.

| ID / test | Preconditions | Observable result | Why it matters | AC | Falsified by |
|---|---|---|---|---|---|
| **P2-01 deterministic dry-run and no writes** | A fresh valid target directory is snapshotted; invoke each profile with `--dry-run` twice against equivalent fresh targets. | Each profile's two stdout/stderr plans and exit codes are identical; both targets remain byte-for-byte empty and unchanged. | A preview must be reproducible and safe to use in automation or review. | AC-PR5-2, AC-PR5-3 | Remove the dry-run guard so one planned file is written, or include a timestamp/random value in output; the snapshot or equality assertion fails. |
| **P2-02 profile separation and existing service marker** | Fresh targets are prepared; the service target contains an explicit regular `pyproject.toml`, while the library target does not. Run both profiles, then run service against a target without the marker. | Library succeeds with only library artifacts; service succeeds only with the pre-existing marker and emits only service artifacts; service without the marker exits non-zero and leaves the target unchanged. | Separate profiles must communicate stable intent, while service setup must never fabricate the project boundary it depends on. | AC-PR5-4, AC-PR5-5 | Make both profiles call the same artifact set, or remove the service marker guard; the artifact-set or rejection assertion fails. |
| **P2-03 refusal and target-boundary safety** | Target contains a pre-existing generated-path file; separate inputs address a regular file, a traversal path escaping the requested directory, and a non-directory target. | Existing content is preserved and command exits non-zero; every invalid target is rejected non-zero before writes; no file outside the intended target changes. | Bootstrap is a filesystem boundary and must fail closed rather than overwrite or escape its target. | AC-PR5-7 | Replace exclusive creation with overwrite, canonicalize away traversal rejection, or accept a regular-file target; the content, exit-code, or outside-snapshot assertion fails. |
| **P2-04 application exclusion and portable metadata** | Run both profiles in isolated temporary directories; inspect all generated paths and text while allowing only repository-independent temporary target names. | No application entrypoint, HTTP server, framework runtime, deployment manifest, or business-logic file exists; metadata is stable and contains no absolute path, username, home directory, or machine/worktree path. | The reference bootstrap must establish Harness structure without silently becoming an application generator or leaking local environment details. | AC-PR5-6, AC-PR5-8 | Add an application file or interpolate the invocation's absolute target/home path into metadata; the path/file inventory or portable-content assertion fails. |
| **P2-05 wiring and regression** | Final PR5 tree is present; bootstrap is executable; existing repository fixtures and shell sensors are available. | Documented invocation resolves to the bootstrap; `bash -n` and `shellcheck --severity=error` pass for the new script; existing hook/install/wiring regression checks and `git diff --check` exit 0. | A reference command that is not wired, syntactically valid, or compatible with existing sensors cannot be delivered safely. | AC-PR5-1, AC-PR5-9 | Remove the wiring anchor, introduce a shell syntax error, or break an existing fixture path; the relevant command exits non-zero. |

## Deferred scope

PR6–PR8 tests and acceptance criteria are intentionally deferred. No PR6–PR8 implementation or
test row is frozen by this document.

## Evidence record

Evidence was collected on 2026-09-13 in the delivery worktree. The implementation and test script
were restored after every mutation.

- **P2-01 — pass:** `.github/scripts/test-python-harness-bootstrap.sh` dry-run equality and
  empty-target assertions passed. Removing the dry-run `exit 0` caused the exact `dry-run wrote
  files` assertion to fail (exit 1); restored, the row passed. Adding a timestamp to the dry-run
  plan did not satisfy the script's current comparison because the two invocations run within the
  same second; no evidence is claimed for that alternate mutation.
- **P2-02 — pass:** profile artifact-set, preserved service marker, and missing-marker rejection
  assertions passed. Removing the service marker guard caused `service marker guard` to fail (exit
  1); restored, the row passed.
- **P2-03 — pass:** overwrite, traversal, non-directory, and outside-target preservation assertions
  passed. Removing the exclusive-create guard caused `overwrite guard` to fail (exit 1); restored,
  the row passed.
- **P2-04 — pass:** application-artifact inventory and machine-path metadata assertions passed.
  Adding the worktree path to a generated README caused `metadata contains machine path` to fail
  (exit 1); restored, the row passed.
- **P2-05 wiring/regression — pass:** executable/wiring assertions passed; removing executable
  permission caused `bootstrap is not executable` to fail (exit 1); restored, the row passed.
  `bash -n`, error-level shellcheck, and diff-check also passed.

Full PR5 and existing Phase 1 validation: `sh .github/scripts/test-python-harness-bootstrap.sh`
passed; `bash .github/scripts/test-hooks.sh` (44), `bash .github/scripts/test-git-hooks.sh` (52),
`bash .github/scripts/test-install.sh` (20), and `bash .github/scripts/test-dup-attribution.sh`
(11) passed. `bash -n` passed for the bootstrap and test scripts;
`shellcheck --severity=error` passed for both; `git diff --check` passed. No machine paths or
application/framework/runtime artifacts were found in generated outputs.

### Oracle blocker remediation evidence

The implementation stages template bytes and uses POSIX `ln` for no-clobber destination creation.
Hard-link creation fails if a destination appears after preflight. An EXIT trap removes only files
recorded as created by this invocation, rolling back earlier files if a later create fails.

- **P2-01 remediation — pass:** library and service dry-runs are independently repeated against
  equivalent targets. Each service marker checksum is captured immediately after marker creation,
  before either dry-run, and compared with its own post-run checksum; both markers remain unchanged.
  Removing the dry-run guard fails the intended checksum/empty-target assertion; restored, the row
  passes.
- **P2-02 remediation — pass:** exact profile artifact presence/count assertions and explicit
  profile-exclusive absence assertions pass. A shared artifact set fails these assertions.
- **P2-03 remediation — pass:** a service marker symlink is rejected before writes. Removing the
  `! -L` check fails the symlink-marker assertion; restored, the row passes.
- **P2-04 remediation — pass:** the deterministic race hook creates `QUALITY.md` after preflight;
  `ln` refuses it, preserves the race file, and rollback removes the earlier generated marker.
  Replacing `ln` with `cp` fails the race assertion; restored, the row passes.
- **P2-05 remediation — pass:** executable wiring, syntax, ShellCheck, regression suites, and
  diff checks were rerun after remediation.

### Oracle attempt 3 remediation evidence

- **P2-01 final — pass:** both service dry-run targets were populated with equivalent existing
  regular markers. The test records `cksum` byte/length checksums before the repeated dry-runs and
  verifies both checksums again afterward; the marker files remain unchanged. Mutating the dry-run
  flag handling caused `FAIL: dry-run wrote files`; the implementation was restored and the test
  passed.
- **P2-04 final — pass:** the production environment hook was removed entirely. The race test now
  copies the shipped script into a test-owned fixture, changes only its timing by inserting a
  `sleep` before the real `ln` operation, and runs a separate test-owned background process that
  creates the destination after preflight. The fixture still executes the shipped no-clobber
  primitive and rollback logic; the timing-only transformation is not part of production. A
  separate concurrent run invokes the unmodified shipped script eight times against one target and
  requires at least one loser with exactly one complete artifact set. Replacing production `ln`
  with `cp` was deliberately applied; the no-clobber race assertion failed, then `ln` was restored.

## PR6 specification: Python quality-gate runner

**Oracle plan:** ora-2  
**Scope:** PR6 only  
**Freeze date:** 2026-09-14  
**Status:** frozen before implementation  
**Validation owner:** parent orchestrator  
**Evidence:** pending implementation, post-implementation tests, and mutation-based falsification.

### Scope and non-goals

PR6 adds a generated, project-owned standard-library `quality_gate.py` runner and the generated
CI invocation for the Python Harness. The runner reads its configuration from the consumer's
`pyproject.toml` and supports exactly these modes:

```text
python quality_gate.py fast
python quality_gate.py full
python quality_gate.py ci
python quality_gate.py architecture
```

The contract is:

- `fast` runs formatting, Ruff checks, and mypy; `full` runs the `fast` gates plus pytest with
  branch coverage, Bandit, and pip-audit; `ci` runs the same complete gate set as `full`; and
  `architecture` runs only explicitly declared architecture commands.
- Source and test paths are explicit configuration values, and the coverage floor defaults to 85%
  when not configured. No implicit source discovery or test discovery is permitted.
- The only package runner is `uv`; every dependency-consuming command is invoked through
  `uv run --frozen`. The lock validation sequence is fixed: resolve the configured lockfile path
  (the repository's `uv.lock` by default), require it to be a regular non-symlink file, then run
  `uv lock --check` before any gate or other `uv` command. A missing, symlinked, unreadable, or
  stale lock fails before formatting, linting, type checking, tests, security checks, or declared
  architecture commands. The runner never refreshes or writes the lockfile.
- pip-audit is run against the locked environment, not an independently resolved requirements
  file: `uv run --frozen pip-audit --local`, with no network/update option. The command therefore
  audits packages installed in the project's frozen `uv` environment; its failure is a gate
  failure.
- Architecture commands are empty by default. Only commands explicitly declared in
  `pyproject.toml` are run, in declaration order, without shell evaluation or command invention.
- A subprocess failure stops execution immediately and preserves the exact subprocess exit status;
  signal termination is reported as the corresponding non-zero status. The runner performs no
  auto-fix, network/bootstrap/install side effect, or virtual-environment creation.
- Generated CI first runs `uv sync --frozen --all-groups`, then invokes the same
  `python quality_gate.py ci`. CI does not add a second or divergent gate definition.
- Bootstrap does not modify a consumer `pyproject.toml` in place. Existing conflicting generated
  configuration is refused with an actionable explanation; otherwise bootstrap emits only the
  deterministic fragment permitted by the PR5 contract and explains that the consumer must merge
  it manually. No service, Docker, Go, application, or governance behavior is included.

PR6 does not add service generation, Docker/container files, Go tooling, governance workflows,
framework selection, application/runtime code, dependency installation, lockfile generation,
network access, auto-fixing, or mutation of a consumer's existing `pyproject.toml`.

### Acceptance criteria

- **AC-PR6-1 Generated ownership and wiring:** A successful bootstrap generates a deterministic,
  project-owned standard-library `quality_gate.py` and the documented CI entrypoint; generated
  files are wired, executable where applicable, and contain no machine-specific paths.
- **AC-PR6-2 Modes:** Only `fast`, `full`, `ci`, and `architecture` are accepted; their gate sets
  match the frozen mode contract, with `ci` equivalent to `full`.
- **AC-PR6-3 Configuration:** Configuration comes from `pyproject.toml`, including explicit source
  and test paths, coverage floor, lockfile path, and optional architecture commands; the coverage
  default is 85% and malformed or unsupported configuration fails clearly before execution.
- **AC-PR6-4 Locked execution:** Lock validation has the frozen ordering and rejects missing,
  symlinked, unreadable, or stale locks before every gate. Dependency-consuming commands use only
  `uv run --frozen`; pip-audit uses `--local` against that locked environment.
- **AC-PR6-5 Exact gates:** The runner invokes Ruff format/check, mypy, pytest with branch coverage
  and the configured threshold, Bandit, and pip-audit exactly as specified, without auto-fix.
- **AC-PR6-6 Architecture allowlist:** Architecture mode runs no command by default and runs only
  explicitly declared commands, in order, with safe argument handling and no shell interpolation.
- **AC-PR6-7 Fail-fast status:** The first failing subprocess stops the run and the runner exits
  with its exact status; no later gate is run.
- **AC-PR6-8 No side effects:** Runner and bootstrap perform no network, bootstrap, installation,
  lockfile-write, virtual-environment-create, auto-fix, or consumer-pyproject in-place mutation.
- **AC-PR6-9 CI parity and boundaries:** Generated CI performs `uv sync --frozen --all-groups`
  followed by `python quality_gate.py ci`, and PR6 emits no service, Docker, Go, or governance
  behavior.
- **AC-PR6-10 Conflict handling:** Bootstrap refuses conflicting existing configuration and gives
  a clear manual-merge explanation, or emits the deterministic PR5-contract fragment without
  modifying the consumer project file.

### Frozen test table

Each row is a post-implementation test contract. The precondition and observable result must be
asserted through the generated project boundary, not by copying constants from the runner. Each
mutation is applied alone, the named assertion must fail, and the implementation is restored.

| ID / test | Preconditions | Observable result | Why it matters | AC | Falsified by |
|---|---|---|---|---|---|
| **P2-05 generated runner contract** | Bootstrap a clean consumer with valid `pyproject.toml` configuration and inspect generated files. | `quality_gate.py` is deterministic, standard-library-only, project-owned, wired, and supports exactly the four documented modes; no non-PR6 artifacts are generated. | A generated runner must be portable, reviewable, and owned by the project rather than hidden in the Harness. | AC-PR6-1, AC-PR6-2, AC-PR6-9 | Remove one mode, add a dependency import, make output nondeterministic, or generate a Docker/service artifact; mode, dependency, checksum, or inventory assertions fail. |
| **P2-06 configuration and lock preflight** | Prepare projects covering explicit paths, omitted coverage floor, custom lock path, missing/symlink/unreadable lock, and stale lock; make gate executables observable fixtures. | Paths and configuration are read from `pyproject.toml`; omitted threshold is 85%; lock checks occur before any gate; missing, symlinked, unreadable, or stale locks fail non-zero without gate execution or lock writes. | Deterministic configuration and early lock rejection prevent running or trusting gates against an unverified dependency graph. | AC-PR6-3, AC-PR6-4 | Move `uv lock --check` after a gate, accept a symlink/missing lock, default to another threshold, or write the lock during validation; ordering, status, or filesystem assertions fail. |
| **P2-07 modes, exact gates, audit target, and architecture allowlist** | Use recording `uv`/tool fixtures with a valid lock and configured source/test paths, threshold, and architecture commands; repeat with no architecture commands. | `fast` runs only format/check/mypy; `full` and `ci` run the exact full sequence including branch coverage, Bandit, and `uv run --frozen pip-audit --local`; architecture runs nothing by default and only declared commands in order. | Gate completeness, locked-environment auditing, and a deny-by-default architecture mode prevent silent omissions and arbitrary command execution. | AC-PR6-2, AC-PR6-5, AC-PR6-6 | Delete a gate, omit `--frozen`, replace `--local`, enable an undeclared command, or make default architecture discovery non-empty; the recorded argv/order assertions fail. |
| **P2-08 fail-fast, CI parity, and safe bootstrap conflicts** | Give the first recorded gate a non-zero status; separately inspect generated CI and bootstrap against an existing conflicting consumer `pyproject.toml`. | The runner stops at the first failure and returns its exact status; CI orders `uv sync --frozen --all-groups` before `python quality_gate.py ci`; bootstrap refuses or emits only the deterministic fragment, never edits the consumer file, and explains manual merge. | Exact failure propagation and non-mutating integration make failures actionable and preserve consumer ownership. | AC-PR6-7, AC-PR6-8, AC-PR6-9, AC-PR6-10 | Continue after failure, normalize the status, reverse CI order, overwrite the consumer file, or silently accept a conflict; status/order/content/explanation assertions fail. |

### Evidence record

Evidence (exceptional Oracle final remediation): `.github/scripts/test-python-harness-runner.sh` covers
P2-05 through P2-08 with hermetic uv argv recording and no network. P2-06 now records the
complete custom-lock success path, the missing custom-lock path, and the regular unreadable-lock
branch using an unprivileged `nobody` process when the host supports it; this macOS host cannot
execute that account through `su` (explicit SKIP, status 1), so no chmod-only success is claimed.
P2-07 uses separate complete logs for fast, full, and ci, compares exact ordered argv, proves
ci==full, exercises the omitted-floor 85 default, configured floor, custom paths, and two
architecture arrays with literal injection-safe argv. Rejection cases checksum `pyproject.toml`
and lock targets before/after and assert no gate log. The unreadable regular-lock case captures
both `su` streams and requires status 2 plus the exact `quality_gate: lockfile is missing,
unreadable, or symlinked: unreadable.lock` diagnostic; setup/invocation failures are skipped only
locally and fail under `CI=true`. Permission restoration is followed by a second checksum check.
Bootstrap and runner suites are wired into
`.github/workflows/ci.yml` on Ubuntu with `contents: read`; CI sets `CI=true`, making inability to
execute the unprivileged unreadable-lock case a failure, while unsupported local hosts explicitly
skip. Row-specific checksum and unreadable-branch mutations failed as intended before restoration.
Runner, bootstrap, Phase1 hooks, `py_compile`, `bash -n`, ShellCheck, wiring validation, and
`git diff --check` passed. Workflow syntax is represented by the repository's existing YAML
workflow structure; no dedicated workflow validator is installed locally. Exceptional Oracle
focused review is authorized by the user.
