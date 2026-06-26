# Route menu UI SFX through AudioManager and add GUT tests
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## Technical Documentation: PR #782 Summary

### Overview

**Title:** Route menu UI SFX through AudioManager and add GUT tests  
**Author:** @ikostan  
**PR:** [#782](https://github.com/ikostan/SkyLockAssault/pull/782)  
**Project:** SkyLockAssault (Godot 4.x)  
**Status:** Merged / In Review (as of June 26, 2026)  
**Related Issue:** [#495](https://github.com/ikostan/SkyLockAssault/issues/495) — [FEATURE] UI Audio Logic Unit Tests (GUT): Confirmation & Cancellation Triggering

### Purpose

This PR centralizes menu UI sound effects (navigation and cancel) through the existing `AudioManager` singleton, eliminates duplicate sound triggers, removes dead or split audio responsibilities, and introduces a robust, cross-platform unit testing framework using GUT. It ensures zero environment leakage across test suites and guarantees stability on both local viewports and headless CI/CD runners.

Use AudioManager.play_sfx for menu navigation/cancel sounds and add test helpers to support GUT. globals.gd: add a test-fallback menu detection via current_scene.name and route _play_ui_navigation_sfx through AudioManager. main_menu.gd: remove redundant cancel-button connection and trigger ui_cancel via AudioManager in _on_quit_dialog_canceled. Add comprehensive GUT tests (test_nav_escape_sfx.gd, test_quit_game_confirm_dialog_sfx.gd) with mock AudioManager scripts and UID files to validate navigation, cancel, and confirmation audio pathways.

This PR focused on audio centralization, test coverage for UI interactions, and infrastructure hardening, with AI bots enhancing review depth and maintainability. The final output benefits from iterative human + bot collaboration.

---

### Key Changes

#### 1. Audio Centralization & Fallback Isolation (`scripts/core/globals.gd`)

- **Legacy Player Removal**: Removed the local `_nav_sfx_player` variable, its preloaded asset definition, and its initialization sequence inside `_ready()`.
- **Asset Alignment**: Corrected the central audio routing key inside `_play_ui_navigation_sfx()` to use `"ui_navigation"`. This explicitly matches the underlying asset name (`ui_navigation.wav`) managed by the `AudioManager` pool.
- **Production-Safe Fallback Gate**: Wrapped the test-helper scene context detection within explicit feature guards:

    ```gdscript
    if (
        (OS.has_feature("debug") or OS.has_feature("ci"))
        and not is_menu_context
        and get_tree().current_scene
        and "Menu" in get_tree().current_scene.name
    ):
        is_menu_context = true
    ```

This implementation completely isolates test-only fallback mechanics from exported release production templates.

#### 2. Dialogue Dismissal Single-Dispatch Safety (`scripts/ui/menus/main_menu.gd`)

- **Duplicate SFX Mitigation**: Disconnected the redundant `close_requested` window wire from `_setup_quit_dialog()`. This completely prevents dual execution loops during title-bar or Escape-key window dismissals.
- **Centralized Cancellation Audio**: Placed the cancellation trigger directly inside `_on_quit_dialog_canceled()` via `AudioManager.play_sfx("ui_cancel")`.
- **Dead Code Eradication**: Permanently deleted the orphaned manual click handler `_on_cancel_button_clicked()` to ensure warning-free compilation runs.
- **Process Termination Shield**: Introduced a `bypass_quit_for_testing` variable gated by feature flags inside `_on_quit_dialog_confirmed()`:

    ```gdscript
    if (OS.has_feature("debug") or OS.has_feature("ci")) and bypass_quit_for_testing:
        Globals.log_message("Bypassing game quit execution for unit testing.", Globals.LogLevel.DEBUG)
        return
    ```

This blocks `get_tree().quit()` execution streams from tearing down the running editor process or silently corrupting automated CI pipelines.

#### 3. Advanced GUT Test Suites

##### Suite A: `test/gut/test_nav_escape_sfx.gd`

- **Headless Environment Recovery**: Programmed `before_each()` to dynamically construct and mount a temporary `dummy_scene_node` straight to `get_tree().current_scene` if the runner executes in a headless server context.
- **Cross-Suite Contamination Guard**: Configured explicit teardown blocks inside `after_each()` to unmount the dummy nodes and restore altered shared scene attributes. This guarantees zero string or naming state pollution leaks down the rest of the testing tree.
- **Optimization**: Eliminated structural dead weight by wiping a legacy `possible_fields` dictionary mapping routine that previously generated no-op execution traces.
- **Asset Synchronicity**: Updated directional validation assertions to track the synchronized `"ui_navigation"` lookup key string.

##### Suite B: `test/gut/test_quit_game_confirm_dialog_sfx.gd`

- **Hierarchy Tree Realization**: Replaced naked script instantiation calls (`MainMenuScript.new()`) with an explicit `MainMenuScene.instantiate()` pipeline structure. This properly builds out and evaluates `@onready` structural children to avoid base null instance crashes.
- **Active Protection Coverage**: Refactored `test_flat_button_anti_trigger_protection` to feed simulated flat button layouts directly into `Globals._on_node_added()` and validated behaviors using native `.pressed.emit()` signals. This transforms a false-positive test path into an authentic functional gate validator.
- **Automation Stability**: Added initialization rules to dynamically flip `bypass_quit_for_testing = true` on the scene instance prior to executing test frames.

#### 4. Infrastructure Isolation Teardowns

- **Pool Restoration**: Connected `restore_audio_mock()` logic to invoke `AudioManager.cleanup_for_test()` in the suite lifecycle `after_all()` teardown phase. This flushes out spy tracking structures and re-allocates a pristine, populated production channel pool for downstream testing scripts.
- **Checksum Verification**: Retained baseline asset checks matching version metrics within our workflow scripts.

---

### Technical Benefits

- **Pure Centralization**: Devolves voice allocation and LRU tracking exclusively onto `AudioManager`, removing rogue node footprint overhead.
- **Architectural Security**: Protects compilation and execution workflows via explicit feature-flag gating, isolating development code hooks from shipped deployment copies.
- **Testing Reliability**: Achieves authentic single-dispatch safety verification and removes cross-suite environmental leakage.

### Testing & Validation

- Fully validated locally inside the Godot editor workspace.
- Headless verification passes cleanly via automated terminal triggers.
- Complete CI/CD testing guarantees **9/9 passing gates** on remote Ubuntu integration pipelines.

### Risks & Considerations

- **Scene Name Dependency**: The debug/CI fallback relies on `"Menu"` substring in `current_scene.name`. Future scene renames could break this (mitigated by feature flags).
- **Test Brittleness**: Heavy use of mocks, signal emission, and scene tree manipulation — requires maintenance if Godot internals or GUT change.
- **Performance**: Negligible, but repeated `get_tree().current_scene` checks in `_input` (already guarded).
- **Platform Quirks**: Quit bypass only active in `debug`/`ci` builds; Web export behavior remains unchanged.

---

## Reviewer's Guide

Routes menu navigation and cancel SFX through AudioManager instead of a dedicated AudioStreamPlayer, introduces test-oriented menu-context detection and quit-bypass hooks, and adds GUT test suites plus CI/Docker hardening for Godot asset verification.

### File-Level Changes

| Change                                                                                                                                  | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Files                                                                                                                                                                                   |
|-----------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Route global menu navigation/cancel SFX through AudioManager and add a test-only menu-context fallback.                                 | <ul><li>Remove the dedicated _nav_sfx_player AudioStreamPlayer and its initialization, relying on AudioManager for SFX playback instead.</li><li>In_input, add a debug/CI-only fallback that treats scenes with "Menu" in their name as menu context when standard detection reports false.</li><li>Update _play_ui_navigation_sfx to invoke AudioManager.play_sfx("ui_navigation") and fix the key name to match the real asset.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                             | `scripts/core/globals.gd`                                                                                                                                                               |
| Centralize quit-dialog cancel SFX via AudioManager and add a test guard to prevent real quits.                                          | <ul><li>Introduce a bypass_quit_for_testing flag on the main menu script to prevent get_tree().quit() during automated tests.</li><li>Update quit dialog setup to rely solely on the canceled signal (which already covers close_requested) and remove the explicit close_requested connection and cancel-button pressed handler.</li><li>Play the cancel SFX inside _on_quit_dialog_canceled using AudioManager.play_sfx("ui_cancel"), replacing the removed _on_cancel_button_clicked path.</li><li>Add an early-return guard in _on_quit_dialog_confirmed when bypass_quit_for_testing is enabled, logging that quit was bypassed instead of quitting.</li></ul>                                                                                                                                                                                                                     | `scripts/ui/menus/main_menu.gd`                                                                                                                                                         |
| Add GUT tests for global navigation/escape SFX routing and quit dialog confirmation/cancel audio behavior, using a mocked AudioManager. | <ul><li>Create test_nav_escape_sfx.gd to cover menu-context gating, non-menu suppression, echo/slider/LineEdit gates, unrelated actions, and single-dispatch behavior for ui_navigation/ui_cancel.</li><li>. In test_nav_escape_sfx.gd, snapshot/restore Globals menu-context-related fields and current_scene.name, and drive inputs through Globals._input/_unhandled_input while stubbing AudioManager.play_sfx via a temporary script with an sfx_calls array.</li><li>Create test_quit_game_confirm_dialog_sfx.gd to instantiate the real main menu scene, enable bypass_quit_for_testing, and assert that _on_quit_dialog_confirmed/_on_quit_dialog_canceled trigger ui_accept/ui_cancel once, while flat buttons do not spuriously fire ui_accept via global hooks.</li><li>Add .uid files for the new GUT test scripts to register them with Godot’s resource system.</li></ul> | `test/gut/test_nav_escape_sfx.gd`<br/>`test/gut/test_quit_game_confirm_dialog_sfx.gd`<br/>`test/gut/test_nav_escape_sfx.gd.uid`<br/>`test/gut/test_quit_game_confirm_dialog_sfx.gd.uid` |
| Harden Godot binary/template verification in Docker and split CI jobs for Python tests and Godot asset checks.                          | <ul><li>In Dockerfile, switch from SHA256SUMS.txt/sha256sum to SHA512-SUMS.txt/sha512sum for both engine and export-template downloads, updating comments and cleanup accordingly.</li><li>In test_ci_scripts.yml, rename the Python test job to test-python with a clearer name, and introduce a separate verify-godot job that checks out the repo and runs the existing verify_godot.sh script under a more descriptive job name and timeout.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                              | `Dockerfile`<br/>`.github/workflows/test_ci_scripts.yml`                                                                                                                                |

### Assessment against linked issues

| Issue                                                  | Objective                                                                                                                                                                                                                                                                                               | Addressed | Explanation |
|--------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| <https://github.com/ikostan/SkyLockAssault/issues/495> | Centralize UI navigation and cancel/quit dialog sound effects through AudioManager, removing direct AudioStreamPlayer usage and redundant button/signal wiring that could double-trigger SFX.                                                                                                           | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/495> | Add a GUT test suite in res://test/gut/test_nav_escape_sfx.gd targeting Globals (globals.gd) that verifies global navigation and ui_cancel behavior, including menu-context gating, echo mitigation, focus gates for LineEdit/Slider, single-dispatch guarantee, and suppression for unrelated actions. | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/495> | Add a GUT test suite in res://test/gut/test_quit_game_confirm_dialog_sfx.gd targeting MainMenu (main_menu.gd) that verifies quit dialog confirmation and cancellation audio routing via AudioManager and ensures flat menu buttons do not trigger global ui_accept confirmation SFX.                    | ✅         |             |

### Possibly linked issues

- **#N/A**: They match: PR implements the specified GUT suites (files, behaviors, AudioManager mocking) for UI audio logic.

---

**Bots/AI Contributions to PR #782**

### AI/Code Review Bots

These automated tools provided summaries, reviews, suggestions, and feedback that contributed to the PR's quality, structure, and testing improvements:

- **@sourcery-ai**: Generated a detailed PR summary, reviewer's guide, sequence diagrams, and code review comments. Highlighted issues like potential double SFX playback in `globals.gd`, test fallback concerns, and dead code in `main_menu.gd`. Provided high-level feedback and actionable prompts.
- **@coderabbitai**: Delivered a walkthrough of changes, bug fix/test/CI summaries, nitpick comments (e.g., dead `_on_cancel_button_clicked` handler, test snapshot logic improvements), and maintainability suggestions. Included poem and pre-merge checks.
- **@deepsourcebot** (DeepSource): Performed automated code review on changes (e.g., commits cd67305...0d3edef), providing a PR report card (Security, Reliability, Complexity, Hygiene) and inline comments via the DeepSource platform. No specific "DeepsourceReview" bot username observed; standard integration uses `@deepsourcebot`.

No evidence of **@dependabot** or other dependency bots in this PR (all commits by human author; changes were manual code/test/CI updates).

### Human Contributors

- **@ikostan**: Primary author and sole code committer. Implemented core changes: routing menu UI SFX (`ui_navigation`/`ui_cancel`) through `AudioManager` in `globals.gd` and `main_menu.gd`; added comprehensive GUT tests (`test_nav_escape_sfx.gd`, `test_quit_game_confirm_dialog_sfx.gd` with mocks/UIDs); introduced test helpers (e.g., `bypass_quit_for_testing`, scene-name fallback for CI/debug); updated Dockerfile (SHA512 verification) and CI workflow (split jobs). Addressed review feedback iteratively across multiple commits.
- **@espanakosta-jpg**: No contributions or mentions found in this PR (commits, reviews, or conversation).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
