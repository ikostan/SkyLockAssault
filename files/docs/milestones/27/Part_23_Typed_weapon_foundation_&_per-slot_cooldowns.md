<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Typed weapon foundation & per-slot cooldowns

---

## PR Summary

**Title:** Typed weapon foundation and per-slot cooldowns  
**PR:** _fill in after opening_  
**Branch:** `typed-weapon-foundation-and-per-slot-cooldowns` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1138 – [FEATURE] Typed weapon foundation and per-slot cooldowns](https://github.com/ikostan/SkyLockAssault/issues/1138)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `enhancement`, `mechanics`, `refactoring`, `architecture`

### Purpose

The first part of #620 (Region 5: Gameplay Entities). It covers three #620 findings:

- **Untyped coupling:** `player.gd`, `weapon.gd` and `bullet.gd` had no `class_name`. The player called the weapon through `has_method()`, and the weapon probed the active firer with `has_method("fire")` and `get("weapon_name")`.
- **Weapon index duplicated:** the active slot was stored in both `Weapon.current_index` and `weapon_resource.current_index`.
- **Switching weapons resets the fire cooldown:** `switch_to()` freed the active firer, so its `can_fire` state and `CooldownTimer` were lost and the replacement could fire at once. Fire, swap and fire again skipped the fire rate. It couldn't happen yet because `Player.tscn` has one weapon, but it would as soon as a second one was added.

The types added here are the base for #1139 (projectile scene), #1141 (shot SFX) and #1137 (hold-to-fire).

---

## Confirm-first results

- **Blocker closed.** #1146 (BulletResource as the single source for weapon tuning) was closed on 2026-11-16, and `switch_to()` no longer syncs stats.
- **Issue line numbers were stale.** They were updated in #1138 before starting: `player.gd:222-229` → `221-227`, `weapon.gd:104` → `87`. The rest of the description matched `main` (`c670d78`).
- **`bullet.gd` had no `weapon_name`.** The name always came from `switch_to()`'s `"Machine Gun"` fallback. `WeaponFirer.weapon_name` defaults to `"Machine Gun"`, so the HUD shows the same text.
- **The shared GUT mock player had a plain `Node2D` weapon.** `GutTestHelper.build_mock_player_scene()` gave the player a mock script that `extends Node2D`. With `Player.weapon` typed as `Weapon`, that mock would fail the typed assignment in 6 suites, so it now `extends Weapon` (Key Changes 5).
- **`test_main_scene_orphan_nodes.gd` is a GUT suite.** The issue lists it under gdUnit4; it lives in `test/gut/` and was extended there.

---

## Key Changes

### 1. New base type `WeaponFirer` (`weapon_firer.gd`)

- `class_name WeaponFirer extends Node2D`: the contract for anything `Weapon` can equip.
- `@export var weapon_name: String = "Machine Gun"`.
- `fire() -> bool` returns `true` only when a shot was fired. The base version calls `push_error("WeaponFirer.fire() must be overridden.")` and returns `false`.

### 2. `Weapon` owns the slots (`weapon.gd`)

- `class_name Weapon`. `current_weapon` is typed `WeaponFirer`.
- **One index:** `Weapon.current_index` is removed. `weapon_resource.current_index` is the only copy.
- **Per-slot firers:** a private `_slots: Array[WeaponFirer]` holds one firer per `weapon_types` entry, created the first time the slot is selected and kept as a child of `Weapon`. A swap hides the outgoing firer and shows the incoming one. The hidden firer's `CooldownTimer` keeps running. Firers are freed with `Weapon`.
- **`switch_to(index)`** validates `index` first. The log message no longer reads `weapon_types[index]` before that check. Then:
  - Out of range or negative: `push_warning("Weapon: Invalid index …")`, as before.
  - Empty slot (`null` scene): `push_error("… is empty!")`. On `main` this crashed on `null.instantiate()`.
  - Scene that doesn't instantiate as a `WeaponFirer`: `push_error("… not a WeaponFirer! Keeping the current weapon.")`, and the instance is freed at once.
  - In all three cases the current weapon, the index and `weapon_swapped` stay unchanged.
  - Otherwise the name and index updates are the same as before, so `weapon_swapped` fires in the same cases.
- **New `switch_to_next()`:** `(weapon_resource.current_index + 1) % count`. It does nothing with one weapon or none.
- **`fire()`:** no `has_method()` probe. With no equipped firer it reports `Weapon.fire(): no weapon equipped!` (on `main`: `current_weapon null or no 'fire()' method!`; the second case can't happen anymore). Ammo is checked and deducted as before.

### 3. `BulletFirer` (`bullet.gd`)

`class_name BulletFirer extends WeaponFirer`, matching the scene's `BulletFirer` root. The cooldown (`can_fire`, `timer`, `CooldownTimer`) stays here, so the suites that read it are unchanged. Nothing else in the file changed. The texture-filter write and the hit handler are #1139's.

### 4. `Player` and `MainScene` typing (`player.gd`, `main_scene.gd`)

- `class_name Player`. `Player.weapon` is typed `Weapon`.
- `_input()`: `weapon.fire()` and `weapon.switch_to_next()`. The `has_method()` probes and the next-slot calculation are gone.
- `MainScene.player` is typed `Player`.

### 5. Tests

**No test case was removed.**

- **`test/gut/test_weapon_firing_state.gd` (17 → 18 tests):**
  - Every mock extends `WeaponFirer`. `TunedWeapon` sets its name in `_init()`, because a subclass can't redeclare an inherited exported property. A new `BareWeapon` implements nothing beyond the base type.
  - `test_switch_without_optional_stats_still_equips` uses `BareWeapon` and asserts that `Weapon` has no `current_index` of its own.
  - `test_active_node_without_fire_method_does_not_emit` is rewritten for the invalid-scene behavior: a plain `Node2D` scene is rejected, the previous firer stays active, and firing still goes to it.
  - New `test_active_firer_without_fire_override_does_not_emit`: covers the base `fire()` error, the case the old `has_method()` probe used to catch.
  - The rate-only and damage-only cases use `BareWeapon` for their unused slot 0.
  - `test_missing_active_weapon_does_not_emit` expects the new error text.
- **New `test/gut/test_weapon_slots.gd` (15 tests):** mock firers copy `BulletFirer`'s `can_fire`/`CooldownTimer` pattern without spawning projectiles.
  - Cooldowns: swapping away and back can't fire until the cooldown ends; an unused slot fires straight after a swap; a cooldown that ends while its slot is hidden stays ended.
  - Slots: the same instance is reused per slot; unselected slots aren't created; only the active firer is visible and receives `fire()`; freeing `Weapon` frees every cached slot.
  - Index: `weapon_resource.current_index` and `weapon_swapped` update on every swap; `switch_to_next()` wraps around and does nothing with one weapon or none.
  - Failures: out-of-range and negative indexes, a non-`WeaponFirer` scene, an empty slot, and `switch_to_next()` onto an invalid slot all leave the active weapon, the index and the signal unchanged.
- **New `test/gdunit4/test_weapon_slot_cooldown.gd` (3 tests):** two real `bullet.tscn` slots in `weapon.tscn`, at difficulty 1.0. Fire, swap away and back, and fire again in the same frame spawns one projectile and uses one round. The slot fires again after its 0.15 s cooldown, an unused slot fires straight away, and a hidden slot's `CooldownTimer` keeps running. If a swap frees the firer, the suite fails with a message instead of a script error.
- **`test/gut/test_main_scene_orphan_nodes.gd` (+1 test):** adds a second `bullet.tscn` slot to the real level, caches both slots, frees the level, and checks that the orphan count returns to its baseline. The existing assertions are unchanged.
- **`test/gut/gut_test_helper.gd`:** the mock player's weapon script now `extends Weapon`, with an inert `_ready()`, `fire()`, `switch_to()` and `switch_to_next()`. It no longer declares `weapon_types` or `current_index`, since `Weapon` provides `weapon_types` and the index belongs to `weapon_resource`.

---

## Design Decisions

- **Keep and hide instead of storing cooldown state on `Weapon`.** This follows the issue: the cooldown stays on `BulletFirer`, the existing suites that read `can_fire`, `timer` and `CooldownTimer` keep working, and the exploit is closed in both directions.
- **Hidden firers aren't paused.** `BulletFirer` has no `_process()` or input handling, so hiding is enough, and its timer must keep running while hidden.
- **Lazy slot creation.** A slot's firer is created the first time it's selected, as the issue asks. The shipped player has one slot, so it still creates exactly one firer, as on `main`.
- **A rejected scene is freed at once and changes nothing.** The current weapon stays visible and equipped, the index and `weapon_swapped` don't change, and no extra node is left behind.
- **`switch_to_next()` doesn't skip an invalid slot.** It tries the next slot and keeps the current weapon if that slot fails. The shipped player has one valid slot, so skipping logic would be untested complexity for now.
- **Out-of-range indexes stay a warning.** The issue asks for a clean failure, not a different log level, so `push_warning()` is unchanged.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdformat --check`, `gdlint` and the docs contract validator as in CI.

| State                    | GUT scripts | GUT tests | GUT asserts | gdUnit4 suites | gdUnit4 tests |
|--------------------------|-------------|-----------|-------------|----------------|---------------|
| `main` (`c670d78`, base) | 115         | 1,136     | 13,466      | 27             | 164           |
| This PR                  | 116         | 1,153     | 13,575      | 28             | 167           |

- **No test cases removed.** Every GUT test on `main` is present and passing on the branch (compared by suite and test name from the JUnit reports).
- **Full GUT suite:** 1,153/1,153. **Full gdUnit4 suite:** 167/167, 0 orphans.
- **Restoring the bug:** with `main`'s free-on-swap behavior put back in `switch_to()`, these fail:

| Suite                          | Fails                                                                                                                                                                                                                                 |
|--------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `test_weapon_slots.gd`         | `test_swap_away_and_back_cannot_fire_until_cooldown_ends`, `test_cooldown_that_ends_while_slot_is_inactive_stays_ended`, `test_swapping_reuses_the_same_instance_per_slot`, `test_only_the_active_firer_is_visible_and_receives_fire` |
| `test_weapon_slot_cooldown.gd` | `test_two_bullet_slots_cannot_bypass_cooldown` (4 failed asserts; the runner stops at the first failing case, as in CI)                                                                                                               |

- **GDScript lint, format and docs:** `gdlint ./scripts`, `gdformat --check ./scripts` and `validate_gdscript_docs.py` on the changed scripts pass.
- **Not run locally:** Playwright (`weapon_firing_test.py`, `difficulty_flow_test.py`, `difficulty_integration_test.py`, `no_error_logs_test.py`), the benchmark and the manual itch.io check. PR run: _fill in after CI._

---

## Known Limitations / Follow-ups

- **`Player.tscn` still has one weapon.** Adding a second one was out of scope, so the per-slot cooldown is covered by unit and scene tests, not by gameplay.
- **`switch_to_next()` doesn't skip invalid slots** (Design Decisions).
- **Next in #620:** #1139 (projectile scene and hit detection) and #1141 (shot sounds through the SFX pool) are unblocked by `BulletFirer`. #1140 needs #1139 too.
- **Manual itch.io check** still to do: firing, the fire rate and the HUD weapon name look as they do on `main`.

---

## Reviewer's Guide

### File-Level Changes

| Change            | Details                                                                                                                                                                                               | Files                                                                                                                                                                                                                                                                                                   |
|-------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Base weapon type. | <ul><li>`WeaponFirer` with `weapon_name` and `fire() -> bool`.</li></ul>                                                                                                                              | `scripts/entities/weapon_firer.gd`<br/>`scripts/entities/weapon_firer.gd.uid`                                                                                                                                                                                                                           |
| Weapon slots.     | <ul><li>`class_name Weapon`; cached firer per slot, hidden when inactive.</li><li>One index; `switch_to_next()`; index validated first.</li><li>Empty and non-`WeaponFirer` slots rejected.</li></ul> | `scripts/entities/weapon.gd`                                                                                                                                                                                                                                                                            |
| Typed entities.   | <ul><li>`BulletFirer extends WeaponFirer`, `Player`, typed `Player.weapon` and `MainScene.player`.</li><li>No `has_method()`/`get()` probing.</li></ul>                                               | `scripts/entities/bullet.gd`<br/>`scripts/entities/player.gd`<br/>`scripts/core/main_scene.gd`                                                                                                                                                                                                          |
| Tests.            | <ul><li>Firing-state mocks extend `WeaponFirer`; plain-`Node2D` cases rewritten.</li><li>New slot and scene suites; orphan case added.</li><li>Mock player weapon extends `Weapon`.</li></ul>         | `test/gut/test_weapon_firing_state.gd`<br/>`test/gut/test_weapon_slots.gd`<br/>`test/gut/test_weapon_slots.gd.uid`<br/>`test/gdunit4/test_weapon_slot_cooldown.gd`<br/>`test/gdunit4/test_weapon_slot_cooldown.gd.uid`<br/>`test/gut/test_main_scene_orphan_nodes.gd`<br/>`test/gut/gut_test_helper.gd` |
| Milestone note.   | <ul><li>This note.</li></ul>                                                                                                                                                                          | `files/docs/milestones/27/Part_23_Typed_weapon_foundation_&_per-slot_cooldowns.md`                                                                                                                                                                                                                      |

### Assessment against linked issues

| Issue                                                   | Objective                                                                         | Addressed | Explanation                                                                                                  |
|---------------------------------------------------------|-----------------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1138> | `player.gd` and `weapon.gd` no longer use `has_method()` or `get()` probing       | ✅         | Typed `Weapon` and `WeaponFirer` calls only.                                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1138> | `Weapon.current_index` is gone; `weapon_resource.current_index` is the only index | ✅         | Pinned by `test_switch_without_optional_stats_still_equips` and `test_resource_index_updates_on_every_swap`. |
| <https://github.com/ikostan/SkyLockAssault/issues/1138> | Swapping weapons can't bypass any slot's cooldown                                 | ✅         | GUT cooldown tests and the gdUnit4 scene test; all fail with `main`'s free-on-swap behavior.                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1138> | Invalid slots and indexes fail cleanly                                            | ✅         | Out-of-range, negative, empty and non-`WeaponFirer` slot tests.                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1138> | Single-weapon gameplay behaves as it does today                                   | ✅ / ⏳     | Existing weapon, difficulty and player suites pass unchanged; Playwright and the itch.io check still to run. |
| <https://github.com/ikostan/SkyLockAssault/issues/1138> | All GUT, gdUnit4, Playwright and lint jobs pass, with no test cases removed       | ✅ / ⏳     | GUT, gdUnit4 and lint pass locally with no cases removed; Playwright runs in CI.                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1138> | Milestone note added                                                              | ✅         | This note.                                                                                                   |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1138 from the #620 (Region 5) review, as its first part, blocked by #1146.
- Chose #1138 for this PR and kept #1102 for a separate one.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked Region 5's sub-issues and blockers, and updated the stale line numbers in #1138 (and #1102) before starting.
    - Ran the baseline GUT (1,136/1,136) and gdUnit4 (164/164) suites on `main`.
    - Found that the shared GUT mock player's weapon had to become a real `Weapon` for the typed reference.
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, compared test names against `main`, and ran `gdformat`, `gdlint` and the docs validator.
    - Put `main`'s free-on-swap behavior back to confirm the cooldown tests catch the bug.
