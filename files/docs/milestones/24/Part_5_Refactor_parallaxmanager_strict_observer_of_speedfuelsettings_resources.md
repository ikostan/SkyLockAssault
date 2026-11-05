<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Refactor parallax manager strict observer of speed, fuel and settings resources- #976

---

## PR #976 Summary: Refactor ParallaxManager — strict observer of Speed/Fuel/Settings resources

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `efactor-parallaxmanager-strict-observer-of-speedfuelsettings-resources` → `main`  
**Linked Issue:** #973 ([REFACTOR] ParallaxManager → strict Observer of Speed/Fuel/Settings resources)  
**Milestone:** Milestone 24 – Resource-Driven Data Refactoring & Player Stat Architecture  
**Labels:** enhancement, refactoring

### Purpose

Make `ParallaxManager` a pure observer of injected **SpeedResource**, **FuelResource**, and **GameSettingsResource**—no direct dependence on Player, `Globals.settings`, or legacy player signals—while hardening editor runtime behavior, isolating tests, and refreshing project docs.

### Core Improvements

#### 1. ParallaxManager resource API (`scripts/managers/parallax_manager.gd`)

- New `setup(speed, fuel, settings)` dependency-injection entry point
- Lifecycle-safe disconnect/reconnect on reinjection or teardown
- Initial sync of speed, fuel-depletion, and difficulty/settings state
- Cached signal-driven state for processing; preserve cache when dependencies are null
- Fuel depletion and recovery driven by **FuelResource** signals (`fuel_changed` / `fuel_depleted`), not settings fields
- Handlers: `_on_speed_updated`, `_on_fuel_changed`, `_on_setting_changed`

#### 2. Scene wiring (`scripts/core/main_scene.gd`)

- Inject the player’s speed/fuel resources and game settings into `background.setup(...)`
- Aligns parallax with the same resource-driven architecture as the HUD migration

#### 3. Editor & globals safeguards

- `@tool` / tool-compatible markings where needed; skip settings load and quit handling in the editor
- Move fallback scene loading out of resource init into runtime global setup
- Update shipped `config_resources/default_settings.tres` (e.g. log level, show_fps)
- Isolate global settings mutations between tests

#### 4. Tests

- GUT: resource injection, idempotent setup, replacement isolation, null deps, flameout, fuel recovery, continued observation of unchanged resources
- Scene-level parallax/performance wiring checks
- Default settings validation; globals resource isolation
- Browser telemetry hold test: lower timing floor **950 ms → 900 ms** for CI/WASM jitter

#### 5. Documentation

- README overhaul: TOC, play instructions, architecture, structure, testing, licensing, feedback
- Clarify closed external code contributions; refresh contributor presentation and Godot 4.X guidance

### Benefits

- Background scrolling tracks authoritative speed/fuel/difficulty without singleton coupling
- Safe hot-swap of resources without stale signal listeners
- Editor runs no longer mutate runtime settings or treat editor shutdown as game quit
- Stronger, isolated regression coverage for Milestone 24 observer patterns

### Status Notes

Fully addresses #973: strict resource observation, lifecycle-safe signals, scene injection, and automated coverage for sync, replacement, null handling, and flameout/recovery.

---

## Reviewer's Guide

The PR replaces ParallaxManager's player/global coupling with lifecycle-safe observation of injected speed, fuel, and settings resources, wires the new API into the main scene, and adds broad regression coverage for synchronization, replacement, null dependencies, flameout, and recovery. It also separates editor behavior from runtime initialization, relaxes a CI-sensitive browser timing threshold, and substantially refreshes project documentation.

### File-Level Changes

