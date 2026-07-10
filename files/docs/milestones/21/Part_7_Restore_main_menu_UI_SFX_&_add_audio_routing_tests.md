# 🏁 Restore main menu UI SFX and add audio routing tests
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## 📋 Overview

This PR completes the architectural refactoring required for **Issue #799**, moving presentational audio asset paths out of the core lifecycle code. Additionally, it addresses and resolves **Issue #811**—a bug where main menu controls were left completely silent due to a metadata gating conflict. 

All scripts have been fully optimized to satisfy the project's rigid formatting rules, and strict typing parameter checks are now completely green across `gdlint`, CodeRabbit, and Sourcery analysis checks.

---

## 🛠️ Detailed Architectural Changes

### 1. Decoupling & Separation of Concerns (Issue #799)

* **`globals.gd` Cleaned**: Completely removed the presentational path configuration `const UI_NAV_SOUND_PATH` and its corresponding preloaded resource variable `_ui_nav_stream`. The file is now restricted purely to global application lifecycle tracking, core logging, and security operations.
* **`audio_constants.gd` Centralized**: Relocated `const UI_NAV_SOUND_PATH = "res://files/sounds/sfx/ui_navigation.wav"` to the top layer of the centralized configuration autoload to consolidate file system lookups.
* **`audio_manager.gd` Streamlined**: Cleaned out obsolete properties. Audio asset paths are now managed dynamically via the centralized asset map arrays and cached transparently within `_sfx_cache` to block disk I/O stutter.

### 2. Main Menu Interface Audio Restoration (Fixes #811)

* **The Root Cause Discovered**: Main menu buttons utilized a `"no_global_sound": true` metadata shield assigned during `_enter_tree()` to intentionally block double-trigger loops through the automated system in `globals.gd`. However, the localized click execution handlers in `main_menu.gd` completely lacked manual audio invocation paths, leaving the interactions silent.
* **The Fix Applied**: Added explicit localized audio execution tracks to `_on_start_pressed()`, `_on_options_button_pressed()`, `_on_quit_pressed()`, and `_on_quit_dialog_confirmed()` using `AudioManager.play_sfx("ui_accept", AudioConstants.BUS_SFX_MENU)`.
* **Bus Alignment Correction**: Fixed the global button fallback hook inside `globals.gd` to route accepts directly to the interface mixing bus (`AudioConstants.BUS_SFX_MENU`) instead of the core gameplay channel (`BUS_SFX`), preserving correct sound attenuation in standalone or menu-only scenes.

---

## 🧪 Headless Automation & Integration Tests (GUT)

Two new automated verification suites have been implemented to guarantee stability and protect against regression tracks:

* **`test_globals_button_routing.gd`**: Automates generic button interface interaction paths to ensure audio output routes flawlessly to the presentation layer bus.
* **`test_main_menu_audio.gd`**: Recreates the concrete menu scene environment, simulates real UI clicks against shielded controls, and confirms proper asset lookup paths.
* **Scene Isolation & Tree Purging**: Resolved a state leak where scene-changing hooks persistently left background game instances or options overlays running between tests. Implemented tree-state snapshots inside `before_each()` and added an active loop cleanup check in `after_each()` to sweep away leaked or orphaned instances.

---

## 🤖 Static Analysis & Code Quality Optimization

Refactored the codebase to resolve every automated quality-gate issue flagged during peer review tracks:

### CodeRabbit AI & `gdlint` Compliance

* Removed vestigial traces including the unused `_ui_nav_stream` declaration from `audio_manager.gd` and stale test helpers from `globals.gd`.
* Enforced absolute static typing requirements across test lifecycles via type-inference operators (`:=`) and replaced array membership evaluations with idiomatic `child not in array` patterns.

### Sourcery AI Enhancements

* **DRY Test Environmental Bootstrapping**: Extracted identical headless audio server creation loops across test suites and consolidated them into a unified utility function: `GutTestHelper.bootstrap_headless_audio_buses()`. Registered the utility globally using `class_name GutTestHelper`.
* **Null-Pointer Safeguards**: Corrected short-circuit evaluation order inside sequential loops. Placed instance verification checks (`is_instance_valid(node)`) *before* layout inequality checks to guard the engine against crash loops when encountering dead pointer addresses.
* **Encapsulation Protection**: Removed fragile assertions where external tests were reading the private pool array (`_sfx_pool`) inside the manager. Added a public diagnostic lookup method `AudioManager.get_active_sfx_bus_name()` to handle routing state validation cleanly.

---

## Reviewer's Guide

Relocates UI navigation/confirmation audio responsibilities from the global Globals node into the audio/resources layer, routes button confirmation/cancel sounds explicitly through the Menu SFX bus, and adds diagnostic APIs plus integration tests to verify correct routing and behavior in both main menu and global button handlers.

### File-Level Changes

