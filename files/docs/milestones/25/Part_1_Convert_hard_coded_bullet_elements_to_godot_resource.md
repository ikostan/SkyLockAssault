<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Convert hard coded bullet elements to godot resource

---

## Summary – PR #982: Convert hard-coded bullet elements to Godot resource

**Author:** @ikostan  
**Milestone:** 25 – Resource Migration & Audio Decoupling  
**Linked issues:** #283, #284  
**Labels:** `enhancement`, `refactoring`

### What this PR does

Replaces hard-coded bullet/projectile settings with a reusable, inspector-configurable `BulletResource`. This makes weapon tuning data-driven, editor-friendly, and easier to customize per weapon while preserving backward compatibility.

### Key changes

**New features**

- Introduced `BulletResource` (`scripts/resources/bullet_resource.gd`) with exported fields for:
  - Fire rate, muzzle offset, projectile speed & lifetime
  - Damage, scale, collision radius
  - Projectile texture and shot sound
- Added shared default configuration (`config_resources/default_bullet.tres`)
- Bullet node now reads all behavior from the injected resource (with runtime fallback to the default)
- Weapon now emits a `weapon_fired(ammo_remaining)` signal so HUD and bots can react without tight coupling
- Weapon switching synchronizes fire-rate and damage from the active bullet’s config (or legacy properties) into the shared `WeaponResource`

**Bug fixes / compatibility**

- Ensures correct stats are applied when switching between resource-configured and legacy weapon scenes
- Projectile collisions, lifetimes, and firing behavior correctly use the selected configuration

**Tests**

- Comprehensive GUT coverage for bullet resource defaults, isolation, projectile properties, cooldowns, collisions, lifetimes, audio, and silent firing
- Weapon firing-state tests (ammo accounting, signals, empty shots, switching, fallback compatibility)
- Updated GdUnit collision tests to validate configured damage and projectile cleanup

**Documentation**

- Added milestone document:  
  `files/docs/milestones/25/Part_1_Convert_hard_coded_bullet_elements_to_godot_resource.md`

### Files touched (high level)
| Area       | Files                                                                                                      |
|------------|------------------------------------------------------------------------------------------------------------|
| Resource   | `bullet_resource.gd`, `default_bullet.tres`                                                                |
| Core logic | `bullet.gd`, `weapon.gd`, `bullet.tscn`                                                                    |
| Tests      | `test_bullet.gd`, `test_bullet_configuration.gd`, `test_bullet_resource.gd`, `test_weapon_firing_state.gd` |
| Docs       | Milestone 25 Part 1 markdown                                                                               |

### Review & quality tooling

- **@sourcery-ai** – PR summary + Reviewer’s Guide (with sequence diagrams)
- **@coderabbitai** – PR summary + reviews + test-generation commits
- **@deepsource-io** – Static analysis / PR Report Card
- **@codecov** – Patch coverage ~80 %, project coverage ~63.7 %

### Status

