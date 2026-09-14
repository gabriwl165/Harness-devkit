#!/bin/sh
set -eu
usage() { printf '%s\n' 'Usage: init-python-harness.sh --profile library|service --target <directory> [--dry-run]' >&2; exit 2; }
profile= target= dry_run=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile) [ "$#" -ge 2 ] || usage; profile=$2; shift 2 ;;
        --target) [ "$#" -ge 2 ] || usage; target=$2; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        *) usage ;;
    esac
done
[ "$profile" = library ] || [ "$profile" = service ] || usage
[ -n "$target" ] || usage
case "/$target/" in */../*|*/..|../*) printf '%s\n' 'error: target must not contain traversal components' >&2; exit 1 ;; esac
[ -d "$target" ] || { printf '%s\n' 'error: target is not a directory' >&2; exit 1; }
if [ "$profile" = service ]; then
    [ -f "$target/pyproject.toml" ] && [ -r "$target/pyproject.toml" ] && [ ! -L "$target/pyproject.toml" ] || { printf '%s\n' 'error: service profile requires a readable regular pyproject.toml' >&2; exit 1; }
    files='README.md QUALITY.md'
else
    files='pyproject.toml README.md QUALITY.md'
fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
template_dir=$script_dir/../templates/python-harness/$profile
for file in $files; do
    [ -f "$template_dir/$file" ] || { printf 'error: missing template: %s\n' "$file" >&2; exit 1; }
    [ ! -e "$target/$file" ] || { printf 'error: refusing to overwrite: %s\n' "$file" >&2; exit 1; }
done
if [ "$dry_run" = true ]; then
    printf 'profile=%s\n' "$profile"
    for file in $files; do printf 'create %s\n' "$file"; done
    exit 0
fi
[ -w "$target" ] || { printf '%s\n' 'error: target is not writable' >&2; exit 1; }
stage=$(mktemp -d "$target/.python-harness-bootstrap.XXXXXX") || exit 1
created=
rollback() {
    for file in $created; do rm "$target/$file" 2>/dev/null || :; done
}
cleanup() { rollback; rm -rf "$stage"; }
trap cleanup EXIT HUP INT TERM
for file in $files; do cp "$template_dir/$file" "$stage/$file"; done
for file in $files; do
    ln "$stage/$file" "$target/$file" || { printf 'error: refusing to create: %s\n' "$file" >&2; exit 1; }
    created="$created $file"
done
trap - EXIT HUP INT TERM
rm -rf "$stage"
printf 'initialized profile=%s\n' "$profile"
