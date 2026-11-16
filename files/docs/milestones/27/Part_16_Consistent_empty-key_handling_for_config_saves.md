<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Consistent empty-key handling for config saves

---

## PR #_TBD_ Summary

**Title:** Consistent empty-key handling for config saves  
**PR:** _TBD_  
**Branch:** `consistent-empty-key-handling-for-config-saves` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1145 – [FEATURE] Consistent empty-key handling for config saves](https://github.com/ikostan/SkyLockAssault/issues/1145)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** enhancement, testing, refactoring, GUT

### Purpose

This PR covers the Region 2 (#617) High finding "Inconsistent encryption failsafe".

Four code paths save `settings.cfg`, and only `Globals._save_settings()` handled an empty encryption key. It saved plaintext. Input mappings, the last input device and audio volumes called `save_encrypted_pass()` with the empty key.

The issue expected those three saves to fail. They don't: Godot 4.7.1 accepts an empty password and writes a normal `GDEC` file, keyed by the MD5 of `""`. So with an empty key:

- The file's format depended on which manager saved last: plaintext after a gameplay save, a "hollow" encrypted file after any other save.
- Once a real key returned, a hollow file failed its MD5 check. Since #1144 that moves the file to `.corrupt` and resets every setting.
- With an empty key, an existing properly encrypted file was decrypted with the MD5 of `""`, failed, and was moved to `.corrupt` the same way.

An empty key is rare: `_get_encryption_key()` returns one only when the salt is empty, and production builds crash on the uninjected placeholder. This PR makes that rare case behave the same everywhere and never lose the file.

---

## Key Changes

### 1. One save helper (`globals.gd`)

- **New `save_config(config, path) -> int`:** saves with `save_encrypted_pass()` when the key is set. With an empty key it saves plaintext with `ConfigFile.save()` and logs `⚠️ FAILSAFE ACTIVE: Saved in PLAINTEXT: <path>` (WARNING), or a plaintext-specific error if the write fails. Returns the save error.
- **All four save paths use it:**

| Save path         | Location                                              |
|-------------------|-------------------------------------------------------|
| Gameplay settings | `Globals._save_settings()`                            |
| Input mappings    | `Settings.save_input_mappings()`                      |
| Last input device | `Settings.save_last_input_device()`                   |
| Audio volumes     | `AudioManager.save_volumes()`                         |

- **Callers keep their own messages.** Each still logs its existing success and error lines, so the Playwright checks for `encrypted settings persisted successfully` are unaffected. `_save_settings()` loses its separate plaintext branch, which `save_config()` now covers.

### 2. Encrypted files are protected when the key is empty (`globals.gd`)

- **`safe_load_config()`:** if the key is empty and the file is encrypted, it doesn't decrypt or move the file. It logs a WARNING and returns `ERR_UNCONFIGURED`.
- All four save paths already skip saving on a read error other than `ERR_FILE_NOT_FOUND`, so the file is never overwritten. The three loaders log the error and keep their defaults.
- No `.corrupt` copy is made and no reset notice is set.
- The encrypted check now runs once per load (`file_exists` and `encrypted` locals).

### 3. Test seam (`globals.gd`)

- **New `set_test_empty_encryption_key(enabled := true)`** next to `set_test_encryption_key()`. It sets `_force_empty_key_for_tests`, which makes `ensure_encryption_key()` return `""` without regenerating a key. The cached key is left unchanged.
- Setting `save_encryption_pass = ""` couldn't simulate the failure, because `ensure_encryption_key()` regenerates the key.

### 4. Docs

- **`Browser_DevTools_Guide_Verifying_Web_Save_Encryption.md`:** "Why This Happens" now says that Godot accepts an empty password, and that since #1145 an empty key saves readable plaintext with no `GDEC` header.
- **`globals.gd` header:** lists `save_config()` with the other shared config I/O.

### 5. Tests

- **`test_config_save_failsafe.gd` (new GUT suite, 11 cases):**

| Area                               | Cases                                                                                                                                    |
|------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| `save_config()`                    | Encrypted with a valid key; readable plaintext and warning with an empty key; seam keeps the cached key                                  |
| Empty key, no file                 | Each of the four paths saves plaintext; all four sections share one file and reload from it                                              |
| Empty key, existing encrypted file | Load keeps the file, makes no `.corrupt` copy, sets no notice; all four saves leave it byte-identical; `_load_settings()` keeps defaults |
| Key returns                        | A plaintext file from an empty key is encrypted by the existing migration, with every section kept                                       |
| Write failures                     | `save_config()` returns the error in both modes; each of the four callers logs its own error                                             |

---

## Design Decisions

- **`ERR_UNCONFIGURED` for "no key".** It isn't `OK`, `ERR_FILE_NOT_FOUND`, or a corruption code, so every caller takes its existing "read failed, don't save" path, and the #1144 move to `.corrupt` is never reached.
- **The plaintext warning is logged only after a successful write.** The issue's sketch logged it before saving. A failed write now logs a plaintext-specific error instead of claiming it saved.
- **A flag, not a fake key, for the test seam.** Tests can't leave a blank `save_encryption_pass` behind by accident, and the suite turns the flag off first in `after_each()`, before anything else is restored.
- **Tests that need `save_last_input_device()` use `Settings.CONFIG_PATH`.** That method has no path parameter. The suite saves the file's bytes in `before_each()` and writes them back in `after_each()`. Its write-failure case puts a directory at `CONFIG_PATH`, which the cleanup removes.
- **Log lines are read with `OS.add_logger()`.** Callers log through the `Globals` autoload, which can't be doubled, so the suite adds a small `Logger` that records what `log_message()` prints (Godot 4.5+).

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, using the same commands as `gut_tests.yml` and `gdunit4_tests.yml` (gdUnit4-coverage stripped, `xvfb-run`). `gdformat --check`, `gdlint` and `markdownlint-cli2` as in CI.

- **Totals:**

| State                           | GUT scripts | GUT tests | GUT asserts | gdUnit4 cases |
|---------------------------------|-------------|-----------|-------------|---------------|
| `main` (`6940a1c`, branch base) | 106         | 932       | 10,623      | 164           |
| This PR (`172373b`)             | 107         | 943       | 10,682      | 164           |

- **Test counts per changed file (`main` → this PR):**

| File                                  | Framework | Cases   |
|---------------------------------------|-----------|---------|
| `test_config_save_failsafe.gd` (new)  | GUT       | 0 → 11  |

- **No test cases removed.** The existing suites the issue names (`test_full_encryption_workflow.gd`, `test_encryption_logging.gd`, `test_settings_migration.gd`, `test_error_edge_cases.gd`, `test_settings.gd`, `test_fps_settings_integration.gd`) pass unchanged.
- **Engine output:** 50 engine errors and 1 `settings.cfg` decryption failure in the full GUT run, the same as on `main`.
- **Mutation checks:** the old behaviour was put back in a scratch copy, and the tests had to fail:
  - **No empty-key guard in `safe_load_config()`:** 3 fail. The encrypted file is moved to `.corrupt`.
  - **Old `save_encrypted_pass()` calls in `Settings` and `AudioManager`:** 3 fail. Input, last device and audio save hollow `GDEC` files, and the coexist and upgrade cases can't read the file.
- **Engine probe:** `ConfigFile.save_encrypted_pass(path, "")` returns `OK` and writes a 60-byte `GDEC` file that `load_encrypted_pass(path, "")` reads back.
- **`tests/ci/test_salt_injection.py`:** 23 passed. `test_injection_readonly_file` fails in the sandbox and on unchanged `main`, because it runs as root, as in Part 15.
- **Not run locally:** Playwright (`volume_sliders_mutes_test.py`, `no_error_logs_test.py`) and the benchmark. _Confirm from the PR run._
- **PR pipeline:** _confirm all jobs from the final run._
- **Benchmark:** _fill in from the PR run._ No game-loop code changes, so no change is expected.

---

## Known Limitations / Follow-ups

- **Callers' success lines still say "Encrypted" in plaintext mode.** For example, `🔒 Encrypted input mappings saved` is logged at DEBUG right after the plaintext warning. The lines were kept as the issue asks, so log-based tests and Playwright checks still match.
- **A hollow file from an older build** is skipped while the key is empty, and goes to `.corrupt` once a real key returns, as before. This needs a build that ran with an empty salt, which production builds can't do.
- **#1103** (Milestone 29) later moves `save_config()` into `SettingsStore`.
- **#1146** (single source for weapon tuning) is planned for this same PR.

---

## Reviewer's Guide

### File-Level Changes

| Change                | Details                                                                                                                                                       | Files                                                                                            |
|-----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| One save helper.      | <ul><li>`save_config()`: encrypted with a key, plaintext without one.</li><li>All four save paths use it; their log lines are unchanged.</li></ul>            | `scripts/core/globals.gd`<br/>`scripts/core/settings.gd`<br/>`scripts/managers/audio_manager.gd` |
| Empty-key load guard. | <ul><li>`safe_load_config()` returns `ERR_UNCONFIGURED` for an encrypted file with an empty key, without decrypting or moving it.</li></ul>                   | `scripts/core/globals.gd`                                                                        |
| Test seam.            | <ul><li>`set_test_empty_encryption_key()` forces an empty key without touching the cached one.</li></ul>                                                      | `scripts/core/globals.gd`                                                                        |
| Tests.                | <ul><li>11 GUT cases.</li><li>`CONFIG_PATH` bytes saved and restored.</li><li>Log lines read with `OS.add_logger()`.</li><li>No test cases removed.</li></ul> | `test/gut/test_config_save_failsafe.gd`                                                          |
| Docs.                 | <ul><li>Hollow-encryption note corrected.</li></ul>                                                                                                           | `files/docs/Browser_DevTools_Guide_Verifying_Web_Save_Encryption.md`                             |
| Milestone note.       | <ul><li>This note.</li></ul>                                                                                                                                  | `files/docs/milestones/27/Part_16_Consistent_empty-key_handling_for_config_saves.md`             |

### Assessment against linked issues

| Issue                                                   | Objective                                                                    | Addressed | Explanation                                                                       |
|---------------------------------------------------------|------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | All four save paths use `save_config()`                                      | ✅         | No other `save_encrypted_pass()` or `ConfigFile.save()` call left in `scripts/`.  |
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | With an empty key, new files save as plaintext for every section             | ✅         | Each path tested alone and all four together.                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | An existing encrypted file is never overwritten, renamed or deleted          | ✅         | Load and all four saves leave it byte-identical; no `.corrupt`, no notice.        |
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | Behavior with a valid key is unchanged                                       | ✅         | Full GUT and gdUnit4 runs pass unchanged.                                         |
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | All GUT, gdUnit4, Playwright, CI script and lint jobs pass, no cases removed | ⏳         | GUT, gdUnit4, lint and `tests/ci` pass locally; confirm Playwright on the PR run. |
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | The PR's milestone note is added                                             | ✅         | This note.                                                                        |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1145 and set its scope.
- Asked for the next Milestone 27 tasks, to add a second issue to this PR, and to work through #1145 and #1146 one at a time.
- Created the `consistent-empty-key-handling-for-config-saves` branch.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Planning**
    - Picked #1145 as next from the Part 15 follow-ups, and proposed pairing it with #1146 (no shared files; together they close Region 2's High and Medium findings).
  - **Verification**
    - Found that Godot accepts an empty password, so the three saves wrote hollow files instead of failing as the issue said.
    - Ran GUT, gdUnit4, `tests/ci` and the linters locally with the CI commands, on `main` and on the branch, and mutation-tested the new suite.
    - Wrote this note.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
