<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Level-owned projectile lifecycle

---

## PR Summary

**Title:** Level-owned projectile lifecycle  
**PR:** _fill in after opening_  
**Branch:** `level-owned-projectile-lifecycle` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1140 – [FEATURE] Level-owned projectile lifecycle](https://github.com/ikostan/SkyLockAssault/issues/1140)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `enhancement`, `mechanics`, `refactoring`

### Purpose

The fourth part of #620 (Region 5: Gameplay Entities). `BulletFirer` added every projectile to the scene root, so shots kept flying for up to 5 s after their level was replaced, for example through pause menu → Back To Main Menu into the loading screen and the menu. This covers the projectile half of the #620 finding "Projectiles and shot sounds outlive the level"; #1141 (Part 24) fixed the sound half.

After this PR, the level owns a `Projectiles` container, so leaving a level frees its projectiles at once, and a projectile can't affect anything outside the level it was fired in.

---

## Confirm-first results

- **Blockers closed.** #1138 (PR #1221) and #1139 (PR #1224) are merged; `main` at `e702742`.
- **Issue line number was stale** (not updated in the issue): #1140's `bullet.gd:128` is now `bullet.gd:89` after #1224.
- **Configure order matters.** `Projectile.configure()` sets `global_position` and `global_rotation`. Before `add_child()`, a node has no parent transform, so those become local values and would be offset under a moved container. The root has an identity transform, which is why the old order worked. `configure()` already restarts the lifetime timer when called inside the tree (#1139), so it can run after `add_child()` with no change to `projectile.gd`.
- **Draw order.** The old parent, the root, drew projectiles after every canvas item of the level, including `PlayerStatsPanel`, `Player` and `FpsCounter`. `PauseMenu` and `HUD` are `CanvasLayer`s and `Background` is a `ParallaxBackground`, so tree order doesn't affect them. Making `Projectiles` the level's last child keeps the same order.
- **Pause behavior.** The level root, the new container and the scene root all use the default process mode, so projectiles still freeze on pause as before.
- **Baseline on `main`:** full GUT suite 1,181/1,181 (117 scripts).

---

## Key Changes

### 1. `WeaponFirer.projectile_parent` (`weapon_firer.gd`)

- New `projectile_parent: Node` and `set_projectile_parent(parent: Node)` on the base type, so `Weapon` can pass the container to any slot without probing for a method.

### 2. `Weapon.set_projectile_parent()` (`weapon.gd`)

- Stores the container and passes it to every cached slot.
- `_get_or_create_slot()` passes it to a slot when the slot is first created.
- This matters because `Weapon._ready()` equips slot 0 before `MainScene._ready()` runs, so slot 0 always exists before injection.

### 3. `BulletFirer.spawn_projectile()` (`bullet.gd`)

- Adds the projectile to the injected parent, then calls `configure()`, so the muzzle position and rotation are applied in global coordinates under any parent transform.
- With no injected parent, or one that was freed, it falls back to `get_tree().root`, so isolated firers in tests keep working.

### 4. `Projectiles` container (`main_scene.tscn`, `main_scene.gd`)

- New `Projectiles` `Node2D`, the last child of the level, at the origin with no transform.
- `MainScene._ready()` calls `player.weapon.set_projectile_parent(projectiles)` right after the player is placed.

### 5. Benchmark runner comment (`benchmark_runner.gd`)

- `_wait_for_bullets_to_clear()` still compares the root's child count. Projectiles no longer live on the root, so it now returns at once. Only its comment changed; the scenario constants are unchanged.

### 6. Tests

**No test case was removed.**

- **`test/gut/test_bullet_configuration.gd` (16 → 21 tests):**
  - The root-fallback check in `test_projectile_uses_configured_motion_and_global_muzzle_offset` is unchanged.
  - New `test_firer_without_injected_parent_falls_back_to_root`.
  - New `test_projectile_is_added_to_injected_parent`.
  - New `test_spawn_position_is_global_under_transformed_parent`: a moved and rotated container still gets the muzzle position, the up rotation and the unchanged velocity.
  - New `test_freed_projectile_parent_falls_back_to_root`.
  - New `test_freeing_injected_parent_frees_its_projectiles`.
- **`test/gut/test_weapon_slots.gd` (15 → 19 tests):** the container reaches a slot created before injection, slots created after it, a container injected before `_ready()`, and replacing or clearing it updates every slot.
- **`test/gut/test_main_scene_orphan_nodes.gd` (7 → 10 tests):** existing assertions unchanged. New tests check that shots in the real level are children of `Projectiles`, that freeing the level with two shots in flight frees them and leaves no orphans, and that replacing the level leaves none of the old shots.
- **`test/gdunit4/test_weapon_firing_bullet.gd` (+2 tests):** a shot fired through the real input action is a child of the level's `Projectiles`, and replacing a level with a shot in flight leaves no bullet that belongs to a freed level.
- **`tests/scene_transition_lifecycle_test.py` (+1 test):** new `test_pw_trans_07_leaving_level_mid_fire_is_clean` fires, uses Back To Main Menu while the shot is in flight, waits for the menu, and checks there are no error logs or page errors.

---

## Design Decisions

- **The parent lives on `WeaponFirer`, not only on `BulletFirer`.** `Weapon` only knows `WeaponFirer`, so this keeps the #1138 rule of no `has_method()` probing.
- **A freed parent counts as no parent.** In the game, firers are freed with their level, so this can't happen. Falling back keeps a shot from crashing if it ever does.
- **The container has no script.** It only groups nodes; `MainScene` holds the reference.
- **The benchmark wait stays.** It's a guard against nodes left on the root. Removing it would change the benchmark's code path.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdlint ./scripts`, `gdformat --check ./scripts` and the docs validator as in CI.

| State                    | GUT scripts | GUT tests | GUT asserts | gdUnit4 tests |
|--------------------------|-------------|-----------|-------------|---------------|
| `main` (`e702742`, base) | 117         | 1,181     | 13,685      | 167           |
| This PR                  | 117         | 1,193     | 13,732      | 169           |

The gdUnit4 count on `main` is from Part 24; the branch diff only adds test functions.

- **Full GUT suite:** 1,193/1,193. **Full gdUnit4 suite:** 169/169, 0 orphans.
- **Restoring the bugs:** each change below was put back on its own; these tests fail:

| Change restored                     | Fails                                                                                                                                                                        |
|-------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Configure before `add_child()`      | GUT: `test_spawn_position_is_global_under_transformed_parent`                                                                                                                |
| Projectiles added to the root again | GUT: `test_projectiles_spawn_under_the_level_container`, `test_freeing_level_with_in_flight_projectiles_leaves_no_orphans`, `test_replacing_level_leaves_no_old_projectiles` |

- **Benchmark (desktop, local, 1 run, scenario unchanged):** valid; no "bullets still alive" warning; 0 orphans during gameplay and the reload loop; 501–502 nodes. The CI PR table is the reference.
- **GDScript lint, format and docs:** `gdlint ./scripts`, `gdformat --check ./scripts` and `validate_gdscript_docs.py` on the changed scripts pass. The added Python test is `black`-formatted.
- **Not run locally:** Playwright (`weapon_firing_test.py`, the scene transition suites and the new PW-TRANS-07), the web benchmark and the manual itch.io checks. PR run: _fill in after CI._

---

## Known Limitations / Follow-ups

- **Manual itch.io checks still to do:**
  - Leaving the level mid-fire leaves no projectiles visible on the loading screen or menu.
  - Projectile draw order is unchanged.
- **Still open from Part 24:** `test/gut/test_weapon_slot_cooldown.gd` runs in no CI job.
- **Next in #620:** #1102 (Bindings API), then #1151 (Main scene and tuning cleanup).

---

## Reviewer's Guide

### File-Level Changes

| Change              | Details                                                                                                                                                 | Files                                                                                                                                                                                                                     |
|---------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Firer parent.       | <ul><li>`projectile_parent` and `set_projectile_parent()` on the base type.</li><li>Spawn adds to the parent, then configures; root fallback.</li></ul> | `scripts/entities/weapon_firer.gd`<br/>`scripts/entities/bullet.gd`                                                                                                                                                       |
| Weapon propagation. | <ul><li>`set_projectile_parent()` passes the container to existing and future slots.</li></ul>                                                          | `scripts/entities/weapon.gd`                                                                                                                                                                                              |
| Level container.    | <ul><li>`Projectiles` node, last child of the level; injected in `_ready()`.</li></ul>                                                                  | `scenes/main_scene.tscn`<br/>`scripts/core/main_scene.gd`                                                                                                                                                                 |
| Benchmark.          | <ul><li>Comment on `_wait_for_bullets_to_clear()`.</li></ul>                                                                                            | `test/benchmark/benchmark_runner.gd`                                                                                                                                                                                      |
| Tests.              | <ul><li>Firer parent and transform cases; `Weapon` propagation; in-flight and replacement cases; real-level gdUnit4 cases; PW-TRANS-07.</li></ul>       | `test/gut/test_bullet_configuration.gd`<br/>`test/gut/test_weapon_slots.gd`<br/>`test/gut/test_main_scene_orphan_nodes.gd`<br/>`test/gdunit4/test_weapon_firing_bullet.gd`<br/>`tests/scene_transition_lifecycle_test.py` |
| Milestone note.     | <ul><li>This note.</li></ul>                                                                                                                            | `files/docs/milestones/27/Part_25_Level-owned_projectile_lifecycle.md`                                                                                                                                                    |

### Assessment against linked issues

| Issue                                                   | Objective                                                              | Addressed | Explanation                                                                                   |
|---------------------------------------------------------|------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1140> | Projectiles in a real level are freed with that level                  | ✅ / ⏳     | GUT orphan and replacement cases, gdUnit4 real-level cases; the itch.io check is still to do. |
| <https://github.com/ikostan/SkyLockAssault/issues/1140> | Isolated firers still work through the root fallback                   | ✅         | Root-fallback and freed-parent cases in `test_bullet_configuration.gd`.                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1140> | All GUT, gdUnit4, Playwright and lint jobs pass, no test cases removed | ✅ / ⏳     | GUT, gdUnit4 and lint pass locally with no cases removed; Playwright runs in CI.              |
| <https://github.com/ikostan/SkyLockAssault/issues/1140> | Milestone note added                                                   | ✅         | This note.                                                                                    |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1140 from the #620 (Region 5) review.
- Chose #1140 as the next PR.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Compared the open #620 sub-issues (#1102, #1140, #1151), checked their blockers, and recommended #1140.
    - Found the stale line number in #1140 and the configure-before-`add_child()` order problem under a moved parent.
    - Checked draw order and pause behavior for the new container, and ran the baseline GUT suite on `main` (1,181/1,181).
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, `gdlint`, `gdformat` and the docs validator, and one desktop benchmark run.
    - Put the old spawn order and the root parent back to confirm the new tests catch them.
