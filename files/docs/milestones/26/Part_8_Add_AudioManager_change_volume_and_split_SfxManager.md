<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Add AudioManager.change_volume() and split SFX playback into SfxManager

---

## PR #1068 Summary

**Title:** T2: Add AudioManager.change_volume() entry point and split SFX playback into SfxManager (#1039)  
**PR:** [#1068](https://github.com/ikostan/SkyLockAssault/pull/1068)  
**Branch:** `t2-add-audiomanagerchange_volume-entry-point` → `main`  
**Author:** @ikostan  
**Closes:** [#1039 – [TASK] T2: Add AudioManager.change_volume() entry point](https://github.com/ikostan/SkyLockAssault/issues/1039)  
**Part of:** [#725 – [EPIC] Migrate Near-Zero Auto-Mute Threshold Logic from UI to AudioManager](https://github.com/ikostan/SkyLockAssault/issues/725) (T2, the second sub-task; step 3 of the epic's implementation order, without T3/T4)  
**Milestone:** Milestone 26: Comprehensive Architectural Review & Performance Benchmarking  
**Labels:** enhancement, testing, menu, audio  

### Purpose

Give `AudioManager` a single volume entry point that applies the near-zero auto-mute rule, so the rule can later run without the Audio Settings menu and callers state their intent (`is_manual_interaction`) instead of the code guessing it from slider focus.

`AudioManager` was already at gdlint's `max-public-methods` cap of 20 (noted as a follow-up in Part 7), so adding `change_volume()` failed lint. The SFX half of the class (pool, cache, playback, diagnostics, UI button hook) shares no state with the volume/mute half, so it moves to its own autoload, `SfxManager`. `AudioManager` drops to 14 public methods, 15 with `change_volume()`, with no lint override.

T3 (#1040) and T4 (#1041) were planned for the same PR, but are deferred to keep this already large PR reviewable.

While verifying the PR with the local Docker pipeline, three pre-existing gaps between that pipeline and GitHub CI also surfaced and are fixed here (see Docker / local pipeline).

### Key Changes

- **New `SfxManager` autoload** (`scripts/managers/sfx_manager.gd`, `project.godot`)
  - Registered before `AudioManager`. Code moved as-is: the `AudioStreamPlayer` pool, the LRU stream cache, `play_sfx()`, `stop_all_sfx()`, the four playback diagnostics, and the global UI button click hook (#800: `_on_node_added`, `_retroactive_ui_scan`, `_on_global_button_pressed`)
  - `cleanup_for_test()` resets the cache and pool and also frees orphaned `AudioStreamPlayer` children. Test suites that swap the node's script with `set_script()` reset `_sfx_pool` but leave the old players in the tree, which leaked 8 nodes per spy suite
- **`AudioManager` keeps volume/mute state only** (`scripts/managers/audio_manager.gd`)
  - 20 → 14 public methods before T2
  - `cleanup_for_test()` stays and delegates the SFX reset to `SfxManager.cleanup_for_test()`, so the existing test teardowns are unchanged
  - `toggle_mute()` plays its confirmation click through `SfxManager.play_sfx()`
- **Call sites moved to `SfxManager`** (`ui_manager.gd`, `volume_slider.gd`, `advanced_settings.gd`, `audio_settings.gd`, `gameplay_settings.gd`, `key_mapping.gd`, `main_menu.gd`)
  - `VolumeSlider` resolves `/root/SfxManager`, so tests can still double the node
- **`AudioManager.change_volume(bus_name, volume, is_manual_interaction := false)`** (#1039)
  - Stores the volume (`volume_changed` fires) and owns the `AudioServer` write for this path
  - Ports today's rule from `audio_settings.gd::_on_global_volume_changed`: at or below `AUTO_MUTE_VOLUME_THRESHOLD` on an unmuted bus → mute; above it on a muted bus → unmute (level-triggered; T3 switches to crossings)
  - Auto-unmute applies the unmuted state to `AudioServer` immediately, for every bus and every caller (`1c3ff94`). Without it, the first write (which still carries the old mute flag) left the mixer muted while `AudioManager` reported unmuted
  - `SFX_CHECK` and the Master feedback hold (`FEEDBACK_HOLD_VOLUME_LINEAR` for `MUTE_HARDWARE_DELAY`) run only for manual interactions; the hold runs from the autoload, with no dependency on any menu node
  - Stale-hold guard ported as `_master_hold_token`; auto-unmute invalidates a pending Master hold (T4 replaces the token with an idempotent re-sync)
  - Does not save; persistence stays with callers. No caller yet (T5/T6)
  - Doc comments on `set_volume()` and `set_bus_state()` state that the raw setters bypass the rule
- **Tests**
  - New `test/gut/test_audio_manager_change_volume.gd` (no scene, parameterized over all six buses): manual vs programmatic in both directions, repeated near-zero no-ops, Master hold then flatten, raise/unmute during the hold, raw setters, config load and reset bypass, unknown bus. CodeRabbit added boundary values, never-saves, other-bus isolation and the not-in-tree path (`570720c`)
  - Three tests added with the auto-unmute fix (`1c3ff94`): programmatic auto-unmute, manual auto-unmute, and programmatic down-then-up, each asserting `AudioServer.is_bus_mute()` on all six buses
  - New `test/gut/test_sfx_manager.gd` (CodeRabbit, `570720c`): LRU recency, failure caching, pool saturation, freed players, invalid-bus fallback, cleanup and lazy pool rebuild
  - 20 GUT suites and 1 GdUnit4 suite moved their SFX calls, spies and node swaps from `AudioManager` to `SfxManager`
  - `test_audio_sfx_centralization.gd`: the pool node-count test now counts `SfxManager`'s children. Counting `AudioManager`'s would compare 0 to 0 and could never fail
- **Docker / local pipeline** (`Dockerfile`, `workspace/run_browser_tests.sh`, `workspace/run_pipeline.sh`)
  - Image installs `.github/scripts/requirements-docs.txt` (`pydantic` and friends, #1055), so `tests/ci/test_update_gdscript_docs.py` can be collected, as the CI "CI & Security" shard already does
  - Image installs `yamllint==1.38.0` (the version CI's `yamllint.yml` currently installs), so the pipeline's YAML Lint step can run
  - Both scripts trust `/project/.git` in addition to `/project`. Since git 2.45.1 a local clone of a repository owned by another user also checks the git directory; without it the `isolated_repo` fixture in `tests/ci/test_docstrings_workflow.py` failed 12 tests with "dubious ownership"
- **Docs**
  - This milestone note; a one-line formatting fix in `files/docs/Development_Guide.md`

### Design Decisions

- **Split `SfxManager` instead of raising the lint limit.** A `.gdlintrc` with `max-public-methods: 25` was tried first and dropped: it loosens the rule for every script, while the split removes the cause. An inline suppression can't work, because gdlint reports this rule at line 1 (the copyright header).
- **`AudioManager.cleanup_for_test()` stays.** It delegates to `SfxManager`, so about 30 test teardowns need no change.
- **Port the rule, but keep the mixer consistent.** T2 reproduces today's mute decisions so the move is reviewable on its own; T3 (crossings) and T4 (re-sync after auto-mute, token removal) change them in a later PR. The one deliberate difference is auto-unmute: today's menu path never sets the `AudioServer` mute flag on auto-mute, so it never has to clear it, but `change_volume()` writes the flag up front and therefore must clear it on unmute.
- **No callers yet.** Routing callers (T5) and reducing the menu callback to a visual-only observer (T6) must land together, otherwise the menu and the manager would both apply the rule.
- **Raw setters stay rule-free.** `set_bus_state()` (used by init, config load and reset) calls `set_volume()` then `set_muted()`; enforcing the rule there would emit a spurious unmute/re-mute for `{0.5, muted}`.
- **Pin `yamllint` in the image.** CI installs the latest release on every run; the image pins the same version (1.38.0) so local runs are reproducible.

### Public API moves

| Before                                                                                                                              | After                                                |
|-------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------|
| `AudioManager.play_sfx()`                                                                                                           | `SfxManager.play_sfx()`                              |
| `AudioManager.stop_all_sfx()`                                                                                                       | `SfxManager.stop_all_sfx()`                          |
| `AudioManager.is_any_sfx_playing()`, `get_active_sfx_playback_count()`, `get_active_sfx_stream_path()`, `get_active_sfx_bus_name()` | `SfxManager.*` (same names)                          |
| `AudioManager.MAX_SFX_CACHE_SIZE`, `SFX_POOL_SIZE`                                                                                  | `SfxManager.*`                                       |
| `AudioManager.cleanup_for_test()`                                                                                                   | unchanged; also resets `SfxManager`                  |
| –                                                                                                                                   | `AudioManager.change_volume()` (new, no callers yet) |

### Compatibility

- **No runtime behavior change:** `change_volume()` has no callers, and the SFX code moved verbatim.
- **Internal API change:** SFX calls move from `AudioManager.*` to `SfxManager.*` (see the table). Any other branch or local copy must register the `SfxManager` autoload before `AudioManager` and take all renamed call sites.
- Save format and bus layout unchanged.
- The local Docker image must be rebuilt (`docker build -t sky-lock-assault-pipeline .`).

### Testing

- Full GUT suite, headless Godot 4.7.1 + GUT 9.7.1 with the Dummy audio driver (same setup as CI)
  - `main` @ `7539ed5` (baseline): 97 scripts, **668/668 passed**
  - Refactor + T2 (`db3a64c`): 98 scripts, **688/688 passed**
  - With CodeRabbit's tests (`570720c`): 99 scripts, 706/708; the 2 failures (`test_sfx_manager.gd`, child count 32 vs 8) came from orphaned players left by the `set_script` spy suites
  - Orphan fix (`e57f2ed`): 99 scripts, **708/708 passed**
  - Final code (`1c3ff94`): 99 scripts, **711/711 passed**
- Mutation check: with the auto-unmute fix reverted, the three new auto-unmute tests fail (programmatic and manual auto-unmute, programmatic down-then-up); with the fix they pass
- `gdformat --check` and `gdlint` clean on `./scripts`; `AudioManager` at 15/20 public methods with no config override
- `yamllint 1.38.0 -c .yamllint.yaml .github/workflows/*.yml`: clean
- Listener-registration test (`test_globals_button_hooks.gd`): with the `is_connected()` guard removed from `SfxManager._ready()`, it still passes, because Godot never creates a duplicate connection for the same callable. Kept as harmless (see follow-ups)
- Local Docker, `run_browser_tests.sh` before the `safe.directory` fix: 500 passed, 12 errors, all in the `isolated_repo` fixture; reproduced by hand (`fatal: detected dubious ownership in repository at '/project/.git'`)
- CI on `1c3ff94`: GUT, GdUnit4, gdlint, Markdown Lint, CI/CD Infrastructure Tests and the browser shards Build, CI & Security and Refactor passed
- [ ] CI: Browser "Core Web Flows" shard green, and all jobs green on the final head
- [ ] Local Docker: full `run_pipeline.sh` passes after the image rebuild

### Known limitations / follow-ups

- The menu still applies its own copy of the rule in `_on_global_volume_changed` until T5/T6 (#1042, #1043) land together.
- T3 (#1040) inverts `test_just_above_threshold_unmutes_audible_muted_bus`, and T4 (#1041) removes `_master_hold_token` and `test_cleanup_invalidates_pending_master_hold`. Both tests are correct for T2 and disposable after.
- The listener-registration test in `test_globals_button_hooks.gd` cannot fail; it could be removed.
- `main_menu.gd` filters dialog-button connections by `Globals._on_global_button_pressed`. The hook lived on `AudioManager` and now lives on `SfxManager`, so the filter never matches. Harmless, since the hook already skips dialog buttons.
- `requirements.txt` is saved as UTF-16; pip reads it, most other tools don't.
- The epic DoD says config load round-trips `{volume, muted}` exactly, but load still forces a zero-volume bus to muted (#1046). Reword the DoD or record the exception.
- The branch history contains a reverted commit and an empty merge (#1067): use **Squash and merge**.

---

## Reviewer's Guide

Moves SFX playback out of `AudioManager` into a new `SfxManager` autoload to get under gdlint's public-method cap, then adds `AudioManager.change_volume()`, which ports the near-zero auto-mute rule from the Audio Settings menu with an explicit `is_manual_interaction` flag, an autoload-owned Master feedback hold, and an auto-unmute that keeps the mixer in step with the manager. No caller uses it yet. Test suites follow the move, new suites cover `change_volume()` and `SfxManager`, a test-only pool leak is fixed, and the local Docker pipeline is brought in line with CI (docs-generator dependencies, `yamllint`, git `safe.directory`).

### File-Level Changes

| Change                                              | Details                                                                                                                                                                                                                                                                                                                                                                                                                | Files                                                                                                                                                                                                                                                                                    |
|-----------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Split SFX playback into its own autoload.           | <ul><li>Move the pool, cache, <code>play_sfx</code>, <code>stop_all_sfx</code>, diagnostics and button hook to <code>SfxManager</code>.</li><li>Register it before <code>AudioManager</code>.</li><li><code>AudioManager.cleanup_for_test()</code> delegates; <code>toggle_mute()</code> clicks via <code>SfxManager</code>.</li><li><code>SfxManager.cleanup_for_test()</code> also frees orphaned players.</li></ul> | `scripts/managers/sfx_manager.gd`<br/>`scripts/managers/sfx_manager.gd.uid`<br/>`scripts/managers/audio_manager.gd`<br/>`project.godot`                                                                                                                                                  |
| Move SFX call sites.                                | <ul><li>Replace <code>AudioManager.play_sfx</code> and related calls with <code>SfxManager</code>.</li><li><code>VolumeSlider</code> resolves <code>/root/SfxManager</code>.</li></ul>                                                                                                                                                                                                                                 | `scripts/managers/ui_manager.gd`<br/>`scripts/ui/components/volume_slider.gd`<br/>`scripts/ui/menus/advanced_settings.gd`<br/>`scripts/ui/menus/audio_settings.gd`<br/>`scripts/ui/menus/gameplay_settings.gd`<br/>`scripts/ui/menus/key_mapping.gd`<br/>`scripts/ui/menus/main_menu.gd` |
| Add the volume entry point.                         | <ul><li><code>change_volume(bus, volume, is_manual_interaction)</code>: store, write <code>AudioServer</code>, apply the ported rule.</li><li>Auto-unmute applies the unmuted state to <code>AudioServer</code> for every bus and caller.</li><li>Manual-only click and Master hold; <code>_master_hold_token</code> guard; no save.</li><li>Raw-setter doc comments.</li></ul>                                        | `scripts/managers/audio_manager.gd`                                                                                                                                                                                                                                                      |
| Cover the entry point and the new manager.          | <ul><li>Manager-level suite over all six buses, with boundary, contract and mixer-mute tests.</li><li><code>SfxManager</code> cache, pool and cleanup suite.</li></ul>                                                                                                                                                                                                                                                 | `test/gut/test_audio_manager_change_volume.gd`<br/>`test/gut/test_sfx_manager.gd` (+ `.uid` files)                                                                                                                                                                                       |
| Migrate existing suites to <code>SfxManager</code>. | <ul><li>SFX calls, spies (<code>set_script</code>) and node swaps target <code>SfxManager</code>.</li><li>Pool node-count test counts <code>SfxManager</code>'s children.</li></ul>                                                                                                                                                                                                                                    | 20 suites under `test/gut/`<br/>`test/gdunit4/test_gdunit_all_menus_navigation_regression.gd`                                                                                                                                                                                            |
| Bring the local Docker pipeline in line with CI.    | <ul><li>Install <code>.github/scripts/requirements-docs.txt</code> and <code>yamllint==1.38.0</code> in the image.</li><li>Trust <code>/project/.git</code> for local clones in both pipeline scripts.</li></ul>                                                                                                                                                                                                       | `Dockerfile`<br/>`workspace/run_browser_tests.sh`<br/>`workspace/run_pipeline.sh`                                                                                                                                                                                                        |
| Record the implementation and review context.       | <ul><li>Add the milestone note for this part.</li><li>One-line formatting fix in the development guide.</li></ul>                                                                                                                                                                                                                                                                                                      | `files/docs/milestones/26/Part_8_Add_AudioManager_change_volume_and_split_SfxManager.md`<br/>`files/docs/Development_Guide.md`                                                                                                                                                           |

### Assessment against linked issues

| Issue                                                   | Objective                                                                            | Addressed | Explanation                                                                  |
|---------------------------------------------------------|--------------------------------------------------------------------------------------|-----------|------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1039> | `change_volume()` reproduces today's rule for all six buses.                         | ✅        | Parameterized over all six buses.                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1039> | `set_volume`, `set_bus_state`, `load_volumes`, `reset_volumes` never apply the rule. | ✅        | Covered by the raw-setter, config-load and reset tests.                      |
| <https://github.com/ikostan/SkyLockAssault/issues/1039> | No SFX when `is_manual_interaction == false`.                                        | ✅        |                                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1039> | Hold runs from the autoload (no dependency on any menu node).                        | ✅        | Suite asserts no Audio Settings menu is in the tree.                         |
| <https://github.com/ikostan/SkyLockAssault/issues/725>  | The rule works with the menu closed (epic DoD).                                      | ➖        | Out of scope for T2: callers switch over in T5/T6, which must land together. |

---

## Review decisions

| Finding                                                                                         | Severity | Decision                                | Reason                                                                                                                                                                                        |
|-------------------------------------------------------------------------------------------------|----------|-----------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Sourcery: SFX tests target the wrong manager                                                    | High     | **Stale**                               | Reviewed on `dd153a3`, where a revert had removed `SfxManager` but kept the test renames. The final head registers the autoload.                                                              |
| Sourcery: SFX teardown cleans the wrong manager                                                 | Medium   | **Stale**                               | Same tree. On the final head `AudioManager.cleanup_for_test()` delegates to `SfxManager.cleanup_for_test()`.                                                                                  |
| CodeRabbit: use `AudioManager` for SFX calls (all-menus navigation, integration, volume slider) | Major    | **Stale, withdrawn**                    | Same tree; applying them would reintroduce `Nonexistent function 'stop_all_sfx'`. CodeRabbit withdrew them after the reply.                                                                   |
| CodeRabbit: re-enter `SfxManager` in the listener-registration test                             | Minor    | **Declined**                            | Godot never creates a duplicate connection for the same callable, so the count cannot exceed 1 whichever `_ready()` runs; verified by removing the guard. CodeRabbit agreed.                  |
| CodeRabbit assessment: manager is not yet the single volume path                                | –        | **Out of scope**                        | T5/T6 (#1042, #1043), per the epic's implementation order.                                                                                                                                    |
| CodeRabbit generated tests (`570720c`): 2 failures in the full suite                            | –        | **Fixed** (`e57f2ed`)                   | Root cause was a test-only leak: `set_script` spy suites orphaned pool players. Fixed in `SfxManager.cleanup_for_test()`.                                                                     |
| CodeRabbit: apply the unmuted state during auto-unmute                                          | Minor    | **Fixed** (`1c3ff94`)                   | Valid: programmatic calls and non-Master buses stayed muted in `AudioServer`. Now applied for every bus and caller; the Master hold-token invalidation is kept. CodeRabbit confirmed the fix. |
| CodeRabbit: assert the target bus hardware mute state on every unmute path                      | Minor    | **Addressed** (`1c3ff94`), bot-resolved | The three new tests assert `AudioServer.is_bus_mute()` on the programmatic, manual and down-then-up unmute paths for all six buses; CodeRabbit marked the thread addressed.                   |

---

## Contribution Summary

### Human contribution (@ikostan)

- **Planning and scope**
  - Started the epic's PR 3 with T2 (#1039).
  - Questioned the `.gdlintrc` override that raised `max-public-methods` for every script, asked whether `audio_manager.gd` could be refactored to need fewer public methods instead, chose the `SfxManager` split, and decided to land the refactor before T3/T4.
  - Decided to finish the PR with the refactor and T2 only and to move T3/T4 to a later PR, since the split already touches 41 files.
- **Implementation and integration**
  - Applied the refactor in the Godot editor, registered the `SfxManager` autoload and moved it above `AudioManager` in Project Settings → Autoload.
  - Ran the GUT suites locally after each step and reported every failing file with its debugger output (`test_all_menus_navigation_regression.gd`, `test_audio_settings_interaction.gd`, `test_audio_sfx_centralization.gd`). That report exposed the vacuous pool node-count test, which then got fixed.
  - Opened PR #1068 and approved the force-push that restored the full refactor after the reverted commit `3cf9302` had left the branch with test renames only.
  - Pushed the orphaned-player fix for `SfxManager.cleanup_for_test()` (`e57f2ed`) after CodeRabbit's generated tests failed in the full suite, and the auto-unmute fix with its tests (`1c3ff94`).
- **Review leadership**
  - Reviewed every Sourcery and CodeRabbit finding before acting and asked for an opinion on each instead of applying suggestions blindly. That stopped the stale "use `AudioManager`" suggestions from undoing the refactor.
  - Pushed back on the claim that the listener-registration test needed a fix. The experiment that followed confirmed the test can't fail in Godot 4 whichever `_ready()` runs, so nothing was changed.
  - Brought CodeRabbit's auto-unmute finding forward, confirmed it was valid, and checked whether its follow-up test request was already covered before resolving it.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Triaged the Sourcery and CodeRabbit findings, proved the listener-registration test cannot fail, fixed the vacuous pool node-count test, and diagnosed the 2 failing CodeRabbit tests as an orphaned-player leak.
  - Confirmed CodeRabbit's auto-unmute finding as a real bug in the new entry point, drafted the fix and the three mixer-mute regression tests (applied as `1c3ff94`), and verified them by mutation: they fail without the fix. Caught that a first version of one test used two `use_parameters` arguments, which GUT rejects (the test silently did nothing), and split it.
  - Diagnosed the local Docker failures: missing `requirements-docs.txt` install, a stray line continuation in the first Dockerfile change that would have turned the `COPY` line into `chmod` arguments, git's "dubious ownership" check on `/project/.git` (git ≥ 2.45.1), and the missing `yamllint`. Verified `yamllint 1.38.0` against the workflows.

- **@sourcery-ai**
  - Generated "Summary by Sourcery" and, on request, the Reviewer's Guide.
  - Posted two findings (1 High, 1 Medium) on `dd153a3`; both stale on the final head.

- **@coderabbitai**
  - Generated "Summary by CodeRabbit" and the linked-issue assessment.
  - Posted four findings on `dd153a3` (three stale and withdrawn, one declined with agreement).
  - Authored `570720c` (`Add regression tests for SfxManager and audio volume boundaries`): 9 tests in `test_audio_manager_change_volume.gd`, the new `test_sfx_manager.gd`, and the `test_globals_button_hooks.gd` rename.
  - Posted two later findings on the entry point: the auto-unmute mixer state (valid, fixed in `1c3ff94`, fix confirmed) and the matching test assertions (marked addressed and resolved by the bot).

- **@deepsource-io**
  - Ran static analysis and posted the report card (overall A); no inline issues.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
