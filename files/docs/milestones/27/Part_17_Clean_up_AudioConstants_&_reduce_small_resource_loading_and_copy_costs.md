<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Clean up AudioConstants & reduce small resource loading and copy costs

---

## PR #1206 Summary

**Title:** Clean up AudioConstants and reduce small resource loading costs  
**PR:** [#1206](https://github.com/ikostan/SkyLockAssault/pull/1206)  
**Branch:** `architect-review-region-2` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1149 – [FEATURE] Clean up AudioConstants names and autoload](https://github.com/ikostan/SkyLockAssault/issues/1149)
- [#1150 – [FEATURE] Reduce small resource loading and copy costs](https://github.com/ikostan/SkyLockAssault/issues/1150)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** FEATURE

### Purpose

This PR covers the five Low findings of Region 2 (#617), the last open work in that epic. After it, every #617 sub-issue is closed. The two parts touch different files.

**Part A: Clean up AudioConstants names and autoload (#1149).**

- `AudioConstants` was an autoload `Node` that held only constants, with no state or functions.
- One sound had three names. `SFX_CHECK = "check"` wasn't in `SFX_ASSET_MAP` and played only through the `.wav` fallback. `SFX_MUTE_TOGGLE` mapped to the same `check.wav` and was unused. `advanced_settings.gd` used the literal `"check"`.
- `player.gd` set the rotor buses with the literals `"SFX_Rotor_Left"` and `"SFX_Rotor_Right"`, which weren't in `AudioConstants`.

**Part B: Reduce small resource loading and copy costs (#1150).**

- `BulletResource` preloaded its texture and sound in script defaults, so any script that loaded the class loaded both assets. `default_bullet.tres` referenced the same files but didn't assign them.
- The `WeaponResource.available_weapons` getter returns a copy. The `current_index` setter and `hud.gd` read it several times, copying the list each time.

Neither part runs per frame, so no visible performance change is expected.

---

## Key Changes

### Part A: Clean up AudioConstants names and autoload (#1149)

#### 1. Class instead of autoload (`audio_constants.gd`, `project.godot`, `README.md`)

- `AudioConstants` is now `class_name AudioConstants` with no `extends`. The header comment says why it isn't an autoload.
- The `AudioConstants` line is removed from `[autoload]` in `project.godot`.
- Every constant name is kept, so the existing `AudioConstants.X` references work unchanged.
- **`README.md`:** the autoload order line no longer lists `AudioConstants`.

#### 2. One name for the check sound (`audio_constants.gd`, `advanced_settings.gd`)

- `SFX_ASSET_MAP` gains `"check": "check.wav"`, so `SFX_CHECK` no longer depends on the `.wav` fallback.
- `SFX_MUTE_TOGGLE` and its `"mute_toggle"` map entry are removed. No production code or test used them.
- `advanced_settings.gd`: `_on_fps_toggle_pressed()` plays `AudioConstants.SFX_CHECK` instead of `"check"`.

#### 3. Rotor bus constants (`audio_constants.gd`, `player.gd`)

- New `BUS_SFX_ROTOR_LEFT` (`"SFX_Rotor_Left"`) and `BUS_SFX_ROTOR_RIGHT` (`"SFX_Rotor_Right"`), with a doc comment saying they send to `SFX_Rotors`.
- They aren't added to `BUS_CONFIG`, because `SFX_Rotors` owns their volume and mute.
- `player.gd` sets the rotor buses from the new constants.

#### 4. Tests

- **`test_audio_constants_discoverability.gd` (12 → 18 cases):**
  - The local rotor constants and their "not exposed in AudioConstants" comment are gone. The routing and saved-layout cases use the new constants, including their `use_parameters()` lists.
  - `test_bus_name_constants` also checks the two rotor constants.
  - The `"SFX_ASSET_MAP" in AudioConstants` assertion works on the class unchanged, so it was kept.
  - **New:** `test_audio_constants_is_not_an_autoload` (no `autoload/AudioConstants` setting, no `/root/AudioConstants` node), `test_check_sound_is_mapped_once` (`SFX_CHECK` is mapped to an existing `check.wav`, `"mute_toggle"` is gone), `test_each_sfx_file_has_one_logical_id`, `test_rotor_playback_buses_are_not_in_bus_config`, `test_player_rotors_use_left_and_right_buses` (instantiates `Player.tscn`), `test_advanced_settings_fps_toggle_plays_check_sound`.
- **`test_audio_sfx_centralization.gd` (9 → 11 cases):**
  - **Rewritten:** `test_play_sfx_unmapped_legacy_fallback` played `"check"` to reach the `.wav` fallback. Every shipped `.wav` is mapped now, so it plays an ID with no entry and no file and reads the path the fallback built from SfxManager's "file not found" warning. It also checks that the ID is cached as missing and nothing plays.
  - **New:** `test_play_sfx_check_resolves_through_asset_map`.

### Part B: Reduce small resource loading and copy costs (#1150)

#### 1. Default assets move to the data file (`bullet_resource.gd`, `default_bullet.tres`)

- `projectile_texture` and `shot_sound` have no default value. Their doc comments say the data file assigns them and what null means (no texture, silent firing).
- `default_bullet.tres` assigns both through its existing `ext_resource` entries (`1_le8fa`, `3_u7yt8`).
- `bullet.gd` still preloads `default_bullet.tres`, so the shipped game loads the same two assets.
- No other scene or resource used the script defaults: `default_bullet.tres` is the only `BulletResource` data file, and the gdUnit4 `test_bullet.gd` case that calls `BulletResource.new()` checks damage only.

#### 2. Single-name lookup (`weapon_resource.gd`, `hud.gd`)

- **New `get_weapon_name(index) -> String`:** returns the name at an index, or `"None"` out of range.
- **New `NO_WEAPON_NAME` constant (`"None"`):** used by the lookup and by the setter's empty-list placeholder.
- **New private `_weapons` array** holds the list. `available_weapons` keeps its export, setter and copying getter, but reads and writes `_weapons`. See Design Decisions for why.
- The `available_weapons` and `current_index` setters use `_weapons` and `get_weapon_name()`, so they no longer copy the list. `max` became `maxi` in both.
- `hud.gd` `setup_hud()`: the initial weapon sync is one `get_weapon_name()` call. The old bounds check is removed, because the resource always keeps `current_index` inside a non-empty list.

#### 3. Tests

- **`test_bullet_resource.gd` (9 → 13 cases):**
  - **Rewritten:** `test_defaults_preserve_existing_projectile_behavior` keeps every numeric check, and its asset checks now load `default_bullet.tres`.
  - **Rewritten:** `test_new_resources_do_not_share_mutable_tuning` assigns both assets to both resources first, then checks that clearing them on one leaves the other's.
  - **New:** `test_new_resource_has_no_default_assets`, `test_default_bullet_tres_assigns_assets` (the `.tres` assigns both, with the same numeric tuning as a new resource), `test_bullet_resource_script_does_not_preload_assets`.
  - `test_custom_configuration_survives_scene_packing` is unchanged and passes.
- **`test_bullet_configuration.gd` (12 → 14 cases):** new `test_default_config_firer_uses_assets_from_default_bullet_tres`. A config-less firer in the tree fires through `fire()` and must produce one projectile with the laser texture and one sound player with the laser sound, so the test also fails if `fire()` stops spawning or playing the sound. The missing-texture and silent-firing cases are unchanged and pass.
- **`test_weapon_resource.gd` (11 → 25 cases):** new cases for names by index, out-of-range `"None"` (-1, -50, 2, 99), the empty-list placeholder, the default list, the returned string not aliasing the list, a `.tres` save and load round trip, `Resource.duplicate()`, and `weapon_swapped` names on all three emit paths. Both `available_weapons` mutation cases are unchanged and pass.
- **`test_hud.gd` (12 → 17 cases):** new cases for the default name after setup, setup on a resource already at index 1, and setup again after a swap.

#### 4. Review follow-up tests (CodeRabbit, `18bb313`)

CodeRabbit added 11 cases on the PR, counted in the numbers above. @claude reviewed them and adjusted four.

- **`test_weapon_resource.gd` (+6):** lookups don't change the selection or emit; clearing the list clamps a selected last slot and emits `(0, "None")` once, a second clear is a no-op, and refilling emits again; a shrink emits even when the clamped slot has the same name; the lookup is isolated from edits to the input and returned arrays; instances don't share `_weapons` (fails with a `static` backing array); names keep empty strings, case and whitespace.
- **`test_hud.gd` (+2):** setup on an empty list replaces a stale label with `{NONE}` and follows the new resource; setup after a shrink shows the clamped weapon, and the replaced resource no longer drives the HUD (message reworded).
- **`test_bullet_resource.gd` (+1):** `test_optional_assets_survive_scene_packing`, for texture-only, sound-only and no assets. Added `assert_null` for unassigned assets, without which the test also passed with the old script defaults; it now fails if a default comes back.
- **`test_bullet_configuration.gd` (+1):** firing with a fresh resource spawns an untextured projectile, plays nothing, and leaves `default_bullet.tres` unchanged. Comment corrected: the test can't detect a fall-back to `default_bullet.tres`, because `bullet.gd` only uses it when `config` is null at `_ready()`.
- **`test_audio_sfx_centralization.gd` (+1):** the check sound resolves on a cold lookup and on a cache hit, on the menu bus. The expected path now comes from `AudioConstants` instead of a hard-coded string.

---

## Design Decisions

### Part A (#1149)

- **No `extends` line.** A `class_name` script with only constants defaults to `RefCounted` and is never instantiated, so there's nothing to extend.
- **`SFX_CHECK` kept, `SFX_MUTE_TOGGLE` removed.** As the issue proposes. `SFX_CHECK` is the name `key_mapping.gd` and `AudioManager` already use.
- **The fallback test reads a log line.** The `.wav` fallback is still in `SfxManager` (out of scope), but no shipped sound reaches it any more. The warning is the only public place that shows the built path. The test swaps in a fresh `GameSettingsResource` while it captures logs, so it can't trigger a settings save.

### Part B (#1150)

- **A private backing array.** The issue's sketch adds `get_weapon_name()` next to the existing property. In Godot 4 a property's getter also runs when its own class reads it, so a lookup that read `available_weapons` would still copy the list. A probe on 4.7.1 confirmed it: one read inside the class called the getter once. Godot's docs suggest a separate variable for direct access, so the list lives in `_weapons`, and the export, setter, copying getter and saved `.tres` format stay the same.
- **`_weapons` repeats the export default.** Godot doesn't call the setter for a member's initial value, so `_weapons` starts as `["Machine Gun"]` too. `test_default_weapon_list_matches_lookup` fails if they drift apart.
- **`"None"` kept as the missing-weapon name.** Review suggested a nullable result or a validity check, because a weapon named `"None"` and an out-of-range index return the same string. #1150 specifies the `String` return with `"None"`, the old code already used it for both cases, and no caller needs to tell them apart, so a `Variant` return or `has_weapon()` waits for a feature that needs it.
- **HUD bounds check removed.** It only guarded against an index outside the list, which the setters prevent. If it ever happened, the HUD would now show `{NONE}` instead of keeping a stale label.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 6.2.0, using the same commands as `gut_tests.yml` and `gdunit4_tests.yml` (gdUnit4-coverage stripped, `xvfb-run`). `gdformat --check` and `gdlint` as in CI.

- **Totals:**

| State                     | GUT scripts | GUT tests | GUT asserts | gdUnit4 cases |
|---------------------------|-------------|-----------|-------------|---------------|
| `main` (`65a8251`, base)  | 107         | 958       | 10,803      | 164           |
| This PR                   | 107         | 991       | 10,950      | 164           |

- **Test counts per changed file (`main` → this PR):**

| File                                      | Framework | Cases   |
|-------------------------------------------|-----------|---------|
| `test_audio_constants_discoverability.gd` | GUT       | 12 → 18 |
| `test_audio_sfx_centralization.gd`        | GUT       | 9 → 11  |
| `test_bullet_resource.gd`                 | GUT       | 9 → 13  |
| `test_bullet_configuration.gd`            | GUT       | 12 → 14 |
| `test_weapon_resource.gd`                 | GUT       | 11 → 25 |
| `test_hud.gd`                             | GUT       | 12 → 17 |

- **No test cases removed.** Three were rewritten: the fallback case and the two `BulletResource` default cases. The suites the issues name pass: `test_sfx_cache_diagnostics.gd`, `test_audio_settings_comprehensive.gd`, `test_audio_sfx_centralization.gd`, `test_weapon_firing_state.gd` (GUT), `test_player.gd`, `test_bullet.gd` (gdUnit4). The issue's `test_weapon_firing_bullet.gd` doesn't exist; the gdUnit4 firing case is in `test_bullet.gd`.
- **GUT warnings:** 3, the same 3 as on `main`.
- **Local flake (not from this PR):** running only the audio suites together, `test_audio_settings_interaction.gd` `test_mute_toggle_triggers_audio` fails with `ERR_FILE_CORRUPT` on a `user://settings.cfg` an earlier suite wrote. It fails the same way on unchanged `main` and passes in the full suite and on its own.
- **Mutation check:** `main`'s production scripts, `project.godot` and `default_bullet.tres` were put back with the new tests:
  - 12 cases fail in `test_bullet_resource.gd` and `test_audio_constants_discoverability.gd`: no-default-assets, `.tres` assigns assets, no preload, not an autoload, check sound mapped once, and every case that uses the rotor constants.
  - `test_weapon_resource.gd` and `test_hud.gd` don't load, because `get_weapon_name()` is missing.
- **Engine probe (Part B):** a property getter that counts calls ran once for one read from inside its own class.
- **Full GUT suite after the review follow-up tests:** 991/991 locally, same 3 warnings as `main`.
- **PR run (`41aae08`):** GUT, gdUnit4, GDScript lint and format, Markdown lint and DeepSource pass.
- **Playwright (PR run):** Core Web Flows shard 65 passed; CI & Security shard 1123 passed (plus 3 passed, 2 skipped in its own check).
- **Benchmark (PR run, report only, baseline `65a8251`):** 0 regressions, 0 warnings on both platforms.

| Metric                      | Desktop baseline → now | Web baseline → now  |
|-----------------------------|------------------------|---------------------|
| Frame interval p95 (ms)     | 17.044 → 17.008        | 43.900 → 33.700     |
| Dropped frames (> 33.4 ms)  | 0 → 0                  | 1,495 → 111         |
| Process, worst/s avg (ms)   | 0.214 → 0.165          | 6.692 → 5.760       |
| Physics, worst/s avg (ms)   | 0.300 → 0.316          | 0.942 → 1.163       |
| OBJECT_RESOURCE_COUNT avg   | 206 → 208              | 206 → 208           |

  No per-frame code changed, so the web timing gains are runner variation, not this PR.

- **Manual check on itch.io:** _after deploy: menu clicks, mute clicks, rotor sounds, bullet sprite and shot sound unchanged._

---

## Known Limitations / Follow-ups

- **#1139 and #1141 are still open.** #1150 asked to land after them to avoid conflicts. Neither has a branch yet, so there is nothing to rebase; when they start, they'll build on this PR and update `test_default_config_firer_uses_assets_from_default_bullet_tres` for the new projectile spawning and SFX pool playback. #1150's Additional Context records this decision.
- **The `.wav` fallback stays in `SfxManager`** with no shipped sound using it. Removing it would change SFX resolution, which belongs with the SFX pool work in #1141.
- **`BulletResource.new()` has no assets.** Code that builds a bullet config in code must assign a texture and sound, or get a projectile without a sprite and silent firing. Only tests do this today.
- **#617 can close** once this merges. Its Findings list still has three unticked items for #1145 and #1146, which are already closed.

---

## Reviewer's Guide

### File-Level Changes

| Change                      | Details                                                                                                                            | Files                                                                                                                                            |
|-----------------------------|------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| A: Class, not autoload.     | <ul><li>`class_name AudioConstants`, no `extends`.</li><li>Autoload entry and README mention removed.</li></ul>                    | `scripts/resources/audio_constants.gd`<br/>`project.godot`<br/>`README.md`                                                                       |
| A: One check sound name.    | <ul><li>`"check"` mapped; `SFX_MUTE_TOGGLE` and `"mute_toggle"` removed.</li><li>FPS toggle uses `SFX_CHECK`.</li></ul>            | `scripts/resources/audio_constants.gd`<br/>`scripts/ui/menus/advanced_settings.gd`                                                               |
| A: Rotor bus constants.     | <ul><li>`BUS_SFX_ROTOR_LEFT` / `BUS_SFX_ROTOR_RIGHT`, not in `BUS_CONFIG`.</li><li>Used by the player.</li></ul>                   | `scripts/resources/audio_constants.gd`<br/>`scripts/entities/player.gd`                                                                          |
| A: Tests.                   | <ul><li>6 cases added, 1 rewritten, 1 added in the centralization suite.</li></ul>                                                 | `test/gut/test_audio_constants_discoverability.gd`<br/>`test/gut/test_audio_sfx_centralization.gd`                                               |
| B: Assets in the data file. | <ul><li>No asset preloads in `BulletResource`.</li><li>`default_bullet.tres` assigns both.</li></ul>                               | `scripts/resources/bullet_resource.gd`<br/>`config_resources/default_bullet.tres`                                                                |
| B: Single-name lookup.      | <ul><li>`get_weapon_name()`, `NO_WEAPON_NAME`, private `_weapons`.</li><li>Setters and HUD sync no longer copy the list.</li></ul> | `scripts/resources/weapon_resource.gd`<br/>`scripts/ui/hud.gd`                                                                                   |
| B: Tests.                   | <ul><li>2 cases rewritten, 15 added.</li><li>No test cases removed.</li></ul>                                                      | `test/gut/test_bullet_resource.gd`<br/>`test/gut/test_bullet_configuration.gd`<br/>`test/gut/test_weapon_resource.gd`<br/>`test/gut/test_hud.gd` |
| Review follow-up tests.     | <ul><li>11 cases from CodeRabbit (`18bb313`); 4 adjusted.</li></ul>                                                                | `test/gut/test_weapon_resource.gd`<br/>`test/gut/test_hud.gd`<br/>`test/gut/test_bullet_resource.gd`<br/>`test/gut/test_bullet_configuration.gd`<br/>`test/gut/test_audio_sfx_centralization.gd` |
| Milestone note.             | <ul><li>This note.</li></ul>                                                                                                       | `files/docs/milestones/27/Part_17_Clean_up_AudioConstants_&_reduce_small_resource_loading_and_copy_costs.md`                                     |

### Assessment against linked issues

| Issue                                                   | Objective                                                         | Addressed | Explanation                                                                                  |
|---------------------------------------------------------|-------------------------------------------------------------------|-----------|----------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1149> | `AudioConstants` is a `class_name` script, not an autoload        | ✅         | Autoload setting and `/root` node checked.                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1149> | The check sound has one constant and one map entry                | ✅         | Map entry, file, and one-ID-per-file checks.                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1149> | Rotor bus names come from `AudioConstants`                        | ✅         | Player scene test checks both buses.                                                         |
| <https://github.com/ikostan/SkyLockAssault/issues/1149> | Sounds and volume behavior are unchanged                          | ⏳         | GUT audio suites and Playwright pass; itch.io check after deploy.                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1150> | `bullet_resource.gd` no longer preloads assets                    | ✅         | Null-default and no-preload checks.                                                          |
| <https://github.com/ikostan/SkyLockAssault/issues/1150> | `default_bullet.tres` assigns the texture and sound directly      | ✅         | `.tres` content and loaded paths checked.                                                    |
| <https://github.com/ikostan/SkyLockAssault/issues/1150> | Reading one weapon name doesn't copy the list                     | ✅         | `get_weapon_name()` reads `_weapons`; engine probe confirms why the backing array is needed. |
| <https://github.com/ikostan/SkyLockAssault/issues/1150> | The shipped game looks and sounds the same                        | ⏳         | Default firer test through `fire()` and Playwright pass; itch.io check after deploy.         |
| Both                                                    | All GUT, gdUnit4, Playwright and lint jobs pass, no cases removed | ✅         | All pass on the PR run (`41aae08`); no test cases removed.                                   |
| Both                                                    | The PR's milestone note is added                                  | ✅         | This note.                                                                                   |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1149 and #1150 and set their scope.
- Asked to finish both remaining #617 tasks in one last PR to close the epic.
- Created the `architect-review-region-2` branch and PR #1206, and applied the changes in four commits: `d4ccced`, `fc7ce88` (tests and this note), `efa6d9a` (production changes), `41aae08` (restored the `default_bullet.tres` asset lines and the `SFX_CHECK` call, and the `fire()` test fix).
- Committed the PR results and review follow-up in `e52e5e0`.
- Took the Sourcery and CodeRabbit review through to resolution, and updated #1150's Additional Context to record why this PR lands before #1139 and #1141.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Planning**
    - Flagged that #1150 asked to land after #1139 and #1141, which are still open, and checked that their changes don't overlap this PR's production files.
    - Found that `get_weapon_name()` needs a backing array, because Godot 4 runs the getter for reads inside the class.
  - **Implementation**
    - Wrote the production and test changes for #1149 and #1150, and the README autoload line fix.
  - **Verification**
    - Ran GUT, gdUnit4, `gdformat` and `gdlint` locally with the CI commands, on `main` and on the branch, and mutation-tested the new tests.
    - Probed the getter behavior on Godot 4.7.1.
    - Wrote this note.
  - **Review follow-up**
    - Found that `efa6d9a` dropped the two asset lines from `default_bullet.tres` (bullets would ship without sprite or sound) and the `SFX_CHECK` call in `advanced_settings.gd`.
    - Rewrote the default-firer test to go through `fire()` (Sourcery) and confirmed it fails when either call is removed.
    - Checked the remaining Sourcery and CodeRabbit comments against the branch head: the ones made on `fc7ce88` were already fixed by `efa6d9a`/`41aae08`; the `"None"` collision and the landing-order comments were answered with reasons.
    - Updated #1150's Additional Context line.
    - Reviewed CodeRabbit's `18bb313` tests, checked the backing-array test with a `static` mutation, and fixed four of them: null checks in the packing test (now fails on restored script defaults), an accurate comment on the fresh-resource firing test, a correct message on the HUD rewiring assertion, and constants instead of a hard-coded path in the check-sound test. Ran the full GUT suite (991/991).
- **@coderabbitai**
  - Reviewed the PR and added 11 regression tests in `18bb313` (weapon lookups and list edge cases, HUD initial sync, optional bullet assets, check sound on the menu bus).
  