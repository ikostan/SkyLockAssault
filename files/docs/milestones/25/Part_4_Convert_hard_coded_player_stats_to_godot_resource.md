<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

# Convert hard coded player stats to godot resource

Move player movement-boundary configuration into a reusable Godot resource and establish coverage for gameplay settings exit behavior.

---



---

## Reviewer's Guide

The PR externalizes player boundary-tuning values into a configurable Godot Resource with serialized defaults and optional per-player overrides, while also adding unrelated GUT characterization coverage for gameplay settings exit paths.

### File-Level Changes

| Change                                                                                                     | Details                                                                                                                                                                                                                                                                                                                                                                                | Files                                                                                                                                                                               |
|------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Introduces a reusable Godot resource for player movement-tuning values and wires the player to consume it. | <ul><li>Adds the `PlayerStatsResource` class with exported hitbox scale and fallback sprite size properties.</li><li>Adds serialized default stats in `default_player_stats.tres`.</li><li>Adds an exported player stats override with fallback to the shipped defaults.</li><li>Replaces hard-coded boundary constants and fallback dimensions with resource-backed values.</li></ul> | `scripts/resources/player_stats_resource.gd`<br/>`scripts/resources/player_stats_resource.gd.uid`<br/>`config_resources/default_player_stats.tres`<br/>`scripts/entities/player.gd` |
| Adds characterization tests for gameplay settings menu exit and cleanup behavior.                          | <ul><li>Covers desktop and web Back-button stack restoration and overlay cleanup.</li><li>Covers unexpected removal behavior with and without a previous menu.</li><li>Documents current non-web and non-idempotent cleanup behavior for future refactoring.</li></ul>                                                                                                                 | `test/gut/test_gameplay_settings_exit_paths.gd`<br/>`test/gut/test_gameplay_settings_exit_paths.gd.uid`                                                                             |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                            | Addressed | Explanation                                                                                                                                                                                                                    |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| https://github.com/ikostan/SkyLockAssault/issues/286 | Create a PlayerStatsResource and default resource containing the existing hitbox scale and fallback sprite size defaults.                                                            | ✅        |                                                                                                                                                                                                                                |
| https://github.com/ikostan/SkyLockAssault/issues/286 | Update player.gd to use the configurable resource values for movement bounds and fallback sprite sizing, while preserving texture precedence and providing a null-resource fallback. | ✅        |                                                                                                                                                                                                                                |
| https://github.com/ikostan/SkyLockAssault/issues/286 | Add dedicated GUT tests covering default stats, custom stats, null fallback behavior, texture-less sprites, and resource default values.                                             | ❌        | The PR does not add the requested test/gut/test_player_stats_resource.gd tests. It adds an unrelated gameplay settings exit-path test instead, so the new player stats behavior is not directly covered by the required tests. |

### Possibly linked issues

- **#[FEATURE]**: PR directly implements the issue's core resource conversion and configurable player bounds behavior, despite missing requested tests and unrelated changes.

---



---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
