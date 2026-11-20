<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Simplify AudioManager bus state & move bus hierarchy rules into AudioManager

---

## PR Summary

**Title:** Simplify AudioManager bus state and move bus hierarchy rules into AudioManager  
**PR:** _fill in after the PR is opened_  
**Branch:** `feature-audiomanager-bus-config-and-hierarchy` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1153 – [FEATURE] Simplify AudioManager bus state lookups](https://github.com/ikostan/SkyLockAssault/issues/1153)
- [#1154 – [FEATURE] Move audio bus hierarchy rules into AudioManager](https://github.com/ikostan/SkyLockAssault/issues/1154)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `enhancement`, `audio`, `refactoring`, `GUT`

### Purpose

Two findings from the #619 (Region 4) review, done in one PR because #1154 builds on the `BUS_CONFIG` that #1153 makes the single source for bus state:

- **#1153:** `AudioManager` repeated the same bus-to-variable mapping in four `match` blocks (`get_volume`, `set_volume`, `get_muted`, `set_muted`), although `AudioConstants.BUS_CONFIG` already held it. Its 12 bus state variables were also `@export`, which does nothing on an autoload with no scene.
- **#1154:** the rule "a muted parent locks its child buses" was written separately in `audio_settings.gd` (control locks and warning dialogs) and in both guards of `audio_web_bridge.gd`, so they could drift apart.

No behavior changes: control locks, warning dialogs, web guard messages, signals and saved settings are the same as on `main`.

---

## Confirm-first results

This is a refactor, so the new tests are expected to pass on `main` except where they check something new. They were run against `main`'s production code (`f7cd427`, all four changed scripts reverted):

| Tests                                                                                                        | On `main`                                                                                               |
|--------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| UI lock and warning pins (`test_audio_hierarchy_and_sliders.gd`), bridge guards (`test_audio_web_bridge.gd`) | 30/30 pass. The pins encode the behavior `main` has, so they guard the refactor rather than a new rule. |
| `test_audio_manager_bus_state.gd`, #1153 part (11 tests)                                                     | 10 pass; `test_bus_state_vars_are_not_exported` fails, because the variables are `@export` on `main`.   |
| `test_audio_manager_bus_state.gd`, #1154 part (12 tests)                                                     | All fail: `get_parent_bus()` and the other hierarchy methods don't exist on `main`.                     |

---

## Key Changes

### 1. Bus state lookups through `BUS_CONFIG` (#1153, `audio_manager.gd`)

- `get_volume()`, `set_volume()`, `get_muted()` and `set_muted()` look the bus up in `AudioConstants.BUS_CONFIG` and read or write its `volume_var` / `muted_var` with `get()` / `set()`. The four per-bus `match` blocks are gone.
- **Unknown buses behave as before:** `get_volume()` returns `0.0`, `get_muted()` returns `false`, the setters change nothing and emit nothing, and each logs the same `Unknown bus for <function>: <bus>` warning.
- **Signals unchanged:** `volume_changed` and `mute_toggled` still fire once per call for a known bus, even when the value is unchanged.
- The unreachable "check config drift" error branch in `set_volume()` is removed: the lookup can no longer drift from `BUS_CONFIG`, and a new test catches a `BUS_CONFIG` entry that names a missing variable.
- The six per-bus debug logs in `set_volume()` are one: `<bus> volume level in AudioManager: <value>`. No test or Playwright check reads them.
- The 12 variables are plain `var` and keep their names (tests and callers use them directly). The `@export_category` lines are gone.
- `audio_manager.gd` alone: 124 lines removed, 48 added by this part.

### 2. `parent` in `BUS_CONFIG` (#1154, `audio_constants.gd`)

| Bus                                    | `parent` |
|----------------------------------------|----------|
| `Master`                               | `""`     |
| `Music`, `SFX`                         | `Master` |
| `SFX_Weapon`, `SFX_Rotors`, `SFX_Menu` | `SFX`    |

It mirrors the sends in `default_bus_layout.tres`, and a test checks that they match.

### 3. Hierarchy methods (#1154, `audio_manager.gd`)

- `get_parent_bus(bus)`: the bus's parent, `""` for Master; an unknown bus logs a warning and returns `""`.
- `get_muted_ancestor(bus)`: the muted ancestor that locks the bus, or `""`. The bus's own mute doesn't count. **When several ancestors are muted, it returns the one nearest Master** (see Design Decisions). The walk is capped at the `BUS_CONFIG` size, so a parent cycle can't loop forever.
- `is_effectively_muted(bus)`: the bus or any ancestor is muted.
- All three are read-only: no state change, no signals.

### 4. Callers use them (#1154)

- **`audio_settings.gd`:**
  - `_update_ui_interactivity()` loops over `BUS_CONFIG`: a mute button is disabled when `get_muted_ancestor()` isn't empty, and a slider is editable when `is_effectively_muted()` is false. New `_get_mute_button_for_bus()` next to `_get_slider_for_bus()`.
  - The warning handlers no longer receive parent flags. Each `_on_*_gui_input()` wrapper passes its bus name, and `_handle_slider_gui_input()` / `_handle_mute_gui_input()` ask `get_muted_ancestor()`; `_show_parent_mute_warning()` picks the Master or SFX dialog. The `master_warning_shown` / `sfx_warning_shown` flags and the "click a muted slider to unmute it" behavior are unchanged.
- **`audio_web_bridge.gd`:** both guards (`_on_change_volume_js()`, `_on_toggle_mute_js()`) use `get_muted_ancestor()`. The warnings are built from its result, so the text is the same as before (`Warning dialog: Master muted, cannot adjust sub-volume`, and so on), and the DOM resync is unchanged. `tests/audio_flow_test.py` matches on that text.

### 5. Tests

No existing test case was removed or changed.

- **New `test/gut/test_audio_manager_bus_state.gd` (23 tests), on a fresh `AudioManager` instance outside the tree**, so the autoload's state and the user's settings are untouched:
  - **#1153 (11):** `BUS_CONFIG` lists exactly the six buses; each entry's `volume_var` / `muted_var` match an independent table and exist as `float` / `bool`; the variables aren't exported; set/get round-trips for every bus, checked against the variable itself; direct assignments are read back; setting one bus leaves the other five unchanged; each setter emits once with the right arguments, also for unchanged values; unknown buses return `0.0` / `false`, change nothing, emit nothing and log the four warnings.
  - **#1154 (12):** every entry has a `String` `parent` naming another `BUS_CONFIG` bus or `""`; `get_parent_bus()` for all six and for an unknown bus; each parent matches the send in `default_bus_layout.tres`; nothing muted, own mute only, Master muted, SFX muted, Master and SFX both muted, muted siblings and children; all 64 mute combinations against an independent reference; the queries are read-only.
- **`test/gut/test_audio_hierarchy_and_sliders.gd` (+2 tests):**
  - All 64 mute combinations: every mute button's `disabled` and slider's `editable` match the rules the menu used on `main`, written out independently in the test.
  - Warning dialogs for 15 cases, slider and mute button: the locking ancestor's dialog (Master before SFX), and none for unlocked controls. This also covers the Menu bus, which had no warning test.
- **`test/gut/test_audio_web_bridge.gd` (+3 tests, TC-AWB-18 to 20):** volume and mute changes to a bus under a muted Master or SFX are rejected, resynced to the DOM, and logged with the ancestor's name, for every child bus, with Master reported first when both are muted; a bus whose own, sibling or child bus is muted still accepts changes.

---

## Design Decisions

- **`get_muted_ancestor()` returns the muted ancestor nearest Master, not the nearest one.** #1154's method comment says "nearest muted ancestor", but its acceptance criteria say control locking and web behavior stay the same, with today's warning messages. Today both callers check Master first: with Master and SFX both muted, a Weapon slider shows "unmute Master" and the bridge logs `Master muted`. The nearest ancestor would be SFX and change both. Master is also the bus the player must unmute first, since SFX's mute button is locked while Master is muted. `test_master_wins_over_sfx` and the UI and bridge pins fail if the method returns the nearest ancestor.
- **The warning handlers in `audio_settings.gd` were changed too.** #1154 names only the control locks (`_update_ui_interactivity()`), but the handlers also encoded the hierarchy: each wrapper passed `master_muted` / `sfx_muted` for its own parents. Leaving them would fail the criterion that neither caller re-implements the rules. The `SettingsMenuBase` migration (#1180) and the label-color polling (#621) are not touched.
- **New suite instead of extending an existing one.** #1153 asked to add the tests to an existing AudioManager suite. The GUT AudioManager suites are each about one feature (auto-mute, config parsing, mute pipeline), and none is about the bus state API, so the bus state and hierarchy tests got their own suite. It follows `test_audio_config_parsing.gd`'s pattern of a fresh instance outside the tree.
- **Variables stay; no `Dictionary`.** As #1153 says, the 12 variables keep their names and moving state into a `Dictionary` is out of scope: tests and callers read them directly.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 v6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdformat --check` and `gdlint` as in CI.

| State                    | GUT tests | GUT asserts | gdUnit4 test cases |
|--------------------------|-----------|-------------|--------------------|
| `main` (`f7cd427`, base) | 1,083     | 11,399      | 164                |
| This PR                  | 1,111     | 13,355      | 164                |

- **No test cases removed.**
- **Full GUT suite:** 1,111/1,111, including `test_audio_settings_comprehensive.gd`, `test_audio_manager_auto_mute.gd`, `test_unmute_from_zero.gd`, `test_toggle_mute_pipeline.gd`, `test_ui_audio_persistence.gd`, `test_error_edge_cases.gd`, `test_ui_mute_logic.gd` and `test_sfx_rotor_volume_control.gd` named by the issues.
- **gdUnit4 suite:** 164/164.
- **Breaking each change:** each change below, applied to this PR's code, makes at least one new or existing test fail.

| Change to the code                                        | Fails                                                                                                                                                     |
|-----------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `@export` back on `master_volume`                         | `test_bus_state_vars_are_not_exported`                                                                                                                    |
| `volume_var` swapped between `SFX_Rotors` and `SFX_Menu`  | `test_bus_config_vars_exist_with_correct_types`, `test_volume_round_trip`, `test_get_volume_reads_the_variable`, `test_setting_one_bus_leaves_the_others` |
| `get_volume()` returns `1.0` for an unknown bus           | `test_unknown_bus_is_rejected_with_warnings`                                                                                                              |
| `set_muted()` no longer emits `mute_toggled`              | 2 in `test_audio_manager_bus_state.gd`, 6 in `test_audio_hierarchy_and_sliders.gd`                                                                        |
| `get_muted_ancestor()` returns the nearest muted ancestor | `test_master_wins_over_sfx`, `test_all_mute_combinations_match_reference`, `test_warning_dialog_matches_locking_ancestor`, TC-AWB-18, TC-AWB-19           |
| `is_effectively_muted()` ignores the bus's own mute       | 4 in `test_audio_manager_bus_state.gd`, 2 in `test_audio_hierarchy_and_sliders.gd`                                                                        |
| `SFX_Menu`'s parent set to `Master`                       | `test_get_parent_bus`, `test_parent_matches_layout_send`, 2 more in the bus state suite, 2 UI pins, TC-AWB-18, TC-AWB-19                                  |
| Bridge volume guard checks only the direct parent         | TC-AWB-18                                                                                                                                                 |
| Mute buttons disabled by `is_effectively_muted()`         | `test_controls_match_legacy_locks_for_all_mute_combinations`                                                                                              |
| SFX lock shows the Master dialog                          | `test_warning_dialog_matches_locking_ancestor`                                                                                                            |

- **GDScript lint and format:** `gdlint scripts` and `gdformat --check scripts` pass, and so does `gdlint` on `test_audio_manager_bus_state.gd`.
- **Not run locally:** Playwright (`volume_sliders_mutes_test.py`, `reset_audio_flow_test.py`, `audio_flow_test.py`), the PR benchmark table, and the manual itch.io check. PR run: _fill in after CI._

---

## Known Limitations / Follow-ups

- **Manual itch.io check** from #1154 is still to do on the web build: muting Master or SFX locks and unlocks the same controls as before.
- **#1154's wording:** its method comment says "nearest muted ancestor"; this PR returns the one nearest Master (Design Decisions). The issue text can be updated to match.
- **#1153's "Do this after #1152"** no longer matters: #1152 merged in PR #1215.

---

## Reviewer's Guide

### File-Level Changes

| Change             | Details                                                                                                                                                            | Files                                                                                                                                                                                    |
|--------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Bus state lookups. | <ul><li>Four getters/setters read `BUS_CONFIG`; `match` blocks removed.</li><li>12 variables plain `var`.</li></ul>                                                | `scripts/managers/audio_manager.gd`                                                                                                                                                      |
| Bus hierarchy.     | <ul><li>`parent` field in `BUS_CONFIG`.</li><li>`get_parent_bus()`, `get_muted_ancestor()`, `is_effectively_muted()`.</li></ul>                                    | `scripts/resources/audio_constants.gd`<br/>`scripts/managers/audio_manager.gd`                                                                                                           |
| Menu.              | <ul><li>Control locks and warning handlers ask AudioManager.</li><li>`_get_mute_button_for_bus()`.</li></ul>                                                       | `scripts/ui/menus/audio_settings.gd`                                                                                                                                                     |
| Web bridge.        | <ul><li>Both guards use `get_muted_ancestor()`; same messages and resync.</li></ul>                                                                                | `scripts/system/audio_web_bridge.gd`                                                                                                                                                     |
| Tests.             | <ul><li>New bus state and hierarchy suite, 23 tests.</li><li>64-combination lock pin and warning dialog pin.</li><li>Bridge guard tests TC-AWB-18 to 20.</li></ul> | `test/gut/test_audio_manager_bus_state.gd`<br/>`test/gut/test_audio_manager_bus_state.gd.uid`<br/>`test/gut/test_audio_hierarchy_and_sliders.gd`<br/>`test/gut/test_audio_web_bridge.gd` |
| Milestone note.    | <ul><li>This note.</li></ul>                                                                                                                                       | `files/docs/milestones/27/Part_21_Simplify_AudioManager_bus_state_&_move_bus_hierarchy_rules_into_AudioManager.md`                                                                       |

### Assessment against linked issues

| Issue                                                   | Objective                                                             | Addressed | Explanation                                                                                           |
|---------------------------------------------------------|-----------------------------------------------------------------------|-----------|-------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1153> | The four functions read `BUS_CONFIG`, no per-bus `match` blocks       | ✅         | Key Changes 1.                                                                                        |
| <https://github.com/ikostan/SkyLockAssault/issues/1153> | The 12 variables keep their names and are plain `var`                 | ✅         | Pinned by `test_bus_config_vars_exist_with_correct_types` and `test_bus_state_vars_are_not_exported`. |
| <https://github.com/ikostan/SkyLockAssault/issues/1153> | Audio behavior, signals and saved settings unchanged                  | ✅         | Full GUT and gdUnit4 suites pass unchanged; signal and unknown-bus tests added.                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1154> | `AudioManager` owns the hierarchy rules, no caller re-implements them | ✅         | Menu locks, menu warnings and both bridge guards use the new methods (Design Decisions).              |
| <https://github.com/ikostan/SkyLockAssault/issues/1154> | Control locking and web behavior unchanged                            | ✅ / ⏳     | 64-combination and warning pins pass on `main` and this PR; manual itch.io check still to do.         |
| Both                                                    | GUT, Playwright and lint pass, no test cases removed                  | ✅ / ⏳     | GUT, gdUnit4 and lint pass locally; Playwright runs in CI.                                            |
| Both                                                    | Milestone note added                                                  | ✅         | This note.                                                                                            |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1153 and #1154 from the #619 (Region 4) review.
- Decided to do both issues in one PR.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked both issues against `main`: #1152 had merged, and #1154's "nearest muted ancestor" conflicts with its own criterion of unchanged warnings, since both callers report Master first.
    - Ran the new UI and bridge pins against `main`'s code (30/30 pass) and the bus state suite (only the `@export` test and the new hierarchy methods fail).
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, `gdformat` and `gdlint` locally, and broke each change (10 mutations) to confirm a test catches it.
    - Wrote this note.
