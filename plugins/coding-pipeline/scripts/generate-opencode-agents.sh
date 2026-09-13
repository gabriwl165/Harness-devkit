#!/usr/bin/env bash
# Generate parseable OpenCode Markdown agents from the pipeline personas.
# PR1 deliberately leaves permission mapping to PR2; no permissions are emitted.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$(cd "$SCRIPT_DIR/../agents" && pwd)"
TARGET="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/agents"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir) [ "$#" -ge 2 ] || exit 2; TARGET="$2"; shift 2 ;;
        -h|--help) printf 'Usage: %s [--output-dir DIR]\n' "$(basename "$0")"; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done
mkdir -p "$TARGET"

frontmatter_field() {
    awk -v field="$2" 'NR == 1 && $0 == "---" { inside=1; next } inside && $0 == "---" { exit } inside && $0 ~ "^" field ":" { sub("^" field ":[[:space:]]*", ""); print; exit }' "$1"
}
body_of() {
    awk 'NR == 1 && $0 == "---" { n=1; next } n == 1 && $0 == "---" { n=2; next } n == 2 { print }' "$1"
}

write_agent() {
    local output_name="$1" core="$2" overlay="${3:-}" description body
    description="$(frontmatter_field "$core" description)"
    body="$(body_of "$core")"
    if [ -n "$overlay" ]; then
        body="$body

$(body_of "$overlay")"
    fi
    # Description and mode are the only required OpenCode agent frontmatter.
    {
        printf '%s\n' '---'
        printf 'description: %s\n' "$description"
        printf 'mode: subagent\n'
        printf '%s\n\n' '---'
        printf '%s\n' "$body"
    } > "$TARGET/$output_name.md"
}

for persona in analyst architect bug-investigator devops plan-reviewer pm qa reviewer \
    rote-adapter rote-analytics rote-datadog rote-github scrum-master stress tuner verdict; do
    write_agent "$persona" "$AGENTS_DIR/$persona.md"
done
write_agent coder-backend "$AGENTS_DIR/coder.md" "$AGENTS_DIR/coder-backend.md"
write_agent coder-frontend "$AGENTS_DIR/coder.md" "$AGENTS_DIR/coder-frontend.md"
printf 'Generated %s OpenCode agents in %s (permissions pending PR2).\n' \
    "$(find "$TARGET" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')" "$TARGET"
