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

This PR modernizes the Godot test CI around the updated runtime and GDUnit4/GUT versions, adds LCOV aggregation and Codecov reporting, centralizes coverage/export settings, and broadens isolated automated validation across settings resources, gameplay settings UI, difficulty scaling, player systems, weapons, bullets, and HUD behavior.

### File-Level Changes

| Change                                                                                                                         | Details                                                                                                                                                                                                                                                                                                                                                                                                       | Files                                                                                                                                                                                                     |
|--------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Upgraded CI workflows to run standardized Godot/GDUnit4 and GUT test environments with more efficient execution and reporting. | <ul><li>Increase GDUnit4 coverage batches from two to three suites and merge LCOV tracefiles before Codecov upload.</li><li>Quiet dependency installation, extraction, and routine version-check output while retaining failure validation.</li><li>Refine GUT installation, test reporting, artifact naming, and retention settings.</li></ul>                                                               | `.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`                                                                                                                               |
| Centralized export and coverage configuration for CI and local test execution.                                                 | <ul><li>Declare Web as a runnable export platform through a shared runnable-presets section.</li><li>Limit coverage collection to game scripts and exclude tests and addons.</li><li>Add the required GDUnit4 coverage runner configuration.</li></ul>                                                                                                                                                        | `export_presets.cfg`<br/>`override.cfg`<br/>`project.godot`                                                                                                                                               |
| Expanded and hardened gameplay settings and difficulty test coverage.                                                          | <ul><li>Add resource-level tests for defaults, boundaries, clamping, change signals, and redundant assignments.</li><li>Add gameplay settings UI initialization, signal wiring, duplicate-connection, and non-Web behavior tests.</li><li>Isolate global settings state and validate difficulty-scaled fuel depletion and weapon cooldowns with lightweight player fixtures.</li></ul>                        | `test/gdunit4/test_gdunit_game_settings_resource.gd`<br/>`test/gdunit4/test_gdunit_game_settings_resource.gd.uid`<br/>`test/gdunit4/test_difficulty.gd`<br/>`test/gdunit4/test_difficulty_integration.gd` |
| Refactored player, HUD, bullet, and shared-helper tests for stronger isolation, typing, and Godot 4.7 compatibility.           | <ul><li>Use typed scene/script references, explicit frame settling, automatic cleanup, and resource-backed gameplay values.</li><li>Expand assertions for fuel depletion, movement, speed and fuel colors, warning blinking, rotor safety, and HUD synchronization.</li><li>Update bullet collision setup to emit the expected Area2D signal and make helper calculations use GameSettingsResource.</li></ul> | `test/gdunit4/test_bullet.gd`<br/>`test/gdunit4/test_helpers.gd`<br/>`test/gdunit4/test_player.gd`                                                                                                        |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                 | Addressed | Explanation |
|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/887 | Integrate gdUnit4-coverage v0.1.4 into the GDUnit4 CI workflow, execute tests in isolated micro-batches below the coverage tool's file limit, and collect LCOV tracefiles for each batch.                                 | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/887 | Merge the batched LCOV tracefiles into a sanitized unified coverage report and upload it to Codecov with the GDUnit4 flag, while retaining coverage and test reports as CI artifacts.                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/887 | Restrict coverage to production scripts, exclude tests/addons and other non-production content, and remove Codecov uploading from the GUT workflow to avoid duplicate metrics.                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/889 | Standardize the development environment by upgrading and aligning Godot 4.7.1-stable, GUT v9.7.1, and gdUnit4 v6.2.0 with the project and CI workflows.                                                                   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/889 | Implement gdUnit4 coverage support with micro-batched test execution, LCOV tracefile merging and path sanitization, and Codecov upload under the GDUnit4 flag.                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/889 | Harden CI and maintain regression coverage by isolating GUT and gdUnit4 reporting, reliably restoring the workspace, and expanding or updating automated tests so the existing suites run under the upgraded environment. | ✅        |             |

### Possibly linked issues

- **#889**: The PR implements the epic’s CI, GDUnit4 coverage, Codecov, test framework, and expanded testing upgrades.

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
