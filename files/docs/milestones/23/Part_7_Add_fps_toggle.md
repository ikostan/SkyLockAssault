# Add fps toggle
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## PR #927 Summary: Add FPS toggle

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `add-fps-toggle` → `main`  
**Linked Issues:** #518 (show_fps on GameSettingsResource), #519 (HUD FPS counter), #520 (Advanced Settings toggle), #522 (GDUnit data-mode tests), #925 (integration tests); related #521 (manual QA plan — not fully addressed)  
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
