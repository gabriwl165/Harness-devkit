# Delivery: OpenCode integration (cc594c)

Base: `74e964f`  
Release branch: `release/opencode-integration-cc594c`  
Worktree: `.worktrees/dlv-cc594c`  
Status: PR2 implementation complete; parent orchestrator owns validation and PR sequencing.

## Codebase/reuse map

| Component | Decision | Existing contract reused |
|---|---|---|
| OpenCode skill installer | extend | `scripts/install-codex.sh:30-60` path walk and selective skill copy |
| OpenCode agent generator | extend | `scripts/generate-codex-agents.sh:45-59,115-122` persona list and coder composition |
| Acceptance tests | new | `install-codex.sh` temp-target convention (`:26-27`) |

## Frozen acceptance criteria

- AC1: user-global defaults are `${AGENTS_HOME:-$HOME/.agents}/skills` and `${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/agents`; explicit overrides support isolated tests.
- AC2: installation is additive/idempotent, preserves unrelated files, and copies only `SKILL.md` plus complete `references/` trees.
- AC3: generated files are OpenCode Markdown with `description` and `mode: subagent`, preserving persona descriptions and prompt bodies without Claude tools frontmatter.
- AC4: every supported non-standalone persona is generated; backend/frontend coder output is core plus exactly one overlay.
- AC5: PR2 emits explicit least-privilege `permission` mappings for every generated persona; permissions use only supported OpenCode actions.
- AC6: Linux/macOS Bash scripts run without dependencies beyond standard shell utilities.

## Frozen test table (complete OC-01–OC-14)

| ID | Input/precondition | Expected observable result | AC | Why it matters |
|---|---|---|---|---|
| OC-01 | Run installer with both temp overrides | Skills and agents land in the two requested roots | AC1 | Prevents writes to the real home and catches path drift |
| OC-02 | Install repository containing SkillSpec artifacts | Only SKILL.md and references trees are copied; no artifacts or standalone coder | AC2/AC4 | Keeps native destinations clean |
| OC-03 | Preseed unmanaged files, install | Preseeded files remain byte-for-byte unchanged | AC2 | Protects user-owned configuration |
| OC-04 | Install twice, snapshot files | Second run has identical file set and contents | AC2 | Makes refresh safe |
| OC-05 | Generate all supported personas | Exactly 18 expected Markdown files exist with descriptions and `mode: subagent` | AC3/AC4 | Ensures persona coverage and parseability |
| OC-06 | Generate coder variants | Backend/frontend each contain core + one matching overlay; `coder.md` absent | AC4 | Preserves dispatch composition |
| OC-07 | Parse generated frontmatter | Every file starts with valid required OpenCode keys and body follows delimiter | AC3 | Prevents OpenCode discovery failures |
| OC-08 | Run installer with no overrides in a guarded HOME | Writes occur only under guarded HOME-derived defaults | AC1 | Verifies default target semantics |
| OC-09 | Use one explicit override and one default | Explicit destination wins without changing the other default | AC1 | Protects composable test/deployment setups |
| OC-10 | Skill with nested references | Nested reference files and directories are retained | AC2 | Preserves linked guidance |
| OC-11 | Existing generated agent and custom agent coexist | Generated agent updates; custom agent remains | AC2/AC3 | Makes regeneration additive |
| OC-12 | Inspect generated body and description | Source description/body are preserved; `tools`/`model` frontmatter is absent | AC3 | Avoids emitting Claude-only schema |
| OC-13 | Inspect coder variants | Core occurs once and exactly one overlay occurs in each variant | AC4 | Prevents duplicate or incomplete composition |
| OC-14 | Inspect PR1 outputs/docs | No permissions field is generated; docs mark permission mapping pending PR2 | AC5 | Keeps sequential PR boundary explicit |

## Three-story manifest

1. **S1 — OpenCode installer (PR1)**: implement safe default/override paths and selective additive skill installation.
2. **S2 — OpenCode persona generator (PR1)**: emit parseable Markdown and composed coder variants, with permissions pending PR2.
3. **S3 — OpenCode acceptance evidence (PR1)**: add exactly OC-01–OC-07 executable tests and falsification record; OC-08–OC-14 remain documented rows for the series.

PR2 additions use OC-15–OC-18: explicit per-persona permissions; schema-only template; exact thin canonical command wrappers; and additive unmanaged command/config preservation. OC-08–OC-11 remain the original frozen PR1 rows and are executed unchanged by the default suite.

## Falsification evidence

OC-01–OC-07 were each falsified one at a time by mutating implementation paths, observing the intended assertion fail, restoring the mutation, and rerunning the selected test green. The durable transcript is in `docs/deliveries/cc594c/falsification-opencode-pr1.md`.
