<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Synchronize Godot documentation and bump paths-filter to 4.0.3

---

## PR Summary: Synchronize Godot documentation and bump paths-filter to 4.0.3 (#989)

### Overview

Automated weekly documentation sync that standardizes public GDScript API documentation to Godot 4 Native BBCode conventions and upgrades the pull-request path-filter dependency used by the lint workflow.

### Key Changes

- **Documentation** (`scripts/core/globals.gd`)
  - Converted public member docstrings to Godot 4 Native BBCode (`##` style).
  - Clarified helper behavior, parameters, and return contracts for focus management, menu/scene loading, logging, version helpers, encryption checks, configuration loading, and test utilities.
  - Removed duplicated/stale wording and documented previously undocumented public helpers.
  - Verified non-comment source integrity (byte-for-byte) and passed documentation contract validator, `gdlint`, and Godot headless checks.

- **CI** (`.github/workflows/lint_test_on_pull.yml`)
  - Bumped `dorny/paths-filter` from `3.0.2` to the securely pinned `v4.0.3` release (commit SHA).
  - Updated related security/maintenance comments to reflect the new major version.

- **Milestone docs**
  - Added a Reviewer’s Guide describing the documentation synchronization and workflow dependency update.

### Review Highlights

- Sourcery identified and the author addressed documentation accuracy issues (empty-path handling in `load_scene_with_loading` and conditional video-player lookup in `load_key_mapping`).
- DeepSource, Codecov, and CodeRabbit also reviewed the changes.

---

## Reviewer's Guide

This documentation-focused sync updates public GDScript docstrings to Godot 4 Native BBCode, clarifies helper behavior and return contracts across global utilities, and upgrades the lint workflow’s pinned path-filter dependency.

### File-Level Changes

| Change                                                                                                                                                    | Details                                                                                                                                                                                                                                                                                                                                                                                          | Files                                     |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------|
| Synchronize public GDScript API documentation with Godot 4 Native BBCode conventions and improve descriptions of parameters, behavior, and return values. | <ul><li>Replace legacy documentation tags with Native BBCode tags such as `[param]`, `[code]`, and return descriptions.</li><li>Clarify behavior for focus management, menu and scene loading, logging, version helpers, encryption checks, configuration loading, and test utilities.</li><li>Remove duplicated or stale wording and document previously undocumented public helpers.</li></ul> | `scripts/core/globals.gd`                 |
| Upgrade the pull-request path filtering action used by the lint workflow.                                                                                 | <ul><li>Pin `dorny/paths-filter` to the v4.0.3 commit instead of the v3.0.2 commit.</li></ul>                                                                                                                                                                                                                                                                                                    | `.github/workflows/lint_test_on_pull.yml` |

---

## Bots / AI Contributors

### @dependabot

- Authored the dependency bump commit updating `dorny/paths-filter` from `3.0.2` to `4.0.3` (commit `3026a74`).
- Provided the standard Dependabot changelog, release notes, and updated-dependencies metadata for the GitHub Actions path-filter upgrade.

### @sourcery-ai

- Generated the PR summary (“Summary by Sourcery”) covering documentation synchronization and the path-filter CI update.
- Produced the Reviewer’s Guide documenting file-level changes to `scripts/core/globals.gd` and `.github/workflows/lint_test_on_pull.yml`.
- Performed multiple code reviews (including the review on Sep 30, 2026) identifying documentation accuracy issues:
  - `load_scene_with_loading` docstring overstated “invalid path” handling (only empty paths are handled).
  - `load_key_mapping` docstring claimed unconditional background-video visibility/processing (only when found at specific relative paths).
- Co-authored the follow-up commit (`9e79eab`) that applied documentation clarifications.
- Continued review activity after subsequent commits (e.g., paths-filter comment accuracy).

### @deepsource-io (DeepSourceReview)

- Ran automated code review on the PR (changes `5b18364...aea03dc`).
- Published the DeepSource PR Report Card (Security / Reliability / Complexity / Hygiene grades) and analyzer status for Python & JavaScript.
- Linked the full review run for further inspection of any inline findings.

### @codecov

- Posted the Codecov coverage report for the PR.
- Reported patch coverage (~81.82% with 4 missing lines) and project coverage (~63.74%), including file-level impact details and comparison against the base commit.

### @coderabbitai

- Present on the PR with Autopilot messaging and review infrastructure.
- Contributed to the overall automated review / CI-assistance surface (including the standard CodeRabbit help and share prompts visible in the conversation).

---

## Human Contributor

### @ikostan

- Primary author and maintainer of the PR.
- Authored / co-authored the core documentation synchronization commits updating public GDScript API docstrings in `scripts/core/globals.gd` to Godot 4 Native BBCode conventions.
- Merged the Dependabot path-filter bump, resolved review feedback from @sourcery-ai (clarified empty-path handling and video-player lookup conditions), pinned the action SHA with accurate security comments, added the milestone documentation, self-assigned the PR, and applied labels (`documentation`, `good first issue`, `dependencies`, `dependabot`).
- Performed the final polish commits that brought the documentation and workflow changes to a review-ready state.

---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
