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

This PR implements a persistent, default-off FPS counter controlled from Advanced Settings, wiring the setting through the resource and config persistence layers to a signal-driven HUD component that updates immediately and disables processing when hidden. It also expands automated GDUnit4 coverage across data behavior, UI binding, lifecycle, persistence, reset handling, and test-fixture isolation, with accompanying implementation notes and manual QA steps.

### File-Level Changes

| Change                                                                                                                    | Details                                                                                                                                                                                                                                                                                                                                                                                                   | Files                                                                                                                                                                             |
|---------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Added a persistent FPS visibility preference to the settings model and configuration lifecycle.                           | <ul><li>Introduced `show_fps` with a default-off value and transition-only change notifications.</li><li>Loaded and saved the preference through the existing global settings configuration path.</li><li>Included the preference in Advanced Settings reset behavior.</li></ul>                                                                                                                          | `scripts/resources/game_settings_resource.gd`<br/>`scripts/core/globals.gd`<br/>`scripts/ui/menus/advanced_settings.gd`                                                           |
| Added an Advanced Settings toggle and live gameplay FPS HUD with signal-driven, immediate updates.                        | <ul><li>Expanded the Advanced Settings scene with a Show FPS checkbox and updated focus navigation.</li><li>Added an FPS counter label displaying the engine-reported frame rate.</li><li>Integrated the counter into the main scene and made visibility and processing respond to setting changes without a scene reload.</li></ul>                                                                      | `scenes/advanced_settings.tscn`<br/>`scenes/fps_counter.tscn`<br/>`scenes/main_scene.tscn`<br/>`scripts/ui/components/fps_counter.gd`<br/>`scripts/ui/menus/advanced_settings.gd` |
| Added automated coverage for the FPS setting, UI integration, persistence, lifecycle, reset behavior, and test isolation. | <ul><li>Tested defaults, mutations, signal arguments, and suppression of redundant notifications.</li><li>Tested counter visibility, processing culling, lifecycle fallback/injection behavior, frame-rate text updates, and unrelated-setting handling.</li><li>Tested configuration persistence, preservation of adjacent settings, reset-button binding, and fixture backup/teardown safety.</li></ul> | `test/gdunit4/test_fps_settings_data_mode.gd`<br/>`test/gdunit4/test_fps_settings_integration.gd`                                                                                 |
| Documented the implementation scope and manual QA workflow for validating the FPS toggle end to end.                      | <ul><li>Recorded the affected issues, architecture changes, testing scope, and implementation status.</li><li>Defined manual checks for default visibility, live toggling, persistence, and console cleanliness.</li></ul>                                                                                                                                                                                | `files/docs/milestones/23/Part_7_Add_fps_toggle.md`                                                                                                                               |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                     | Addressed | Explanation |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/518 | Add an exported `show_fps` boolean to `GameSettingsResource` with a default value of `false`.                                                                                                                                                                                 | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/518 | Implement `show_fps` change detection and emit `setting_changed` with exactly the key `"show_fps"` and the new boolean value, without emitting when the value is unchanged.                                                                                                   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/518 | Persist and restore the `show_fps` preference through the existing settings save/load architecture.                                                                                                                                                                           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/519 | Create and integrate a reusable FPS counter Label component that uses the project UI styling and remains anchored to the top-left of the gameplay HUD.                                                                                                                        | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/519 | Display the current framerate in the format "FPS: [X]" and update it during gameplay.                                                                                                                                                                                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/519 | Bind the counter to GameSettingsResource.show_fps so its initial visibility, mid-game toggling, and processing state are handled efficiently without a scene reload.                                                                                                          | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/520 | Add a styled FPS toggle consisting of a label and CheckButton to the Advanced Settings menu, with stable script access and appropriate focus navigation.                                                                                                                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/520 | Synchronize the toggle with GameSettingsResource.show_fps, initialize it without emitting a redundant signal, update the setting when toggled, and persist the preference through the existing settings system.                                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/520 | Make FPS visibility respond immediately to setting changes during gameplay, including HUD integration, persistence across sessions, and reset-to-default behavior.                                                                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/521 | Document a predefined manual end-to-end test plan for the FPS counter, covering the default-off state, enabling the setting, UI visibility and continuous updates, real-time disabling without a scene reload, persistence across sessions, and expected error-free behavior. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/522 | Add GDUnit4 tests under test/gdunit4/ verifying that a fresh GameSettingsResource initializes show_fps to false and supports false-to-true and true-to-false mutations.                                                                                                       | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/522 | Add tests verifying the setting_changed signal emits exactly the expected arguments once for each actual show_fps transition, preserves emission order, and suppresses emissions for redundant assignments.                                                                   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/522 | Ensure the FPS settings tests are isolated and deterministic by using fresh settings resources, observing signals only after initialization, and restoring global state during teardown.                                                                                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/925 | Add GDUnit4 integration coverage for FPSCounter visibility transitions and processing culling in the real Godot SceneTree, verifying both false-to-true and true-to-false behavior.                                                                                           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/925 | Add integration tests for settings persistence across a fresh resource/session boundary while verifying that changing and saving show_fps does not modify unrelated settings.                                                                                                 | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/925 | Add real Options UI integration coverage verifying initial synchronization with Globals.settings, production toggle interaction, signal-driven FPSCounter updates without scene reload, and appropriate test/global-state isolation.                                          | ✅        |             |

### Possibly linked issues

- **#520**: PR directly implements the requested Advanced Settings FPS toggle and its settings synchronization and persistence.
- **#518**: PR adds show_fps to GameSettingsResource, emits correct signals, and persists the setting as requested.
- **#925**: PR directly implements the issue's requested FPS integration tests, including SceneTree mounting, signal updates, UI interaction, and fresh-session persistence.

---

## QA Manual Test Plan: FPS Counter Implementation

**Description**:

A predefined set of manual testing steps to verify the FPS feature works end-to-end before merging.

**Steps to Execute**:

1. **Launch Game:** Start the game from the editor. Ensure no FPS counter is visible by default.
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
