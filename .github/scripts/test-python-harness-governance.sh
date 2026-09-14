#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
generator=$root/plugins/coding-pipeline/scripts/init-python-harness.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
for profile in library service; do
    d="$tmp/$profile"; mkdir -p "$d/src" "$d/tests"
    [ "$profile" = library ] || printf '[project]\nname="fixture"\n' > "$d/pyproject.toml"
    sh "$generator" --profile "$profile" --target "$d" >/dev/null || fail "$profile bootstrap"
    for file in python-harness-policy.toml agent-controls.md mcp-governance.md governance_validator.py; do
        [ -f "$d/$file" ] || fail "$profile missing $file"
    done
    sed 's/REPLACE_WITH_PROJECT_OWNER/fixture-owner/' "$d/python-harness-policy.toml" > "$d/policy.tmp"
    mv "$d/policy.tmp" "$d/python-harness-policy.toml"
    python3 "$d/governance_validator.py" >/dev/null || fail "$profile valid policy"
    python3 - "$d/python-harness-policy.toml" "$profile" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
assert f'profile = "{sys.argv[2]}"' in text
assert 'allowed_write_paths = ["src", "tests"]' in text
assert 'required_quality_command = "python quality_gate.py ci"' in text
assert '[review]\nrequired = true' in text
assert '[falsification]\nrequired = true' in text
assert '[mcp]\nenabled = false\nallowlist = []' in text
PY
    grep -F 'No MCP server is configured or enabled by default' "$d/mcp-governance.md" >/dev/null || fail 'MCP default documentation'
    grep -F 'integration points only' "$d/agent-controls.md" >/dev/null || fail 'agent controls boundary'
    grep -F 'do not enforce runtime permissions' "$d/agent-controls.md" >/dev/null || fail 'agent controls enforcement claim'
    grep -F 'integration points only' "$d/mcp-governance.md" >/dev/null || fail 'MCP boundary'
    grep -F 'not generated or enforced' "$d/mcp-governance.md" >/dev/null || fail 'MCP enforcement claim'
    [ ! -e "$d/.claude/settings.local.json" ] || fail 'host settings generated'
    if find "$d" -type f -print | grep -Ei '(^|/)(\.env(\..*)?|secrets?|credentials?|oauth|settings\.local\.json|settings\.json|permissions\.json|allowed-tools\.json|host[-_ ](permissions?|controls?)|endpoints?)(\.|$)' >/dev/null; then
        fail "$profile emitted forbidden file"
    fi
    content_files=$(find "$d" -type f ! -name '*.md' -print)
    if [ -n "$content_files" ] && printf '%s\n' "$content_files" | xargs grep -I -E '(^|[[:space:]])(password|passwd|secret|token|api[_-]?key)[[:space:]]*=' >/dev/null 2>&1; then
        fail "$profile emitted credential-like assignment"
    fi
    if [ -n "$content_files" ] && printf '%s\n' "$content_files" | xargs grep -I -Ei '(^|[[:space:]])[A-Za-z0-9_.-]*(endpoint|server|url|uri|command)[A-Za-z0-9_.-]*[[:space:]]*=[[:space:]]*[A-Za-z][A-Za-z0-9+.-]*://' >/dev/null 2>&1; then
        fail "$profile emitted endpoint assignment"
    fi
    if [ -n "$content_files" ] && printf '%s\n' "$content_files" | xargs grep -I -E '[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]/]+:[^[:space:]/]+@' >/dev/null 2>&1; then
        fail "$profile emitted URL userinfo"
    fi
    # Documentation may mention endpoints/secrets as prohibited concepts, but
    # generated files must not contain a literal endpoint value or credential.
    if [ -n "$content_files" ] && printf '%s\n' "$content_files" | xargs grep -I -Ei '(https?|mcp|stdio|ssh|ws|wss)://[^[:space:]) ]+' >/dev/null 2>&1; then
        fail "$profile emitted literal endpoint"
    fi
done

make_service_fixture() {
    d=$1
    mkdir -p "$d/src" "$d/tests" "$d/bin"
    printf '[project]\nname="fixture"\n' > "$d/pyproject.toml"
    sh "$generator" --profile service --target "$d" >/dev/null
    sed 's/REPLACE_WITH_PROJECT_OWNER/fixture-owner/' "$d/python-harness-policy.toml" > "$d/policy.tmp"; mv "$d/policy.tmp" "$d/python-harness-policy.toml"
}

