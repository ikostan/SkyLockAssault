<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Main scene and tuning cleanup

---

## PR Summary

**Title:** Architect review region 5 gameplay entities scene typography optimization  
**PR:** [#1256](https://github.com/ikostan/SkyLockAssault/pull/1256)  
**Branch:** `architect-review-region-5-gameplay-entities-scene-typography-optimization` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1151 – [FEATURE] Main scene and tuning cleanup](https://github.com/ikostan/SkyLockAssault/issues/1151)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `documentation`, `testing`, `refactoring`, `EPIC`

### Purpose

The sixth and last part of #620 (Region 5: Gameplay Entities & Scene Typography Optimization). It fixes the seven remaining Low findings:

| Finding                                                | Fixed by          |
|--------------------------------------------------------|-------------------|
| Difficulty and fire cooldown behavior isn't documented | Key Change 1      |
| Low-speed threshold formula is repeated                | Key Change 2      |
| `print()` and untyped `TelemetryScript`                | Key Change 3      |
| Bush and decor layer setup is nearly identical         | Key Change 4      |
| An older message's timer can hide a newer message      | Key Change 5      |
| Gameplay code depends on a UI constant                 | Key Change 6      |
| Spawn, bounds, and speed values are unexplained        | Key Change 7      |

Gameplay is unchanged apart from the top movement bound, which moves from `-0.83` to exactly `-5/6` of the screen height (about 3.6 pixels on a 1080-pixel screen).

---

## Confirm-first results

- **Blockers closed.** #1102 (Part 26) and #1148 are closed; PR #1252 is merged; `main` at `23f338b`.
- **Issue line numbers had moved.** #1102 removed `_process()` from `main_scene.gd` and added the Settings signal handlers, so every `main_scene.gd` line in the issue was off. The code itself matched the findings.
- **`test_difficulty_integration.gd` already checks difficulty 2.0** for fuel and cooldown, but not the direction across levels, and not scrolling.
- **The bottom bound needs no change.** `screen_size.y / 6` already equals `(1 - 5/6) * height`.
- **Baseline on `main`:** full GUT suite 1,224/1,224 (118 scripts, 13,892 asserts).

---

## Key Changes

### 1. Document difficulty (`game_settings_resource.gd`)

- `GameSettingsResource.difficulty` has a doc comment: the range (0.5-2.0), and that higher difficulty lengthens the fire cooldown, burns fuel faster and scrolls faster, with the file that applies each.
- One-line comments at the three call sites (`bullet.gd`, `player.gd`, `parallax_manager.gd`) point back to it.

### 2. Share the low-speed threshold (`speed_resource.gd`)

- New `SpeedResource.get_low_threshold() -> float`: `min_speed + (max_speed - min_speed) * low_yellow_fraction`.
- Used at all four places that repeated the formula: the `speed_low` check in `SpeedResource.current_speed`, the `speed_low` bridge in `player.gd`, and `update_speed_bar()` and `check_speed_warning()` in `hud.gd`.

### 3. Logging and typing (`main_scene.gd`, `web_telemetry_adapter.gd`)

- `print("Viewport size: ", ...)` is now `Globals.log_message(..., Globals.LogLevel.DEBUG)`.
- `web_telemetry_adapter.gd` declares `class_name WebTelemetryAdapter`. `main_scene.gd` creates it with `WebTelemetryAdapter.new()`, and `web_telemetry_adapter` is typed `WebTelemetryAdapter` instead of `Node`. The runtime `load()` is gone.

### 4. Shared layer setup (`main_scene.gd`)

- New private `_populate_sprite_layer(layer, id_prefix, viewport, configure: Callable)`. It frees the layer's children, finds the textures by prefix, adds two sprites per texture with a random texture, scale (0.5-1.5) and position, and sets `motion_scale` and `motion_mirroring`.
- `configure` runs per sprite after the scale is set and before the position is picked. `_configure_decor_sprite()` holds the decor flips and cardinal rotation; the bushes pass an empty `Callable`.
- `setup_bushes_layer()` and `setup_decor_layer()` stay as public one-line wrappers.
- The rotation list is now the `DECOR_ROTATIONS` constant.
- Each layer keeps its `motion_scale` (1, 0.5), density, scale range and mirroring. The random calls run in the same order as before, so a given seed gives the same layout.

### 5. Message timer (`main_scene.gd`)

- New `_message_generation` counter. Each `show_message()` increases it and remembers its own value.
- When a message's time is up, the label is hidden only if the generation hasn't changed, so an older timer can no longer hide a newer message.
- `_showing_unbound_key_message` still resets when a `KEY_PRESS_UNBOUND` message expires, even if a newer message is showing, so that warning can appear again.
- The 4-second duration is the `MESSAGE_DURATION` constant.

### 6. Deadzone constant (`settings.gd`)

- `AXIS_DEADZONE_THRESHOLD` (0.5) moved from `InputRemapButton` to `Settings`, with a doc comment.
- `main_scene.gd` and `input_remap_button.gd` use `Settings.AXIS_DEADZONE_THRESHOLD`. `main_scene.gd` no longer refers to `InputRemapButton`.
- Both count an axis at or above the threshold (`45e024d`). Key Mapping used `>`, while gameplay ignored only values below 0.5, so at exactly 0.5 the game reported an unbound input that Key Mapping wouldn't accept. `input_remap_button.gd` now uses `>=`, as Godot counts an action pressed from its deadzone up; the constant's doc comment says so.

### 7. Spawn, bounds and speed values (`player_stats_resource.gd`)

- New `PlayerStatsResource.spawn_y_fraction`, default `5.0 / 6.0`, with an editor range of 0-1.
  - `main_scene.gd` spawns the player at `viewport.y * spawn_y_fraction` (was `viewport.y / 1.2`, the same point).
  - `player.gd` uses it for both vertical bounds: `-spawn_y_fraction * height` (was `-0.83`) and `(1 - spawn_y_fraction) * height` (was `height / 6`, the same value).
- New `PlayerStatsResource.starting_speed`, default 250.0, replacing the literal in `player.gd`.
- `main_scene.gd` reads the fraction from the player's stats, falling back to `Player.DEFAULT_PLAYER_STATS`, so spawn and bounds always use the same value.

### 8. Tests

**No test case was removed.**

- **Updated:**
  - `test/gut/test_player_stats_bounds.gd`: top-bound expectations move by `0.0333 * height` (−2 at 600 px, −1.6 at 480 px).
  - `test/gut/test_input_remap_ec.gd` and `test/gut/test_input_remap_button_device_aware.gd`: use `Settings.AXIS_DEADZONE_THRESHOLD`.
- **New `test/gut/test_sprite_layer_setup.gd` (10 tests, LAYER-01 to LAYER-10):** bush and decor counts, scale ranges, positions, motion scale and mirroring; bushes aren't rotated or flipped; the height follows `parallax_screens_tall`; a seeded rebuild repeats; no matching textures or an unknown prefix leave the layer empty; a null layer is ignored; `configure` runs once per sprite; rebuilds leave no orphans.
- **New `test/gut/test_main_scene_messages.gd` (10 tests):**
  - MSG-01 to MSG-07: a single message hides after 4 s; a second message stays for its full 4 s after the first timer ends; one generation per call; the `KEY_PRESS_UNBOUND` flag resets under a newer message and stays set while its own message shows; the critical warning stays once per session; back-to-back messages. The suite raises `Engine.time_scale` to 8, so each 4-second message takes about 0.5 real seconds.
  - DZ-01 to DZ-03: the constant moved and kept its value; a small movement on an unbound axis is ignored; a larger one warns.
- **`test/gut/test_speed_resource.gd` (+4):** `get_low_threshold()` with defaults, custom values and equal limits; `speed_low` fires at the threshold and not just above.
- **`test/gut/test_hud.gd` (+1, parameterized):** the HUD warning and color switch at the same threshold as `speed_low`.
- **`test/gut/test_player_stats_bounds.gd` (+7):** default fraction and speed; exact `-5/6` top bound; the spawn point is inside the bounds and the bounds reach both edges; custom fractions move both bounds; custom starting speeds apply and are clamped; the player's `speed_low` passes `get_low_threshold()`; `MainScene` spawns at the player's fraction.
- **`test/gdunit4/test_difficulty_integration.gd` (+1):** at difficulty 0.5, 1.0 and 2.0, cooldown, fuel burn and scroll step all increase, and 2.0 is twice Normal.
- **CodeRabbit's tests (`4850054`, 7 tests, 9 cases):**
  - `test_input_remap_button_device_aware.gd`: `test_gamepad_remap_accepts_motion_at_deadzone` (±1). Just below the threshold keeps the old binding; exactly at it remaps with the sign kept. Renamed from `test_gamepad_remap_requires_motion_beyond_deadzone` and its boundary flipped in `45e024d` (Key Change 6).
  - `test_main_scene_messages.gd`: the key-press flag resets on expiry even when the message label was freed; an unbound axis at exactly 0.5 warns, in both directions (±1); a bound axis doesn't warn.
  - `test_player_stats_bounds.gd`: spawn-fraction and starting-speed changes apply only to the next player; the player's `speed_low` passes the threshold for limits and fraction changed after spawn.
  - `test_sprite_layer_setup.gd`: rebuilding decor keeps the same bush sprites and mirroring.

---

## Design Decisions

- **`configure` runs before the position is picked,** matching the old decor order (scale, flips, rotation, position), so the random sequence and seeded layouts don't change (LAYER-05).
- **An empty `Callable` means "nothing extra",** instead of a no-op function, so the bush wrapper stays one line.
- **`main_scene.gd` reads the spawn fraction from the player's stats,** not from its own export, so one value drives spawn and bounds. The player sets its default stats in its own `_ready()`, which runs first; the fallback only guards that order.
- **The difficulty comments at the call sites only point to the property,** so the description lives in one place.
- **Message tests speed up time** with `Engine.time_scale` instead of shortening `MESSAGE_DURATION`, so they test the shipped duration. Test waits use `SceneTreeTimer`s too, so they scale the same way, with a 0.5 s game-time margin on each side of every timer.
- **No alias was left on `InputRemapButton`** for the deadzone, so the UI class can't become a dependency again (DZ-01).
- **The deadzone boundary is inclusive (`>=`) in both places,** matching Godot's own pressed check. The alternative, `>` in both, would have changed gameplay instead of Key Mapping.

---

## Review

- **CodeRabbit, review (`5c6e854`):** review limit reached; no comments.
- **CodeRabbit, unit test generation (`4850054`):** 7 tests (9 cases), all kept. Reviewed: all pass, and each catches a real change (Verification). `test_gamepad_remap_requires_motion_beyond_deadzone` and `test_unbound_axis_at_exact_deadzone_warns_in_either_direction` pinned opposite rules at exactly 0.5; fixed in `45e024d` by making Key Mapping inclusive. Style: no `##` comments or IDs, and `:=` inference; not changed.
- **Sourcery:** "looks great"; reviewer's guide and linked-issue check at `45e024d`. #620: 15 of 15 met. #1151: 9 of 12 met, 3 to check by hand (CI, benchmark, manual itch.io checks).
- **DeepSource:** grade A on `23f338b...45e024d`, no inline issues.
- **Qodo:** reviews paused for this account.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdlint ./scripts` and `gdformat --check ./scripts` as in CI.

| State                    | GUT scripts | GUT tests | GUT asserts | gdUnit4 tests |
|--------------------------|-------------|-----------|-------------|---------------|
| `main` (`23f338b`, base) | 118         | 1,224     | 13,892      | 169           |
| `b8ece90` (#1151 code)   | 120         | 1,256     | 15,960      | 170           |
| This PR (`45e024d`)      | 120         | 1,263     | 15,997      | 170           |

The gdUnit4 count on `main` is from Part 26; this PR adds one gdUnit4 test. CodeRabbit's 7 tests make up the GUT difference between `b8ece90` and `45e024d`.

- **PR CI at `b8ece90`:** all jobs pass: GUT, gdUnit4, GDScript lint and format, Markdown lint, the web build, both browser shards ("Core Web Flows", "CI & Security") and the desktop and web benchmarks (report only). YAML lint and CI infrastructure tests skipped (no changes).
- **PR CI at `45e024d`:** the pipeline was still running when this note was updated.
- **Full GUT suite locally at `45e024d`:** 1,263/1,263.
- **Full gdUnit4 suite locally at `45e024d`:** 170/170 (27 suites), 0 orphans.
- **GDScript lint and format:** `gdlint ./scripts` and `gdformat --check ./scripts` pass.
- **Restoring the old behavior:** each change below was made on its own; these tests fail:

| Change                                            | Fails                                                                                |
|---------------------------------------------------|--------------------------------------------------------------------------------------|
| Older timer hides the label (no generation check) | MSG-02, MSG-04                                                                       |
| No deadzone check in `MainScene._input()`         | DZ-02                                                                                |
| Top bound back to `-0.83`                         | 13 tests in `test_player_stats_bounds.gd`                                            |
| Spawn back to `viewport.y / 1.2`                  | `test_main_scene_spawn_follows_player_stats` (custom fractions)                      |
| Starting speed back to `250.0`                    | `test_custom_starting_speed_applies`                                                 |
| Decor flips and rotation also applied to bushes   | LAYER-03                                                                             |
| Low threshold computed with the high fraction     | 7 tests in `test_speed_resource.gd`, `test_hud.gd` and `test_player_stats_bounds.gd` |
| Key Mapping back to `>` (ignores exactly 0.5)     | `test_gamepad_remap_accepts_motion_at_deadzone`                                      |
| Gameplay ignores exactly 0.5 (`<=`)               | `test_unbound_axis_at_exact_deadzone_warns_in_either_direction`                      |
| Key-press flag not reset when the label is gone   | `test_message_expiry_releases_key_warning_when_label_was_freed`                      |
| `_input()` warns without checking the binding     | `test_bound_axis_at_exact_deadzone_does_not_warn`                                    |
| Player stores the low threshold at spawn          | `test_player_speed_low_reports_updated_limits_and_fraction`                          |
| Decor rebuild also rebuilds the bushes            | `test_rebuilding_decor_preserves_bush_sprites_and_mirroring`                         |

Six of CodeRabbit's seven tests are the only test in their files that catches their change. The seventh, `test_spawn_tuning_changes_apply_to_the_next_player_only`, overlaps two existing bounds tests.

- **Not run locally:** Playwright, the benchmarks and the manual itch.io checks. CI ran Playwright and the benchmarks at `b8ece90`.

---

## Known Limitations / Follow-ups

- **Manual itch.io checks still to do:**
  - The plane spawns and moves to its limits as before (the top limit is about 3.6 px higher on a 1080-pixel screen).
  - Background bushes and decor look as before.
- **Benchmark:** the scenario is unchanged and both jobs pass at `b8ece90` (report only); check the PR table for regressions.
- **PR CI at `45e024d`:** still running when this note was updated. The commit changes one comparison in `input_remap_button.gd`, a doc comment and one test.
- **Still open from Part 24:** `test/gut/test_weapon_slot_cooldown.gd` runs in no CI job.
- **#620 is complete with this PR.** Next: #621 (Region 6) and #625 (Performance Validation, Part 2).

---

## Reviewer's Guide

### File-Level Changes

| Change           | Details                                                                                                                                                        | Files                                                                                                                                                                                                                                                                                                                                       |
|------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Difficulty docs. | <ul><li>Doc comment on `difficulty`; pointers at the three call sites.</li></ul>                                                                               | `scripts/resources/game_settings_resource.gd`<br/>`scripts/entities/bullet.gd`<br/>`scripts/entities/player.gd`<br/>`scripts/managers/parallax_manager.gd`                                                                                                                                                                                  |
| Low threshold.   | <ul><li>`get_low_threshold()`, used at four places.</li></ul>                                                                                                  | `scripts/resources/speed_resource.gd`<br/>`scripts/entities/player.gd`<br/>`scripts/ui/hud.gd`                                                                                                                                                                                                                                              |
| Main scene.      | <ul><li>Debug logging, typed adapter.</li><li>Shared layer helper.</li><li>Message generation.</li><li>Deadzone from Settings; spawn from stats.</li></ul>     | `scripts/core/main_scene.gd`<br/>`scripts/system/web_telemetry_adapter.gd`                                                                                                                                                                                                                                                                  |
| Deadzone.        | <ul><li>`AXIS_DEADZONE_THRESHOLD` moved to `Settings`.</li><li>Key Mapping accepts exactly 0.5 (`>=`), like gameplay.</li></ul>                                | `scripts/core/settings.gd`<br/>`scripts/ui/components/input_remap_button.gd`                                                                                                                                                                                                                                                                |
| Player stats.    | <ul><li>`spawn_y_fraction`, `starting_speed`; bounds use the fraction.</li></ul>                                                                               | `scripts/resources/player_stats_resource.gd`<br/>`scripts/entities/player.gd`                                                                                                                                                                                                                                                               |
| Tests.           | <ul><li>Two new GUT suites; additions to four GUT suites and one gdUnit4 suite; updated bounds and deadzone references.</li><li>CodeRabbit: 7 tests.</li></ul> | `test/gut/test_sprite_layer_setup.gd`<br/>`test/gut/test_main_scene_messages.gd`<br/>`test/gut/test_speed_resource.gd`<br/>`test/gut/test_hud.gd`<br/>`test/gut/test_player_stats_bounds.gd`<br/>`test/gut/test_input_remap_ec.gd`<br/>`test/gut/test_input_remap_button_device_aware.gd`<br/>`test/gdunit4/test_difficulty_integration.gd` |
| Milestone note.  | <ul><li>This note.</li></ul>                                                                                                                                   | `files/docs/milestones/27/Part_27_Main_scene_&_tuning_cleanup.md`                                                                                                                                                                                                                                                                           |

### Assessment against linked issues

| Issue                                                   | Objective                                                         | Addressed | Explanation                                                                    |
|---------------------------------------------------------|-------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1151> | The seven findings are resolved as described                      | ✅        | Key Changes 1-7.                                                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1151> | Gameplay unchanged, apart from the small top-bound correction     | ✅        | Seeded layouts repeat (LAYER-05); difficulty factors unchanged; same spawn.    |
| <https://github.com/ikostan/SkyLockAssault/issues/1151> | A newer message is never hidden early by an older timer           | ✅        | MSG-02, MSG-04.                                                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1151> | All GUT, gdUnit4, Playwright and lint jobs pass; no cases removed | ⏳        | All pass in CI at `b8ece90` and locally at `45e024d`; CI at `45e024d` running. |
| <https://github.com/ikostan/SkyLockAssault/issues/1151> | The PR's milestone note is added under `files/docs/milestones/`   | ✅        | This note.                                                                     |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1151 from the #620 (Region 5) review, with the seven findings and the implementation plan.
- Asked to finish epic #620 with this last sub-issue.
- Opened PR #1256 and committed the #1151 changes (`b8ece90`).
- Started CodeRabbit's unit-test generation, and chose to make Key Mapping's deadzone inclusive.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Checked #1151 and its blockers (#1102, #1148), and that no PR for it existed.
    - Found that the issue's `main_scene.gd` line numbers had moved after #1102, and that the bottom bound needed no change.
  - **Tests**
    - Updated the bounds and deadzone tests, wrote the two new GUT suites and the additions to four GUT suites and one gdUnit4 suite.
  - **Review**
    - Reviewed CodeRabbit's seven tests: ran them, broke each covered behavior to confirm the test catches it, and found the two that pinned opposite rules at exactly 0.5.
    - Proposed the inclusive boundary, and committed it with the updated test (`45e024d`).
    - Reviewed PR #1256: CI results and the bot reviews.
  - **Verification**
    - Ran the full GUT and gdUnit4 suites on `main` and the branch, `gdlint` and `gdformat`.
    - Restored thirteen old behaviors one at a time to confirm the tests catch each.
    - Wrote this note and updated it for `4850054` and `45e024d`.
- **@coderabbitai**
  - **Tests (`4850054`):** 7 tests (9 cases) in four GUT suites.
- **@sourcery-ai:** review, reviewer's guide and the linked-issue check (#620: 15 of 15; #1151: 9 of 12 met, 3 by hand).
- **@deepsource-io:** grade A.
