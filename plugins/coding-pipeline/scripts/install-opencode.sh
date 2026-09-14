#!/usr/bin/env bash
# Install the devkit's native OpenCode skills and generated agent source.
# Additive and idempotent: unrelated files in either destination are preserved.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENTS_HOME_TARGET="${AGENTS_HOME:-$HOME/.agents}"
OPENCODE_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

usage() {
    printf 'Usage: %s [--agents-home DIR] [--opencode-config-dir DIR] [--source-root DIR]\n' "$(basename "$0")"
    printf '  --source-root DIR  advanced test/packaging override for the plugins source root\n'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --agents-home) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; AGENTS_HOME_TARGET="$2"; shift 2 ;;
        --opencode-config-dir) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; OPENCODE_DIR="$2"; shift 2 ;;
        --source-root) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; PLUGINS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

mkdir -p "$AGENTS_HOME_TARGET/skills" "$OPENCODE_DIR/agents"
skill_count=0
for skill_dir in "$PLUGINS"/*/skills/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    name="$(basename "$skill_dir")"
    dest="$AGENTS_HOME_TARGET/skills/$name"
    mkdir -p "$dest"
    cp "$skill_dir/SKILL.md" "$dest/SKILL.md"
    if [ -d "$skill_dir/references" ]; then
        mkdir -p "$dest/references"
        cp -R "$skill_dir/references/." "$dest/references/"
    fi
    skill_count=$((skill_count + 1))
done

bash "$SCRIPT_DIR/generate-opencode-agents.sh" --output-dir "$OPENCODE_DIR/agents"
if [ -d "$SCRIPT_DIR/../opencode/commands" ]; then
    mkdir -p "$OPENCODE_DIR/commands"
    for command_file in "$SCRIPT_DIR/../opencode/commands"/*.md; do
        [ -f "$command_file" ] || continue
        cp "$command_file" "$OPENCODE_DIR/commands/"
    done
fi
if [ -f "$SCRIPT_DIR/../opencode/opencode.json" ]; then
    cp "$SCRIPT_DIR/../opencode/opencode.json" "$OPENCODE_DIR/opencode.template.json"
fi
printf 'Installed %s skills to %s/skills and OpenCode agents to %s/agents.\n' \
    "$skill_count" "$AGENTS_HOME_TARGET" "$OPENCODE_DIR"