mutate_policy() {
    policy=$1
    name=$2
    python3 - "$policy" "$name" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); text = p.read_text()
changes = {
    "profile": ('profile = "service"', 'profile = "unknown"'),
    "owner": ('owner = "fixture-owner"', 'owner = ""'),
    "placeholder": ('owner = "fixture-owner"', 'owner = "REPLACE_WITH_PROJECT_OWNER"'),
    "duplicate": ('allowlist = []', 'allowlist = [{ id = "same", owner = "fixture-owner", approval = "approved", classification = "internal", timeout = 10 }, { id = "same", owner = "fixture-owner", approval = "approved", classification = "internal", timeout = 10 }]'),
    "missing-field": ('allowlist = []', 'allowlist = [{ id = "one", owner = "fixture-owner", approval = "approved", timeout = 10 }]'),
    "missing-metadata": ('allowlist = []', 'allowlist = [{ id = "one", owner = "fixture-owner", approval = "approved", timeout = 10 }]'),
    "timeout": ('allowlist = []', 'allowlist = [{ id = "one", owner = "fixture-owner", approval = "approved", classification = "internal", timeout = 0 }]'),
    "credential": ('owner = "fixture-owner"', 'api_key = "literal-fixture-value"\nowner = "fixture-owner"'),
    "userinfo": ('owner = "fixture-owner"', 'owner = "https://fixture:literal@invalid.example"'),
    "paths-absolute": ('allowed_write_paths = ["src", "tests"]', 'allowed_write_paths = ["/tmp", "tests"]'),
    "paths-traversal": ('allowed_write_paths = ["src", "tests"]', 'allowed_write_paths = ["src/../escape"]'),
}
old, new = changes[sys.argv[2]]
if old not in text:
    raise SystemExit(f"mutation anchor missing: {sys.argv[2]}")
p.write_text(text.replace(old, new, 1))
PY
}

mutate_reject() {
    name=$1
    d="$tmp/reject-$name"
    make_service_fixture "$d"
    mutate_policy "$d/python-harness-policy.toml" "$name"
    set +e; output=$(python3 "$d/governance_validator.py" 2>&1); result=$?; set -e
    [ "$result" -ne 0 ] || fail "$name mutation accepted"
    [ -n "$output" ] || fail "$name mutation had no diagnostic"
}
for mutation in profile owner duplicate missing-field timeout credential userinfo paths-absolute paths-traversal; do
    mutate_reject "$mutation"
done

runner_mutation() {
    name=$1
    expected=$2
    for mode in full ci; do
        d="$tmp/runner-$name-$mode"
        make_service_fixture "$d"
        mutate_policy "$d/python-harness-policy.toml" "$name"
        printf '[project]\nname="fixture"\n[tool.harness.quality_gate]\nsource_paths=["src"]\ntest_paths=["tests"]\nlockfile="missing.lock"\n' > "$d/pyproject.toml"
        cat > "$d/bin/uv" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HARNESS_LOG"
EOF
        chmod +x "$d/bin/uv"; : > "$d/log"
        set +e; output=$(HARNESS_LOG="$d/log" PATH="$d/bin:$PATH" python3 "$d/quality_gate.py" "$mode" 2>&1); result=$?; set -e
        [ "$result" -eq 2 ] || fail "$mode/$name status"
        printf '%s' "$output" | grep -F "$expected" >/dev/null || fail "$mode/$name diagnostic"
        printf '%s' "$output" | grep -F 'lockfile' >/dev/null && fail "$mode/$name lock diagnostic won"
        [ ! -s "$d/log" ] || fail "$mode/$name ran uv"
    done
}
runner_mutation profile 'profile must be library or service'
runner_mutation owner 'owner must be resolved to a non-empty value'
runner_mutation placeholder 'owner is unresolved or policy contains credential-like data'
runner_mutation duplicate 'MCP IDs must be unique'
runner_mutation credential 'owner is unresolved or policy contains credential-like data'
runner_mutation userinfo 'owner is unresolved or policy contains credential-like data'
runner_mutation timeout 'MCP timeout must be positive'
runner_mutation missing-metadata 'MCP entries require id, owner, approval, and classification'

