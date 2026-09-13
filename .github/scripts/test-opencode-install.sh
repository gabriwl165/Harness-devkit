#!/usr/bin/env bash
# OC-01–OC-07 executable acceptance tests. Tests use only temporary destinations.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/plugins/coding-pipeline/scripts/install-opencode.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
assert_file() { [ -f "$1" ] || { printf 'missing: %s\n' "$1" >&2; exit 1; }; }
assert_contains() { grep -qF -- "$2" "$1" || { printf 'not found: %s\n' "$2" >&2; exit 1; }; }
assert_permission() {
    python3 - "$1" "$2" <<'PY'
import sys
from pathlib import Path
path, persona = sys.argv[1:]
actions = {'read','edit','glob','grep','list','bash','task','external_directory','todowrite','question','webfetch','websearch','lsp','doom_loop','skill'}
lines = Path(path).read_text().splitlines()
assert lines[0] == '---'
end = lines.index('---', 1)
front = lines[1:end]
assert 'permission:' in front
values = {}
for line in front[front.index('permission:') + 1:]:
    if not line.startswith('  '): break
    key, value = line.strip().split(': ', 1)
    assert key in actions and value in {'allow','ask','deny'}
    values[key] = value
assert set(values) == actions
coding = {'coder-backend','coder-frontend','devops','tuner'}
bug = {'bug-investigator'}
artifact = {'architect','pm','scrum-master','plan-reviewer'}
rote = {'rote-adapter','rote-analytics','rote-datadog','rote-github'}
def policy(**overrides):
    result = dict.fromkeys(actions, 'deny')
    result.update(read='allow', glob='allow', grep='allow', list='allow', question='allow', skill='allow')
    result.update(overrides)
    return result
expected = {}
for name in coding:
    expected[name] = policy(edit='allow', bash='ask', todowrite='allow', webfetch='allow', lsp='allow')
expected['bug-investigator'] = policy(edit='allow', bash='ask', todowrite='allow', webfetch='allow', lsp='allow')
expected['analyst'] = policy(edit='allow', todowrite='allow', webfetch='deny')
for name in {'architect','pm','scrum-master'}:
    expected[name] = policy(edit='allow', task='ask', todowrite='allow', webfetch='allow')
expected['plan-reviewer'] = policy(webfetch='allow')
for name in rote:
    expected[name] = policy(edit='allow', bash='ask', task='ask', external_directory='allow', todowrite='allow', webfetch='allow', websearch='allow', lsp='allow')
for name in {'qa','reviewer','stress','verdict'}:
    expected[name] = policy(webfetch='allow')
assert values == expected[persona], f'{persona} permission policy mismatch: {values}'
PY
}
assert_frontmatter() {
    awk '
        NR == 1 { if ($0 != "---") exit 1; in_frontmatter = 1; next }
        in_frontmatter && $0 == "---" { closed = 1; in_frontmatter = 0; next }
        in_frontmatter {
            if ($0 ~ /^description:[[:space:]]*[^[:space:]].*$/) description = 1
            if ($0 == "mode: subagent") mode = 1
            if ($0 ~ /^(tools|model):/) invalid = 1
            next
        }
        !in_frontmatter && NF { body = 1 }
        END { exit !(closed && description && mode && !invalid && body) }
    ' "$1" || { printf 'invalid OpenCode frontmatter/body: %s\n' "$1" >&2; exit 1; }
}
install_fixture() {
    bash "$INSTALL" --agents-home "$TMP/agents-home" --opencode-config-dir "$TMP/config" "$@" >/dev/null
}
create_skill_fixture() {
    mkdir -p "$TMP/source/plugins/fixture/skills/fixture-skill/references/nested" \
        "$TMP/source/plugins/fixture/skills/fixture-skill/source/nested" \
        "$TMP/source/plugins/fixture/skills/fixture-skill/imports/nested" \
        "$TMP/source/plugins/fixture/skills/fixture-skill/resources/nested" \
        "$TMP/source/plugins/fixture/skills/fixture-skill/.skillspec/nested"
    printf '%s\n' '---' 'name: fixture-skill' 'description: fixture' '---' > "$TMP/source/plugins/fixture/skills/fixture-skill/SKILL.md"
    printf 'reference\n' > "$TMP/source/plugins/fixture/skills/fixture-skill/references/root.md"
    printf 'nested reference\n' > "$TMP/source/plugins/fixture/skills/fixture-skill/references/nested/guide.md"
    printf 'artifact\n' > "$TMP/source/plugins/fixture/skills/fixture-skill/skill.spec.yml"
    printf 'artifact\n' > "$TMP/source/plugins/fixture/skills/fixture-skill/deps.toml"
    for dir in source imports resources .skillspec; do printf 'artifact\n' > "$TMP/source/plugins/fixture/skills/fixture-skill/$dir/nested/file.txt"; done
}

