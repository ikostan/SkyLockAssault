# Part 2: Add UI auto-mute with click SFX and expand audio integrity tests

## Technical Session Summary & Architectural Documentation

Add automatic near-zero volume auto-mute/unmute behavior with click sound
feedback across audio buses, centralize UI mute handling, harden audio SFX
loading, and expand tests and CI workflows to support the new audio behavior
and asset integrity checks.

New Features:

- Introduce auto-mute and auto-unmute coupling between volume sliders and
- bus mute state based on a near-zero volume threshold, with click SFX
- feedback for focused UI interactions.

Enhancements:

- Centralize audio UI mute toggle logic into shared helpers that map buses to
  sliders/buttons and apply deferred hardware mutes for safer click playback.
- Strengthen AudioManager SFX playback by short-circuiting missing resources
  via a tracked cache and avoiding engine errors when SFX files are absent
  or invalid.
- Align volume slider expectations and tests with configured step sizes and
  debounce behavior to reduce flakiness and better reflect real UI behavior.
- Add integrity scanning for sprite and audio assets to ensure they load and
  parse correctly in headless and CI environments.

CI:

- Tighten browser and GUT test workflows with pinned third-party actions,
  explicit yamllint suppressions, improved cache keys, dummy audio driver
  usage, and updated Codecov integration.
- Relax and rebalance stale issue/PR workflow timings while pinning the
  stale action to a specific commit for supply-chain safety.

Documentation:

- Expand the milestone UI audio persistence test-plan document with a
  reviewer guide, file-level change breakdown, and mapping against linked
  issues for coverage tracking.

Tests:

- Extend GUT and GDUnit4 suites with comprehensive coverage for auto-mute
  thresholds, focus-driven SFX feedback, silent programmatic updates, SFX
  pooling/LRU behavior, and encrypted config handling.
- Adjust existing audio reset, volume control, mute logic, and UI
  persistence tests to account for timing delays, slider snapping, and
  headless environment constraints.
- Add new comprehensive audio settings and SFX centralization tests plus
  asset integrity suites for sprites and audio resources.

Chores:

- Reconfigure stale workflow thresholds and messages to better match
  project activity cadence while improving security via action pinning.

### Architectural Documentation: Mute Signal Isolation & Decoupling Patterns

To prevent automated updates from triggering unintended audio feedback,
the UI layer implements a strict input focus-gating pattern. Audio
feedback streams (such as the `"check"` SFX asset) are structurally isolated
within execution blocks that validate runtime UI focus states:

* **Slider Proxy Inputs:** Volume sliders check `active_slider.has_focus()`
  during boundary threshold evaluations before permitting audio
  playback tracking.
* **Centralized Mute Toggles:** The underlying utility function
  `_execute_bus_mute_toggle()` computes focus dynamically prior to
  state execution:

<!-- markdownlint-disable MD013 -->

```gdscript
var has_user_focus: bool = (button != null and button.has_focus()) or (slider != null and slider.has_focus())
```
<!-- markdownlint-disable MD013 -->

---

## Reviewer's Guide

Implement focus-aware auto-mute/unmute behavior with click SFX across
all audio buses, centralize mute toggle handling, harden SFX playback
and asset loading, and expand/headless-proof the associated audio/UI
tests and CI workflows.

### File-Level Changes

