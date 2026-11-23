<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Bindings API: rebind/reset with a bindings_changed signal

---

## PR Summary

**Title:** Bindings api rebindreset with a bindings changed signal  
**PR:** [#1252](https://github.com/ikostan/SkyLockAssault/pull/1252)  
**Branch:** `bindings-api-rebindreset-with-a-bindings_changed-signal` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1102 – [TASK] Bindings API: rebind/reset with a bindings_changed signal](https://github.com/ikostan/SkyLockAssault/issues/1102)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `FEATURE`

### Purpose

The fifth part of #620 (Region 5: Gameplay Entities), found in the #616 (Region 1) review and deferred from PR #1098. Key bindings had no owner API:

- `input_remap_button.gd` and `key_mapping.gd` edited `InputMap` directly.
- `MainScene._process()` called `Settings.has_unbound_critical_actions_for_current_device()` every frame.
- `key_mapping.gd` reached into the current scene to call `MainScene.clear_unbound_warning()`.
- `settings.gd` repeated the "is this a keyboard or gamepad event" check in four places, although `InputEventCodec.get_event_device_type()` already does it.

After this PR, `Settings` is the one place that changes bindings for the UI, and it announces every change with a new `bindings_changed` signal. `MainScene` reacts to that signal instead of polling every frame. This also fixes the #621 (Region 6) findings "remap logic spread across UI files" and "key_mapping → MainScene coupling", and removes the per-frame poll that #625 (Performance Validation, Part 2) measures.

The branch also carries the reworked issue and PR templates and a refreshed local CI guide (Key Changes 6 and 7).

---

## Confirm-first results

- **Blockers closed.** #1101 (Part 22) and #1148 are closed; PR #1250 (Part 25) is merged; `main` at `c312188`.
- **Issue line numbers were current.** `input_remap_button.gd` (200, 230) and `key_mapping.gd` (123, 131, 150, 194) matched the issue.
- **The poll did more than the issue lists.**
  - It also reacted to device switches: switching Key Mapping to a device with an unbound critical action showed the warning on the next frame. Listening only to `bindings_changed` would drop that.
  - `MainScene` is pausable, and Key Mapping is opened from the pause menu, so the poll never ran while the player was in Key Mapping. The warning appeared on resume. Checking on the signal right away would play the 4-second warning behind the pause menu, where it would expire unseen.
- **Automatic conflict unbinding would change behavior.** When no Key Mapping menu is open, `InputRemapButton` applies a remap without the conflict dialog and leaves other actions alone. `test_finish_remap_invalid_index` (gdUnit4) relies on this: it binds `A` to a test action while `move_left` also uses `A`.
- **One existing test called the removed method.** `test_process_script_execution_time` called `MainScene._process()` 60 times.
- **Baseline on `main`:** full GUT suite 1,197/1,197 (117 scripts).

---

## Key Changes

### 1. Bindings API (`settings.gd`)

- New `bindings_changed` signal.
- New `rebind(action, event, unbind_from: Array[String] = [])`:
  - Removes the exact input from each action in `unbind_from` first. Unknown action names are skipped.
  - Replaces the action's first binding for the event's device (keyboard or gamepad), as the remap button shows it, and keeps the other device's binding.
  - Works for any action in `InputMap`, not only `Settings.ACTIONS`.
  - Ignores a `null` event, an unknown action or a non-keyboard/gamepad event (logged as a warning, no signal).
  - Doesn't save; the caller saves with `save_input_mappings()`, as before.
  - Emits `bindings_changed` once, after the whole change.
- `reset_to_defaults(device_type)` now emits `bindings_changed` after it saves. Its device guard uses `INPUT_DEVICES`.
- `_remove_event_from_conflicts()` is reused by `rebind()` and skips unknown actions.

### 2. One device check (`settings.gd`)

- `_add_missing_defaults()`, `reset_to_defaults()`, `get_pause_binding_label_for_device()` and `has_unbound_critical_actions_for_current_device()` use `InputEventCodec.get_event_device_type()`. No new helper was added.

### 3. UI routes through Settings (`input_remap_button.gd`, `key_mapping.gd`)

- `InputRemapButton._input()` applies a remap with `Settings.rebind(action, new_event)`. `erase_old_event()` is removed; nothing else called it.
- `_on_conflict_confirmed()` calls `Settings.rebind(action, event, current_conflicts)`. It now saves once, through `finish_remap()`; before, it saved twice.
- `_on_reset_pressed()` no longer calls into `MainScene`. Both `main.clear_unbound_warning()` calls are gone.
- `scripts/core/input_layout_migration.gd` keeps its direct `InputMap` calls, as the issue specifies (out of scope).

### 4. Event-driven unbound-controls warning (`main_scene.gd`)

- `_process()` is removed. `MainScene` no longer processes every frame.
- `_check_unbound_controls()` shows the critical warning once, if a critical action has no binding for the current device. It runs:
  - at level start, at the end of `_ready()`;
  - on `Settings.bindings_changed`, which first clears the once-per-session flag;
  - on `Settings.input_device_changed`, which keeps the flag.
- While the scene is paused, a check is marked pending and runs on `NOTIFICATION_UNPAUSED`.
- Connects in `_enter_tree()` and disconnects in `_exit_tree()`, because the `Settings` autoload outlives the level.
- `clear_unbound_warning()` is removed; `_on_bindings_changed()` replaces it.

### 5. Tests

**No test case was removed.**

- **`test/gut/test_main_scene_parallax_and_performance.gd`:** `test_process_script_execution_time` is rewritten. It checks that `MainScene` has no `_process()` and isn't processing, and times the event-driven check against the same 2 ms bound.
- **New `test/gut/test_bindings_api.gd` (27 tests):**
  - `rebind()`: same-device replacement, a device with no binding, listed and unlisted conflicts, invalid input, unmanaged actions (BIND-01 to BIND-06).
  - `reset_to_defaults()`: emits once, ignores an unknown device (RESET-01, RESET-02).
  - Device checks through `InputEventCodec` (DEV-01).
  - UI: no UI script calls `InputMap.action_add_event`, `action_erase_event` or `action_erase_events`; `key_mapping.gd` has no `MainScene`, `current_scene` or `clear_unbound_warning` in its code; the conflict dialog and the Reset button go through `Settings` (UI-01 to UI-04).
  - `MainScene`: no warning when bound, warning at level start, fixed vs. still unbound, no repeat without a binding change, device switch, deferred while paused, fixed while paused, disconnect and reconnect (MS-01 to MS-09).
- **CodeRabbit's tests (`585026e`, 5 tests):**
  - BIND-07: an axis moved with listed conflicts, including one that doesn't exist; listeners see the finished change.
  - BIND-08: a second keyboard key is kept, and `rebind()` doesn't save.
  - RESET-03: a gamepad reset saves before it notifies.
  - UI-05: a direct axis remap emits once and normalizes the direction.
  - MS-10: a device switch while paused is checked against the device selected at resume.
- **RESET-03 fix (`afc45d8`):** its observer read the save with `load_encrypted_pass()`, which fails when `Globals.save_config()` falls back to plaintext. It now reads through `Globals.safe_load_config()` and checks that the observer ran once.

### 6. Issue and PR templates (not part of #1102)

- **`bug_report.md`:** adds Build, OS / Browser, Input Device, Reproducibility and Logs. Every original field stays; hints are HTML comments, so they don't appear in submitted issues.
- **`feature_request.md`:** adds Out of Scope, Testing (one line per suite) and Acceptance Criteria with the two repeated checks prefilled. A comment at the top states the one-issue-one-PR size limit.
- **`pull_request_template.md`:** follows the milestone note structure (Purpose, Key Changes, Design Decisions, Testing, Reviewer's Guide, Contributors) with a checklist of project rules. Its front matter is removed: GitHub pasted it into every PR description.
- **Lint (`c898abb`):** hints wrapped to 80 characters for MD013; MD041 is disabled in the PR template instead of adding a `#` heading to every PR description.

### 7. Local CI guide (not part of #1102)

`files/docs/Local_CI_Pipeline_for_Godot_Project_using_Docker.md` is rewritten for the current `Dockerfile` and `workspace/` scripts:

- Script paths are `/project/workspace/<script>`. `run_unit_tests.sh` no longer exists; GUT and gdUnit4 each have their own script.
- A versions table: Godot 4.7.1, gdUnit4 6.2.0, GUT 9.7.1, gdtoolkit, yamllint, markdownlint-cli2.
- `run_browser_tests.sh` arguments, `test_injection.sh` with `-p 8080:8080`, and a "Where the Tests Live" table.
- Removed: the embedded old `Dockerfile` and `run_pipeline.sh`, Godot 4.5 and gdUnit4 6.0.0, `tests/difficulty_persistence_test.py`, and an example test for a `fuel_manager.gd` that doesn't exist.

---

## Design Decisions

- **`reset_to_defaults()` keeps its name.** The issue proposes `Settings.reset(device)`. Adding it beside `reset_to_defaults()` would mean two names for one operation; renaming changes `key_mapping.gd` and 13 lines in the GUT tests. Sourcery's linked-issue check notes the different name.
- **Conflicts are unbound only when listed.** `rebind()` takes `unbind_from` instead of unbinding every conflict itself, so the remap button's no-dialog path keeps today's behavior (Confirm-first).
- **`rebind()` doesn't save; `reset_to_defaults()` does.** Both keep their previous save behavior. RESET-03 pins that the reset saves before it emits, so observers read the new file.
- **`MainScene` also listens to `input_device_changed`,** to keep the warning the poll showed on a device switch.
- **Checks wait for unpause** through `NOTIFICATION_UNPAUSED`, not a `_process()` flag check, so nothing runs per frame.
- **Signals connect in `_enter_tree()`,** paired with `_exit_tree()`, so a level removed from the tree and added back reconnects (MS-09).

---

## Review

- **CodeRabbit, MD013 in the three templates (`d4779e7`): fixed** in `c898abb`.
- **CodeRabbit, MD041 in `pull_request_template.md`: fixed differently.** MD041 is disabled for that file; a top-level heading would add a redundant title to every PR description. @ikostan replied on the thread.
- **CodeRabbit, unit test generation (`585026e`):** 5 tests, all kept. Reviewed: all pass, each catches a real change (Verification), and RESET-03's encryption-only read was fixed in `afc45d8`. Style: they use `:=` inference while the rest of the file declares types; not changed.
- **CodeRabbit, later commits:** review rate limited.
- **Sourcery:** review budget used up; its reviewer's guide and linked-issue check ran. #1102: 5 of 6 requirements met, 1 to check by hand (the suites pass; see Verification).
- **DeepSource:** grade A on `c312188...afc45d8`.
- **Qodo:** reviews paused for this account.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdlint ./scripts` and `gdformat --check ./scripts` as in CI. Markdown with markdownlint-cli2 v0.24.0 and `.markdownlint-cli2.yaml`.

| State                    | GUT scripts | GUT tests | GUT asserts | gdUnit4 tests |
|--------------------------|-------------|-----------|-------------|---------------|
| `main` (`c312188`, base) | 117         | 1,197     | 13,751      | 169           |
| This PR (`59e24d4`)      | 118         | 1,224     | 13,892      | 169           |

The gdUnit4 count on `main` is from Part 25. On this branch it was run at `d4779e7`; later commits change only GUT tests and docs.

- **PR CI at `59e24d4` (last code change):** all jobs pass: GUT, gdUnit4, GDScript lint and format, Markdown lint, CI infrastructure tests, the web build, both browser shards ("Core Web Flows", "CI & Security") and the desktop and web benchmarks (report only). YAML lint skipped (no workflow changes). `ec6b0d3` adds only this note.
- **Full GUT suite locally at `59e24d4`:** 1,224/1,224.
- **Restoring the old behavior:** each change below was made on its own; these tests fail:

| Change                                                   | Fails                                                                                                                                                  |
|----------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| `MainScene` ignores `input_device_changed`               | MS-06, MS-10                                                                                                                                           |
| Check runs at once while paused                          | MS-07, MS-10                                                                                                                                           |
| `bindings_changed` doesn't clear the warning flag        | MS-03, MS-04, MS-07, MS-08                                                                                                                             |
| `rebind()` ignores `unbind_from`                         | BIND-03, BIND-07, UI-03                                                                                                                                |
| `rebind()` doesn't emit                                  | BIND-01, BIND-03, BIND-07, MS-03, MS-04, MS-07, UI-03, UI-05                                                                                           |
| `rebind()` removes every binding for the device          | BIND-08                                                                                                                                                |
| `reset_to_defaults()` emits before it saves              | RESET-03                                                                                                                                               |
| `MainScene` doesn't disconnect on leaving the tree       | MS-09                                                                                                                                                  |

CodeRabbit's MS-10, BIND-08 and RESET-03 are the only tests that catch three of these, so they add real coverage.

- **GDScript lint and format:** `gdlint ./scripts` and `gdformat --check ./scripts` pass.
- **Markdown lint:** the three templates and the local CI guide report 0 issues.
- **Not run locally:** Playwright, the benchmarks and the manual itch.io checks.

---

## Known Limitations / Follow-ups

- **`load_input_mappings()` doesn't emit `bindings_changed`.** It only runs at startup, before any observer exists.
- **Local CI scripts and image, found while updating the guide (not changed):**
  - Mounting the clone on `/project` hides the gdUnit4 and GUT copies baked into the image; `run_gdunit4_unit_tests.sh` copies `addons/gdUnit4` onto itself, and `run_pipeline.sh` looks for `/opt/addons`, which the `Dockerfile` never creates.
  - Version drift from CI: the GUT script downloads 9.5.0 (CI 9.7.1), `run_pipeline.sh` falls back to gdUnit4 6.1.3 (CI 6.2.0), and the image has markdownlint-cli2 0.12.1 (CI v0.24.0).
- **PR description:** still the unfilled old template.
- **Manual itch.io checks still to do:**
  - Remapping and Reset in Key Mapping work for keyboard and gamepad.
  - The unbound-controls warning appears on resume when a critical action is left unbound, and not when it's fixed.
- **Still open from Part 24:** `test/gut/test_weapon_slot_cooldown.gd` runs in no CI job.
- **Next in #620:** #1151 (Main scene and tuning cleanup), its last part. #625 (Performance Validation, Part 2) is unblocked.

---

## Reviewer's Guide

### File-Level Changes

| Change          | Details                                                                                                                                                               | Files                                                                                                                         |
|-----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Bindings API.   | <ul><li>`bindings_changed`, `rebind()`; `reset_to_defaults()` emits after saving.</li><li>Four device checks use `InputEventCodec.get_event_device_type()`.</li></ul> | `scripts/core/settings.gd`                                                                                                    |
| UI routing.     | <ul><li>Remap and conflict confirm call `Settings.rebind()`; `erase_old_event()` removed.</li><li>No calls into `MainScene`.</li></ul>                                | `scripts/ui/components/input_remap_button.gd`<br/>`scripts/ui/menus/key_mapping.gd`                                           |
| Warning.        | <ul><li>No `_process()`; checks at level start and on the Settings signals, deferred while paused.</li></ul>                                                          | `scripts/core/main_scene.gd`                                                                                                  |
| Tests.          | <ul><li>New bindings suite; performance test rewritten.</li><li>CodeRabbit: BIND-07, BIND-08, RESET-03, UI-05, MS-10.</li></ul>                                       | `test/gut/test_bindings_api.gd`<br/>`test/gut/test_main_scene_parallax_and_performance.gd`                                    |
| Templates.      | <ul><li>Project-specific fields, testing and acceptance sections; PR template follows the milestone note.</li></ul>                                                   | `.github/ISSUE_TEMPLATE/bug_report.md`<br/>`.github/ISSUE_TEMPLATE/feature_request.md`<br/>`.github/pull_request_template.md` |
| Local CI guide. | <ul><li>Current image, `workspace/` scripts, outputs and troubleshooting.</li></ul>                                                                                   | `files/docs/Local_CI_Pipeline_for_Godot_Project_using_Docker.md`                                                              |
| Milestone note. | <ul><li>This note.</li></ul>                                                                                                                                          | `files/docs/milestones/27/Part_26_Bindings_API_rebind_reset_with_a_bindings_changed_signal.md`                                |

### Assessment against linked issues

| Issue                                                   | Objective                                                                          | Addressed | Explanation                                                                     |
|---------------------------------------------------------|------------------------------------------------------------------------------------|-----------|---------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1102> | No direct `InputMap.action_add_event` / `action_erase_event` calls in UI scripts   | ✅         | UI-01 scans every script under `scripts/ui/`.                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1102> | `main_scene._process` no longer checks bindings; the warning still appears         | ✅         | `_process()` removed; MS-02, MS-04, MS-06, MS-07, MS-10.                        |
| <https://github.com/ikostan/SkyLockAssault/issues/1102> | `key_mapping.gd` no longer calls into `main_scene`; fixing bindings clears warning | ✅         | UI-02; MS-03 and MS-08.                                                         |
| <https://github.com/ikostan/SkyLockAssault/issues/1102> | Key-mapping GUT/gdUnit4 and Playwright suites pass; no test cases removed          | ✅         | GUT, gdUnit4 and both browser shards pass in CI at `59e24d4`; no cases removed. |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1102 from the #616 (Region 1) review and moved it under #620.
- Kept the current milestone plan and chose #1102 as the next PR, with #1151 as a separate PR.
- Opened PR #1252 and committed the implementation (`d4779e7`), the templates (`cdc53a7`, `c898abb`), the RESET-03 fix (`afc45d8`) and the local CI guide (`59e24d4`).
- Started CodeRabbit's unit-test generation and replied to CodeRabbit's MD041 comment.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked #1102 and #1151 and their blockers, and recommended two PRs, #1102 first: both change the unbound-warning code in `main_scene.gd` and `input_remap_button.gd`, and #1102 blocks #625's benchmark comparison.
    - Found that the poll also covered device switches and pause, and that automatic conflict unbinding would change the remap button's no-dialog path.
  - **Templates and docs**
    - Proposed the issue and PR template changes one at a time, fixed the MD013/MD041 lint failures, and drafted the reply to CodeRabbit's MD041 comment.
    - Rewrote the local CI guide from the current `Dockerfile` and `workspace/` scripts, and listed the script problems found.
  - **Verification**
    - Ran the full GUT and gdUnit4 suites on `main` and the branch, `gdlint`, `gdformat` and markdownlint.
    - Restored eight old behaviors one at a time to confirm the tests catch each.
  - **Review**
    - Reviewed CodeRabbit's five tests: ran them, found RESET-03's encryption-only read, and proposed the fix applied in `afc45d8`.
    - Reviewed PR #1252: CI results and the bot reviews. Wrote this note.
- **@coderabbitai**
  - **Review:** MD013 in the three templates and MD041 in the PR template.
  - **Tests (`585026e`):** BIND-07, BIND-08, RESET-03, UI-05 and MS-10.
- **@sourcery-ai:** reviewer's guide and the #1102 linked-issue check (5 of 6 met, 1 by hand).
- **@deepsource-io:** grade A.
