<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Signal decoupling for new resources

---

## PR #956 Summary: Signal decoupling for new resources

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `signal-decoupling-for-new-resources` → `main`  
**Linked Issue:** #952 ([FEATURE] Phase 1: Resource Foundations & GUT Tests); related #472  
**Milestone:** Milestone 24 – Resource-Driven Data Refactoring & Player Stat Architecture  
**Labels:** enhancement, testing, refactoring, GUT, QA

### Purpose

Introduce standalone player resource models for **fuel**, **speed**, and **weapons**—decoupled from broader game settings—with validated state transitions, boundary invariants, and deterministic observer signals, backed by focused GUT coverage.

### Core Improvements

#### 1. `FuelResource` (`scripts/resources/fuel_resource.gd`)

- Max/current fuel with clamping and threshold ordering
- `refuel()` helper with bounded capacity
- Signals: **`fuel_changed`** (effective changes only), **`fuel_depleted`** (positive → zero crossing only)
- GUT: initialization, consumption/refuel, clamping, invariants, no redundant emissions

#### 2. `SpeedResource` (`scripts/resources/speed_resource.gd`)

- Min/max/current speed with non-inverting limits and auto-clamp on boundary shifts
- Acceleration, deceleration, lateral speed, normalized warning threshold
- Signals: **`speed_updated`**, **`speed_low`**, **`speed_maxed`** (directional threshold crossings; suppressed on no-op assigns)
- GUT: boundary enforcement, limit shifts, update suppression, low/max crossings

#### 3. `WeaponResource` (`scripts/resources/weapon_resource.gd`)

- `available_weapons`, `current_index`, max/current ammo, fire rate, damage
- Signals: **`ammo_updated`**, **`weapon_swapped`** (effective changes only)
- Defensive array handling: duplicate on assign, protect list from external mutation, clamp index on inventory shrink
- GUT: ammo/inventory bounds, signal counts, protected-list behavior

#### 4. Design notes

- Exported properties as source of truth (redundant backing fields removed where possible)
- Setters enforce invariants without noisy emissions on unchanged values
- Resource UIDs registered for Godot tooling

### Benefits

- Clear domain boundaries for player stats (fuel / speed / weapons)
- UI and gameplay can observe resources without coupling to `GameSettingsResource`
- Safer weapon inventory (no silent out-of-bounds from external array mutation)
- Headless-friendly GUT suites for CI under Milestone 24 Phase 1

### Status Notes

Delivers Phase 1 resource foundations from #952: three independent resources, signal semantics, and dedicated GUT coverage (plus a small main-menu audio assertion timing fix for CI stability).

---

## Reviewer's Guide

This PR establishes decoupled FuelResource, SpeedResource, and WeaponResource models whose setters enforce bounds and emit deterministic observer signals only for effective state changes or defined threshold crossings. It adds dedicated GUT coverage for invariants, signal semantics, and defensive weapon-array ownership, stabilizes headless UI/audio tests, centralizes Playwright browser installation in the Docker image, and documents the Phase 1 milestone.

### File-Level Changes

| Change                                                                                                              | Details                                                                                                                                                                                                                                                                                                                                                                                                                    | Files                                                                                                                                                                                                                                                                                          |
|---------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Introduces standalone, validated fuel and speed resources with deterministic change and threshold-crossing signals. | <ul><li>Added bounded fuel state, refueling, threshold ordering, and depletion notifications.</li><li>Added non-inverting speed limits, automatic current-speed clamping, tuning properties, and low/max crossing notifications.</li><li>Added initialization and boundary/signal tests for both resources.</li></ul>                                                                                                      | `scripts/resources/fuel_resource.gd`<br/>`scripts/resources/fuel_resource.gd.uid`<br/>`scripts/resources/speed_resource.gd`<br/>`scripts/resources/speed_resource.gd.uid`<br/>`test/gut/test_fuel_resource.gd`<br/>`test/gut/test_speed_resource.gd`<br/>`test/gut/test_speed_resource.gd.uid` |
| Adds defensive weapon inventory and ammunition state management with observer notifications.                        | <ul><li>Added clamped ammo limits and effective-change-only ammo signals.</li><li>Added weapon selection clamping and swap notifications when the active index or name changes.</li><li>Copied weapon arrays on assignment and retrieval to prevent external mutation, including safe handling of empty inventories.</li><li>Added focused tests for ammo, inventory bounds, signal counts, and array ownership.</li></ul> | `scripts/resources/weapon_resource.gd`<br/>`scripts/resources/weapon_resource.gd.uid`<br/>`test/gut/test_weapon_resource.gd`<br/>`test/gut/test_weapon_resource.gd.uid`                                                                                                                        |
| Improves headless test reliability by asserting UI effects before deferred transitions execute.                     | <ul><li>Reworked FPS toggle interaction to use direct state and pressed-signal simulation instead of mouse input.</li><li>Moved main-menu audio assertions ahead of deferred scene transitions and expanded quit-button audio checks.</li></ul>                                                                                                                                                                            | `test/gdunit4/test_fps_settings_integration.gd`<br/>`test/gut/test_main_menu_audio.gd`                                                                                                                                                                                                         |
| Updates the development container to share a single Playwright browser installation across users.                   | <ul><li>Configured a shared browser path, installed Chromium during image build, and made the installation readable by the non-root user.</li><li>Removed the redundant post-user browser installation and healthcheck.</li></ul>                                                                                                                                                                                          | `Dockerfile`                                                                                                                                                                                                                                                                                   |
| Documents the Phase 1 resource-decoupling milestone and its implementation scope.                                   | <ul><li>Recorded resource responsibilities, signal semantics, invariants, testing scope, and contributor/review metadata.</li></ul>                                                                                                                                                                                                                                                                                        | `files/docs/milestones/24/Part_2_Signal_decoupling_for_new_resources.md`                                                                                                                                                                                                                       |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                   | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/952 | Create standalone FuelResource, SpeedResource, and WeaponResource classes that separate mutable runtime state from configuration, enforce the specified bounds and invariants, and emit deterministic signals only for effective mutations and defined threshold crossings. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/952 | Add dedicated GUT test suites covering initialization, normal and boundary behavior, clamping, unchanged assignments, signal payloads, and fuel/speed threshold-crossing semantics for all three resources.                                                                 | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/952 | Stabilize headless CI by updating affected integration/UI tests and Docker Playwright setup without modifying gameplay scenes, HUD/UI scripts, or Player physics.                                                                                                           | ✅        |             |

### Possibly linked issues

- **#952**: The PR directly delivers the issue’s requested resources, invariants, signal semantics, tests, and Docker/headless test stabilization.

---

## PR #956 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (including feedback on `WeaponResource` array ownership / external mutation risk and early assessment that weapon coverage was incomplete before it landed).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the fuel/speed/weapon resource decoupling and GUT coverage.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **60.02%** vs base; all modified coverable lines covered; all tests successful).

- **@copilot** (GitHub Copilot)  
  Co-authored the commit that refactored GUT tests to assert signal emit counts.

> **Note:** **@dependabot** did not author commits or leave reviews on this PR (no dependency-bump activity observed).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Introduced standalone `FuelResource`, `SpeedResource`, and `WeaponResource` with clamped bounds, threshold invariants, and deterministic signals (`fuel_changed` / `fuel_depleted`, `speed_updated` / `speed_low` / `speed_maxed`, `ammo_updated` / `weapon_swapped`); protected weapon inventory from external mutation; clamped index on inventory shrink; expanded GUT suites for clamping, signal-crossing semantics, and defensive array handling; and fixed main-menu audio assertion timing—under Milestone 24 Phase 1 (#952).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
