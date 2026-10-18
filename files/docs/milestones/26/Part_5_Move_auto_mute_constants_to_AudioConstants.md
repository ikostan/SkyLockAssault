<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Move auto-mute constants to AudioConstants

---

## PR #1052 Summary

**Title:** T1 move auto mute constants to audioconstants  
**PR:** [#1052](https://github.com/ikostan/SkyLockAssault/pull/1052)  
**Branch:** `t1-move-auto-mute-constants-to-audioconstants` → `main`  
**Author:** @ikostan  
**Closes:**

- [#1038 – [TASK] T1: Move auto-mute constants to AudioConstants](https://github.com/ikostan/SkyLockAssault/issues/1038)
- [#1049 – [TASK] Remove stale comments in audio_settings.gd](https://github.com/ikostan/SkyLockAssault/issues/1049)

**Part of:** [#725 – [EPIC] Migrate Near-Zero Auto-Mute Threshold Logic from UI to AudioManager](https://github.com/ikostan/SkyLockAssault/issues/725) (T1, the first sub-task)  
**Milestone:** Milestone 26: Comprehensive Architectural Review & Performance Benchmarking  
**Labels:** audio, refactoring, TASK  

### Purpose

Prepare the auto-mute rule for its move from the Audio Settings menu to `AudioManager` (#725). The threshold and the hardware delay were declared in `scripts/ui/menus/audio_settings.gd`, so tests read them from a menu instance, and `AudioManager` could not use them without depending on a UI script. This PR moves them into the shared `AudioConstants` autoload.

The PR also removes three leftover review comments from `audio_settings.gd` (#1049). #1049 notes it can be folded into the #725 work because both touch the same file.

This is a pure refactor: no behavior change.

### Key Changes

- **Shared constants** (`scripts/resources/audio_constants.gd`)
  - `AUTO_MUTE_VOLUME_THRESHOLD: float = 0.001`: the linear volume at or below which a bus auto-mutes, and above which an auto-muted bus is restored
  - `MUTE_HARDWARE_DELAY: float = 0.15`: the seconds a hardware mute or volume cutoff is deferred so the confirmation click can finish playing
  - `FEEDBACK_HOLD_VOLUME_LINEAR: float = 0.15` (new): the temporary Master volume held while the auto-mute click plays
  - `SFX_CHECK` now has an explicit type, `String`
- **Audio Settings** (`scripts/ui/menus/audio_settings.gd`)
  - Neither constant is declared here any more; all uses read `AudioConstants.*`
  - The Master hold uses `linear_to_db(AudioConstants.FEEDBACK_HOLD_VOLUME_LINEAR)` instead of the magic `linear_to_db(0.15)`
  - The four `play_sfx("check")` calls now use `AudioConstants.SFX_CHECK`
- **Stale comments removed** (same file, #1049)
  - `# To this:` above the button connections in `_ready()`
  - `# Note: Double check your @onready var name for the rotors mute button (mute_rotors vs mute_rotor)` in `_update_ui_interactivity()`. The name is `mute_rotor`.
  - The `FIXED MUTE TOGGLE CALLBACKS` section header now sits above `_execute_bus_mute_toggle` instead of above a lookup helper
  - `_get_slider_for_bus` and `_get_mute_button_for_bus` are grouped under a new `BUS LOOKUP HELPERS` header. The function bodies are unchanged.
- **Tests** (`test/gut/test_audio_settings_comprehensive.gd`)
  - `_get_safety_wait_time()` and all 14 TC-AM cases read `AudioConstants` instead of `audio_instance`

### Design Decisions

- **One source of truth in `AudioConstants`.** `MUTE_HARDWARE_DELAY` was already shared by the auto-mute path and `_execute_bus_mute_toggle`. Once the threshold rule moves to `AudioManager` (#725), both constants must live where the manager and the UI can both reach them without either depending on the other.
- **A separate constant for the feedback hold.** The Master hold value `0.15` equals `MUTE_HARDWARE_DELAY` only by coincidence: one is a linear volume, the other a duration in seconds. A named constant stops anyone "fixing" one by editing the other. The docstring says this explicitly.
- **Moving the lookup helpers.** #1049 only asked to move the section header. Doing only that would leave `_get_slider_for_bus` under "WARNING DIALOG HELPERS", which is the same kind of mislabel. Grouping the two lookup helpers under their own header fixes it; the function bodies are unchanged.
- **`advanced_settings.gd` left alone.** It still calls `play_sfx("check")` once. #1038 limits the change to `audio_settings.gd`, so that call is a follow-up.

### Compatibility

- No gameplay, audio or UI behavior change; all constant values are identical to before
- `AudioConstants` only gains constants; no existing name changed
- Any external code that read `MUTE_HARDWARE_DELAY` or `AUTO_MUTE_VOLUME_THRESHOLD` from an Audio Settings instance must switch to `AudioConstants`. Only `test_audio_settings_comprehensive.gd` did, and it is updated here.

### Testing

- Full GUT suite, headless Godot 4.7.1 with the Dummy audio driver (same setup as CI)
  - `main` @ `3c1f470` (baseline): 95 scripts, **630/630 passed**, 4611 asserts
  - PR head `0524392`: 95 scripts, **630/630 passed**, 4611 asserts, no script errors
- `gdformat --check` and `gdlint` clean on `audio_constants.gd` and `audio_settings.gd`
- Repo-wide search on the PR head: no `"check"` literal, no `# To this:` or `Double check your` comment in `audio_settings.gd`, and no `audio_instance.AUTO_MUTE_VOLUME_THRESHOLD` / `audio_instance.MUTE_HARDWARE_DELAY` reference anywhere. Older milestone notes still mention the names; they are historical records and stay as written.
- [ ] CI: GUT, GDUnit4 and browser shards green on the final head

---

## Reviewer's Guide

Centralizes the auto-mute threshold, the hardware mute delay, a new feedback-hold volume and the check SFX key in `AudioConstants`. Audio Settings and the comprehensive auto-mute tests now read the shared values, and stale review comments and a misplaced section header are cleaned out of `audio_settings.gd`. No behavior change.

### File-Level Changes

| Change                                             | Details                                                                                                                                                                                                                                                                    | Files                                                                           |
|----------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------|
| Centralize the auto-mute constants.                | <ul><li>Add <code>AUTO_MUTE_VOLUME_THRESHOLD</code>, <code>MUTE_HARDWARE_DELAY</code> and the new <code>FEEDBACK_HOLD_VOLUME_LINEAR</code> with docstrings.</li><li>Add the <code>String</code> type to <code>SFX_CHECK</code>.</li></ul>                                  | `scripts/resources/audio_constants.gd`                                          |
| Use the shared constants in Audio Settings.        | <ul><li>Remove the local constant declarations.</li><li>Replace the magic <code>linear_to_db(0.15)</code> with <code>FEEDBACK_HOLD_VOLUME_LINEAR</code>.</li><li>Replace the four <code>"check"</code> literals with <code>AudioConstants.SFX_CHECK</code>.</li></ul>      | `scripts/ui/menus/audio_settings.gd`                                            |
| Clean up stale comments and section headers.       | <ul><li>Remove <code># To this:</code> and the <code>mute_rotors</code> vs <code>mute_rotor</code> note.</li><li>Move the mute-toggle callbacks header above <code>_execute_bus_mute_toggle</code>.</li><li>Group the bus lookup helpers under their own header.</li></ul> | `scripts/ui/menus/audio_settings.gd`                                            |
| Point the auto-mute tests at the shared constants. | <ul><li><code>_get_safety_wait_time()</code> and TC-AM-001 to TC-AM-014 read <code>AudioConstants</code>.</li></ul>                                                                                                                                                        | `test/gut/test_audio_settings_comprehensive.gd`                                 |
| Record the implementation and review context.      | <ul><li>Add the milestone note for this part.</li></ul>                                                                                                                                                                                                                    | `files/docs/milestones/26/Part_5_Move_auto_mute_constants_to_AudioConstants.md` |

### Assessment against linked issues

| Issue                                                   | Objective                                                                   | Addressed | Explanation                                                  |
|---------------------------------------------------------|-----------------------------------------------------------------------------|-----------|--------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1038> | No behavior change; all existing suites pass.                               | ✅        | GUT 630/630 before and after; confirm CI on the final head.  |
| <https://github.com/ikostan/SkyLockAssault/issues/1038> | `audio_settings.gd` declares neither constant.                              | ✅        |                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1038> | No `"check"` string literal left in `audio_settings.gd`.                    | ✅        |                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1038> | Tests read the constants from `AudioConstants` instead of `audio_instance`. | ✅        |                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1049> | Remove the stale `# To this:` and `mute_rotors` vs `mute_rotor` comments.   | ✅        | Fixed in `0524392` after CodeRabbit flagged them as missing. |
| <https://github.com/ikostan/SkyLockAssault/issues/1049> | Move the mute-toggle callbacks header above `_execute_bus_mute_toggle`.     | ✅        | The lookup helpers also got their own header.                |

---

## Contribution Summary

### Human contribution (@ikostan)

- **Planning and scope**
  - Filed #1038 as T1 of the #725 epic and #1049 as a related cleanup, and folded both into one PR.
- **Implementation and integration**
  - Opened the PR and applied every change by hand from the reviewed snippets.
  - Uploaded each edited file for verification and fixed the gaps it showed: three remaining `"check"` literals, 14 test references to `audio_instance`, and the two stale comments CodeRabbit's issue assessment flagged.
- Notable commits by @ikostan:
  - `Centralize audio mute timing constants` (`e34bab0`)
  - `Use AudioConstants in audio settings` (`06b8590`)
  - `Update audio_settings.gd` (`4828e9f`)
  - `Remove stale audio settings comments` (`0524392`)

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Checked each uploaded file against the reference implementation and pointed out the exact lines still missing (the `"check"` literals, the 14 test references, the two stale comments).
  - Checked out the PR branch, confirmed no leftover literals, comments or `audio_instance` references, and re-ran lint and the full GUT suite on `0524392` (630/630).

- **@sourcery-ai**
  - Generated "Summary by Sourcery" and, on request, the Reviewer's Guide with a sequence diagram.
  - Review found no issues.

- **@coderabbitai**
  - Generated "Summary by CodeRabbit" and the linked-issue assessment, which caught that the #1049 comment removals were missing from an earlier head (fixed in `0524392`).
  - No actionable comments in the latest review. Pre-merge checks: 4 passed, 1 failed (the PR description still had template placeholders).

- **@deepsource-io**
  - Ran static analysis and posted the report card; the Python and JavaScript analyzers passed and no inline issues were reported.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
