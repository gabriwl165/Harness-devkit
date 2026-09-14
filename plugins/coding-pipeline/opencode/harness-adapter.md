# OpenCode harness adapter

PR2 maps every generated persona to explicit OpenCode permissions. The generator emits all listed keys so an omitted capability cannot become ambient access.

| Persona group | allow | ask | deny |
|---|---|---|---|
| `coder-backend`, `coder-frontend`, `devops` | read, edit, glob, grep, list, todowrite, question, webfetch, lsp, skill | bash | task, external_directory, websearch, doom_loop |
| `tuner` | read, edit, glob, grep, list, todowrite, question, webfetch, lsp, skill | bash | task, external_directory, websearch, doom_loop |
| `bug-investigator` | read, edit, glob, grep, list, todowrite, question, webfetch, lsp, skill | bash | task, external_directory, websearch, doom_loop |
| `analyst` | read, edit, glob, grep, list, todowrite, question, skill | — | bash, task, external_directory, webfetch, websearch, lsp, doom_loop |
| `architect`, `pm`, `scrum-master` | read, edit, glob, grep, list, todowrite, question, webfetch, skill | task | bash, external_directory, websearch, lsp, doom_loop |
| `plan-reviewer` | read, glob, grep, list, question, webfetch, skill | — | edit, bash, task, external_directory, todowrite, websearch, lsp, doom_loop |
| `rote-adapter`, `rote-analytics`, `rote-datadog`, `rote-github` | read, edit, glob, grep, list, todowrite, question, webfetch, websearch, lsp, skill | bash, task | doom_loop |
| `qa`, `reviewer`, `stress`, `verdict` | read, glob, grep, list, question, webfetch, skill | — | edit, bash, task, external_directory, todowrite, websearch, lsp, doom_loop |

The mapping is intentionally conservative. `permission` is used, never Claude `tools` or deprecated OpenCode `tools`. Permission mapping is explicit in generated frontmatter and follows OpenCode's last-match-wins semantics without relying on wildcards.

## Installation and delivery boundaries

- Installer: [`scripts/install-opencode.sh`](../scripts/install-opencode.sh) copies skills to `${AGENTS_HOME:-$HOME/.agents}/skills`, generates agents with [`scripts/generate-opencode-agents.sh`](../scripts/generate-opencode-agents.sh), and installs the curated command wrappers from `opencode/commands/` plus the non-active `opencode.template.json`.
- Tests: [`.github/scripts/test-opencode-install.sh`](../../../.github/scripts/test-opencode-install.sh) uses temporary roots and does not fetch the live schema or contact a network.
- Delivery behavior: this repository keeps one worktree per delivery and uses sequential release/PR series; those rules are documented in `AGENTS.md` and `plugins/coding-pipeline/references/delivery-and-worktree.md`. OpenCode itself does not provide stacked-PR semantics.
- Limitation: generated agents and configuration are schema/contract tested, but full pipeline sequencing has not been exercised end-to-end in a live OpenCode session.
