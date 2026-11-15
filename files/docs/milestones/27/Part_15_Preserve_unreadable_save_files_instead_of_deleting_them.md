<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Preserve unreadable save files instead of deleting them

---

## PR #_TBD_ Summary

**Title:** Preserve unreadable save files instead of deleting them  
**PR:** _fill in after opening_  
**Branch:** `1144-preserve-unreadable-save-files` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1144 – [FEATURE] Preserve unreadable save files instead of deleting them](https://github.com/ikostan/SkyLockAssault/issues/1144)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** documentation, enhancement, testing, GUT

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
- **`main_menu.gd`:** `_show_settings_reset_notice_if_pending()` runs at the end of `_ready()`. It shows "Settings could not be read and were reset." for `settings_reset_notice_duration` seconds (new export, default 5.0), then hides it. The label ignores the mouse and can't take focus, so the buttons and the intro focus work as before.

### 3. Salt rotation rule documented

- **`Production_Salt_Injection_&_Security_Guard_Architecture.md`:** new section 6, "Salt Rotation Rule". It explains what a rotation does to saved settings and outlines a migration (try the previous salt, re-save with the new one).
- **`deploy_to_itch.yml`:** a comment above "Inject Production Salt into GDScript" links to that section.
- **Two existing docs** still described deletion and now describe the move: `Browser_DevTools_Guide_Verifying_Web_Save_Encryption.md` (missing-file causes, expected recovery logs) and `Performance_Benchmark_Guide.md` (MD5 mismatch troubleshooting).

---

## Design Decisions

- **The move happens in `safe_load_config()`, as the issue asks.** `Globals` reads first (autoload order contract), so it moves the file. `Settings` and `AudioManager` then find no file and take the normal first-boot path. The tests check that only the first read fails.
- **Separate helper.** `_preserve_unreadable_config()` keeps `safe_load_config()` readable and gives the rename failure path one place.
- **Failures keep the original error.** Returning `ERR_FILE_NOT_FOUND` after a failed rename would make callers save defaults over the unreadable file, which is the data loss this issue removes.
- **Success is logged as WARNING, not DEBUG.** A reset of every setting is worth seeing at the default log level (INFO). The Playwright no-error test uses this line to check that a normal start doesn't take this path.
- **Notice label outside the panel.** The panel starts transparent for `intro_delay`. Inside it, the notice would be hidden for most of its 5 seconds.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, using the same commands as `gut_tests.yml` and `gdunit4_tests.yml` (gdUnit4-coverage stripped, `xvfb-run`). `gdformat --check`, `gdlint`, `yamllint`, `black --check`, `markdownlint-cli2` and `tests/ci` as in CI.

- **Totals:**

| State         | GUT tests | GUT asserts | gdUnit4 cases |
|---------------|-----------|-------------|---------------|
| `main`        | 918       | 10,512      | 157           |
| This PR       | 927       | 10,584      | 160           |

- **Test counts per changed file (`main` → this PR):**

| File                                            | Framework  | Cases   |
|-------------------------------------------------|------------|---------|
| `test_save_file_recovery.gd` (new)              | GUT        | 0 → 9   |
| `test_main_menu_settings_reset_notice.gd` (new) | gdUnit4    | 0 → 3   |
| `test_main_menu_intro_visibility.gd`            | gdUnit4    | 11 → 11 |
| `no_error_logs_test.py`                         | Playwright | 1 → 1   |

- **Real encrypted files.** The new GUT tests save with one key and load with another, or damage a byte after the header. `test_scenario_5_corrupted_file_fails_gracefully` is unchanged: it writes plaintext without the encrypted header, so it never reaches this code.
- **Extra case beyond the issue's list:** a failed rename (a non-empty directory at the backup path) keeps the file, returns `ERR_FILE_CORRUPT` and sets no notice.
- **`test_main_menu_intro_visibility.gd`:** its hand-built menu supplies only the nodes `main_menu.gd`'s `@onready` vars need. It now also adds `SettingsResetNotice`. Without it, all 11 cases errored. No test cases changed.
- **`no_error_logs_test.py`:** the existing test also asserts that the reset log lines don't appear on a normal start.
- **No test cases removed.**
- **Mutation check:** with `main`'s `globals.gd` in a scratch copy, all 9 new GUT tests fail.
- **`tests/ci`:** 1122 passed locally. `test_salt_injection.py::test_injection_readonly_file` fails in the sandbox and on unchanged `main`, because it runs as root. It passes in CI.
- **Not run locally:** Playwright (no web export templates in the sandbox) and the benchmark. _Fill in from the PR run._
- **Manual check on a local web export:** _still to do._ Export twice with different salts, serve both from the same origin, save settings in the first, then load the second:
  - [ ] The game starts with defaults and shows the notice once.
  - [ ] Reloading doesn't show the notice again.
  - [ ] Newly changed settings persist after another reload.

---

## Known Limitations / Follow-ups

- **#1145** (empty-key saves) is next. It changes the same branch of `safe_load_config()`.
- **Restoring from `.corrupt`** and **salt migration** are out of scope, as in the issue.
- **#1103** (Milestone 29) later moves this code into `SettingsStore`.
- **Web persistence of the rename:** on web, `user://` changes are synced to IndexedDB when a file is closed. The rename itself doesn't close a file. The next save does, and on that same startup `Settings._ready()` saves the backfilled default key bindings, because it found no file. The manual web check above confirms this.

---

## Reviewer's Guide

### File-Level Changes

| Change                    | Details                                                                                                                                                                                 | Files                                                                                                                                                                                                                                       |
|---------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Rename instead of delete. | <ul><li>`_preserve_unreadable_config()` moves the file to `.corrupt`, keeping one copy.</li><li>Failures keep the file and return the original error.</li></ul>                         | `scripts/core/globals.gd`                                                                                                                                                                                                                   |
| Reset notice.             | <ul><li>`consume_settings_reset_notice()` one-shot flag.</li><li>Non-blocking main menu label for 5 seconds.</li></ul>                                                                  | `scripts/core/globals.gd`<br/>`scripts/ui/menus/main_menu.gd`<br/>`scenes/main_menu.tscn`                                                                                                                                                   |
| Salt rule.                | <ul><li>Section 6 in the salt doc.</li><li>Workflow comment linking to it.</li><li>Deletion wording updated in two guides.</li></ul>                                                    | `files/docs/Production_Salt_Injection_&_Security_Guard_Architecture.md`<br/>`.github/workflows/deploy_to_itch.yml`<br/>`files/docs/Browser_DevTools_Guide_Verifying_Web_Save_Encryption.md`<br/>`files/docs/Performance_Benchmark_Guide.md` |
| Tests.                    | <ul><li>9 GUT and 3 gdUnit4 cases.</li><li>Visibility fixture gets the new label.</li><li>Playwright no-error test checks the reset log lines.</li><li>No test cases removed.</li></ul> | `test/gut/test_save_file_recovery.gd`<br/>`test/gdunit4/test_main_menu_settings_reset_notice.gd`<br/>`test/gdunit4/test_main_menu_intro_visibility.gd`<br/>`tests/no_error_logs_test.py`                                                    |
| Milestone note.           | <ul><li>This note.</li></ul>                                                                                                                                                            | `files/docs/milestones/27/Part_15_Preserve_unreadable_save_files_instead_of_deleting_them.md`                                                                                                                                               |

### Assessment against linked issues

| Issue                                                   | Objective                                                                    | Addressed | Explanation                                                                       |
|---------------------------------------------------------|------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | An unreadable encrypted file is preserved as `.corrupt`, one copy kept       | ✅         | Wrong-key, damaged and replace-existing cases tested.                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | Defaults load, and the player sees one non-blocking notice                   | ✅         | GUT checks all three managers; gdUnit4 checks the notice, its timeout and focus.  |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | Other read errors still leave the file untouched                             | ✅         | Encrypted parse error and plaintext parse error tested; failed rename tested too. |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | The salt rule is documented, and the deploy workflow links to it             | ✅         | Section 6 and the workflow comment.                                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | All GUT, gdUnit4, Playwright, CI script and lint jobs pass, no cases removed | ⏳         | Passed locally except Playwright and the benchmark; confirm on the PR run.        |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | Manual web check                                                             | ⏳         | Still to do.                                                                      |
| <https://github.com/ikostan/SkyLockAssault/issues/1144> | The PR's milestone note is added                                             | ✅         | This note.                                                                        |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1144 and set its scope.
- Asked to plan Milestone 27's next work as one PR at a time and to start #1144.
- Applied the changes, committed, and opened the PR.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Planning**
    - Mapped the open Milestone 27 work and the Region 2 order (#1144 before #1145, #1146 before #1138).
    - Flagged that the Region issues are nested as sub-issues of each other, and that #1150 can't land before Region 5.
    - Checked #1144's line references against current `main` (the delete branch had moved from lines 688–699 to about 700–711).
  - **Implementation**
    - Wrote the rename helper, the reset notice, the docs, and the new tests.
    - Found that the hand-built menu in `test_main_menu_intro_visibility.gd` needed the new label.
  - **Verification**
    - Probed Godot's error codes for wrong-key, damaged, truncated and unparsable files before writing the tests.
    - Ran GUT, gdUnit4, `tests/ci` and the linters locally with the CI commands, and mutation-tested the new GUT suite against `main`'s `globals.gd`.
- _Review bots: fill in after review._

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
