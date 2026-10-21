<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Restore audible volume on unmute-from-zero and unify the mute pipeline

---

## PR #1062 Summary

**Title:** Bug unmuting a bus at zero volume leaves it unmuted at 0  
**PR:** [#1062](https://github.com/ikostan/SkyLockAssault/pull/1062)  
**Branch:** `bug-unmuting-a-bus-at-zero-volume-leaves-it-unmuted-at-0` → `main`  
**Author:** @ikostan  
**Closes:**

- [#1046 – [BUG] Unmuting a bus at zero volume leaves it unmuted at 0](https://github.com/ikostan/SkyLockAssault/issues/1046)
- [#1048 – [FEATURE] Move the mute-toggle pipeline (_execute_bus_mute_toggle) to AudioManager](https://github.com/ikostan/SkyLockAssault/issues/1048)

**Related:** [#725 – [EPIC] Migrate Near-Zero Auto-Mute Threshold Logic from UI to AudioManager](https://github.com/ikostan/SkyLockAssault/issues/725) (both issues were planned to land after #725; this PR implements them standalone, see Design Decisions)  
**Milestone:** Milestone 26: Comprehensive Architectural Review & Performance Benchmarking  
**Labels:** bug, enhancement, FEATURE, refactoring, testing, QA, GUI, menu, github actions, github_actions  

### Purpose

Unmuting a bus whose volume was at 0 (mute button, clicking the locked slider, or the web `toggleMute*` bridge) left it **unmuted at 0**: the button showed sound on while the bus stayed silent. This contradicted the auto-mute rule (≤ threshold ⇒ muted), and the rule never re-ran because the volume didn't change.

#1046 fixes this by restoring the last audible volume. #1048 moves the mute pipeline from the Audio Settings menu into `AudioManager`, so the menu and the web bridge share one code path and one fix. The menu is now visual-only for mute, as it already was for volume.

### Key Changes

- **Unmute-from-zero restore** (`scripts/managers/audio_manager.gd`, `scripts/resources/audio_constants.gd`)
  - `_last_audible_volume` per bus (in memory), captured at **commit points**: `save_volumes()` and `load_volumes()`, not on every `set_volume()`. A drag 0.66 → 0 passes through 0.099, 0.066, 0.033 and must not overwrite 0.66
  - New `AudioConstants.UNMUTE_FROM_ZERO_FALLBACK_VOLUME = 0.495` (15 slider steps) when no audible volume is known, e.g. after a restart
  - Private `_restore_volume_for_unmute()` raises a bus at or below the threshold; buses above it keep their volume
- **Shared mute pipeline** (#1048)
  - New `AudioManager.toggle_mute(bus_name, muted, is_manual_interaction := false)`: confirmation click for manual presses, immediate logical flip, unmute-from-zero restore, `MUTE_HARDWARE_DELAY` deferred cutoff for manual mutes, then applies the newest state (a toggle during the delay wins). Does not save, mirroring `set_volume()`
  - `audio_settings.gd`: `_execute_bus_mute_toggle` drops the focus gate and calls `toggle_mute(bus, muted, true)`; the unused `_get_mute_button_for_bus` is removed
  - `audio_web_bridge.gd`: `_on_toggle_mute_js` becomes `toggle_mute(bus, muted, false)` + `save_volumes()`
- **Slider sync** (`scripts/ui/components/volume_slider.gd`, `audio_settings.gd`)
  - New `VolumeSlider.sync_from_manager()` keeps `_previous_value` in step with external volume changes; otherwise moving the slider straight back to 0 after a restore was swallowed by the delta early-return
  - The debounced save is postponed while the pointer is held, so a pause mid-drag never commits a near-silent step
- **Review hardening**
  - Any Master unmute (menu, web, reset) now invalidates the pending auto-mute zeroing timer via `_on_global_mute_toggled`
  - Loading applies the auto-mute rule: a bus saved at 0 while unmuted loads muted
  - Loaded volumes are clamped to 0.0–1.0 (with a warning); restore values are clamped too
  - The menu saves the mute before the hardware delay, so closing the menu within 0.15 s no longer loses it
- **Dependency bump merged into the branch** (Dependabot)
  - `actions/create-github-app-token` 3.2.0 → 3.3.0 (`bi_weekly_gd_docstrings.yml`, #1061)

### Design Decisions

- **Restore the last audible volume** (decision recorded on #1046), rather than refusing the unmute or jumping one slider step.
- **Commit points, not every change.** Tracking every `set_volume()` would restore 0.033 after a drag to 0.
- **Standalone ahead of #725.** The mute path needs no volume-hold helper from #725, so #1048 does not depend on it. The Master `_master_zero_token` stays in the UI until #725 moves the threshold rule into `AudioManager`.
- **No new public API beyond `toggle_mute()`.** gdlint caps `AudioManager` at 20 public methods; it is exactly at 20, so the restore and getter helpers are private.
- **Zero volume loads muted, not restored** (Sourcery suggested restoring an audible level on load). Restoring would play sound after the player deliberately chose 0.
- **The menu does not await `toggle_mute()`.** The logical state is set before the delay, so it is saved immediately; the deferred cutoff completes in the `AudioManager` autoload, which outlives the menu.

### Expected Behavior

| Action on a bus                                     | Before                | After                        |
|-----------------------------------------------------|-----------------------|------------------------------|
| Drag to 0 from 0.66, then mute button / `ui_accept` | Unmuted at 0 (silent) | Unmuted at **0.66**          |
| Unmute at 0 after a restart                         | Unmuted at 0 (silent) | Unmuted at **0.495**         |
| Unmute a bus above the threshold                    | Volume unchanged      | Volume unchanged             |
| Web `toggleMute*` unmute at 0                       | Unmuted at 0 (silent) | Restored; DOM slider follows |
| Click a muted slider above zero                     | Unmuted at 0 (silent) | Unmuted at the clicked level |
| Real mute-button press with focus elsewhere         | Silent                | Confirmation click           |
| Background sync (reset, web, Playwright)            | Silent                | Silent                       |
| Close the menu within 0.15 s of a mute              | Mute lost on restart  | Mute saved                   |

### Compatibility

- **Audible changes:** unmuting from zero now plays at the restored level; real mute-button presses always click.
- **Saved settings:** a config with a bus at 0 and `muted = false` now loads muted; out-of-range volumes are clamped on load.
- **Pre-existing bug also fixed:** the quick-exit save loss existed on `main`.
- No scene, bus-layout or save-format change.

### Testing

- Full GUT suite, headless Godot 4.7.1 + GUT 9.7.1 with the Dummy audio driver (same setup as CI)
  - `main` @ `3376a8f` (baseline): 95 scripts, **632/632 passed**
  - Final code: 97 scripts, **664/664 passed** (32 new tests)
- New suites
  - `test/gut/test_unmute_from_zero.gd` (19 tests): the four acceptance criteria, drag-to-zero, slider-click unmute, debounced-save commit point, Master timer race (menu and web), slider re-mute, fallback, load normalization, clamping, paused drag, release commit
  - `test/gut/test_toggle_mute_pipeline.gd` (13 tests): manual vs programmatic, deferred cutoff, cutoff race, locked-slider proxy, background sync silent, persistence, parent-mute guard, quick menu close
  - `test_audio_settings_interaction.gd`: the focus-gate test is replaced by a background-sync-is-silent test
  - `test_audio_config_parsing.gd`: the zero cases of `test_numeric_volumes_include_zero_and_one` now expect a muted load
- Mutation checks: each fix was reverted in turn and its test failed (Master token bump and its web-path move, newest-state re-read, save snapshot, load normalization, drag postpone, clamping, quick-exit save)
- `gdlint` and `gdformat --check` clean on `./scripts`
- Playwright `tests/unmute_from_zero_test.py` (2 tests: restore reaches the DOM slider; 0.495 after reload) collects and passes ruff, but was not run locally (needs a web export)
- [ ] CI: GUT, GDUnit4 and browser shards green on the final head
- [ ] In a running build: drag Music to 0, press its mute button, Music returns at the previous level

### Known limitations / follow-ups

- A DOM slider set to 0 still does not auto-mute; the bridge has no threshold logic (#725).
- Clicking a muted slider exactly at zero stays muted but plays `check` twice; a dedicated error sound and warning are tracked in #___.
- No test covers a real mouse click on Godot's slider: headless GUT can't deliver one, and Playwright needs the slider's on-screen position (same plumbing as #___).
- `AudioManager` is at gdlint's 20 public-method cap; the next public method needs a refactor or a lint decision.

---

## Reviewer's Guide

Fixes unmuting at zero volume by restoring the last committed audible volume (or 0.495), and moves the mute pipeline into `AudioManager.toggle_mute()` so the Audio Settings menu and the web bridge share it. Hardens the restore against load, drag, range and timing edge cases found in review, and adds GUT and Playwright regression coverage.

### File-Level Changes

| Change                                                       | Details                                                                                                                                                                                                                                                                                                             | Files                                                                                                                                                                                                              |
|--------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Restore an audible volume on unmute-from-zero.               | <ul><li>Track <code>_last_audible_volume</code> at save/load commit points.</li><li>Add <code>UNMUTE_FROM_ZERO_FALLBACK_VOLUME</code> (0.495).</li><li>Load at-zero buses muted; clamp loaded and restore volumes to 0.0–1.0.</li></ul>                                                                             | `scripts/managers/audio_manager.gd`<br/>`scripts/resources/audio_constants.gd`                                                                                                                                     |
| Share one mute pipeline between the menu and the web bridge. | <ul><li>Add <code>AudioManager.toggle_mute()</code> (click, flip, restore, deferred cutoff, newest-state apply).</li><li>Menu: no focus gate, save before the delay, remove <code>_get_mute_button_for_bus</code>.</li><li>Bridge: call <code>toggle_mute(…, false)</code> + <code>save_volumes()</code>.</li></ul> | `scripts/managers/audio_manager.gd`<br/>`scripts/ui/menus/audio_settings.gd`<br/>`scripts/system/audio_web_bridge.gd`                                                                                              |
| Keep sliders and timers consistent with external changes.    | <ul><li><code>VolumeSlider.sync_from_manager()</code> resyncs the delta tracker.</li><li>Postpone the debounced save while dragging.</li><li>Invalidate the Master zeroing timer on any unmute.</li></ul>                                                                                                           | `scripts/ui/components/volume_slider.gd`<br/>`scripts/ui/menus/audio_settings.gd`                                                                                                                                  |
| Add regression coverage.                                     | <ul><li>GUT suites for unmute-from-zero and the shared pipeline.</li><li>Update the focus-gate and zero-volume parsing tests.</li><li>Playwright: restored volume in the DOM slider, fallback after reload.</li></ul>                                                                                               | `test/gut/test_unmute_from_zero.gd`<br/>`test/gut/test_toggle_mute_pipeline.gd`<br/>`test/gut/test_audio_settings_interaction.gd`<br/>`test/gut/test_audio_config_parsing.gd`<br/>`tests/unmute_from_zero_test.py` |
| Bump a pinned GitHub Action (Dependabot).                    | <ul><li><code>actions/create-github-app-token</code> 3.2.0 → 3.3.0.</li></ul>                                                                                                                                                                                                                                       | `.github/workflows/bi_weekly_gd_docstrings.yml`                                                                                                                                                                    |
| Record the implementation and review context.                | <ul><li>Add the milestone note for this part.</li></ul>                                                                                                                                                                                                                                                             | `files/docs/milestones/26/Part_7_Restore_audible_volume_on_unmute_and_unify_mute_pipeline.md`                                                                                                                      |

### Assessment against linked issues

| Issue                                                   | Objective                                                                   | Addressed | Explanation                                                                                  |
|---------------------------------------------------------|-----------------------------------------------------------------------------|-----------|----------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1046> | Auto-mute at 0 from 0.66, then unmute restores 0.66.                        | ✅        | Mute button, `ui_accept` and web bridge. A click on the slider unmutes at the clicked level. |
| <https://github.com/ikostan/SkyLockAssault/issues/1046> | Unmute at 0 after a restart gives 0.495.                                    | ✅        |                                                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1046> | Unmuting a bus above the threshold leaves its volume unchanged.             | ✅        |                                                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1046> | DOM slider value follows the restored volume.                               | ✅        | GUT with a mocked bridge; Playwright test pending its first CI run.                          |
| <https://github.com/ikostan/SkyLockAssault/issues/1048> | One mute contract for the menu and the web bridge; the menu is visual-only. | ✅        | `AudioManager.toggle_mute()`.                                                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1048> | Focus check removed; sync stays silent; tests updated.                      | ✅        | Background sync uses `set_pressed_no_signal`, so only real presses click.                    |
| <https://github.com/ikostan/SkyLockAssault/issues/1048> | Start after #725.                                                           | ➖        | Not needed: the mute path doesn't use the #725 hold helper.                                  |

---

## Review decisions

| Finding (Sourcery)                                    | Severity | Decision                          | Reason                                                                                                                                            |
|-------------------------------------------------------|----------|-----------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| Web unmute silenced by a stale Master auto-mute timer | High     | Fixed (`ae122b1`)                 | The token is now invalidated in `_on_global_mute_toggled`, which every unmute path reaches; reproduced first (Master at `-inf` dB while unmuted). |
| Saved zero volume stays silent                        | Medium   | **Fixed differently** (`818fdfe`) | Loading applies the auto-mute rule (zero ⇒ muted) instead of restoring an audible level, which would override the player's choice of 0.           |
| Paused drags restore a near-silent volume             | Medium   | Fixed (`818fdfe`)                 | `VolumeSlider` postpones its debounced save while the pointer is held.                                                                            |
| Out-of-range volumes restored above 1.0               | Medium   | Fixed (`818fdfe`)                 | Clamp on load and on snapshot.                                                                                                                    |
| Quick menu exit drops the mute save                   | Medium   | Fixed (`6ea99a8`)                 | Also present on `main`. Save before the delay; the cutoff finishes in the autoload.                                                               |

---

## Contribution Summary

### Human contribution (@ikostan)

- **Planning and scope**
  - Filed #1046 and #1048, recorded the product decision for #1046 (restore the last audible volume), and chose to implement both standalone, ahead of #725, in one PR.
- **Implementation and integration**
  - Opened the PR, merged the Dependabot bump (#1061), and applied every change from the reviewed files.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Confirmed the #1046 bug path and found that tracking every volume change would restore a near-silent drag step; proposed commit-point tracking.
  - Found, by reading Godot 4.7.1's `Slider` source, that a real click on a muted slider is applied twice, corrected the over-reaching AC1 test, and drafted the follow-up feature request.

- **@sourcery-ai**
  - Generated "Summary by Sourcery" and, on request, the Reviewer's Guide with diagrams and the linked-issue assessment.
  - Posted five findings (1 High, 4 Medium), all valid; four fixed as suggested, one fixed differently (see Review decisions).

- **@coderabbitai**
  - Generated "Summary by CodeRabbit"; no actionable comments, merge risk minimal, docstring coverage 100%.
  - Pre-merge checks: 4 passed, 1 warning (the PR description still had template placeholders; resolved by this summary).

- **@deepsource-io**
  - Ran static analysis and posted the report card (overall A); Python and JavaScript analyzers passed, no inline issues.

- **@dependabot**
  - Opened the bump merged into this branch: `actions/create-github-app-token` 3.2.0 → 3.3.0 (#1061, `7de977f`).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
