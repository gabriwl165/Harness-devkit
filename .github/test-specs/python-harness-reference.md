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
