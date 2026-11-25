<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Splash startup scene and Esc cancels key remapping

---

## PR Summary

**Title:** Fix splash startup scene request and Esc cancelling key remapping  
**PR:** TBD  
**Branch:** `fix/splash-startup-and-esc-cancel-remap` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1167 – [BUG] Splash screen never requests its startup scene, so every launch runs the error path](https://github.com/ikostan/SkyLockAssault/issues/1167)
- [#1168 – [BUG] Esc can't cancel key remapping; remove unused remap label tables](https://github.com/ikostan/SkyLockAssault/issues/1168)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `bug`, `testing`

### Purpose

The first two sub-issues of #621 (Region 6: Presentation & View Layers), fixed in one PR to save time. They touch different files, so they can be reviewed separately:

| Issue | Bug                                                                    | Fixed by        |
|-------|------------------------------------------------------------------------|-----------------|
| #1167 | The splash screen never requests a load, so every launch logs 2 ERRORs | Key Change 1    |
| #1168 | Esc gets bound while remapping; four unused label tables               | Key Changes 2-3 |

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
- Polling and fetching use `resolved_next_scene` instead of `Globals.next_scene`.
- The router routes to `resolved_next_scene` and still clears `Globals.next_scene`. The empty-path branch can't happen any more; it stays as a defensive WARNING ("Empty startup scene - returning to main menu.").
- The request and both scene changes go through three small methods, `_request_threaded_load()`, `_change_scene_to_file()` and `_change_scene_to_packed()`, so tests can stub them.

### 2. Esc cancels keyboard remapping (`input_remap_button.gd`, #1168)

- New `cancel_listening()`: restores the button text, sets `button_pressed` and `listening` to false, and marks the input handled. It doesn't touch `InputMap` and doesn't save.
- `_input()` checks for Esc before any binding logic (`_consume_escape()`), only while listening on keyboard. Gamepad listening ignores Esc, as before.
- Esc is matched on `physical_keycode` (what binding uses) or `keycode`, so a synthetic event that only sets the logical key also cancels. Echoes and releases don't cancel.
- **The Controls menu stays open and no cancel sound plays:** the event is marked handled in `_input()`, so later `_input()` handlers (`UIManager`'s cancel sound) and `_unhandled_input()` (the pause toggle) never see it.
- **A pending conflict isn't affected:** while the Key Mapping conflict dialog waits for this button, Esc is left to the dialog and the button keeps listening.
- To stay under `gdlint`'s `max-returns`, the two device checks in `_input()` moved into `_is_event_for_current_device()`.

### 3. Prompt text and unused tables (#1168)

- The keyboard prompt is now "Press a key (Esc to cancel)": `GameSettingsResource.remap_prompt_keyboard` and the fallback text in `_on_pressed()`. The prompt isn't saved to the settings file, so no migration is needed.
- `KEY_LABELS`, `JOY_BUTTON_LABELS`, `JOY_AXIS_BASE_LABELS` and `JOY_AXIS_LABELS` and their doc lines are gone. The test comments that mentioned them now point to `InputEventCodec.get_event_label()` (the issue says `Settings.get_event_label()`; the code uses `InputEventCodec`).

### 4. Tests

**No test case was removed.**

- **Updated:**
  - `../../../../test/gut/test_splash_screen.gd`: `test_poll_resource_backend_handles_invalid_resource_type` points `resolved_next_scene` at the non-PackedScene; `test_transition_gating_mechanics_fire_on_full_completion` routes through `resolved_next_scene` and also checks that `Globals.next_scene` is cleared. `after_each()` fetches any threaded load left by `_ready()`.
  - `../../../../test/gut/test_globals_resource.gd`: the new keyboard prompt, and that it mentions Esc.
  - Comments only: `test_input_remap_button_device_aware.gd`, `test_key_mapping_menu.gd`, `../../../../test/gdunit4/test_input_remap_button.gd`.
- **`../../../../test/gut/test_splash_screen.gd` (+6):** a partial double with stubbed scene changes runs the real splash screen:
  - The boot state (`next_scene = ""`) requests and loads the main menu with no ERROR log (the confirm-first case).
  - A set `next_scene` is requested and loaded instead.
  - A failed request sets `load_failed`, pushes the bar to 100 and reaches the direct-load fallback.
  - A missing scene (request accepted, load fails) takes the existing failure path and the same fallback.
  - Progress from the real loader never goes down and reaches 100 through a finished load.
  - The defensive empty-path branch logs a WARNING, not an ERROR, and loads the main menu.
- **New `../../../../test/gut/test_input_remap_esc_cancel.gd` (15 tests):**
  - Esc stops keyboard listening, keeps the binding, saves nothing and restores the text (the confirm-first case); also with `physical_keycode` only and with Shift held. An Esc release or Esc while not listening does nothing.
  - `cancel_listening()` marks the input handled.
  - A real Esc event (`Input.parse_input_event`) never reaches a probe node's later `_input()` or `_unhandled_input()`; a control case shows the probe does see an unhandled Esc.
  - In the real Key Mapping menu, Esc cancels, the binding and text stay, and the menu stays open.
  - Esc while listening on gamepad does nothing.
  - Other keys still bind; a pure modifier is still ignored.
  - Clicking the button again still cancels.
  - A pending conflict for this button isn't affected; one for another button doesn't block the cancel.
  - Pause can't be bound to Esc through remapping, and Reset to defaults restores Esc.
- **Playwright:**
  - `../../../../tests/no_error_logs_test.py`: a normal load must log none of the splash ERROR lines.
  - `../../../../tests/fps_counter_e2e_test.py` and `tests/difficulty_integration_test.py`: "empty next_scene" and "loading failed or invalid" removed from their ignore lists. They were only there to hide this bug.

---

## Design Decisions

- **One PR for two sub-issues,** to save time. Each is a small, separate change (different scripts and test files), so either can still be reverted alone.
- **Stubbable scene-change methods** instead of really changing scenes in tests. A real change to the main menu would replace the test scene and start its music.
- **Esc while a conflict is pending is left to the dialog.** At runtime the exclusive dialog already gets the key first; the check only makes sure the button can never bind Esc or open a second dialog if it is called anyway.
- **`keycode` is also accepted for Esc,** so the cancel doesn't depend on how the event was created. Binding still uses `physical_keycode`.
- **The Playwright check targets the splash messages only,** not every ERROR line, because other tests still ignore startup encryption warnings that this PR doesn't touch.

---

## Verification

Run locally with Godot 4.7.1-stable and GUT 9.7.1, set up as `gut_tests.yml` does. `gdlint ./scripts` and `gdformat --check ./scripts` as in CI.

| State              | GUT scripts | GUT tests | GUT asserts |
|--------------------|-------------|-----------|-------------|
| `main` (`00cb22c`) | 120         | 1,263     | -           |
| This branch        | 121         | 1,284     | 16,144      |

- **Full GUT suite locally:** 1,284/1,284.
- **GDScript lint and format:** pass.
- **Restoring the old behavior:**

| Change                                                        | Fails                                             |
|---------------------------------------------------------------|---------------------------------------------------|
| Old `input_remap_button.gd` (Esc binds)                       | 9 of 15 tests in `test_input_remap_esc_cancel.gd` |
| No request in `_ready()`; poll and route `Globals.next_scene` | The 6 new tests in `test_splash_screen.gd`        |

- **Not run locally:** gdUnit4 (only comments changed), Playwright, the benchmark and the manual itch.io checks.

---

## Known Limitations / Follow-ups

- **Manual itch.io checks still to do:**
  - The splash bar advances smoothly, and the main menu opens as before.
  - In Controls, start a keyboard remap and press Esc: the binding stays and the menu stays open. Remapping to another key still works.
- **Benchmark:** the scenario is unchanged; check the PR table.
- **#1102 also changes `input_remap_button.gd`:** it is closed, so no rebase is expected from it.
- **Next in #621:** the loader merge sub-task (after #1167, as the issue asks).

---

## Reviewer's Guide

### File-Level Changes

| Change          | Details                                                                                                                     | Files                                                                                                                                                                                                                                                                           |
|-----------------|-----------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Splash screen.  | <ul><li>Resolve and request the startup scene in `_ready()`.</li><li>Poll, fetch and route `resolved_next_scene`.</li></ul> | `../../../../scripts/ui/screens/splash_screen.gd`                                                                                                                                                                                                                               |
| Esc cancel.     | <ul><li>`cancel_listening()`; Esc checked before binding.</li><li>Unused label tables removed.</li></ul>                    | `../../../../scripts/ui/components/input_remap_button.gd`                                                                                                                                                                                                                       |
| Prompt.         | <ul><li>"Press a key (Esc to cancel)".</li></ul>                                                                            | `../../../../scripts/resources/game_settings_resource.gd`                                                                                                                                                                                                                       |
| GUT tests.      | <ul><li>New Esc suite; 6 new splash tests; updated cases and comments.</li></ul>                                            | `../../../../test/gut/test_input_remap_esc_cancel.gd`<br/>`test/gut/test_splash_screen.gd`<br/>`test/gut/test_globals_resource.gd`<br/>`test/gut/test_input_remap_button_device_aware.gd`<br/>`test/gut/test_key_mapping_menu.gd`<br/>`test/gdunit4/test_input_remap_button.gd` |
| Playwright.     | <ul><li>Splash ERROR check on load; ignore entries removed.</li></ul>                                                       | `../../../../tests/no_error_logs_test.py`<br/>`tests/fps_counter_e2e_test.py`<br/>`tests/difficulty_integration_test.py`                                                                                                                                                        |
| Milestone note. | <ul><li>This note.</li></ul>                                                                                                | `files/docs/milestones/27/Part_28_Splash_startup_scene_&_Esc_cancels_key_remapping.md`                                                                                                                                                                                          |

### Assessment against linked issues

| Issue                                                   | Objective                                                                    | Addressed | Explanation                                |
|---------------------------------------------------------|------------------------------------------------------------------------------|-----------|--------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1167> | The confirm-first result is recorded on the PR                               | ✅        | Confirm-first results.                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1167> | The splash screen requests and loads its target, defaulting to the main menu | ✅        | Key Change 1; new splash tests.            |
| <https://github.com/ikostan/SkyLockAssault/issues/1167> | A normal launch logs no errors                                               | ✅        | Boot-state GUT test; Playwright check.     |
| <https://github.com/ikostan/SkyLockAssault/issues/1168> | The confirm-first result is recorded on the PR                               | ✅        | Confirm-first results.                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1168> | Esc cancels keyboard remapping without changing or saving anything           | ✅        | Key Change 2; Esc suite.                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1168> | The four unused label tables are gone                                        | ✅        | Key Change 3.                              |
| Both                                                    | All GUT, gdUnit4, Playwright and lint jobs pass; no cases removed            | ⏳        | GUT and lint pass locally; CI not run yet. |
| Both                                                    | The PR's milestone note is added under `..`                                  | ✅        | This note.                                 |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1167 and #1168 from the #621 (Region 6) review, with the confirm-first steps and the fixes.
- Decided (2026-11-09) that Esc cancels keyboard remapping.
- Asked to fix both bugs in one PR to save time.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Reproduced both bugs on `main` with GUT before changing code.
  - **Fixes**
    - Implemented both fixes, and pushed the splash bar to 100 on a failed request so the fallback can't hang.
    - Kept Esc away from a pending conflict dialog, and accepted `keycode` as well as `physical_keycode`.
  - **Tests**
    - Wrote the new Esc suite and the six splash tests, updated the existing cases and comments, and tightened three Playwright tests.
  - **Verification**
    - Ran the full GUT suite, `gdlint` and `gdformat`.
    - Restored the old behavior of each fix to confirm the new tests catch it.
    - Wrote this note.
