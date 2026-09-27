<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Add web telemetry adapter for fuel sync- #985

---



---

## Reviewer's Guide

The PR extracts browser fuel telemetry from the hot global settings path into a dedicated, web-only adapter. The adapter observes the player’s fuel resource, initializes and updates `window.currentFuel` through the JavaScript bridge, skips redundant writes, and tears down safely while native builds avoid the adapter’s runtime overhead.

### File-Level Changes

| Change                                                                                                                                                    | Details                                                                                                                                                                                                                                                                         | Files                                                                                       |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Moves browser fuel synchronization into a dedicated telemetry node that observes the fuel resource and updates browser state only when the value changes. | <ul><li>Adds a web-only adapter with lifecycle-safe resource binding and teardown.</li><li>Primes and updates `window.currentFuel` through the JavaScript bridge while suppressing duplicate values.</li><li>Self-removes on native builds to avoid runtime overhead.</li></ul> | `scripts/system/web_telemetry_adapter.gd`<br/>`scripts/system/web_telemetry_adapter.gd.uid` |
| Integrates the telemetry adapter into the main scene and supplies the player’s fuel resource.                                                             | <ul><li>Instantiates and adds the adapter during scene initialization so its web-platform guard runs.</li><li>Binds the adapter to `player.fuel_resource` after the scene is ready.</li></ul>                                                                                   | `scripts/core/main_scene.gd`                                                                |
| Removes high-frequency fuel handling from the global settings-change path.                                                                                | <ul><li>Deletes direct browser fuel updates and debug-only fuel logging from the global settings handler.</li><li>Leaves regular setting handling responsible for non-fuel settings.</li></ul>                                                                                  | `scripts/core/globals.gd`                                                                   |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                      | Addressed | Explanation                                                                                                                                                                                                                                                                                                                                    |
|------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| https://github.com/ikostan/SkyLockAssault/issues/472 | Move Fuel, Speed, and Weapons state changes into Resource-backed signals with setters that emit updates independently of Player or Level scripts.                                                              | ❌        | The PR does not add or modify the Fuel, Speed, or Weapons resources, their signals, or setter-based emission logic. The adapter assumes that FuelResource already exposes a compatible fuel_changed signal but does not implement that part of the refactor.                                                                                   |
| https://github.com/ikostan/SkyLockAssault/issues/472 | Make the HUD and environment observe resource signals directly, so they render or react to telemetry without depending on the Player node or direct polling.                                                   | ❌        | The changes only add a web telemetry observer for FuelResource. No HUD or parallax/environment wiring is updated, and the requested resource injection into those systems is not implemented.                                                                                                                                                  |
| https://github.com/ikostan/SkyLockAssault/issues/472 | Complete external web telemetry wiring and validate the resource-signal behavior with independent unit tests.                                                                                                  | ❌        | The PR does implement a web-only FuelResource observer that updates window.currentFuel and removes the old global settings-path synchronization. However, it adds no GUT tests for signal emission or telemetry behavior, and it does not cover the full Fuel, Speed, and Weapons resource refactor, so this objective is not fully addressed. |
| https://github.com/ikostan/SkyLockAssault/issues/955 | Remove high-frequency fuel telemetry handling from globals.gd and keep the fuel data layer platform-agnostic.                                                                                                  | ✅        |                                                                                                                                                                                                                                                                                                                                                |
| https://github.com/ikostan/SkyLockAssault/issues/955 | Introduce a dedicated WebTelemetryAdapter that observes FuelResource.fuel_changed, publishes the effective fuel value to window.currentFuel, avoids redundant updates, and safely disconnects during teardown. | ✅        |                                                                                                                                                                                                                                                                                                                                                |
| https://github.com/ikostan/SkyLockAssault/issues/955 | Preserve the existing window.currentFuel contract required by the Playwright fuel depletion test while avoiding telemetry overhead on native builds.                                                           | ✅        |                                                                                                                                                                                                                                                                                                                                                |

### Possibly linked issues

- **#472**: The PR directly implements the issue’s requested adapter, globals cleanup, deduplication, lifecycle handling, and window.currentFuel synchronization.

---



---



<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