| Change                                                                                            | Details                                                                                                                                                                                                                                                                                                                                                                            | Files                                                                                                                                                                                                          |
|---------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Refactor ParallaxManager into a dependency-injected observer of authoritative gameplay resources. | <ul><li>Add setup-based injection for speed, fuel, and settings resources.</li><li>Synchronize initial state and cache signal-driven speed, difficulty, and fuel status.</li><li>Disconnect old observers safely during reinjection, null setup, and resource replacement.</li><li>Drive flameout and recovery from FuelResource rather than settings or player signals.</li></ul> | `scripts/managers/parallax_manager.gd`                                                                                                                                                                         |
| Update scene integration to use the new resource-observer API.                                    | <ul><li>Inject the player speed and fuel resources plus active settings into the parallax manager.</li><li>Remove legacy player speed signal wiring and obsolete priming/update paths.</li><li>Add scene-level assertions for resource identity and speed synchronization.</li></ul>                                                                                               | `scripts/core/main_scene.gd`<br/>`test/gut/test_main_scene_parallax_and_performance.gd`                                                                                                                        |
| Harden editor/runtime separation and default resource initialization.                             | <ul><li>Mark editor-executed globals and settings resources as tool-compatible.</li><li>Skip editor settings loading and game quit handling.</li><li>Move fallback scene loading from resource initialization into runtime global setup.</li><li>Update and validate shipped default settings.</li></ul>                                                                           | `scripts/core/globals.gd`<br/>`scripts/resources/game_settings_resource.gd`<br/>`config_resources/default_settings.tres`<br/>`test/gut/test_game_settings_resource.gd`<br/>`test/gut/test_globals_resource.gd` |
| Expand automated coverage for observer lifecycle and gameplay state transitions.                  | <ul><li>Add tests for initial synchronization, null dependencies, idempotent setup, replacement isolation, and continued observation.</li><li>Cover fuel depletion, immediate offset reset, recovery, and speed/settings updates.</li><li>Isolate settings resources between tests to prevent global-state leakage.</li></ul>                                                      | `test/gut/test_parallax_manager.gd`<br/>`test/gut/test_main_scene_parallax_and_performance.gd`<br/>`test/gut/test_game_settings_resource.gd`<br/>`test/gut/test_globals_resource.gd`                           |
| Adjust browser timing tolerance for CI/WASM variability.                                          | <ul><li>Lower the UX hold test's minimum accepted in-engine delay from 950 ms to 900 ms while preserving the 1400 ms upper bound.</li></ul>                                                                                                                                                                                                                                        | `tests/telemetry_and_hold_test.py`                                                                                                                                                                             |
| Reorganize project documentation around current gameplay and development workflows.               | <ul><li>Condense the README and add structured project, play, architecture, testing, licensing, security, and feedback sections.</li><li>Document the resource-based architecture and closed external-contribution policy.</li><li>Add milestone documentation for the refactor and its implementation rationale.</li></ul>                                                        | `README.md`<br/>`files/docs/milestones/24/Part_5_Refactor_parallaxmanager_strict_observer_of_speedfuelsettings_resources.md`                                                                                   |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                 | Addressed | Explanation |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/973 | Refactor ParallaxManager into a strict observer of injected SpeedResource, FuelResource, and GameSettingsResource, removing direct dependencies on Player, Globals.settings, and legacy player-driven signals.                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/973 | Implement a lifecycle-safe observer API that disconnects replaced resources, connects the current resources, synchronizes initial state, handles fuel depletion and recovery, and uses only cached signal-driven state during processing. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/973 | Update scene wiring and automated coverage/documentation to support and validate the resource-injection architecture, including replacement isolation, idempotent setup, null dependencies, and flameout recovery.                        | ✅        |             |

### Possibly linked issues

- **#973**: PR directly implements issue #973 through resource injection, observer lifecycle management, fuel recovery, and comprehensive tests.
- **#973**: The PR implements the issue by adding resource injection, lifecycle-safe observation, and removing legacy Player-to-ParallaxManager wiring.

---

## PR #976 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review of the ParallaxManager resource-observer refactor (positive overall assessment).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the parallax DI migration and README/editor changes. Authored expanded parallax injection/lifecycle tests; co-authored `default_settings.tres` updates.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@deepsource-autofix**  
  Authored automated style/format commits (`style: format code with Black and isort`).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **63.82%**, **+3.40%** vs base; patch coverage **~77.8%** with 6 lines missing in `parallax_manager.gd`; all tests successful).

> **Note:** **@dependabot** did not author commits or leave reviews on this PR (no dependency-bump activity observed).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Refactored `ParallaxManager` into a strict observer of injected `SpeedResource`, `FuelResource`, and `GameSettingsResource` (lifecycle-safe connect/disconnect, initial sync, fuel depletion/recovery); wired injection from `main_scene`; hardened editor `@tool` / quit/settings side effects in Globals and settings resources; isolated test globals; relaxed browser UX timing lower bound for CI/WASM jitter; and substantially refreshed the README under Milestone 24 (#973).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
