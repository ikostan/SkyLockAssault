<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Splash startup scene and Esc cancels key remapping

---

## PR Summary

**Title:** Fix splash startup and Esc remap cancel  
**PR:** [#1258](https://github.com/ikostan/SkyLockAssault/pull/1258)  
**Branch:** `splash-screen-never-requests-its-startup-scene-so-every-launch-runs-the-error-path` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1167 – [BUG] Splash screen never requests its startup scene, so every launch runs the error path](https://github.com/ikostan/SkyLockAssault/issues/1167)
- [#1168 – [BUG] Esc can't cancel key remapping; remove unused remap label tables](https://github.com/ikostan/SkyLockAssault/issues/1168)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `bug`

### Purpose

The first two sub-issues of #621 (Region 6: Presentation & View Layers), fixed in one PR to save time. They touch different files, so they can be reviewed separately:

| Issue | Bug                                                                    | Fixed by        |
|-------|------------------------------------------------------------------------|-----------------|
| #1167 | The splash screen never requests a load, so every launch logs 2 ERRORs | Key Change 1    |
| #1168 | Esc gets bound while remapping; four unused label tables               | Key Changes 2-3 |

The PR also carries two changes that aren't part of either bug (Key Changes 5 and 6): the Release Drafter PR trigger and the new `Dev_Automation_Plan.md`.

---

## Confirm-first results

Both bugs were confirmed against `main` (`00cb22c`) before any code changed, with throwaway GUT cases (the permanent versions are in Key Change 4):

- **#1167, confirmed.** With `Globals.next_scene = ""` (the boot state), `load_threaded_get_status("res://scenes/main_menu.tscn")` after `_ready()` was `THREAD_LOAD_INVALID_RESOURCE` (nothing requested). The first poll set `load_failed` and `display_target = 100`, and the launch logged both ERRORs:
  - `[ERROR] Loading failed or invalid.`
  - `[ERROR] Empty next_scene - returning to main menu.`
- **#1168, confirmed.** Keyboard listening on an action bound to `A`, then Esc: the action's keyboard binding became `Escape`, the button text `Escape`, and the mappings were saved.
- **Baseline on `main`:** full GUT suite 1,263/1,263 (120 scripts).

---

## Key Changes

### 1. Splash screen requests its startup scene (`splash_screen.gd`, #1167)

- `_ready()` sets `resolved_next_scene` to `Globals.next_scene`, or `DEFAULT_STARTUP_SCENE` when that is empty, and requests it with `ResourceLoader.load_threaded_request()`.
- If the request doesn't return `OK`, it logs an ERROR, sets `load_failed` **and pushes `display_target` to 100**. The issue only asked for `load_failed`, but polling stops once that is set, so without the push the bar never reaches the transition threshold and the screen would hang.
- Polling and fetching use `resolved_next_scene` instead of `Globals.next_scene`, so changing the global after `_ready()` can't redirect the load.
- The router routes to `resolved_next_scene` and still clears `Globals.next_scene`. The empty-path branch can't happen any more; it stays as a defensive WARNING ("Empty startup scene - returning to main menu.").
- The request and both scene changes go through three small methods, `_request_threaded_load()`, `_change_scene_to_file()` and `_change_scene_to_packed()`, so tests can stub them.

### 2. Esc cancels keyboard remapping (`input_remap_button.gd`, #1168)

- New `cancel_listening()`: restores the button text, sets `button_pressed` and `listening` to false, and marks the input handled. It doesn't touch `InputMap` and doesn't save.
- `_input()` checks for Esc before any binding logic (`_consume_escape()`), only while listening on keyboard. Gamepad listening ignores Esc, as before.
- Esc is matched on `physical_keycode` (what binding uses) or `keycode`, so a synthetic event that only sets the logical key also cancels. A release doesn't cancel.
- **A held Esc (echo) is never bound** (review fix): every Esc press is consumed, but only a non-echo press cancels. Before this, an Esc echo skipped the cancel and fell through to the binding code, which bound and saved Esc if listening started while Esc was held.
- **The Controls menu stays open and no cancel sound plays:** the event is marked handled in `_input()`, so later `_input()` handlers (`UIManager`'s cancel sound) and `_unhandled_input()` (the pause toggle) never see it.
- **A pending conflict isn't affected:** while the Key Mapping conflict dialog waits for this button, Esc is left to the dialog and the button keeps listening.
- To stay under `gdlint`'s `max-returns`, the two device checks in `_input()` moved into `_is_event_for_current_device()`.

### 3. Prompt text and unused tables (#1168)

- The keyboard prompt is now "Press a key (Esc to cancel)": `GameSettingsResource.remap_prompt_keyboard` (what players see) and the fallback text in `_on_pressed()` (used only when settings are missing). The prompt isn't saved to the settings file, so no migration is needed.
- `KEY_LABELS`, `JOY_BUTTON_LABELS`, `JOY_AXIS_BASE_LABELS` and `JOY_AXIS_LABELS` and their doc lines are gone. Nothing read them; button text comes from `InputEventCodec.get_event_label()`, and default bindings from `InputDefaults`. The six test comments and assert messages that named them now point to `InputEventCodec.get_event_label()` (the issue says `Settings.get_event_label()`; the code uses `InputEventCodec`).

### 4. Tests

**No test case was removed.**

- **Updated:**
  - `test/gut/test_splash_screen.gd`:
    - `test_poll_resource_backend_handles_invalid_resource_type` points `resolved_next_scene` at the non-PackedScene.
    - `test_transition_gating_mechanics_fire_on_full_completion` fetches the main-menu request from `_ready()` before swapping in the dummy path (review fix: the request leaked into the boot test), routes through `resolved_next_scene` and checks that `Globals.next_scene` is cleared.
    - `after_each()` and `_drain_threaded_load()` fetch any threaded load left by `_ready()`, failed loads included (review fix: Godot keeps a failed request until it is fetched).
  - `test/gut/test_globals_resource.gd`: the new keyboard prompt, and that it mentions Esc.
  - Comments and assert messages only: `test/gut/test_input_remap_button_device_aware.gd`, `test/gut/test_key_mapping_menu.gd`, `test/gdunit4/test_input_remap_button.gd`.
- **`test/gut/test_splash_screen.gd` (+8, 18 in total):** a partial double with stubbed scene changes runs the real splash screen:
  - The boot state (`next_scene = ""`) requests and loads the main menu with no ERROR log (the confirm-first case).
  - A set `next_scene` is requested and loaded instead.
  - A failed request sets `load_failed`, pushes the bar to 100 and reaches the direct-load fallback.
  - A missing scene (request accepted, load fails) takes the existing failure path and the same fallback.
  - Progress from the real loader never goes down and reaches 100 through a finished load.
  - The defensive empty-path branch logs a WARNING, not an ERROR, and loads the main menu.
  - Changing `Globals.next_scene` after `_ready()` doesn't redirect the load (CodeRabbit).
  - A failed default request loads the main menu directly, exactly once (CodeRabbit).
- **New `test/gut/test_input_remap_esc_cancel.gd` (19 tests):**
  - Esc stops keyboard listening, keeps the binding, saves nothing and restores the text (the confirm-first case); also with `physical_keycode` only, `keycode` only (CodeRabbit) and with Shift held. An Esc release or Esc while not listening does nothing.
  - A held Esc (echo) is never bound and doesn't cancel; a real press afterwards still cancels.
  - `cancel_listening()` marks the input handled.
  - A real Esc event (`Input.parse_input_event`) never reaches a probe node's later `_input()` or `_unhandled_input()`; a control case shows the probe does see an unhandled Esc.
  - In the real Key Mapping menu, Esc cancels, the binding and text stay, and the menu stays open. Keyboard mode is selected with `set_pressed_no_signal()` (review fix: pressing the toggle saved the device choice and broke the "nothing saved" check).
  - Esc while listening on gamepad does nothing; gamepad events don't bind or end keyboard listening (CodeRabbit).
  - Other keys still bind; a pure modifier is still ignored.
  - Clicking the button again still cancels.
  - A pending conflict for this button isn't affected; one for another button doesn't block the cancel.
  - Pause can't be bound to Esc through remapping, and Reset to defaults restores Esc.
  - The fallback prompt says Esc cancels when settings are missing (CodeRabbit).
- **New `tests/ci/test_release_drafter_workflow.py`:** `release_drafter_pr.yml` runs only on `opened`, `reopened` and `synchronize`. It finds the workflow from the file's own location (`PROJECT_ROOT`), like the other `tests/ci/` tests, so it works from any folder.

### 5. Release Drafter skips PR edits (`release_drafter_pr.yml`)

- `edited` is removed from the `pull_request` trigger types. Every PR description edit, checkbox ticks included, started a run: 16 runs on this PR in about 4 minutes, 24 each on the two PRs before it.
- The runs added nothing: `release-drafter.yml` has no `autolabeler`, so each run only rebuilt the draft from already-merged PRs. The draft that matters is built by `release_drafter.yml` from the main pipeline.

### 6. Dev automation plan (`files/docs/Dev_Automation_Plan.md`)

- A new plan for the automation work after Milestone 27.6, across Milestones 29–35 (at most 3 automation PRs per milestone):
  - The code-smell report: metrics script, then AI review and weekly read-only reports.
  - API docs: generate and convert, then deploy.
  - The project guides on the same docs site (#162 in two parts).
- Types go into the refactor work, with no bot. Milestone 28 (game dev) gets nothing added. Sentry waits for the JS separation and real players.
- It also covers bot guardrails, scheduling, per-project AI quotas and the open decisions.

---

## Design Decisions

- **One PR for two sub-issues,** to save time. Each is a small, separate change (different scripts and test files), so either can still be reverted alone.
- **Stubbable scene-change methods** instead of really changing scenes in tests. A real change to the main menu would replace the test scene and start its music.
- **Esc while a conflict is pending is left to the dialog.** At runtime the exclusive dialog already gets the key first; the check only makes sure the button can never bind Esc or open a second dialog if it is called anyway.
- **`keycode` is also accepted for Esc,** so the cancel doesn't depend on how the event was created. Binding still uses `physical_keycode`.
- **An Esc echo is swallowed, not used to cancel.** It only happens when Esc was already held before listening started, so it isn't a request to cancel; a fresh press is.
- **Non-standard gamepad buttons stay unnamed.** The removed `JOY_BUTTON_LABELS` table had names for Misc 1, Paddle 1–4 and Touchpad; `InputEventCodec` shows them as "Button 15"–"Button 20", as it already did before this PR. They aren't on standard controllers and no default binds them.
- **No Playwright changes.** The splash ERROR check in `tests/no_error_logs_test.py` and removing the old splash errors from two ignore lists were left out of this PR; the GUT boot-state test covers "no ERROR on a normal boot".

---

## Verification

Run locally on the PR head (`8fc6bba`) with Godot 4.7.1-stable and GUT 9.7.1, set up as `gut_tests.yml` does. `gdlint ./scripts` and `gdformat --check ./scripts` as in CI.

| State               | GUT scripts | GUT tests | GUT asserts |
|---------------------|-------------|-----------|-------------|
| `main` (`00cb22c`)  | 120         | 1,263     | -           |
| This PR (`8fc6bba`) | 121         | 1,290     | 16,161      |

- **Full GUT suite locally:** 1,290/1,290.
- **GDScript lint and format:** pass.
- **`tests/ci/test_release_drafter_workflow.py`:** passes.
- **Restoring the old behavior:**

| Change                                                        | Fails                                                                                  |
|---------------------------------------------------------------|----------------------------------------------------------------------------------------|
| Old `input_remap_button.gd` (Esc binds)                       | 9 of the first 15 tests in `test_input_remap_esc_cancel.gd`                            |
| Esc echo skips the cancel check (before the review fix)       | `test_esc_echo_is_not_bound`                                                           |
| No request in `_ready()`; poll and route `Globals.next_scene` | The first 6 new tests in `test_splash_screen.gd`                                       |
| Esc matched on `physical_keycode` only                        | `test_esc_cancels_with_logical_keycode_only`                                           |
| A keyboard remap button accepts gamepad events                | `test_keyboard_listening_ignores_gamepad_events`                                       |
| Fallback prompt without "(Esc to cancel)"                     | `test_keyboard_fallback_prompt_explains_esc_cancellation`                              |
| Polling follows `Globals.next_scene`                          | `test_startup_load_keeps_original_target_after_global_changes` and 2 more splash tests |
| The router routes `Globals.next_scene`                        | `test_failed_default_request_uses_default_for_direct_load` and 2 more splash tests     |

- **CI on `8fc6bba`:** GUT, gdUnit4, GDScript lint and format, YAML lint, Markdown lint, CI/CD infrastructure tests and DeepSource pass. Browser functional tests and the benchmark were still running when this note was written.
- **Not run locally:** gdUnit4 (only comments changed), Playwright, the benchmark and the manual itch.io checks.

---

## Review

All 10 review threads are resolved.

| Reviewer   | Finding                                                                                | Outcome                                                                                |
|------------|----------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| CodeRabbit | An Esc echo reaches the binding code and gets bound                                    | Fixed (`6d9c131`); confirmed first with `test_esc_echo_is_not_bound`.                  |
| CodeRabbit | Selecting Keyboard in the menu test saves the device choice                            | Fixed (`6d9c131`): `set_pressed_no_signal()`; confirmed with a saved `gamepad` choice. |
| CodeRabbit | The router test leaks the main-menu request into the boot test                         | Fixed (`a602c09`); confirmed the request was still in progress at the boot test.       |
| CodeRabbit | `_drain_threaded_load()` leaves failed requests in the loader                          | Fixed (`8fc6bba`): failed loads are fetched too.                                       |
| CodeRabbit | 4 findings on `Dev_Automation_Plan.md` (schedule, quotas, guide publishing, next step) | Fixed in `8fc6bba`.                                                                    |
| Sourcery   | Only the fallback prompt said Esc cancels                                              | Fixed (`c254168`): `remap_prompt_keyboard` updated.                                    |
| Sourcery   | Test comments still named the removed tables                                           | Fixed (`c428a1a`).                                                                     |

- CodeRabbit also pushed regression tests (`6da221b`): 3 Esc tests, 2 splash tests and the Release Drafter test. All were reviewed and kept; the Release Drafter test was changed to find the workflow through `PROJECT_ROOT` (`9332ee0`), and DeepSource's autofix formatted it with Black (`12c6a92`).

---

## Known Limitations / Follow-ups

- **Manual itch.io checks still to do:**
  - The splash bar advances smoothly, and the main menu opens as before.
  - In Controls, start a keyboard remap and press Esc: the binding stays and the menu stays open. Remapping to another key still works.
- **Playwright still ignores the old splash errors:** `tests/fps_counter_e2e_test.py` and `tests/difficulty_integration_test.py` keep "empty next_scene" and "loading failed or invalid" in their ignore lists, and nothing in the browser tests checks that a normal launch logs no splash errors.
- **A held non-Esc key can still be bound by its echo** (for example, holding Enter after opening a remap button with it). This was already true before this PR.
- **Benchmark:** the scenario is unchanged; check the PR table.
- **Next in #621:** the loader merge sub-task (after #1167, as the issue asks).

---

## Reviewer's Guide

### File-Level Changes

| Change           | Details                                                                                                                      | Files                                                                                                                                                                                                                                                               |
|------------------|------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Splash screen.   | <ul><li>Resolve and request the startup scene in `_ready()`.</li><li>Poll, fetch and route `resolved_next_scene`.</li></ul>  | `scripts/ui/screens/splash_screen.gd`                                                                                                                                                                                                                               |
| Esc cancel.      | <ul><li>`cancel_listening()`; Esc checked before binding; echoes never bound.</li><li>Unused label tables removed.</li></ul> | `scripts/ui/components/input_remap_button.gd`                                                                                                                                                                                                                       |
| Prompt.          | <ul><li>"Press a key (Esc to cancel)".</li></ul>                                                                             | `scripts/resources/game_settings_resource.gd`                                                                                                                                                                                                                       |
| GUT tests.       | <ul><li>New Esc suite (19); 8 new splash tests; updated cases and comments.</li></ul>                                        | `test/gut/test_input_remap_esc_cancel.gd`<br/>`test/gut/test_splash_screen.gd`<br/>`test/gut/test_globals_resource.gd`<br/>`test/gut/test_input_remap_button_device_aware.gd`<br/>`test/gut/test_key_mapping_menu.gd`<br/>`test/gdunit4/test_input_remap_button.gd` |
| Release Drafter. | <ul><li>No run on PR edits; a test pins the trigger types.</li></ul>                                                         | `.github/workflows/release_drafter_pr.yml`<br/>`tests/ci/test_release_drafter_workflow.py`                                                                                                                                                                          |
| Automation plan. | <ul><li>New plan for Milestones 29–35.</li></ul>                                                                             | `files/docs/Dev_Automation_Plan.md`                                                                                                                                                                                                                                 |
| Milestone note.  | <ul><li>This note.</li></ul>                                                                                                 | `files/docs/milestones/27/Part_28_Splash_startup_scene_&_Esc_cancels_key_remapping.md`                                                                                                                                                                              |

### Assessment against linked issues

| Issue                                                   | Objective                                                                    | Addressed | Explanation                                                         |
|---------------------------------------------------------|------------------------------------------------------------------------------|-----------|---------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1167> | The confirm-first result is recorded on the PR                               | ✅        | Confirm-first results.                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1167> | The splash screen requests and loads its target, defaulting to the main menu | ✅        | Key Change 1; new splash tests.                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1167> | A normal launch logs no errors                                               | ✅        | Boot-state GUT test. No Playwright check (see Known Limitations).   |
| <https://github.com/ikostan/SkyLockAssault/issues/1168> | The confirm-first result is recorded on the PR                               | ✅        | Confirm-first results.                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1168> | Esc cancels keyboard remapping without changing or saving anything           | ✅        | Key Change 2; Esc suite.                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1168> | The keyboard prompt says Esc cancels                                         | ✅        | Key Change 3.                                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1168> | The four unused label tables are gone; test comments updated                 | ✅        | Key Change 3.                                                       |
| Both                                                    | All GUT, gdUnit4, Playwright and lint jobs pass; no cases removed            | ⏳        | GUT, gdUnit4 and lint pass in CI; browser tests were still running. |
| Both                                                    | The PR's milestone note is added under `files/docs/milestones/`              | ✅        | This note.                                                          |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1167 and #1168 from the #621 (Region 6) review, with the confirm-first steps and the fixes.
- Decided (2026-11-09) that Esc cancels keyboard remapping.
- Asked to fix both bugs in one PR to save time.
- Applied the review fixes on the PR branch (`6d9c131`, `a602c09`, `c254168`, `8fc6bba`), and fixed CodeRabbit's failed-load finding in `_drain_threaded_load()`.
- Removed the `edited` trigger from the Release Drafter PR workflow (`1a370ec`), and updated its trigger test (`9332ee0`).
- Wrote `Dev_Automation_Plan.md` and revised it after review.
- Kept the Playwright changes out of this PR, and skipped naming non-standard gamepad buttons.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Reproduced both bugs on `main` with GUT before changing code.
  - **Fixes**
    - Implemented both fixes, and pushed the splash bar to 100 on a failed request so the fallback can't hang.
    - Kept Esc away from a pending conflict dialog, and accepted `keycode` as well as `physical_keycode`.
    - Checked that the removed label tables were dead code, and compared every entry against `InputEventCodec` and `InputDefaults`.
  - **Tests**
    - Wrote the new Esc suite and the first six splash tests, and updated the existing cases and comments.
  - **Review**
    - Confirmed each CodeRabbit and Sourcery finding against the code before fixing it: the Esc echo, the menu test saving the device, the leaked main-menu request, the configured prompt and the stale table comments.
    - Wrote the fixes and their tests, and pushed the comment updates (`c428a1a`).
    - Reviewed CodeRabbit's regression tests by breaking each fix to confirm the matching test fails, and found the Release Drafter test's folder-dependent path.
    - Traced the Release Drafter runs to the `edited` trigger and the missing `autolabeler`.
  - **Verification**
    - Ran the full GUT suite, `gdlint` and `gdformat`.
    - Restored the old behavior of each fix to confirm the new tests catch it.
    - Wrote this note and updated it for the final PR.
- **CodeRabbit**
  - Reviewed the PR: 8 findings, all fixed (4 on code and tests, 4 on `Dev_Automation_Plan.md`).
  - Pushed regression tests (`6da221b`): 3 Esc tests, 2 splash tests and the Release Drafter trigger test.
- **Sourcery**
  - Reviewed the PR: 2 findings, both fixed (the configured prompt and the stale table comments).
- **DeepSource**
  - Formatted `tests/ci/test_release_drafter_workflow.py` with Black (`12c6a92`).
