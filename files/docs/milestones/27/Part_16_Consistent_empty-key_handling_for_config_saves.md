<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Consistent empty-key handling for config saves & use BulletResource as the single source for weapon tuning

---

## PR #_TBD_ Summary

**Title:** Consistent empty-key handling for config saves & use BulletResource as the single source for weapon tuning  
**PR:** _TBD_  
**Branch:** `consistent-empty-key-handling-for-config-saves` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1145 – [FEATURE] Consistent empty-key handling for config saves](https://github.com/ikostan/SkyLockAssault/issues/1145)
- [#1146 – [FEATURE] Use BulletResource as the single source for weapon tuning](https://github.com/ikostan/SkyLockAssault/issues/1146)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** enhancement, testing, refactoring, mechanics, GUT

### Purpose

This PR covers the last High and both Medium findings of Region 2 (#617) that were still open. After it, only the two Low tasks (#1149, #1150) remain in #617. The two parts touch different files.

**Part A: Consistent empty-key handling for config saves (#1145).** This is the High finding "Inconsistent encryption failsafe".

Four code paths save `settings.cfg`, and only `Globals._save_settings()` handled an empty encryption key. It saved plaintext. Input mappings, the last input device and audio volumes called `save_encrypted_pass()` with the empty key.

The issue expected those three saves to fail. They don't: Godot 4.7.1 accepts an empty password and writes a normal `GDEC` file, keyed by the MD5 of `""`. So with an empty key:

- The file's format depended on which manager saved last: plaintext after a gameplay save, a "hollow" encrypted file after any other save.
- Once a real key returned, a hollow file failed its MD5 check. Since #1144 that moves the file to `.corrupt` and resets every setting.
- With an empty key, an existing properly encrypted file was decrypted with the MD5 of `""`, failed, and was moved to `.corrupt` the same way.

An empty key is rare: `_get_encryption_key()` returns one only when the salt is empty, and production builds crash on the uninjected placeholder. Part A makes that rare case behave the same everywhere and never lose the file.

**Part B: Use BulletResource as the single source for weapon tuning (#1146).** These are the Medium findings "Shared template mutation" and "Two sources for weapon tuning".

Weapon tuning existed in two places with different defaults:

| Resource         | `fire_rate` | `damage`      | Used for                                   |
|------------------|-------------|---------------|--------------------------------------------|
| `BulletResource` | 0.15        | `int` 10      | Firing cooldown and hits                   |
| `WeaponResource` | 0.1         | `float` 10.0  | Only copied and clamped in `switch_to()`   |

`Weapon.switch_to()` copied the config's values into `WeaponResource`, clamped them there, and wrote them back to `current_weapon.config`. For a bullet without its own config, that's the shared `default_bullet.tres`, so equipping a weapon wrote into a resource every default bullet uses. No other production code read the `WeaponResource` fields.

---

## Key Changes

### Part A: Consistent empty-key handling for config saves (#1145)

#### 1. One save helper (`globals.gd`)

- **New `save_config(config, path) -> int`:** saves with `save_encrypted_pass()` when the key is set. With an empty key it saves plaintext with `ConfigFile.save()` and logs `⚠️ FAILSAFE ACTIVE: Saved in PLAINTEXT: <path>` (WARNING), or a plaintext-specific error if the write fails. Returns the save error.
- **All four save paths use it:**

| Save path         | Location                            |
|-------------------|-------------------------------------|
| Gameplay settings | `Globals._save_settings()`          |
| Input mappings    | `Settings.save_input_mappings()`    |
| Last input device | `Settings.save_last_input_device()` |
| Audio volumes     | `AudioManager.save_volumes()`       |

- **Callers keep their own messages.** Each still logs its existing success and error lines, so the Playwright checks for `encrypted settings persisted successfully` are unaffected. `_save_settings()` loses its separate plaintext branch, which `save_config()` now covers.

#### 2. Encrypted files are protected when the key is empty (`globals.gd`)

- **`safe_load_config()`:** if the key is empty and the file is encrypted, it doesn't decrypt or move the file. It logs a WARNING and returns `ERR_UNCONFIGURED`.
- All four save paths already skip saving on a read error other than `ERR_FILE_NOT_FOUND`, so the file is never overwritten. The three loaders log the error and keep their defaults.
- No `.corrupt` copy is made and no reset notice is set.
- The encrypted check now runs once per load (`file_exists` and `encrypted` locals).

#### 3. Test seam (`globals.gd`)

- **New `set_test_empty_encryption_key(enabled := true)`** next to `set_test_encryption_key()`. It sets `_force_empty_key_for_tests`, which makes `ensure_encryption_key()` return `""` without regenerating a key. The cached key is left unchanged.
- Setting `save_encryption_pass = ""` couldn't simulate the failure, because `ensure_encryption_key()` regenerates the key.

#### 4. Docs

- **`Browser_DevTools_Guide_Verifying_Web_Save_Encryption.md`:** "Why This Happens" now says that Godot accepts an empty password, and that since #1145 an empty key saves readable plaintext with no `GDEC` header.
- **`globals.gd` header:** lists `save_config()` with the other shared config I/O.

### Part B: Use BulletResource as the single source for weapon tuning (#1146)

#### 1. Validation moves to `BulletResource` (`bullet_resource.gd`)

- **`fire_rate`** setter clamps to `maxf(0.01, value)`, and **`damage`** setter to `maxi(0, value)`. These are the bounds `WeaponResource` used to apply.
- Default values are unchanged (0.15, 10), and `default_bullet.tres` sets neither, so it loads the same tuning as before.
- New header and doc comments: the resource is the only source of both values, and `default_bullet.tres` is shared, so code must not write to a config at runtime.

#### 2. Mirrors removed (`weapon_resource.gd`, `weapon.gd`)

- **`WeaponResource`:** `fire_rate` and `damage` removed, with the "Tuning Properties" section. The header now says firing tuning lives in `BulletResource`.
- **`Weapon.switch_to()`:** the whole stat sync is gone: the copy from `config`, the write-back, and the `get("fire_rate")` / `get("damage")` fallback for nodes without a config. The weapon name, `available_weapons`, `current_index` and ammo handling are unchanged. Its doc comment says stats are never copied or written back.

#### 3. Tests

- **`test_weapon_firing_state.gd`:** the 7 `switch_to()` cases are rewritten, and 2 are added:

| Before                                                              | After                                                           | Now checks                                                                                      |
|---------------------------------------------------------------------|-----------------------------------------------------------------|-------------------------------------------------------------------------------------------------|
| `test_switch_copies_direct_stats_without_replacing_shared_resource` | `test_switch_keeps_shared_resource_and_node_stats`              | Same `WeaponResource`, name, index and ammo; node stats not rewritten                           |
| `test_switch_updates_stats_again_for_next_weapon`                   | `test_switch_to_next_weapon_updates_name_and_index`             | Second weapon's name and index; its node stats unchanged                                        |
| `test_switch_without_optional_stats_preserves_resource_values`      | `test_switch_without_optional_stats_still_equips`               | Equips with the "Machine Gun" fallback name                                                     |
| `test_switch_with_only_fire_rate_preserves_damage`                  | `test_switch_with_only_fire_rate_updates_name_and_index`        | Index 1, name, `weapon_swapped` signal                                                          |
| `test_switch_with_only_damage_preserves_fire_rate`                  | `test_switch_with_only_damage_updates_name_and_index`           | Index 1, name, `weapon_swapped` signal                                                          |
| `test_switch_applies_resource_bounds_to_imported_stats`             | `test_switch_to_bullet_uses_resource_bounds`                    | A bullet with 0.0 / -5 fires with 0.01 / 0, clamped by `BulletResource`                         |
| `test_switch_to_configured_bullet_synchronizes_shared_stats`        | `test_switch_to_configured_bullet_uses_its_own_config`          | The firer's own config values after the swap                                                    |
| _(new)_                                                             | `test_switch_leaves_default_bullet_config_unchanged`            | In the tree, a config-less bullet uses `default_bullet.tres`, which stays 0.15 / 10 after swaps |
| _(new)_                                                             | `test_two_firers_sharing_one_config_stay_unchanged_after_swaps` | Two controllers share one config through several swaps; values unchanged                        |

- **`test_bullet_resource.gd`:** 4 new cases: `fire_rate` below 0.01 clamps (0.0, -1.0, 0.005), negative `damage` clamps to 0 (-1, -50), valid values including both bounds are kept, and `default_bullet.tres` loads 0.15 / 10.
- **`test_weapon_resource.gd`:** 1 new case: `WeaponResource` has no `fire_rate` or `damage` property.
- The mock weapon classes (`TunedWeapon`, `RateOnlyWeapon`, `DamageOnlyWeapon`) stay. The ammo and `weapon_fired` cases are unchanged.

---

## Design Decisions

### Part A (#1145)

- **`ERR_UNCONFIGURED` for "no key".** It isn't `OK`, `ERR_FILE_NOT_FOUND`, or a corruption code, so every caller takes its existing "read failed, don't save" path, and the #1144 move to `.corrupt` is never reached.
- **The plaintext warning is logged only after a successful write.** The issue's sketch logged it before saving. A failed write now logs a plaintext-specific error instead of claiming it saved.
- **A flag, not a fake key, for the test seam.** Tests can't leave a blank `save_encryption_pass` behind by accident, and the suite turns the flag off first in `after_each()`, before anything else is restored.
- **Tests that need `save_last_input_device()` use `Settings.CONFIG_PATH`.** That method has no path parameter. The suite saves the file's bytes in `before_each()` and writes them back in `after_each()`. Its write-failure case puts a directory at `CONFIG_PATH`, which the cleanup removes.
- **Log lines are read with `OS.add_logger()`.** Callers log through the `Globals` autoload, which can't be doubled, so the suite adds a small `Logger` that records what `log_message()` prints (Godot 4.5+).

### Part B (#1146)

- **Clamps in setters, as the issue proposes.** They also apply when a `.tres` loads, so a bad value in a data file is corrected on load instead of only when a weapon is equipped.
- **`maxf` / `maxi` instead of `max`.** Typed versions, so the setters don't go through `Variant`. The bounds match the removed `WeaponResource` setters.
- **Mock-stat cases kept, with new meaning.** The classes no longer feed any stat sync. They now check that a weapon node with stray `fire_rate` / `damage` properties still equips, gets its name and index, and keeps its own values.
- **The default-config case runs in the tree.** `bullet.gd` assigns `default_bullet.tres` in `_ready()`. With the controller outside the tree, the bullet's config stays null and the case would test nothing.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, using the same commands as `gut_tests.yml` and `gdunit4_tests.yml` (gdUnit4-coverage stripped, `xvfb-run`). `gdformat --check`, `gdlint` and `markdownlint-cli2` as in CI.

- **Totals:**

| State                             | GUT scripts | GUT tests | GUT asserts | gdUnit4 cases |
|-----------------------------------|-------------|-----------|-------------|---------------|
| `main` (`6940a1c`, branch base)   | 106         | 932       | 10,623      | 164           |
| Part A (`172373b`)                | 107         | 943       | 10,682      | 164           |
| Part B (`1f9a0e0`)                | 107         | 950       | 10,718      | 164           |

- **Test counts per changed file (`main` → this PR):**

| File                                  | Framework | Cases   |
|---------------------------------------|-----------|---------|
| `test_config_save_failsafe.gd` (new)  | GUT       | 0 → 11  |
| `test_weapon_firing_state.gd`         | GUT       | 14 → 16 |
| `test_bullet_resource.gd`             | GUT       | 3 → 7   |
| `test_weapon_resource.gd`             | GUT       | 10 → 11 |

- **No test cases removed.** The existing suites the issues name pass unchanged:
  - Part A: `test_full_encryption_workflow.gd`, `test_encryption_logging.gd`, `test_settings_migration.gd`, `test_error_edge_cases.gd` (GUT), `test_settings.gd`, `test_fps_settings_integration.gd` (gdUnit4).
  - Part B: `test_bullet_configuration.gd` (GUT), `test_bullet.gd`, `test_difficulty_integration.gd` (gdUnit4). `test_difficulty_integration.gd` still expects the cooldown to scale from `BulletResource.fire_rate` (0.15 × difficulty).
- **Engine output:** the same engine errors as on `main`, apart from the start-up read of `user://settings.cfg`, which depends on what earlier local runs left in `user://`.
- **Mutation checks:** the old behaviour was put back in a scratch copy, and the tests had to fail:
  - **Part A, no empty-key guard in `safe_load_config()`:** 3 fail. The encrypted file is moved to `.corrupt`.
  - **Part A, old `save_encrypted_pass()` calls in `Settings` and `AudioManager`:** 3 fail. Input, last device and audio save hollow `GDEC` files, and the coexist and upgrade cases can't read the file.
  - **Part B, `main`'s `weapon.gd`, `weapon_resource.gd` and `bullet_resource.gd`:** 3 fail: both clamp cases and the `WeaponResource` field check. The 16 `test_weapon_firing_state.gd` cases pass on `main` too: with valid values, the old write-back stored the same numbers it read, so the shared config never visibly changed. The fix is that nothing writes to it now; the field check and the clamp cases are what fail without it.
- **Engine probe (Part A):** `ConfigFile.save_encrypted_pass(path, "")` returns `OK` and writes a 60-byte `GDEC` file that `load_encrypted_pass(path, "")` reads back.
- **`tests/ci/test_salt_injection.py`:** 23 passed. `test_injection_readonly_file` fails in the sandbox and on unchanged `main`, because it runs as root, as in Part 15.
- **Not run locally:** Playwright (Part A: `volume_sliders_mutes_test.py`, `no_error_logs_test.py`; Part B: `weapon_firing_test.py`, `difficulty_flow_test.py`, `difficulty_integration_test.py`) and the benchmark. _Confirm from the PR run._
- **PR pipeline:** _confirm all jobs from the final run._
- **Benchmark:** _fill in from the PR run._ No per-frame code changes; `switch_to()` now does less work.

---

## Known Limitations / Follow-ups

- **Callers' success lines still say "Encrypted" in plaintext mode (Part A).** For example, `🔒 Encrypted input mappings saved` is logged at DEBUG right after the plaintext warning. The lines were kept as the issue asks, so log-based tests and Playwright checks still match.
- **A hollow file from an older build (Part A)** is skipped while the key is empty, and goes to `.corrupt` once a real key returns, as before. This needs a build that ran with an empty salt, which production builds can't do.
- **#1103** (Milestone 29) later moves `save_config()` into `SettingsStore`.
- **Nothing stops runtime code from writing to a shared config (Part B).** `switch_to()` no longer does, and the resource's header comment says not to, but the resource isn't read-only. `config.duplicate()` per firer, or `resource_local_to_scene`, would enforce it; #1138 can decide when it adds base weapon types.
- **#1138** (typed weapon foundation) is no longer blocked by #1146. Its description already notes that this PR removes the stat sync.
- **#1150** edits `bullet_resource.gd` and its tests next, so it should be rebased on this PR.

---

## Reviewer's Guide

### File-Level Changes

| Change                         | Details                                                                                                                                                        | Files                                                                                                                                            |
|--------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| A: One save helper.            | <ul><li>`save_config()`: encrypted with a key, plaintext without one.</li><li>All four save paths use it; their log lines are unchanged.</li></ul>             | `scripts/core/globals.gd`<br/>`scripts/core/settings.gd`<br/>`scripts/managers/audio_manager.gd`                                                 |
| A: Empty-key load guard.       | <ul><li>`safe_load_config()` returns `ERR_UNCONFIGURED` for an encrypted file with an empty key, without decrypting or moving it.</li></ul>                    | `scripts/core/globals.gd`                                                                                                                        |
| A: Test seam.                  | <ul><li>`set_test_empty_encryption_key()` forces an empty key without touching the cached one.</li></ul>                                                       | `scripts/core/globals.gd`                                                                                                                        |
| A: Tests.                      | <ul><li>11 GUT cases.</li><li>`CONFIG_PATH` bytes saved and restored.</li><li>Log lines read with `OS.add_logger()`.</li></ul>                                 | `test/gut/test_config_save_failsafe.gd`                                                                                                          |
| A: Docs.                       | <ul><li>Hollow-encryption note corrected.</li></ul>                                                                                                            | `files/docs/Browser_DevTools_Guide_Verifying_Web_Save_Encryption.md`                                                                             |
| B: Validation in the resource. | <ul><li>`fire_rate` and `damage` setters clamp in `BulletResource`.</li></ul>                                                                                  | `scripts/resources/bullet_resource.gd`                                                                                                           |
| B: Mirrors removed.            | <ul><li>`WeaponResource.fire_rate` / `damage` removed.</li><li>`switch_to()` stat sync, write-back and fallback removed.</li></ul>                             | `scripts/resources/weapon_resource.gd`<br/>`scripts/entities/weapon.gd`                                                                          |
| B: Tests.                      | <ul><li>7 `switch_to()` cases rewritten, 2 added.</li><li>4 `BulletResource` cases and 1 `WeaponResource` case added.</li><li>No test cases removed.</li></ul> | `test/gut/test_weapon_firing_state.gd`<br/>`test/gut/test_bullet_resource.gd`<br/>`test/gut/test_weapon_resource.gd`                             |
| Milestone note.                | <ul><li>This note.</li></ul>                                                                                                                                   | `files/docs/milestones/27/Part_16_Consistent_empty-key_handling_for_config_saves_&_use_BulletResource_as_the_single_source_for_weapon_tuning.md` |

### Assessment against linked issues

| Issue                                                   | Objective                                                                           | Addressed | Explanation                                                                              |
|---------------------------------------------------------|-------------------------------------------------------------------------------------|-----------|------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | All four save paths use `save_config()`                                             | ✅         | No other `save_encrypted_pass()` or `ConfigFile.save()` call left in `scripts/`.         |
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | With an empty key, new files save as plaintext for every section                    | ✅         | Each path tested alone and all four together.                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | An existing encrypted file is never overwritten, renamed or deleted                 | ✅         | Load and all four saves leave it byte-identical; no `.corrupt`, no notice.               |
| <https://github.com/ikostan/SkyLockAssault/issues/1145> | Behavior with a valid key is unchanged                                              | ✅         | Full GUT and gdUnit4 runs pass unchanged.                                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1146> | `BulletResource` is the only source of `fire_rate` and `damage`, and validates them | ✅         | Setters clamp; clamp, bound and `.tres` cases added.                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1146> | `WeaponResource` no longer has those fields                                         | ✅         | Field check added.                                                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1146> | `switch_to()` no longer changes any `BulletResource`                                | ✅         | Write-back removed; default and shared-config cases check the values.                    |
| <https://github.com/ikostan/SkyLockAssault/issues/1146> | Firing rate, damage and difficulty scaling stay the same in the game                | ⏳         | Defaults unchanged and gdUnit4 difficulty test passes; confirm Playwright on the PR run. |
| Both                                                    | All GUT, gdUnit4, Playwright, CI script and lint jobs pass, no cases removed        | ⏳         | GUT, gdUnit4, lint and `tests/ci` pass locally; confirm Playwright on the PR run.        |
| Both                                                    | The PR's milestone note is added                                                    | ✅         | This note.                                                                               |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1145 and #1146 and set their scope.
- Asked for the next Milestone 27 tasks, to add a second issue to this PR, and to work through #1145 and #1146 one at a time.
- Created the `consistent-empty-key-handling-for-config-saves` branch.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Planning**
    - Picked #1145 as next from the Part 15 follow-ups, and proposed pairing it with #1146 (no shared files; together they close Region 2's High and Medium findings).
    - Confirmed that #1138's description already accounts for the removed stat sync.
  - **Verification**
    - Found that Godot accepts an empty password, so the three saves wrote hollow files instead of failing as #1145 said.
    - Ran GUT, gdUnit4, `tests/ci` and the linters locally with the CI commands, on `main` and after each part, and mutation-tested the new and rewritten tests.
    - Wrote this note.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
