<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Synchronize Godot documentation and bump paths-filter to 4.0.3

---



---

## Reviewer's Guide

This documentation-focused sync updates public GDScript docstrings to Godot 4 Native BBCode, clarifies helper behavior and return contracts across global utilities, and upgrades the lint workflow’s pinned path-filter dependency.

### File-Level Changes

| Change                                                                                                                                                    | Details                                                                                                                                                                                                                                                                                                                                                                                          | Files                                     |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------|
| Synchronize public GDScript API documentation with Godot 4 Native BBCode conventions and improve descriptions of parameters, behavior, and return values. | <ul><li>Replace legacy documentation tags with Native BBCode tags such as `[param]`, `[code]`, and return descriptions.</li><li>Clarify behavior for focus management, menu and scene loading, logging, version helpers, encryption checks, configuration loading, and test utilities.</li><li>Remove duplicated or stale wording and document previously undocumented public helpers.</li></ul> | `scripts/core/globals.gd`                 |
| Upgrade the pull-request path filtering action used by the lint workflow.                                                                                 | <ul><li>Pin `dorny/paths-filter` to the v4.0.3 commit instead of the v3.0.2 commit.</li></ul>                                                                                                                                                                                                                                                                                                    | `.github/workflows/lint_test_on_pull.yml` |

---



---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