| Change                                                                                                                                               | Details                                                                                                                                                                                                                                                                                                                                                                       | Files                                                                                                                                                                         |
|------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Move UI navigation sound path constant out of global state into audio constants/resources.                                                           | <ul><li>Remove UI navigation sound path and preloaded stream fields from Globals, including the private navigation SFX helper.</li><li>Introduce UI_NAV_SOUND_PATH constant in AudioConstants to centralize UI SFX asset paths.</li></ul>                                                                                                                                     | `scripts/core/globals.gd`<br/>`scripts/resources/audio_constants.gd`                                                                                                          |
| Route UI confirmation/cancel sounds through the dedicated Menu SFX audio bus and add local playback for main menu buttons that bypass global sounds. | <ul><li>Change global button handler to play the ui_accept sound through BUS_SFX_MENU instead of BUS_SFX.</li><li>Update main menu button handlers (start/options/quit) to explicitly play ui_accept on BUS_SFX_MENU due to no_global_sound metadata.</li><li>Ensure quit dialog confirm/cancel handlers route ui_accept/ui_cancel through BUS_SFX_MENU.</li></ul>            | `scripts/core/globals.gd`<br/>`scripts/ui/menus/main_menu.gd`                                                                                                                 |
| Expose audio diagnostic API for tests and add headless audio bus bootstrap helpers.                                                                  | <ul><li>Add get_active_sfx_bus_name() to AudioManager to expose the bus used by the most recently started SFX.</li><li>Add bootstrap_headless_audio_buses() helper and class_name to GutTestHelper for test audio setup and DRYness.</li></ul>                                                                                                                                | `scripts/managers/audio_manager.gd`<br/>`test/gut/gut_test_helper.gd`                                                                                                         |
| Add integration/automation tests verifying main menu audio playback and global button routing behaviors.                                             | <ul><li>Create test_main_menu_audio.gd to validate main menu buttons trigger ui_accept over the menu bus and handle scene cleanup.</li><li>Create test_globals_button_routing.gd to verify global button sounds route to the Menu SFX bus, respect suppression flags, and exclude dialog-internal buttons.</li><li>Add UID metadata files for the new test scripts.</li></ul> | `test/gut/test_main_menu_audio.gd`<br/>`test/gut/test_globals_button_routing.gd`<br/>`test/gut/test_globals_button_routing.gd.uid`<br/>`test/gut/test_main_menu_audio.gd.uid` |
| Tidy logging/encryption comments without behavior changes.                                                                                           | <ul><li>Reflow and clarify comments around log_message guard, encryption key generation, CI-injected salt, and WebAssembly/JavaScriptBridge constraints.</li><li>Remove stale inline note from mock player collision node name in test helper.</li></ul>                                                                                                                      | `scripts/core/globals.gd`<br/>`test/gut/gut_test_helper.gd`                                                                                                                   |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                     | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/799 | Relocate the UI navigation sound path constant (UI_NAV_SOUND_PATH) and any other presentation-focused audio constants from scripts/core/globals.gd into the audio layer (e.g., scripts/resources/audio_constants.gd or audio_manager.gd), so globals.gd no longer contains audio asset paths. | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/799 | Move any associated preloaded UI navigation audio streams and helper functions for navigation SFX out of globals.gd into the audio manager’s lifecycle (or otherwise into the audio layer) so that globals.gd no longer owns navigation sound playback/caching.                               | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/799 | Ensure code style/formatting remains compliant (e.g., passes workspace/run_gdlint.sh) after relocating the UI audio constants and related logic.                                                                                                                                              | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/811 | Ensure main menu buttons (Start, Options, Quit) that are shielded by `no_global_sound` metadata play the `ui_accept` confirmation sound locally, routed through the menu-specific SFX bus (`AudioConstants.BUS_SFX_MENU`).                                                                    | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/811 | Route global button press confirmation sounds through the dedicated menu SFX bus while preserving suppression for flat buttons, `no_global_sound` metadata, and dialog-internal buttons.                                                                                                      | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/811 | Add automated tests that verify main menu button audio playback and global button routing behavior, including robust scene-tree and audio cleanup to avoid test pollution.                                                                                                                    | ✅         |             |

### Possibly linked issues

- **#FEATURE**: PR moves UI_NAV_SOUND_PATH and related navigation audio handling from globals.gd into AudioConstants/AudioManager, matching the feature request.
- **#0**: PR directly fixes silent Main Menu buttons by adding local ui_accept calls and proper menu SFX bus routing with tests.

---

**Bots/AI Contributions to PR #812**

This PR primarily involves refactoring audio-related constants, routing UI navigation and menu sounds to a dedicated presentation bus, adding diagnostic APIs, and expanding GUT tests for audio behavior. Multiple AI-powered tools and bots contributed summaries, reviews, suggestions, and checks.

### AI/Bot Contributors

- **@sourcery-ai**: Provided a detailed PR summary, categorized changes (Bug Fixes, Enhancements, Tests), walkthrough of modifications across files (e.g., globals.gd, audio_constants.gd, audio_manager.gd, main_menu.gd, and test files), estimated review effort, related issues/PRs, suggested labels, and even a thematic poem. It helped structure the overall context and improvements.
- **@coderabbitai**: Delivered feature/bug fix/test summaries, posted actionable review comments (including nitpicks on unused code, preloading optimizations, formatting fixes), inline suggestions, and autofix prompts. It reviewed specific commits and files, leveraging repo-specific learnings for Godot/GDScript best practices.
- **@deepsource-io** (via DeepSource Code Review / DeepsourceReview): Performed automated code review on commits (e.g., 7ade280...3afd0b9), identifying issues with inline comments and a full review summary.

These bots enhanced code quality, provided automated testing/validation insights, enforced formatting/style rules (e.g., gdformat), and generated documentation-oriented summaries without direct code commits from external humans beyond the PR author.

### Human Contributors

- **@ikostan**: Primary author and contributor. Handled all commits, including initial refactor of audio resources, routing menu audio to the dedicated bus, updates to main_menu.gd and globals.gd, dead code removal, style fixes, test helper extraction, and integration of feedback from AI reviews. Self-assigned, labeled, and linked related issues (#811, #799).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
