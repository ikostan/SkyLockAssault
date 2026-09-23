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

## Reviewer's Guide

The PR migrates HUD telemetry and weapon presentation from global or cached state to injected authoritative resources, adds finite-ammunition enforcement and HUD displays, improves signal-safe hot-swapping and warning behavior, expands isolated regression tests, and updates licensing, contribution policy, documentation, and CI dependencies.

### File-Level Changes

| Change                                                                                           | Details                                                                                                                                                                                                                                                                                                                                                                                                | Files                                                                                                                                                                                                                                     |
|--------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Make HUD telemetry authoritative and resource-injected, with safe signal lifecycle management.   | <ul><li>Replace global settings and cached speed reads with FuelResource and SpeedResource values.</li><li>Add deterministic initial synchronization for fuel, speed, weapon, and ammo.</li><li>Disconnect old resource signals and idempotently connect new ones during hot-swaps.</li><li>React to speed threshold changes and exact warning boundaries, including fuel-depletion updates.</li></ul> | `scripts/ui/hud.gd`<br/>`scripts/resources/speed_resource.gd`<br/>`scenes/main_scene.tscn`                                                                                                                                                |
| Add weapon and ammunition state to gameplay and HUD presentation.                                | <ul><li>Add weapon and ammo rows to the stats panel.</li><li>Update weapon names with a fallback and synchronize ammo display from WeaponResource signals.</li><li>Require positive ammo before firing and decrement ammo only after a successful projectile launch.</li><li>Return firing success from the bullet implementation.</li></ul>                                                           | `scripts/entities/weapon.gd`<br/>`scripts/entities/bullet.gd`<br/>`scenes/main_scene.tscn`<br/>`scripts/ui/hud.gd`                                                                                                                        |
| Expand regression coverage around resource-driven HUD behavior and lifecycle isolation.          | <ul><li>Build an isolated programmatic HUD fixture with standalone resources.</li><li>Test invalid injection, hot-swapping, idempotent signal connections, resource mutations, warning boundaries, flameout behavior, weapon labels, and ammo updates.</li><li>Update player tests to mutate SpeedResource rather than HUD-local cached state.</li></ul>                                               | `test/gut/test_hud.gd`<br/>`test/gdunit4/test_player.gd`                                                                                                                                                                                  |
| Align project automation, licensing, and contribution documentation with the new project policy. | <ul><li>Replace GPL metadata and license text with PolyForm Noncommercial License 1.0.0.</li><li>Document closed external code/documentation contributions and retain issue-based feedback channels.</li><li>Generalize Godot version references to 4.X.</li><li>Update the pinned Codecov action revision.</li></ul>                                                                                  | `LICENSE`<br/>`CONTRIBUTING.md`<br/>`README.md`<br/>`.github/workflows/browser_test.yml`<br/>`scripts/ui/hud.gd`<br/>`scripts/entities/bullet.gd`<br/>`files/docs/milestones/24/Part_4_Migrate_HUD_&_weapons_to_resource_driven_state.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                        | Addressed | Explanation |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/280 | Define weapon state signals on WeaponResource, including weapon_swapped(index, weapon_name) and ammo_updated(current, max_ammo), and emit them when weapon selection or ammunition changes.                                                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/280 | Move weapon state handling into the resource-driven weapon layer, updating weapon selection and consuming ammunition only after a successful shot.                                                                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/280 | Inject WeaponResource into the HUD, connect the weapon signals for weapon-name and ammunition display updates, and add isolated tests covering the signal-driven behavior.                                                                       | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/953 | Integrate FuelResource and SpeedResource into Player and WeaponResource into Weapon as the authoritative gameplay data layer, and inject those exact resources into the HUD from the main scene without passing Player nodes.                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/953 | Refactor the unified HUD into a resource-only observer that connects to fuel, speed, threshold, weapon-swap, and ammo signals; supports idempotent resource replacement and teardown; and synchronizes its UI from current resource values.      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/953 | Decouple HUD tests from Player scenes by using standalone resources and cover resource hot-swapping, signal lifecycle, UI thresholds, warnings, weapon presentation, and ammunition updates.                                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/964 | Convert hud.gd into a pure observer of injected fuel, speed, and weapon resources, removing dependencies on Player nodes, player physics signals, and Globals.settings for telemetry.                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/964 | Implement deterministic, idempotent HUD setup and resource hot-swapping: disconnect previous resources, assign new resources, connect signals without duplication, and synchronize the UI from current resource values.                          | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/964 | Ensure complete resource-driven HUD behavior and lifecycle safety, including fuel/speed warnings and colors, weapon/ammo displays, and disconnecting all resource signals when the HUD exits the scene tree without managing resource lifetimes. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/965 | Refactor `test_hud.gd` to run HUD tests in isolation from player nodes, mock player hierarchies, and physical game scenes by constructing the HUD UI and injecting standalone FuelResource, SpeedResource, and WeaponResource instances.         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/965 | Verify that mutating the public resource properties drives the complete resource setter, signal, and HUD update pipeline for fuel, speed, warning states, weapon display, and ammunition.                                                        | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/965 | Prove robust resource replacement and idempotent signal wiring, including bi-directional hot-swapping for all three resources and stable connection counts after repeated injection.                                                             | ✅        |             |

### Possibly linked issues

- **#953**: The PR directly implements the issue’s Player/Weapon integration, resource injection bridge, HUD observer migration, hot-swapping, and isolated tests.
- **#280**: PR directly implements isolated HUD resource tests, bi-directional replacement checks, and signal idempotency validation.

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
