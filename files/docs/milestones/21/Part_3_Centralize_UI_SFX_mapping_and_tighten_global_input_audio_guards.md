# Centralize UI SFX mapping and tighten global input audio guards
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## Summary by Sourcery

Refine global UI input handling and audio routing to support device tracking, menu context guards, and data-driven SFX lookup, while expanding automated coverage around audio buses, mute controls, sliders, and button hooks.

### Overall PR Context

The PR focuses on refactoring global UI audio handling for better consistency, robustness, and test coverage in a Godot project. AI tools significantly aided in summarizing changes, spotting potential issues (e.g., flakiness, code complexity), and ensuring comprehensive test expansion. The final output benefited from iterative human refinements addressing bot feedback.

Enhancements:

- Introduce data-driven UI sound routing using logical action-to-SFX mappings and an asset map that decouples identifiers from file extensions and file layout.
- Improve global input processing with device tracking, menu-context detection helpers, echo and mouse-motion filtering, and targeted ui_accept/ui_cancel navigation guards.
- Adjust test infrastructure to avoid runner path brittleness, ensure bus availability in headless environments, and prevent cross-suite global state leakage.

Tests:

- Add extensive GUT suites for audio integration, volume hierarchy and slider focus behavior, global button hook registration, global input guards, and SFX asset resolution and input performance.
- Update existing audio SFX centralization and navigation/escape SFX tests to align with the new logical identifier mapping, input guards, and test runner discovery patterns.
- Expanded GUT coverage for audio focus gating, mute timing, hierarchy behavior, and input guardrails.

New Features:

- UI sounds are now driven by a centralized UI SFX mapping for consistent action audio.
- Sound playback now supports logical sound identifiers resolved via an asset map.

Bug Fixes:

- UI navigation/cancel/accept sounds are more tightly gated by GUI focus and control type.
- Mouse motion is ignored for UI sound triggering.
- Audio mute/unmute and slider focus/drag behavior are stabilized, preserving expected click feedback and hardware mute state.

Chores:

- Removed the unit-test runner script.

### Key Technical Decisions

- **Data-driven SFX routing** over hardcoded strings → easier asset management and future expansion.
- **Early-exit guards** in `Globals._input()` for performance and clarity.
- **Extensive GUT integration tests** rather than unit tests only → better coverage of AudioServer + UI focus interactions.
- Removal of `run_unit_tests.sh` → consolidation toward editor/GUT runner.

---

## Reviewer's Guide

Strengthens global UI input-to-audio routing by centralizing UI SFX mappings, refining Globals._input guards, and expanding GUT integration tests for audio mute hierarchy, button hooks, sliders, and ui_accept/ui_cancel behavior.

### File-Level Changes

