# Centralize UI SFX configuration and add audio integrity tests
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## PR #827 Summary: UI Navigation Focus SFX & Global UI Audio Integration

**Author:** [@ikostan](https://github.com/ikostan)  
**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault/pull/827)  
**Milestone:** Milestone 21 – Implement Global UI SFX Layer & Decouple Settings  
**Labels:** enhancement, good first issue, testing, menu, audio, refactoring, EPIC

### What This PR Does
This PR centralizes sound effect (SFX) asset path configuration and strengthens testing for global UI audio features in the Godot-based SkyLockAssault project. It lays groundwork for consistent UI navigation sounds (focus, accept, cancel, etc.) by reducing duplication and improving maintainability.<grok-card data-id="3fea19" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

### Key Changes by File
- **`scripts/resources/audio_constants.gd`**:
  - Added `SFX_DIR_PATH` as the single source of truth for all SFX assets.
  - Replaced legacy `UI_NAV_SOUND_PATH`.
  - Enhanced constants for audio buses and mappings.<grok-card data-id="deced2" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

- **`scripts/managers/audio_manager.gd`**:
  - Updated `play_sfx()` to use the centralized `AudioConstants.SFX_DIR_PATH`.
  - Removed duplicated local path constants.<grok-card data-id="194b85" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

- **`test/gut/test_audio_constants_discoverability.gd`** (new):
  - Comprehensive GUT tests verifying:
    - Directory existence and format.
    - Bus name constants and `BUS_CONFIG` structure.
    - `SFX_ASSET_MAP` and `UI_SFX` referential integrity.
  - Includes associated `.uid` file.<grok-card data-id="e5d67d" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

### AI & Bot Support
- **@sourcery-ai**: Provided PR summary, Reviewer's Guide, and actionable review comments.
- **@coderabbitai**: Assisted with review tips and unit test ideas.
- **@deepsource-io**: Ran automated code review with a detailed Report Card.

### Relation to Broader Work
- Advances **EPIC #490** and related issues (#801, #802) around global UI audio handling, decoupling from `globals.gd`, and legacy cleanup.
- Note: Some full UI input routing and callback migration items are noted as still pending in the PR assessment.

### Testing & Status
- Changes tested in Godot editor.
- New unit tests added for long-term reliability.
- Multiple iterative commits by @ikostan incorporating bot feedback.

This is a solid refactoring step toward a cleaner, more maintainable audio system for UI interactions across the game.

---

## Developer Changelog

- **Centralized UI SFX path configuration** so audio asset locations have one authoritative source, preventing path drift between playback code and configuration/tests.
- **Hardened pooled SFX playback against Godot lifecycle timing** by safely handling calls before pool initialization and ignoring freed `AudioStreamPlayer` instances during playback and diagnostics.
- **Improved audio routing resilience** by validating requested buses and safely falling back to the dedicated menu-SFX bus when a caller supplies an invalid bus.
- **Expanded audio integrity coverage from static checks to runtime validation**: mapped assets must load as valid `AudioStream`s, fallback routing is exercised, and freed-player scenarios are tested end-to-end.
- **Preserved session-level caching of missing assets intentionally** to avoid repeated resource lookups and input-time micro-stutter when an asset is unavailable.
- **Strengthened type clarity in UI traversal code** to improve editor assistance and maintainability without adding runtime overhead.

---

## Player-Facing Impact

- UI navigation, confirmation, and cancellation sounds should be **more consistent and reliable** across menus.
- The game is more resilient during scene changes, startup timing, and audio-system edge cases—reducing the chance of missing UI sounds or runtime errors.
- Invalid or unavailable audio configuration now degrades more gracefully, favoring fallback behavior over broken or silent interactions.
- No intended gameplay changes; this is a **stability, consistency, and maintainability** improvement to the UI audio experience.

---

## Reviewer's Guide

Centralizes UI SFX configuration and input handling into shared managers/constants, hardens pooled audio playback, and adds regression/integrity tests to validate menu navigation and device-toggle audio behavior end-to-end.

### File-Level Changes