oc_01_locations() {
    install_fixture
    assert_file "$TMP/agents-home/skills/task/SKILL.md"
    assert_file "$TMP/config/agents/analyst.md"
}
oc_02_exclusions() {
    create_skill_fixture
    install_fixture --source-root "$TMP/source/plugins"
    assert_file "$TMP/agents-home/skills/fixture-skill/SKILL.md"
    assert_contains "$TMP/agents-home/skills/fixture-skill/references/root.md" reference
    assert_contains "$TMP/agents-home/skills/fixture-skill/references/nested/guide.md" 'nested reference'
    for artifact in skill.spec.yml deps.toml source imports resources .skillspec; do
        [ ! -e "$TMP/agents-home/skills/fixture-skill/$artifact" ] || { printf 'forbidden artifact copied: %s\n' "$artifact" >&2; exit 1; }
    done
    [ ! -e "$TMP/config/agents/coder.md" ]
}
oc_03_preservation() {
    printf 'keep\n' > "$TMP/agents-home/keep.txt"
    printf 'custom\n' > "$TMP/config/agents/custom.md"
    printf 'command\n' > "$TMP/config/custom-command.md"
    printf 'config\n' > "$TMP/config/config.json"
    keep_before="$TMP/keep-before"
    custom_before="$TMP/custom-before"
    command_before="$TMP/command-before"
    config_before="$TMP/config-before.json"
    cp "$TMP/agents-home/keep.txt" "$keep_before"
    cp "$TMP/config/agents/custom.md" "$custom_before"
    cp "$TMP/config/custom-command.md" "$command_before"
    cp "$TMP/config/config.json" "$config_before"
    install_fixture
    cmp -s "$keep_before" "$TMP/agents-home/keep.txt" || { printf 'unmanaged skill-root file changed\n' >&2; exit 1; }
    cmp -s "$custom_before" "$TMP/config/agents/custom.md" || { printf 'unmanaged agent file changed\n' >&2; exit 1; }
    cmp -s "$command_before" "$TMP/config/custom-command.md" || { printf 'unmanaged command file changed\n' >&2; exit 1; }
    cmp -s "$config_before" "$TMP/config/config.json" || { printf 'unmanaged config file changed\n' >&2; exit 1; }
}
oc_04_idempotency() {
    cp -R "$TMP/agents-home" "$TMP/agents-before"
    cp -R "$TMP/config" "$TMP/config-before"
    install_fixture
    diff -ru "$TMP/agents-before" "$TMP/agents-home" >/dev/null
    diff -ru "$TMP/config-before" "$TMP/config" >/dev/null
    assert_file "$TMP/config/agents/analyst.md"
}
oc_05_persona_coverage() {
    count="$(find "$TMP/config/agents" -maxdepth 1 -type f -name '*.md' ! -name custom.md | wc -l | tr -d ' ')"
    [ "$count" -eq 18 ]
    for name in analyst architect bug-investigator devops plan-reviewer pm qa reviewer rote-adapter rote-analytics rote-datadog rote-github scrum-master stress tuner verdict coder-backend coder-frontend; do
        assert_file "$TMP/config/agents/$name.md"
        assert_contains "$TMP/config/agents/$name.md" 'mode: subagent'
    done
}
oc_06_coder_composition() {
    assert_contains "$TMP/config/agents/coder-backend.md" 'This file is the **shared Coder core**'
    assert_contains "$TMP/config/agents/coder-backend.md" 'Coder overlay — Backend'
    assert_contains "$TMP/config/agents/coder-frontend.md" 'This file is the **shared Coder core**'
    assert_contains "$TMP/config/agents/coder-frontend.md" 'Coder overlay — Frontend'
    [ "$(grep -cF 'This file is the **shared Coder core**' "$TMP/config/agents/coder-backend.md")" -eq 1 ]
    [ "$(grep -cF 'This file is the **shared Coder core**' "$TMP/config/agents/coder-frontend.md")" -eq 1 ]
    [ "$(grep -cF 'Coder overlay — Backend' "$TMP/config/agents/coder-backend.md")" -eq 1 ]
    [ "$(grep -cF 'Coder overlay — Frontend' "$TMP/config/agents/coder-frontend.md")" -eq 1 ]
    [ "$(grep -cF 'Coder overlay — Frontend' "$TMP/config/agents/coder-backend.md" || true)" -eq 0 ]
    [ "$(grep -cF 'Coder overlay — Backend' "$TMP/config/agents/coder-frontend.md" || true)" -eq 0 ]
    [ ! -e "$TMP/config/agents/coder.md" ]
}
oc_07_parseability() {
    for file in "$TMP/config/agents"/*.md; do
        [ "$(basename "$file")" = custom.md ] && continue
        assert_frontmatter "$file"
    done
}
oc_08_locations_default() {
    home="$TMP/home"
    HOME="$home" AGENTS_HOME='' OPENCODE_CONFIG_DIR='' bash "$INSTALL" >/dev/null
    assert_file "$home/.agents/skills/task/SKILL.md"
    assert_file "$home/.config/opencode/agents/analyst.md"
}
oc_09_locations_override() {
    mkdir -p "$TMP/default-home"
    HOME="$TMP/default-home" AGENTS_HOME="$TMP/explicit-agents" OPENCODE_CONFIG_DIR='' bash "$INSTALL" >/dev/null
    assert_file "$TMP/explicit-agents/skills/task/SKILL.md"
    assert_file "$TMP/default-home/.config/opencode/agents/analyst.md"
}
oc_10_nested_references() {
    create_skill_fixture
    install_fixture --source-root "$TMP/source/plugins"
    assert_contains "$TMP/agents-home/skills/fixture-skill/references/nested/guide.md" 'nested reference'
}
oc_11_custom_agent() {
    install_fixture
    printf 'custom\n' > "$TMP/config/agents/custom.md"
    before="$TMP/custom-agent-before"
    cp "$TMP/config/agents/custom.md" "$before"
    install_fixture
    cmp -s "$before" "$TMP/config/agents/custom.md" || { printf 'custom agent changed\n' >&2; exit 1; }
    assert_file "$TMP/config/agents/analyst.md"
}
oc_08_permissions() {
    for file in "$TMP/config/agents"/*.md; do
        [ "$(basename "$file")" = custom.md ] && continue
        assert_permission "$file" "$(basename "$file" .md)"
    done
}
oc_09_config_contract() {
    assert_file "$TMP/config/opencode.template.json"
    python3 - "$TMP/config/opencode.template.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text())
assert data == {'$schema': 'https://opencode.ai/config.json'}
PY
}
oc_10_commands() {
    [ "$(find "$TMP/config/commands" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')" -eq 3 ]
    for file in "$TMP/config/commands"/*.md; do
        assert_contains "$file" 'canonical'
        assert_contains "$file" 'skill'
    done
}
oc_11_preserve_opencode_user_files() {
    printf 'keep command\n' > "$TMP/config/commands/custom.md"
    printf '{"custom":true}\n' > "$TMP/config/opencode.json"
    cp "$TMP/config/commands/custom.md" "$TMP/custom-command-before"
    cp "$TMP/config/opencode.json" "$TMP/config-before.json"
    install_fixture
    cmp -s "$TMP/custom-command-before" "$TMP/config/commands/custom.md" || { printf 'unmanaged OpenCode command changed\n' >&2; exit 1; }
    cmp -s "$TMP/config-before.json" "$TMP/config/opencode.json" || { printf 'unmanaged OpenCode config changed\n' >&2; exit 1; }
}
oc_15_permission_contract() {
    oc_08_permissions
}
oc_16_config_contract() {
    oc_09_config_contract
}
oc_17_command_contract() {
    [ "$(find "$TMP/config/commands" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')" -eq 3 ]
    for name in task multi-agent quality-gate; do
        file="$TMP/config/commands/$name.md"
        assert_file "$file"
        assert_contains "$file" "canonical \`${name}\` skill"
        [ "$(wc -l < "$file" | tr -d ' ')" -le 8 ] || { printf 'command wrapper too large: %s\n' "$name" >&2; exit 1; }
        [ "$(grep -cF -- '---' "$file")" -eq 2 ] || { printf 'command frontmatter malformed: %s\n' "$name" >&2; exit 1; }
    done
}
oc_18_additive_files() {
    oc_11_preserve_opencode_user_files
}

selected="${1:-all}"
case "$selected" in
    all) oc_01_locations; oc_02_exclusions; oc_03_preservation; oc_04_idempotency; oc_05_persona_coverage; oc_06_coder_composition; oc_07_parseability; oc_08_locations_default; oc_09_locations_override; oc_10_nested_references; oc_11_custom_agent; oc_15_permission_contract; oc_16_config_contract; oc_17_command_contract; oc_18_additive_files ;;
    OC-01) oc_01_locations ;;
    OC-02) install_fixture; oc_02_exclusions ;;
    OC-03) install_fixture; oc_03_preservation ;;
    OC-04) install_fixture; oc_04_idempotency ;;
    OC-05) install_fixture; oc_05_persona_coverage ;;
    OC-06) install_fixture; oc_06_coder_composition ;;
    OC-07) install_fixture; oc_07_parseability ;;
    OC-08) oc_08_locations_default ;;
    OC-09) oc_09_locations_override ;;
    OC-10) oc_10_nested_references ;;
    OC-11) oc_11_custom_agent ;;
    OC-15) install_fixture; oc_15_permission_contract ;;
    OC-16) install_fixture; oc_16_config_contract ;;
    OC-17) install_fixture; oc_17_command_contract ;;
    OC-18) install_fixture; oc_18_additive_files ;;
    *) printf 'Usage: %s [OC-01..OC-11|OC-15..OC-18]\n' "$0" >&2; exit 2 ;;
esac
printf 'OC-01–OC-18 passed\n'
