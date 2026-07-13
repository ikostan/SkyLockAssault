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

| Change                                                                                                                                              | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Files                                                                                       |
|-----------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Centralize SceneTree node_added observation and global Button pressed SFX wiring inside AudioManager, including retroactive scanning and filtering. | <ul><li>Connect AudioManager._on_node_added to SceneTree.node_added in _ready() with a guard to ensure only one listener is registered.</li><li>Introduce _retroactive_ui_scan to recursively traverse the scene tree and call the same button-hook logic on pre-existing nodes.</li><li>Implement _on_node_added to filter out flat buttons, buttons with no_global_sound metadata, and buttons inside AcceptDialog, then connect pressed to _on_global_button_pressed with CONNECT_DEFERRED.</li><li>Implement _on_global_button_pressed in AudioManager to play the ui_accept sound on the configured SFX menu bus.</li><li>Remove the Globals-based node_added listener and its button hook/audio callback functions so AudioManager owns the behavior.</li></ul>                                                             | `scripts/managers/audio_manager.gd`<br/>`scripts/core/globals.gd`                           |
| Align unit tests with the new AudioManager-centric button wiring, and add coverage for retroactive scanning and listener singularity.               | <ul><li>Update connection-count helpers to look for AudioManager._on_global_button_pressed instead of Globals._on_global_button_pressed.</li><li>Change duplicate-scan tests to drive AudioManager._on_node_added and assert that connection counts remain single.</li><li>Add tests verifying retroactive scan hooks pre-existing buttons, remains idempotent on already wired nodes, and traverses mixed hierarchies without wiring non-button containers.</li><li>Add a test to ensure AudioManager’s node_added listener registration remains strictly singular even if _ready() is re-entered.</li><li>Refactor quit dialog SFX tests to use an inherited AudioManager script double that overrides play_sfx for spying while preserving real node wiring, and drop the obsolete flat-button test tied to Globals.</li></ul> | `test/gut/test_globals_button_hooks.gd`<br/>`test/gut/test_quit_game_confirm_dialog_sfx.gd` |
| Tighten GitHub Actions workflows for browser tests and GDScript linting/formatting to satisfy yamllint and modern tooling requirements.             | <ul><li>Normalize quoting and indentation in browser_test.yml, including double-quoting if conditions, artifact names, paths, and Codecov arguments.</li><li>Add yamllint disable/enable comments around long lines like Playwright cache key comments and the embedded Python HTTP server script.</li><li>Adjust the Playwright cache key to depend on the resolved Playwright package version and fix related condition expressions.</li><li>Switch gdlint workflow from the Scony/godot-gdscript-toolkit action to installing gdtoolkit via pip directly.</li></ul>                                                                                                                                                                                                                                                            | `.github/workflows/browser_test.yml`<br/>`.github/workflows/gdlint.yml`                     |
| Add milestone documentation describing the AudioManager port and summarizing architectural, testing, and CI changes.                                | <ul><li>Create a new markdown milestone file explaining the move of button SFX wiring from Globals to AudioManager.</li><li>Document the key refactoring, test updates, and CI workflow changes along with benefits and implications.</li><li>Include a short reviewer’s guide and notes on AI/bot contribution for the milestone.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | `files/docs/milestones/21/Part_8_Port_tree_node_observation_loop_into_audio_manager.md`     |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                    | Addressed | Explanation |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/800 | Move the active tree observer mechanism `_on_node_added` from `scripts/core/globals.gd` into `scripts/managers/audio_manager.gd` and connect it directly to `SceneTree.node_added` during `AudioManager._ready()`.                                           | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/800 | Preserve the existing node filtering contracts in the observer (`get_class() == "Button"`, flat button and `no_global_sound` exclusions, and internal `AcceptDialog` button exclusions) when implemented inside `AudioManager`.                              | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/800 | Ensure button `pressed` signal connections created by the observer use `CONNECT_DEFERRED` and route to a local `AudioManager` playback callback rather than `Globals`, making the audio singleton autonomous.                                                | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/813 | Quote all previously bare string values and conditional `if:` expressions in `.github/workflows/browser_test.yml` so they conform to yamllint’s `quoted-strings` rule.                                                                                       | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/813 | Eliminate yamllint `[quoted-strings]` warnings for `.github/workflows/browser_test.yml` in the CI YAML Lint / build workflow.                                                                                                                                | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/814 | Resolve yamllint line-length violations in .github/workflows/browser_test.yml (specifically the long cache key comment/key and embedded Python HTTP server block) by keeping lines under 90 characters or using explicit yamllint disable/enable directives. | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/815 | Ensure all direct uses of actions/setup-python in local GitHub workflow files are explicitly set to version v6 (not v5).                                                                                                                                     | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/815 | Clarify in CI/CD configuration or comments that any remaining Node.js 20 deprecation warnings originate from third-party/composite actions and that local workflows are already on setup-python@v6.                                                          | ✅         |             |

### Possibly linked issues

- **#800**: PR implements the requested AudioManager node_added listener, button filtering, and playback callback, plus related tests and CI updates.

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
