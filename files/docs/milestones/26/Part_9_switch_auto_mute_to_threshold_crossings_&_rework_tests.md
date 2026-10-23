<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Switch auto-mute to threshold crossings, re-sync AudioServer, and rework the auto-mute tests

---

## PR #1072 Summary

**Title:** 1040 task t3 switch auto muteunmute to a threshold crossing rule  
**PR:** [#1072](https://github.com/ikostan/SkyLockAssault/pull/1072)  
**Branch:** `1040-task-t3-switch-auto-muteunmute-to-a-threshold-crossing-rule` → `main`  
**Author:** @ikostan  
**Closes:**

- [#1040 – [TASK] T3: Switch auto-mute/unmute to a threshold-crossing rule](https://github.com/ikostan/SkyLockAssault/issues/1040)
- [#1041 – [TASK] T4: Re-sync AudioServer after auto-mute and remove _master_zero_token](https://github.com/ikostan/SkyLockAssault/issues/1041)
- [#1044 – [TASK] T7: Rework auto-mute test suites](https://github.com/ikostan/SkyLockAssault/issues/1044)

**Part of:** [#725 – [EPIC] Migrate Near-Zero Auto-Mute Threshold Logic from UI to AudioManager](https://github.com/ikostan/SkyLockAssault/issues/725) (T3, T4 and T7; T5 #1042 and T6 #1043 are still open)  
**Follows:** [#1068](https://github.com/ikostan/SkyLockAssault/pull/1068) (T2, `AudioManager.change_volume()`)  
**Milestone:** Milestone 26: Comprehensive Architectural Review & Performance Benchmarking  
**Labels:** testing, menu, audio, QA  

### Purpose

T2 (#1068) ported the near-zero auto-mute rule into `AudioManager.change_volume()` unchanged. This PR changes that rule and its tests in three steps:

- **T3 (#1040):** the rule was level-triggered. Any volume above `AUTO_MUTE_VOLUME_THRESHOLD` on a muted bus unmuted it, so a programmatic change such as `window.changeMusicVolume([0.5])` overrode a mute the player chose. The rule now fires only when the volume **crosses** the threshold, so a player's mute survives any change that stays audible.
- **T4 (#1041):** auto-mute only flipped the logical flag, so `AudioServer.is_bus_mute()` stayed `false` while `AudioManager` reported muted. Master got a hard-coded `linear_to_db(0.0)` after its feedback hold, which is why a generation token was needed to stop stale writes. AudioServer is now re-synced from the manager's current state, which makes stale timers harmless, and both tokens are removed.
- **T7 (#1044):** the menu suite simulated "manual" with `grab_focus()` + `AudioManager.set_volume()` and emitted `volume_changed` directly, testing the design being removed; TC-AM-003/006 asserted `player.playing`, which passes even when the click is inaudible. The manager contract is now pinned at manager level, and every TC-AM case drives a real input path.

T5 (routing callers through `change_volume()`) and T6 (reducing the menu observer to visual-only) are **not** part of this PR. Review showed the menu observer still applied the old level rule, so it was brought in line with the crossing rule here (`88ba856`), without rerouting callers.

### Key Changes

- **Threshold-crossing rule** (`scripts/managers/audio_manager.gd`, T3)
  - `change_volume()` reads the previous volume before `set_volume()` and computes `crossed_down` (`old > T` and `new <= T`) and `crossed_up` (`old <= T` and `new > T`)
  - Auto-mute only on `crossed_down` for an unmuted bus; auto-unmute only on `crossed_up` for a muted bus. Anything else leaves the mute flag alone
  - No extra state: the stored previous volume is enough, so the rule survives restarts
  - Docstring documents the accepted corner case: a bus muted with its button at 0.8, then set to 0 and back up, is unmuted on the way up (at zero an explicit mute and an auto-mute look the same)
- **AudioServer re-sync and token removal** (`audio_manager.gd`, `audio_settings.gd`, T4)
  - Once an auto-mute settles (after the Master hold, or right away without one), `apply_volume_to_bus(bus, get_volume(bus), get_muted(bus))` writes the manager's current state, re-reading it the same way `toggle_mute()` already does
  - `_master_hold_token` (manager) and `_master_zero_token` (menu) are removed, with their bumps in `cleanup_for_test()`, `_on_global_mute_toggled()` and the auto-unmute branches
  - The menu observer's auto-unmute now clears the AudioServer mute on **every** bus, not only a focused Master. Needed because auto-mute now sets the hardware flag; without it a bus raised from zero with the menu open would stay silent in the mixer
  - A positive near-zero auto-mute keeps the stored volume in the mixer and is silenced by the mute flag, instead of a forced `0.0` write
- **Menu observer follows the crossing rule** (`scripts/ui/menus/audio_settings.gd`, `88ba856`)
  - `_on_global_volume_changed()` runs after `set_volume()` has overwritten the manager's value, so the menu keeps its own `_last_seen_volume` per bus, seeded in `_ready()` before the signal is connected
  - Both branches now require a crossing, matching `change_volume()`. With the menu open, a bridge or `change_volume()` call to another audible volume no longer unmutes a player-muted bus
- **Manager-level suite** (`test/gut/test_audio_manager_auto_mute.gd`, new, 50 test functions, T7)
  - Extended from the T2 suite rather than duplicated: everything is parameterized over the six buses
  - `test_transition_matrix`: every bus × manual/programmatic × down/up (24 cases), asserting the mute state, exactly one `mute_toggled`, the mixer flag, the new volume, and a click only when manual
  - T3 section: player mute survives audible changes (manual and programmatic) and a raise to full; crossing up unmutes; repeated near-zero values are no-ops; crossing down on a muted bus is silent; the corner case; an unmuted-at-zero bus stays unmuted below the threshold
  - T4 section: mixer mute matches the manager after every auto-mute; near-zero auto-mute keeps the stored volume; down-then-up within `MUTE_HARDWARE_DELAY` ends unmuted at the up volume; a stale hold re-applies the current state; no token left in the manager or the menu
  - Raw setters, `apply_volumes_from_config()`, `load_volumes()` from an encrypted file and `reset_volumes()` bypass the rule; the suite asserts no Audio menu is in the tree
- **Integration suite** (`test/gut/test_audio_settings_comprehensive.gd`, rewritten, 20 test functions, T7)
  - Manual cases drive a focused `VolumeSlider` through `slider.value`; automation cases call the real web-bridge handler `_on_change_volume_js` through a `TestBridge` subclass that overrides only the JS argument parsing
  - Every TC-AM case is kept and parameterized over all six buses: manual auto-mute (001–006), automation silence (007–012, bridge and unfocused slider), idempotency (013), manual and automation upward unmute (014), Master hold then silence, newer drag, mute-button unmute during the hold, other buses untouched (015–016)
  - Assertions cover the manager, the mute button, the AudioServer mute flag and an **audible** click (its bus, SFX and Master unmuted), not just `player.playing`
  - Menu lifetime: freeing the menu during the Master hold raises no engine errors; a second test checks the mixer and stays pending until T5/T6 (see Known limitations)
  - Section 7 (`88ba856`): with the menu open, a bridge change and a `change_volume()` call to an audible volume keep a player-muted bus muted, with no transition or click; the through-zero corner case unmutes
- **CodeRabbit regression tests** (`02e6c74`)
  - Manager suite: exact-threshold raise unmutes; an unmuted threshold baseline needs a fresh down-crossing; a hold re-applies the latest muted volume; overlapping holds keep the final state
  - Integration suite: the menu seeds its baseline from the manager when opened at the threshold; near-zero updates from that baseline stay unmuted; a reopened menu preserves a mute made while it was closed; crossings on interleaved buses are independent
- **Playwright VOL-13** (`tests/volume_sliders_mutes_test.py`)
  - With Audio open, `changeMasterVolume([0])` unchecks `#mute-master`; `changeMasterVolume([0.5])` checks it again and leaves the shared page clean. Click silence stays covered by GUT, since JS cannot observe SFX

### Design Decisions

- **Crossings judged against the previous stored volume, no extra state.** A per-bus "auto-muted" flag would have to be persisted and kept in sync with every mute path; the previous volume is already stored and survives restarts. The cost is the documented corner case, which the issue accepts.
- **Re-sync from current state instead of a token.** A late timer that re-applies whatever the manager holds now is idempotent, so a newer drag or unmute during the hold simply wins. The token only existed because the old code wrote a fixed `0.0`.
- **Fix the menu observer in this PR, not in T6.** The review showed the observer still contradicted T3 with the menu open (the web-bridge criterion of #1040). Tracking the last seen volume in the menu is a small change inside #1040's scope; rerouting callers and making the observer visual-only stay with T5/T6.
- **Rename the T2 suite instead of a second manager suite.** `test_audio_manager_change_volume.gd` already covered most of what #1044 lists for all six buses; a new file beside it would have duplicated about 40 tests. The PR adds `test_audio_manager_auto_mute.gd`, but the old file was not deleted (see Known limitations).
- **Rewrite TC-AM cases, don't drop them.** The first T7 draft cut the integration suite to 4 tests; it was rejected in review. Every case now runs through the real slider or bridge path, parameterized over the six buses, and keeps its TC-AM number.
- **Known gaps as self-activating `pending()` checks.** The SFX/SFX_Menu click audibility (#1047) and the menu-freed-mid-hold mixer state (T5/T6) are asserted live and report pending only while the gap exists, so they start enforcing as soon as the fix lands.

### Expected Behavior

| Action on a bus                                               | Before                                 | After                                  |
|---------------------------------------------------------------|----------------------------------------|----------------------------------------|
| Muted with its button at 0.8, then `change_volume(bus, 0.5)`  | Unmuted                                | **Stays muted**                        |
| Same, through `changeMusicVolume([0.5])` with Audio open      | Unmuted (menu observer)                | **Stays muted**                        |
| Auto-muted at 0, then raised to 0.3                           | Unmuted                                | Unmuted                                |
| Repeated near-zero updates on an auto-muted bus               | No-op                                  | No-op                                  |
| Drag to 0 (any bus): `AudioServer.is_bus_mute()` after settle | `false` while the manager says muted   | **`true`**, matches the manager        |
| Master dragged to 0 and back up within 0.15 s                 | Unmuted (token gate)                   | Unmuted at the up volume (no token)    |
| Muted at 0.8, set to 0, then back to 0.3                      | Unmuted                                | Unmuted (accepted corner case)         |

### Compatibility

- **Behavior change:** volume changes that stay above the threshold no longer unmute a muted bus, from the menu, the web bridge or `change_volume()`.
- **Mixer state:** auto-muted buses are now muted in `AudioServer` too; the Master hold ends with the mute flag set and the stored volume, instead of `-inf` dB.
- `change_volume()` still has no production callers (T5); the slider and the bridge still reach the rule through the menu observer while the menu is open.
- No save-format, bus-layout or scene change.

### Testing

- Full GUT suite, headless Godot 4.7.1 + GUT 9.7.1 with the Dummy audio driver (same setup as CI)
  - `main` @ `1c3ff94` (Part 8 final): 99 scripts, **711/711 passed**
  - T3 alone: **718/718 passed**
  - T3 + T4 + rebuilt T7: **720 passed, 3 pending**
  - With the observer fix (`88ba856`): **767 passed, 3 pending**
  - PR head `02e6c74`: 100 scripts, **775 passed, 3 pending, 0 failed**, 8200 asserts
- The 3 pending checks are the documented gaps: SFX and SFX_Menu click audibility (#1047), and the mixer state after the menu is freed mid-hold (T5/T6)
- Mutation checks
  - T3: with the old level rule, 4 new manager tests fail (player mute survives audible change, raise to full, just-above-threshold, unmuted-at-zero)
  - T4: against the T3 code (token + hard-coded `0.0`), the new sync, stale-hold, near-zero and token tests fail, and the menu tests fail their hardware-mute precondition
  - Observer fix: with the old level-triggered observer, the two "player mute survives with the menu open" tests fail
- Bug reproduced while writing the lifetime test: after freeing the menu mid-hold, Master reported muted while `AudioServer` had mute `false` and volume `0.15`
- CI on `02e6c74`: GUT, GdUnit4, gdlint, Build Web Artifact, CI & Security and Refactor Suite passed
- [ ] CI: Browser "Core Web Flows" shard green (runs VOL-13)
- [ ] In a running build: mute Music at a normal level, change its volume from the web overlay, Music stays muted

### Known limitations / follow-ups

- **Duplicate manager suite.** `test/gut/test_audio_manager_change_volume.gd` (+ `.uid`) is still on the branch next to `test_audio_manager_auto_mute.gd`; the rename landed as a copy, so the manager tests run twice (44 extra tests). Delete the old file and its `.uid`.
- **Menu freed during the Master hold leaves Master audible** (pre-existing). The hold lives in the menu observer, so its coroutine dies with the menu and Master stays at `FEEDBACK_HOLD_VOLUME_LINEAR` while `AudioManager` reports muted. Fixed by T5/T6, which move the hold into the autoload; `test_menu_freed_during_master_hold_ends_muted_in_mixer` starts enforcing then.
- **SFX / SFX_Menu click is inaudible.** The click plays on SFX_Menu, so auto-muting SFX or SFX_Menu silences its own click (#1047). The old TC-AM-003/006 hid this.
- **Down-up-down within 0.15 s on Master.** Without a token, the first hold's timer re-syncs during the second hold and cuts that click short. Nothing ends in a wrong state; `toggle_mute()` behaves the same way.
- **T5/T6 still open.** The menu observer still runs its own copy of the rule (now crossing-based) and the slider and bridge do not call `change_volume()` yet.
- **PR description and links.** The description is still the template (CodeRabbit's description check warns) and has no `Closes` lines, so CodeRabbit skipped its linked-issue checks. Add `Closes #1040`, `Closes #1041`, `Closes #1044`, and consider a title naming all three tasks.
- `ruff` with default rules flags three pre-existing lines in `tests/volume_sliders_mutes_test.py` (`RUF010`, `FURB122`, `BLE001`); CI does not run ruff.
- Part 8's note still names `test_audio_manager_change_volume.gd`; it is a historical record and stays as written.

---

## Reviewer's Guide

Moves auto-mute and auto-unmute in `AudioManager.change_volume()` and in the Audio Settings observer from level-triggered checks to threshold crossings, so player-chosen mutes survive audible volume changes. Re-syncs `AudioServer` from the manager after every auto-mute, which makes stale Master holds harmless and removes both generation tokens. Pins the contract in a scene-free manager suite over all six buses and rewrites the menu suite to drive the real slider and web-bridge paths, with audible-click checks, menu-lifetime coverage and a Playwright regression.

### File-Level Changes

| Change                                           | Details                                                                                                                                                                                                                                                                               | Files                                                                                         |
|--------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| Switch the manager rule to threshold crossings.  | <ul><li>Read the previous volume before <code>set_volume()</code>.</li><li>Mute on a down-crossing of an unmuted bus, unmute on an up-crossing of a muted bus.</li><li>Document the through-zero corner case.</li></ul>                                                               | `scripts/managers/audio_manager.gd`                                                           |
| Re-sync AudioServer and remove the tokens.       | <ul><li>Apply the manager's current state after the hold, or right away without one.</li><li>Remove <code>_master_hold_token</code> and <code>_master_zero_token</code> and their bumps.</li><li>Menu auto-unmute clears the hardware mute on every bus.</li></ul>                    | `scripts/managers/audio_manager.gd`<br/>`scripts/ui/menus/audio_settings.gd`                  |
| Apply the crossing rule in the menu observer.    | <ul><li>Track <code>_last_seen_volume</code> per bus, seeded in <code>_ready()</code>.</li><li>Require a crossing for both branches.</li></ul>                                                                                                                                        | `scripts/ui/menus/audio_settings.gd`                                                          |
| Pin the contract at manager level.               | <ul><li>Transition matrix over bus × caller × direction.</li><li>Crossing, re-sync, stale-hold, no-token, raw-setter, load and reset tests for all six buses.</li><li>CodeRabbit threshold and overlapping-hold regressions.</li></ul>                                                | `test/gut/test_audio_manager_auto_mute.gd`<br/>`test/gut/test_audio_manager_auto_mute.gd.uid` |
| Rewrite the menu suite through real input paths. | <ul><li>Focused <code>VolumeSlider</code> for manual cases, the web-bridge handler for automation.</li><li>All TC-AM cases kept and parameterized over the six buses, with audible-click checks.</li><li>Menu lifetime, player-mute-survives and CodeRabbit baseline tests.</li></ul> | `test/gut/test_audio_settings_comprehensive.gd`                                               |
| Update the T2 suite for T3/T4.                   | <ul><li>Invert the just-above-threshold test, add the crossing and re-sync tests, replace the token-cleanup test.</li><li>Still present beside the new suite (see Known limitations).</li></ul>                                                                                       | `test/gut/test_audio_manager_change_volume.gd`                                                |
| Add a Playwright regression.                     | <ul><li>VOL-13: Master to 0 unchecks <code>#mute-master</code>; 0.5 checks it again.</li></ul>                                                                                                                                                                                        | `tests/volume_sliders_mutes_test.py`                                                          |
| Record the implementation and review context.    | <ul><li>Add the milestone note for this part.</li></ul>                                                                                                                                                                                                                               | `files/docs/milestones/26/Part_9_Switch_auto_mute_to_threshold_crossings_and_rework_tests.md` |

### Assessment against linked issues

| Issue                                                   | Objective                                                                                   | Addressed | Explanation                                                                                                                      |
|---------------------------------------------------------|---------------------------------------------------------------------------------------------|-----------|----------------------------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1040> | A bus muted at 0.8 stays muted after `change_volume(bus, 0.5)`.                             | ✅        | Manager and menu-open tests, all six buses. The first review flagged the menu observer; fixed in `88ba856`.                      |
| <https://github.com/ikostan/SkyLockAssault/issues/1040> | A bus auto-muted at 0 unmutes after `change_volume(bus, 0.3)`.                              | ✅        |                                                                                                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1040> | Repeated near-zero updates are no-ops (no signal, no SFX), covering TC-AM-013's intent.     | ✅        | Manager suite (both callers) and TC-AM-013 through the slider and the bridge.                                                    |
| <https://github.com/ikostan/SkyLockAssault/issues/1040> | `changeMusicVolume([0.5])` on muted Music keeps it muted.                                   | ✅        | GUT through the real bridge handler with the menu open, all six buses; not yet a Playwright case.                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1041> | After any auto-mute settles, `AudioServer.is_bus_mute(idx) == AudioManager.get_muted(bus)`. | ✅        | Manager and menu paths, all six buses. Exception: menu freed mid-hold, pending T5/T6.                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1041> | Down-crossing then up-crossing within `MUTE_HARDWARE_DELAY` ends unmuted at the up volume.  | ✅        |                                                                                                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1041> | No token variable in manager or menu.                                                       | ✅        | Asserted by `test_no_hold_token_remains`.                                                                                        |
| <https://github.com/ikostan/SkyLockAssault/issues/1044> | Old focus-based TC-AM cases removed or rewritten.                                           | ✅        | All rewritten through real input paths; none dropped.                                                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1044> | New suite covers all six buses.                                                             | ✅        | `test_audio_manager_auto_mute.gd`; the old file still needs deleting.                                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1044> | GUT, GdUnit4, Playwright green in CI.                                                       | ⏳        | GUT and GdUnit4 green on `02e6c74`; the Core Web Flows shard (VOL-13) was still running.                                         |

---

## Review decisions

| Finding                                                                                  | Severity | Decision                        | Reason                                                                                                                                         |
|------------------------------------------------------------------------------------------|----------|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| Sourcery assessment: #1040 crossing rule not enforced through the Audio Settings handler | –        | **Fixed** (`88ba856`)           | Valid. The observer was still level-triggered; it now tracks the last seen volume and requires a crossing.                                     |
| Sourcery assessment: a web-bridge audible change can override a player mute              | –        | **Fixed** (`88ba856`)           | Same root cause. New tests change a player-muted bus to an audible volume through the bridge and through `change_volume()` with the menu open. |
| CodeRabbit: guard menu auto-mute transitions with a volume crossing                      | Minor    | **Fixed** (`88ba856`), resolved | Same finding as above; the applied fix matches its suggestion (named `_last_seen_volume`, seeded before the signal is connected).              |
| CodeRabbit pre-merge check: description still has template placeholders                  | Warning  | Resolved by this summary        | Paste this note into the PR description and add the `Closes` lines.                                                                            |
| CodeRabbit generated tests (`02e6c74`)                                                   | –        | **Accepted**                    | Eight regressions on threshold baselines, overlapping holds and menu reopen; all pass on the head.                                             |

---

## Contribution Summary

### Human contribution (@ikostan)

- **Planning and scope**
  - Took the epic's T3, T4 and T7 one issue at a time, asking for each to be finished before the next, and combined them in one PR.
- **Review leadership**
  - Brought the Sourcery linked-issue assessment forward, which led to the menu-observer fix.
  - Kept every change local until reviewed and pushed only on request.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Found that the menu observer's auto-unmute had to clear the hardware mute on every bus once auto-mute started setting it.
  - Flagged before review that #1040's first and web-bridge criteria could not hold end to end while the observer stayed level-triggered.
  - Found, while writing the lifetime test, that freeing the menu mid-hold leaves Master audible at the hold level, and that the old TC-AM-003/006 hid an inaudible click on SFX/SFX_Menu (#1047); both are now tracked by self-activating pending checks.

- **@sourcery-ai**
  - Generated the Reviewer's Guide (on request) with sequence diagrams and the linked-issue assessment, which flagged the two #1040 gaps in the menu observer (fixed in `88ba856`).
  - No inline review: the weekly review budget was exhausted.

- **@coderabbitai**
  - Generated "Summary by CodeRabbit" with the walkthrough and sequence diagram; merge risk low.
  - Posted one Minor finding: the menu handler needed a volume-crossing guard. Valid; fixed in `88ba856` and resolved.
  - Pre-merge checks: 4 passed (linked-issue and scope checks skipped, since no issue is linked), 1 warning (template description).
  - Authored `02e6c74` (`Add regression tests for audio mute thresholds, delayed holds, and menu state synchronization`) through unit-test generation: four manager tests and four menu tests.

- **@deepsource-io**
  - Ran static analysis on `f3b5a3b...02e6c74` and posted the report card; the Python and JavaScript analyzers ran, no inline issues.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
