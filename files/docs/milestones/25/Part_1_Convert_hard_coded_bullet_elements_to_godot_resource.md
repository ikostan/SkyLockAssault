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

### File-Level Changes

| Change                                                                                                            | Details                                                                                                                                                                                                                                                                                                                                                                                                                                      | Files                                                                                                                                                                                                                                                                                                 |
|-------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Replace inline projectile tuning with reusable, inspector-configurable BulletResource assets and shared defaults. | <ul><li>Introduce exported resource fields for firing, movement, damage, visuals, collision, and audio.</li><li>Load a shared default resource when scenes omit custom configuration.</li><li>Apply resource values to projectile spawning, collision, lifetime, and sound playback while preserving scene-level overrides.</li></ul>                                                                                                        | `scripts/resources/bullet_resource.gd`<br/>`scripts/resources/bullet_resource.gd.uid`<br/>`config_resources/default_bullet.tres`<br/>`scripts/entities/bullet.gd`<br/>`scenes/bullet.tscn`                                                                                                            |
| Strengthen weapon integration with configured and legacy weapon scenes.                                           | <ul><li>Synchronize fire-rate and damage from configured bullets or legacy node properties into the shared weapon resource.</li><li>Preserve existing shared values when optional legacy stats are absent and rely on resource bounds for imported values.</li><li>Emit remaining ammunition after each successful shot for HUD and bot consumers.</li></ul>                                                                                 | `scripts/entities/weapon.gd`                                                                                                                                                                                                                                                                          |
| Expand automated coverage for resource behavior, projectile configuration, and weapon state.                      | <ul><li>Add GUT coverage for defaults, scene packing, per-instance isolation, projectile properties, cooldowns, collisions, lifetimes, audio, and silent firing.</li><li>Add weapon tests for ammo accounting, firing signals, failed/empty shots, weapon switching, fallback compatibility, and configured bullet synchronization.</li><li>Update GdUnit collision coverage to validate configured damage and projectile cleanup.</li></ul> | `test/gdunit4/test_bullet.gd`<br/>`test/gut/test_bullet_configuration.gd`<br/>`test/gut/test_bullet_configuration.gd.uid`<br/>`test/gut/test_bullet_resource.gd`<br/>`test/gut/test_bullet_resource.gd.uid`<br/>`test/gut/test_weapon_firing_state.gd`<br/>`test/gut/test_weapon_firing_state.gd.uid` |
| Add milestone documentation for the resource conversion.                                                          | <ul><li>Add the milestone document placeholder for converting hard-coded bullet elements to a Godot resource.</li></ul>                                                                                                                                                                                                                                                                                                                      | `files/docs/milestones/25/Part_1_Convert_hard_coded_bullet_elements_to_godot_resource.md`                                                                                                                                                                                                             |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                        | Addressed | Explanation |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/283 | Replace hard-coded bullet and weapon projectile statistics with a reusable BulletResource and provide a shared default .tres configuration.                                                                                                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/283 | Inject BulletResource configurations into bullet scenes and ensure firing, projectile movement, lifetime, damage, visuals, collision, muzzle offset, and audio use the selected resource while preserving defaults and per-weapon customization. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/283 | Integrate resource-backed weapon state by synchronizing active weapon statistics during switching and emitting firing/ammunition updates for decoupled HUD and bot consumers.                                                                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/284 | Create a reusable Godot BulletResource and default resource containing configurable bullet values such as scale, collision radius, speed, lifetime, damage, visuals, sound, and firing rate.                                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/284 | Replace hard-coded bullet behavior in bullet.gd with values read from the selected BulletResource, while retaining sensible defaults and supporting per-weapon customization.                                                                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/284 | Integrate the bullet configuration with weapon firing and scene instantiation so configured bullets can be used by weapons without breaking legacy behavior.                                                                                     | ✅        |             |

### Possibly linked issues

- **#284**: The PR directly implements the issue by moving bullet constants into BulletResource and applying configurable resource values.
- **#284**: The PR directly implements the issue’s proposed modular bullet resources and weapon integration, including configurable stats and reactive firing updates.

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