| Change                                                                                                                                                                        | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Files                                                                                                                                                                                                                                                                                                                                   |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Decouple global UI input/audio routing from Globals into a dedicated UiManager that owns menu-context detection and navigation/cancel SFX playback.                           | <ul><li>Remove _input-based UI SFX handling from globals.gd, including local navigation action list and helper methods.</li><li>Introduce ui_manager.gd singleton that processes input events, tracks current input device, checks menu contexts, and routes ui_accept/ui_cancel/navigation actions via AudioConstants.UI_SFX.</li><li>Use AudioConstants.NAV_ACTIONS instead of a duplicated _nav_actions array for navigation-guard logic.</li><li>Update multiple tests to send synthetic input through UiManager._input instead of Globals._input.</li></ul>                                                                                                                                                                                                                  | `scripts/core/globals.gd`<br/>`scripts/managers/ui_manager.gd`<br/>`test/gut/test_globals_input_guards.gd`<br/>`test/gut/test_nav_escape_sfx.gd`<br/>`test/gut/test_audio_integration.gd`<br/>`test/gut/test_audio_sfx_centralization.gd`                                                                                               |
| Centralize SFX directory and UI/action-related audio constants and reuse them across managers and menus.                                                                      | <ul><li>Replace UI_NAV_SOUND_PATH with a general SFX_DIR_PATH constant pointing at the SFX asset directory.</li><li>Add SFX_CHECK logical key and NAV_ACTIONS array for UI navigation actions to AudioConstants.</li><li>Use AudioConstants.SFX_DIR_PATH when resolving SFX asset paths in AudioManager.play_sfx instead of a local constant.</li><li>Pass BUS_SFX_MENU explicitly when playing confirmation audio in key_mapping device-toggle callbacks.</li></ul>                                                                                                                                                                                                                                                                                                              | `scripts/resources/audio_constants.gd`<br/>`scripts/managers/audio_manager.gd`<br/>`scripts/ui/menus/key_mapping.gd`                                                                                                                                                                                                                    |
| Harden AudioManager’s pooled SFX handling against uninitialized pools and freed AudioStreamPlayer instances while improving diagnostics.                                      | <ul><li>Add lazy initialization guard for the SFX pool inside play_sfx so calls before pool setup are safe.</li><li>Ensure pool iteration and selection in play_sfx checks is_instance_valid before using players, with a fallback that picks the first valid player or errors if none exist.</li><li>Guard is_any_sfx_playing, get_active_sfx_playback_count, stop_all_sfx, get_active_sfx_stream_path, and get_active_sfx_bus_name with is_instance_valid on each pooled player.</li><li>Tighten typing in traversal helpers (e.g., Node-typed child/parent variables) for clarity and editor support.</li></ul>                                                                                                                                                                | `scripts/managers/audio_manager.gd`                                                                                                                                                                                                                                                                                                     |
| Add audio constants discoverability and integrity tests to enforce configuration correctness, asset existence, bus routing fallbacks, and resilience to freed pool players.   | <ul><li>Introduce test_audio_constants_discoverability.gd to validate bus name constants, BUS_CONFIG structure/types, SFX_ASSET_MAP schema, UI_SFX referential integrity, and AudioConstants.SFX_DIR_PATH-based asset existence/loadability.</li><li>Add tests that verify fallback routing to BUS_SFX_MENU when an invalid bus is requested and that the fallback bus exists in AudioServer.</li><li>Add tests that confirm play_sfx continues to work when a pooled AudioStreamPlayer has been freed.</li><li>Register the new GUT test via a .uid file for runner discovery.</li></ul>                                                                                                                                                                                         | `test/gut/test_audio_constants_discoverability.gd`<br/>`test/gut/test_audio_constants_discoverability.gd.uid`                                                                                                                                                                                                                           |
| Extend regression coverage for UI navigation SFX across all menus and for device-toggle/key-mapping behaviors, including paused trees and silent initialization requirements. | <ul><li>Add test_all_menus_navigation_regression.gd to instantiate each menu scene, focus a control, push navigation input via the viewport, and assert ui_navigation.wav is played (including a variant for paused pause_menu).</li><li>Add test_device_toggle_audio_regression.gd to ensure keyboard/gamepad toggles in key_mapping_menu play check.wav and respect Globals.options_open and device state.</li><li>Add test_key_mapping_load_regression.gd with a mocked AudioManager to assert that key_mapping_menu _ready() does not play check SFX on initialization.</li><li>Adjust existing tests to clean up focus, unpause the SceneTree, and reset AudioManager state between runs to avoid crosstalk.</li><li>Register new regression tests via .uid files.</li></ul> | `test/gut/test_all_menus_navigation_regression.gd`<br/>`test/gut/test_device_toggle_audio_regression.gd`<br/>`test/gut/test_key_mapping_load_regression.gd`<br/>`test/gut/test_all_menus_navigation_regression.gd.uid`<br/>`test/gut/test_device_toggle_audio_regression.gd.uid`<br/>`test/gut/test_key_mapping_load_regression.gd.uid` |
| Refine key_mapping menu initialization and device-toggle audio behavior to avoid spurious sounds while providing explicit confirmation feedback.                              | <ul><li>Change key_mapping _ready() to use set_pressed_no_signal based on Globals.current_input_device for keyboard/gamepad toggles, preventing audio callbacks during initialization.</li><li>Simplify and clarify _ready() comments and JS bridge calls, keeping web-specific behavior but tightening code.</li><li>Explicitly play AudioConstants.SFX_CHECK on BUS_SFX_MENU inside _on_keyboard_toggled and _on_gamepad_toggled only when toggled_on is true.</li></ul>                                                                                                                                                                                                                                                                                                        | `scripts/ui/menus/key_mapping.gd`<br/>`test/gut/test_device_toggle_audio_regression.gd`<br/>`test/gut/test_key_mapping_load_regression.gd`                                                                                                                                                                                              |
| Document the centralized UI SFX configuration and new audio integrity/regression test suites as part of Milestone 21.                                                         | <ul><li>Add milestone doc Part_10_Centralize_UI_SFX_configuration_&_add_audio_integrity_tests.md summarizing the architectural changes, tests, bots’ contributions, and relation to EPIC #490 and related issues.</li><li>Describe developer-facing changes (centralized path config, hardened playback, fallbacks, expanded tests) and player-facing impact (more consistent UI audio).</li></ul>                                                                                                                                                                                                                                                                                                                                                                                | `files/docs/milestones/21/Part_10_Centralize_UI_SFX_configuration_&_add_audio_integrity_tests.md`                                                                                                                                                                                                                                       |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                         | Addressed | Explanation |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/490 | Decouple global UI input handling from Globals by introducing a UiManager singleton that intercepts input, tracks the active device, evaluates menu context, and triggers navigation/cancel SFX, while removing the input/SFX logic from Globals.gd.              | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/490 | Centralize UI SFX configuration and routing by using AudioConstants for SFX paths and navigation action lists, and ensure global UI navigation/cancel and device-toggle sounds are played via AudioManager using the appropriate SFX buses.                       | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/490 | Update and expand test coverage to validate the decoupled UiManager input pipeline, audio constants integrity, menu navigation SFX across all menus (including paused states), device toggle audio behavior, and silent initialization of the key mapping menu.   | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/801 | Port global button pressed audio callback logic from globals.gd to audio_manager.gd and adapt it to use AudioManager's pooled playback (_sfx_pool) with centralized SFX configuration (AudioConstants.SFX_DIR_PATH, UI_SFX, BUS_SFX_MENU).                        | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/801 | Migrate the global UI input listener loop and input-device tracking out of globals.gd into a dedicated UiManager singleton, routing UI navigation/accept/cancel SFX via AudioManager and AudioConstants, and keeping it active even when the SceneTree is paused. | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/801 | Update legacy references across the codebase (including tests) that called Globals._on_node_added, Globals._on_global_button_pressed, or Globals._input so they now target AudioManager and UiManager equivalents instead.                                        | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/802 | Purge legacy UI audio/input handling and deprecated hooks/constants from globals.gd (including removal of UI_NAV_SOUND_PATH usage and moving global input/SFX logic out of the globals singleton so no dead UI audio code remains there).                         | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/802 | Centralize SFX asset path configuration and UI navigation SFX handling into dedicated resources/managers (e.g., AudioConstants, AudioManager, UiManager), with code using the centralized constants rather than legacy globals.                                   | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/802 | Strengthen and document automated test coverage for global UI audio behavior and configuration (GUT tests for audio constants, navigation/cancel SFX, menu/device toggle regression, and milestone documentation reflecting this verification).                   | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/828 | Ensure that toggling the Keyboard device CheckButton in the Key Mapping / Controls menu plays the check.wav confirmation sound via the audio system.                                                                                                              | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/828 | Ensure that toggling the Gamepad device CheckButton in the Key Mapping / Controls menu plays the check.wav confirmation sound via the audio system.                                                                                                               | ✅         |             |

