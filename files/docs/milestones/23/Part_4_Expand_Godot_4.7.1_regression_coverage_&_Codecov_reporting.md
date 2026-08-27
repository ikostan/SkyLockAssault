# Expand Godot 4.7.1 regression coverage and Codecov reporting
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

## PR #906 Summary: Dev environment, testing frameworks & CI/CD pipeline upgrade

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `dev-environment-testing-frameworks-cicd-pipeline-upgrade` → `main`  
**Linked Issues:** #887 (gdUnit4-coverage + batched LCOV & Codecov), #889 (Dev Environment / Testing / CI epic)  
**Milestone:** Milestone 23 – Settings Architecture & FPS Counter Implementation  
**Labels:** testing, EPIC, QA, gdunit4

### Purpose

Modernize and harden the Godot test infrastructure under 4.7.1: expand GDUnit4 regression coverage (settings, gameplay, menus, player/HUD/weapons), standardize micro-batched coverage with production-only LCOV, and stabilize GUT/GDUnit4 CI reporting so Codecov reflects real game-script coverage without duplicate metrics.

### Core Improvements

#### 1. Expanded GDUnit4 Regression Coverage

- **GameSettingsResource** – defaults, clamping, boundaries, change signals, redundant assignments  
- **Gameplay settings UI** – init/sync, signal wiring, idempotent connections, non-Web safety  
- **Difficulty / fuel** – isolation via Globals/`GameSettingsResource`, scaled depletion, weapon cooldown  
- **Player & HUD** – movement, fuel/speed colors, warning blink, rotor safety, HUD sync  
- **Bullets** – reliable collision simulation (`Area2D` + idle-frame settle) for headless CI  
- **Menu navigation SFX** – all menu scenes, including paused menus  

#### 2. Coverage Pipeline (GDUnit4)

- Domain-scoped **micro-batches** (below gdUnit4-coverage file limits)  
- Per-batch LCOV → merge + path sanitization → `final_coverage.lcov`  
- Coverage limited to **production scripts**; tests/addons excluded  
- LCOV path inspection/debug steps for reliable Codecov attribution  
- Codecov upload under **GDUnit4** flag; GUT Codecov uploads removed (no double-counting)

#### 3. GUT & Workflow Hygiene

- Quieter dependency/engine install steps (failures still fail the job)  
- Improved test-report artifact naming and retention  
- Workflow comments referencing #887 and coverage design

#### 4. Project / Export Config

- `export_presets.cfg`: shared `[runnable_presets]`; Web marked runnable  
- `override.cfg` + `project.godot`: shared GDUnit4 coverage defaults  
- Tests updated for typed settings APIs and lighter scene fixtures under Godot 4.7.1

### Benefits

- Broader automated protection for settings architecture and core gameplay systems  
- More stable headless CI (isolation, idle-frame waits, deterministic difficulty fixtures)  
- Cleaner Codecov signal focused on production GDScript (**~53.6%** project coverage on this PR, **+7.1%** vs base)  
- Aligns with the #887 / #889 goals for batched coverage + toolchain standardization

### Status Notes

Implements the gdUnit4-coverage + Codecov reporting work from #887 and the broader test/CI hardening objectives of epic #889 under Milestone 23.

---

## Reviewer's Guide

This PR upgrades the Godot 4.7.1 test infrastructure by expanding isolated GDUnit4 regression coverage across settings, menus, gameplay, and HUD behavior, while restructuring CI into domain-based LCOV micro-batches that produce sanitized production-only Codecov metrics; it also aligns GUT reporting, Web export runnability, and project coverage defaults.

### File-Level Changes

