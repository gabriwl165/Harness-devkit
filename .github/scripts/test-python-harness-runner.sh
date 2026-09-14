#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
generator=$root/plugins/coding-pipeline/scripts/init-python-harness.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
checksum() { cksum "$@" 2>/dev/null || true; }
make_project() {
    d=$1; mkdir -p "$d/src" "$d/tests" "$d/bin"
    printf 'x\n' > "$d/src/module.py"; printf 'x\n' > "$d/tests/test_module.py"; : > "$d/uv.lock"
    sh "$generator" --profile library --target "$d" >/dev/null
}
make_uv() {
    d=$1
    cat > "$d/bin/uv" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$HARNESS_LOG"
if [ "$#" -ge 3 ] && [ "$1" = run ] && [ "$2" = --frozen ]; then
    [ "${HARNESS_FAIL_TOOL:-}" = "$3" ] && exit "${HARNESS_FAIL_STATUS:-17}"
fi
exit "${HARNESS_UV_STATUS:-0}"
EOF
    chmod +x "$d/bin/uv"
}
config() {
    d=$1; floor=${2:-}; lock=${3:-uv.lock}; arch=${4:-}
    printf '[project]\nname="fixture"\n[tool.harness.quality_gate]\nsource_paths=["src"]\ntest_paths=["tests"]\n' > "$d/pyproject.toml"
    [ -n "$floor" ] && printf 'coverage_floor=%s\n' "$floor" >> "$d/pyproject.toml"
    printf 'lockfile="%s"\narchitecture_commands=%s\n' "$lock" "${arch:-[]}" >> "$d/pyproject.toml"
}

# P2-05: generated projects accept exactly the four modes and reject others.
a="$tmp/a"; b="$tmp/b"; mkdir "$a" "$b"; make_project "$a"; make_project "$b"; config "$a"
cmp "$a/quality_gate.py" "$b/quality_gate.py" || fail 'runner is nondeterministic'
grep -F 'import tomllib' "$a/quality_gate.py" >/dev/null || fail 'runner does not use stdlib TOML'
make_uv "$a"; : > "$a/log"
HARNESS_LOG="$a/log" PATH="$a/bin:$PATH" python3 "$a/quality_gate.py" fast || fail 'fast mode'
expected_fast='lock --check
run --frozen ruff format --check src
run --frozen ruff check src
run --frozen mypy src'
printf '%s\n' "$expected_fast" | cmp - "$a/log" || fail 'fast sequence mismatch'
: > "$a/log"
HARNESS_LOG="$a/log" PATH="$a/bin:$PATH" python3 "$a/quality_gate.py" architecture || fail 'empty architecture mode'
[ "$(wc -l < "$a/log" | tr -d ' ')" -eq 1 ] || fail 'empty architecture ran a gate command'
: > "$a/log"
expected_default_full='lock --check
run --frozen ruff format --check src
run --frozen ruff check src
run --frozen mypy src
run --frozen pytest --cov src --cov-branch --cov-fail-under=85 tests
run --frozen bandit -r src
run --frozen pip-audit --local'
HARNESS_LOG="$a/log" PATH="$a/bin:$PATH" python3 "$a/quality_gate.py" full || fail 'full mode'
printf '%s\n' "$expected_default_full" | cmp - "$a/log" || fail 'full sequence mismatch'
cp "$a/log" "$a/full.log"; : > "$a/log"
HARNESS_LOG="$a/log" PATH="$a/bin:$PATH" python3 "$a/quality_gate.py" ci || fail 'ci mode'
printf '%s\n' "$expected_default_full" | cmp - "$a/log" || fail 'ci sequence mismatch'
cmp "$a/full.log" "$a/log" || fail 'ci and full differ'
if HARNESS_LOG="$a/log" PATH="$a/bin:$PATH" python3 "$a/quality_gate.py" invalid >/dev/null 2>&1; then fail 'invalid mode accepted'; fi
[ ! -e "$a/Dockerfile" ] || fail 'non-PR6 artifact generated'
generated_before=$(checksum "$a/quality_gate.py" "$a/.github/workflows/python-quality.yml")
[ "$generated_before" = "$(checksum "$a/quality_gate.py" "$a/.github/workflows/python-quality.yml")" ] || fail 'generated artifacts mutated'

# P2-06/P2-07: lock preflight, defaults, configured floor, exact frozen argv.
p="$tmp/project"; make_project "$p"; config "$p" 91 uv.lock; make_uv "$p"; : > "$p/log"
HARNESS_LOG="$p/log" PATH="$p/bin:$PATH" python3 "$p/quality_gate.py" full || fail 'full gate'
expected='lock --check
run --frozen ruff format --check src
run --frozen ruff check src
run --frozen mypy src
run --frozen pytest --cov src --cov-branch --cov-fail-under=91 tests
run --frozen bandit -r src
run --frozen pip-audit --local'
printf '%s\n' "$expected" | cmp - "$p/log" || fail 'exact full argv/default floor'

