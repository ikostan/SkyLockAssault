<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Preserve unreadable save files instead of deleting them

---

## PR #1200 Summary

**Title:** Preserve unreadable save files  
**PR:** [#1200](https://github.com/ikostan/SkyLockAssault/pull/1200)  
**Branch:** `preserve-unreadable-save-files-instead-of-deleting-them` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1144 – [FEATURE] Preserve unreadable save files instead of deleting them](https://github.com/ikostan/SkyLockAssault/issues/1144)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** refactoring, documentation, enhancement, testing, GUT

### Purpose

This PR covers two Region 2 (#617) findings: "A decrypt failure wipes every section" and "Salt rotation would trigger that wipe for every web player".

- `Globals.safe_load_config()` deleted `settings.cfg` when decryption failed with `ERR_FILE_CORRUPT` or `ERR_INVALID_DATA`. The file holds gameplay settings, key bindings and audio volumes, so one failed read lost all of them, with no copy left to inspect and no message to the player.
- On web builds every player's file is encrypted with the same key, which depends only on `PRODUCTION_SALT`. Rotating the salt would have deleted every web player's settings on their next load.

The empty-key save handling (#1145) changes the same `safe_load_config()` branch and is blocked by this issue, so it follows in its own PR.

---

## Key Changes

### 1. Rename instead of delete (`globals.gd`)

- **New `CORRUPT_BACKUP_SUFFIX`** (`".corrupt"`).
- **New `_preserve_unreadable_config(path, load_err)`**, called from the `ERR_FILE_CORRUPT` / `ERR_INVALID_DATA` branch of `safe_load_config()`:
  - Removes an existing `path.corrupt` first, so only the latest copy is kept.
  - Moves the file with `DirAccess.rename_absolute()`, contents unchanged.
  - On success, sets the reset notice and returns `ERR_FILE_NOT_FOUND`, so callers still load defaults, as before.
  - If the old backup can't be removed or the rename fails, logs an error, leaves the file in place and returns the original error. Callers then skip saving, as on the old failed-delete path.
- **Other errors are unchanged.** Other decryption errors (for example `ERR_PARSE_ERROR` from a file that decrypts but isn't valid config text) and all plaintext load errors still leave the file untouched.
- **Doc comment and logs** now describe the move instead of deletion. The header comment lists the recovery path.

### 2. One-shot reset notice

- **`Globals._settings_reset_notice_pending`**, set only after a successful move. Not saved, so the notice appears once per run.
- **`Globals.consume_settings_reset_notice() -> bool`** returns `true` once, then `false`.
- **`main_menu.tscn`:** new hidden `SettingsResetNotice` label under `VideoStreamPlayer`, just below the menu panel. It sits outside the panel, so it's visible during the intro fade.
- **`main_menu.gd`:** `_show_settings_reset_notice_if_pending()` runs at the end of `_ready()`. It shows "Settings could not be read and were reset." for `settings_reset_notice_duration` seconds (new export, default 5.0), then hides it.
- **Non-blocking:** the function sets the label's `mouse_filter` to `MOUSE_FILTER_IGNORE` and `focus_mode` to `FOCUS_NONE` before showing it. Both are Label's defaults; setting them in code keeps the notice non-blocking even if the scene changes (raised by Sourcery).

### 3. Salt rotation rule documented

- **`Production_Salt_Injection_&_Security_Guard_Architecture.md`:** new section 6, "Salt Rotation Rule". It explains what a rotation does to saved settings and outlines a migration (try the previous salt, re-save with the new one).
- **`deploy_to_itch.yml`:** a comment above "Inject Production Salt into GDScript" links to that section.
- **Two existing docs** still described deletion and now describe the move: `Browser_DevTools_Guide_Verifying_Web_Save_Encryption.md` (missing-file causes, expected recovery logs) and `Performance_Benchmark_Guide.md` (MD5 mismatch troubleshooting).

### 4. Tests

- **`test_save_file_recovery.gd` (new GUT suite, 14 cases):** 9 written with the change, 5 added by CodeRabbit (`cc1269c`).
- **`test_main_menu_settings_reset_notice.gd` (new gdUnit4 suite, 7 cases):** 3 written with the change, 4 added by CodeRabbit.
- **`test_main_menu_intro_visibility.gd`:** its hand-built menu now also adds `SettingsResetNotice`.
- **`no_error_logs_test.py`:** also asserts that a normal start doesn't log the reset.
- **Review fixes:**
  - The reset test sets its own `fire` binding instead of reading whatever an earlier suite left in the shared InputMap (CodeRabbit).
  - The GUT suite restores `AudioManager._last_audible_volume`, which `load_volumes()` and `save_volumes()` rebuild (CodeRabbit).
  - Two of CodeRabbit's added tests were reworded (see Design Decisions), and its GUT asserts got failure messages like the rest of the suite.

---

## Design Decisions

- **The move happens in `safe_load_config()`, as the issue asks.** `Globals` reads first (autoload order contract), so it moves the file. `Settings` and `AudioManager` then find no file and take the normal first-boot path. The tests check that only the first read fails.
- **Separate helper.** `_preserve_unreadable_config()` keeps `safe_load_config()` readable and gives the rename failure path one place.
- **Failures keep the original error.** Returning `ERR_FILE_NOT_FOUND` after a failed rename would make callers save defaults over the unreadable file, which is the data loss this issue removes.
- **Success is logged as WARNING, not DEBUG.** A reset of every setting is worth seeing at the default log level (INFO). The Playwright no-error test uses this line to check that a normal start doesn't take this path.
- **Notice label outside the panel.** The panel starts transparent for `intro_delay`. Inside it, the notice would be hidden for most of its 5 seconds.
- **Mouse filter and focus mode set in code.** Sourcery flagged the label as able to catch clicks, because the `.tscn` has no `mouse_filter` line. That was wrong: Godot omits default values from scenes, and Label already defaults to `MOUSE_FILTER_IGNORE` and `FOCUS_NONE`. A `mouse_filter = 2` line in the scene would be dropped on the next editor save, so the values are set in `_show_settings_reset_notice_if_pending()` instead.
- **CodeRabbit's added tests: 7 kept as written, 2 reworded.**
  - `test_invalid_data_preserves_bytes_and_sets_notice` claimed to check that both corruption codes are handled, but it calls the helper directly and the helper ignores the code. Renamed to `test_preserve_helper_handles_invalid_data_like_corrupt`, with a comment that says what it checks.
  - `test_notice_timeout_after_menu_leaves_tree` asserted that the notice stays visible after the menu leaves the tree. That's a side effect of the early `return`, not a requirement, and it made the test fail if the code simply hid the label. The test now checks only that the timeout raises no error and the notice stays consumed.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, using the same commands as `gut_tests.yml` and `gdunit4_tests.yml` (gdUnit4-coverage stripped, `xvfb-run`). `gdformat --check`, `gdlint`, `yamllint`, `black --check`, `markdownlint-cli2` and `tests/ci` as in CI.

- **Totals:**

| State                                       | GUT tests | GUT asserts | gdUnit4 cases |
|---------------------------------------------|-----------|-------------|---------------|
| `main`                                      | 918       | 10,512      | 157           |
| `13ec8eb` (CI)                              | 927       | 10,585      | 160           |
| + CodeRabbit tests and review fixes (local) | 932       | 10,623      | 164           |

- **Test counts per changed file (`main` → this PR):**

| File                                            | Framework  | Cases   |
|-------------------------------------------------|------------|---------|
| `test_save_file_recovery.gd` (new)              | GUT        | 0 → 14  |
| `test_main_menu_settings_reset_notice.gd` (new) | gdUnit4    | 0 → 7   |
| `test_main_menu_intro_visibility.gd`            | gdUnit4    | 11 → 11 |
| `no_error_logs_test.py`                         | Playwright | 1 → 1   |

- **Real encrypted files.** The new GUT tests save with one key and load with another, or damage a byte after the header. `test_scenario_5_corrupted_file_fails_gracefully` is unchanged: it writes plaintext without the encrypted header, so it never reaches this code.
- **Extra case beyond the issue's list:** a failed rename (a non-empty directory at the backup path) keeps the file, returns `ERR_FILE_CORRUPT` and sets no notice.
- **`test_main_menu_intro_visibility.gd`:** its hand-built menu supplies only the nodes `main_menu.gd`'s `@onready` vars need. Without `SettingsResetNotice`, all 11 cases errored. No test cases changed.
- **No test cases removed.**
- **Mutation checks:** the old behaviour was put back in a scratch copy, and the tests had to fail:
  - **`main`'s `globals.gd`:** all 9 original GUT tests fail.
  - **Reset test with the file actually applied:** fails on the `fire` binding (75 instead of 32).
  - **No `_last_audible_volume` restore:** a known history set before the suite isn't restored afterwards.
  - **No `is_instance_valid` guard on the notice label:** `test_notice_timeout_after_label_is_freed` hits "previously freed" and aborts the run.
  - **`ERR_INVALID_DATA` removed from `safe_load_config()`'s check:** no test fails (see Known Limitations).
- **`tests/ci`:** 1122 passed locally. `test_salt_injection.py::test_injection_readonly_file` fails in the sandbox and on unchanged `main`, because it runs as root. It passes in CI.
- **PR pipeline:**
  - **`fa9b99d` and `13ec8eb`:** every job passed, including both browser shards and the benchmark.
  - **`cc1269c`:** GDScript lint failed on a trailing tab in `main_menu.gd` (line 115, from `6ef1b9e`), so the test jobs were skipped. Fixed in the follow-up commit.
  - **Final commit:** _confirm all jobs from the final run._
- **Browser shards (`13ec8eb`):** Core Web Flows ran 65 tests, as in Part 14. CI & Security ran 1123, up from 1118 in Part 14 by tests merged to `main` since; this PR adds none there.
- **Benchmark (`13ec8eb`):** report-only, no ⚠️ on desktop or web.
  - **Settings saves in 60 s:** 0 on desktop and web.
  - **Desktop:** flat. Frame interval p95 17.095 ms (baseline 17.080), 0 dropped frames.
  - **Web:** frame interval p95 36.2 ms (baseline 38.9, −7%), dropped frames 699 (baseline 1432, −51%). The game loop doesn't change in this PR, so this is runner variation, not a gain.
- **Manual check on a local web export:** _still to do._ Export twice with different salts, serve both from the same origin, save settings in the first, then load the second:
  - [ ] The game starts with defaults and shows the notice once.
  - [ ] Reloading doesn't show the notice again.
  - [ ] Newly changed settings persist after another reload.

---

## Known Limitations / Follow-ups

- **#1145** (empty-key saves) is next. It changes the same branch of `safe_load_config()`.
- **Restoring from `.corrupt`** and **salt migration** are out of scope, as in the issue.
- **#1103** (Milestone 29) later moves this code into `SettingsStore`.
- **`ERR_INVALID_DATA` has no real-file test.** No known way makes Godot return it for a settings file, so removing it from `safe_load_config()`'s check would go unnoticed. The helper test documents this instead of claiming coverage.
- **GUT skips a suite that doesn't parse and still exits 0.** Seen while working on this PR: a parse error in `test_save_file_recovery.gd` produced only "Ignoring script … because it does not extend GutTest", so CI would have stayed green without running the suite. Needs its own bug issue.
- **Web persistence of the rename:** on web, `user://` changes are synced to IndexedDB when a file is closed. The rename itself doesn't close a file. The next save does, and on that same startup `Settings._ready()` saves the backfilled default key bindings, because it found no file. The manual web check above confirms this.

---

## Reviewer's Guide

### File-Level Changes

| Change                    | Details                                                                                                                                                                                                                                                          | Files                                                                                                                                                                                                                                       |
|---------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Rename instead of delete. | <ul><li>`_preserve_unreadable_config()` moves the file to `.corrupt`, keeping one copy.</li><li>Failures keep the file and return the original error.</li></ul>                                                                                                  | `scripts/core/globals.gd`                                                                                                                                                                                                                   |
| Reset notice.             | <ul><li>`consume_settings_reset_notice()` one-shot flag.</li><li>Main menu label for 5 seconds, with mouse filter and focus mode set in code.</li></ul>                                                                                                          | `scripts/core/globals.gd`<br/>`scripts/ui/menus/main_menu.gd`<br/>`scenes/main_menu.tscn`                                                                                                                                                   |
| Salt rule.                | <ul><li>Section 6 in the salt doc.</li><li>Workflow comment linking to it.</li><li>Deletion wording updated in two guides.</li></ul>                                                                                                                             | `files/docs/Production_Salt_Injection_&_Security_Guard_Architecture.md`<br/>`.github/workflows/deploy_to_itch.yml`<br/>`files/docs/Browser_DevTools_Guide_Verifying_Web_Save_Encryption.md`<br/>`files/docs/Performance_Benchmark_Guide.md` |
| Tests.                    | <ul><li>14 GUT and 7 gdUnit4 cases, 9 of them from CodeRabbit.</li><li>Shared InputMap and audio history restored.</li><li>Visibility fixture gets the new label.</li><li>Playwright no-error test checks the reset log lines.</li><li>No test cases removed.</li></ul> | `test/gut/test_save_file_recovery.gd`<br/>`test/gdunit4/test_main_menu_settings_reset_notice.gd`<br/>`test/gdunit4/test_main_menu_intro_visibility.gd`<br/>`tests/no_error_logs_test.py`                                                    |
| Milestone note.           | <ul><li>This note.</li></ul>                                                                                                                                                                                                                                     | `files/docs/milestones/27/Part_15_Preserve_unreadable_save_files_instead_of_deleting_them.md`                                                                                                                                               |

### Assessment against linked issues

| Issue                                                   | Objective                                                                    | Addressed | Explanation                                                                                          |
|---------------------------------------------------------|------------------------------------------------------------------------------|-----------|------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | An unreadable encrypted file is preserved as `.corrupt`, one copy kept       | ✅         | Wrong-key, damaged, replace-existing and second-recovery cases tested.                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | Defaults load, and the player sees one non-blocking notice                   | ✅         | GUT checks all three managers; gdUnit4 checks the notice, its timeout, focus, mouse filter and reload. |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | Other read errors still leave the file untouched                             | ✅         | Encrypted parse error and plaintext parse error tested; failed rename tested too.                    |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | The salt rule is documented, and the deploy workflow links to it             | ✅         | Section 6 and the workflow comment.                                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | All GUT, gdUnit4, Playwright, CI script and lint jobs pass, no cases removed | ⏳         | All passed on `13ec8eb`; lint failed on `cc1269c` and was fixed. Confirm on the final run.           |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | The benchmark shows no unexplained regression                                | ✅         | No ⚠️ on `13ec8eb`; settings saves stay at 0.                                                         |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | Manual web check                                                             | ⏳         | Still to do.                                                                                         |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | The PR's milestone note is added                                             | ✅         | This note.                                                                                           |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1144 and set its scope.
- Asked to plan Milestone 27's next work as one PR at a time and to start #1144.
- Applied the changes, committed, and opened the PR.
- Ran CodeRabbit's unit test generation, reviewed the bot findings, and asked for a review of the generated tests.
- Commits:
  - `48d4b3f` Preserve unreadable save files
  - `4db3280` Add settings reset notice to main menu
  - `fa9b99d` Document save recovery and salt rotation risks
  - `9ebe691` Stabilize save recovery reset tests
  - `13ec8eb` Update no_error_logs_test.py
  - `6ef1b9e` Make settings reset notice non-blocking

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Planning**
    - Mapped the open Milestone 27 work and the Region 2 order (#1144 before #1145, #1146 before #1138).
    - Flagged that the Region issues are nested as sub-issues of each other, and that #1150 can't land before Region 5.
    - Checked #1144's line references against current `main` (the delete branch had moved from lines 688–699 to about 700–711).
  - **Verification**
    - Probed Godot's error codes for wrong-key, damaged, truncated and unparsable files before writing the tests.
    - Ran GUT, gdUnit4, `tests/ci` and the linters locally with the CI commands, and mutation-tested the new suites.
    - Compared `4db3280` with the local branch and found five files missing from the PR (workflow comment, two guides, visibility fixture, Playwright check).
  - **Review**
    - Agreed with CodeRabbit's `fire` binding and audio history findings, fixed both, and checked each fix in a scratch copy.
    - Showed that CodeRabbit's missing-label finding was raised on `48d4b3f`, before `4db3280` added the label.
    - Showed that Sourcery's mouse-filter finding was wrong (Label's defaults), and suggested setting both values in code anyway.
    - Reviewed CodeRabbit's 9 generated tests: 7 kept, 2 reworded, assert messages added. Found the trailing tab that failed lint on `cc1269c`.
- **@coderabbitai**
  - Generated 9 unit tests on request (`cc1269c`): 5 GUT, 4 gdUnit4.
  - Flagged that the reset test assumed `fire` wasn't bound to K (fixed).
  - Flagged that the suite didn't restore `_last_audible_volume` (fixed).
  - Flagged the missing `SettingsResetNotice` node; outdated, reviewed at `48d4b3f`.
  - Posted a walkthrough of the PR.
- **@sourcery-ai**
  - Posted a linked-issues checklist and a reviewer's guide.
  - Flagged the missing workflow comment (fixed in `fa9b99d`).
  - Flagged that the notice could catch clicks; not the case, but both values are now set in code.
  - Stopped reviewing later pushes: the 7-day review budget ran out.
- **@deepsource-io**
  - Graded the Python and JavaScript changes and flagged one comment line in `no_error_logs_test.py` as too long (93 > 88 characters). _Outcome: fill in._
- **@qodo-code-review**
  - Reviews paused for this account; no findings.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
