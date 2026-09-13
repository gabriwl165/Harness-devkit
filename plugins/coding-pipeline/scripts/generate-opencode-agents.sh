#!/usr/bin/env bash
# Generate parseable OpenCode Markdown agents from the pipeline personas.
# OpenCode permissions are explicit and deny-by-default; this mapping is the PR2 contract.
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
    local output_name="$1" core="$2" overlay="${3:-}" description body permission
    description="$(frontmatter_field "$core" description)"
    body="$(body_of "$core")"
    if [ -n "$overlay" ]; then
        body="$body

$(body_of "$overlay")"
    fi
    permission="$(permission_for "$output_name")"
    {
        printf '%s\n' '---'
        printf 'description: %s\n' "$description"
        printf 'mode: subagent\n'
        printf '%s\n' 'permission:'
        printf '%s\n' "$permission"
        printf '%s\n\n' '---'
        printf '%s\n' "$body"
    } > "$TARGET/$output_name.md"
}

permission_for() {
    case "$1" in
        coder-backend|coder-frontend|devops|tuner)
            cat <<'PERMISSIONS'
  read: allow
  edit: allow
  glob: allow
  grep: allow
  list: allow
  bash: ask
  task: deny
  external_directory: deny
  todowrite: allow
  question: allow
  webfetch: allow
  websearch: deny
  lsp: allow
  doom_loop: deny
  skill: allow
PERMISSIONS
            ;;
        bug-investigator)
            cat <<'PERMISSIONS'
  read: allow
  edit: allow
  glob: allow
  grep: allow
  list: allow
  bash: ask
  task: deny
  external_directory: deny
  todowrite: allow
  question: allow
  webfetch: allow
  websearch: deny
  lsp: allow
  doom_loop: deny
  skill: allow
PERMISSIONS
            ;;
        analyst)
            cat <<'PERMISSIONS'
  read: allow
  edit: allow
  glob: allow
  grep: allow
  list: allow
  bash: deny
  task: deny
  external_directory: deny
  todowrite: allow
  question: allow
  webfetch: deny
  websearch: deny
  lsp: deny
  doom_loop: deny
  skill: allow
PERMISSIONS
            ;;
        architect|pm|scrum-master)
            cat <<'PERMISSIONS'
  read: allow
  edit: allow
  glob: allow
  grep: allow
  list: allow
  bash: deny
  task: ask
  external_directory: deny
  todowrite: allow
  question: allow
  webfetch: allow
  websearch: deny
  lsp: deny
  doom_loop: deny
  skill: allow
PERMISSIONS
            ;;
        plan-reviewer)
            cat <<'PERMISSIONS'
  read: allow
  edit: deny
  glob: allow
  grep: allow
  list: allow
  bash: deny
  task: deny
  external_directory: deny
  todowrite: deny
  question: allow
  webfetch: allow
  websearch: deny
  lsp: deny
  doom_loop: deny
  skill: allow
PERMISSIONS
            ;;
        rote-adapter|rote-analytics|rote-datadog|rote-github)
            cat <<'PERMISSIONS'
  read: allow
  edit: allow
  glob: allow
  grep: allow
  list: allow
  bash: ask
  task: ask
  external_directory: allow
  todowrite: allow
  question: allow
  webfetch: allow
  websearch: allow
  lsp: allow
  doom_loop: deny
  skill: allow
PERMISSIONS
            ;;
        *)
            cat <<'PERMISSIONS'
  read: allow
  edit: deny
  glob: allow
  grep: allow
  list: allow
  bash: deny
  task: deny
  external_directory: deny
  todowrite: deny
  question: allow
  webfetch: allow
  websearch: deny
  lsp: deny
  doom_loop: deny
  skill: allow
PERMISSIONS
            ;;
    esac
}

for persona in analyst architect bug-investigator devops plan-reviewer pm qa reviewer \
    rote-adapter rote-analytics rote-datadog rote-github scrum-master stress tuner verdict; do
    write_agent "$persona" "$AGENTS_DIR/$persona.md"
done
write_agent coder-backend "$AGENTS_DIR/coder.md" "$AGENTS_DIR/coder-backend.md"
write_agent coder-frontend "$AGENTS_DIR/coder.md" "$AGENTS_DIR/coder-frontend.md"
printf 'Generated %s OpenCode agents in %s with explicit permissions.\n' \
    "$(find "$TARGET" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')" "$TARGET"