# A valid custom lock path must reach every gate.
custom="$tmp/custom"; make_project "$custom"; rm "$custom/uv.lock"; : > "$custom/custom.lock"; config "$custom" 88 custom.lock; make_uv "$custom"; : > "$custom/log"
HARNESS_LOG="$custom/log" PATH="$custom/bin:$PATH" python3 "$custom/quality_gate.py" full || fail 'custom lock full gate'
printf '%s\n' 'lock --check
run --frozen ruff format --check src
run --frozen ruff check src
run --frozen mypy src
run --frozen pytest --cov src --cov-branch --cov-fail-under=88 tests
run --frozen bandit -r src
run --frozen pip-audit --local' | cmp - "$custom/log" || fail 'custom lock sequence mismatch'
rm "$p/uv.lock"; : > "$p/other.lock"; python3 - "$p/pyproject.toml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); p.write_text(p.read_text().replace('lockfile="uv.lock"', 'lockfile="other.lock"'))
PY
: > "$p/log"; missing_project_before=$(checksum "$p/pyproject.toml"); rm "$p/other.lock"; HARNESS_LOG="$p/log" PATH="$p/bin:$PATH" python3 "$p/quality_gate.py" fast 2>/dev/null && fail 'missing lock accepted'; [ ! -s "$p/log" ] || fail 'gate ran before lock rejection'; [ "$missing_project_before" = "$(checksum "$p/pyproject.toml")" ] || fail 'missing-lock changed pyproject'; [ ! -e "$p/other.lock" ] || fail 'missing-lock recreated lock'
: > "$p/other.lock"
ln -s other.lock "$p/uv.lock"; python3 - "$p/pyproject.toml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); p.write_text(p.read_text().replace('lockfile="other.lock"', 'lockfile="uv.lock"'))
PY
before=$(checksum "$p/pyproject.toml" "$p/other.lock"); symlink_target_before=$(checksum "$p/other.lock"); HARNESS_LOG="$p/log" PATH="$p/bin:$PATH" python3 "$p/quality_gate.py" fast 2>/dev/null && fail 'symlink lock accepted'; [ ! -s "$p/log" ] || fail 'gate ran for symlink'; [ "$before" = "$(checksum "$p/pyproject.toml" "$p/other.lock")" ] || fail 'symlink mutated config/target'; [ "$symlink_target_before" = "$(checksum "$p/other.lock")" ] || fail 'symlink target mutated'

# Unreadable regular locks use an unprivileged account when available; chmod
# alone is not treated as evidence on privileged hosts.
rm "$p/uv.lock"; : > "$p/other.lock"; mkdir "$p/unreadable.lock"; python3 - "$p/pyproject.toml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); p.write_text(p.read_text().replace('lockfile="uv.lock"', 'lockfile="unreadable.lock"'))
PY
: > "$p/log"; set +e; HARNESS_LOG="$p/log" PATH="$p/bin:$PATH" python3 "$p/quality_gate.py" fast 2>"$p/direct.err"; direct_status=$?; set -e; expected_lock_error='quality_gate: lockfile is missing, unreadable, or symlinked: unreadable.lock'; [ "$direct_status" -eq 2 ] || fail 'directory lock status'; grep -Fx "$expected_lock_error" "$p/direct.err" >/dev/null || fail 'directory lock diagnostic'; [ ! -s "$p/log" ] || fail 'gate ran for unreadable lock'
rm -rf "$p/unreadable.lock"
if id nobody >/dev/null 2>&1 && command -v su >/dev/null 2>&1; then
    : > "$p/unreadable.lock"; unreadable_before=$(checksum "$p/pyproject.toml" "$p/unreadable.lock"); chmod 755 "$tmp" "$p" "$p/src" "$p/tests" "$p/bin"
    chmod 644 "$p/pyproject.toml" "$p/quality_gate.py" "$p/src/module.py" "$p/tests/test_module.py"
    chmod 000 "$p/unreadable.lock"; : > "$p/log"; chmod 666 "$p/log"
    set +e
    su nobody -s /bin/sh -c "cd '$p' && HARNESS_LOG='$p/log' PATH='$p/bin:/usr/bin:/bin' python3 quality_gate.py fast" >"$p/su.out" 2>"$p/su.err"
    status=$?
    set -e
    if [ "$status" -eq 2 ] && grep -Fx "$expected_lock_error" "$p/su.err" >/dev/null; then
        chmod 644 "$p/unreadable.lock"
        [ ! -s "$p/log" ] || fail 'gate ran for unreadable regular lock'
        [ "$unreadable_before" = "$(checksum "$p/pyproject.toml" "$p/unreadable.lock")" ] || fail 'unreadable lock mutated files'
    elif [ "$status" -eq 0 ] || grep -F 'quality_gate:' "$p/su.err" >/dev/null; then
        fail "unexpected unreadable-lock runner result (status $status)"
    else
        [ "${CI:-}" = true ] && fail "unprivileged setup failed in CI (status $status): $(tr '\n' ' ' < "$p/su.err")"
        printf '%s\n' "SKIP: nobody setup/invocation unavailable (status $status)"
    fi
    chmod 644 "$p/unreadable.lock"
    [ "$unreadable_before" = "$(checksum "$p/pyproject.toml" "$p/unreadable.lock")" ] || fail 'unreadable-lock restore mutated files'
