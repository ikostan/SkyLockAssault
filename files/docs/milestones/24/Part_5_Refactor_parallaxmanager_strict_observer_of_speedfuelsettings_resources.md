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
