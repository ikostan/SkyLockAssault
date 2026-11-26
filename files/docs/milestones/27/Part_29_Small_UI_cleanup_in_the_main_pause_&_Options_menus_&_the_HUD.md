<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Small UI cleanup in the main, pause and Options menus, and the HUD

---

## PR Summary

**Title:** Small UI cleanup in the main, pause and Options menus, and the HUD  
**PR:** TBD (not opened yet)  
**Branch:** `ui-cleanup-main-pause-options-menus-and-hud-1169` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1169 – [FEATURE] Small UI cleanup in the main, pause, and Options menus, and the HUD](https://github.com/ikostan/SkyLockAssault/issues/1169)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `enhancement`, `GUT`, `refactoring`

### Purpose

The third sub-issue of #621 (Region 6: Presentation & View Layers). It removes five leftovers from earlier changes, all Low findings from the #621 review:

| Finding                                                                   | Fixed by     |
|---------------------------------------------------------------------------|--------------|
| The quit dialog removes a click handler that `Globals` no longer owns     | Key Change 1 |
| Unused `options_menu` preloads in the main and pause menus                | Key Change 2 |
| The pause menu and Options log every left click                           | Key Change 3 |
| The same HUD disconnect block in `setup_hud()` and `_exit_tree()`         | Key Change 4 |
| `_on_speed_low()` and `_on_speed_maxed()` repeat `check_speed_warning()`  | Key Change 5 |

There is no change for the player: menu sounds, Options access and HUD warnings behave as before.

---

## Confirm-first results

Both points were checked against `main` (`4f35da2`) before any code changed, with GUT cases that are now kept as regression tests (Key Change 6):

- **Quit dialog, confirmed.**
  - `Globals` has no `_on_global_button_pressed`; only `SfxManager` does. The two loops in `_setup_quit_dialog()` matched `Globals` as the owner, so they could never disconnect anything.
  - `SfxManager._on_node_added()` skips every button inside an `AcceptDialog` (`sfx_manager.gd:418-423`). A plain `ConfirmationDialog` that `main_menu.gd` never touches also gets no global sound connection on its OK and Cancel buttons.
  - The main menu's quit dialog buttons have no `_on_global_button_pressed` connection, and pressing OK or Cancel plays exactly one sound (`ui_accept` or `ui_cancel`).
- **HUD speed blink, confirmed.**
  - With every HUD handler removed from `speed_low` and `speed_maxed`, blinking still starts at the low threshold and at maximum speed, and stops back in the normal range, through `check_speed_warning()` alone.
  - Why it always holds: `SpeedResource.current_speed` emits `speed_updated` before `speed_low` and `speed_maxed`, so `check_speed_warning()` has already run. `speed_low` fires at `current_speed <= get_low_threshold()`, the same condition `check_speed_warning()` uses. `speed_maxed` fires at `max_speed`, which is always at or above the high warning band, because `high_yellow_fraction` is clamped to 1.0.
- **Issue line numbers had moved.** `main_menu.gd`: the preload is at `:40` (not `:38`), and the two loops are at `:281-301` (not `:221-240`). The other locations matched.
- **Baseline on `main`:** full GUT suite 1,290/1,290 (121 scripts, 16,176 asserts).

---

## Key Changes

### 1. Quit dialog (`main_menu.gd`)

- Deleted both disconnect loops in `_setup_quit_dialog()`. The `confirmed` and `canceled` connections stay.
- A short comment says why nothing needs sanitizing, and the DEBUG log now reads "QuitDialog signals connected." (it no longer claims to sanitize buttons).

### 2. Unused preloads (`main_menu.gd`, `pause_menu.gd`)

- Deleted the `options_menu` variables in both menus and the `:vartype options_menu:` doc line in `main_menu.gd`. Both menus open Options through `Globals.load_options()`.
- Also removes an eager load of `options_menu.tscn` each time either menu script loads.

### 3. Click logging (`pause_menu.gd`, `options_menu.gd`)

- Deleted `_input()` in both. It only logged left clicks at DEBUG.

### 4. One place to disconnect HUD signals (`hud.gd`)

- New `_disconnect_resources(speed, fuel, weapon)` disconnects the HUD from whichever resources it's given; `null` leaves a resource alone.
- `setup_hud()` passes only the resources being replaced (the old one when it differs from the new one, otherwise `null`), so re-injecting the same resource keeps its wiring.
- `_exit_tree()` passes all three current resources.

### 5. Speed handlers (`hud.gd`)

- Deleted `_on_speed_low()` and `_on_speed_maxed()`, with their connect and disconnect lines. The speed blink comes only from `check_speed_warning()`, which runs on every `speed_updated` and `thresholds_changed`.
- `SpeedResource.speed_low` and `speed_maxed` are unchanged; `player.gd` still forwards them.

### 6. Tests

**No test case was removed.**

- **Updated:** `test/gdunit4/test_pause_menu.gd` PM-07 called `menu._input()` directly with a left and a right click. It now checks that `pause_menu.gd` defines no `_input()`. The pause toggle checks in the same case are unchanged.
- **`test/gut/test_quit_game_confirm_dialog_sfx.gd` (+6, 8 in total):**
  - `Globals` has no global button sound handler; `SfxManager` does.
  - A plain `ConfirmationDialog` gets no global sound connection on its OK and Cancel buttons.
  - The quit dialog's OK and Cancel buttons have none either.
  - Pressing OK plays one `ui_accept`; pressing Cancel plays one `ui_cancel` and no `ui_accept`, counted after deferred calls.
  - Setting the dialog up again keeps one `confirmed` and one `canceled` connection, and leaves it hidden.
- **`test/gut/test_hud.gd` (+8, 26 in total):**
  - Speed blinking starts at the low threshold and at maximum speed and stops in the normal range, with no HUD handler on `speed_low` or `speed_maxed` (the confirm-first case).
  - Maximum speed is inside the warning band even with `high_yellow_fraction` set to 1.0.
  - The HUD doesn't connect to `speed_low` or `speed_maxed`.
  - Initial wiring makes exactly two HUD connections per resource.
  - `setup_hud()` with the same resources disconnects nothing.
  - `setup_hud()` with one new resource (speed, fuel or weapon, parameterized) disconnects only the replaced one.
  - Leaving the tree removes every HUD connection from all three resources.
  - Freeing a second HUD leaves no connections to it, and the first HUD still reacts.
- **New `test/gut/test_menu_click_logging.gd` (3 tests):**
  - A left click pushed through the viewport with the pause menu or Options open logs no "Clicked at" line (captured with `OS.add_logger()`, at DEBUG level), and neither script defines `_input()`.
  - Neither the main nor the pause menu keeps an `options_menu` scene.
  - On `main`, all three failed, so they do catch the old logging.

---

## Design Decisions

- **`null` means "leave connected"** in `_disconnect_resources()`, as the issue suggested. `setup_hud()` decides which resources are replaced, and the helper only disconnects.
- **The `is_connected()` guards stay** in the helper, so it's safe to call on a resource that was never connected or was already disconnected.
- **PM-07 checks the script's own method list,** not `has_method("_input")`. `_input` is a virtual method of `Node`, so `has_method()` doesn't say whether the script still overrides it.
- **The click test pushes real input through the viewport** and captures the log, so it proves the behavior ("a click logs nothing"), not only that a function is gone.

---

## Verification

Run locally on the branch with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 v6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdlint ./scripts` and `gdformat --check ./scripts` as in CI.

| State              | GUT scripts | GUT tests | GUT asserts |
|--------------------|-------------|-----------|-------------|
| `main` (`4f35da2`) | 121         | 1,290     | 16,176      |
| This branch        | 122         | 1,307     | 16,237      |

- **Full GUT suite locally:** 1,307/1,307.
- **Full gdUnit4 suite locally:** 170/170 (27 suites), including PM-07 and the `check_speed_warning()` cases in `test_player.gd`.
- **GDScript lint and format:** pass.
- **Before the code change,** the new tests that describe the new code failed as expected (7 failures: the HUD speed connections, the click logs and the preloads), and all confirm-first cases passed.
- **Not run locally:** Playwright (`back_flow_test.py`, `telemetry_and_hold_test.py`, `no_error_logs_test.py`), the benchmark and the manual itch.io checks.

---

## Known Limitations / Follow-ups

- **Manual itch.io checks still to do:**
  - Quit plays one confirm or cancel sound.
  - The speed label blinks at low and maximum speed as before.
- **Benchmark:** the scenario is unchanged; check the PR table.
- **Found while testing, not part of this PR:** `test/gut/test_weapon_slot_cooldown.gd` (#1138) extends `GdUnitTestSuite` but sits in the GUT folder. GUT can't parse it and skips it ("Could not find base class GdUnitTestSuite"), and the gdUnit4 job only runs `test/gdunit4`, so neither runner runs it. Moving it to `test/gdunit4/` should be a separate small fix.
- **Next in #621:** #1182 (Advanced), #1180 (Audio) and #1181 (Key Mapping) onto `SettingsMenuBase`, then #1183 (shared loader).

---

## Reviewer's Guide

### File-Level Changes

| Change          | Details                                                                                                                             | Files                                                                                                                |
|-----------------|-------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| Quit dialog.    | <ul><li>Dead disconnect loops removed.</li></ul>                                                                                    | `scripts/ui/menus/main_menu.gd`                                                                                      |
| Preloads.       | <ul><li>Unused `options_menu` variables and doc line removed.</li></ul>                                                             | `scripts/ui/menus/main_menu.gd`<br/>`scripts/ui/menus/pause_menu.gd`                                                 |
| Click logging.  | <ul><li>`_input()` removed.</li></ul>                                                                                               | `scripts/ui/menus/pause_menu.gd`<br/>`scripts/ui/menus/options_menu.gd`                                              |
| HUD.            | <ul><li>`_disconnect_resources()` used by `setup_hud()` and `_exit_tree()`.</li><li>Speed low and maxed handlers removed.</li></ul> | `scripts/ui/hud.gd`                                                                                                  |
| GUT tests.      | <ul><li>6 quit dialog tests; 8 HUD tests; new click logging suite (3).</li></ul>                                                    | `test/gut/test_quit_game_confirm_dialog_sfx.gd`<br/>`test/gut/test_hud.gd`<br/>`test/gut/test_menu_click_logging.gd` |
| gdUnit4 tests.  | <ul><li>PM-07 checks there's no `_input()` instead of calling it.</li></ul>                                                         | `test/gdunit4/test_pause_menu.gd`                                                                                    |
| Milestone note. | <ul><li>This note.</li></ul>                                                                                                        | `files/docs/milestones/27/Part_29_Small_UI_cleanup_in_the_main_pause_&_Options_menus_&_the_HUD.md`                   |

### Assessment against linked issues

| Issue                                                   | Objective                                                               | Addressed | Explanation                                         |
|---------------------------------------------------------|-------------------------------------------------------------------------|-----------|-----------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | The confirm-first results are recorded on the PR                        | ✅        | Confirm-first results.                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | The five items are removed or simplified as described                   | ✅        | Key Changes 1-5.                                    |
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | Menu sounds, Options access and HUD warnings behave as before           | ✅        | GUT and gdUnit4 suites; manual checks still to do.  |
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | All GUT, gdUnit4, Playwright and lint jobs pass; no cases removed       | ⏳        | GUT, gdUnit4 and lint pass locally; CI not run yet. |
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | The PR's milestone note is added under `files/docs/milestones/`         | ✅        | This note.                                          |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1169 from the #621 (Region 6) review, with the confirm-first steps and the proposed changes.
- Picked #1169 as the next PR.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked both points on `main` with GUT before changing code, and traced why the speed blink can't depend on `speed_low` or `speed_maxed` (signal order and the clamped `high_yellow_fraction`).
    - Found the moved line numbers in `main_menu.gd`.
  - **Changes**
    - Implemented the five cleanups and the `_disconnect_resources()` helper.
  - **Tests**
    - Wrote the 17 new GUT tests and rewrote PM-07 without removing it.
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, `gdlint` and `gdformat` before and after the change.
    - Found that `test_weapon_slot_cooldown.gd` never runs in either test job.
    - Wrote this note.