### Possibly linked issues

- **#490**: PR delivers EPIC #490: adds UiManager, centralized AudioConstants-based UI SFX, reroutes input, and comprehensive audio tests.

---

## Bots/AI Contributions Summary for PR #827

This PR received significant support from AI-powered code review and automation bots that provided summaries, feedback, reviews, and testing prompts.

### AI / Bot Contributors
- **@sourcery-ai** — Generated the main PR summary, Reviewer's Guide, and left detailed code review comments (e.g., suggestions around `UI_NAV_SOUND_PATH` replacement and discoverability). Offered commands for further interactions like `@sourcery-ai review` or `@sourcery-ai summary`.
- **@coderabbitai** — Contributed finishing touches, unit test generation suggestions, and overall code review assistance (highlighted in the PR conversation with thanks for OSS support).
- **@deepsource-io** (DeepSource Code Review / DeepsourceReview) — Performed automated static analysis and code review on the changes (covering commits including `d6b9071...0155c0c`). Provided a PR Report Card with grades for Security, Reliability, Complexity, and Hygiene, plus inline issue comments.

(No visible contributions from `@dependabot` or similar dependency bots in this PR.)

### @ikostan Contributions (Human Maintainer)

@ikostan is the sole human author and primary contributor:

- Authored and iterated on all code changes through multiple commits.
- **Core work**:
  - Centralized SFX directory configuration (`SFX_DIR_PATH`) in `scripts/resources/audio_constants.gd`.
  - Updated path resolution logic in `scripts/managers/audio_manager.gd`.
  - Added a full GUT test suite (`test/gut/test_audio_constants_discoverability.gd`) validating constants, asset maps, bus configs, and referential integrity.
- Drove the PR forward, applied bot feedback, added labels/milestone, and triggered bot reviews.

These bot contributions helped refine the code quality, documentation, and test coverage while @ikostan handled the architectural implementation.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
