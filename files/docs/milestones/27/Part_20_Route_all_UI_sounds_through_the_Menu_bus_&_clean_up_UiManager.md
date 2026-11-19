<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Route all UI sounds through the Menu bus & clean up UiManager

---

## PR Summary

**Title:** Route all UI sounds through the Menu bus and clean up UiManager  
**PR:** _fill in after opening the PR._  
**Branch:** `issue-1152-menu-bus-ui-sounds` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1152 – [FEATURE] Route all UI sounds through the Menu bus and clean up UiManager](https://github.com/ikostan/SkyLockAssault/issues/1152)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `bug`, `enhancement`, `audio`, `refactoring`, `GUT`, `SFX`

### Purpose

`UiManager` played the navigation and cancel sounds on the `SFX` bus, while button accepts (`SfxManager._on_global_button_pressed()`) already used `SFX_Menu`. So the Menu slider and mute silenced button clicks but not navigation or cancel. As decided on 2026-11-05, the Menu slider now controls every UI sound. This replaces the explicit `SFX` routing from #490. `SFX_Menu` sends to `SFX`, so the SFX and Master controls still apply.

The PR also removes dead code from `UiManager._check_menu_context()` and `_handle_ui_cancel_action()`, and records the measured cost of `SfxManager._on_node_added()`. That is the part of #619 (Region 4) this issue covers.

---

## Confirm-first results

The new and updated tests were run against unchanged `main` (`8cd7cce`) with only `ui_manager.gd` reverted. 11 cases fail, and each failure is one of the issue's findings:

| Suite                       | Fails on `main`                                                                                                                                                                                                                    |
|-----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `test_nav_escape_sfx.gd`    | 6 of 18: cancel and navigation request `SFX` instead of `SFX_Menu` (5 cases), and a scene named `MainMenu` / `OptionsMenu` / `Menu` with no marker turns on UI sounds (`test_scene_named_menu_without_group_is_not_menu_context`). |
| `test_ui_sfx_menu_bus.gd`   | 3 of 8: navigation and cancel play on `SFX`, so muting Menu or setting it to 0 leaves them audible.                                                                                                                                |
| `test_audio_integration.gd` | 2 of 8: navigation (Scenario C) and cancel (Scenario D) play on `SFX`.                                                                                                                                                             |

**The scene-name heuristic never matched in production.** `main_menu.tscn`'s root node is named `Control`, and no other scene that can become `current_scene` has "Menu" in its root name (`SplashScreen`, `LoadingScreen`, `Node2D`). A probe on the real main menu during its intro (before Start has focus) gave `_check_menu_context()` = `false`, and `true` once the root was in the `menu_context` group. Only the GUT suite matched the heuristic, by renaming the test scene to `MainMenu`. See Design Decisions for why the group was not added to `main_menu.tscn`.

---

## Key Changes

### 1. All UI sounds on the Menu bus (`ui_manager.gd`)

- `_handle_ui_cancel_action()` and `_handle_ui_navigation_action()` call `SfxManager.play_sfx(..., AudioConstants.BUS_SFX_MENU)` instead of `BUS_SFX`.
- The two "route through the SFX bus (Issue #490)" comments and the file header now name the Menu bus.

### 2. `_check_menu_context()` cleanup (`ui_manager.gd`)

- **Dead branch removed.** The "Test Environment Fallback" block (debug / CI feature check) repeated the three checks above it, so it could never change the result.
- **Name heuristic removed.** `"Menu" in active_scene.name` is gone. The explicit opt-ins stay: the scene root in the `menu_context` group, or with `is_menu_context` metadata.
- The runtime checks are unchanged: `get_tree().paused`, `Globals.options_open`, a non-empty `Globals.hidden_menus`, or a focused control.

### 3. Stale remap check removed (`ui_manager.gd`)

`has_method("cancel_remap")` is gone; no script defines `cancel_remap()`. Remap buttons are still recognized by their `action` property (`InputRemapButton.action`), and the `action_name` check stays.

### 4. `_on_node_added` measured, left unchanged (`sfx_manager.gd` not modified)

Measured in the benchmark scenario with temporary timing around the handler (not committed): 60 s of sustained firing at the 60 FPS cap, after the 5 s warm-up.

| Metric                         | Value                                           |
|--------------------------------|-------------------------------------------------|
| Calls in the 60 s window       | 4,320 (1.2 per frame), 0 of them `Button` nodes |
| Total time                     | 4.894 ms                                        |
| Average per call / worst call  | 1.13 µs / 63 µs                                 |
| Per frame                      | 1.36 µs (0.008 % of the 16.67 ms frame budget)  |
| Benchmark process time (avg)   | 0.49 ms, so the handler is about 0.3 % of it    |

The cost isn't visible, so, as the issue says, the code is unchanged and no follow-up was filed. An A/B run with the hook disconnected wasn't used: its frame-time noise is far larger than 1.4 µs per frame. The figures include the timing calls, so they slightly overstate the real cost.

### 5. Tests

- **`test/gut/test_nav_escape_sfx.gd` (9 → 18 cases):**
  - `_set_menu_context()` adds or removes the `menu_context` group instead of renaming the scene to `MainMenu` / `GameLevel`. `after_each()` restores the scene's original name, group membership and metadata, and releases any focus a test left behind.
  - Existing cases unchanged and still running: context suppression, exit cleanup, echo, single dispatch, text field, slider and unrelated actions. The cancel and focused-navigation cases also assert the requested bus is `SFX_Menu`.
  - New: navigation without focus requests `SFX_Menu` for all four directions; no UI sound requests `SFX`; a scene named `MainMenu` / `OptionsMenu` / `Menu` without a marker is not a menu context; the group and the metadata each make one; the runtime checks (paused tree, `options_open`, `hidden_menus`, focus) still work without a marker; a focused `InputRemapButton` (`action`) and a control with `action_name` suppress the cancel sound; a plain focused button gets it on `SFX_Menu`.
- **New `test/gut/test_ui_sfx_menu_bus.gd` (8 cases), real managers and bus layout:**
  - Navigation, cancel and button accept all start a player on `SFX_Menu`, and `SFX_Menu` sends to `SFX`.
  - With Menu muted, or at volume 0, all three are silent; at normal volume all three are audible. "Silent" means the player's bus or a bus it sends to (up to Master) is muted or at volume 0 on the `AudioServer`.
  - With SFX or Master muted, all three are silent.
  - Muting Menu or setting it to 0 leaves `SFX_Weapon` and `SFX_Rotors` audible, unmuted, and at the same volume.
  - Bus state is set with `set_bus_state()` and `apply_volume_to_bus()` and restored after each test, so nothing is saved to `settings.cfg`.
- **`test/gut/test_audio_integration.gd` (7 → 8 cases):** Scenario C also asserts that both navigation sounds play on `SFX_Menu`; new Scenario D checks that the cancel sound plays on `SFX_Menu`, not `SFX`. `TARGET_BUS` stays `SFX`, because Scenarios A and B and the mute tests check muting the parent SFX bus.

---

## Design Decisions

- **The `menu_context` group was not added to `main_menu.tscn`.** The issue asked for it, but the name heuristic it was meant to replace never matched in production (Confirm-first results). Adding it would change behavior: during the intro (3 s delay plus fade, while the menu is still invisible and Start has no focus) arrows and Esc would start playing navigation and cancel sounds. Once Start has focus, focus already makes it a menu context. So no scene was given the group, and removing the heuristic changes nothing in the game. The group and metadata stay as explicit opt-ins for a future scene that needs UI sounds without focus, and are covered by tests. Decided with @ikostan on 2026-11-19.
- **Options, pause, loading and other menus still work through runtime state.** Options sets `Globals.options_open`, pause sets `get_tree().paused`, sub-menus push `Globals.hidden_menus`, and every menu gives a button focus. `test_runtime_flags_open_menu_context_without_scene_marker` covers each, and `test_all_menus_navigation_regression.gd` (GUT) and `test_gdunit_all_menus_navigation_regression.gd` (gdUnit4) pass unchanged.
- **Accepts were already on the Menu bus.** `SfxManager._on_global_button_pressed()` used `BUS_SFX_MENU` before this PR, so only navigation and cancel moved.
- **Silence is checked at the bus, not by listening.** Headless runs use the dummy audio driver, so the tests check where the player plays and that the bus chain to Master is muted or at volume 0. That is what makes it silent in the game.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 v6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdformat --check` and `gdlint` as in CI.

| State                    | GUT tests | GUT asserts | gdUnit4 test cases |
|--------------------------|-----------|-------------|--------------------|
| `main` (`8cd7cce`, base) | 1,056     | 11,261      | 164                |
| This PR                  | 1,074     | 11,380      | 164                |

- **No test cases removed.**
- **Full GUT suite:** 1,074/1,074, including `test_all_menus_navigation_regression.gd`, `test_globals_input_guards.gd` and `test_audio_sfx_centralization.gd`.
- **gdUnit4 suite:** 164/164, including `test_gdunit_all_menus_navigation_regression.gd`.
- **New tests on `main`:** 11 cases fail (see Confirm-first results).
- **Breaking each change:** each change below, applied to this PR's `ui_manager.gd`, makes at least one new test fail.

| Change to the code                               | Fails                                                                                                         |
|--------------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| Navigation and cancel back on `BUS_SFX`          | 5 in `test_nav_escape_sfx.gd`, 3 in `test_ui_sfx_menu_bus.gd`, 2 in `test_audio_integration.gd`               |
| `"Menu" in active_scene.name` restored           | `test_scene_named_menu_without_group_is_not_menu_context`                                                     |
| Group check removed                              | `test_scene_in_menu_context_group_is_menu_context` and the 4 cases that enter a context through the group     |
| Metadata check removed                           | `test_scene_with_menu_context_meta_is_menu_context`                                                           |
| `action` check removed                           | `test_remap_button_action_suppresses_cancel_sound`                                                            |
| `action_name` check removed                      | `test_action_name_control_suppresses_cancel_sound`                                                            |

- **GDScript lint and format:** `gdlint scripts` and `gdformat --check scripts` pass, and so do `gdlint` and `gdformat --check` on `test_ui_sfx_menu_bus.gd`.
- **Not run locally:** Playwright (`volume_sliders_mutes_test.py`, `audio_flow_test.py`, `no_error_logs_test.py`), the PR benchmark table, and the manual itch.io checks. PR run: _fill in after CI._

---

## Known Limitations / Follow-ups

- **Manual itch.io checks** from the issue are still to do on the web build: Menu slider at 0 silences navigation, cancel and button sounds; navigation and cancel follow the Menu slider at normal volume; sounds still play in the main, options, pause and key mapping menus.
- **#1101 also changes `ui_manager.gd`** (`_track_input_device()`, lines 47–51). This PR doesn't touch those lines, so the rebase should be trivial.
- **The `_on_node_added` result should also be recorded in #619,** as the issue asks.

---

## Reviewer's Guide

### File-Level Changes

| Change          | Details                                                                                                                                                                                            | Files                                                                                                                                                        |
|-----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Menu bus.       | <ul><li>Navigation and cancel play on `BUS_SFX_MENU`.</li></ul>                                                                                                                                    | `scripts/managers/ui_manager.gd`                                                                                                                             |
| Menu context.   | <ul><li>Dead debug/CI fallback removed.</li><li>Scene-name heuristic removed; group and metadata opt-ins kept.</li></ul>                                                                           | `scripts/managers/ui_manager.gd`                                                                                                                             |
| Remap check.    | <ul><li>`has_method("cancel_remap")` removed; `action` / `action_name` kept.</li></ul>                                                                                                             | `scripts/managers/ui_manager.gd`                                                                                                                             |
| Tests.          | <ul><li>Helper uses the `menu_context` group; bus assertions; 9 new cases.</li><li>New real-manager suite, 8 cases.</li><li>Navigation bus asserts in Scenario C; new cancel Scenario D.</li></ul> | `test/gut/test_nav_escape_sfx.gd`<br/>`test/gut/test_ui_sfx_menu_bus.gd`<br/>`test/gut/test_ui_sfx_menu_bus.gd.uid`<br/>`test/gut/test_audio_integration.gd` |
| Milestone note. | <ul><li>This note.</li></ul>                                                                                                                                                                       | `files/docs/milestones/27/Part_20_Route_all_UI_sounds_through_the_Menu_bus_&_clean_up_UiManager.md`                                                          |

### Assessment against linked issues

| Issue                                                   | Objective                                                                   | Addressed | Explanation                                                                                                                            |
|---------------------------------------------------------|-----------------------------------------------------------------------------|-----------|----------------------------------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1152> | All UI sounds use `BUS_SFX_MENU`                                            | ✅         | Navigation and cancel moved; accept already used it.                                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1152> | No dead branch, scene-name heuristic or `cancel_remap` check in `UiManager` | ✅         | All three removed.                                                                                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1152> | `menu_context` group on the scenes that need it                             | ✅         | No scene needs it: the heuristic never matched in production, and adding it to the main menu would change behavior (Design Decisions). |
| <https://github.com/ikostan/SkyLockAssault/issues/1152> | UI sounds still play in every menu                                          | ✅ / ⏳     | Covered by GUT and gdUnit4 navigation suites; manual itch.io check still to do.                                                        |
| <https://github.com/ikostan/SkyLockAssault/issues/1152> | `_on_node_added` result recorded                                            | ✅ / ⏳     | Recorded here (Key Changes 4); still to add on the PR and in #619.                                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1152> | GUT, gdUnit4, Playwright and lint pass, no test cases removed               | ✅ / ⏳     | GUT, gdUnit4 and lint pass locally; Playwright runs in CI.                                                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1152> | Milestone note added                                                        | ✅         | This note.                                                                                                                             |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1152 from the #619 (Region 4) review, with the 2026-11-05 decision that the Menu slider controls all UI sounds.
- Decided not to add the `menu_context` group to `main_menu.tscn` once the probe showed the name heuristic never matched in production.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked the issue's line references against `main` and found that `main_menu.tscn`'s root is `Control`, so the scene-name heuristic never matched in production; confirmed it with a probe on the real main menu.
    - Ran the new and updated tests against `main`'s `ui_manager.gd`: 11 cases fail.
  - **Fix**
    - Routed navigation and cancel through `BUS_SFX_MENU`, removed the dead fallback, the name heuristic and the `cancel_remap` check.
    - Reworked `test_nav_escape_sfx.gd` to use the `menu_context` group and added 9 cases, added Menu-bus asserts and Scenario D to `test_audio_integration.gd`, and wrote `test_ui_sfx_menu_bus.gd`.
  - **Measurement**
    - Timed `_on_node_added` during the benchmark's 60 s firing window with temporary instrumentation (not committed).
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, `gdformat` and `gdlint` locally, and broke each change to confirm a new test catches it.
    - Wrote this note.
