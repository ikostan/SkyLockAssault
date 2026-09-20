<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# UI hud migration

---

## PR #966 Summary: UI HUD migration

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `ui-hud-migration` → `main`  
**Linked Issues:** #962 (Phase 2 PR 1/4: Player & Weapon Data Layer), #963 (Phase 2 PR 2/4: HUD DI Bridge); related #280  
**Milestone:** Milestone 24 – Resource-Driven Data Refactoring & Player Stat Architecture  
**Labels:** enhancement, refactoring

### Purpose

Migrate HUD and player telemetry to resource-driven state: the player owns runtime **FuelResource** / **SpeedResource**, the weapon publishes **WeaponResource**, and the HUD receives all three via dependency injection—while keeping legacy settings/signal consumers working during the transition.

### Core Improvements

#### 1. Player data layer (`scripts/entities/player.gd`)

- Local `FuelResource` and `SpeedResource` as runtime sources of truth
- Speed clamping, movement, fuel consumption, and depletion routed through resources
- Compatibility bridges: mirror resource events to legacy player signals / settings readers
- Initialize fuel capacity, consumption rate, and speed tuning from settings on spawn
- Restore boundary calculations where needed for gameplay correctness

#### 2. Weapon telemetry (`scripts/entities/weapon.gd`)

- `WeaponResource` tracks available weapon names and current index
- Sync resource state on weapon switch; emit swap notifications for HUD/observers

#### 3. HUD dependency injection (`scripts/ui/hud.gd` + `scripts/core/main_scene.gd`)

- `main_scene` extracts player fuel/speed/weapon resources and passes them into `HUD.setup_hud(...)`
- HUD stores injected resources; connects `speed_updated`, `fuel_changed`, weapon/ammo signals via compatibility bridges
- Idempotent reconnect + `_exit_tree` cleanup to avoid leaks on hot-swap / teardown
- Bars and warnings driven from authoritative resource values (not direct player-node wiring)

#### 4. Tests & stability

- GUT HUD tests inject mock resources; emit telemetry from `SpeedResource` (etc.) instead of player signals
- Synchronize resource bounds with test settings; weapon resource fallbacks
- Clean up stale persisted test artifacts before settings runs
- Project config updates for plugin/test tooling as needed

### Benefits

- HUD no longer depends on the Player node for fuel/speed/weapon display
- Clear ownership: resources own state; player/weapon update them; HUD observes
- Safer signal lifecycle (guarded connect/disconnect)
- Path toward dropping runtime mutations of `Globals.settings` for active telemetry (compatibility bridge retained where still required)

### Status Notes

Implements the Phase 2 HUD DI bridge (#963) and much of the player/weapon resource integration (#962). Sourcery noted remaining tension with #962’s “no runtime `Globals.settings` fuel writes” criterion where an explicit compatibility sync still updates `_settings.current_fuel` for legacy consumers during migration.

---



---

## PR #966 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (including feedback on SpeedResource tuning initialization from settings, and assessment of #962/#963 acceptance criteria).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the HUD DI migration and resource bridges. Co-authored commits updating `project.godot` and `scripts/ui/hud.gd`.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **60.22%**, **+0.20%** vs base; patch coverage **~81.2%** with 13 lines missing in `hud.gd`; all tests successful).

- **@copilot** (GitHub Copilot)  
  Co-authored the commit that synced the HUD fuel bar and updated tests to use resources.

> **Note:** **@dependabot** did not author commits or leave reviews on this PR (no dependency-bump activity observed).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Migrated player fuel/speed ownership to local `FuelResource` / `SpeedResource` instances; synchronized weapon selection via `WeaponResource`; injected the three resources into `HUD.setup_hud()` from `main_scene`; added guarded signal bridges and teardown for hot-swap/lifecycle safety; retained legacy settings compatibility where needed; cleaned stale test artifacts; and updated GUT/HUD tests for resource-driven telemetry under Milestone 24 Phase 2 (#962, #963).

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
