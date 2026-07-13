# 🏁 Port tree node observation loop into audiomanager
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## Overview

This pull request by **@ikostan** refactors the global UI button sound effects (SFX) handling in the SkyLockAssault Godot project. It migrates the automatic `Button` `pressed` signal hooking logic (previously in `Globals`) into the centralized `AudioManager` singleton. This improves architecture, lifecycle management, and maintainability while addressing related issues around UI audio consistency.

### Key Changes

- **Core Refactoring** (`scripts/managers/audio_manager.gd`, `scripts/core/globals.gd`):
  - `AudioManager` now registers a guarded listener to `SceneTree.node_added` in `_ready()`.
  - Added `_retroactive_ui_scan()` for recursive traversal to hook pre-existing buttons created before the manager initializes.
  - Implemented filtering (flat buttons, `no_global_sound` metadata, buttons inside `AcceptDialog`s) and duplicate-connection guards using `CONNECT_DEFERRED`.
  - Centralized `_on_global_button_pressed()` to route `ui_accept` SFX via the configured menu bus.
  - Obsolete code in `Globals` is commented out/removed.

- **Testing Updates** (`test/gut/`):
  - Expanded tests for retroactive scanning, idempotency, listener singularity, and AudioManager-specific behavior.
  - Updated mocks and helpers to target the new implementation (e.g., `AudioManager._on_global_button_pressed`).
  - Improved quit dialog SFX tests with better inheritance and spying.

- **CI/CD Improvements** (`.github/workflows/`):
  - Normalized YAML quoting, indentation, and added yamllint directives for long lines/comments.
  - Updated Playwright cache key and artifact handling.
  - Switched gdlint workflow to direct `gdtoolkit` pip installation.

### Benefits & Implications

- **Better Separation of Concerns**: Audio logic is now fully owned by `AudioManager`, reducing Globals bloat and lifecycle issues.
- **Robustness**: Retroactive scanning + guards ensure reliable SFX for dynamically created UI elements.
- **Maintainability**: Cleaner tests, lint-compliant workflows, and reduced risk of duplicate connections or missed buttons.
- **Related Issues**: Primarily resolves #800 (feature port); also tackles CI lint bugs (#813, #814, etc.).

### AI/Bot Support

- Summaries, reviews, and suggestions from **@sourcery-ai**, **@coderabbitai**, and **@deepsource-io** (see separate bot contributions summary for details).

---

## Reviewer's Guide

Ports global UI button audio wiring from Globals into AudioManager, adding retroactive scene-tree scanning and strict listener registration while updating tests and CI workflows to validate and support the new behavior.

### File-Level Changes

| Change                                                                                                                                             | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Files                                                                                       |
|----------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Centralize global button audio wiring in AudioManager, including retroactive UI scanning and strict singleton listener registration.               | <ul><li>Attach AudioManager._on_node_added as a guarded listener to SceneTree.node_added in _ready, ensuring only a single connection.</li><li>Introduce _retroactive_ui_scan to recursively traverse the scene tree at startup and pass existing nodes through the same parsing logic used for new nodes.</li><li>Implement _on_node_added in AudioManager to filter out flat buttons, buttons with no_global_sound metadata, and buttons inside AcceptDialog before wiring their pressed signal.</li><li>Implement _on_global_button_pressed in AudioManager to play the ui_accept sound through the configured SFX bus.</li><li>Remove Globals-based node_added listener and its _on_node_added/_on_global_button_pressed implementations to fully migrate the responsibility into AudioManager.</li></ul> | `scripts/managers/audio_manager.gd`<br/>`scripts/core/globals.gd`                           |
| Update and expand tests to target AudioManager’s button hook behavior, including retroactive scanning, idempotency, and listener-count guarantees. | <ul><li>Change button connection-count helpers to look for AudioManager._on_global_button_pressed instead of Globals._on_global_button_pressed.</li><li>Update duplicate-scan test to invoke AudioManager._on_node_added and assert no duplicate connections are created.</li><li>Add tests verifying retroactive scan hooks up pre-existing buttons, remains idempotent on already-wired hierarchies, and keeps AudioManager’s node_added listener strictly singular.</li><li>Refactor quit dialog SFX tests to use an inherited AudioManager script double that overrides play_sfx while preserving real node wiring logic.</li><li>Remove obsolete flat button anti-trigger test that depended on Globals._on_node_added, since the behavior is now covered via AudioManager and its filtering.</li></ul>  | `test/gut/test_globals_button_hooks.gd`<br/>`test/gut/test_quit_game_confirm_dialog_sfx.gd` |
| Tighten CI workflows for browser tests and GDScript linting/formatting to align with tooling and lint expectations.                                | <ul><li>Adjust Playwright cache key to depend on the installed Playwright version and add yamllint annotations for long lines.</li><li>Normalize YAML quoting and condition expressions in browser_test.yml for consistency and lint compliance, including artifact names and Codecov configuration.</li><li>Switch gdlint workflow from using the Scony/godot-gdscript-toolkit GitHub Action to installing gdtoolkit via pip directly.</li></ul>                                                                                                                                                                                                                                                                                                                                                             | `.github/workflows/browser_test.yml`<br/>`.github/workflows/gdlint.yml`                     |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                    | Addressed | Explanation                                                                                                                                                                                                                                                                                                                                                                                                                 |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| https://github.com/ikostan/SkyLockAssault/issues/800 | Move the scene tree node_added observer and its button-audio handling logic from scripts/core/globals.gd into scripts/managers/audio_manager.gd, and connect it from AudioManager._ready().                                                                  | ✅         |                                                                                                                                                                                                                                                                                                                                                                                                                             |
| https://github.com/ikostan/SkyLockAssault/issues/800 | Preserve the existing button filtering contracts in the node-added handler (class == "Button", flat and metadata exclusions, AcceptDialog internal button exclusion) while wiring button.pressed to the audio callback using CONNECT_DEFERRED.               | ✅         |                                                                                                                                                                                                                                                                                                                                                                                                                             |
| https://github.com/ikostan/SkyLockAssault/issues/800 | Ensure AudioManager autonomously manages button audio hooks, including using its own local playback callback and safe listener registration to the scene tree’s node_added signal.                                                                           | ✅         |                                                                                                                                                                                                                                                                                                                                                                                                                             |
| https://github.com/ikostan/SkyLockAssault/issues/813 | Update .github/workflows/browser_test.yml to quote all yamllint-flagged string values (including if conditions, artifact names, paths, and other literals) using double quotes.                                                                              | ✅         |                                                                                                                                                                                                                                                                                                                                                                                                                             |
| https://github.com/ikostan/SkyLockAssault/issues/813 | Eliminate yamllint `[quoted-strings]` warnings for browser_test.yml so the YAML Lint / build workflow runs clean.                                                                                                                                            | ✅         |                                                                                                                                                                                                                                                                                                                                                                                                                             |
| https://github.com/ikostan/SkyLockAssault/issues/814 | Resolve yamllint line-length violations in .github/workflows/browser_test.yml (specifically the long cache key comment/key and embedded Python HTTP server block) by keeping lines under 90 characters or using explicit yamllint disable/enable directives. | ✅         |                                                                                                                                                                                                                                                                                                                                                                                                                             |
| https://github.com/ikostan/SkyLockAssault/issues/815 | Update all direct uses of actions/setup-python in local GitHub workflow files (e.g., browser_test.yml, gdlint.yml) to use version v6 instead of v5, removing the Node.js 20 deprecation warning.                                                             | ❌         | The diff for .github/workflows/browser_test.yml shows only formatting, quoting, and cache-key changes and does not modify any actions/setup-python usage. The gdlint.yml changes switch from the Scony/godot-gdscript-toolkit action to installing gdtoolkit via pip, but there is no direct setup-python step changed to @v6. Therefore, any direct setup-python@v5 usage in workflows is not shown as updated in this PR. |
| https://github.com/ikostan/SkyLockAssault/issues/815 | Eliminate the deprecated Node.js 20 runtime warning originating from third-party/composite GitHub Actions that internally use actions/setup-python@v5, by updating or replacing those actions.                                                               | ✅         |                                                                                                                                                                                                                                                                                                                                                                                                                             |

