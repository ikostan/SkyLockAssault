<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Fix unbound menu navigation keys & the 0.0s profiling baseline

---

## PR #1161 Summary

**Title:** Bug menu navigation keys become unbound and gamepad flight loses the left stick from the second launch  
**PR:** [#1161](https://github.com/ikostan/SkyLockAssault/pull/1161)  
**Branch:** `bug-menu-navigation-keys-become-unbound-and-gamepad-flight-loses-the-left-stick-from-the-second-launch` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1160 – [BUG] Menu navigation keys become "Unbound" and gamepad flight loses the left stick from the second launch](https://github.com/ikostan/SkyLockAssault/issues/1160)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** bug, testing, menu, GUT, QA

## PR #1159 Summary

**Title:** Bug test profiling baseline reports a duration of 00s after testsci runs  
**PR:** [#1159](https://github.com/ikostan/SkyLockAssault/pull/1159)  
**Branch:** `bug-test-profiling-baseline-reports-a-duration-of-00s-after-testsci-runs` → `main`  
**Author:** @ikostan  
**Merged:** 2026-11-06, merge commit `af54f91`  
**Resolves:**

- [#1157 – [BUG] Test Profiling Baseline reports a duration of 0.0s after tests/ci runs](https://github.com/ikostan/SkyLockAssault/issues/1157)

**Related:** [#776](https://github.com/ikostan/SkyLockAssault/issues/776), [#1155](https://github.com/ikostan/SkyLockAssault/pull/1155), [#1156](https://github.com/ikostan/SkyLockAssault/issues/1156)  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** bug, testing, CI/CD, python, QA

### Purpose

Two bugs that broke a value only after the first run:

- **#1161:** from the second launch, the menu arrow keys showed "Unbound" in Key Mapping and the Unbound Controls dialog appeared on start. The same load also stripped the left stick from Speed Up, Move Left and Move Right. Any client that saves `user://settings.cfg` was affected.
- **#1159:** after a full `tests/ci/` run, the "Test Profiling Baseline (#776)" section printed `Total Suite Duration : 0.0s`, and `artifacts/metrics_baseline.json` saved a 0.0 duration and a fake timestamp.

---

## Key Changes

### 1. Root cause of #1160

Three issues combined:

- **`key:0`:** Godot's built-in `ui_*` key events set `keycode` but leave `physical_keycode` at 0. `serialize_event()` wrote only `physical_keycode`, so the arrows, Enter and Tab were saved as `key:0`, which the next load rejects.
- **Shared inputs:** `project.godot` gave the flight actions the arrow keys as hidden second bindings, and the built-in `ui_*` actions also carried the left stick. The strict cross-action conflict check then stripped one side on load: the menu lost its arrows and flight lost the stick.
- **Two default layouts:** `project.godot` and `Settings.DEFAULT_*` disagreed (speed on the left or right stick, next weapon on a stick flick or Y, pause on X or Start).

### 2. One default layout (`input_defaults.gd`, `project.godot`)

- **New `scripts/core/input_defaults.gd`:** holds the layout, the two conflict groups and one event builder (`make_event`). It replaces three copies of the same code in `settings.gd`. `Settings.DEFAULT_KEYBOARD`, `DEFAULT_GAMEPAD`, `GAMEPLAY_ACTIONS` and `MENU_ACTIONS` stay as aliases, so callers don't change.
- **`project.godot` `[input]`:** one binding per action per device, matching the layout. The `ui_*` actions are now defined explicitly, which removes Godot's built-in keycode-only and left-stick events.

| Action                        | Keyboard        | Gamepad                 |
|-------------------------------|-----------------|-------------------------|
| Speed up / down               | W / S           | Left Stick Up / Down    |
| Move left / right             | A / D           | Left Stick Left / Right |
| Fire                          | Space           | A                       |
| Next weapon                   | Q               | Y                       |
| Pause                         | Esc             | Start                   |
| Menu up / down / left / right | Arrows          | D-pad                   |
| Accept                        | Enter           | A                       |
| Menu next / prev              | Tab / Shift+Tab | RB / LB                 |

### 3. `settings.gd`

- **Conflict groups:** `get_conflicting_actions()` checks only within the gameplay group or the menu group, with pause in both. A can now be both Fire and Accept.
- **Saved keys:** a key with `physical_keycode` set is saved as `key:`. A keycode-only special key (arrows, Enter, Tab, Esc, F-keys, numpad) is also saved as `key:`, because its logical and physical codes are the same. A keycode-only printable key is saved as `lkey:` and restored as a logical keycode, so it keeps following the keyboard layout.
- **`_key_identity()`:** a new helper that `serialize_event()` and `events_match()` share, so matching and saving agree.
- **Backfill:** `_add_missing_defaults()` counts both `key:` and `lkey:` entries as saved keyboard bindings.
- **Migration flag:** `_migrate_input_layout_v3()` always flags a save, so its run-once flag is persisted even when no binding changed.

### 4. One-time v3 migration (`input_layout_migration.gd`)

- **New `scripts/core/input_layout_migration.gd`:** repairs saves broken by the old defaults, once.
- **Removes:** only the 8 known legacy extras (arrow keys on the 4 flight actions, left-stick axes on the 4 `ui_*` actions), and only while the action has another binding on that device.
- **Restores:** only the 8 slots the bug stripped (menu arrows on keyboard, flight stick on gamepad), only if the action still has a binding on its other device, and only if the default is free in its group.
- **Keeps:** every other binding, extra binding and unbind, including fully unbound actions.

### 5. #1159: session state isolation (`tests/ci/`)

- **Cause:** `_invoke_sessionfinish` in `test_metrics_baseline.py` wrote fake values into the real `conftest._SESSION_STATE`, and nothing restored them. The tests pass `start_time: 0.0`, which `conftest.py` treats as "no start time".
- **Fix:** `isolate_profiling_globals` now replaces `_SESSION_STATE` with a test-local value for each test. `conftest.py`'s timing logic doesn't change.
- **Log spacing (`conftest.py`):** `pytest_runtest_logstart` no longer prints a leading blank line for tests under `tests/ci/`. Other tests keep it.
- **`.gitignore`:** adds `pytest-ci.txt`, and fixes the missing newline at the end of the file.

### 6. Tests

- **#1161, `test_input_layout_menu_gameplay_split.gd` (new, 33 test functions):** defaults and `project.godot` agreement, the agreed layout, conflict groups, serialization (`key:`, `lkey:`, matching rules), save and reload, and 13 migration cases.
- **#1161, five existing GUT files:** expected values changed from the old right stick to the left stick. No cases were removed.
- **#1159, `test_metrics_baseline.py`:** 1 regression test by @claude and 3 by CodeRabbit. They cover isolation, restoring the state after each test, the exported and printed duration, and the log spacing.

### 7. Docs (#1159)

- **`Local_CI_Pipeline_for_Godot_Project_using_Docker.md`:** new "Running the CI Helper Tests (`tests/ci`)" section with the PowerShell `docker run` command. It explains why both `safe.directory` entries are needed.
- **`README.md`:** links that section from the testing list.

---

## Design Decisions

- **Menus and flight may share inputs.** They never read input at the same time, so the conflict rule now applies only within a group. This lets A be Fire and Accept, and the arrows and left stick each belong to one group.
- **Pause is in both groups.** It is pressed during flight and also closes menus, so nothing else in either group may use Esc or Start.
- **One binding per action per device.** The Key Mapping screen shows and edits one binding per device, so a hidden second binding couldn't be seen or changed.
- **Classic arcade layout.** The whole plane flies on the left stick so the right thumb stays on the face buttons. Pause moved from X to Start, so it isn't pressed by accident next to A. Speed down moved from X to S, for WASD.
- **The migration targets only what the bug left behind.** A generic trim or restore could not tell a stale binding from a remap, or a bug-stripped slot from a deliberate unbind. In the 8 bug slots the two still look the same, so a deliberate unbind there is restored. All 8 are critical actions, so leaving one unbound would show the Unbound Controls dialog anyway.
- **`lkey:` instead of converting to physical.** Godot has no API from a logical key to its physical position, so a logical key has to be stored as logical.
- **Special keys stay `key:`.** Old saves only contain `key:`, and they load unchanged.
- **New files keep `settings.gd` under gdlint's limits.** The fix pushed it over the 1000-line and 20-public-method limits. Moving the layout and migration out brings it to about 970 lines.
- **#1159 fixes the test, not `conftest.py`.** The timing code was correct, and 0 still means "no start time".

---

## Review Decisions

| PR    | Reviewer   | Finding                                                                          | Decision                                                                                                                                                                                |
|-------|------------|----------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| #1161 | Sourcery   | Valid bindings are permanently lost (Medium)                                     | **Fixed in `c20fc09`:** a remap appends the new key, so "keep the first" kept the stale one. The trim now removes only the known legacy extras.                                         |
| #1161 | Sourcery   | Unbound controls become bound again (Medium)                                     | **Fixed in `c20fc09`:** restore is limited to the bug-stripped slots. Unbinds elsewhere and fully unbound actions are kept.                                                             |
| #1161 | Sourcery   | Key bindings change after reload (Medium)                                        | **Fixed in `cf619ab`:** valid for printable keys on layouts like AZERTY. Logical keys are saved as `lkey:`.                                                                             |
| #1161 | Sourcery   | Migration runs again on launch (Medium)                                          | **Fixed in `cf619ab`:** confirmed on a fresh profile, where a launch with no changes wrote no config at all.                                                                            |
| #1161 | Sourcery   | Default backfill masks binding loss (Medium)                                     | **Fixed in `3e9bf57`:** confirmed by breaking the code on purpose. With the `key:0` serializer restored, REG-01 and MIG-01 still passed.                                                |
| #1161 | CodeRabbit | Count `lkey:` entries as saved keyboard bindings (Minor)                         | **Fixed in `f063ee3`:** a corrupt `lkey:` entry was treated as an explicit unbind.                                                                                                      |
| #1161 | CodeRabbit | PR description incomplete (pre-merge check)                                      | **Open:** the description is still the template. This note can fill it.                                                                                                                 |
| #1159 | CodeRabbit | Assert `conftest._SESSION_STATE is _REAL_SESSION_STATE` after teardown (Nitpick) | **Not applied:** the fixture replaces the state during the test on purpose, so that assertion would always fail. `test_isolation_restores_session_state_after_test` covers restoration. |
| #1159 | CodeRabbit | Generated 3 test cases (`6242d46`)                                               | **Kept.**                                                                                                                                                                               |
| #1159 | CodeRabbit | PR description incomplete (pre-merge check)                                      | **Not addressed** before the merge.                                                                                                                                                     |
| #1159 | Sourcery   | Linked-issue check: `conftest.py` changed for log spacing                        | **Accepted:** the #1157 criterion said `conftest.py` doesn't change. The timing logic didn't; only the log spacing did.                                                                 |
| #1159 | DeepSource | Formatting                                                                       | **Fixed by autofix in `921db22`** (Black and isort).                                                                                                                                    |

---

## Verification

### #1161

- **Reproduced first:** headless on Godot 4.7.1. After one save and relaunch, `ui_up` had no keyboard binding and `speed_up` had lost its stick.
- **Repaired end to end:** a broken save made by the old code loads with the menu arrows and flight stick back, and stays fixed on relaunch.
- **Locally on the final code:** GUT 867/867 and gdUnit4 155/155 pass. gdlint and gdformat are clean on `./scripts`.
- **Tests catch the bugs:** breaking the code on purpose made the tests fail each time: the old conflict rule or the `key:0` serializer, a do-nothing restore, the old trim and restore, the old flag handling, the old key format, and the missing `lkey:` check.
- **Migration flag:** after one launch on a fresh profile, the saved config holds the flag. Before the fix, no config was written.
- **PR CI on `f063ee3`:** to confirm before the merge.
- **Not verified:** the web client. It uses the same `Settings` code, so it is very likely affected and fixed the same way.

### #1159

- **CI:** all 20 checks passed on the merged head.
- **Before the fix:** a full `tests/ci/` run printed `0.0s` against pytest's 26.94 s, and the JSON held `2026-08-06T03:00:00Z`.
- **After the fix:** the run printed 35.35 s against pytest's 35.35 s, and the JSON held a real duration and timestamp.
- **Regression test:** it fails without the fixture change.
- **Local failure, not from this PR:** `test_injection_readonly_file` fails when tests run as root, as in the sandbox. It passes in CI.

---

## Known Limitations / Follow-ups

- **Players' own saves:** the migration repairs only what the bug broke. A save that still holds the old choices (X for speed down, B for accept, X for pause) keeps them until the player presses Reset for each device on the Key Mapping screen.
- **v2 migration flag:** `_migrate_legacy_unbound_states()` only saves when something changed, so its flag can fail to stick the same way. It predates #1161 and needs its own issue.
- **Mixed key matching:** a logical and a physical printable key never count as the same key, so a conflict between them isn't reported. Neither form is created by the game itself today.
- **PR descriptions:** both PRs kept the unfilled template, which CodeRabbit flagged both times.
- **GUT editor panel:** the panel keeps its own settings, separate from `.gutconfig.json`. With no directories set, it refuses to run. Load `res://.gutconfig.json` in the panel.
- **Reviews:** Qodo reviews were paused, so Qodo reviewed neither PR.

---

## Reviewer's Guide

### File-Level Changes

| Change                   | Details                                                                                                                                             | Files                                                                                                                                                                                                                                                                                                      |
|--------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Default layout.          | <ul><li>Layout, conflict groups and `make_event`.</li><li>One binding per action per device in `[input]`.</li></ul>                                 | `scripts/core/input_defaults.gd`<br/>`project.godot`                                                                                                                                                                                                                                                       |
| Settings.                | <ul><li>Scoped conflicts.</li><li>`key:` / `lkey:` and `_key_identity`.</li><li>`lkey:` in backfill.</li><li>Migration flag always saved.</li></ul> | `scripts/core/settings.gd`                                                                                                                                                                                                                                                                                 |
| v3 migration.            | <ul><li>Removes 8 legacy extras.</li><li>Restores 8 bug-stripped slots.</li></ul>                                                                   | `scripts/core/input_layout_migration.gd`                                                                                                                                                                                                                                                                   |
| GUT tests.               | <ul><li>New suite, 33 test functions.</li><li>Right stick to left stick in 5 files, no cases removed.</li></ul>                                     | `test/gut/test_input_layout_menu_gameplay_split.gd`<br/>`test/gut/test_combined_multi_manager_loads.gd`<br/>`test/gut/test_deserialize_event_key_tokens.gd`<br/>`test/gut/test_error_edge_cases.gd`<br/>`test/gut/test_key_mapping_menu_device_aware.gd`<br/>`test/gut/test_settings_unbound_scenarios.gd` |
| Session state isolation. | <ul><li>Test-local `_SESSION_STATE`.</li><li>4 new tests.</li></ul>                                                                                 | `tests/ci/test_metrics_baseline.py`                                                                                                                                                                                                                                                                        |
| Log spacing.             | <ul><li>No leading blank line for `tests/ci/`.</li></ul>                                                                                            | `tests/conftest.py`                                                                                                                                                                                                                                                                                        |
| Docs and ignore list.    | <ul><li>Running `tests/ci` in Docker on Windows.</li><li>`pytest-ci.txt` ignored.</li></ul>                                                         | `files/docs/Local_CI_Pipeline_for_Godot_Project_using_Docker.md`<br/>`README.md`<br/>`.gitignore`                                                                                                                                                                                                          |

### Assessment against linked issues

| Issue                                                   | Objective                                                                     | Addressed | Explanation                                                                            |
|---------------------------------------------------------|-------------------------------------------------------------------------------|-----------|----------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1160> | Menu arrows stay bound after save and reload, with no Unbound Controls dialog | ✅         | REG-01 checks the saved entries and the reloaded bindings.                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1160> | Speed Up, Move Left and Move Right keep the left stick                        | ✅         | REG-01, MIG-01 and MIG-13.                                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1160> | One default layout in `project.godot` and `Settings`                          | ✅         | LAYOUT-01 to LAYOUT-03 check the agreement and the layout.                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1160> | Conflicts scoped to gameplay and menu groups, pause in both                   | ✅         | GROUP-01 to GROUP-05.                                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1160> | Keycode-only events are no longer saved as `key:0`                            | ✅         | SER-01 to SER-08, with `lkey:` for logical printable keys.                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1160> | One-time v3 migration repairs broken saves                                    | ✅         | MIG-01 to MIG-13. The flag is persisted even with no changes (MIG-12).                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1160> | Regression tests for save and reload, conflict groups and migration           | ✅         | New suite, and 5 files updated with no cases removed.                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1157> | A full `tests/ci/` run prints a duration close to pytest's total              | ✅         | 35.35 s against 35.35 s.                                                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1157> | `metrics_baseline.json` holds the real duration and timestamp                 | ✅         | Checked after a full run.                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1157> | A regression test fails without the fixture change                            | ✅         | `test_invoke_sessionfinish_leaves_real_session_state_unchanged`.                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1157> | `conftest.py` doesn't change; 0 still means "no start time"                   | 🟡        | The timing logic is unchanged. `conftest.py` changed for the separate log-spacing fix. |
| <https://github.com/ikostan/SkyLockAssault/issues/1157> | `pytest tests/ci/` passes, no test cases removed                              | ✅         | 20 checks passed in CI.                                                                |

---

## Contributors

### Human contribution (@ikostan)

- Found the "Unbound" menu keys on the PC client and reported them with screenshots.
- Checked the input map in the editor and questioned the diagnosis, which led to the explanation of how the two configs combine.
- Chose the arcade layout and S for speed down, and filed #1160 from the draft.
- Brought back every Sourcery and CodeRabbit finding for assessment, and applied all the code to the PR branch.
- For #1159, skipped the log spacing for `tests/ci/`, documented running the CI helper tests in Docker on Windows, answered CodeRabbit's nitpick, and merged.
- Commits by @ikostan:
  - #1161:
    - `56e75e5` Test menu and gameplay input layout split
    - `ce0281c` Split gameplay and menu input defaults
    - `c20fc09` Repair only known legacy input bindings
    - `cf619ab` Preserve logical keys in saved bindings
    - `3e9bf57` Strengthen input layout regression tests
    - `f063ee3` Recognize legacy keys during input migration
  - #1159:
    - `19d42a3` Isolate metrics baseline session state
    - `d1415ef` Update .gitignore
    - `7d9871e` Skip log spacing for CI tests
    - `2d6c6a6` Document Docker-based CI tests on Windows
    - `418235f` Document CI helper test instructions

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **#1160 diagnosis**
    - Reproduced the bug headless on Godot 4.7.1, and traced it to `key:0`, the shared inputs and the two default layouts.
    - Found that the same load also stripped the gamepad left stick from flight.
    - Proposed the arcade layout and the gameplay and menu conflict groups.
  - **#1161 code and tests**
    - Broke the code on purpose for every fix to show the tests catch it.
  - **Review findings**
    - Checked each Sourcery and CodeRabbit finding against the code and confirmed all six, then wrote the fixes and the thread replies.
  - **#1159**
    - Traced the 0.0 s duration to `_invoke_sessionfinish` leaking into the real `_SESSION_STATE`, drafted and filed #1157, and wrote the fixture fix and its regression test.

- **@sourcery-ai**
  - Posted the PR summaries, Reviewer's Guides and linked-issue checks on both PRs.
  - #1161: posted 5 inline comments, all fixed.
  - #1159: flagged the `conftest.py` change against the #1157 criterion.

- **@coderabbitai**
  - #1161: posted a walkthrough, one outside-diff comment (fixed) and the pre-merge checks.
  - #1159: posted one nitpick (answered without a change) and generated 3 test cases.
  - Commits:
    - `6242d46` Add regression tests for metrics session isolation, duration reporting, and CI log spacing

- **@deepsource-io**
  - Python and JavaScript analysis: overall grade A on both PRs.
  - Commits:
    - `921db22` style: format code with Black and isort

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
