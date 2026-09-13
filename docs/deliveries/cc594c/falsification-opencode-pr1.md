# PR1 falsification transcript

All commands below ran from `.worktrees/dlv-cc594c`. Each mutation was applied to an implementation file, the selected test was run, the mutation was restored immediately, and the selected test was rerun green. Failure output is quoted exactly; no setup failure is used as evidence.

| Test | Mutation command | Observed intended failure assertion | Restoration and final green |
|---|---|---|---|
| OC-01 | Exact replacement in installer: `dest="$AGENTS_HOME_TARGET/skills/$name"` → `dest="$OPENCODE_DIR/skills/$name"`; command: `bash .github/scripts/test-opencode-install.sh OC-01` | `missing: /var/.../agents-home/skills/task/SKILL.md` | Restored exact assignment; selected test passed |
| OC-02 | Exact replacement in installer: `cp "$skill_dir/SKILL.md" "$dest/SKILL.md"` → `cp -R "$skill_dir/." "$dest/"`; command: `bash .github/scripts/test-opencode-install.sh OC-02` | `forbidden artifact copied: skill.spec.yml` | Restored exact selective copy; selected test passed |
| OC-03 | Exact replacement in installer: `bash "$SCRIPT_DIR/generate-opencode-agents.sh" --output-dir "$OPENCODE_DIR/agents"` → same command plus `; rm -f "$OPENCODE_DIR/agents/custom.md"`; command: `bash .github/scripts/test-opencode-install.sh OC-03` | `unmanaged agent file changed` | Restored exact command; selected test passed |
| OC-04 | Exact replacement in installer: `bash "$SCRIPT_DIR/generate-opencode-agents.sh" --output-dir "$OPENCODE_DIR/agents"` → same command plus `\nrm -f "$OPENCODE_DIR/agents/analyst.md"`; command: `bash .github/scripts/test-opencode-install.sh OC-04` | Exit status `1` at `diff -ru "$TMP/config-before" "$TMP/config" >/dev/null`; no failure text was printed because the diff output is redirected | Restored exact command; `bash .github/scripts/test-opencode-install.sh OC-04` passed |
| OC-05 | Exact replacement in generator persona list: `stress tuner verdict; do` → `stress tuner; do`; command: `bash .github/scripts/test-opencode-install.sh OC-05` | Exit status 1 from `[ "$count" -eq 18 ]` | Restored `verdict`; selected test passed |
| OC-06 | Exact replacement: `write_agent coder-backend "$AGENTS_DIR/coder.md" "$AGENTS_DIR/coder-backend.md"` → `write_agent coder-backend "$AGENTS_DIR/coder.md"`; command: `bash .github/scripts/test-opencode-install.sh OC-06` | `not found: Coder overlay — Backend` | Restored backend overlay argument; selected test passed |
| OC-07 | Exact replacement in generator: `printf 'mode: subagent\n'` → `printf 'mode: primary\n'`; command: `bash .github/scripts/test-opencode-install.sh OC-07` | `invalid OpenCode frontmatter/body: .../analyst.md` | Restored `mode: subagent`; selected test passed |

Final green transcript:

```text
$ bash .github/scripts/test-opencode-install.sh
OC-01–OC-07 passed
```

The mutation commands are recorded as exact path-level changes and were applied/reverted in the worktree; no mutation remains in the implementation.