| Change                                                                                                                                                                                       | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Files                                                                                                                                                                                                                                                                                   |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Refactor global input handling to track hardware devices, gate menu context more robustly, and route UI SFX via data-driven mappings instead of hardcoded logic.                             | <ul><li>Add echo-event and mouse-motion filters at the top of Globals._input.</li><li>Introduce _track_input_device to keep Globals.current_input_device in sync with key/mouse/gamepad usage.</li><li>Factor menu context detection into _check_menu_context using paused/options/hidden menus plus scene name/group/meta markers with debug/CI fallbacks.</li><li>Replace direct navigation/cancel sound logic with _process_ui_navigation_sfx and per-action handlers that consult AudioConstants.UI_SFX and prevent double audio for sliders and interactive controls.</li></ul>                                                                        | `scripts/core/globals.gd`                                                                                                                                                                                                                                                               |
| Introduce centralized audio constants for UI SFX logical IDs and asset filename resolution, and update AudioManager SFX playback to use them.                                                | <ul><li>Add UI_SFX map from input actions (ui_up/ui_down/ui_accept/ui_cancel, etc.) to logical SFX identifiers.</li><li>Add SFX_ASSET_MAP from logical SFX IDs to concrete filenames with extensions, including non-wav assets.</li><li>Change AudioManager.play_sfx to treat sfx_name as a logical ID, resolve through SFX_ASSET_MAP, and fall back to .wav if unmapped.</li></ul>                                                                                                                                                                                                                                                                         | `scripts/resources/audio_constants.gd`<br/>`scripts/managers/audio_manager.gd`                                                                                                                                                                                                          |
| Stabilize and extend key-mapping integration tests to avoid global state leakage and ensure consistent InputMap setup.                                                                       | <ul><li>Cache and restore Globals.current_input_device around the key-mapping suite.</li><li>Reset Globals.current_input_device to keyboard and clear/reload InputMap actions in before_each.</li><li>Preserve and restore user settings config via backup files in before_all/after_all.</li></ul>                                                                                                                                                                                                                                                                                                                                                         | `test/gut/test_integration_key_mapping.gd`                                                                                                                                                                                                                                              |
| Fix audio navigation and quit-dialog test discovery and robustness under GUT, and expand SFX centralization coverage.                                                                        | <ul><li>Switch audio routing tests to extend GutTest instead of the test.gd path for reliable discovery.</li><li>Fix a split string literal crash in test_nav_escape_sfx by consolidating the assertion message.</li><li>Load main_menu.tscn for quit-dialog tests to guarantee onready hierarchy is present.</li><li>Add tests to verify AudioManager.play_sfx resolves mapped asset extensions and uses .wav fallback, and that Globals._input ignores mouse motion events.</li></ul>                                                                                                                                                                     | `test/gut/test_nav_escape_sfx.gd`<br/>`test/gut/test_quit_game_confirm_dialog_sfx.gd`<br/>`test/gut/test_audio_sfx_centralization.gd`                                                                                                                                                   |
| Add integration suites for audio bus mute behavior, hierarchy propagation, slider drag focus-loss handling, and global button hook lifecycle.                                                | <ul><li>Add test_audio_integration.gd to validate SFX bus mute/unmute behavior, AudioServer bus creation, navigation focus gating, mute toggle signal isolation, rapid mute hardware cutoff cancellation, and deferred hardware cutoff for UI mute buttons.</li><li>Add test_audio_hierarchy_and_sliders.gd to verify master/SFX/multi-bus hierarchy locking/unlocking and resilient VolumeSlider drag state under window focus loss notifications.</li><li>Add test_globals_button_hooks.gd to assert global button hook inclusion/exclusion rules, reparenting idempotency, duplicate scan protection, and safe cleanup after node destruction.</li></ul> | `test/gut/test_audio_integration.gd`<br/>`test/gut/test_audio_hierarchy_and_sliders.gd`<br/>`test/gut/test_globals_button_hooks.gd`<br/>`test/gut/test_audio_hierarchy_and_sliders.gd.uid`<br/>`test/gut/test_audio_integration.gd.uid`<br/>`test/gut/test_globals_button_hooks.gd.uid` |
| Add integration tests ensuring global ui_accept and navigation guards bypass audio for interactive controls while preserving fallback audio for passive controls and stale focus navigation. | <ul><li>Introduce test_globals_input_guards.gd to exercise ui_accept bypass for CheckButton, sliders, BaseButton subclasses, and TextureButtons, while confirming passive controls still trigger global audio.</li><li>Add coverage that stale focus in a valid menu context still produces navigation SFX and that directional navigation events via Globals._input are not dropped.</li><li>Include UID tracking files for new test scripts.</li></ul>                                                                                                                                                                                                    | `test/gut/test_globals_input_guards.gd`<br/>`test/gut/test_globals_input_guards.gd.uid`                                                                                                                                                                                                 |
| Remove obsolete local unit test runner tooling from the workspace.                                                                                                                           | <ul><li>Delete workspace/run_unit_tests.sh to consolidate test execution away from this script.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `workspace/run_unit_tests.sh`                                                                                                                                                                                                                                                           |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                       | Addressed | Explanation |
|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/493 | Add a GUT integration test suite at res://test/gut/test_audio_integration.gd that verifies muted SFX bus propagation from AudioManager through UI button interaction to Godot's AudioServer, following the described Scenario A behavior and architectural nuances.             | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/493 | Add a GUT integration test in the same suite that verifies unmuted SFX bus behavior for UI button interaction and AudioServer state (Scenario B), confirming audible playback and correct hardware mute flags.                                                                  | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/493 | Configure the audio integration test suite with the specified lifecycle hooks and architectural requirements (placement under test/gut, using AudioManager.apply_volume_to_bus, targeting the parent SFX bus index, and sanitizing the AudioManager pool via cleanup_for_test). | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/764 | Implement correct UI audio behavior for navigation, accept, and cancel actions, including menu-context gating, echo mitigation, suppression for LineEdit/TextEdit and Slider controls, and protection against double audio on buttons/flat buttons/dialog internals.            | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/764 | Provide automated GUT test coverage (including test_nav_escape_sfx.gd and test_quit_game_confirm_dialog_sfx.gd and related new suites) to verify the specified UI audio behaviors and acceptance criteria.                                                                      | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/785 | Prevent global ui_accept audio from playing when toggling audio bus Mute CheckButtons via keyboard/gamepad, so only the local 'check' sound effect is heard.                                                                                                                    | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/786 | Update global UI input handling so that pressing ui_accept (Enter/Space) while a volume slider is focused does not play the generic ui_accept sound, leaving audio feedback only to slider horizontal adjustments.                                                              | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/786 | Add automated tests that verify ui_accept audio is suppressed for focused volume sliders (and similar controls) to prevent regressions of the unwanted sound.                                                                                                                   | ✅         |             |

