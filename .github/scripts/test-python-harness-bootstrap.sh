#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
generator=$root/plugins/coding-pipeline/scripts/init-python-harness.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert() { "$@" || fail "$*"; }
checksum() { cksum "$1" | cut -d' ' -f1-2; }

[ -x "$generator" ] || fail 'bootstrap is not executable'
grep -F 'plugins/coding-pipeline/scripts/init-python-harness.sh --profile library|service --target <directory>' "$root/README.md" >/dev/null || fail 'README wiring anchor'

mkdir "$tmp/lib-a" "$tmp/lib-b" "$tmp/svc" "$tmp/svc-dry-a" "$tmp/svc-dry-b" "$tmp/missing" "$tmp/service-missing" "$tmp/symlink"
before=$(ls -la "$tmp/lib-a")
plan_a=$(sh "$generator" --profile library --target "$tmp/lib-a" --dry-run 2>&1) || fail 'library dry-run'
plan_b=$(sh "$generator" --profile library --target "$tmp/lib-b" --dry-run 2>&1) || fail 'library dry-run repeat'
[ "$plan_a" = "$plan_b" ] || fail 'dry-run plans differ'
[ "$before" = "$(ls -la "$tmp/lib-a")" ] || fail 'dry-run wrote files'
[ "$(find "$tmp/lib-a" -mindepth 1 -print | wc -l | tr -d ' ')" = 0 ] || fail 'dry-run changed target'
printf '[project]\nname = "dry-service"\n' > "$tmp/svc-dry-a/pyproject.toml"
cp "$tmp/svc-dry-a/pyproject.toml" "$tmp/svc-dry-b/pyproject.toml"
service_marker_a=$(checksum "$tmp/svc-dry-a/pyproject.toml")
service_marker_b=$(checksum "$tmp/svc-dry-b/pyproject.toml")
service_plan_a=$(sh "$generator" --profile service --target "$tmp/svc-dry-a" --dry-run 2>&1) || fail 'service dry-run'
service_plan_b=$(sh "$generator" --profile service --target "$tmp/svc-dry-b" --dry-run 2>&1) || fail 'service dry-run repeat'
[ "$service_plan_a" = "$service_plan_b" ] || fail 'service dry-run plans differ'
[ "$service_marker_a" = "$(checksum "$tmp/svc-dry-a/pyproject.toml")" ] && [ "$service_marker_b" = "$(checksum "$tmp/svc-dry-b/pyproject.toml")" ] || fail 'service dry-run changed marker'
[ "$(find "$tmp/svc-dry-a" -mindepth 1 -print | wc -l | tr -d ' ')" = 1 ] || fail 'service dry-run changed target'

sh "$generator" --profile library --target "$tmp/lib-a" || fail 'library generation'
[ -f "$tmp/lib-a/pyproject.toml" ] || fail 'library marker missing'
[ ! -e "$tmp/lib-a/src" ] || fail 'library emitted application source'
printf '[project]\nname = "existing"\n' > "$tmp/svc/pyproject.toml"
marker_before=$(checksum "$tmp/svc/pyproject.toml")
sh "$generator" --profile service --target "$tmp/svc" || fail 'service generation'
[ ! -e "$tmp/svc/pyproject.toml.tmp" ] || fail 'service marker replacement'
[ -f "$tmp/svc/QUALITY.md" ] && [ -f "$tmp/svc/README.md" ] && [ -f "$tmp/svc/pyproject.toml" ] || fail 'service artifact set'
[ "$(find "$tmp/svc" -maxdepth 1 -type f | wc -l | tr -d ' ')" = 3 ] || fail 'service artifact count'
[ -f "$tmp/lib-a/QUALITY.md" ] && [ -f "$tmp/lib-a/README.md" ] && [ -f "$tmp/lib-a/pyproject.toml" ] || fail 'library artifact set'
[ "$(find "$tmp/lib-a" -maxdepth 1 -type f | wc -l | tr -d ' ')" = 3 ] || fail 'library artifact count'
[ ! -e "$tmp/lib-a/service.toml" ] && [ ! -e "$tmp/svc/library.toml" ] || fail 'profile-exclusive artifact'
[ "$marker_before" = "$(checksum "$tmp/svc/pyproject.toml")" ] || fail 'service marker changed'
if sh "$generator" --profile service --target "$tmp/service-missing"; then fail 'service marker guard'; fi
[ "$(find "$tmp/service-missing" -mindepth 1 -print | wc -l | tr -d ' ')" = 0 ] || fail 'service guard wrote files'
printf '[project]\nname = "real"\n' > "$tmp/symlink/real.toml"
ln -s real.toml "$tmp/symlink/pyproject.toml"
if sh "$generator" --profile service --target "$tmp/symlink"; then fail 'service symlink marker guard'; fi
[ "$(find "$tmp/symlink" -mindepth 1 -print | wc -l | tr -d ' ')" = 2 ] || fail 'symlink marker changed target'

