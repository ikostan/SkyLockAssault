<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Route volume callers through change_volume(), make the Audio Settings observer visual-only, and derive GUT mute waits from AudioConstants

---

## PR #1074 Summary

**Title:** T5 t6 migrate near zero auto mute threshold logic  
**PR:** [#1074](https://github.com/ikostan/SkyLockAssault/pull/1074)  
**Branch:** `t5_t6_Migrate_Near-Zero_Auto-Mute_Threshold_Logic` → `main`  
**Author:** @ikostan  
**Closes:** #1043 and #1054

- [#1042 – [TASK] T5: Route volume callers through change_volume() with is_manual_interaction](https://github.com/ikostan/SkyLockAssault/issues/1042)
- [#1043 – [TASK] T6: Reduce audio_settings._on_global_volume_changed to a visual-only observer](https://github.com/ikostan/SkyLockAssault/issues/1043)
- [#1054 – [TASK] Derive mute-delay waits in GUT tests from AudioConstants](https://github.com/ikostan/SkyLockAssault/issues/1054)

**Part of:** [#725 – [EPIC] Migrate Near-Zero Auto-Mute Threshold Logic from UI to AudioManager](https://github.com/ikostan/SkyLockAssault/issues/725) (T5 and T6, the last two sub-tasks)  
**Follows:** [#1072](https://github.com/ikostan/SkyLockAssault/pull/1072) (T3, T4, T7)  
**Follow-up filed:** [#1075 – [BUG] Master feedback hold is cut short by an at-or-below-threshold change_volume() during MUTE_HARDWARE_DELAY](https://github.com/ikostan/SkyLockAssault/issues/1075) (Milestone 27)  
**Milestone:** Milestone 26: Comprehensive Architectural Review & Performance Benchmarking  
**Labels:** enhancement, testing, audio, refactoring  

### Purpose

Finish moving the near-zero auto-mute rule out of the Audio Settings menu (#725). Since T2/T3 the rule lived in `AudioManager.change_volume()`, but nothing called it: the slider and the web bridge still wrote the volume themselves, and the menu's `_on_global_volume_changed()` applied its own copy of the rule, deciding "manual vs programmatic" from slider focus.

- **T5 (#1042):** every volume source now calls `change_volume()` and states its own intent. This also fixes the focus leak: `Globals.ensure_initial_focus()` gives the Master slider focus when the menu opens, so a web-bridge `changeMasterVolume([0])` was treated as manual (click + Master hold), and the bridge's own `apply_volume_to_bus(..., muted=true)` then overrode that hold at once.
- **T6 (#1043):** the menu callback becomes a visual-only observer. No rule, no click, no hold, no `await`, no mixer writes.
- **#1054:** every GUT wait for the mute cutoff derives from `AudioConstants.MUTE_HARDWARE_DELAY` through one shared constant, so changing the delay can't make tests drift.

T5 and T6 must land together: with T5 alone, the menu and the manager both apply the rule, and 4 Master hold/focus tests fail.

### Key Changes

- **Shared GUT wait** (`test/gut/gut_test_helper.gd`, #1054)
  - `GutTestHelper.MUTE_CUTOFF_WAIT = AudioConstants.MUTE_HARDWARE_DELAY + 0.1`, the same 0.1 s margin as `HOLD_WAIT` / `CUTOFF_WAIT` in the newer suites
  - Used by the 10 hardcoded `create_timer(0.2)` waits in `test_master_volume_control_and_music.gd`, `test_sfx_volume_control.gd`, `test_sfx_weapon_volume_control.gd`, `test_sfx_rotor_volume_control.gd`, `test_ui_mute_logic.gd` and `test_preserve_other_sections.gd`; Scenario D (`wait_seconds(0.2)`) and Scenario F (`MUTE_HARDWARE_DELAY * 2.0`) in `test_audio_integration.gd`; and the two inline `MUTE_HARDWARE_DELAY + 0.1` waits in `test_unmute_from_zero.gd`
  - Comments no longer hardcode "0.15s"; `test_tc_sl_09` no longer claims a deferred "file write" and says its assertions are synchronous, the wait being an upper bound
- **Callers state their intent** (T5)
  - `VolumeSlider._on_value_changed()` calls `AudioManager.change_volume(bus, v, _is_dragging or has_focus())`, the same check `_handle_slider_sfx()` uses; its direct `AudioServer.set_bus_volume_db()` write is removed. Debounced save and slider SFX unchanged
  - `VolumeSlider.set_value_programmatically()` calls `change_volume(bus, v, false)`; its direct `AudioServer` write is removed, and `_previous_value` is synced before the call
  - `AudioWebBridge._on_change_volume_js()` calls `change_volume(bus, value, false)`; the separate `set_volume()` + `apply_volume_to_bus()` pair is removed. `save_volumes()` and the parent-mute guards stay
  - `volume_slider.gd` has no `AudioServer.set_bus_volume_db` left
- **Visual-only menu observer** (`scripts/ui/menus/audio_settings.gd`, T6)
  - `_on_global_volume_changed()` is one line: `_sync_slider_visual(_get_slider_for_bus(bus_name), volume)`. It keeps `_sync_slider_visual()`, so `VolumeSlider` still resyncs its delta tracker (#1046)
  - Removed: `_last_seen_volume` and its seeding in `_ready()`, the crossing detection, the auto-mute/unmute branches, the focus check, the Master feedback hold, the click and every `AudioServer` call in that path. `audio_settings.gd` shrinks from 792 to 712 lines
  - `_exit_tree()` (the Master re-sync added in #1072) is removed: the hold now runs in the autoload and re-syncs Master itself, so the menu-side re-sync only cut the confirmation click short when the menu closed mid-hold
  - The observer's doc comment states that `change_volume()` owns the mixer write for volume changes and `toggle_mute()` for mute presses (Sourcery finding, `ef327b2`)
- **Tests** (`test/gut/test_audio_settings_comprehensive.gd`)
  - `test_t5_bridge_master_zero_with_initial_focus_is_silent`: with the menu's initial focus left on Master, `_on_change_volume_js([0], Master)` mutes Master at once, with no click and no hold
  - `test_t5_focused_slider_to_zero_clicks_once` (all six buses): a focused slider moved to 0 auto-mutes and the confirmation click plays exactly once. New helper `_count_playing_clicks()`
  - `test_menu_freed_during_master_hold_ends_muted_in_mixer` rewritten for the new behavior: after the menu is freed mid-hold, Master stays held audible and the click keeps playing; once the hold ends, Master is muted at the stored volume
  - Two stale doc comments updated; no test case removed

### Design Decisions

- **Shared constant in `GutTestHelper`, margin `+ 0.1`.** The issue proposed one constant per file with a `+ 0.05` margin "as `_get_safety_wait_time()`". That helper is gone, every newer suite uses `+ 0.1`, and `GutTestHelper` already exists on the GUT side (not in `test/gdunit4/test_helpers.gd`, which the GUT job doesn't load).
- **Keep bounded waits at sites 3–11 (#1054 Option A).** The issue said those waits never engaged the delay. That stopped being true with #1048: `toggle_mute()` defers the cutoff on every manual press, focused or not. Replacing them with one frame now fails 9 tests on `main`, so Option B was dropped and the comments say they wait out the deferred cutoff.
- **The slider decides "manual" with the same check as its SFX.** `_is_dragging or has_focus()` is what already gated the slider sound; the manager no longer infers intent from focus, and the bridge is always programmatic.
- **Keep `_sync_slider_visual()` instead of the issue's `set_value_no_signal()`.** A plain `set_value_no_signal()` would leave `VolumeSlider._previous_value` stale and bring back the swallowed-move bug fixed in #1046.
- **Remove the menu `_exit_tree()` re-sync.** It existed only because the hold was a coroutine on the menu. With the hold in the autoload it was redundant and cut the click short; removing it fails only the old "muted as soon as the menu is freed" assertion, which the rewritten test replaces.
- **Keep `set_value_programmatically()`.** It has no production caller now, but it is the documented "update without SFX or save" API from Milestone 17, with three dedicated tests in `test_volume_slider.gd`. Removing it is an API decision, not a cleanup.

### Expected Behavior

| Action                                                                | Before                                                  | After                                             |
|-----------------------------------------------------------------------|---------------------------------------------------------|---------------------------------------------------|
| Audio menu open (Master focused), `changeMasterVolume([0])`           | Click + Master hold, then hold overridden by the bridge | **Master muted at once, no click, no hold**       |
| Focused slider dragged to 0                                           | Rule applied by the menu observer                       | Rule applied once by `change_volume()`, one click |
| Volume change with the menu closed (bridge, code)                     | Rule only via `change_volume()` callers (none)          | **Same rule as with the menu open**               |
| Master dragged to 0, menu closed within 0.15 s                        | Master muted at once, click cut short (`_exit_tree()`)  | **Click finishes**, Master muted when hold ends   |
| `AudioServer` write for a volume change                               | Slider, bridge and menu each wrote the mixer            | Only `AudioManager.change_volume()`               |
| `MUTE_HARDWARE_DELAY` changed to 0.3 s                                | 6 GUT tests fail                                        | Full GUT suite passes                             |

### Compatibility

- **Audible changes:** web-bridge volume changes never click or hold Master, whatever has focus; closing the menu during a Master auto-mute no longer cuts the click short.
- **`set_value_programmatically()`** now applies the near-zero auto-mute rule (silently). It has no production callers.
- No scene, bus-layout or save-format change.

### Testing

- Full GUT suite, headless Godot 4.7.1 + GUT 9.7.1 with the Dummy audio driver (same setup as CI)
  - `main` @ `212090e` (baseline): 99 scripts, 734 tests, **733 passed**, 2 pending sub-cases (#1047)
  - #1054 alone (`825c7eb`): **733 passed**, same pending; grep from the acceptance criteria returns nothing
  - T5 alone: 732/736 (4 Master hold/focus failures from the double rule, as expected); with T6: **735 passed**, 2 pending sub-cases
  - PR head `ef327b2`: 736 tests, **735 passed**, 2 pending sub-cases (#1047)
- Change check (#1054): with `MUTE_HARDWARE_DELAY = 0.3`, 6 tests fail on `main`; on the branch the full suite passes. Reverted afterwards
- Mutation checks
  - #1054 premise: sites 3–12 replaced with one frame fails 9 tests (delay engaged since #1048)
  - Bridge passing `is_manual_interaction = true`: `test_t5_bridge_master_zero_with_initial_focus_is_silent` fails
  - Click played twice in `change_volume()`: `test_t5_focused_slider_to_zero_clicks_once` fails on all six buses
  - Old `_exit_tree()` restored: the rewritten menu-lifetime test fails (hold and click cut short)
- Flakiness: affected suites 5 consecutive runs at each step, all green
- gdUnit4 (v6.2.0, run as in CI: `xvfb-run`, coverage plugin stripped): **142/142** on 8 full runs; `test_gdunit_all_menus_navigation_regression.gd` alone 8/8
- `gdformat --check` and `gdlint` clean on `audio_settings.gd`, `volume_slider.gd`, `audio_web_bridge.gd`
- CI on `ffe6d82`: the gdUnit4 job failed once in `test_options_menu_navigation_sfx` (focus owner was another `Button` at line 159). The code is identical to the locally verified head and nothing on that path changed, so it is treated as a flaky focus race; re-run
- [ ] CI: GUT, gdUnit4 and browser shards green on the final head
- [ ] In a running build: open Audio, drag Master to 0 and press Back at once; the click finishes, Master ends muted

### Known limitations / follow-ups

- **Master hold vs. a follow-up near-zero change (#1075, Milestone 27).** An at-or-below-threshold `change_volume()` during `MUTE_HARDWARE_DELAY` mutes Master at once and cuts the click. Not reachable from `VolumeSlider` (step 0.033, threshold 0.001, repeated 0 dropped by its early return); reachable through automation. Pre-existing (the bridge override described in #1042).
- **SFX / SFX_Menu click inaudible (#1047).** Still reported by the 2 pending sub-cases.
- **`test_gdunit_all_menus_navigation_regression.gd` focus race.** If it fails again, make line 159 print both buttons' node paths and wait until focus lands instead of one frame.
- **#1054 issue text** predates #1048; its body was updated with a status note (delay engaged at sites 1–11, margin `+ 0.1`, Option B dropped).
- **PR description** is still the template and its `Closes` line is a placeholder; paste this note and add `Closes #1042`, `Closes #1043`, `Closes #1054`.
- **Epic #725:** all seven sub-tasks (T1–T7) are done with this PR; close it after merge once its DoD is checked (Part 8 noted the config-load round-trip wording).

---

## Reviewer's Guide

Routes every volume source through `AudioManager.change_volume()` with an explicit `is_manual_interaction` flag (the slider by drag/focus, the web bridge and programmatic slider updates as automation), and reduces the Audio Settings `volume_changed` handler to a visual-only observer with no rule, timing or mixer writes. The redundant menu-exit Master re-sync is removed, so the autoload's feedback hold outlives the menu. GUT waits for the mute cutoff now derive from `AudioConstants.MUTE_HARDWARE_DELAY` through `GutTestHelper.MUTE_CUTOFF_WAIT`, and new tests pin the bridge-with-focus and click-once behavior.

### File-Level Changes

| Change                                            | Details                                                                                                                                                                                                                                                                                                                                                                    | Files                                                                                                                                                                                                                                                                                                                                                                                                |
|---------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Derive GUT mute-cutoff waits from AudioConstants. | <ul><li>Add <code>GutTestHelper.MUTE_CUTOFF_WAIT</code> (<code>MUTE_HARDWARE_DELAY + 0.1</code>).</li><li>Replace hardcoded <code>0.2</code> waits, Scenario D/F waits and inline delay expressions.</li><li>Drop "0.15s" and "file write" from comments.</li></ul>                                                                                                        | `test/gut/gut_test_helper.gd`<br/>`test/gut/test_audio_integration.gd`<br/>`test/gut/test_master_volume_control_and_music.gd`<br/>`test/gut/test_sfx_volume_control.gd`<br/>`test/gut/test_sfx_weapon_volume_control.gd`<br/>`test/gut/test_sfx_rotor_volume_control.gd`<br/>`test/gut/test_ui_mute_logic.gd`<br/>`test/gut/test_preserve_other_sections.gd`<br/>`test/gut/test_unmute_from_zero.gd` |
| Route volume callers through `change_volume()`.   | <ul><li>Slider: <code>change_volume(bus, v, _is_dragging or has_focus())</code>; programmatic updates pass <code>false</code>.</li><li>Bridge: <code>change_volume(bus, value, false)</code> + <code>save_volumes()</code>.</li><li>Remove direct <code>AudioServer</code> / <code>apply_volume_to_bus</code> writes.</li></ul>                                            | `scripts/ui/components/volume_slider.gd`<br/>`scripts/system/audio_web_bridge.gd`                                                                                                                                                                                                                                                                                                                    |
| Make the menu volume observer visual-only.        | <ul><li><code>_on_global_volume_changed()</code> only syncs the slider via <code>_sync_slider_visual()</code>.</li><li>Remove <code>_last_seen_volume</code>, the rule, click, hold and mixer writes.</li><li>Remove the <code>_exit_tree()</code> Master re-sync.</li><li>Clarify mixer ownership (<code>change_volume()</code> vs <code>toggle_mute()</code>).</li></ul> | `scripts/ui/menus/audio_settings.gd`                                                                                                                                                                                                                                                                                                                                                                 |
| Pin the new contract in the integration suite.    | <ul><li>Bridge with Master's initial focus stays silent with no hold.</li><li>Focused slider to 0 clicks exactly once (six buses).</li><li>Menu freed mid-hold: hold and click survive, Master muted when the hold ends.</li></ul>                                                                                                                                         | `test/gut/test_audio_settings_comprehensive.gd`                                                                                                                                                                                                                                                                                                                                                      |
| Record the implementation and review context.     | <ul><li>Add the milestone note for this part.</li></ul>                                                                                                                                                                                                                                                                                                                    | `files/docs/milestones/26/Part_10_Route_volume_callers_through_change_volume_and_make_menu_visual_only.md`                                                                                                                                                                                                                                                                                           |

### Assessment against linked issues

| Issue                                                   | Objective                                                                                     | Addressed | Explanation                                                                                                         |
|---------------------------------------------------------|-----------------------------------------------------------------------------------------------|-----------|---------------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1042> | No `AudioServer.set_bus_volume_db` in `volume_slider.gd`.                                     | ✅        |                                                                                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1042> | Audio menu open, `changeMasterVolume([0])`: Master mutes, no click.                           | ✅        | `test_t5_bridge_master_zero_with_initial_focus_is_silent`; needs T6 in the same PR.                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1042> | Focused slider dragged to 0: bus mutes, click plays once.                                     | ✅        | `test_t5_focused_slider_to_zero_clicks_once`, all six buses.                                                        |
| <https://github.com/ikostan/SkyLockAssault/issues/1043> | `_on_global_volume_changed` only updates slider visuals.                                      | ✅        | Uses `_sync_slider_visual()` rather than plain `set_value_no_signal()` to keep the #1046 fix.                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1043> | `test_global_volume_changed_bypasses_signals` passes unchanged.                               | ✅        | File untouched.                                                                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1043> | Freeing the menu within `MUTE_HARDWARE_DELAY` of an auto-mute: no errors, bus ends muted.     | ✅        | Both menu-lifetime tests; the hold now also survives the menu.                                                      |
| <https://github.com/ikostan/SkyLockAssault/issues/1054> | No hardcoded mute-delay value in `test/gut` (grep returns nothing).                           | ✅        |                                                                                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1054> | Every cutoff wait, including Scenario F, derives from `MUTE_HARDWARE_DELAY` via one constant. | ✅        | Scenario F: `test_audio_integration.gd:186`. Sourcery's ❌ was checked against the pre-#1048 issue text.            |
| <https://github.com/ikostan/SkyLockAssault/issues/1054> | Comments describe what each test exercises.                                                   | ✅        | Since #1048 the delay is engaged at sites 1–11 (one frame fails 9 tests); site 12 documents its synchronous checks. |
| <https://github.com/ikostan/SkyLockAssault/issues/1054> | Change check with `MUTE_HARDWARE_DELAY = 0.3` passes.                                         | ✅        | 6 failures on `main`, 0 on the branch.                                                                              |

---

## Review decisions

| Finding                                                                                     | Severity | Decision                      | Reason                                                                                                                                                                                                                                |
|---------------------------------------------------------------------------------------------|----------|-------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Sourcery: confirmation click is cut off (`volume_slider.gd:165`, `audio_web_bridge.gd:219`) | Medium   | **Deferred to #1075**         | Valid for `change_volume()`, not reachable from `VolumeSlider` (step 0.033 vs threshold 0.001; a repeated 0 never reaches the manager). Reproduced only via a programmatic or manual ≤ threshold call within the delay. Pre-existing. |
| Sourcery: mixer ownership is overstated (`audio_settings.gd:253`)                           | Low      | **Fixed** (`ef327b2`)         | The comment now limits `change_volume()` to volume-change writes and names `toggle_mute()` for mute presses.                                                                                                                          |
| Sourcery assessment: #1054 Scenario F not on the shared constant                            | –        | **Declined (false positive)** | Scenario F uses `GutTestHelper.MUTE_CUTOFF_WAIT`; the bot looked for the inline `+ 0.05` form the original issue predicted.                                                                                                           |
| Sourcery assessment: #1054 comments should say the toggle applies synchronously             | –        | **Declined (obsolete)**       | Since #1048 the cutoff is deferred on every manual press; one-frame waits fail 9 tests. The issue text was updated with a status note.                                                                                                |
| CodeRabbit pre-merge check: description still has template placeholders                     | Warning  | Resolved by this summary      | Paste this note and add the `Closes` lines.                                                                                                                                                                                           |

---

## Contribution Summary

### Human contribution (@ikostan)

- **Planning and scope**
  - Chose the shared `GutTestHelper` constant, the `+ 0.1` margin, the scope of the replacements and the bounded wait for site 12.
- **Implementation and integration**
  - Applied every change by hand from the reviewed code, uploaded the edited files for verification (all matched), and pushed the branch.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Re-verified #1054 against current `main` and found its premise outdated since #1048 (one-frame waits fail 9 tests; the 0.3 s change check fails 6), which ruled out Option B and changed the margin and constant location.
  - Wrote the two T5 acceptance tests and the rewritten menu-lifetime test, each verified by mutation; kept `_sync_slider_visual()` over the issue's `set_value_no_signal()` to preserve the #1046 fix.
  - Found the redundant `_exit_tree()` re-sync and that removing `set_value_programmatically()` would drop tests.
  - Triaged the Sourcery findings (reproduced the hold cut via `change_volume()`, showed it is not reachable from the slider, drafted #1075), the false-positive #1054 assessment and the gdUnit4 CI failure (8 clean full runs locally), and verified the uploaded files against the reference.

- **@sourcery-ai**
  - Generated the PR summary and the Reviewer's Guide with the linked-issue assessment.
  - Posted two inline findings: confirmation click cut off (valid for `change_volume()`, deferred to #1075) and overstated mixer ownership (valid, fixed in `ef327b2`, thread outdated).
  - Its #1054 assessment marked two criteria unmet; both were checked against the pre-#1048 issue text and are false positives.

- **@coderabbitai**
  - Generated "Summary by CodeRabbit"; no actionable comments, 13 additional comments marked LGTM, merge risk minimal.
  - Pre-merge checks: 4 passed (linked-issue and scope checks skipped, since no issue is linked in the description), 1 warning (template description).
  - Unit-test generation task.

- **@deepsource-io**
  - Ran static analysis and posted the report card (overall A); the Python and JavaScript analyzers passed, no inline issues.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
