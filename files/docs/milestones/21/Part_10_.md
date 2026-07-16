# UI Navigation Focus SFX & Global UI Audio Integration
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

### Overview

This pull request centralizes SFX (sound effects) path configuration and improves audio asset discoverability and integrity testing for the SkyLockAssault project. It focuses on refactoring audio-related constants and managers to support a more consistent global UI audio system, while adding robust GUT (Godot Unit Test) coverage.<grok-card data-id="36c6ab" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

This PR primarily advances audio configuration centralization and testing for UI navigation SFX in the SkyLockAssault project. Multiple AI-powered code review and automation bots contributed through summaries, reviews, feedback, and prompts.

### Key Changes

- **AudioConstants (`scripts/resources/audio_constants.gd`)**:
  - Introduced `SFX_DIR_PATH` as a unified base directory constant for all game SFX assets (`res://files/sounds/sfx/`).
  - Replaced legacy `UI_NAV_SOUND_PATH` with the broader `SFX_DIR_PATH`.
  - Added documentation and structural improvements for SFX asset mapping and bus configuration.<grok-card data-id="19c5e7" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

- **AudioManager (`scripts/managers/audio_manager.gd`)**:
  - Updated `play_sfx` logic to resolve paths through `AudioConstants.SFX_DIR_PATH` instead of hard-coded local constants.
  - Removed duplicated `SFX_DIR_PATH` to eliminate configuration drift.<grok-card data-id="f65ecd" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

- **Testing (`test/gut/test_audio_constants_discoverability.gd` + `.uid`)**:
  - New comprehensive test suite validating:
    - `SFX_DIR_PATH` existence, format, and disk presence.
    - Audio bus name constants and `BUS_CONFIG` structure/metadata.
    - `SFX_ASSET_MAP` integrity and referential links from `UI_SFX` mappings.
  - Ensures audio configuration is discoverable and production-ready.<grok-card data-id="2ff807" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

### AI/Bot Contributions

- **@sourcery-ai**: Generated PR summary, Reviewer's Guide, and code review feedback.
- **@coderabbitai**: Provided review assistance and unit test generation prompts.
- **@deepsource-io**: Automated code review with Report Card (Security, Reliability, etc.).

### Related Issues / EPIC

- Partially addresses **EPIC #490** (Global UI SFX configuration and integration) and linked issues (#801, #802) around decoupling from `globals.gd`, callback migration, and legacy cleanup.
- Note: Some broader UI input handling (`_unhandled_input`, dedicated players, full globals purge) appears pending based on the self-assessment in the PR.<grok-card data-id="6d2142" data-type="citation_card" data-plain-type="render_inline_citation" ></grok-card>

### Testing & Validation

- Changes were tested in Godot editor.
- New unit tests enforce audio config integrity.
- Iterative commits refined implementation following bot feedback.

This PR strengthens the audio architecture foundation for consistent UI sound handling across the game.

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

**Bots/AI Contributions to PR #827**

### AI/Bot Contributors

- **@sourcery-ai**: Generated the PR summary, provided a Reviewer's Guide, and left targeted code review comments (e.g., on replacing `UI_NAV_SOUND_PATH` with better discoverability mechanisms in `AudioConstants`). It also offered interaction commands for further reviews.
- **@coderabbitai**: Contributed finishing touches suggestions, unit test generation prompts, and code review assistance (noted in the conversation with thanks for OSS support).
- **@deepsource-io** (DeepSource Code Review / DeepsourceReview): Performed an automated code review on the changes (commit range including `d6b9071...0155c0c`), providing a PR Report Card with grades on Security, Reliability, Complexity, and Hygiene, plus inline issues.

Other common bots like `@dependabot` do not appear to have contributed to this specific PR.

### @ikostan Contributions (Human Maintainer)

@ikostan is the primary author and contributor, driving the core implementation:

- **Key Changes**:

  - Centralized SFX asset directory configuration (`SFX_DIR_PATH`) in `scripts/resources/audio_constants.gd`.
  - Updated `scripts/managers/audio_manager.gd` to resolve SFX paths via `AudioConstants` (removing duplicated local constants).
  - Added comprehensive GUT tests in `test/gut/test_audio_constants_discoverability.gd` for bus constants, asset map integrity, bus config structure, directory validation, and UI SFX referential integrity (plus associated `.uid` file).
  - Multiple iterative commits refining constants, manager logic, tests, and bot-triggering updates.

The PR addresses aspects of related EPIC #490 and issues like #801/#802 through refactoring and testing, though some broader UI input handling and globals decoupling remain pending per the assessment. All work was committed by @ikostan.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
