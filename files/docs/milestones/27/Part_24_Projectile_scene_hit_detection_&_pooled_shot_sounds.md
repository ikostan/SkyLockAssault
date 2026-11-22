<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Projectile scene, hit detection & pooled shot sounds

---

## PR Summary

**Title:** Projectile scene, hit detection and pooled shot sounds  
**PR:** _fill in after opening_  
**Branch:** `projectile-scene-and-pooled-shot-sfx` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1139 – [FEATURE] Projectile scene and hit detection](https://github.com/ikostan/SkyLockAssault/issues/1139)
- [#1141 – [FEATURE] Play shot sounds through the SFX pool](https://github.com/ikostan/SkyLockAssault/issues/1141)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `enhancement`, `mechanics`, `performance`, `refactoring`, `audio`, `SFX`

### Purpose

The second and third parts of #620 (Region 5: Gameplay Entities), shipped as one PR because both rewrite `BulletFirer` (`bullet.gd`) and the same test suite (`test_bullet_configuration.gd`). Together they fix the whole "Per-shot allocation" finding: #1139 the projectile, #1141 the sound.

**#1139** covers four #620 findings:

- **Hits only detect `Area2D` targets:** only `area_entered` was connected, so a physics-body enemy could never be hit.
- **Per-shot allocation (projectile):** each shot built its body, area, sprite, shape, new `CircleShape2D` and timer in code.
- **Collision layers and masks are unset:** everything used layer 1 and mask 1.
- **An entity changes a viewport-wide setting:** the firer set the default texture filter.

**#1141** covers two #620 findings:

- **Shot SFX is positioned at the origin:** each shot created an `AudioStreamPlayer2D` without setting its position.
- **Shot sounds outlive the level (sound half):** each player was an extra node on the scene root.

---

## Confirm-first results

- **Blockers closed.** #1138 (adds `BulletFirer`) is merged (PR #1221, `main` at `4c21c6d`). #1141 had no other blocker.
- **Issue line numbers were stale** (not updated in the issues):
  - #1139: `bullet.gd:106-113` → `111-118` (hit lambda), `bullet.gd:26-28` → `30-33` (texture-filter write).
  - #1141: `bullet.gd:75-81` → `76-91` (`play_sfx_with_volume()`), `bullet.gd:81` → `86` (root `add_child`).
- **The texture filter is already nearest project-wide.** `project.godot` sets `default_texture_filter=0`, and projectiles are added to the root, so removing the write changes nothing on screen.
- **`Player.tscn` needed no change.** Its `CharacterBody2D` uses the defaults, layer 1 and mask 1, which is the new `player` layer. A test now pins that.
- **The shot sound doesn't loop.** `retro-laser-1-236669.mp3.import` has `loop=false`, so a pooled player always frees up.
- **Pre-existing, not changed here:** `test/gut/test_weapon_slot_cooldown.gd` (added by #1138) `extends GdUnitTestSuite` but lives in `test/gut/`. GUT skips it ("does not extend GutTest"), and the gdUnit4 job only runs `test/gdunit4/`, so its 3 tests run in neither job. Copied into `test/gdunit4/` locally, all 3 pass on this branch. See Known Limitations.

---

## Key Changes

### 1. New `projectile.tscn` and `Projectile` (`projectile.gd`) (#1139)

```text
Projectile (RigidBody2D, gravity_scale = 0, group "bullets", layer 0, mask 0)
├── Sprite2D
├── HitArea (Area2D, layer 3 player_projectiles, mask 2 enemies)
│   └── CollisionShape2D (shared CircleShape2D, radius 3.0)
└── LifetimeTimer (Timer, one_shot, 5.0 s)
```

- `class_name Projectile extends RigidBody2D`.
- `configure(config: BulletResource, spawn_position: Vector2)` applies the texture, sprite scale, upward velocity, position, rotation (`UP_ROTATION`), lifetime and damage. It only reads the config.
- **Shared shape:** every default-radius projectile uses the scene's `CircleShape2D`. A config with another `collision_radius` gets a duplicate, so the shared shape is never changed.
- **Lifetime:** the timer starts in `_ready()`. `configure()` also restarts it when the projectile is already in the tree, so #1140 can add the projectile to its level container first and configure it afterwards.
- **One hit handler:** `HitArea.area_entered` and `HitArea.body_entered` both go to `_on_hit(target: Node2D)`, connected in the scene. A `_has_hit` flag makes later calls do nothing, so a projectile never damages two targets, or one target twice when both signals fire. `has_method("take_damage")` stays until the enemy work defines a damage contract. The `Projectile hit:` debug log is kept.
- `LifetimeTimer.timeout` → `queue_free`, connected in the scene.

### 2. Named physics layers (`project.godot`) (#1139)

| Layer | Name                 |
|-------|----------------------|
| 1     | `player`             |
| 2     | `enemies`            |
| 3     | `player_projectiles` |

### 3. `BulletFirer` (`bullet.gd`) (#1139, #1141)

- `spawn_projectile()` instantiates `PROJECTILE_SCENE`, calls `configure()` with the muzzle position, and still adds the projectile to the scene root (the level-owned container is #1140).
- The viewport texture-filter write in `_ready()` is gone.
- `play_sfx_with_volume()` is renamed `play_shot_sound()`. It calls `SfxManager.play_stream(config.shot_sound, AudioConstants.BUS_SFX_WEAPON)`. A null `shot_sound` still fires silently.
- The `Firing with scaled cooldown:` log that the Playwright suites read is unchanged.
- `DEFAULT_BULLET_CONFIG`, `PROJECTILE_SCENE` and `config` now have `##` docs, and the commented-out `projectile_texture`/`shot_sound` leftovers are removed.

### 4. `SfxManager.play_stream()` (`sfx_manager.gd`) (#1141)

- New `play_stream(stream: AudioStream, bus_name: String, pitch_scale: float = 1.0, volume_db: float = 0.0)`. It skips the name lookup and the LRU cache.
- `play_sfx()` and `play_stream()` share two private helpers:
  - `_ensure_sfx_pool()`: the lazy pool rebuild that used to be inline in `play_sfx()`.
  - `_play_on_pool()`: picks an idle player (or takes over the first valid one), sets the stream, pitch and volume, routes the bus with the same SFX_Menu fallback, and plays.
- A null stream logs a WARNING (`play_stream() called with a null stream.`) and plays nothing. `BulletFirer` checks for null first, so silent firing logs nothing.
- `play_sfx()` behaves as before; its existing tests pass unchanged.

### 5. Tests

**No test case was removed.**

- **`test/gut/test_bullet_configuration.gd` (14 → 15 tests):**
  - Motion, muzzle offset, radius, lifetime, damage, missing-texture and zero-speed cases are unchanged and pass against the scene. The motion case also checks that the projectile is a `Projectile` from `projectile.tscn`.
  - `test_configured_sound_uses_weapon_bus_and_cleans_up_on_finish` keeps its name and is rewritten for the pool: one pooled `AudioStreamPlayer` plays the stream on `SFX_Weapon`, no player is added to the root, the pool doesn't grow, and the player is reused, not freed.
  - `test_default_config_firer_uses_assets_from_default_bullet_tres` checks the shot sound in the pool instead of a root player.
  - `test_null_sound_allows_silent_firing` also checks that nothing plays and no warning or error is logged.
  - `test_fresh_resource_fires_without_inheriting_default_assets` also checks that the pool stays silent.
  - New `test_firer_does_not_change_viewport_texture_filter`.
- **New `test/gut/test_projectile.gd` (17 tests, 18 runs):**
  - Hits: a physics-body target and an `Area2D` target with `take_damage()` take damage, and the projectile is freed; a target without `take_damage()` (body and area) frees the projectile without an error; both signals for one target apply damage once; two targets in one tick damage only the first; a zero-damage hit still counts as the hit.
  - Shape: default-radius projectiles share one shape; a custom radius gets its own and leaves the shared one unchanged.
  - Layers: `HitArea` is on layer 3 with mask 2; the root body has no layers; the layer names are in Project Settings; `Player.tscn`'s body keeps layer 1 and mask 1.
  - Lifecycle: `configure()` applies motion, visuals and lifetime; configuring after entering the tree restarts the lifetime; an unconfigured projectile still frees itself; `configure()` never writes to the config.
- **`test/gut/test_audio_sfx_centralization.gd` (+4 tests):** `play_stream()` plays on the requested bus through the pool without touching the name cache; reuses pool players; falls back to SFX_Menu for an unknown bus, as `play_sfx()` does; and fails cleanly on a null stream.
- **`test/gut/test_sfx_manager.gd` (+2 tests):** `play_stream()` rebuilds an empty pool, and takes over the first player of a saturated pool without allocating.
- **`test/gdunit4/test_bullet.gd` (+2 tests):** real overlaps, not emitted signals. A stationary projectile overlapping a `StaticBody2D` on the `enemies` layer damages it once and is freed. One overlapping a body on the `player` layer doesn't hit it and keeps flying.
- **`test/gdunit4/test_weapon_firing_bullet.gd` (+1 test):** firing in the real level adds no audio player to the root, keeps the pool size, and plays the shot sound on `SFX_Weapon`. It checks the pooled player's assigned stream, which stays set after the short sound ends, so it doesn't race playback.

---

## Design Decisions

- **One PR for #1139 and #1141.** Both rewrite `bullet.gd` and `test_bullet_configuration.gd`, and neither depends on the other's logic. #1140 stays separate: it depends on #1139 and pulls in `main_scene.tscn`, `Weapon`, the benchmark runner and the orphan-node suite.
- **The root body has no collision layers.** It has no shape, so it never collided; layer 0 and mask 0 make that explicit. The issue only specified `HitArea`'s layers.
- **Signals are connected in the scene,** so they are live as soon as the scene is instantiated, before it enters the tree.
- **`configure()` works before or after `add_child()`.** This PR configures first (the root has an identity transform). #1140's level container may need the opposite order.
- **No pooling of projectiles.** As the issue says, pooling waits for a benchmark that shows it's needed.
- **`play_sfx_with_volume()` renamed to `play_shot_sound()`.** It no longer creates a player or touches volume, and only the bullet tests called it.
- **A null stream in `play_stream()` is a warning, not an error.** It's a caller bug, but it shouldn't stop the game. `BulletFirer` never sends one.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdformat --check`, `gdlint` and the docs contract validator as in CI.

| State                    | GUT scripts | GUT tests | GUT asserts | gdUnit4 suites | gdUnit4 tests |
|--------------------------|-------------|-----------|-------------|----------------|---------------|
| `main` (`4c21c6d`, base) | 116         | 1,153     | 13,575      | 27             | 164           |
| This PR                  | 117         | 1,177     | 13,663      | 27             | 167           |

- **No test cases removed.** Every GUT and gdUnit4 test on `main` is present and passing on the branch (compared by suite and test name from the JUnit reports).
- **Full GUT suite:** 1,177/1,177. **Full gdUnit4 suite:** 167/167, 0 orphans.
- **Restoring the bugs:** each change below was put back on its own; these tests fail:

| Change restored                                           | Fails                                                                                                                                                                                                                                             |
|-----------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `body_entered` not connected (`area_entered` only)        | GUT: 5 in `test_projectile.gd`, including `test_physics_body_target_takes_damage_and_projectile_is_freed`. gdUnit4: `test_projectile_damages_physics_body_on_enemies_layer`                                                                       |
| No `_has_hit` guard                                       | GUT: `test_both_signals_for_one_target_apply_damage_once`, `test_two_targets_in_the_same_tick_only_the_first_takes_damage`, `test_zero_damage_still_counts_as_the_hit`                                                                            |
| `HitArea` on default layer 1 / mask 1                     | GUT: `test_hit_area_uses_player_projectiles_layer_and_enemies_mask`. gdUnit4: `test_projectile_damages_physics_body_on_enemies_layer`                                                                                                             |
| Per-shot `AudioStreamPlayer2D` on the root + filter write | GUT: `test_default_config_firer_uses_assets_from_default_bullet_tres`, `test_configured_sound_uses_weapon_bus_and_cleans_up_on_finish`, `test_firer_does_not_change_viewport_texture_filter`. gdUnit4: `test_firing_adds_no_sound_player_to_root` |

- **Benchmark (desktop, local, scenario unchanged):** per-second samples during the 60 s firing window, same container, `main` vs this PR. For the comparison only, the scratch copies also logged the `bullets` group size and the root `AudioStreamPlayer2D` count; the committed runner is unchanged.

| Metric (per-second samples) | `main`      | This PR     | Why                                                                                             |
|-----------------------------|-------------|-------------|-------------------------------------------------------------------------------------------------|
| Projectiles alive           | 61          | 60          | Sampling phase at a 0.075 s cooldown (difficulty 0.5); one projectile is 5 nodes either way.    |
| Root shot-sound players     | 2–3         | 0           | Shots use the pool (#1141).                                                                     |
| Nodes                       | 508–509     | 501         | −1 projectile (−5) and −2–3 sound players.                                                      |
| Objects                     | 2,556–2,559 | 2,489–2,490 | No `CircleShape2D` per shot (about 60 alive on `main`), no per-shot sound players or playbacks. |
| Resources                   | 210         | 213         | `projectile.tscn`, `projectile.gd` and the shared shape, loaded once.                           |
| Orphans (gameplay, reload)  | 0, 0        | 0, 0        |                                                                                                 |

  Frame timings changed less between `main` and this PR than between two runs of the same build on this machine, so they show no regression or gain. Both runs were valid. The CI PR table is the reference.

- **GDScript lint, format and docs:** `gdlint ./scripts`, `gdformat --check ./scripts` and `validate_gdscript_docs.py` on the changed scripts pass.
- **Not run locally:** Playwright (`weapon_firing_test.py`, `difficulty_flow_test.py`, `difficulty_integration_test.py`, `audio_flow_test.py`, `volume_sliders_mutes_test.py`), the web benchmark and the manual itch.io checks. PR run: _fill in after CI._

---

## Known Limitations / Follow-ups

- **Projectiles still live under the scene root** until their lifetime ends: #1140.
- **`test/gut/test_weapon_slot_cooldown.gd` runs in no CI job** (Confirm-first results). Moving it to `test/gdunit4/` would fix that; it's outside #1139 and #1141.
- **Pooling projectiles** waits for a benchmark that shows it's needed.
- **Manual itch.io checks still to do:**
  - Projectiles look the same, with no change to filtering or draw order (#1139).
  - Shots sound centered and at the expected volume at both sides of the screen (#1141).
  - The Weapon volume and mute controls still affect shots (#1141).
  - Rapid fire doesn't cut off menu sounds in normal play (#1141).
- **Next in #620:** #1140 (level-owned projectile lifecycle) is unblocked by this PR.

---

## Reviewer's Guide

### File-Level Changes

| Change                | Details                                                                                                                                                                                | Files                                                                                                                                                                                                                                                                                |
|-----------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Projectile scene.     | <ul><li>`Projectile` scene with shared shape, `HitArea` on layer 3 / mask 2, and lifetime timer.</li><li>`configure()`; one `_on_hit()` for areas and bodies; hit-once flag.</li></ul> | `scenes/projectile.tscn`<br/>`scripts/entities/projectile.gd`<br/>`scripts/entities/projectile.gd.uid`                                                                                                                                                                               |
| Named physics layers. | <ul><li>`player`, `enemies`, `player_projectiles`.</li></ul>                                                                                                                           | `project.godot`                                                                                                                                                                                                                                                                      |
| Firer.                | <ul><li>Spawns `projectile.tscn`; no texture-filter write.</li><li>`play_shot_sound()` through `SfxManager.play_stream()` on `SFX_Weapon`.</li></ul>                                   | `scripts/entities/bullet.gd`                                                                                                                                                                                                                                                         |
| SFX pool.             | <ul><li>`play_stream()`; `play_sfx()` and `play_stream()` share `_ensure_sfx_pool()` and `_play_on_pool()`.</li></ul>                                                                  | `scripts/managers/sfx_manager.gd`                                                                                                                                                                                                                                                    |
| Tests.                | <ul><li>Bullet config suite rewritten for the scene and the pool.</li><li>New projectile suite; `play_stream()` cases.</li><li>Real-overlap and firing-audio gdUnit4 cases.</li></ul>  | `test/gut/test_bullet_configuration.gd`<br/>`test/gut/test_projectile.gd`<br/>`test/gut/test_projectile.gd.uid`<br/>`test/gut/test_audio_sfx_centralization.gd`<br/>`test/gut/test_sfx_manager.gd`<br/>`test/gdunit4/test_bullet.gd`<br/>`test/gdunit4/test_weapon_firing_bullet.gd` |
| Milestone note.       | <ul><li>This note.</li></ul>                                                                                                                                                           | `files/docs/milestones/27/Part_24_Projectile_scene_hit_detection_&_pooled_shot_sounds.md`                                                                                                                                                                                            |

### Assessment against linked issues

| Issue                                                   | Objective                                                                           | Addressed | Explanation                                                                                                   |
|---------------------------------------------------------|-------------------------------------------------------------------------------------|-----------|---------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1139> | Projectiles come from `projectile.tscn`; code no longer assembles their nodes       | ✅         | `spawn_projectile()` instantiates the scene; pinned by the motion case and `test_projectile.gd`.              |
| <https://github.com/ikostan/SkyLockAssault/issues/1139> | Physics-body and `Area2D` targets can both be hit; each projectile hits once        | ✅         | GUT hit cases and the gdUnit4 real-overlap test; fail without `body_entered` or the `_has_hit` guard.         |
| <https://github.com/ikostan/SkyLockAssault/issues/1139> | Collision layers are named and set                                                  | ✅         | `project.godot` names; `HitArea` layer 3 / mask 2; pinned by GUT and the gdUnit4 positive and negative cases. |
| <https://github.com/ikostan/SkyLockAssault/issues/1139> | `bullet.gd` no longer changes the viewport's texture filter                         | ✅ / ⏳     | `test_firer_does_not_change_viewport_texture_filter`; the itch.io look check is still to do.                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1141> | Shot sounds use the pool on `SFX_Weapon` and are no longer positioned at the origin | ✅ / ⏳     | Pooled `AudioStreamPlayer` (non-positional) on `SFX_Weapon`; the itch.io listening check is still to do.      |
| <https://github.com/ikostan/SkyLockAssault/issues/1141> | Firing no longer adds audio nodes to the scene root                                 | ✅         | GUT pool cases and `test_firing_adds_no_sound_player_to_root`; the benchmark shows 0 root sound players.      |
| Both                                                    | All GUT, gdUnit4, Playwright and lint jobs pass, with no test cases removed         | ✅ / ⏳     | GUT, gdUnit4 and lint pass locally with no cases removed; Playwright runs in CI.                              |
| Both                                                    | Milestone note added                                                                | ✅         | This note.                                                                                                    |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1139 and #1141 from the #620 (Region 5) review.
- Chose to ship #1139 and #1141 in one PR, and kept #1102 and #1140 for separate ones.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked that #1138 is merged and #1139/#1141 are unblocked, and found the stale line numbers in both issues.
    - Compared candidate pairs (#1139 with #1141, #1140 or #1102) and recommended #1139 + #1141.
    - Ran the baseline GUT (1,153/1,153) and gdUnit4 (164/164) suites on `main`.
    - Found that `test/gut/test_weapon_slot_cooldown.gd` runs in no CI job, and confirmed its 3 tests pass when run by gdUnit4.
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, compared test names against `main`, and ran `gdformat`, `gdlint` and the docs validator.
    - Put each fixed behavior back to confirm the new tests catch it.
    - Ran the desktop benchmark on `main` and the branch, with extra counters in scratch copies to explain the node and object changes.
