# PR2 Story: OpenCode permissions and managed artifacts

## Frozen decisions

- All generated agents contain explicit `permission:` frontmatter for every supported action.
- Coding personas (`coder-backend`, `coder-frontend`, `devops`) allow file/read/navigation capabilities, ask for `bash`, deny delegation, and deny external directories, web search, and doom loops.
- `analyst` allows edit for Project Brief artifacts while denying shell, delegation, and network access.
- `bug-investigator` allows edit for RED tests and asks for shell, without delegation.
- `architect`, `pm`, and `scrum-master` allow edit and ask for task delegation while denying shell.
- `plan-reviewer` is strictly read-only and denies edit, shell, task delegation, and todo mutation.
- `tuner` allows edit and asks for shell without delegation.
- Rote specialists allow edit, shell, task, web, and external-directory access required by their adapter/analytics/GitHub/Datadog duties.
- QA, reviewer, stress, and verdict remain read-only.
- The committed JSON is a non-active `opencode.template.json` and has only the schema key. Commands are three additive wrappers: `task`, `multi-agent`, and `quality-gate`.

## Falsification evidence

OC-08–OC-11 are the original frozen rows recovered from the committed PR1 contract and remained green in regression runs; they are not newly falsified here. PR2 additions are OC-15–OC-18 and were independently falsified:

| Test | Implementation mutation | Selected command and observed failure | Restoration |
|---|---|---|---|
| OC-15 | Mutated one emitted policy value at a time and ran `bash .github/scripts/test-opencode-install.sh OC-15`: analyst `edit allow→deny`; read-only reviewer `edit deny→allow`; plan-reviewer `edit deny→allow`; tuner `bash ask→deny`; coder/devops `edit allow→deny`; bug-investigator `task deny→ask`; rote specialists `websearch allow→deny`; default read-only `doom_loop deny→allow` | Each run exited 1 on the exact assertion `permission policy mismatch: {...}` for the mutated persona/policy; no whole permission block was removed | Restored each single value; after every restoration `bash .github/scripts/test-opencode-install.sh OC-15` passed |
| OC-16 | Changed template schema URL to `https://example.invalid/config.json` | `bash .github/scripts/test-opencode-install.sh OC-16`; Python contract exited 1 with `AssertionError` | Restored official schema URL; OC-16 passed |
| OC-17 | Replaced task wrapper text `canonical \`task\` skill` with `canonical workflow` | `bash .github/scripts/test-opencode-install.sh OC-17`; `not found: skill` | Restored canonical reference; OC-17 passed |
| OC-18 | Removed unmanaged command using `rm -f "$OPENCODE_DIR/commands/custom.md"` after copy | `bash .github/scripts/test-opencode-install.sh OC-18`; `unmanaged OpenCode command changed` | Removed mutation; OC-18 passed |

Final selected reruns were green, followed by the full OC-01–OC-18 suite.