<!-- markdownlint-disable MD013 MD033 table-column-style -->
| Change                                                                                                           | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Files                                                                                                                                                                                                                                                                                                                                                                                                                |
|------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Add symmetric auto-mute/unmute coupling to volume sliders with focus-gated click SFX for all audio buses.        | <ul><li>Extend _on_global_volume_changed to update sliders and apply near-zero AUTO_MUTE_VOLUME_THRESHOLD logic for auto-muting/unmuting per bus.</li><li>Gate click SFX playback on slider focus and introduce a master-specific token + hardware delay to let confirmation sounds play before forcing volume to 0 dB.</li><li>Use AudioManager.get_muted/set_muted and AudioServer bus indices to keep UI, manager state, and hardware volumes in sync when crossing the threshold.</li></ul>                                                                                                                                                                                                                               | `scripts/ui/menus/audio_settings.gd`<br/>`scenes/volume_controls/master_volume_control.tscn`<br/>`scenes/volume_controls/music_volume_control.tscn`<br/>`scenes/volume_controls/sfx_menu_volume_control.tscn`<br/>`scenes/volume_controls/sfx_rotors_volume_control.tscn`<br/>`scenes/volume_controls/sfx_volume_control.tscn`<br/>`scenes/volume_controls/sfx_weapon_volume_control.tscn`                           |
| Centralize mute toggle handling and bus-to-UI lookups with focus-aware click SFX and deferred hardware mute.     | <ul><li>Introduce _get_slider_for_bus and _get_mute_button_for_bus helpers to map AudioConstants bus names to scene controls with assertion-backed default branches.</li><li>Replace per-bus _on_*_mute_toggled implementations with a unified async _execute_bus_mute_toggle that updates AudioManager, UI interactivity, applies volume to the bus, defers hardware mute by MUTE_HARDWARE_DELAY, and saves volumes.</li><li>Play the shared "check" SFX only when the interaction originates from focused buttons/sliders, keeping background sync operations silent.</li></ul>                                                                                                                                             | `scripts/ui/menus/audio_settings.gd`<br/>`scripts/managers/audio_manager.gd`<br/>`files/sounds/sfx/check.wav.import`                                                                                                                                                                                                                                                                                                 |
| Harden centralized SFX playback to be safe against missing/corrupt resources and enforce pooling/LRU guarantees. | <ul><li>Guard AudioManager.play_sfx with ResourceLoader.exists before load, log warnings, and cache missing SFX in _missing_sfx_cache to avoid repeated disk hits.</li><li>Differentiate between missing and unparseable streams in log messages while preserving the LRU cache semantics and fixed pool size.</li><li>Add GUT tests that validate pool overlap behavior, flooding/hijack behavior, LRU eviction, missing-asset suppression, and constant AudioManager child count.</li></ul>                                                                                                                                                                                                                                 | `scripts/managers/audio_manager.gd`<br/>`test/gut/test_audio_sfx_centralization.gd`<br/>`test/gut/test_audio_sfx_centralization.gd.uid`                                                                                                                                                                                                                                                                              |
| Align audio UI tests with slider step behavior, encryption, and new mute-delay semantics.                        | <ul><li>Update many GUT tests (audio reset, music/SFX/weapon/rotor controls, reset scenarios, preserve_other_sections, audio_sync_decoupling) to use step-aligned values (e.g., 0.495/0.693/0.99) or assert_almost_eq tolerances instead of exact 0.5/0.7/1.0 expectations.</li><li>Introduce waits (~0.2s) in tests that depend on the new MUTE_HARDWARE_DELAY to ensure hardware mute/save completes before assertions.</li><li>Ensure tests use Globals.set_test_encryption_key and encrypted ConfigFile save/load where appropriate to avoid engine errors with encrypted configs.</li></ul>                                                                                                                              | `test/gut/test_audio_reset_button.gd`<br/>`test/gut/test_master_volume_control_and_music.gd`<br/>`test/gut/test_sfx_volume_control.gd`<br/>`test/gut/test_sfx_weapon_volume_control.gd`<br/>`test/gut/test_sfx_rotor_volume_control.gd`<br/>`test/gut/test_audio_sync_decoupling.gd`<br/>`test/gut/test_preserve_other_sections.gd`<br/>`test/gdunit4/test_audio_settings.gd`<br/>`test/gut/test_reset_scenarios.gd` |
| Add comprehensive auto-mute, signal-decoupling, and integrity tests for audio and sprite resources.              | <ul><li>Add test_audio_settings_comprehensive.gd to cover focus-driven auto-mute threshold behavior per bus, automation-vs-manual SFX triggering, idempotent near-zero updates, and upward unmute transitions with safety timing derived from production constants.</li><li>Add test_audio_signal_decoupling.gd to assert that programmatic AudioManager changes (e.g., WebBridge/Playwright) do not emit UI click SFX via pooled players.</li><li>Introduce asset integrity suites that recursively scan configured sprite and audio directories, loading each resource, validating dimensions/durations, and checking codec-specific data/image payloads.</li><li>Add corresponding .uid files for new GUT tests.</li></ul> | `test/gut/test_audio_settings_comprehensive.gd`<br/>`test/gut/test_audio_settings_comprehensive.gd.uid`<br/>`test/gut/test_audio_signal_decoupling.gd`<br/>`test/gut/test_audio_signal_decoupling.gd.uid`<br/>`test/gut/test_sprite_integrity.gd`<br/>`test/gut/test_sprite_integrity.gd.uid`<br/>`test/gut/test_audio_resource_integrity.gd`<br/>`test/gut/test_audio_resource_integrity.gd.uid`                    |
| Document the UI audio persistence/mute test plan and reviewer guidance.                                          | <ul><li>Extend the milestone 19 test-plan markdown with a detailed reviewer guide, file-level changes table, issue mapping table, and a summary of bot vs human contributions for the earlier UI bus persistence work.</li><li>Clarify which new GUT suites were added for UI audio persistence and mute logic, and how they satisfy specific GitHub issues (e.g., #499, #707–#712).</li></ul>                                                                                                                                                                                                                                                                                                                                | `files/docs/milestones/19/PART_1_test_plan_implementation_for_ui_bus_persistence.md`                                                                                                                                                                                                                                                                                                                                 |
| Tighten CI workflows for browser tests, GUT tests, stale labeling, and release drafting.                         | <ul><li>In browser_test.yml, adjust cache keys/IDs for pip and Playwright (including a step to extract the Playwright version), wrap long lines with yamllint disable/enable comments, and update the Codecov action SHA.</li><li>In gut_tests.yml, run Godot with --audio-driver Dummy under a timeout to initialize project/UIDs safely in headless CI.</li><li>In stale.yml, pin actions/stale to a specific commit (v10.3.0), relax and rebalance stale/close timings and messages for issues/PRs, and keep labels/exempt labels consistent.</li><li>In release_drafter workflows, update release-drafter action SHAs to a newer commit and keep config-name usage explicit.</li></ul>                                    | `.github/workflows/browser_test.yml`<br/>`.github/workflows/gut_tests.yml`<br/>`.github/workflows/stale.yml`<br/>`.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml`                                                                                                                                                                                                              |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                                                                                                                 | Addressed | Explanation |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/496 | Ensure the SFX_Menu audio bus is fully configured and treated as a first-class channel in code: BUS_SFX_MENU constant present and used, BUS_CONFIG registers menu_volume/menu_muted, and AudioManager exposes menu_volume/menu_muted properties wired through its volume/mute APIs.                                                                                                       | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/496 | Integrate the SFXMenu UI row into the AudioSettings scene using the sfx_menu_volume_control.tscn subscene (HSlider + mute CheckButton), structurally sequenced after the SFXRotors row.                                                                                                                                                                                                   | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/496 | Unify menu SFX UI behavior in audio_settings.gd with the other buses, including clean slider event processing, auto-mute/auto-unmute around a near-zero threshold, and centralized mute toggle handling for BUS_SFX_MENU.                                                                                                                                                                 | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/568 | Provide a dedicated `check.wav` audio feedback for all mute-related user interactions in the Audio Settings UI, wired through the centralized AudioManager SFX API and only triggered on explicit manual interactions (focused buttons/sliders), not on programmatic state changes.                                                                                                       | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/568 | Ensure the backend AudioManager exposes a robust, non-blocking SFX playback pipeline (pooled AudioStreamPlayers + LRU cache + missing-asset handling) that can safely serve `check.wav` and other UI sounds without stutter or engine errors in both normal and headless/CI environments.                                                                                                 | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/568 | Audit and prove mute signal decoupling via tests and documentation so that data-driven UI refreshes, initialization, WebBridge/Playwright sync loops, and other automated routines can mutate audio state in complete silence while manual hardware inputs still emit `check.wav` feedback.                                                                                               | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/569 | Add the `check.wav` sound asset to the SFX asset library under `res://files/sounds/sfx/` and ensure it is imported and tracked by Godot/source control.                                                                                                                                                                                                                                   | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/569 | Ensure `check.wav` is correctly loadable and referenceable via the standard SFX pipeline (e.g., `AudioManager.play_sfx`), suitable for playback on the `AudioConstants.BUS_SFX_MENU` bus, and accessible to future AudioManager integrations.                                                                                                                                             | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/569 | Integrate the new mute-toggle confirmation SFX without modifying or replacing existing audio assets, and validate asset integrity/import behavior in Godot (editor/exports).                                                                                                                                                                                                              | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/570 | Introduce a public centralized SFX playback API in AudioManager that UI components call via an identifier string (with safe default bus and optional overrides).                                                                                                                                                                                                                          | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/570 | Implement high-performance centralized SFX playback using a pre-allocated AudioStreamPlayer pool with hijacking under load, constant node count, and an LRU AudioStream cache plus failure cache to avoid I/O stutters and repeated disk lookups.                                                                                                                                         | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/570 | Wire UI/menu interactions to this centralized SFX system (e.g., click and auto-mute feedback using identifier-based SFX like "check"), ensuring correct bus routing, pitch/volume overrides support, and that programmatic updates do not trigger SFX.                                                                                                                                    | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/571 | Play the dedicated confirmation sound via AudioManager.play_sfx("check") whenever a user manually toggles any mute control (Master, Music, SFX, Weapon, Rotors, Menu) or triggers an intentional proxy unmute via slider interaction, with exactly one playback per physical interaction.                                                                                                 | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/571 | Ensure that audio feedback for mute/volume changes is strictly limited to direct, focused user interactions and remains completely silent for programmatic updates (initialization, config load/restore, WebBridge/Playwright sync, and other backend AudioManager changes), with no duplicate sounds per single human action.                                                            | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/571 | Update audio_settings.gd and related tests/documentation to encode and verify the new behavior (focus-gated click SFX, auto-mute/auto-unmute coupling, and signal decoupling) across all relevant buses and UI elements.                                                                                                                                                                  | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/572 | Implement focus-gated mute/volume audio feedback so that manual UI interactions (mute buttons, slider proxy toggles, auto-mute at threshold) play the click SFX exactly once, while programmatic state changes (AudioManager sync, WebBridge, Playwright, config load/reset, UI init) cannot reach those SFX paths.                                                                       | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/572 | Ensure that all automated operations (menu initialization, configuration load/reset, inbound WebBridge synchronization, headless/Playwright-driven changes) update UI and AudioManager state silently, with no unintended audio playback or coupling between automated data pipelines and hardware interaction listeners, and verify this via automated tests across all six audio buses. | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/572 | Formally document the mute signal isolation and decoupling patterns, including how focus-gated SFX, centralized mute toggle handling, and test coverage prevent regressions in future UI audio development.                                                                                                                                                                               | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/723 | Implement symmetric auto-mute and auto-unmute coupling for all six audio channels so that when a volume slider reaches a near-zero threshold the corresponding bus is muted, the associated CheckButton reflects the muted/unmuted state, and the behavior mirrors existing auto-unmute logic.                                                                                            | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/723 | Ensure confirmation audio feedback (check.wav) is played exactly once only for manual user adjustments (when the relevant HSlider or mute control has focus), remains completely silent during programmatic updates (WebBridge/config load/automated tests), and avoid feedback loops between slider changes and mute checkbox synchronization.                                           | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/723 | Wire the auto-mute/auto-unmute behavior into the existing volume_changed monitoring for all six channels and add tests/documentation that verify manual interactive cases (audible) and automated cases (silent) per the described scenarios.                                                                                                                                             | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/724 | Create a dedicated GUT unit test file that isolates and tests the auto-mute threshold rules for audio settings.                                                                                                                                                                                                                                                                           | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/724 | Verify correct auto-mute/auto-unmute state transitions, including manual (focused) vs programmatic/unfocused interactions, idempotent zero-volume updates, and coverage of all six primary audio buses with signal isolation under focus and non-focus contexts.                                                                                                                          | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/724 | Ensure the new tests are robust and compliant: they reset backend state in before_each/after_each for isolation, avoid unintended sound during background sync, and adhere to project linting (gdlint) and execution requirements (runnable via run_gut.sh selector).                                                                                                                     | ✅         |             |
<!-- markdownlint-enable MD013 MD033 table-column-style -->

---

This PR received substantial support from automated bots and AI-powered
tools for dependency management, code review, static analysis, and PR
summarization. These contributions improved security, CI reliability,
documentation quality, and overall code health.

### Automated Bots & AI Tools

- **@dependabot[bot]**: Managed dependency updates for GitHub Actions workflows,
  including version bumps for `codecov/codecov-action`, `actions/stale`, and
  `release-drafter/release-drafter`. This helped maintain supply-chain security
  and latest CI/CD features.
- **@sourcery-ai**: Provided a detailed PR summary covering new features (audio
  feedback, auto-mute/unmute), enhancements (centralized mute handling, SFX
  improvements), CI changes, expanded test coverage, and documentation updates.
- **@coderabbitai**: Delivered a focused summary highlighting finer slider controls,
  auto-mute logic with audio feedback, documentation updates, and maintenance
  chores (CI pinning and asset configuration).
- **@deepsource-io**: Performed automated static code analysis and code review.
  Evaluated changes across Security, Reliability, Complexity, and Hygiene
  categories, providing an overall grade, inline comments, and a comprehensive
  review report.

These automated contributions strengthened testing robustness, asset integrity 
checks, workflow pinning, and reviewer documentation.

---

### Human Maintainers

- **@ikostan**: Primary author and main contributor. Implemented core features
  including audio feedback for mute buttons, centralized mute handling with
  focus-aware SFX, auto-mute/unmute logic, AudioManager hardening (SFX pooling
  + LRU cache), extensive test suite updates (GUT/GDUnit4), CI refinements,
  and detailed milestone documentation with reviewer guides and sequence diagrams.

- **@espanakosta-jpg**: Contributed custom audio assets, specifically
  creating/updating `check.wav` and its `.import` file for improved UI click
  feedback.

---
