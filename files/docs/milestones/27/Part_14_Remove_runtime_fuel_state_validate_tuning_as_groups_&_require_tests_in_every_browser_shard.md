<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Remove runtime fuel state, validate tuning as groups & require tests in every browser shard

---

## PR #1195 Summary

**Title:** Require tests in every browser shard  
**PR:** [#1195](https://github.com/ikostan/SkyLockAssault/pull/1195)  
**Branch:** `1143-1147-1148-1194-fuel-tuning-and-ci-shard` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1143 – [FEATURE] Remove runtime fuel state and the player's global write](https://github.com/ikostan/SkyLockAssault/issues/1143)
- [#1147 – [FEATURE] Validate fuel thresholds as a group and define them as percentages](https://github.com/ikostan/SkyLockAssault/issues/1147)
- [#1148 – [FEATURE] Keep only plain tuning values in GameSettingsResource](https://github.com/ikostan/SkyLockAssault/issues/1148)
- [#1194 – [BUG] Browser Refactor Suite shard runs no tests but passes](https://github.com/ikostan/SkyLockAssault/issues/1194)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** enhancement, bug, refactoring, architecture, performance, testing, GUT, CI/CD, github actions, playwright

### Purpose

This PR finishes the fuel and tuning part of Region 2 (#617) and fixes a CI shard that passed without running anything.

- **#1143:** live fuel was kept in two places, `FuelResource` and `GameSettingsResource.current_fuel`, and the player copied every change between them. Every fuel tick emitted `setting_changed`, and a player without `Globals.settings` replaced the global with its own fallback. #1142 (Part 13) moved the tests off the settings fuel API, so the copy and the API can now go.
- **#1147:** the four fuel thresholds validated each other one at a time, so the result depended on assignment order. Applying (20, 15, 10, 5) from the defaults clamped `high` to 51. Their unit (percent of `max_fuel`) wasn't documented anywhere.
- **#1148:** `GameSettingsResource` repeated the validation of `SpeedResource` and `FuelResource` with about 150 lines of setters, backing fields and signals that nothing used. Copying the speed limits one at a time had the same order problem as the thresholds.
- **#1194:** the browser workflow's Refactor Suite shard matched no files since July, wrote an empty report and passed, because `allow_empty` was set.

The four issues touch the same files in a fixed order (#1143 → #1147 → #1148), so they ship as one PR with one commit per issue. #1194 is a small workflow fix and goes first, so this PR's own runs skip the empty shard.

---

## Key Changes

### 1. Every browser shard must run tests (#1194)

- **Matrix:** removed the Refactor Suite entry from `browser_test.yml`. Only Core Web Flows (`tests/*_test.py`) and CI & Security (`tests/ci/*.py`) remain.
- **Empty shards fail:** removed the `allow_empty` switch. A shard whose pattern matches no files still writes a zero-test `junit.xml` (so the Test Results Summary shows which shard broke) and then exits with an error. The report upload step already had `if: always()`, so the empty report is still uploaded.
- **Docstring:** `test_pr_path_filters.py` no longer names `tests/refactor/` as a Playwright suite.

### 2. Live fuel lives only on `FuelResource` (#1143)

- **`GameSettingsResource`:** removed `current_fuel`, `_current_fuel`, the `fuel_depleted` signal, `refuel()`, `_init()`, and the `max_fuel` setter's clamp of `current_fuel`. `max_fuel` keeps its minimum of 1.0 and its `setting_changed` signal.
- **`player.gd`:**
  - No longer copies fuel into the settings at spawn or on every `fuel_changed`.
  - No longer listens to `setting_changed` (`_on_setting_changed()` and its connect and disconnect are gone).
  - A player without `Globals.settings` still logs an error and uses a fallback `GameSettingsResource`, but keeps it local instead of assigning it to `Globals.settings`.
- **Nothing replaces the removed code.** The HUD, parallax and web telemetry already read `FuelResource` directly (`hud.gd`, `parallax_manager.gd`, `web_telemetry_adapter.gd`). Refueling goes through `fuel_resource.current_fuel` or `refuel()`, and `_on_fuel_changed()` still reignites the engine.
- **`globals.gd`:** updated the `persisted_schema` filter comment. Its example no longer mentions `current_fuel`.

### 3. Fuel thresholds validated as a group (#1147)

- **`FuelResource.set_thresholds(high, medium, low, no_fuel) -> bool`:** checks the whole set first: `0 <= no_fuel < low < medium < high <= 100`, each at least 1 apart, with NaN and infinity rejected. A valid set applies exactly as written, whatever the current values are. An invalid set logs a warning (`push_warning`), returns `false`, and changes nothing.
- **Single-value setters:** kept for the Inspector and existing callers, still clamping against their neighbours, and now also limited to 0–100.
- **Backing fields:** the four thresholds store their values in private fields, so `set_thresholds()` can write a validated set without going through the order-dependent clamps.
- **`player.gd`:** one `set_thresholds()` call replaces the four one-by-one copies.
- **Units:** both resources document the thresholds as percentages of `max_fuel`, matching how the HUD compares them.

### 4. Settings hold plain tuning values (#1148)

- **`GameSettingsResource`:** 11 fields are plain exports with the same names and defaults: `max_speed`, `min_speed`, `lateral_speed`, `acceleration`, `deceleration`, `high_yellow_fraction`, `low_yellow_fraction`, and the four fuel thresholds. Their setters, backing fields and `setting_changed` emissions are gone. The `setting_changed` doc lists every plain property. The file went from 296 lines on `main` to 140.
- **`SpeedResource.set_speed_limits(new_min, new_max) -> bool`:** requires `0 <= new_min <= new_max`, `new_max >= 1`, both finite. A valid pair applies exactly, then `current_speed` is clamped into the new range. An invalid pair logs a warning, returns `false`, and changes nothing. `max_speed` and `min_speed` now use backing fields, like the fuel thresholds.
- **`player.gd`:**
  - One `set_speed_limits()` call replaces the two one-by-one copies.
  - The min speed applied at spawn is cached in `_fueled_min_speed`. `_set_speed()` restores it after a flameout instead of re-reading `_settings.min_speed`.
- **Validation lives in one place.** Invalid tuning in the settings reaches the player as written. `SpeedResource` and `FuelResource` reject or clamp it.

---

## Design Decisions

- **One PR, one commit per issue.** #1143, #1147 and #1148 must land in that order and change the same lines in `game_settings_resource.gd` and `player.gd`. Separate PRs would have meant rebasing those lines twice. Each commit stays reviewable on its own.
- **#1194 rides along as the first commit.** It's a workflow-only change, and putting it first meant this PR's own runs skipped the empty shard.
- **Stale `current_fuel` keys are kept as found.** A `current_fuel` key in an old `settings.cfg` loads without an error, and a save leaves it untouched. Globals never writes a value for it. This follows the existing rule of keeping unknown keys (`future_option`). Removing the key would be a save-format change, which #1143 rules out.
- **Group setters write backing fields.** Going through the single setters would still clamp against the old neighbours, which is the bug itself. Validating the whole set first and then writing the fields directly makes the result independent of the current values.
- **`push_warning()` in the resources.** `FuelResource` and `SpeedResource` don't depend on `Globals`, so the rejection warning stays engine-level. `player.gd` ignores the return values with `@warning_ignore("return_value_discarded")`, because the resource already logs the warning.
- **Settings setters were left alone in #1147.** #1148 removes them, so #1147 only documented their units. Between the two commits, a settings value like `high = 150` was rejected at spawn.
- **Restore the applied `min_speed`, not the settings value.** Re-reading `_settings.min_speed` after a flameout would undo a rejected pair: with min 900 and max 800 the player keeps 95/713, but the first refuel would pull 900 back in, and the setter would clamp it to 713. The trade-off is that a mid-flight change to `Globals.settings.min_speed` waits for the next spawn. Nothing in the game or the tests changes it mid-flight.
- **Speed fractions keep the one-by-one copy.** `high_yellow_fraction` is copied before `low_yellow_fraction`, and `low` clamps to `high`, so every valid pair already applies exactly.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, using the same commands as `gut_tests.yml` and `gdunit4_tests.yml` (gdUnit4-coverage stripped, `xvfb-run`). `gdformat --check`, `gdlint`, `yamllint`, `ruff` and `tests/ci` as in CI.

- **Totals after each commit:**

| State                    | GUT tests | GUT asserts | gdUnit4 cases |
|--------------------------|-----------|-------------|---------------|
| `main` (`1a8f329`)       | 876       | 10,152      | 155           |
| + #1194                  | 876       | 10,152      | 155           |
| + #1143                  | 881       | 10,187      | 155           |
| + #1147                  | 893       | 10,265      | 155           |
| + #1148                  | 909       | 10,388      | 157           |

- **Test counts per changed file (`main` → this PR):**

| File                                     | Framework | Cases                       |
|------------------------------------------|-----------|-----------------------------|
| `test_browser_test_workflow.py`          | pytest    | 15 → 20 (6 collected cases) |
| `test_pr_path_filters.py`                | pytest    | 22 → 22                     |
| `test_player_fuel_logic.gd`              | GUT       | 6 → 9                       |
| `test_player_lifecycle.gd`               | GUT       | 2 → 3                       |
| `test_parallax_manager.gd`               | GUT       | 16 → 16                     |
| `test_game_settings_resource.gd`         | GUT       | 9 → 13                      |
| `test_globals_settings_serialization.gd` | GUT       | 26 → 27                     |
| `test_fuel_resource.gd`                  | GUT       | 9 → 17                      |
| `test_hud.gd`                            | GUT       | 10 → 12                     |
| `test_speed_resource.gd`                 | GUT       | 6 → 14                      |
| `test_player_tuning_copy.gd` (new)       | GUT       | 0 → 6                       |
| `test_player.gd`                         | gdUnit4   | 16 → 18                     |
| `test_difficulty.gd`                     | gdUnit4   | 1 → 1                       |
| `test_difficulty_integration.gd`         | gdUnit4   | 1 → 1                       |

- **No test cases removed.** The four `BRIDGE TEST (#1143)` spots from Part 13 were rewritten to confirm the bridge is gone: two tests in `test_player_fuel_logic.gd`, the bridge checks in `test_player_lifecycle.gd`, and the marked part of `test_parallax_manager.gd`.
- **Mutation checks:** for each issue, the old behaviour was put back in a scratch copy, and the new tests had to fail:
  - **#1194:** the old workflow fails 3 of the new workflow tests.
  - **#1143:** the old production code fails 9 new or rewritten tests across 5 suites.
  - **#1147:** the one-by-one player copy, `set_thresholds()` through the single setters, no 0/100 limits, and no range check are each caught.
  - **#1148:** the one-by-one speed copy, restoring from `settings.min_speed`, `set_speed_limits()` through the setters, and the old validating settings file are each caught.
- **`tests/ci`:** 1117 passed locally. `test_salt_injection.py::test_injection_readonly_file` fails in the sandbox and on unchanged `main`, because it runs as root, which ignores read-only permissions. It passes in CI.
- **PR pipeline:**
  - **Earlier commits:** all jobs passed on `77563a26`, `58f05e1f` and `5323d5a7`, including both browser shards and the benchmark.
  - **Latest commit (`161b2b70`):** lint, GUT, gdUnit4 and the CI & Security shard passed. _Core Web Flows and the benchmark: fill in from the final run._
- **Browser shard counts (#1194):** Core Web Flows ran 65 tests, as in run #408. CI & Security ran 1118, up from 1112. The difference is exactly the 6 new regression tests in `tests/ci/test_browser_test_workflow.py`. Nothing was lost by removing the shard.
- **Benchmark:**
  - **Settings saves in 60 s:** 0 on desktop and web.
  - **Desktop:** flat on every run.
  - **Web, `58f05e1f`:** flagged ⚠️ on frame interval p95 (+53%, 56.7 ms). The next commit, `5323d5a7`, contains the same #1143 code and measured 44.7 ms (+20%). The last 7 web runs on `main` ranged from 32.8 to 45.5 ms p95 and from 64 to 1494 dropped frames, so this reads as runner noise. #1143 only removes work (a `setting_changed` emission per fuel tick). _Confirm with the `161b2b70` table._

---

## Known Limitations / Follow-ups

- **Manual web check (#1143):** HUD fuel warnings, the engine stopping on flameout, and the background stopping still need a check on the web build (locally, or on itch.io after merge).
- **Stale `current_fuel` keys** stay in old save files. Removing them on save would need its own issue, since it changes the save format.
- **#1150** depends on #1146, #1139 and #1141 (Region 5), so #617 can't close until Region 5 is done. Either move #1150 under #620 or accept that #617 stays open.
- **#617 is still a sub-issue of the closed #616.**
- **`workspace/run_pipeline.sh`** still passes `--ignore=tests/refactor`. It does nothing now that the folder is gone and can be cleaned up later.

---

## Reviewer's Guide

### File-Level Changes

| Change                       | Details                                                                                                                                                                                               | Files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
|------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Browser shards (#1194).      | <ul><li>Refactor Suite shard and `allow_empty` removed.</li><li>Empty shards write a zero-test report, then fail.</li></ul>                                                                           | `.github/workflows/browser_test.yml`<br/>`tests/ci/test_browser_test_workflow.py`<br/>`tests/ci/test_pr_path_filters.py`                                                                                                                                                                                                                                                                                                                                                                           |
| Fuel ownership (#1143).      | <ul><li>Settings fuel API and the player's two-way copy removed.</li><li>Fallback settings stay local.</li></ul>                                                                                      | `scripts/resources/game_settings_resource.gd`<br/>`scripts/entities/player.gd`<br/>`scripts/core/globals.gd`                                                                                                                                                                                                                                                                                                                                                                                       |
| Fuel thresholds (#1147).     | <ul><li>`FuelResource.set_thresholds()` validates a set atomically.</li><li>Single setters limited to 0–100.</li><li>Percentage unit documented.</li></ul>                                            | `scripts/resources/fuel_resource.gd`<br/>`scripts/entities/player.gd`<br/>`scripts/resources/game_settings_resource.gd`                                                                                                                                                                                                                                                                                                                                                                            |
| Plain tuning values (#1148). | <ul><li>11 settings fields are plain exports.</li><li>`SpeedResource.set_speed_limits()` copies the limits as a pair.</li><li>Zero-fuel path restores the applied `min_speed`.</li></ul>              | `scripts/resources/game_settings_resource.gd`<br/>`scripts/resources/speed_resource.gd`<br/>`scripts/entities/player.gd`                                                                                                                                                                                                                                                                                                                                                                           |
| Tests.                       | <ul><li>Bridge tests rewritten to confirm the bridge is gone.</li><li>New tests for group setters, HUD percentages, plain settings fields and player copies.</li><li>No test cases removed.</li></ul> | `test/gut/test_player_fuel_logic.gd`<br/>`test/gut/test_player_lifecycle.gd`<br/>`test/gut/test_parallax_manager.gd`<br/>`test/gut/test_game_settings_resource.gd`<br/>`test/gut/test_globals_settings_serialization.gd`<br/>`test/gut/test_fuel_resource.gd`<br/>`test/gut/test_hud.gd`<br/>`test/gut/test_speed_resource.gd`<br/>`test/gut/test_player_tuning_copy.gd`<br/>`test/gdunit4/test_player.gd`<br/>`test/gdunit4/test_difficulty.gd`<br/>`test/gdunit4/test_difficulty_integration.gd` |
| Milestone note.              | <ul><li>This note.</li></ul>                                                                                                                                                                          | `files/docs/milestones/27/Part_14_Remove_runtime_fuel_state_validate_tuning_as_groups_&_require_tests_in_every_browser_shard.md`                                                                                                                                                                                                                                                                                                                                                                   |

### Assessment against linked issues

| Issue                                                   | Objective                                                                      | Addressed | Explanation                                                                                                                                 |
|---------------------------------------------------------|--------------------------------------------------------------------------------|-----------|---------------------------------------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1194> | Only Core Web Flows and CI & Security run                                      | ✅         | Refactor Suite entry removed; a test checks the matrix.                                                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1194> | An empty shard writes a zero-test report and fails                             | ✅         | Tested by running the real step script with a stubbed `pytest`.                                                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1194> | Core Web Flows and CI & Security keep their test counts (65 and 1112)          | ✅         | 65 and 1118. The extra 6 are the new regression tests; nothing was lost.                                                                    |
| <https://github.com/ikostan/SkyLockAssault/issues/1194> | yamllint, actionlint and `tests/ci` pass                                       | ✅         | YAML Lint job (yamllint + actionlint) and the CI & Security shard passed.                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1143> | Runtime fuel state and the `max_fuel` clamp removed from the settings resource | ✅         | `current_fuel`, `fuel_depleted`, `refuel()` and the clamp are gone; a test checks they don't exist.                                         |
| <https://github.com/ikostan/SkyLockAssault/issues/1143> | Player bridge removed; fallback settings stay local                            | ✅         | Tests check that settings writes can't change fuel, fuel changes can't touch the settings, and the fallback leaves `Globals.settings` null. |
| <https://github.com/ikostan/SkyLockAssault/issues/1143> | A stale `current_fuel` key loads cleanly and isn't written                     | ✅         | It loads without an error and a save leaves it as found (see Design Decisions).                                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1143> | A full fuel run emits no `setting_changed`                                     | ✅         | Drained through the real timer callback, then refuelled; no emission.                                                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1143> | HUD, engine and background checked on the web build                            | ⏳         | Manual check still to do.                                                                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1147> | `set_thresholds()` applies a set all at once or not at all                     | ✅         | Lowered, raised, boundary and 8 invalid sets tested.                                                                                        |
| <https://github.com/ikostan/SkyLockAssault/issues/1147> | Thresholds can't go outside 0–100                                              | ✅         | Single setters and `set_thresholds()` both enforce it.                                                                                      |
| <https://github.com/ikostan/SkyLockAssault/issues/1147> | `player.gd` copies thresholds with one call                                    | ✅         | Tested with lowered and raised custom sets.                                                                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1147> | The percentage unit is documented; default HUD behaviour unchanged             | ✅         | Documented in both resources. Existing HUD tests pass unchanged; new tests cover `max_fuel = 200` and custom bands.                         |
| <https://github.com/ikostan/SkyLockAssault/issues/1148> | The listed fields are plain exports with the same names and defaults           | ✅         | Tested for all 11 fields.                                                                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1148> | Validation exists only in `SpeedResource` and `FuelResource`                   | ✅         | Settings store values as written; new tests show the entity resources reject or clamp invalid values.                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1148> | `max_fuel` behaves as before                                                   | ✅         | Minimum of 1.0, `setting_changed`, save and reload all tested.                                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1148> | Gameplay with the default values is unchanged                                  | ✅         | All existing GUT, gdUnit4 and Playwright tests pass unchanged.                                                                              |
| All four                                                | GUT, gdUnit4, Playwright and lint pass, with no test cases removed             | ⏳         | Passed on the earlier commits; confirm on the final run.                                                                                    |
| All four                                                | The PR's milestone note is added                                               | ✅         | This note.                                                                                                                                  |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1143, #1147, #1148 and #1194 and set their scope and order.
- Chose to bundle the four issues into one PR and to put #1194 in it.
- Asked for the changes as fully updated files, applied them, committed one commit per issue, and opened the PR.
- Reviewed the bot findings and asked for this note.
- Commits:
  - `77563a26` Require tests in every browser shard
  - `58f05e1f` Move live fuel state out of settings
  - `5323d5a7` Apply fuel thresholds atomically
  - `161b2b70` Apply tuning settings atomically at player spawn

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Planning**
    - Mapped the open Milestone 27 work after #1142 and recommended #1143 as the next task.
    - Grouped Region 2 into PRs by shared files and ordering (#1143 + #1147 + #1148, #1144 + #1145), and flagged that #1150 can't land before Region 5.
  - **Verification**
    - Ran GUT, gdUnit4, `tests/ci`, `gdformat`, `gdlint`, `yamllint` and `ruff` locally after each issue, with the CI commands.
    - Mutation-tested each issue by putting the old behaviour back and confirming the new tests fail.
  - **Review**
    - Checked Sourcery's test count finding against the CI logs (65 and 1118, the extra 6 being the new tests) and the web benchmark ⚠️ against `main`'s run history.
- **@sourcery-ai**
  - Flagged that `tests/refactor/` changes would no longer run; resolved, since the folder is empty and the empty-shard guard now covers it.
  - Flagged that the zero-test report wouldn't be uploaded after a failing shard; resolved, since the upload step already runs with `if: always()`.
  - Flagged the CI & Security count rising from 1112 to 1118; the extra tests are the new #1194 regression tests.
  - Posted a linked-issues assessment and a summary of the PR in its description.
- **@coderabbitai**
  - Flagged that the PR description was still the template and didn't mention the GDScript changes.
  - Reported Ruff S603/S607 and an ast-grep command-injection note on the workflow test harness. They don't apply: the script comes from the repo's own workflow file, not outside input.
  - Posted a summary of the PR in its description.
- **@qodo-code-review**
  - Reviews paused for this account; no findings.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
