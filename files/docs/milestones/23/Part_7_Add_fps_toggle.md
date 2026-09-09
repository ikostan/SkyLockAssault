# Add fps toggle
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## PR #927 Summary: Add FPS toggle

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `add-fps-toggle` → `main`  
**Linked Issues:** #518 (show_fps on GameSettingsResource), #519 (HUD FPS counter), #520 (Advanced Settings toggle), #522 (GDUnit data-mode tests), #925 (integration tests); related #521 (manual QA plan — fully addressed)  
**Milestone:** Milestone 23 – Settings Architecture & FPS Counter Implementation  
**Labels:** enhancement, testing, menu, GUI, controls, QA

### Purpose
Add a persistent Advanced Settings option to show or hide a live on-screen FPS counter during gameplay, with immediate UI updates (no scene reload), config persistence across sessions, and reset-to-default behavior—backed by GDUnit4 unit and integration coverage.

### Core Improvements

#### 1. Settings model (`GameSettingsResource` + `Globals`)
- New `show_fps: bool` (default **false**)
- Emits `setting_changed("show_fps", value)` only on actual transitions
- Load/save via existing config path in `globals.gd`
- Reset with other Advanced Settings (returns to **false**)

#### 2. Advanced Settings UI
- FPS container with label + `CheckButton` in `advanced_settings.tscn`
- Initializes from `Globals.settings.show_fps`
- Toggle updates the setting and persists on change
- Focus navigation adjusted for the expanded panel

#### 3. Live FPS counter HUD
- New `scenes/fps_counter.tscn` + `scripts/ui/components/fps_counter.gd`
- Displays `Engine.get_frames_per_second()` as **FPS: [X]**
- Wired into `main_scene.tscn` (top-left styling/position)
- Visibility and `set_process` driven by `show_fps` (processing off when hidden)
- Uses `Globals.settings` with fallback/warning if settings are missing

#### 4. Automated tests (GDUnit4)
- **Data mode** (`test_fps_settings_data_mode.gd`): defaults, bidirectional mutations, signal contract (exact args, no emit on redundant assign), isolation
- **Integration** (`test_fps_settings_integration.gd`): mount `FPSCounter` in SceneTree; visibility + process culling; Advanced Settings binding; persistence across resource/session boundary; unrelated settings unchanged; fixture backup/teardown safety; reset-button path

### Benefits
- Players can enable a live framerate readout without leaving the settings architecture
- Preference survives restarts and resets cleanly with Advanced Settings
- Counter stays cheap when hidden (`set_process(false)`)
- Strong automated coverage for data, UI binding, and persistence under Milestone 23

### Status Notes

Implements #518, #519, #520, #521, #522, and #925.

---

## Reviewer's Guide

This PR adds a persistent, default-off FPS counter controlled from Advanced Settings, connecting a new settings property through config persistence and change signals to a processing-culling HUD component with immediate updates. It also expands GDUnit4 coverage for data contracts, UI behavior, persistence, reset handling, audio paths, and test-fixture isolation, while documenting manual QA.

### File-Level Changes