| Change                                                                                                          | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Files                                                                                                                                                                                                                                                     |
|-----------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Standardize GDUnit4 coverage execution and production-only Codecov reporting.                                   | <ul><li>Partition tests into domain-specific isolated micro-batches and capture per-batch LCOV files.</li><li>Merge tracefiles, normalize paths, exclude tests/addons, inspect results, and upload under the GDUnit4 Codecov flag.</li><li>Add shared GDUnit4 coverage defaults and remove duplicate coverage concerns from the GUT workflow.</li></ul>                                                                                                               | `.github/workflows/gdunit4_tests.yml`<br/>`override.cfg`<br/>`project.godot`                                                                                                                                                                              |
| Align CI workflows and Web export configuration with the Godot 4.7.1 test environment.                          | <ul><li>Quiet Godot and GUT dependency installation without changing failure behavior.</li><li>Rename and retain GUT test-report artifacts for seven days.</li><li>Declare the Web export as a runnable preset through shared runnable-preset configuration.</li></ul>                                                                                                                                                                                                | `.github/workflows/gut_tests.yml`<br/>`export_presets.cfg`                                                                                                                                                                                                |
| Expand regression coverage for settings resources, gameplay settings initialization, and menu navigation audio. | <ul><li>Test settings defaults, clamping, boundaries, change signals, redundant assignments, UI synchronization, signal wiring, and non-Web initialization.</li><li>Exercise navigation SFX across all menu scenes and while the pause menu is active and the scene tree is paused.</li></ul>                                                                                                                                                                         | `test/gdunit4/test_gdunit_game_settings_resource.gd`<br/>`test/gdunit4/test_gdunit_game_settings_resource.gd.uid`<br/>`test/gdunit4/test_gdunit_all_menus_navigation_regression.gd`<br/>`test/gdunit4/test_gdunit_all_menus_navigation_regression.gd.uid` |
| Harden gameplay regression fixtures and broaden player, HUD, difficulty, fuel, weapon, and bullet validation.   | <ul><li>Replace heavyweight scene fixtures with typed, resource-backed player fixtures where possible and restore global settings between tests.</li><li>Add or refine assertions for difficulty-scaled fuel depletion, weapon cooldowns, movement, HUD color and warning states, fuel shutdown, rotor safety, and shared calculations.</li><li>Use Area2D collision fixtures, idle-frame settling, and automatic cleanup for more reliable headless tests.</li></ul> | `test/gdunit4/test_bullet.gd`<br/>`test/gdunit4/test_difficulty.gd`<br/>`test/gdunit4/test_difficulty_integration.gd`<br/>`test/gdunit4/test_helpers.gd`<br/>`test/gdunit4/test_player.gd`                                                                |
| Document the Godot 4.7.1 coverage and CI modernization work.                                                    | <ul><li>Record the linked issues, implementation areas, coverage strategy, and expected benefits for the milestone.</li></ul>                                                                                                                                                                                                                                                                                                                                         | `files/docs/milestones/23/Part_4_Expand_Godot_4.7.1_regression_coverage_&_Codecov_reporting.md`                                                                                                                                                           |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                 | Addressed | Explanation |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/887 | Integrate gdUnit4-coverage v0.1.4 into the GDUnit4 CI workflow and execute isolated micro-batched test sessions that remain below the tool's file limit while collecting per-batch LCOV tracefiles.                                       | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/887 | Merge the batched LCOV tracefiles into a sanitized unified report, upload it to Codecov under the GDUnit4 flag, and retain coverage and test reports as CI artifacts.                                                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/887 | Restrict coverage to production scripts while excluding tests and addons, and remove Codecov uploading from the GUT workflow to avoid duplicate coverage metrics.                                                                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/889 | Standardize the development and CI test environment on Godot 4.7.1-stable, GUT v9.7.1, and gdUnit4 v6.2.0.                                                                                                                                | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/889 | Implement reliable gdUnit4 coverage execution using isolated micro-batches, merged and sanitized LCOV tracefiles, production-only filtering, and Codecov upload under the GDUnit4 flag while preventing duplicate GUT coverage reporting. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/889 | Expand and stabilize automated regression coverage for settings, gameplay systems, player/HUD/weapons, bullets, and menu navigation, while hardening CI test isolation, reporting, and workspace restoration.                             | ✅        |             |

### Possibly linked issues

- **#889**: Directly addresses the epic by expanding regression coverage and implementing standardized micro-batched LCOV and Codecov reporting.

---

## PR #906 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review on the GDUnit4/GUT CI modernization, coverage batching, and expanded gameplay/menu regression tests.

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Co-authored a commit updating the menu navigation regression tests (`test_gdunit_all_menus_navigation_regression.gd`).

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published review findings on the PR changes.

- **@copilot** (GitHub Copilot)  
  Co-authored the commit that added HUD speed-bar color transition tests (`test_speed_colors` in `test_player.gd`).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **53.59%**, **+7.14%** vs base; all modified coverable lines covered; all tests successful). Target of the production-only LCOV uploads configured in this PR (GDUnit4 flag; GUT Codecov uploads removed to avoid duplicate metrics).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Expanded and hardened GDUnit4 coverage for GameSettingsResource, gameplay settings UI, difficulty/fuel scaling, player movement, HUD, bullets, and menu navigation SFX (including paused menus); stabilized tests for Godot 4.7.1; standardized GDUnit4 micro-batch coverage, LCOV merge/path sanitization, and production-only Codecov reporting; quieted/refined GUT CI; updated export presets and coverage overrides; and iteratively refined CI and test isolation across many commits.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
