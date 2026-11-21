<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Settings owns its input device & migration flags

---

## PR Summary

**Title:** Move input state ownership into Settings  
**PR:** [#1219](https://github.com/ikostan/SkyLockAssault/pull/1219)  
**Branch:** `settings-owns-its-state-migration-flag-and-current-input-device` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1101 – [TASK] Settings owns its state: migration flag and current input device](https://github.com/ikostan/SkyLockAssault/issues/1101)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `refactoring`, `EPIC`, `TASK`

### Purpose

From the #616 (Region 1, checkpoint 3) review: Settings kept its own state on Globals, so state mutation was not unidirectional.

- The run-once migration flags were metadata on Globals (`Globals.set_meta` / `has_meta` / `get_meta`).
- `Globals.current_input_device` was written by `settings.gd`, `ui_manager.gd` and `key_mapping.gd`.

This PR gives each value one owner, Settings, and lets consumers react to device changes through a signal. It also fixes #619's finding "ui_manager device tracking conflicts with Key Mapping": moving the mouse while Key Mapping showed "gamepad" switched the device to keyboard. #1101 is a sub-issue of #619 and blocks #1102.

---

## Confirm-first results

- **Issue line numbers were stale.** The settings.gd lines the issue cites (~101, 103, 625, 746, 779, 860, 862) have moved; the code was found by name. `ui_manager.gd` (49, 51) and `key_mapping.gd` (343, 357) matched the issue's findings.
- **A second flag used the same pattern.** `INPUT_LAYOUT_MIGRATION_KEY` (`input_layout_migrated_v3`), added after the issue was written, was also stored as Globals metadata. It moved too (Design Decisions).
- **The regression tests fail on `main`'s tracking logic.** The new suites call the new API, so they can't run against `main` as is. Instead, `_track_input_device()` was put back to `main`'s logic (keys, mouse buttons and mouse motion select keyboard, no Key Mapping check), writing through `Settings.set_input_device()`. 2 of 1,127 tests failed, with 4 failed asserts:

| Test                                           | Fails with `main`'s logic                                                                                                              |
|------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| `test_uidev_04_mouse_motion_keeps_device`      | Mouse motion switches gamepad to keyboard and emits `input_device_changed`.                                                            |
| `test_uidev_06_key_mapping_open_keeps_gamepad` | With Key Mapping open on Gamepad, mouse motion sent through `Input.parse_input_event()` switches to keyboard, and so does a key press. |

- **`gdlint` blocked the issue's API as written.** On `main`, `settings.gd` already had exactly 20 public methods, gdlint's `max-public-methods` limit, and 962 of the allowed 1,000 lines. The four new public methods took it to 24 methods and 1,019 lines. @ikostan decided to split the file in this PR (Design Decisions).

---

## Key Changes

### 1. Settings owns the input device (`settings.gd`)

- New private `_current_input_device` (default `keyboard`) and `INPUT_DEVICES` constant (`["keyboard", "gamepad"]`).
- `get_input_device()` returns it.
- `set_input_device(device)` is the only writer. An unknown value is logged (`Ignoring unknown input device: '<value>'`) and ignored. A real change emits the new `input_device_changed(device)` signal; setting the current device emits nothing.
- `set_input_device()` does not save. Key Mapping, where the player picks the device, still calls `save_last_input_device()`. The on-disk key `[input] last_input_device` is unchanged.
- `load_last_input_device()` goes through `set_input_device()`. A missing, unreadable or unknown saved value selects `keyboard`, as before. A non-`String` value now also falls back to `keyboard`; on `main` it would have failed the typed assignment.
- `get_pause_binding_label()` and `has_unbound_critical_actions_for_current_device()` read the private field.

### 2. Settings owns the migration flags (`settings.gd`)

- New `MIGRATION_KEYS` constant (`settings_migrated_v2`, `input_layout_migrated_v3`) and private `_completed_migrations: Dictionary[String, bool]`.
- `is_migration_done(key)` reads a flag; private `_mark_migration_done(key)` sets it. Both migrations mark themselves, and `_ready()` checks `is_migration_done()`. The duplicate `Globals.set_meta()` in `_ready()` after `_migrate_legacy_unbound_states()` is gone.
- `load_input_mappings()` restores each flag stored as `true` under `[meta]`, and `save_input_mappings()` writes each done flag back. **The `[meta]` keys on disk are unchanged.** As on `main`, a flag missing from the config leaves the in-memory flag as it is. A non-`bool` value is ignored.
- New test-only helper `set_migration_done_for_test(key, done)`, next to `set_needs_save_for_test()`.

### 3. Globals no longer holds the device (`globals.gd`)

`current_input_device` and its doc lines are removed. No read-only forwarder was needed: every reader moved to `Settings.get_input_device()`. The header no longer lists the device among Globals' duties.

### 4. UiManager device tracking (`ui_manager.gd`)

- New static `_device_for_event()`: keys and mouse buttons → `keyboard`, joypad buttons and axes → `gamepad`, anything else (**including mouse motion**) → `""`.
- `_track_input_device()` returns early when the event has no device or the device is already current, then returns when the Key Mapping screen is open (a node in the `key_mapping_menu` group, the same group `input_remap_button.gd` uses to find the screen). Otherwise it calls `Settings.set_input_device()`.
- As on `main`, a switch from UiManager is not saved.

### 5. Key Mapping (`key_mapping.gd`)

- `_ready()` sets the toggles from `Settings.get_input_device()`.
- `_on_keyboard_toggled()` and `_on_gamepad_toggled()` call a new `_select_device(device)`: `Settings.set_input_device()`, `Settings.save_last_input_device()`, refresh the remap buttons, play the check sound, log. Same steps as before, in the same order.

### 6. Event helpers moved to `InputEventCodec` (new `input_event_codec.gd`)

- `serialize_event()`, `deserialize_event()`, `events_match()`, `_key_identity()`, `get_event_device_type()`, `get_event_label()` and `KEY_MODIFIER_TOKENS` moved from `settings.gd` unchanged, as static functions of `class_name InputEventCodec`. Only `static` was added to the functions that were instance methods.
- Every caller uses `InputEventCodec.…`: `settings.gd`, `input_layout_migration.gd`, `input_remap_button.gd`, `key_mapping.gd`, `main_scene.gd` and 9 test suites. No wrappers stay on Settings.
- `input_layout_migration.gd`: `count_bindings_for_device(action, device)` and `_remove_legacy_extras()` no longer take the `settings` argument, which they used only for the moved helpers (gdlint `unused-argument`). `migrate(settings)` keeps it for `get_conflicting_actions()`.
- **`settings.gd`: 962 → 740 lines, 20 → 19 public methods.**

### 7. Tests

**No test case was removed.**

- **New `test/gut/test_settings_owned_state.gd` (10 tests, 2 of them added by CodeRabbit, see Review fixes).** It saves and restores the InputMap, device and both flags around each test.
  - DEV-01 to 04: a change sets the device and emits once with the device; the current device emits nothing; `mouse`, `""` and `Gamepad` are rejected without a signal; Globals has no `current_input_device`.
  - DEV-05: `get_pause_binding_label()` follows the current device.
  - FLAG-01: both migrations set their flags in Settings and leave no Globals metadata.
  - FLAG-02: an existing save with both `[meta]` keys loads both flags, and saving writes them back under the same keys.
  - FLAG-03: a missing key, `false`, `"yes"` and `1` don't mark the migration done.
  - FLAG-04: a flag that isn't done is not written.
  - FLAG-05: a config that sets only one flag marks that migration done and keeps one that already ran.
- **New `test/gut/test_ui_manager_input_device.gd` (11 tests, 3 of them added by CodeRabbit).**
  - UIDEV-01 to 05: key press → keyboard; joypad button and axis → gamepad; mouse click → keyboard; mouse motion changes nothing and emits nothing; input from the current device emits nothing.
  - UIDEV-06 (the #619 regression): with Key Mapping open on Gamepad, mouse motion through `Input.parse_input_event()` and a key press leave the device on gamepad and the toggle on Gamepad.
  - UIDEV-07: the Key Mapping toggle still switches the device while the screen is open.
  - UIDEV-08: tracking resumes once the screen is freed.
  - UIDEV-09: an event from no device (an `InputEventAction`) changes nothing.
  - UIDEV-10: a switch from UiManager is not saved; loading the saved device undoes it and emits once.
  - UIDEV-11: a saved device that isn't a `String` falls back to keyboard.
  - UIDEV-07 and UIDEV-10/11 write the real `settings.cfg`; the suite backs it up and `after_each()` restores it (see Review fixes).
- **New `test/gut/test_input_event_codec.gd` (4 tests, added by CodeRabbit).**
  - CODEC-01 / 02: gamepad buttons and axes round-trip with their device and direction, and matching compares each field.
  - CODEC-03: malformed gamepad strings are rejected (9 cases).
  - CODEC-04: a mouse click is not a binding; this pins that `events_match()` only compares key and gamepad events.
- **Migrated to the new API (9 suites):** `Globals.current_input_device` → `Settings.get_input_device()` / `set_input_device()`, and `Globals.set_meta` / `has_meta` / `remove_meta` on the flag keys → `Settings.set_migration_done_for_test()` / `is_migration_done()`. In `test_input_layout_menu_gameplay_split.gd`, `_set_flag()` now calls the helper.
- **Codec rename (9 suites):** `Settings.<helper>` → `InputEventCodec.<helper>`, doc comments included.

### Review fixes

#### CodeRabbit

- **UIDEV-07 restores `settings.cfg` from teardown (`c024f49`):** the test wrote the in-memory device back to `Settings.CONFIG_PATH` at the end of its body. CodeRabbit's reason, that a failed assert stops the test, is wrong for GUT (checked with a probe: the body keeps running). Two real problems remained: writing back the in-memory device changed the file even when the test passed, and a script error in the body would skip the line. The test now backs up the file before the toggle, and `after_each()` restores it or removes it if it didn't exist. Checked against a stable `settings.cfg`: the old version changed the file whether the test passed or hit an injected script error; the new one leaves it unchanged in both cases.
- **Outside the diff, `test_key_mapping_load_regression.gd` and `test_settings_migration.gd` (`c35a2d8`):** the PR's first commit still had the old versions of these two suites. Line 46 assigned `Globals.current_input_device`, which raised a script error in `before_each()` (the test still passed, without its gamepad precondition), and lines 18–19 removed Globals metadata, which no longer resets the legacy flag. Both use the Settings API now; the full suite has no script errors.
- **Outside the diff, four `Settings.get_event_label()` callers in the remap suites (`ef8d022`):** already fixed when the review arrived; it ran on the first commit (`4cc5dba`).
- **Added tests (`36c200b`):** CodeRabbit committed 9 tests (DEV-05, FLAG-05, UIDEV-09 to 11, CODEC-01 to 04). All pass, and each fails when the code it covers is broken (Verification). They were given IDs and doc comments like the rest of their suites, and `test_input_event_codec.gd` the usual header.

#### Sourcery

- **Tests still use removed Globals state** (Medium): same two suites as CodeRabbit's outside-diff finding, fixed in `c35a2d8`. The lines it anchored on in `test_settings_owned_state.gd` (87–88, 25–26) were left as they are: DEV-04 checks on purpose that Globals has no device field, and the setup already uses the Settings API.

---

## Design Decisions

- **The v3 layout flag moved too.** #1101 names only `LEGACY_MIGRATION_KEY`, but `INPUT_LAYOUT_MIGRATION_KEY` was written the same way. Leaving it would keep the Settings → Globals coupling the issue removes. Both flags now share one storage and one save/restore loop over `MIGRATION_KEYS`.
- **The event helpers were split out in this PR.** The issue's API pushes `settings.gd` past gdlint's 20-public-method and 1,000-line limits. Raising the limits would hide the code smell this milestone is fixing. A separate prerequisite PR was considered; @ikostan chose to do the split here. The moved helpers work on one event at a time and hold no Settings state, so they fit a static helper like `input_defaults.gd`.
- **`class_name InputEventCodec` instead of a preload.** `input_defaults.gd` is preloaded by Settings, but the codec has about 75 call sites across scripts and tests. A global class name avoids a preload constant in every file.
- **`set_input_device()` does not save.** If it did, UiManager would write `settings.cfg` on every device switch, and the saved value would follow the last device used rather than the Key Mapping choice. PR #1098 removed a per-tick settings save for the same reason. Key Mapping saves explicitly, as before.
- **Key Mapping is detected through its existing group.** `key_mapping.gd` already joins `key_mapping_menu` and `input_remap_button.gd` already looks it up, so no new flag or signal was added. UiManager checks the group only when an event would change the device.
- **Mouse buttons still select keyboard.** The issue asks to stop switching on mouse motion only. A click is a deliberate input, and the keyboard device covers mouse use.
- **No Globals forwarder.** The issue allowed a read-only `Globals.current_input_device` forwarder if needed. Every reader was migrated, so none was added.

---

## Verification

Run locally with Godot 4.7.1-stable and GUT 9.7.1, set up as `gut_tests.yml` does. `gdformat --check` and `gdlint` as in CI.

| State                    | GUT scripts | GUT tests | GUT asserts |
|--------------------------|-------------|-----------|-------------|
| `main` (`8ecdd34`, base) | 112         | 1,111     | 13,355      |
| This PR                  | 115         | 1,136     | 13,466      |

- **No test cases removed.**
- **Full GUT suite:** 1,136/1,136, from an empty user data folder, with no script errors.
- **Breaking the fix:** `main`'s tracking logic in `_track_input_device()` fails UIDEV-04 and UIDEV-06 (Confirm-first results).
- **Breaking the code CodeRabbit's tests cover:** each change below makes at least one of them fail.

| Change to the code                                     | Fails                     |
|--------------------------------------------------------|---------------------------|
| Loading clears flags missing from the config           | FLAG-05                   |
| `get_pause_binding_label()` ignores the current device | DEV-05                    |
| Events from no device count as keyboard                | UIDEV-09                  |
| `set_input_device()` emits without a change            | UIDEV-10, DEV-02          |
| UiManager saves the device it detects                  | UIDEV-10                  |
| An invalid saved value keeps the current device        | UIDEV-11                  |
| Gamepad button serialization drops the device          | CODEC-01                  |
| Axis matching ignores the device                       | CODEC-02                  |
| Axis strings accept extra fields                       | CODEC-03                  |

- **GDScript lint and format:** `gdlint ./scripts` and `gdformat --check ./scripts` pass.
- **Not run locally:** gdUnit4 (no suite references the changed APIs), Playwright, the benchmark and the manual itch.io check. The PR pipeline didn't run on CodeRabbit's commit `36c200b`. PR run: _fill in after CI._

---

## Known Limitations / Follow-ups

- **Nothing listens to `input_device_changed` yet.** The signal is in place, but no consumer was changed to use it; that wasn't part of #1101.
- **Settings is at 19 of 20 public methods.** #1102 adds `rebind()` and `reset()`, which would take it to 21, so #1102 needs another small cut (for example, moving the test-only helpers or the device-type checks it already plans to extract).
- **Manual itch.io check** still to do: with Key Mapping open on Gamepad, moving the mouse keeps Gamepad selected, and the pause label and Unbound Controls warning follow the selected device.

---

## Reviewer's Guide

### File-Level Changes

| Change            | Details                                                                                                                                                     | Files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
|-------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Device ownership. | <ul><li>Private device field, `get_input_device()`, `set_input_device()`, `input_device_changed`.</li><li>`Globals.current_input_device` removed.</li></ul> | `scripts/core/settings.gd`<br/>`scripts/core/globals.gd`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Migration flags.  | <ul><li>`_completed_migrations`, `is_migration_done()`, `MIGRATION_KEYS`; same `[meta]` keys.</li><li>`set_migration_done_for_test()`.</li></ul>            | `scripts/core/settings.gd`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Device tracking.  | <ul><li>No switch on mouse motion or while Key Mapping is open.</li><li>Writes through Settings.</li></ul>                                                  | `scripts/managers/ui_manager.gd`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Key Mapping.      | <ul><li>Reads and sets the device through Settings; `_select_device()`.</li></ul>                                                                           | `scripts/ui/menus/key_mapping.gd`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Event codec.      | <ul><li>Six helpers and `KEY_MODIFIER_TOKENS` moved to `InputEventCodec`.</li><li>Callers updated; unused `settings` arguments dropped.</li></ul>           | `scripts/core/input_event_codec.gd`<br/>`scripts/core/input_event_codec.gd.uid`<br/>`scripts/core/settings.gd`<br/>`scripts/core/input_layout_migration.gd`<br/>`scripts/ui/components/input_remap_button.gd`<br/>`scripts/ui/menus/key_mapping.gd`<br/>`scripts/core/main_scene.gd`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Tests.            | <ul><li>Three new suites, 25 tests (9 added by CodeRabbit).</li><li>9 suites migrated to the device and flag API.</li><li>9 suites renamed to `InputEventCodec`.</li></ul>            | `test/gut/test_settings_owned_state.gd`<br/>`test/gut/test_settings_owned_state.gd.uid`<br/>`test/gut/test_ui_manager_input_device.gd`<br/>`test/gut/test_ui_manager_input_device.gd.uid`<br/>`test/gut/test_input_event_codec.gd`<br/>`test/gut/test_input_event_codec.gd.uid`<br/>`test/gut/test_input_layout_menu_gameplay_split.gd`<br/>`test/gut/test_deserialize_event_key_tokens.gd`<br/>`test/gut/test_settings_unbound_scenarios.gd`<br/>`test/gut/test_settings_ec.gd`<br/>`test/gut/test_events_match_meta.gd`<br/>`test/gut/test_integration_key_mapping.gd`<br/>`test/gut/test_main_menu_audio.gd`<br/>`test/gut/test_deduplication_on_migration.gd`<br/>`test/gut/test_blank_key_labels_on_missing_config.gd`<br/>`test/gut/test_device_toggle_audio_regression.gd`<br/>`test/gut/test_input_remap_button.gd`<br/>`test/gut/test_key_mapping_load_regression.gd`<br/>`test/gut/test_settings_migration.gd`<br/>`test/gut/test_input_remap_button_device_aware.gd`<br/>`test/gut/test_input_remap_ec.gd` |
| Milestone note.   | <ul><li>This note.</li></ul>                                                                                                                                | `files/docs/milestones/27/Part_22_Settings_owns_its_input_device_&_migration_flags.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

### Assessment against linked issues

| Issue                                                   | Objective                                                                               | Addressed | Explanation                                                                                       |
|---------------------------------------------------------|-----------------------------------------------------------------------------------------|-----------|---------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1101> | Nothing calls `Globals.set_meta(LEGACY_MIGRATION_KEY, ...)`                             | ✅         | The v3 flag was moved too; pinned by FLAG-01.                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1101> | No script outside Settings writes the input device                                      | ✅         | UiManager and Key Mapping call `Settings.set_input_device()`; the Globals field is gone (DEV-04). |
| <https://github.com/ikostan/SkyLockAssault/issues/1101> | `set_input_device(device)` and `input_device_changed(device)`                           | ✅         | DEV-01 to 03.                                                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1101> | Existing saves still load (same `[meta]` key and device key on disk)                    | ✅         | FLAG-02, SCN-16, MIG-02, MIG-12 and EC-09.                                                        |
| <https://github.com/ikostan/SkyLockAssault/issues/1101> | Tests updated for the new API; no test cases removed                                    | ✅         | 1,111 → 1,136 tests, all passing.                                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1101> | Mouse motion with Key Mapping on "gamepad" doesn't switch to keyboard (regression test) | ✅ / ⏳     | UIDEV-06 fails with `main`'s logic and passes now; manual itch.io check still to do.              |
| <https://github.com/ikostan/SkyLockAssault/issues/1101> | Milestone note added                                                                    | ✅         | This note.                                                                                        |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1101 from the #616 (Region 1) review; the refactor was deferred from PR #1098.
- Made it a sub-issue of #619 and moved it to Milestone 27.
- Decided to split the event helpers out of `settings.gd` in this PR when gdlint's limits blocked the issue's API.
- Opened #1219 and applied the review fixes (`ef8d022`, `c024f49`, `c35a2d8`).

### Bots / AI contributions

- **@coderabbitai**
  - Review: UIDEV-07 restore from teardown, applied with a different reason (see Review fixes).
  - Outside-diff review: the two suites still using Globals state and the four `Settings.get_event_label()` callers.
  - Added 9 tests (`36c200b`): DEV-05, FLAG-05, UIDEV-09 to 11, CODEC-01 to 04.
- **@sourcery-ai**
  - Review: tests still using removed Globals state, applied (see Review fixes).
- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked the issue against `main`: found the stale line numbers and the v3 layout flag stored on Globals the same way.
    - Ran the baseline GUT suite on `main` (1,111/1,111) and found that `settings.gd` was already at gdlint's public-method limit.
  - **Implementation**
    - Wrote the Settings device and flag API, the UiManager tracking fix and the Key Mapping changes.
    - Moved the event helpers to `InputEventCodec` and updated every caller.
    - Migrated 9 test suites to the new API and wrote the two new suites (16 tests).
  - **Verification**
    - Ran the full GUT suite from an empty user folder (1,127/1,127, same error output as `main`), `gdformat` and `gdlint`.
    - Put `main`'s tracking logic back to confirm UIDEV-04 and UIDEV-06 catch the bug.
    - Wrote this note.
  - **Review fixes**
    - Checked CodeRabbit's UIDEV-07 finding: a probe showed a failed GUT assert doesn't stop the test, but the file was still changed on every run. Wrote the backup-and-restore fix and checked it against a stable `settings.cfg`, with and without an injected script error.
    - Found the two suites still using Globals state on the PR branch, fixed them, and checked the outside-diff findings against the pushed commits.
    - Reviewed CodeRabbit's 9 tests (full suite, `gdlint`, 9 code breaks), and gave them IDs, doc comments and the codec suite's header.