| Change                                                                                                                              | Details                                                                                                                                                                                                                                                                                                                                                   | Files                                                                                                                                                                             |
|-------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Added a persistent, default-off FPS visibility setting across the settings model and configuration lifecycle.                       | <ul><li>Added `show_fps` with transition-only `setting_changed` signaling.</li><li>Loaded and saved the preference through the existing config path.</li><li>Included the preference in Advanced Settings reset behavior.</li></ul>                                                                                                                       | `scripts/resources/game_settings_resource.gd`<br/>`scripts/core/globals.gd`<br/>`scripts/ui/menus/advanced_settings.gd`                                                           |
| Added an Advanced Settings control and signal-driven gameplay HUD counter.                                                          | <ul><li>Added the Show FPS CheckButton and updated focus navigation.</li><li>Added a reusable top-left FPS counter displaying the engine-reported frame rate.</li><li>Updated visibility and processing immediately when the setting changes, without a scene reload.</li><li>Added focus-aware audio feedback for explicit toggle interaction.</li></ul> | `scenes/advanced_settings.tscn`<br/>`scenes/fps_counter.tscn`<br/>`scenes/main_scene.tscn`<br/>`scripts/ui/components/fps_counter.gd`<br/>`scripts/ui/menus/advanced_settings.gd` |
| Added comprehensive automated coverage for the setting, UI integration, persistence, lifecycle, reset behavior, and test isolation. | <ul><li>Covered defaults, bidirectional mutations, signal arguments, and suppression of redundant emissions.</li><li>Covered SceneTree visibility and processing culling, menu synchronization, persistence isolation, reset behavior, and FPS text updates.</li><li>Added safe configuration backup and teardown handling for tests.</li></ul>           | `test/gdunit4/test_fps_settings_data_mode.gd`<br/>`test/gdunit4/test_fps_settings_integration.gd`<br/>`test/gdunit4/test_input_remap_button.gd`                                   |
| Documented the implementation and end-to-end manual QA workflow.                                                                    | <ul><li>Recorded architecture, affected areas, linked issue coverage, and automated test scope.</li><li>Documented default state, live toggling, persistence, reset, and console validation steps.</li></ul>                                                                                                                                              | `files/docs/milestones/23/Part_7_Add_fps_toggle.md`                                                                                                                               |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                            | Addressed | Explanation |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/518 | Add an exported boolean `show_fps` property to `GameSettingsResource` with a default value of `false`.                                                                                                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/518 | Implement change detection for `show_fps`, emitting `setting_changed` with exactly the key `"show_fps"` and the new boolean value only when the value changes.                                                                       | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/518 | Persist and restore the `show_fps` preference through the existing settings save/load architecture.                                                                                                                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/519 | Create and integrate a reusable, themed FPS counter Label scene anchored to the top-left of the gameplay HUD.                                                                                                                        | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/519 | Implement FPS counter behavior that displays the current framerate as "FPS: [X]", initializes visibility from GameSettingsResource.show_fps, responds immediately to setting_changed updates, and disables processing while hidden.  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/519 | Wire the FPS counter into the gameplay UI and ensure its visibility setting is persisted and usable during gameplay without a scene reload.                                                                                          | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/520 | Add a styled FPS toggle consisting of a label and CheckButton to the Advanced Settings menu, with stable script access and initialization from the existing show_fps setting without emitting a redundant signal.                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/520 | Make toggling the Advanced Settings control update GameSettingsResource.show_fps and persist the preference through the existing settings save/load architecture, including reset-to-default behavior.                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/520 | Ensure changing the FPS setting immediately shows or hides the gameplay HUD FPS counter without a scene reload.                                                                                                                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/521 | Document a predefined manual end-to-end QA test plan for the FPS counter, covering default visibility, enabling the toggle, live UI updates, disabling without a scene reload, persistence across sessions, and error-free behavior. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/522 | Add GDUnit4 tests under test/gdunit4/ covering fresh GameSettingsResource initialization with show_fps set to false and bidirectional false-to-true-to-false state mutations.                                                        | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/522 | Verify the setting_changed signal contract for show_fps, including exact arguments, emission order, one emission per actual transition, and no emission when assigning the existing value.                                           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/522 | Ensure the FPS settings tests are isolated and deterministic by connecting observers only after initialization, using fresh resources, and restoring global or filesystem state during teardown.                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/925 | Add GDUnit4 integration coverage for FPSCounter visibility transitions and processing culling in the real Godot SceneTree, including both false-to-true and true-to-false transitions.                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/925 | Add integration tests for genuine session-boundary persistence of show_fps and verify that saving it preserves unrelated settings such as difficulty and log level.                                                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/925 | Add real Options UI integration coverage for initial synchronization, production toggle interaction, signal-driven FPSCounter updates without a scene reload, and isolated/restored global test state.                               | ✅        |             |

### Possibly linked issues

- **#520**: The PR adds the Advanced Settings CheckButton, initializes it safely, updates show_fps, persists changes, and updates HUD visibility.
- **#518**: PR directly implements the issue by adding GameSettingsResource.show_fps, correct signal behavior, and persistence.
- **#925**: The PR directly implements the issue's requested FPS integration tests and acceptance criteria under test/gdunit4/.

---

## QA Manual Test Plan: FPS Counter Implementation

**Description**:

A predefined set of manual testing steps to verify the FPS feature works end-to-end before merging.

**Steps to Execute**:

1. **Launch Game:** Clear your saved test configuration (or click Reset in Advanced Settings), then start the game from the editor. Ensure no FPS counter is visible by default.
2. **Toggle On:** Navigate to Options -> Advanced Settings. Toggle "Show FPS" to ON.
3. **Verify UI:** Enter gameplay. Verify the FPS counter appears in the top-left corner and updates its value continuously.
4. **Real-time Toggle:** Pause the game, navigate to settings, and toggle "Show FPS" to OFF. Resume gameplay. Verify the counter disappears immediately without a scene reload.
5. **Persistence:** Turn "Show FPS" ON. Close the game entirely. Relaunch the game. Enter gameplay. Verify the FPS counter is still visible (confirming the setting saved and loaded correctly).

**Expected Behavior**:

The UI perfectly syncs with the settings resource state, saves across sessions, and displays accurate engine framerates without throwing errors in the console.

---

## PR #927 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (including integration-test feedback on FPS toggle discovery). Co-authored an update to `scripts/ui/components/fps_counter.gd`.

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the FPS toggle feature and related pre-merge checks.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **58.54%**, **+2.27%** vs base; patch coverage **92%** with 2 lines missing in `advanced_settings.gd`; all tests successful).

- **@copilot** (GitHub Copilot)  
  Co-authored commits for FPS toggle/persistence wiring, safer deterministic FPS settings tests, and reset-button / settings-save test refinements.

> **Note:** **@dependabot** did not author commits or leave reviews on this PR (no dependency-bump activity observed).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Implemented the persistent `show_fps` preference on `GameSettingsResource` with change signaling; added the Advanced Settings FPS toggle and load/save via `Globals`; introduced the live `FPSCounter` UI component (visibility + `set_process` culling); integrated it into the main scene; and added GDUnit4 unit/integration coverage for defaults, signals, persistence, UI binding, lifecycle, reset behavior, and fixture backup/teardown isolation under Milestone 23.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
