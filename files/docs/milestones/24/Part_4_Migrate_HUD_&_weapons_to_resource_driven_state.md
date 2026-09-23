<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Migrate HUD and weapons to resource-driven state

---

## PR #971 Summary: Migrate HUD and weapons to resource-driven state- #971

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `ui-hud-migration-sub-task` → `main`  
**Linked Issues:** #280 (weapon system signals / HUD), #953 (Phase 2 UI & HUD migration); related #472  
**Milestone:** Milestone 24 – Resource-Driven Data Refactoring & Player Stat Architecture  
**Labels:** enhancement, testing, dependencies, github actions, dependabot, github_actions, refactoring, GUT, QA, gdunit4

### Purpose

Finish migrating HUD telemetry and weapon/ammo presentation to authoritative injected resources, enforce ammunition on fire, expand isolated tests, and update project licensing/contribution policy (PolyForm Noncommercial; closed to external code/docs contributions).

### Core Improvements

#### 1. Resource-driven HUD (`scripts/ui/hud.gd`, `scenes/main_scene.tscn`)
- Drop direct `Globals.settings` / cached `_current_speed` paths for display
- Read fuel, speed, thresholds, and fractions from injected **FuelResource** / **SpeedResource**
- Idempotent disconnect/reconnect on resource hot-swap (`speed_updated`, `speed_low`, `speed_maxed`, fuel, ammo)
- Deterministic initial sync of fuel, speed, weapon, and ammo after setup/reassignment
- Speed/fuel warning visuals driven from resource values; fix low-speed threshold edge cases
- New **Weapon** and **Ammo** rows in the stats panel

#### 2. Weapon & ammo (`scripts/entities/weapon.gd`, `bullet.gd`)

- `fire()` returns success; ammo required when finite
- Decrement ammo **only after a successful shot**; warn when depleted
- Optional `weapon_name` with safe fallback (e.g. Machine Gun)
- HUD listens to `ammo_updated` / swap state for label + ammo bar

#### 3. Tests

- GUT HUD suite: programmatic fixture with standalone resources (no player-scene coupling)
- Coverage for invalid injection, replacement isolation, idempotent wiring, resource-driven updates
- GdUnit4: speed/fuel checks via `speed_resource`; StatManager lifecycle; independent blinking thresholds
- Flameout test adjusts min speed before zeroing to match real physics reaction

#### 4. Licensing, docs & CI

- Replace GPL with **PolyForm Noncommercial License 1.0.0**
- CONTRIBUTING / README: closed to external code & documentation contributions; issues welcome for bugs/feedback
- Godot version refs generalized to **4.X**
- Pin **codecov/codecov-action** **7.0.0 → 7.1.1** (via Dependabot #970)

### Benefits

- HUD is a pure observer of fuel/speed/weapon resources
- Ammo is gameplay-enforced, not display-only
- Safer hot-swap and teardown of resource signal wiring
- Clearer legal/contribution posture for a source-available noncommercial project
- Stronger isolated regression net for Milestone 24 Phase 2 UI

### Status Notes

Advances #280 / #953 resource-driven HUD and weapon telemetry. Sourcery noted isolated weapon-swap/ammo UI assertions may still be thinner than fuel/speed coverage; Codecov reported project **~63.8%** (**+3.5%**) with patch below the 80% target on some HUD/weapon lines.

---



---

## PR #971 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@dependabot**  
  Authored the dependency bump of **codecov/codecov-action** from **7.0.0 → 7.1.1** (merged via #970 into this branch).

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review of the resource-driven HUD migration, weapon/ammo wiring, and licensing/docs changes.

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the HUD/weapon resource migration. Co-authored README updates.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **63.79%**, **+3.45%** vs base; patch coverage **~76.1%** with missing lines mainly in `hud.gd` / `weapon.gd` / `bullet.gd`; all tests successful; patch target 80% not met).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Drove HUD fully from injected `FuelResource` / `SpeedResource` / `WeaponResource` (removed `Globals.settings` speed path); fixed idempotent hot-swap signal reconnects and initial sync; added weapon name + ammo HUD UI; enforced ammo checks and successful-shot consumption in `weapon.fire()`; expanded isolated GUT/GdUnit4 HUD tests (injection, replacement, StatManager lifecycle, flameout alignment); switched the project to **PolyForm Noncommercial License 1.0.0** and closed external contributions in CONTRIBUTING/README—under Milestone 24 (#280 / #953).

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
