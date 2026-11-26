<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Small UI cleanup in the main, pause and Options menus, and the HUD

---

## PR Summary

**Title:** Clean up menus and HUD signal handling  
**PR:** [#1273](https://github.com/ikostan/SkyLockAssault/pull/1273)  
**Branch:** `small-ui-cleanup-in-the-main-pause-and-options-menus-and-the-hud` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1169 – [FEATURE] Small UI cleanup in the main, pause, and Options menus, and the HUD](https://github.com/ikostan/SkyLockAssault/issues/1169)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `testing`, `menu`, `refactoring`

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

**No test case was removed.** CodeRabbit added 4 more tests during review (`93e16be`); they are listed with the file they went into and marked *(CodeRabbit)*.

- **Updated:** `test/gdunit4/test_pause_menu.gd` PM-07 called `menu._input()` directly with a left and a right click. It now checks that `pause_menu.gd` defines no `_input()`. The pause toggle checks in the same case are unchanged.
- **`test/gut/test_quit_game_confirm_dialog_sfx.gd` (+7, 9 in total):**
  - `Globals` has no global button sound handler; `SfxManager` does.
  - A plain `ConfirmationDialog` gets no global sound connection on its OK and Cancel buttons.
  - The quit dialog's OK and Cancel buttons have none either.
  - Pressing OK plays one `ui_accept`; pressing Cancel plays one `ui_cancel` and no `ui_accept`, counted after deferred calls.
  - Setting the dialog up again keeps one `confirmed` and one `canceled` connection, and leaves it hidden.
  - *(CodeRabbit)* Setting up an open dialog hides it; after reopening, Cancel and OK each play exactly one sound, on the Menu bus.
- **`test/gut/test_hud.gd` (+10, 28 in total):**
  - Speed blinking starts at the low threshold and at maximum speed and stops in the normal range, with no HUD handler on `speed_low` or `speed_maxed` (the confirm-first case).
  - Maximum speed is inside the warning band even with `high_yellow_fraction` set to 1.0.
  - The HUD doesn't connect to `speed_low` or `speed_maxed`.
  - Initial wiring makes exactly two HUD connections per resource.
  - `setup_hud()` with the same resources disconnects nothing.
  - `setup_hud()` with one new resource (speed, fuel or weapon, parameterized) disconnects only the replaced one.
  - Leaving the tree removes every HUD connection from all three resources.
  - Freeing a second HUD leaves no connections to it, and the first HUD still reacts. The second HUD is added with `add_child_autofree()` as a fallback, and is still freed explicitly (review fix, `67ab118`).
  - *(CodeRabbit)* After the speed resource is replaced, changing only `high_yellow_fraction` starts and stops the warning and its timer.
  - *(CodeRabbit)* Replacing a HUD's resources, or removing it from the tree, leaves a second HUD on the same resources working, and the first HUD ignores them (parameterized: replace, exit tree).
- **New `test/gut/test_menu_click_logging.gd` (4 tests):**
  - A left click pushed through the viewport with the pause menu or Options open logs no "Clicked at" line (captured with `OS.add_logger()`, at DEBUG level), and neither script defines `_input()`.
  - Neither the main nor the pause menu keeps an `options_menu` scene.
  - On `main`, these three failed, so they do catch the old logging and the preloads.
  - *(CodeRabbit)* From the main menu and from the pause menu (parameterized), the Options button opens the configured Options scene and hides the caller, and Back frees Options and shows the caller again.

---

## Design Decisions

- **`null` means "leave connected"** in `_disconnect_resources()`, as the issue suggested. `setup_hud()` decides which resources are replaced, and the helper only disconnects.
- **The `is_connected()` guards stay** in the helper, so it's safe to call on a resource that was never connected or was already disconnected.
- **PM-07 checks the script's own method list,** not `has_method("_input")`. `_input` is a virtual method of `Node`, so `has_method()` doesn't say whether the script still overrides it.
- **The click test pushes real input through the viewport** and captures the log, so it proves the behavior ("a click logs nothing"), not only that a function is gone.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 v6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdlint ./scripts` and `gdformat --check ./scripts` as in CI.

| State                                  | GUT scripts | GUT tests | GUT asserts |
|----------------------------------------|-------------|-----------|-------------|
| `main` (`4f35da2`)                     | 121         | 1,290     | 16,176      |
| First commit (`46c6a85`)               | 122         | 1,307     | 16,237      |
| PR head, after review (`eac69b1`)      | 122         | 1,311     | 16,277      |

- **Full GUT suite locally on `eac69b1`:** 1,311/1,311.
- **Full gdUnit4 suite locally on `46c6a85`:** 170/170 (27 suites), including PM-07 and the `check_speed_warning()` cases in `test_player.gd`. The review commits changed only GUT tests.
- **GDScript lint and format:** pass.
- **Before the code change,** the new tests that describe the new code failed as expected (7 failures: the HUD speed connections, the click logs and the preloads), and all confirm-first cases passed.
- **Breaking the code on purpose** (in a local copy, undone after each run) shows CodeRabbit's tests catch real regressions:

| Change                                                                  | Fails                                                                                                           |
|-------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| `setup_hud()` no longer connects `thresholds_changed`                   | `test_speed_warning_tracks_threshold_changes_after_speed_replacement` and 4 more HUD tests                      |
| `_disconnect_resources()` disconnects every listener, not only this HUD | `test_hud_cleanup_preserves_shared_resource_subscribers` (both cases), `test_freeing_hud_leaves_no_connections` |
| The main menu's Options button isn't connected                          | `test_options_button_round_trip_without_a_menu_local_scene` (main)                                              |
| The quit dialog's OK button is also connected to the global click sound | `test_reopened_quit_dialog_plays_one_sound_after_repeated_setup` and 2 more quit dialog tests                   |

  Removing the pause menu's Options `connect()` line doesn't fail the pause case, and that is correct: `pause_menu.tscn` also connects the button.

- **CI on `eac69b1`:** GDScript lint and format, Markdown lint, GUT, gdUnit4 and the web build pass. The browser test shards and the benchmark were still running when this note was updated.
- **Not run locally:** Playwright (`back_flow_test.py`, `telemetry_and_hold_test.py`, `no_error_logs_test.py`), the benchmark and the manual itch.io checks.

---

## Review

| Reviewer   | Finding                                                                                           | Outcome                                                                                                                                                             |
|------------|---------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| CodeRabbit | Nitpick: register the second HUD in `test_freeing_hud_leaves_no_connections` for autofree         | Fixed (`67ab118`). The stated reason was corrected in the reply: a failed GUT assertion doesn't stop the test; the real risk is a script error before `hud.free()`. |
| CodeRabbit | Generated unit tests (`93e16be`): 4 tests in 3 files                                              | All kept. Each one fails when the code it covers is broken (see Verification).                                                                                      |
| Sourcery   | No code review (weekly review budget used up); posted a reviewer's guide and a linked-issue check | Linked issues: 11 of 14 #1169 requirements met; the other 3 (Playwright, benchmark, itch.io checks) are runtime checks to do by hand.                               |
| DeepSource | Static analysis (Python, JavaScript)                                                              | No issues reported.                                                                                                                                                 |
| Qodo       | Reviews paused for this account                                                                   | No review.                                                                                                                                                          |

---

## Known Limitations / Follow-ups

- **Manual itch.io checks still to do:**
  - Quit plays one confirm or cancel sound.
  - The speed label blinks at low and maximum speed as before.
- **Benchmark:** the scenario is unchanged; check the PR table.
- **CodeRabbit's Options round-trip test sits in `test_menu_click_logging.gd`,** a file named for click logging. It fits there loosely (it checks the menus work without the removed preloads); moving it to a navigation suite is optional.
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
| GUT tests.      | <ul><li>7 quit dialog tests; 10 HUD tests; new click logging suite (4). 4 of the 21 are from CodeRabbit.</li></ul>                  | `test/gut/test_quit_game_confirm_dialog_sfx.gd`<br/>`test/gut/test_hud.gd`<br/>`test/gut/test_menu_click_logging.gd` |
| gdUnit4 tests.  | <ul><li>PM-07 checks there's no `_input()` instead of calling it.</li></ul>                                                         | `test/gdunit4/test_pause_menu.gd`                                                                                    |
| Milestone note. | <ul><li>This note.</li></ul>                                                                                                        | `files/docs/milestones/27/Part_29_Small_UI_cleanup_in_the_main_pause_&_Options_menus_&_the_HUD.md`                   |

### Assessment against linked issues

| Issue                                                   | Objective                                                         | Addressed | Explanation                                                                        |
|---------------------------------------------------------|-------------------------------------------------------------------|-----------|------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | The confirm-first results are recorded on the PR                  | ✅        | Confirm-first results.                                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | The five items are removed or simplified as described             | ✅        | Key Changes 1-5.                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | Menu sounds, Options access and HUD warnings behave as before     | ✅        | GUT and gdUnit4 suites; manual checks still to do.                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | All GUT, gdUnit4, Playwright and lint jobs pass; no cases removed | ⏳        | Lint, GUT and gdUnit4 pass in CI; Playwright and the benchmark were still running. |
| <https://github.com/ikostan/SkyLockAssault/issues/1169> | The PR's milestone note is added under `files/docs/milestones/`   | ✅        | This note.                                                                         |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1169 from the #621 (Region 6) review, with the confirm-first steps and the proposed changes.
- Picked #1169 as the next PR.
- Opened PR #1273 (`46c6a85`).
- Requested CodeRabbit's generated unit tests (`93e16be`).
- Applied CodeRabbit's autofree fix (`67ab118`) and replied to the review.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked both points on `main` with GUT before changing code, and traced why the speed blink can't depend on `speed_low` or `speed_maxed` (signal order and the clamped `high_yellow_fraction`).
    - Found the moved line numbers in `main_menu.gd`.
  - **Tests**
    - Wrote the 17 new GUT tests and rewrote PM-07 without removing it.
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, `gdlint` and `gdformat` before and after the change.
    - Found that `test_weapon_slot_cooldown.gd` never runs in either test job.
    - Wrote this note.
  - **Review**
    - Checked CodeRabbit's nitpick against how GUT assertions work, found its stated reason was wrong but the fix still useful, and wrote the fix and the reply.
    - Reviewed CodeRabbit's 4 generated tests: ran them, checked they leave no state behind (full suite 1,311/1,311), and broke the code each one covers to confirm it fails.
    - Reviewed PR #1273 and updated this note.
- **@coderabbitai**
  - Reviewed the PR: 1 nitpick, fixed (`67ab118`).
  - Generated 4 unit tests (`93e16be`): threshold changes after a speed swap, shared resource listeners, the Options round trip, and the reopened quit dialog.
- **@sourcery-ai**
  - Posted a reviewer's guide and a linked-issue check (11 of 14 requirements met, 3 to check by hand). No code review: the weekly review budget was used up.
- **@deepsource-io**
  - Static analysis (Python, JavaScript): no issues.
