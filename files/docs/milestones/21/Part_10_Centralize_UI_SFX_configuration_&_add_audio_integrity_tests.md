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

Centralizes SFX directory configuration into AudioConstants and wires AudioManager to use it, while adding tests that verify audio constants, asset paths, bus configuration, and UI SFX mappings are discoverable and correct.

### File-Level Changes

| Change                                                                                                                           | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Files                                                                                                         |
|----------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| AudioManager now resolves SFX paths via AudioConstants rather than a local hard-coded directory constant.                        | <ul><li>Removed the local SFX_DIR_PATH constant from the audio manager to avoid duplicate configuration sources.</li><li>Updated play_sfx path construction to use AudioConstants.SFX_DIR_PATH when building the full asset path.</li><li>Kept legacy behavior of appending .wav when needed while routing all resolution through the shared base directory constant.</li></ul>                                                                                                                    | `scripts/managers/audio_manager.gd`                                                                           |
| AudioConstants now exposes a unified SFX base directory constant instead of a single UI navigation sound path.                   | <ul><li>Replaced the UI_NAV_SOUND_PATH constant with a general SFX_DIR_PATH pointing to the SFX asset directory.</li><li>Documented SFX_DIR_PATH as the centralized configuration point for all game SFX asset paths.</li></ul>                                                                                                                                                                                                                                                                    | `scripts/resources/audio_constants.gd`                                                                        |
| Added GUT tests to enforce discoverability and integrity of audio constants, asset maps, bus configuration, and UI SFX mappings. | <ul><li>Added a test ensuring AudioConstants.SFX_DIR_PATH exists, is non-empty, ends with a slash, and the directory exists on disk.</li><li>Added tests that validate all audio bus name string constants and that BUS_CONFIG contains properly typed metadata for each bus.</li><li>Added tests that every SFX_ASSET_MAP entry resolves to a real file and that every UI_SFX mapping points to a defined logical SFX key.</li><li>Created associated UID file for the new test script.</li></ul> | `test/gut/test_audio_constants_discoverability.gd`<br/>`test/gut/test_audio_constants_discoverability.gd.uid` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                   | Addressed | Explanation                                                                                                                                                                                                                                                                                                                                                                    |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| https://github.com/ikostan/SkyLockAssault/issues/490 | Add global UI SFX configuration in audio_constants.gd, including a UI_SFX dictionary mapping UI input actions to SFX asset identifiers/paths under res://files/sounds/sfx/.                                                                                 | ❌         | The PR introduces a base SFX directory constant (AudioConstants.SFX_DIR_PATH) and related tests, and removes UI_NAV_SOUND_PATH, but does not add the requested UI_SFX dictionary or any explicit mapping from UI input actions to SFX assets.                                                                                                                                  |
| https://github.com/ikostan/SkyLockAssault/issues/490 | Update AudioManager.gd to integrate global UI audio handling by adding dedicated UI AudioStreamPlayer nodes and implementing _unhandled_input(event: InputEvent) to play navigation, accept, and cancel SFX.                                                | ❌         | The only change to AudioManager.gd is replacing a local SFX_DIR_PATH constant with AudioConstants.SFX_DIR_PATH for asset resolution. No UI-specific AudioStreamPlayer nodes or _unhandled_input implementation are added, and no logic for playing UI navigation/accept/cancel sounds is introduced.                                                                           |
| https://github.com/ikostan/SkyLockAssault/issues/490 | Ensure all UI sounds are routed through the SFX bus (AudioConstants.BUS_SFX) as part of the global UI audio integration.                                                                                                                                    | ❌         | The PR does not modify any bus routing or node bus assignments for UI sounds. Existing bus constants are only verified via tests; there is no new or updated routing logic to guarantee UI sounds use the SFX bus.                                                                                                                                                             |
| https://github.com/ikostan/SkyLockAssault/issues/801 | Port `_on_global_button_pressed()` from `globals.gd` to `audio_manager.gd` and adapt it to use the AudioManager internal playback pool (`_sfx_pool`) with `AudioConstants.BUS_SFX`.                                                                         | ❌         | The diff only changes the SFX directory path handling in `audio_manager.gd` (switching to `AudioConstants.SFX_DIR_PATH`) and adds discoverability tests for `AudioConstants`. There is no movement or modification of `_on_global_button_pressed()`, no integration with `_sfx_pool`, and no changes related to BUS_SFX routing.                                               |
| https://github.com/ikostan/SkyLockAssault/issues/801 | Update all legacy calls that explicitly reference `Globals._on_node_added` or `Globals._on_global_button_pressed` (including tests) to instead target AudioManager equivalents.                                                                             | ❌         | The PR does not modify any references to `Globals._on_node_added` or `Globals._on_global_button_pressed`. The only changes are to use `AudioConstants.SFX_DIR_PATH` in `play_sfx` and to add tests for `AudioConstants` paths, bus names, asset map integrity, and UI SFX referential integrity.                                                                               |
| https://github.com/ikostan/SkyLockAssault/issues/801 | Decouple global UI playback callbacks from `globals.gd` by wiring them into the unified internal audio mixing and playback system.                                                                                                                          | ❌         | No structural changes are made to global UI playback callbacks or to `globals.gd`. The PR improves audio constants usage and adds tests but does not re-route UI callbacks into the AudioManager playback engine or otherwise alter the coupling to `globals.gd`.                                                                                                              |
| https://github.com/ikostan/SkyLockAssault/issues/802 | Purge legacy and deprecated hooks/constants (`_on_node_added`, `_on_global_button_pressed`, `UI_NAV_SOUND_PATH`) from `scripts/core/globals.gd`.                                                                                                            | ❌         | The PR modifies `audio_manager.gd`, introduces `SFX_DIR_PATH` in `audio_constants.gd`, and adds a new GUT test file. It does not change `scripts/core/globals.gd`, nor does it remove the specified deprecated hooks or constants from that file.                                                                                                                              |
| https://github.com/ikostan/SkyLockAssault/issues/802 | Ensure the cleanup is validated by running systemic validation scripts and browser/system tests as described (lint, unit tests, browser tests, Playwright tests, and full pipeline), with any necessary code or documentation updates to reflect this pass. | ❌         | The PR does not include changes to scripts, configuration, or documentation related to `workspace/run_gdlint.sh`, `workspace/run_gut_unit_tests.sh`, `workspace/run_browser_tests.sh`, the Python/Playwright tests, or `workspace/run_pipeline.sh`. Any test execution mentioned in the PR is generic and not tied to the specific validation pipeline described in the issue. |

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
