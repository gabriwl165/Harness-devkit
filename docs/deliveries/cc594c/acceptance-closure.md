# Acceptance closure

OC-12 verifies source-to-generated descriptions and bodies for every ordinary persona and both composed coder variants, while excluding source Claude `tools`/`model` keys from generated frontmatter. OC-13 independently dispatches the coder composition assertion. OC-14 verifies integrated release traceability: permissions are present and the former PR1 no-permission criterion is documented as superseded by OC-15.

Falsification evidence:

- OC-12: mutated the generator description extraction to emit `description: mutated`; `bash .github/scripts/test-opencode-install.sh OC-12` failed with the source correspondence assertion, restored extraction, and reran green.
- OC-13: mutated backend composition to omit its overlay; `bash .github/scripts/test-opencode-install.sh OC-13` failed with `not found: Coder overlay — Backend`, restored the call, and reran green.
- OC-14 implementation branch: exact replacement in `plugins/coding-pipeline/scripts/generate-opencode-agents.sh`, `printf '%s\n' 'permission:'` → `printf '%s\n' 'permissions:'`; `bash .github/scripts/test-opencode-install.sh OC-14` failed with `AssertionError: analyst.md` from the explicit-permission assertion. Restored `permission:` and reran OC-14 green (`OC-01–OC-19 passed`).
- OC-14 documentation branch: exact replacement in `docs/deliveries/delivery-opencode-integration-cc594c.md`, the full Transition statement → `Transition statement: changed`; `bash .github/scripts/test-opencode-install.sh OC-14` failed with the exact-transition assertion (`AssertionError`, Python stderr). Restored the full statement and reran OC-14 green (`OC-01–OC-19 passed`).

The default suite covers the non-contiguous set OC-01–OC-19, with OC-12–OC-14 now explicitly dispatched; OC-08–OC-11 and OC-15–OC-19 remain green regression/PR2/PR3 coverage.