### Possibly linked issues

- **#N/A**: PR creates test_audio_integration.gd with Scenario A/B mute propagation tests and proper setup/teardown exactly as the issue requests.
- **#FEATURE UI Audio Logic Unit Tests (GUT)**: PR implements the requested audio_settings UI-to-AudioManager GUT suites (mute, sliders, focus) plus extra global audio features.
- **#[FEATURE] UI Audio Logic Unit Tests (GUT)**: PR implements the requested nav/escape and quit dialog GUT tests and supporting Globals/AudioManager audio routing logic.

---

**Bots/AI Contributors to PR #784**

### AI/Bot-Assisted Contributions

These automated tools provided code summaries, reviews, suggestions, and analysis that influenced the development and refinement of the PR:

- **@sourcery-ai**: Generated the primary PR summary, reviewer's guide, and multiple code reviews with high-level feedback on focus gating, test brittleness, scene dependencies, timing in tests, and metadata files. Offered actionable prompts for addressing comments.
- **@coderabbitai**: Provided a detailed summary of new features, bug fixes, and tests. Posted actionable inline comments (e.g., on test flakiness in `test_audio_integration.gd` and `_input` function complexity/return limits). Included context from prior learnings in the repo.
- **@deepsource-io**: Performed a code review across changes (e.g., commits in the range 939000c...912c858), generating a PR report card with assessments on security, reliability, complexity, and hygiene. Included Python/JavaScript analysis links and inline issue summaries.

No evidence of other common bots like @dependabot in the visible PR activity, commits, or reviews.

These tools did not author code but provided valuable guardrails: Sourcery and CodeRabbit drove iterative refinements (especially around test robustness and input guard logic), while DeepSource contributed static analysis.

### Human Contributors

- **@ikostan**: Primary author who implemented the core changes—centralizing UI SFX mappings in `AudioConstants`, tightening global input guards in `Globals._input()` (device tracking, menu context, echo/mouse filters, focus-based navigation/accept/cancel logic), updating `AudioManager`, and adding/extending extensive GUT integration tests for audio buses, mute hierarchy, sliders, button hooks, and input guards. Also handled test infrastructure cleanup (e.g., removing `run_unit_tests.sh`).
- **@espanakosta-jpg**: No visible direct commits, reviews, or comments attributed in the PR timeline or files (based on available data). 

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