printf 'keep\n' > "$tmp/lib-b/README.md"
if sh "$generator" --profile library --target "$tmp/lib-b"; then fail 'overwrite guard'; fi
mkdir "$tmp/escape"
escape_before=$(ls -la "$tmp/escape")
if sh "$generator" --profile library --target "$tmp/lib-a/../escape"; then fail 'traversal guard'; fi
[ "$escape_before" = "$(ls -la "$tmp/escape")" ] || fail 'traversal wrote outside target'
printf 'outside\n' > "$tmp/outside"
if sh "$generator" --profile library --target "$tmp/outside"; then fail 'file target guard'; fi

fixture_root="$tmp/race-fixture"
mkdir -p "$fixture_root/scripts"
ln -s "$root/plugins/coding-pipeline/templates" "$fixture_root/templates"
fixture="$fixture_root/scripts/init-python-harness.sh"
cp "$generator" "$fixture"
python3 - "$fixture" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
needle = '    ln "$stage/$file" "$target/$file" ||'
replacement = '    if [ "$file" = QUALITY.md ]; then sleep 1; fi\n' + needle
if text.count(needle) != 1:
    raise SystemExit('fixture synchronization anchor missing')
path.write_text(text.replace(needle, replacement))
PY
rollback_target="$tmp/rollback"
mkdir "$rollback_target"
(
    while [ ! -e "$rollback_target/README.md" ]; do sleep 0.01; done
    printf 'race\n' > "$rollback_target/QUALITY.md"
) &
racer=$!
if sh "$fixture" --profile library --target "$rollback_target"; then fail 'race no-clobber'; fi
wait "$racer"
[ "$(find "$rollback_target" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')" = 1 ] || fail 'rollback removed race file or left generated file'
[ -f "$rollback_target/QUALITY.md" ] || fail 'race file not preserved'
[ ! -e "$rollback_target/pyproject.toml" ] || fail 'rollback left partial output'

concurrent_target="$tmp/concurrent"
mkdir "$concurrent_target"
pids=
for _ in 1 2 3 4 5 6 7 8; do
    sh "$generator" --profile library --target "$concurrent_target" >"$tmp/concurrent.$_" 2>&1 &
    pids="$pids $!"
done
concurrent_failures=0
for pid in $pids; do wait "$pid" || concurrent_failures=$((concurrent_failures + 1)); done
[ "$concurrent_failures" -ge 1 ] || fail 'concurrent no-clobber race not observed'
[ "$(find "$concurrent_target" -maxdepth 1 -type f | wc -l | tr -d ' ')" = 3 ] || fail 'concurrent artifact set'

metadata_target="$tmp/metadata-check"
mkdir "$metadata_target"
sh "$generator" --profile library --target "$metadata_target" >/dev/null || fail 'metadata generation'
if grep -R -E '/(Users|home|var/folders)/|/tmp/|Harness-devkit|/gabs/' "$metadata_target" >/dev/null; then fail 'metadata contains machine path'; fi

for profile in library service; do
    target="$tmp/$profile-check"
    mkdir "$target"
    if [ "$profile" = service ]; then
        printf '[project]\nname = "check"\n' > "$target/pyproject.toml"
    fi
    sh "$generator" --profile "$profile" --target "$target" >/dev/null || fail "$profile portable generation"
    if find "$target" -type f -print | grep -E '(^|/)(app|main|server|deploy|Dockerfile|docker-compose|wsgi|asgi)(\.|$)|\.service$' >/dev/null; then
        fail "$profile emitted application artifact"
    fi
    if grep -R -E '/(Users|home|var/folders)/|/tmp/|Harness-devkit|/gabs/' "$target" >/dev/null; then
        fail "$profile metadata contains machine path"
    fi
done

if sh "$generator" --profile nope --target "$tmp/lib-a"; then fail 'invalid profile accepted'; fi
if sh "$generator" --profile library; then fail 'missing target accepted'; fi
printf 'PASS: python harness bootstrap\n'
