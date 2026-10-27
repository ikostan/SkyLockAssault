<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Keep the auto-mute confirmation click audible across its whole feedback path: per-click windows instead of a Master-only hold

---

## PR #1081 Summary

**Title:** Master feedback auto mute confirmation click  
**PR:** [#1081](https://github.com/ikostan/SkyLockAssault/pull/1081)  
**Branch:** `master-feedback-auto-mute-confirmation-click` → `main`  
**Author:** @ikostan  
**Closes:** #1075 and #1047

- [#1075 – [BUG] Master feedback hold is cut short by an at-or-below-threshold change_volume() during MUTE_HARDWARE_DELAY](https://github.com/ikostan/SkyLockAssault/issues/1075)
- [#1047 – [FEATURE] Keep the auto-mute confirmation click audible for SFX and SFX_Menu](https://github.com/ikostan/SkyLockAssault/issues/1047)

**Follows:** [#1074](https://github.com/ikostan/SkyLockAssault/pull/1074) (T5, T6; epic #725), where #1075 was filed from a Sourcery finding  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** audio, bug, refactoring, testing  

### Purpose

Make the auto-mute confirmation click reliably audible. Before this PR it was protected only for Master, and only against a single crossing:

- **#1075:** during the Master feedback hold, a second `change_volume()` at or below the threshold is not a new crossing, but `change_volume()` wrote the mixer before applying the rule. It wrote the already-muted flag, hard-muting Master and cutting the click. Not reachable from `VolumeSlider` (step 0.033, repeated 0 dropped), but reachable through the web bridge, programmatic callers and manual near-zero follow-ups.
- **#1047:** the click plays on `SFX_Menu → SFX → Master`. Auto-muting SFX or SFX_Menu played it into a bus already at ~0. TC-AM-001/006 only reported this through 2 `pending()` sub-cases.
- **Review findings on this PR** (Sourcery, CodeRabbit) showed a per-bus hold still let one bus's timer mute a segment of the path under a later click, and `toggle_mute()` wrote mutes straight to the mixer during a hold. The final design tracks clicks, not buses.

### Key Changes

- **Per-click windows** (`scripts/managers/audio_manager.gd`)
  - `_clicks_in_flight`: every SFX_CHECK click `AudioManager` plays (auto-mute, auto-unmute, mute button) opens a `MUTE_HARDWARE_DELAY` window through the new `_play_confirmation_click()`. All three former `SfxManager.play_sfx(AudioConstants.SFX_CHECK)` calls go through it
  - `_is_path_write_deferred(bus)`: true while a window is open and the bus is on the click's feedback path
  - `_sync_bus_or_defer(bus)`: applies the bus state, unless that would silence a deferred bus. Then a bus at or below the threshold is held at `FEEDBACK_HOLD_VOLUME_LINEAR`, a muted audible bus is left as it is, and the mute flag is never touched
  - `_deferred_buses`: every bus whose write was deferred is recorded; `_end_click_window()` re-syncs exactly those from the newest state when the last window closes (`_resync_deferred_buses()`), then emits `feedback_path_settled`
  - Removed: the per-bus `_pending_feedback_holds`, `_has_pending_feedback_hold()` and `_release_feedback_hold()` from the first #1075 iteration
- **Feedback path** (#1047)
  - `_is_in_feedback_path(bus)` walks `AudioServer.get_bus_send()` up from `BUS_SFX_MENU` (today SFX_Menu, SFX, Master), read live so a re-routed layout is followed, capped at `bus_count` steps against send cycles
  - Manual down-crossings on any path bus get the hold; Music, SFX_Weapon and SFX_Rotors stay immediate
- **`change_volume()`**
  - Top mixer write: an at-or-below value on a deferred bus writes the hold level instead of the muted state (#1075)
  - Down-crossing: `set_muted(true)`, click, `_sync_bus_or_defer()`; a manual call on a path bus awaits `feedback_path_settled`, so `await change_volume(...)` still means "the hold has finished"
  - Up-crossing unchanged: unmuted state applied at once, then the click
- **`toggle_mute()`**: the final write goes through `_sync_bus_or_defer()`, so a programmatic mute of a path bus during a click is deferred and a manual toggle's own click keeps the path open. Unmutes and off-path mutes apply at once. The existing engine-workaround delay is unchanged
- **Docs**
  - `change_volume()` steps 1, 4 and 5, the `is_manual_interaction` param and the "await it only if…" line, plus the `toggle_mute()` flow
  - `FEEDBACK_HOLD_VOLUME_LINEAR` (`audio_constants.gd`), `VolumeSlider._on_value_changed()` and the `audio_web_bridge.gd` comment no longer describe the hold as Master-only
- **Tests**
  - `test_audio_manager_auto_mute.gd`
    - #1075: near-zero follow-ups (3 values × 2 callers), programmatic crossing down during a hold, audible updates apply at once, overlapping holds (deterministic and real)
    - #1047: path membership, layout following, send-cycle guard, SFX/SFX_Menu hold then flatten, no hold off-path or programmatic, #1075 guard on the new buses
    - Review scenarios: cross-bus holds (deterministic and real), programmatic `toggle_mute()` during a click (Master, SFX), safe immediate writes, manual toggle vs a later click
    - The 8 "FEEDBACK HOLD ROUTING AND LIFECYCLE REGRESSIONS" tests generated by CodeRabbit (`34e80bc`), ported to the click-window counter
    - `test_no_hold_token_remains` also checks no click window is left open at rest
  - `test_audio_settings_comprehensive.gd`: `SELF_SILENCING_BUSES` and the `pending()` branch removed, so `test_tc_am_001_006_manual_slider_auto_mutes` asserts an audible click on all six buses. `_is_click_audible()` walks the player's send chain and checks volume as well as mute
  - `test_volume_change_callers.gd`: `FEEDBACK_PATH_BUSES`; `test_unfocused_drag_to_zero_is_manual` expects the hold on every path bus (its old Master-only check also leaked an un-awaited hold into the next two tests)
  - No test case removed

### Design Decisions

- **Track clicks, not buses.** A per-bus counter cannot stop SFX_Menu's timer from muting SFX_Menu while a later SFX click still streams through it, nor cover `toggle_mute()`. One count of clicks in flight answers the real question ("is any click still playing through this bus?") for every caller.
- **Record deferred buses instead of re-deriving the path at the end.** `test_feedback_hold_rerouting_changes_manual_cutoff` found that a bus held under one routing (Music, with SFX_Menu sent through it) stayed at the hold level if the route changed back before the last window closed.
- **Hold level instead of skipping the write (#1075).** Skipping would leave a bus raised during the hold at that raised level until the timer; writing `FEEDBACK_HOLD_VOLUME_LINEAR` matches the issue's "stays at the hold level until the delay ends".
- **Never unmute a bus the player muted.** Deferral only changes volume levels, never the mute flag. With SFX_Menu muted by the player, menu clicks stay silent, as the player asked.
- **Hold the whole path, keep the click on SFX_Menu (#1047 decision).** A dedicated click bus would bypass the player's SFX and SFX_Menu volumes. Accepted trade-off: other sounds on a held bus play at the hold level for the window.
- **Audibility by bus volume and mute flag, not peak meters.** Peak readings are unreliable with the Dummy driver in headless CI.
- **Public `feedback_path_settled` signal.** gdlint rejects a leading underscore on signal names; it is documented as the hold's completion signal.
- **Windows survive `cleanup_for_test()`.** Clearing the counter while a timer is pending would let that timer close a newer window early (kept from the #1075 counter, pinned by `test_feedback_hold_cleanup_preserves_pending_count`).
- **Deterministic timing tests.** Two real 0.15 s timers started apart can fire in the same frame after a hitch (the first overlap test failed when run alone). Tests that need to observe "first window closed, second still open" hold the second window open by hand and close it with `_end_click_window()`.

### Expected Behavior

| Action                                                                       | Before                                          | After                                                         |
|------------------------------------------------------------------------------|-------------------------------------------------|---------------------------------------------------------------|
| Master auto-muted by slider, then `change_volume(Master, 0)` within 0.15 s   | Master hard-muted, click cut                    | **Master stays at the hold level**, muted when the click ends |
| SFX or SFX_Menu slider dragged to 0                                          | Click played into a bus at ~0 (inaudible)       | **Click audible**, bus muted when it ends                     |
| SFX_Menu, then SFX auto-muted within 0.15 s                                  | (per-bus hold) SFX_Menu muted under SFX's click | **Both held** until the last click ends                       |
| Web bridge mutes SFX while a click plays                                     | Click cut at once                               | State flips at once; **mixer mutes when the click ends**      |
| Music / Weapon / Rotors auto-muted, or any programmatic change with no click | Immediate                                       | Immediate (unchanged)                                         |
| Any unmute or above-threshold change during a hold                           | Immediate                                       | Immediate (TC-AM-016 unchanged)                               |
| Menu bus muted by the player, SFX auto-muted                                 | Click silent                                    | Click silent (by design: the player muted menu sounds)        |

### Compatibility

- **Audible changes:** SFX and SFX_Menu auto-mutes now click audibly; other sounds on SFX, SFX_Menu or Master play at 0.15 linear while a click window is open.
- **`change_volume()` await semantics:** a manual path-bus auto-mute awaits until the last open window closes, not only its own timer.
- **New public signal:** `AudioManager.feedback_path_settled`.
- No scene, bus-layout or save-format change.

### Testing

- Full GUT suite, headless Godot 4.7.1 + GUT 9.7.1 with the Dummy audio driver (same setup as CI)
  - `main` @ `8f8fe8b` + #1075 (`ab3fea5`): 755 tests, **754 passed**, 2 pending sub-cases (#1047)
  - - #1047 (`aeeeea7`): 762 tests, **762 passed**, 0 pending
  - - review rework (`a43ab87`, with this PR's own review tests): 767 tests, **767 passed**
  - PR head `8547129`: 775 tests, **775 passed**, 0 pending
- Mutation checks
  - #1075 fix reverted: the 3 #1075 regression tests fail (and the counter-at-rest check); the TC-AM-016 immediacy test passes either way, as intended
  - Re-sync gate removed (#1075 iteration): the crossing-down-during-hold and first-of-overlapping tests fail
  - `audio_manager.gd` at the #1075 state (no path hold): 5 new manager tests, TC-AM-001/006 (now failing instead of pending) and `test_unfocused_drag_to_zero_is_manual` fail
  - `toggle_mute()` writing the mixer directly: both `toggle_mute()` review tests fail
  - Re-sync on every window close: the cross-bus, first-of-overlapping and manual-toggle tests fail
  - Per-path re-sync instead of `_deferred_buses`: `test_feedback_hold_rerouting_changes_manual_cutoff` fails (found while merging)
- Flakiness: the first overlap test (two staggered real timers) failed 6/6 when run alone; after making it deterministic, the four #1075 timing-sensitive tests ran 3 times each in isolation, all green
- gdUnit4 (v6.2.0, run as in CI: `xvfb-run`, coverage plugin stripped): **142/142** at every step
- `gdformat --check` and `gdlint` clean on every changed file in `scripts/`
- Uploaded `audio_manager.gd` and `test_audio_manager_auto_mute.gd` checked against the reference; the pushed head differs only by blank lines in `audio_constants.gd` and `test_volume_change_callers.gd`
- [ ] CI: GUT, gdUnit4 and browser shards green on the final head
- [ ] In a running build: drag SFX_Menu, then SFX to 0 quickly; both clicks are heard and both buses end muted

### Known limitations / follow-ups

- **Raw writers are not deferred.** `apply_all_volumes()`, `load_volumes()` and `reset_volumes()` write the mixer directly, so a Reset within 0.15 s of a click can cut it. Not filed; raise if it shows up in play.
- **Back-to-back clicks extend the hold.** Each click opens its own window, so rapid clicks keep the path held until 0.15 s after the last one.
- **`test_audio_manager_auto_mute.gd` is 1,604 lines.** gdlint flags `max-file-lines` and `max-public-methods` (CI does not lint tests). The #1075 and #1047 sections would split cleanly into their own suite.
- **Part 9 note (Milestone 26)** describes the #1047 check as a "self-activating pending"; it was an unconditional `pending()`, which is why it had to be removed by hand here.
- **PR description** is still the template; paste this note and add `Closes #1075`, `Closes #1047` (both issues are already linked in the sidebar).

---

## Reviewer's Guide

Replaces the Master-only confirmation-click hold with per-click windows on the click's live feedback path (SFX_Menu → SFX → Master). While any click is streaming, writes that would silence a bus on that path are deferred: the bus is held at `FEEDBACK_HOLD_VOLUME_LINEAR` or left as it is. When the last window closes, every deferred bus is re-synced from the newest manager state. `toggle_mute()` uses the same deferral; unmutes, above-threshold changes, off-path buses and programmatic changes with no click stay immediate. The integration suite now requires an audible click on all six buses.

### File-Level Changes

| Change                                                      | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Files                                                                                                                        |
|-------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| Defer silencing writes on the feedback path per click.      | <ul><li><code>_clicks_in_flight</code>, <code>_play_confirmation_click()</code>, <code>_end_click_window()</code>, <code>feedback_path_settled</code>.</li><li><code>_is_in_feedback_path()</code> walks live bus sends from SFX_Menu.</li><li><code>_sync_bus_or_defer()</code> and <code>_deferred_buses</code> / <code>_resync_deferred_buses()</code>.</li><li><code>change_volume()</code> and <code>toggle_mute()</code> route their writes through the deferral.</li></ul> | `scripts/managers/audio_manager.gd`                                                                                          |
| Describe the hold as path-wide, not Master-only.            | <ul><li><code>FEEDBACK_HOLD_VOLUME_LINEAR</code> doc.</li><li>Slider and web-bridge comments.</li></ul>                                                                                                                                                                                                                                                                                                                                                                           | `scripts/resources/audio_constants.gd`<br/>`scripts/ui/components/volume_slider.gd`<br/>`scripts/system/audio_web_bridge.gd` |
| Pin #1075, #1047 and the review scenarios at manager level. | <ul><li>Near-zero follow-ups, overlapping and cross-bus holds, <code>toggle_mute()</code> during a click.</li><li>Path membership, re-routing, send cycles, missing SFX_Menu, cleanup, unattached manager.</li><li>Ported CodeRabbit routing and lifecycle tests.</li></ul>                                                                                                                                                                                                       | `test/gut/test_audio_manager_auto_mute.gd`                                                                                   |
| Enforce an audible click on all six buses.                  | <ul><li>Remove the <code>pending()</code> branch in TC-AM-001/006.</li><li><code>_is_click_audible()</code> checks volume and mute along the send chain.</li><li>Caller test expects the hold on every path bus.</li></ul>                                                                                                                                                                                                                                                        | `test/gut/test_audio_settings_comprehensive.gd`<br/>`test/gut/test_volume_change_callers.gd`                                 |
| Record the implementation and review context.               | <ul><li>Add the milestone note for this part.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                           | `files/docs/milestones/27/Part_1_Keep_the_confirmation_click_audible_across_the_feedback_path.md`                            |

### Assessment against linked issues

| Issue                                                   | Objective                                                                                             | Addressed | Explanation                                                                                                  |
|---------------------------------------------------------|-------------------------------------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1075> | Programmatic and manual at-or-below follow-ups during the hold don't mute Master; muted after it.     | ✅        | `test_regression_near_zero_follow_up_keeps_master_hold` (3 values × 2 callers).                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1075> | Overlapping holds: the first timer neither mutes nor unmutes Master while the second is pending.      | ✅        | `test_regression_first_of_overlapping_holds_leaves_second_alone` (deterministic) and the real-timer variant. |
| <https://github.com/ikostan/SkyLockAssault/issues/1075> | Above-threshold updates during a hold still apply immediately (TC-AM-016 unchanged).                  | ✅        | `test_audible_updates_during_master_hold_apply_immediately`; TC-AM-016 untouched.                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1075> | New tests fail when the fix is reverted.                                                              | ✅        | Mutation checks above.                                                                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1075> | Revisit `test_no_hold_token_remains` for the new counter.                                             | ✅        | Kept; also asserts no click window is open at rest.                                                          |
| <https://github.com/ikostan/SkyLockAssault/issues/1047> | Walk `AudioServer.get_bus_send()` up from `BUS_SFX_MENU`; today Master, SFX and SFX_Menu.             | ✅        | `_is_in_feedback_path()`; membership, re-routing, cycle and missing-bus tests.                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1047> | Apply the hold to any bus on that path for manual down-crossings.                                     | ✅        | Generalized to per-click windows after review.                                                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1047> | Test with a bus volume check rather than `player.playing`.                                            | ✅        | `_is_click_audible()` and `_click_chain_audible()` check mute and volume per bus.                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1047> | Remove the `pending()` branch so the audible-click check enforces on all six buses; no pending tests. | ✅        | GUT reports 0 pending.                                                                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1047> | Full GUT and gdUnit4 suites pass.                                                                     | ✅        | 775/775 and 142/142.                                                                                         |

---

## Review decisions

| Finding                                                                                                | Severity | Decision                     | Reason                                                                                                                                                                 |
|--------------------------------------------------------------------------------------------------------|----------|------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Sourcery: confirmation clicks get cut short across buses (`audio_manager.gd:358–361`, also `:369–371`) | Medium   | **Fixed** (`a43ab87`)        | Valid: holds were per bus. Replaced by per-click windows; `test_regression_cross_bus_holds_wait_for_last_click`.                                                       |
| CodeRabbit: keep the click route audible until overlapping holds finish (`audio_manager.gd:369–370`)   | Minor    | **Fixed** (`a43ab87`)        | Same root cause (SFX_Menu then SFX within the delay). Both real-timer and deterministic tests.                                                                         |
| Sourcery: programmatic mutes cut off clicks (`audio_manager.gd:344–345`, also `:361–364`)              | Medium   | **Fixed** (`a43ab87`)        | Valid: `toggle_mute()` wrote the mixer directly. Now deferred for path buses; `test_regression_programmatic_toggle_mute_waits_for_click`.                              |
| Sourcery: manual toggle cuts off click (`audio_manager.gd:358–361`, also `:369`)                       | Medium   | **Fixed** (`a43ab87`)        | Valid: the toggle's own delay was invisible to the hold. Its click now opens a window; `test_regression_manual_toggle_mute_waits_for_last_click`.                      |
| Sourcery: callers get wrong settling guidance (docs, `audio_manager.gd:306–307`, also `:359–361`)      | Low      | **Fixed** (`a43ab87`)        | `change_volume()`, `FEEDBACK_HOLD_VOLUME_LINEAR` and slider docs now name SFX and SFX_Menu; the lost `is_manual_interaction` doc line was restored.                    |
| CodeRabbit generated tests: 8 routing and lifecycle regressions (`34e80bc`)                            | –        | **Kept, ported** (`8547129`) | Written against the per-bus counter replaced in review; rewritten for `_clicks_in_flight` with no case dropped. The re-routing test exposed the `_deferred_buses` gap. |
| CodeRabbit pre-merge: description still the template                                                   | Warning  | Resolved by this summary     | Paste this note and add the `Closes` lines.                                                                                                                            |

---

## Contribution Summary

### Human contribution (@ikostan)

- **Planning and scope**
  - Decided to resolve #1075 and #1047 in one PR, and added the #1047 acceptance criterion (remove the `pending()` branch, no pending tests).
- **Implementation and integration**
  - Applied every change by hand, pushed the branch, opened PR #1081, requested CodeRabbit unit-test generation, relayed the five review findings, and uploaded the edited files and the bot-extended test file for verification and merge.
  - Implemented the #1075 fix (pending-hold counter, hold level for at-or-below follow-ups, gated re-sync) and the #1047 feedback-path hold (`_is_in_feedback_path()` over live bus sends), with tests verified by mutation.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Replaced a timing-based overlap test that failed in isolation (both 0.15 s timers firing in one frame) with deterministic tests that hold a window open by hand.
  - Found that the old Master-only caller test leaked an un-awaited hold into the next two tests, and that `_is_click_audible()` should walk the real send chain and check volume.
  - Triaged the five review findings (all valid, one root cause), redesigned the hold as per-click windows covering `toggle_mute()`, and pinned each scenario with a test that fails on a targeted mutant.
  - Merged CodeRabbit's 8 generated tests into the reworked suite without dropping cases, and fixed the re-route gap they exposed (`_deferred_buses`).
  - Ran GUT and gdUnit4 locally at every step, and checked the pushed head against the reference.

- **@sourcery-ai**
  - Generated the PR summary and the Reviewer's Guide with a sequence diagram and the linked-issue assessment (all four objectives ✅ for #1047 and #1075).
  - Posted 4 inline findings: cross-bus cutoff, programmatic mutes, manual toggle (Medium) and settling docs (Low). All valid and fixed in `a43ab87`; threads resolved.

- **@coderabbitai**
  - Generated "Summary by CodeRabbit" and posted 1 actionable comment (cross-bus cutoff, Minor), fixed in `a43ab87`.
  - Unit-test generation: committed 8 routing and lifecycle regression tests (`34e80bc`), kept and ported; one of them found the re-route gap.
  - Later runs stopped at the free OSS review limit.

- **@deepsource-io**
  - Ran static analysis on `8f8fe8b...8547129` and posted the report card: grade A overall and for security, reliability, complexity and hygiene; the Python and JavaScript analyzers passed. AI review not triggered.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