Ready for review. All linked feature objectives (#283 / #284) are addressed.

---

## Reviewer's Guide

This PR centralizes bullet behavior in reusable Godot resources with shared defaults and per-weapon overrides, updates weapon switching and firing-state signaling for compatibility with the new configuration model, and adds broad automated coverage for projectile behavior, persistence, and ammunition state.

This PR converts projectile behavior from inline constants to reusable Godot resources with shared defaults and per-weapon overrides, updates weapon switching and ammunition signaling for both new and legacy scenes, adds broad behavior and compatibility tests, and makes CI path-aware.

### File-Level Changes

| Change                                                                                                                 | Details                                                                                                                                                                                                                                                                                                                                                                                             | Files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
|------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Replace hard-coded projectile tuning with reusable Godot resource configuration and shared defaults.                   | <ul><li>Add exported bullet fields for firing, movement, damage, visuals, collision, and audio.</li><li>Load the default resource when a scene has no custom configuration.</li><li>Apply configured values when spawning, moving, colliding, rendering, playing audio, and expiring projectiles.</li></ul>                                                                                         | `scripts/resources/bullet_resource.gd`<br/>`scripts/resources/bullet_resource.gd.uid`<br/>`config_resources/default_bullet.tres`<br/>`scripts/entities/bullet.gd`<br/>`scenes/bullet.tscn`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Integrate resource-backed bullet settings with weapon switching and firing state while retaining legacy compatibility. | <ul><li>Synchronize fire-rate and damage from configured bullets or legacy weapon properties into the shared weapon resource.</li><li>Preserve existing shared statistics when legacy scenes omit optional properties and apply resource bounds to imported values.</li><li>Emit the remaining ammunition after each successful shot.</li></ul>                                                     | `scripts/entities/weapon.gd`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Expand automated coverage around configurable projectiles and weapon behavior.                                         | <ul><li>Test resource defaults, scene packing, isolation, projectile configuration, cooldowns, collisions, lifetimes, audio, and silent firing.</li><li>Test ammunition accounting, firing signals, failed and empty shots, switching, fallback compatibility, and configured-stat synchronization.</li><li>Update collision coverage to verify configured damage and projectile cleanup.</li></ul> | `test/gdunit4/test_bullet.gd`<br/>`test/gut/test_bullet_configuration.gd`<br/>`test/gut/test_bullet_configuration.gd.uid`<br/>`test/gut/test_bullet_resource.gd`<br/>`test/gut/test_bullet_resource.gd.uid`<br/>`test/gut/test_weapon_firing_state.gd`<br/>`test/gut/test_weapon_firing_state.gd.uid`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Make pull-request CI conditional on relevant file changes.                                                             | <ul><li>Add changed-path detection for GDScript, Markdown, YAML, and CI files.</li><li>Gate linting, unit tests, browser tests, and CI-script tests using the detected paths and upstream job results.</li></ul>                                                                                                                                                                                    | `.github/workflows/lint_test_on_pull.yml`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Document the bullet resource migration and update licensing headers.                                                   | <ul><li>Add milestone documentation describing the resource conversion, compatibility behavior, tests, and affected files.</li><li>Update or add copyright and SPDX headers across touched scripts.</li></ul>                                                                                                                                                                                       | `files/docs/milestones/25/Part_1_Convert_hard_coded_bullet_elements_to_godot_resource.md`<br/>`scripts/core/game_paths.gd`<br/>`scripts/core/globals.gd`<br/>`scripts/core/main_scene.gd`<br/>`scripts/core/settings.gd`<br/>`scripts/entities/player.gd`<br/>`scripts/managers/audio_manager.gd`<br/>`scripts/managers/parallax_manager.gd`<br/>`scripts/managers/resource_preloader.gd`<br/>`scripts/managers/ui_manager.gd`<br/>`scripts/resources/audio_constants.gd`<br/>`scripts/resources/fuel_resource.gd`<br/>`scripts/resources/game_settings_resource.gd`<br/>`scripts/resources/speed_resource.gd`<br/>`scripts/resources/weapon_resource.gd`<br/>`scripts/system/JavaScriptBridgeWrapper.gd`<br/>`scripts/system/OSWrapper.gd`<br/>`scripts/system/audio_web_bridge.gd`<br/>`scripts/ui/components/fps_counter.gd`<br/>`scripts/ui/components/input_remap_button.gd`<br/>`scripts/ui/components/volume_slider.gd`<br/>`scripts/ui/menus/advanced_settings.gd`<br/>`scripts/ui/menus/audio_settings.gd`<br/>`scripts/ui/menus/gameplay_settings.gd`<br/>`scripts/ui/menus/key_mapping.gd`<br/>`scripts/ui/menus/main_menu.gd`<br/>`scripts/ui/menus/options_menu.gd`<br/>`scripts/ui/menus/pause_menu.gd`<br/>`scripts/ui/screens/loading_screen.gd`<br/>`scripts/ui/screens/splash_screen.gd` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                 | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/283 | Replace hard-coded projectile and weapon-related bullet values with a reusable BulletResource and provide a shared default .tres configuration containing firing, damage, movement, lifetime, muzzle, visual, collision, and audio settings.              | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/283 | Inject BulletResource configurations into bullet scenes and make projectile firing, movement, collision damage, lifetime, visuals, muzzle offset, cooldown, and audio use the selected resource while retaining shared defaults and legacy compatibility. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/283 | Integrate resource-backed bullet statistics with weapon switching and expose decoupled firing/ammunition state through weapon_fired, while preserving WeaponResource-driven weapon-swapped and ammo-updated behavior.                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/284 | Create a reusable Godot bullet resource and default .tres configuration containing configurable values such as scale, collision radius, speed, lifetime, firing rate, damage, visuals, and sound.                                                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/284 | Replace hard-coded bullet behavior in bullet.gd with values from the selected resource, including projectile scale, collision radius, speed, lifetime, damage, visuals, audio, and firing cooldown, while retaining defaults.                             | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/284 | Integrate the resource-backed bullet configuration with weapon firing and scene instantiation so different weapons can use customized bullet settings without breaking legacy behavior.                                                                   | ✅        |             |

### Possibly linked issues

- **#284**: The PR directly implements the issue by introducing BulletResource, default .tres configuration, configurable projectile behavior, and weapon integration.
- **#283**: The PR directly implements the issue’s resource-driven bullet conversion and weapon integration, including configurable stats and firing signals.

---

## Bot & AI Contributions to PR #982

This pull request includes contributions and automated assistance from several bots and AI tools that supported code review, testing, coverage reporting, and quality analysis.

### @coderabbitai

- Generated the **Summary by CodeRabbit** section in the PR description, highlighting new features (configurable bullet resources, default fallbacks, ammo reporting) and bug fixes (weapon switch synchronization).
- Performed AI-powered code reviews with no actionable comments in the latest run (CHILL profile, Advanced plan).
- Authored commit `dd8a5b6` (“Add tests for bullet resource configuration and weapon firing state; update projectile collision coverage”).
- Co-authored commit `961ef28` (test updates).
- Initiated coding-agent unit-test generation tasks and provided finishing-touch suggestions.

### @sourcery-ai

- Generated the **Summary by Sourcery** in the PR body, covering new features, bug fixes, enhancements, documentation, and tests.
- Produced the detailed **Reviewer’s Guide**, including sequence diagrams for resource-driven projectile firing and weapon switching/firing state.
- Performed code review, identifying issues such as potential synchronization gaps for `fire_rate`/`damage` when using the new `BulletResource` configuration.
- Provided interactive review tips and commands for further Sourcery actions.

### @deepsource-io

- Ran **DeepSource Code Review** on the changes (commits `1344fa5`…`468fe59`).
- Delivered a PR Report Card covering Security, Reliability, Complexity, and Hygiene.
- Provided language-specific analysis links (Python/JavaScript) and a full review summary on the DeepSource dashboard.

### @codecov

- Posted the **Codecov Report** comment.
- Reported patch coverage of 80.00% (4 lines missing coverage) and overall project coverage of 63.70%.
- Confirmed all tests successful with no failed tests.
- Compared base (`1344fa5`) to head (`468fe59`).

### @dependabot

- Standard dependency-management bot integration present in the repository workflow (no direct commits or comments observed on this specific PR, but included for complete contributor recognition as requested).

---

## Human Contributor

### @ikostan

- Primary author and owner of the PR.
- Authored the majority of commits, including the core refactor (`Refactor bullets to use resource config`), weapon ammo HUD signal exposure, resource isolation/preloading improvements, test additions, documentation, and iterative fixes.
- Self-assigned the PR, added labels (`enhancement`, `refactoring`), linked related issues (#283, #284), added the PR to Milestone 25 and the project board.
- Actively responded to and incorporated feedback from the above bots/AI tools.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
