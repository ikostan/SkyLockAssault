<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Skip freed menu-stack entries in every Back and cleanup path

---

## PR Summary

**Title:** Skip freed menus when restoring hidden stack  
**PR:** [#1213](https://github.com/ikostan/SkyLockAssault/pull/1213)  
**Branch:** `bug-freed-entries-on-globalshidden_menus-abort-menu-back-and-cleanup-typed-pop_back` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1211 – [BUG] Freed entries on Globals.hidden_menus abort menu Back and cleanup (typed pop_back)](https://github.com/ikostan/SkyLockAssault/issues/1211)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `bug`

### Purpose

A menu freed while it is still on `Globals.hidden_menus` leaves a stale entry. Nine places popped the stack with `var prev_menu: Node = …hidden_menus.pop_back()`. Assigning a freed instance to a typed `Node` variable raises `SCRIPT ERROR: Trying to assign invalid previously freed instance.` and stops the function on that line, so the `is_instance_valid(prev_menu)` check below it never ran. In Audio Settings the player was stuck on the menu; in Options, `options_open` and `options_instance` stayed set.

PR #1210 fixed the same pattern in Key Mapping, and `SettingsMenuBase` was already correct, each with its own copy of the loop. This PR moves that loop into one `Globals` helper and uses it in the Back and exit paths. The three failed-load rollbacks in `Globals` instead undo only their own push (see Review fixes).

---

## Confirm-first results

The new GUT suite (HMS-01 – HMS-14) was run against unchanged `main` (`0f28ac9`) with only the test file added. All 14 cases fail:

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

### 2. `Globals._roll_back_hidden_menu(pushed_menu) -> bool` (`globals.gd`)

- Used by the three failed-load paths in `load_key_mapping()` and `load_options()`. Each load now remembers the menu it pushed (`pushed_menu`, `null` if `menu_to_hide` was null or freed).
- Finds that entry with `rfind()`, removes it, shows the menu again and returns `true`. If the load pushed nothing, or the entry isn't on the stack, the stack is left alone and it returns `false`.

### 3. Callers

Each `if not …hidden_menus.is_empty(): var prev_menu: Node = …pop_back(); if is_instance_valid(prev_menu):` became `var prev_menu: Node = Globals.pop_hidden_menu(); if prev_menu != null:`. The bodies are unchanged apart from one less level of indentation.

| File                    | Function                                                                                                               |
|-------------------------|------------------------------------------------------------------------------------------------------------------------|
| `options_menu.gd`       | `_teardown()`                                                                                                          |
| `audio_settings.gd`     | `_on_back_button_pressed()`, `_on_tree_exited()`                                                                       |
| `advanced_settings.gd`  | `_on_advanced_back_button_pressed()`, `_on_tree_exited()`                                                              |
| `globals.gd`            | `_on_options_exited_unexpectedly()`; the 3 failed-load rollbacks use `_roll_back_hidden_menu()` instead (Review fixes) |
| `key_mapping.gd`        | Back: its own loop from #1210 replaced by the helper                                                                   |
| `settings_menu_base.gd` | `_restore_previous_menu()`: its own loop replaced by the helper                                                        |

`gdformat` joined one `log_message()` call in `advanced_settings.gd` onto one line after the dedent.

### 4. Tests

- **New `test/gut/test_hidden_menu_stack.gd` (25 cases):**
  - **Helper:** empty stack (HMS-01), only freed entries (HMS-02), freed entry above a live menu (HMS-03: returns the live one, keeps the menu below, shows nothing), live menu on top (HMS-04).
  - **Back and exit paths,** each with a freed entry above a live menu: Options Back (HMS-05), Audio Back (HMS-06), Audio unexpected exit (HMS-08), Advanced Back (HMS-09), Advanced unexpected exit (HMS-10) and `_on_options_exited_unexpectedly()` (HMS-12). Each checks the live menu is shown, the stack is empty, and the function finished (menu freed, Options state reset).
  - **Audio Back with only freed entries (HMS-07):** the menu still closes. See Design Decisions.
  - **Failed-load rollbacks,** each run with a null caller and with a valid one, on a stack with a freed entry above another screen's live menu: `load_key_mapping()` with no scene (HMS-11), `load_options()` with no scene (HMS-13) and with a scene that fails to instantiate (HMS-14). Each checks the function finished, the caller (if any) is shown and its entry removed, and the other screen's menu and the freed entry are still on the stack, with that menu still hidden.
  - **Edge cases (HMS-15 – HMS-25, added by CodeRabbit):**
    - Consecutive pops over freed and null entries keep LIFO order and show nothing (HMS-15).
    - `_roll_back_hidden_menu()` directly: nothing pushed (HMS-16), menu not on the stack (HMS-17), caller on the stack twice (HMS-18), freed entry above the caller (HMS-19), second rollback of the same menu (HMS-20). HMS-18 and HMS-19 check the helper's contract; in the game a failed load rolls back right after its own push.
    - Options unexpected exit with only freed entries still resets the state (HMS-21), and an older exit leaves a newer live instance, the stack and the live menu alone (HMS-22).
    - Back followed by the menu's own tree exit restores only one menu: Audio (HMS-23), Advanced (HMS-24) and Options (HMS-25).
- Key Mapping and `SettingsMenuBase` keep their existing freed-entry tests, which now go through the helper: KM-WEB-10, SMB-09 and SMB-14.

### Review fixes

#### CodeRabbit

- **`globals.gd`, failed loads popped a menu they never pushed:** `load_key_mapping()` and `load_options()` push `menu_to_hide` only when it is valid, but their failure paths always popped. With a null or freed caller and a freed entry above another screen's live menu, the helper popped and showed that menu, and a later Back could no longer restore it. Before this PR, the freed entry made the typed pop stop before it got that far. The three failure paths now undo only their own push with `_roll_back_hidden_menu()` (Key Changes 2). HMS-11, HMS-13 and HMS-14 were rewritten (not removed) to run with a null and a valid caller and to check that the other screen's menu stays on the stack and hidden; with the previous commit's `globals.gd`, all three fail ("null caller: unrelated + freed entries left alone"). `test_load_options_reentrancy.gd` (gdUnit4), which rolls back a valid caller, is unchanged and passes.
- **Edge-case tests (`6398d99`):** CodeRabbit added 11 tests. They were checked by breaking the code they guard (table below). Each one fails on at least one change, and nine of the ten changes are caught only by these tests, not by HMS-01 – HMS-14. The exception is HMS-16, which no single change catches, because it overlaps the null-caller half of HMS-11/13/14. It was kept because it's cheap. They were then given the suite's IDs (HMS-15 – HMS-25) and doc comments. The comments on HMS-18 and HMS-19 now say they check the helper's contract, and the test code is unchanged.

| Change to the code                                         | Fails                       | Caught by HMS-01 – 14 |
|------------------------------------------------------------|-----------------------------|-----------------------|
| Helper stops at the first freed entry                      | HMS-15, 21, 23, 24, 25      | ✅ (8 cases)           |
| Rollback uses `find()` instead of `rfind()`                | HMS-18                      | ❌                     |
| Rollback pops the top instead of its own entry             | HMS-17, 18, 19, 20          | ❌                     |
| Rollback shows a menu that isn't on the stack              | HMS-17, 20                  | ❌                     |
| Rollback falls back to `pop_hidden_menu()`                 | HMS-17, 20                  | ❌                     |
| No "still in the tree" guard in the Options exit handler   | HMS-22                      | ❌                     |
| Options state reset only when a menu was found             | HMS-21                      | ❌                     |
| No `_intentional_exit` guard in Audio / Advanced           | HMS-23 / HMS-24             | ❌                     |
| No `_torn_down` guard in Options                           | HMS-25                      | ❌                     |

#### Sourcery (not applied)

- **"Recovery paths bypass helper" (`globals.gd`):** the three failed-load rollbacks deliberately don't use `pop_hidden_menu()`. When the load pushed its caller, the caller is on top and both remove the same entry. When it pushed nothing, the helper would skip the freed entry and pop and show another screen's menu, which is the bug CodeRabbit found. Key Mapping, `SettingsMenuBase` and every Back / exit path do use the helper.
- **"Rollback tests expect hidden menu" (`test_hidden_menu_stack.gd`):** HMS-11/13/14 keep the other screen's menu on the stack and hidden on purpose; expecting it to be shown would test for the bug. The issue's "freed entry skipped, live menu shown" rule is covered for every Back / exit path (HMS-05, 06, 08, 09, 10, 12).

---

## Design Decisions

- **Skip, don't stop.** The rule from `SettingsMenuBase` and Key Mapping after #1210: a freed entry is discarded and the next live menu is shown. A freed entry means that menu is gone; the one below it is still the right screen to go back to.
- **A failed load undoes its own push, not "the top of the stack".** The rollback finds the entry it pushed with `rfind()` and removes that, so it can't touch a menu another screen left there, freed or not.
- **The helper returns the menu and does nothing else.** Every caller restores something different (focus target, DOM overlays, log text), so only the popping is shared.
- **Audio Back with only freed entries now uses the empty-stack fallback.** Before, that case had a non-empty stack, so the `else:` branch (`change_scene_to_file(Globals.previous_scene)`) never ran; with the fix the function would finish with no menu shown. Now `prev_menu == null` covers both "empty" and "only freed entries", so Back goes to `previous_scene` in both. HMS-07 blanks `previous_scene`, as the other Audio tests do, and checks that the menu still closes.
- **One file for the new tests.** The nine places are in four scripts, and the tests share the same freed-entry setup, so they live in one `HMS` suite instead of being spread over the per-menu suites. With 25 cases the file needs `# gdlint: disable=max-public-methods`, as `test_deserialize_event_key_tokens.gd` already does.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 v6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdformat --check` and `gdlint` as in CI.

| State                    | GUT tests | GUT asserts | gdUnit4 test cases |
|--------------------------|-----------|-------------|--------------------|
| `main` (`0f28ac9`, base) | 1,031     | 11,143      | 164                |
| This PR                  | 1,056     | 11,260      | 164                |

- **No test cases removed.**
- **Full GUT suite:** 1,056/1,056.
- **gdUnit4 suite:** 164/164, including `test_options_teardown.gd`, `test_load_options_reentrancy.gd`, `test_audio_settings.gd` and `test_audio_unexpected_exit.gd`, which drive the changed paths.
- **New suite on `main`:** HMS-01 – HMS-14 fail, 14/14 (see Confirm-first results).
- **Rollback fix on the previous commit:** HMS-11, HMS-13 and HMS-14 fail with the old rollback (see Review fixes).
- **CodeRabbit's tests:** each fails when the code it guards is broken (see Review fixes).
- **No typed `pop_back()` left:** `grep -rn "hidden_menus.pop_back" scripts/` finds only the one inside `pop_hidden_menu()`, which pops into a `Variant`.
- **GDScript lint and format:** `gdlint scripts` and `gdformat --check scripts` pass, and so do `gdlint` and `gdformat --check` on `test_hidden_menu_stack.gd`.

---

## Known Limitations / Follow-ups

- **Advanced Back uses `get_node()` on the restored menu** for `Panel/OptionsVBoxContainer/AdvancedSettingsButton`, which logs an error if the restored menu isn't Options. Advanced Settings is only opened from Options, so it doesn't happen in the game; HMS-09 and HMS-24 give their live menu that path.

---

## Reviewer's Guide

### File-Level Changes

| Change           | Details                                                                                                                                                           | Files                                                                                                                   |
|------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| Helpers.         | <ul><li>`pop_hidden_menu()`: skips freed entries, returns the live menu or `null`.</li><li>`_roll_back_hidden_menu()`: undoes a failed load's own push.</li></ul> | `scripts/core/globals.gd`                                                                                               |
| Globals callers. | <ul><li>Options exit handler uses `pop_hidden_menu()`.</li><li>3 failed-load rollbacks use `_roll_back_hidden_menu()`.</li></ul>                                  | `scripts/core/globals.gd`                                                                                               |
| Menu callers.    | <ul><li>5 Back / exit paths use the helper.</li></ul>                                                                                                             | `scripts/ui/menus/options_menu.gd`<br/>`scripts/ui/menus/audio_settings.gd`<br/>`scripts/ui/menus/advanced_settings.gd` |
| Existing loops.  | <ul><li>Replaced by the helper.</li></ul>                                                                                                                         | `scripts/ui/menus/key_mapping.gd`<br/>`scripts/ui/menus/settings_menu_base.gd`                                          |
| Tests.           | <ul><li>New GUT suite, 25 cases (HMS-15 – HMS-25 by CodeRabbit).</li></ul>                                                                                        | `test/gut/test_hidden_menu_stack.gd`<br/>`test/gut/test_hidden_menu_stack.gd.uid`                                       |
| Milestone note.  | <ul><li>This note.</li></ul>                                                                                                                                      | `files/docs/milestones/27/Part_19_Skip_freed_menu-stack_entries_in_every_Back_and_cleanup_path.md`                      |

### Assessment against linked issues

| Issue                                                   | Objective                                                        | Addressed | Explanation                                                                                       |
|---------------------------------------------------------|------------------------------------------------------------------|-----------|---------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | One GUT test per place with a freed entry on top                 | ✅         | HMS-05, HMS-06, HMS-08 – HMS-14. HMS-11/13/14 check the rollback rule from Review fixes.          |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | Helper tests: empty, only freed, freed above valid               | ✅         | HMS-01 – HMS-03 (and HMS-04, live on top; HMS-15, mixed stack).                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | Existing suites pass, no cases dropped (GUT and gdUnit4)         | ✅         | 1,056/1,056 GUT, 164/164 gdUnit4 locally.                                                         |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | No `var … : Node = …hidden_menus.pop_back()` left in `scripts/`  | ✅         | Only `pop_hidden_menu()` pops, into a `Variant`.                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | Helper also used in `key_mapping.gd` and `settings_menu_base.gd` | ✅         | One copy of the loop. The 3 failed-load rollbacks undo their own push instead (Review fixes).     |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | All tests pass in CI                                             | ⏳         | Pass locally; CI's GUT job didn't run on CodeRabbit's commit, so the next PR run confirms.        |
| <https://github.com/ikostan/SkyLockAssault/issues/1211> | Milestone note added                                             | ✅         | This note.                                                                                        |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1211 from the freed-entry failure found in #1210, listed the nine places and set the fix and test scope.
- Triaged the review comments and had CodeRabbit's added tests reviewed.

### Bots / AI contributions

- **@coderabbitai**
  - Review: failed loads should roll back only the menu they pushed (`globals.gd`), applied (see Review fixes).
  - Added 11 edge-case tests (`6398d99`), now HMS-15 – HMS-25.
- **@sourcery-ai**
  - Review: two comments asking for the helper in the rollback paths and for the rollback tests to expect the other screen's menu shown; not applied (see Review fixes).
- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked the nine places against `main` after #1210 merged, and ran the new suite on unchanged code: all 14 cases fail.
  - **Fix**
    - Added `Globals.pop_hidden_menu()` and switched the Back and exit paths, Key Mapping and `SettingsMenuBase` to it.
    - Wrote HMS-01 – HMS-14 in `test_hidden_menu_stack.gd`.
  - **Review fixes**
    - Applied CodeRabbit's rollback finding: added `_roll_back_hidden_menu()`, rewrote HMS-11, 13 and 14 and checked them against the previous commit.
    - Reviewed CodeRabbit's 11 tests by breaking the code each one guards, gave them IDs HMS-15 – HMS-25 and doc comments, and corrected the HMS-18 comment.
    - Answered the two Sourcery comments.
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, `gdformat` and `gdlint` locally.
    - Wrote this note.
  