<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Skip freed menu-stack entries in every Back and cleanup path

---

## PR Summary

**Title:** Skip freed entries on `Globals.hidden_menus` in every Back and cleanup path  
**PR:** _(to be opened)_  
**Branch:** `fix-freed-hidden-menus-pop-1211` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1211 – [BUG] Freed entries on Globals.hidden_menus abort menu Back and cleanup (typed pop_back)](https://github.com/ikostan/SkyLockAssault/issues/1211)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `bug`

### Purpose

A menu freed while it is still on `Globals.hidden_menus` leaves a stale entry. Nine places popped the stack with `var prev_menu: Node = …hidden_menus.pop_back()`. Assigning a freed instance to a typed `Node` variable raises `SCRIPT ERROR: Trying to assign invalid previously freed instance.` and stops the function on that line, so the `is_instance_valid(prev_menu)` check below it never ran. In Audio Settings the player was stuck on the menu; in Options, `options_open` and `options_instance` stayed set.

PR #1210 fixed the same pattern in Key Mapping, and `SettingsMenuBase` was already correct, each with its own copy of the loop. This PR moves that loop into one `Globals` helper and uses it in all eleven places.

---

## Confirm-first results

The new GUT suite was run against unchanged `main` (`0f28ac9`) with only the test file added. All 14 cases fail:

| Cases           | Result on `main`                                                                                                                                                           |
|-----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| HMS-01 – HMS-04 | Fail: `Globals.pop_hidden_menu()` doesn't exist yet.                                                                                                                       |
| HMS-05 – HMS-14 | Fail on `Trying to assign invalid previously freed instance.`, and their state checks fail too (live menu not shown, Audio / Advanced not freed, Options state not reset). |

So every one of the nine places in the issue stops as described. Line numbers had moved since `7b46ec4`; the code was the same.

---

## Key Changes

### 1. `Globals.pop_hidden_menu() -> Node` (`globals.gd`)

- Pops into a `Variant`, discards freed entries (logged at DEBUG, as before) and returns the first live menu, or `null` if the stack is empty or held only freed entries.
- Only pops. Showing the menu, focus and the web overlays stay with each caller, since they differ per menu.

### 2. Callers

Each `if not …hidden_menus.is_empty(): var prev_menu: Node = …pop_back(); if is_instance_valid(prev_menu):` became `var prev_menu: Node = Globals.pop_hidden_menu(); if prev_menu != null:`. The bodies are unchanged apart from one less level of indentation.

| File                    | Function                                                                                                |
|-------------------------|---------------------------------------------------------------------------------------------------------|
| `options_menu.gd`       | `_teardown()`                                                                                           |
| `audio_settings.gd`     | `_on_back_button_pressed()`, `_on_tree_exited()`                                                        |
| `advanced_settings.gd`  | `_on_advanced_back_button_pressed()`, `_on_tree_exited()`                                               |
| `globals.gd`            | `load_key_mapping()` (failure), `_on_options_exited_unexpectedly()`, `load_options()` (2 failure paths) |
| `key_mapping.gd`        | Back: its own loop from #1210 replaced by the helper                                                    |
| `settings_menu_base.gd` | `_restore_previous_menu()`: its own loop replaced by the helper                                         |

`gdformat` joined one `log_message()` call in `advanced_settings.gd` onto one line after the dedent.

### 3. Tests

- **New `test/gut/test_hidden_menu_stack.gd` (14 cases):**
  - **Helper:** empty stack (HMS-01), only freed entries (HMS-02), freed entry above a live menu (HMS-03: returns the live one, keeps the menu below, shows nothing), live menu on top (HMS-04).
  - **One case per place in the issue,** each with a freed entry above a live menu: Options Back (HMS-05), Audio Back (HMS-06), Audio unexpected exit (HMS-08), Advanced Back (HMS-09), Advanced unexpected exit (HMS-10), `load_key_mapping()` rollback (HMS-11), `_on_options_exited_unexpectedly()` (HMS-12), `load_options()` with no scene (HMS-13) and with a scene that fails to instantiate (HMS-14). Each checks the live menu is shown, the stack is empty, and the function finished (menu freed, Options state reset, `options_open` reset).
  - **Audio Back with only freed entries (HMS-07):** the menu still closes. See Design Decisions.
- Key Mapping and `SettingsMenuBase` keep their existing freed-entry tests, which now go through the helper: KM-WEB-10, SMB-09 and SMB-14.

---

## Design Decisions

- **Skip, don't stop.** The rule from `SettingsMenuBase` and Key Mapping after #1210: a freed entry is discarded and the next live menu is shown. A freed entry means that menu is gone; the one below it is still the right screen to go back to.
- **The helper returns the menu and does nothing else.** Every caller restores something different (focus target, DOM overlays, log text), so only the popping is shared.
- **Audio Back with only freed entries now uses the empty-stack fallback.** Before, that case had a non-empty stack, so the `else:` branch (`change_scene_to_file(Globals.previous_scene)`) never ran; with the fix the function would finish with no menu shown. Now `prev_menu == null` covers both "empty" and "only freed entries", so Back goes to `previous_scene` in both. HMS-07 blanks `previous_scene`, as the other Audio tests do, and checks that the menu still closes.
- **One file for the new tests.** The nine places are in four scripts, and the tests share the same freed-entry setup, so they live in one `HMS` suite instead of being spread over the per-menu suites.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 v6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdformat --check` and `gdlint` as in CI.

| State                    | GUT tests | GUT asserts | gdUnit4 test cases |
|--------------------------|-----------|-------------|--------------------|
| `main` (`0f28ac9`, base) | 1,031     | 11,143      | 164                |
| This PR                  | 1,045     | 11,185      | 164                |

- **No test cases removed.**
- **Full GUT suite:** 1,045/1,045.
- **gdUnit4 suite:** 164/164, including `test_options_teardown.gd`, `test_load_options_reentrancy.gd`, `test_audio_settings.gd` and `test_audio_unexpected_exit.gd`, which drive the changed paths.
- **New suite on `main`:** 14/14 fail (see Confirm-first results).
- **No typed `pop_back()` left:** `grep -rn "hidden_menus.pop_back" scripts/` finds only the one inside `pop_hidden_menu()`, which pops into a `Variant`.
- **GDScript lint and format:** `gdlint scripts` and `gdformat --check scripts` pass.

---

## Known Limitations / Follow-ups

- **The `Globals` rollback paths pop an entry they may not have pushed.** `load_key_mapping()` and `load_options()` push `menu_to_hide` only when it is valid, but their failure paths always pop. With a valid `menu_to_hide`, the pop takes back that entry, which can't be freed in between, so the freed-entry case only happens when nothing was pushed. Then the rollback pops (and shows) a menu that belongs to whatever was open before. This predates the PR and isn't changed here; HMS-11, HMS-13 and HMS-14 test the issue's rule as written.
- **Advanced Back uses `get_node()` on the restored menu** for `Panel/OptionsVBoxContainer/AdvancedSettingsButton`, which logs an error if the restored menu isn't Options. Advanced Settings is only opened from Options, so it doesn't happen in the game; HMS-09 gives its live menu that path.

---

## Reviewer's Guide

### File-Level Changes

| Change           | Details                                                                                      | Files                                                                                                                   |
|------------------|----------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| Helper.          | <ul><li>`pop_hidden_menu()`: skips freed entries, returns the live menu or `null`.</li></ul> | `scripts/core/globals.gd`                                                                                               |
| Globals callers. | <ul><li>4 recovery paths use the helper.</li></ul>                                           | `scripts/core/globals.gd`                                                                                               |
| Menu callers.    | <ul><li>5 Back / exit paths use the helper.</li></ul>                                        | `scripts/ui/menus/options_menu.gd`<br/>`scripts/ui/menus/audio_settings.gd`<br/>`scripts/ui/menus/advanced_settings.gd` |
| Existing loops.  | <ul><li>Replaced by the helper.</li></ul>                                                    | `scripts/ui/menus/key_mapping.gd`<br/>`scripts/ui/menus/settings_menu_base.gd`                                          |
| Tests.           | <ul><li>New GUT suite, 14 cases.</li></ul>                                                   | `test/gut/test_hidden_menu_stack.gd`<br/>`test/gut/test_hidden_menu_stack.gd.uid`                                       |
| Milestone note.  | <ul><li>This note.</li></ul>                                                                 | `files/docs/milestones/27/Part_19_Skip_freed_menu-stack_entries_in_every_Back_and_cleanup_path.md`                      |

### Assessment against linked issues

| Issue                                                   | Objective                                                          | Addressed | Explanation                                                    |
|---------------------------------------------------------|--------------------------------------------------------------------|-----------|----------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | One GUT test per place with a freed entry on top                   | ✅         | HMS-05, HMS-06, HMS-08 – HMS-14.                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | Helper tests: empty, only freed, freed above valid                 | ✅         | HMS-01 – HMS-03 (and HMS-04, live on top).                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | Existing suites pass, no cases dropped (GUT and gdUnit4)           | ✅         | 1,045/1,045 GUT, 164/164 gdUnit4 locally.                      |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | No `var … : Node = …hidden_menus.pop_back()` left in `scripts/`    | ✅         | Only `pop_hidden_menu()` pops, into a `Variant`.               |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | Helper also used in `key_mapping.gd` and `settings_menu_base.gd`   | ✅         | One copy instead of eleven.                                    |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | All tests pass in CI                                               | ⏳         | Pass locally; PR run to confirm.                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | Milestone note added                                               | ✅         | This note.                                                     |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1211 from the freed-entry failure found in #1210, listed the nine places and set the fix and test scope.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked the nine places against `main` after #1210 merged, and ran the new suite on unchanged code: all 14 cases fail.
  - **Fix**
    - Added `Globals.pop_hidden_menu()` and switched all eleven places to it.
    - Wrote the 14 GUT cases in `test_hidden_menu_stack.gd`.
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, `gdformat` and `gdlint` locally.
    - Wrote this note.
