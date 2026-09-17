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