### Possibly linked issues

- **#800**: PR implements the centralized Button pressed SFX hook with strict Button filtering, CONNECT_DEFERRED, exclusions, and AudioManager routing.

---

**Bots/AI Contributions Summary for PR #817**

### AI/Bot-Assisted Review and Automation

This PR benefited significantly from automated code review tools and AI assistants, which provided summaries, suggestions, walkthroughs, nitpicks, and quality checks. These contributions helped refine the refactoring (porting UI button observation logic to `AudioManager`), improve tests, clean up CI workflows, and address potential issues like duplicate connections and retroactive scanning.

Key bots/AI contributors (in GitHub-mentionable format):
- **@sourcery-ai**: Generated the PR summary, reviewer's guide, sequence diagrams, and provided high-level feedback (e.g., suggestions on removing dead code in `globals.gd` and guarding the `node_added` listener). It also flagged the need for retroactive UI scanning for pre-existing buttons.
- **@coderabbitai**: Delivered a detailed walkthrough, change summaries, nitpick comments (e.g., removing commented-out dead code), and quality/maintainability suggestions. It also produced a fun poem summarizing the changes.
- **@deepsource-io** (via DeepSourceReview): Performed automated code analysis on the changes, providing a PR report card with grades on security, reliability, complexity, and hygiene, plus inline review comments and links to full Python/JavaScript reviews.

These tools enhanced code quality, ensured consistency with project standards (e.g., GDScript/Godot practices), and streamlined the review process without direct code commits (all commits were authored by the human contributor).

### @ikostan Contributions (Human Maintainer)

@ikostan drove the entire implementation through multiple targeted commits, handling the core refactoring, test updates, and CI fixes. Key efforts include:

- Porting global `Button` SFX hooking logic from `Globals` to `AudioManager` (including `_on_node_added`, `_on_global_button_pressed`, and `CONNECT_DEFERRED` guards).
- Adding retroactive UI tree scanning (`_retroactive_ui_scan`) to handle buttons created before `AudioManager._ready()`.
- Implementing strict singleton listener registration to prevent duplicates.
- Updating and expanding GUT tests (e.g., `test_globals_button_hooks.gd`, `test_quit_game_confirm_dialog_sfx.gd`) for new behavior, idempotency, and lifecycle coverage.
- Cleaning up `globals.gd` (commenting out obsolete hooks) and refining CI workflows (YAML quoting, yamllint fixes, Playwright cache, gdtoolkit installation in `.github/workflows/`).
- Addressing linked issues (#800, #813, #814, etc.) for refactoring, bug fixes, and lint compliance.

This PR centralizes UI audio management, improves maintainability, and resolves several CI/lint issues while preserving existing behavior for flat buttons, dialog buttons, and metadata exclusions.

**Overall Impact**: Strong collaboration between human engineering and AI tooling resulted in a polished, well-tested change ready for merge. No dependency updates or external bot commits (e.g., no @dependabot activity here).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