else
    printf '%s\n' 'SKIP: no portable unprivileged account/su for unreadable regular lock test'
fi
rm -f "$p/unreadable.lock"
python3 - "$p/pyproject.toml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); p.write_text(p.read_text().replace('lockfile="unreadable.lock"', 'lockfile="other.lock"'))
PY
stale_before=$(checksum "$p/pyproject.toml" "$p/other.lock")
python3 - "$p/bin/uv" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); p.write_text(p.read_text().replace('exit "${HARNESS_UV_STATUS:-0}"', 'if [ "$1" = lock ]; then exit 41; fi\nexit "${HARNESS_UV_STATUS:-0}"'))
PY
: > "$p/log"; set +e; HARNESS_LOG="$p/log" PATH="$p/bin:$PATH" python3 "$p/quality_gate.py" fast 2>/dev/null; status=$?; set -e; [ "$status" -eq 41 ] || fail 'stale lock status'; [ "$(wc -l < "$p/log" | tr -d ' ')" -eq 1 ] || fail 'stale lock ordering'; [ "$stale_before" = "$(checksum "$p/pyproject.toml" "$p/other.lock")" ] || fail 'stale lock mutated files'

# Architecture is deny-by-default and executes declared argv without a shell.
python3 - "$p/bin/uv" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); p.write_text(p.read_text().replace('if [ "$1" = lock ]; then exit 41; fi\n', ''))
PY
rm -f "$p/uv.lock"; : > "$p/other.lock"; python3 - "$p/pyproject.toml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); p.write_text(p.read_text().replace('lockfile="uv.lock"', 'lockfile="other.lock"'))
PY
cat > "$p/bin/arch" <<'EOF'
#!/bin/sh
printf 'arch:%s\n' "$1" >> "$HARNESS_LOG"
EOF
chmod +x "$p/bin/arch"
python3 - "$p/pyproject.toml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); p.write_text(p.read_text().replace('architecture_commands=[]', 'architecture_commands=[["./bin/arch","first;$(touch HACKED)"],["./bin/arch","second value"]]'))
PY
: > "$p/log"; HARNESS_LOG="$p/log" PATH="$p/bin:$PATH" python3 "$p/quality_gate.py" architecture || fail 'architecture mode'
printf '%s\n' 'lock --check
arch:first;$(touch HACKED)
arch:second value' | cmp - "$p/log" || fail 'architecture declaration order/argv mismatch'; [ ! -e "$p/HACKED" ] || fail 'architecture shell injection'

# P2-08: exact fail-fast status plus generated CI ordering.
make_project "$tmp/fail"; config "$tmp/fail" 91; make_uv "$tmp/fail"; : > "$tmp/fail/log"
set +e
HARNESS_LOG="$tmp/fail/log" HARNESS_FAIL_TOOL=ruff HARNESS_FAIL_STATUS=37 PATH="$tmp/fail/bin:$PATH" python3 "$tmp/fail/quality_gate.py" fast 2>/dev/null
status=$?
set -e
[ "$status" -eq 37 ] || fail 'failure status changed'; [ "$(wc -l < "$tmp/fail/log" | tr -d ' ')" -eq 2 ] || fail 'not fail-fast'
grep -F 'uv sync --frozen --all-groups' "$tmp/fail/.github/workflows/python-quality.yml" >/dev/null || fail 'CI sync missing'
grep -F 'python quality_gate.py ci' "$tmp/fail/.github/workflows/python-quality.yml" >/dev/null || fail 'CI runner missing'
[ "$(grep -c 'contents: read' "$tmp/fail/.github/workflows/python-quality.yml")" -eq 1 ] || fail 'workflow permission missing'
[ "$(grep -nE 'uv sync|quality_gate.py ci' "$tmp/fail/.github/workflows/python-quality.yml" | cut -d: -f1 | tr '\n' ' ')" = '13 14 ' ] || fail 'CI order changed'

# Existing consumer configuration is refused without changing a byte.
conflict="$tmp/conflict"; mkdir "$conflict"; printf '[project]\nname="consumer"\n[tool.harness.quality_gate]\nsource_paths=["src"]\n' > "$conflict/pyproject.toml"
before=$(cksum "$conflict/pyproject.toml")
set +e
message=$(sh "$generator" --profile library --target "$conflict" 2>&1)
status=$?
set -e
[ "$status" -ne 0 ] || fail 'conflicting configuration accepted'
printf '%s' "$message" | grep -F 'merge the deterministic fragment manually' >/dev/null || fail 'conflict message lacks manual merge guidance'
[ "$before" = "$(cksum "$conflict/pyproject.toml")" ] || fail 'conflict changed consumer pyproject'
printf 'PASS: python harness runner (P2-05..P2-08)\n'