# Additional symlink/nonregular lock fixtures prove malformed governance wins.
for lock_case in symlink nonregular; do
    d="$tmp/runner-lock-$lock_case"; mkdir -p "$d/src" "$d/tests" "$d/bin"
    printf '[project]\nname="fixture"\n' > "$d/pyproject.toml"
    sh "$generator" --profile service --target "$d" >/dev/null
    sed 's/REPLACE_WITH_PROJECT_OWNER/fixture-owner/' "$d/python-harness-policy.toml" | sed 's/owner = "fixture-owner"/owner = ""/' > "$d/policy.tmp"; mv "$d/policy.tmp" "$d/python-harness-policy.toml"
    : > "$d/target.lock"
    if [ "$lock_case" = symlink ]; then ln -s target.lock "$d/lock.lock"; else mkdir "$d/lock.lock"; fi
    printf '[project]\nname="fixture"\n[tool.harness.quality_gate]\nsource_paths=["src"]\ntest_paths=["tests"]\nlockfile="lock.lock"\n' > "$d/pyproject.toml"
    cat > "$d/bin/uv" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HARNESS_LOG"
EOF
    chmod +x "$d/bin/uv"; : > "$d/log"
    set +e; output=$(HARNESS_LOG="$d/log" PATH="$d/bin:$PATH" python3 "$d/quality_gate.py" full 2>&1); result=$?; set -e
    [ "$result" -eq 2 ] || fail "full/$lock_case status"
    printf '%s' "$output" | grep -F 'owner must be resolved' >/dev/null || fail "full/$lock_case diagnostic"
    printf '%s' "$output" | grep -F 'lockfile' >/dev/null && fail "full/$lock_case lock diagnostic won"
    [ ! -s "$d/log" ] || fail "full/$lock_case ran uv"
done

# full and ci validate before lock/gates; the recording fixture proves no later command runs.
d="$tmp/ordering"; mkdir -p "$d/src" "$d/tests" "$d/bin"
sh "$generator" --profile library --target "$d" >/dev/null
sed 's/REPLACE_WITH_PROJECT_OWNER/fixture-owner/' "$d/python-harness-policy.toml" > "$d/policy.tmp"; mv "$d/policy.tmp" "$d/python-harness-policy.toml"
: > "$d/uv.lock"
cat > "$d/bin/uv" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HARNESS_LOG"
EOF
chmod +x "$d/bin/uv"
for mode in full ci; do
    for lock_case in missing symlink unreadable; do
        sed -i.bak 's/owner = "fixture-owner"/owner = ""/' "$d/python-harness-policy.toml"
        case "$lock_case" in
            missing) lock_name=missing.lock; rm -f "$d/$lock_name" "$d/target.lock" ;;
            symlink) lock_name=target.lock; : > "$d/target.lock"; ln -sf target.lock "$d/$lock_name" ;;
            unreadable) lock_name=unreadable.lock; rm -rf "$d/$lock_name"; mkdir "$d/$lock_name" ;;
        esac
        printf '[project]\nname="fixture"\n[tool.harness.quality_gate]\nsource_paths=["src"]\ntest_paths=["tests"]\nlockfile="%s"\n' "$lock_name" > "$d/pyproject.toml"
        : > "$d/log"
        set +e; output=$(HARNESS_LOG="$d/log" PATH="$d/bin:$PATH" python3 "$d/quality_gate.py" "$mode" 2>&1); result=$?; set -e
        [ "$result" -eq 2 ] || fail "$mode/$lock_case status did not preserve governance failure"
        printf '%s' "$output" | grep -F 'owner must be resolved' >/dev/null || fail "$mode/$lock_case governance diagnostic missing"
        printf '%s' "$output" | grep -F 'lockfile' >/dev/null && fail "$mode/$lock_case reported lock before governance"
        [ ! -s "$d/log" ] || fail "$mode/$lock_case ran uv after governance failure"
        mv "$d/python-harness-policy.toml.bak" "$d/python-harness-policy.toml"
    done
done
printf 'PASS: python harness governance (P2-09/P2-10)\n'
