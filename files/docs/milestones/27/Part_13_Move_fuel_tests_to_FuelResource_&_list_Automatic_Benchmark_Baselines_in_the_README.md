<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Move fuel tests to FuelResource & list Automatic Benchmark Baselines in the README

---

## PR #TBD Summary

**Title:** Move fuel tests from the settings resource to FuelResource  
**PR:** #TBD  
**Branch:** `test/1142-fuel-tests-to-fuel-resource` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1142 – [FEATURE] Move fuel tests from the settings resource to FuelResource](https://github.com/ikostan/SkyLockAssault/issues/1142)
- [#1134 – [BUG] README docs list is missing Automatic Benchmark Baselines](https://github.com/ikostan/SkyLockAssault/issues/1134)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** enhancement, testing, refactoring, GUT, gdunit4, bug, documentation

### Purpose

Fuel state lives on `FuelResource`, but many tests still set and read it through `GameSettingsResource` (`current_fuel`, `fuel_depleted`, `refuel()`). They passed only because the player's compatibility bridge copies fuel between the two resources. #1143 removes that API and the bridge, so these tests have to move first.

This PR changes tests only, so any failure comes from the test migration and not from production code. It also adds the missing Automatic Benchmark Baselines row to the README's Documentation table (#1134).

---

## Key Changes

### 1. Tests migrated by what they check (#1142)

The search from #1142 found 63 references in 14 files (the issue listed about 59 in 13 files). `test_globals_fuel_telemetry.gd` was added after the issue was written.

| What the test checks                   | Now uses                                                                     | Files                                                                                                                                                                          |
|----------------------------------------|------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Player, HUD or difficulty behavior     | `player.fuel_resource` (the same instance `main_scene` injects into the HUD) | `test_player.gd`, `test_difficulty.gd`, `test_difficulty_integration.gd`, `test_fuel_additional_edge_cases.gd`, `test_player_movement_signals.gd`, `test_player_fuel_logic.gd` |
| Fuel rules: depletion signal, refuel   | A `FuelResource` instance                                                    | `test_fuel_edge_cases.gd`, `test_fuel_integration.gd`, `test_fuel_additional_edge_cases.gd`                                                                                    |
| UI reacting to fuel signals            | `FuelResource.fuel_changed`; `max_fuel` still through `setting_changed`      | `test_fuel_ui.gd`, `test_fuel_persistence_integration.gd`                                                                                                                      |
| Non-persisted setting filtering        | Another runtime-only property on the resource                                | `test_globals_setting_change_filter.gd`, `test_globals_fuel_telemetry.gd`                                                                                                      |
| A stale `current_fuel` key in a config | The key stays as test data                                                   | `test_globals_settings_serialization.gd`                                                                                                                                       |

- **Filter tests:** `current_fuel` was replaced with `low_yellow_fraction` in the runtime-properties list (it wasn't there yet), `lateral_speed` in the one-minute end-to-end loop and in `test_globals_fuel_telemetry.gd`, and `max_speed` in the benchmark runner case. Each new key is asserted to be outside `persisted_schema`.
- **`test_globals_fuel_telemetry.gd`:** two test functions were renamed from `fuel` to `runtime` (`test_runtime_notification_skips_persistence_and_logging`, `test_bulk_loading_still_suppresses_runtime_side_effects`), because they no longer use fuel.
- **Stale config key:** `test_load_ignores_unknown_keys_resource_names_and_wrong_section_case` used to check `settings.current_fuel == 100.0`. It now snapshots every script property on the resource before and after the load, which is a stronger check and survives #1143.

### 2. Bridge tests (marked for #1143)

Tests whose purpose is the settings ↔ player bridge are kept and marked `BRIDGE TEST (#1143)`, so #1143 rewrites them to confirm the bridge is gone:

- **`test_player_fuel_logic.gd`, 2 new tests:** `test_engine_reignites_on_refuel` used to refuel through `Globals.settings`, so it was the only test that exercised the settings → player direction. It now refuels through `fuel_resource`. To keep the bridge covered until #1143, two new tests check it directly:
  - `test_bridge_settings_fuel_write_reaches_fuel_resource`: a settings write reaches `fuel_resource` and reignites the engine and rotors.
  - `test_bridge_fuel_resource_change_mirrors_to_settings`: a `fuel_resource` change is mirrored into `Globals.settings.current_fuel`.
- **`test_parallax_manager.gd`:** the "settings fuel must not drive the background" part of `test_replacing_settings_ignores_old_difficulty_and_fuel_settings`.
- **`test_player_lifecycle.gd`:** the `setting_changed` bridge connect and disconnect checks. No API reference, marked so #1143 finds it.

### 3. State leaks fixed on the way

- **`test_fuel_integration.gd`** replaced `Globals.settings` in `before_each()` and never restored it. It now saves and restores it, as #1142's acceptance criteria require.
- **`test_fuel_ui.gd`** connected a lambda to `Globals.settings.setting_changed` and never disconnected it, so the listener outlived the test. It now observes a local `FuelResource`, and its `before_each()`/`after_each()` (which only saved and restored `current_fuel`) were removed.
- **`before_test()`/`after_test()`** in `test_player.gd`, `test_difficulty.gd` and `test_difficulty_integration.gd` no longer save and restore `settings.current_fuel`. The tests don't set it any more. The player's bridge still writes it until #1143, but nothing reads it, and the next player's `_ready()` resets it from `fuel_resource`.

### 4. README (#1134)

- Added row 14, [Automatic Benchmark Baselines](../../Automatic_Benchmark_Baselines.md), after the Performance Benchmark Guide, and renumbered Milestone notes to 15. Every file in `files/docs/` is now listed.

---

## Design Decisions

- **Tests only.** Nothing under `scripts/` changes, so a failing test points at the migration, not at production code.
- **Config keys aren't the API.** `"current_fuel"` as a saved-config key, or as a string passed to `_on_setting_changed()`, doesn't use the settings fuel API. Config keys stay as test data, per #1142. Strings passed to the Globals filter were swapped anyway, because a runtime property that still exists on the resource tests the filter better.
- **New bridge tests instead of keeping old ones on the bridge.** Migrating `test_engine_reignites_on_refuel` left the settings → player direction untested, so two small, clearly marked tests cover both directions until #1143. That's why `test_player_fuel_logic.gd` goes from 4 to 6 cases.
- **One PR for both issues.** #1134 is a two-line README fix with no overlap, so it rides along instead of taking its own PR.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, using the same commands as `gut_tests.yml` and `gdunit4_tests.yml` (gdUnit4-coverage stripped, `xvfb-run`).

- **Before (`0dab7ae`, `main`):** GUT 874 passed, 10,145 asserts. gdUnit4 155 passed.
- **After (`2e483b6`):** GUT 876 passed, 10,152 asserts. gdUnit4 155 passed. No script or parse errors in either log.
- **Test counts per changed file (before → after):**

| File                                     | Framework | Cases   |
|------------------------------------------|-----------|---------|
| `test_player.gd`                         | gdUnit4   | 16 → 16 |
| `test_difficulty.gd`                     | gdUnit4   | 1 → 1   |
| `test_difficulty_integration.gd`         | gdUnit4   | 1 → 1   |
| `test_fuel_additional_edge_cases.gd`     | GUT       | 2 → 2   |
| `test_fuel_edge_cases.gd`                | GUT       | 1 → 1   |
| `test_fuel_ui.gd`                        | GUT       | 1 → 1   |
| `test_fuel_integration.gd`               | GUT       | 2 → 2   |
| `test_fuel_persistence_integration.gd`   | GUT       | 4 → 4   |
| `test_globals_setting_change_filter.gd`  | GUT       | 8 → 8   |
| `test_globals_settings_serialization.gd` | GUT       | 26 → 26 |
| `test_globals_fuel_telemetry.gd`         | GUT       | 3 → 3   |
| `test_player_movement_signals.gd`        | GUT       | 5 → 5   |
| `test_player_fuel_logic.gd`              | GUT       | 4 → 6   |
| `test_parallax_manager.gd`               | GUT       | 16 → 16 |
| `test_player_lifecycle.gd`               | GUT       | 2 → 2   |

- **Simulated #1143:** in a scratch copy, `current_fuel`, `fuel_depleted` and `refuel()` were removed from `GameSettingsResource`, and the player's mirror and listener body were removed. GUT then ran 876 cases and only the three marked tests failed: the two new bridge tests and the marked part of `test_replacing_settings_ignores_old_difficulty_and_fuel_settings`. gdUnit4 passed all 155. So no unmarked test still depends on the API.
- **Remaining matches** for the #1142 search: the two new bridge tests (`test_player_fuel_logic.gd:108`, `:124`), the marked parallax line (`test_parallax_manager.gd:336`), and the stale config key test data (`test_globals_settings_serialization.gd:179`, `:268`).
- **Not verified yet:** the PR pipeline run.

---

## Known Limitations / Follow-ups

- **#1143:** rewrite the four `BRIDGE TEST (#1143)` spots to confirm the bridge is gone, and remove the API from `GameSettingsResource` and `player.gd`.
- **`test_player_lifecycle.gd`:** its marked bridge checks didn't fail in the simulation, because the scratch copy kept `_on_setting_changed()` as an empty function. They fail once #1143 deletes it.
- **Until #1143:** the bridge still writes `Globals.settings.current_fuel` during tests, and the suites no longer restore it. Nothing reads it, so this has no effect.

---

## Reviewer's Guide

### File-Level Changes

| Change                | Details                                                                                                                          | Files                                                                                                                                                                                                                  |
|-----------------------|----------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Player and HUD tests. | <ul><li>Fuel set and read through `player.fuel_resource`.</li><li>`current_fuel` save and restore removed from setup.</li></ul>  | `test/gdunit4/test_player.gd`<br/>`test/gdunit4/test_difficulty.gd`<br/>`test/gdunit4/test_difficulty_integration.gd`<br/>`test/gut/test_fuel_additional_edge_cases.gd`<br/>`test/gut/test_player_movement_signals.gd` |
| Fuel rule tests.      | <ul><li>Depletion signal and negative refuel on a `FuelResource`.</li><li>`Globals.settings` restored after each test.</li></ul> | `test/gut/test_fuel_edge_cases.gd`<br/>`test/gut/test_fuel_integration.gd`<br/>`test/gut/test_fuel_additional_edge_cases.gd`                                                                                           |
| UI signal tests.      | <ul><li>`fuel_changed` drives the bar value.</li><li>No listener left on `Globals.settings`.</li></ul>                           | `test/gut/test_fuel_ui.gd`<br/>`test/gut/test_fuel_persistence_integration.gd`                                                                                                                                         |
| Globals filter tests. | <ul><li>Runtime-only keys instead of `current_fuel`.</li><li>Full property snapshot on load.</li></ul>                           | `test/gut/test_globals_setting_change_filter.gd`<br/>`test/gut/test_globals_fuel_telemetry.gd`<br/>`test/gut/test_globals_settings_serialization.gd`                                                                   |
| Bridge tests.         | <ul><li>2 new tests, both directions.</li><li>Existing bridge checks marked for #1143.</li></ul>                                 | `test/gut/test_player_fuel_logic.gd`<br/>`test/gut/test_parallax_manager.gd`<br/>`test/gut/test_player_lifecycle.gd`                                                                                                   |
| README.               | <ul><li>Automatic Benchmark Baselines row added; Milestone notes renumbered.</li></ul>                                           | `README.md`                                                                                                                                                                                                            |
| Milestone note.       | <ul><li>This note.</li></ul>                                                                                                     | `files/docs/milestones/27/Part_13_Move_fuel_tests_to_FuelResource_&_list_Automatic_Benchmark_Baselines_in_the_README.md`                                                                                               |

### Assessment against linked issues

| Issue                                                   | Objective                                                                      | Addressed | Explanation                                                                                   |
|---------------------------------------------------------|--------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1142> | All migrated files pass in GUT and gdUnit4                                     | ✅         | Locally; the PR run is still to come.                                                         |
| <https://github.com/ikostan/SkyLockAssault/issues/1142> | Test cases per file are the same or higher, with before and after counts       | ✅         | Table above. `test_player_fuel_logic.gd` 4 → 6; every other file unchanged.                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1142> | Remaining references to the settings fuel API are only the marked bridge tests | ✅         | Plus the stale config key, which #1142 keeps as test data. Confirmed by the #1143 simulation. |
| <https://github.com/ikostan/SkyLockAssault/issues/1142> | Tests restore any `Globals.settings` values they change                        | ✅         | `test_fuel_integration.gd` now restores it.                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1142> | No change under `scripts/`                                                     | ✅         | Tests, README and this note only.                                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1134> | Every doc in `files/docs/` is listed in the README                             | ✅         | Row 14 added, Milestone notes renumbered to 15.                                               |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1142 and #1134 and set their scope.
- Picked #1142 as the next task and added #1134 to the same PR.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Next task**
    - Mapped the Milestone 27 blocking chains and recommended #1142, the start of the longest one (#1142 → #1143 → #1147 → #1148 → #1151).
  - **Migration**
    - Re-ran the #1142 search (63 references in 14 files), migrated each test by what it checks, and marked the bridge tests.
    - Found the `Globals.settings` leak in `test_fuel_integration.gd` and the leftover listener in `test_fuel_ui.gd`, and added two bridge tests to keep both directions covered.
  - **Verification**
    - Ran GUT and gdUnit4 locally before and after, with the CI commands, and compared counts per file.
    - Simulated #1143 in a scratch copy to show that only the marked tests still use the API.
  - **README**
    - Added the #1134 row.
  - Commits:
    - `2e483b6` Move fuel tests from the settings resource to FuelResource

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
