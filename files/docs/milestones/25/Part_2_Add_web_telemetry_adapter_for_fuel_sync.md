<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Add web telemetry adapter for fuel sync- #985

---

## Summary – PR #985: Add web telemetry adapter for fuel sync

**Author:** @ikostan  
**Milestone:** 25 – Resource Migration & Audio Decoupling  
**Linked issues:** #955 (Phase 4: WebGL & Playwright E2E Synchronization), #472  
**Labels:** `enhancement`, `refactoring`, `architecture`

### What this PR does

Moves high-frequency browser fuel synchronization out of the global settings path into a dedicated, web-only `WebTelemetryAdapter`. The adapter observes the player’s `FuelResource`, publishes values to `window.currentFuel` for Playwright E2E tests, skips redundant updates, and keeps native builds free of telemetry overhead.

This change moves browser fuel synchronization out of the hot settings path and into a dedicated Web telemetry adapter. It observes the fuel resource, skips redundant updates, and exposes the browser value via window.currentFuel for Playwright E2E checks while keeping native builds free of the overhead.

### Key changes

**New features**

- Added `WebTelemetryAdapter` (`scripts/system/web_telemetry_adapter.gd`):
  - Observes `FuelResource.fuel_changed`
  - Publishes initial + changed (clamped) fuel values to `window.currentFuel`
  - Suppresses duplicate browser writes
  - Handles safe setup, rebinding, and teardown
  - Self-disables / removes itself on non-web builds
- `MainScene` creates, owns, and configures the adapter (gated by `OS.has_feature("web")`)

**Bug fixes / cleanup**

- Removed high-frequency fuel sync and special-case debug handling from `globals.gd`
- Restored normal settings persistence and logging behavior for `current_fuel`

**Tests**

- GUT coverage for:
  - Platform gating (web vs native)
  - Fuel synchronization, priming, deduplication, clamping, fractional values
  - Rebinding and teardown
  - MainScene ownership and legacy Globals behavior
- New test files:
  - `test_web_telemetry_adapter.gd`
  - `test_main_scene_web_telemetry.gd`
  - `test_globals_fuel_telemetry.gd`

**Documentation**

- Added milestone document:  
  `files/docs/milestones/25/Part_2_Add_web_telemetry_adapter_for_fuel_sync.md`

### Files touched (high level)
| Area        | Files                                                                                                          |
|-------------|----------------------------------------------------------------------------------------------------------------|
| Adapter     | `web_telemetry_adapter.gd` (+ UID)                                                                             |
| Integration | `main_scene.gd`, `globals.gd`                                                                                  |
| Tests       | `test_web_telemetry_adapter.gd`, `test_main_scene_web_telemetry.gd`, `test_globals_fuel_telemetry.gd` (+ UIDs) |
| Docs        | Milestone 25 Part 2 markdown                                                                                   |

### Review & quality tooling
- **@sourcery-ai** – PR summary + Reviewer’s Guide (with sequence diagram)
- **@coderabbitai** – PR summary + reviews + regression-test commit
- **@deepsource-io** – Static analysis / PR Report Card
- **@codecov** – 100% coverage of modified lines; project coverage 63.74%

### Status

Implements Phase 4 of the signal-decoupling work. All linked objectives for #955 are addressed. Ready for review.

---

## Reviewer's Guide

The PR extracts high-frequency browser fuel synchronization from Globals into a dedicated WebTelemetryAdapter, wires it to the player’s FuelResource from MainScene, avoids redundant JavaScript updates, cleans up safely across lifecycle and platform boundaries, and adds focused unit and scene coverage.

### File-Level Changes

| Change                                                                    | Details                                                                                                                                                                                                                                   | Files                                                                                                                                                                                                                                                                                         |
|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Moves browser fuel synchronization into a dedicated web-only observer.    | <ul><li>Adds lifecycle-safe FuelResource binding and teardown.</li><li>Publishes the initial and changed fuel values through window.currentFuel.</li><li>Suppresses duplicate browser writes and self-removes on native builds.</li></ul> | `scripts/system/web_telemetry_adapter.gd`<br/>`scripts/system/web_telemetry_adapter.gd.uid`                                                                                                                                                                                                   |
| Integrates the adapter into scene initialization.                         | <ul><li>Creates and owns the adapter from MainScene.</li><li>Injects the player fuel resource after scene setup.</li><li>Gates resource setup on the web platform.</li></ul>                                                              | `scripts/core/main_scene.gd`                                                                                                                                                                                                                                                                  |
| Removes fuel-specific telemetry from the global settings path.            | <ul><li>Deletes direct JavaScript fuel updates and debug-only special handling.</li><li>Restores current_fuel to normal settings persistence and logging behavior.</li></ul>                                                              | `scripts/core/globals.gd`                                                                                                                                                                                                                                                                     |
| Adds regression and integration coverage for the new telemetry lifecycle. | <ul><li>Tests native platform cleanup and web binding.</li><li>Covers priming, deduplication, clamping, fractional values, rebinding, and teardown.</li><li>Verifies legacy Globals behavior and MainScene ownership.</li></ul>           | `test/gut/test_globals_fuel_telemetry.gd`<br/>`test/gut/test_globals_fuel_telemetry.gd.uid`<br/>`test/gut/test_main_scene_web_telemetry.gd`<br/>`test/gut/test_main_scene_web_telemetry.gd.uid`<br/>`test/gut/test_web_telemetry_adapter.gd`<br/>`test/gut/test_web_telemetry_adapter.gd.uid` |
| Documents the implementation and issue coverage.                          | <ul><li>Summarizes the adapter design and changed files.</li><li>Records that the broader resource-backed Fuel/Speed/Weapons refactor in issue #472 remains out of scope.</li></ul>                                                       | `files/docs/milestones/25/Part_2_Add_web_telemetry_adapter_for_fuel_sync.md`                                                                                                                                                                                                                  |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                             | Addressed | Explanation                                                                                                                                                                                                                                                      |
|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| https://github.com/ikostan/SkyLockAssault/issues/472 | Move Fuel, Speed, and Weapons state changes into Resource-backed signals with setters that emit updates independently of Player or Level scripts.                                                                                     | ✅        | **Merged in Phase 1 (PR #952).** The `FuelResource`, `SpeedResource`, and `WeaponResource` were successfully created with encapsulated setter-based emission logic.                                                                                              |
| https://github.com/ikostan/SkyLockAssault/issues/472 | Make the HUD and environment observe resource signals directly, so they render or react to telemetry without depending on the Player node or direct polling.                                                                          | ✅        | **Merged in Phase 2 (PR #953) & Phase 3 (PR #954).** The UI/HUD and ParallaxManager were successfully refactored to act as strict, passive observers via dependency injection.                                                                                   |
| https://github.com/ikostan/SkyLockAssault/issues/472 | Complete external web telemetry wiring and validate the resource-signal behavior with independent unit tests.                                                                                                                         | ✅        | **Completed in Phase 4 (Current PR #955).** The `WebTelemetryAdapter` successfully routes the signals to the browser DOM, and the extensive 19-case GUT test suite (`test_web_telemetry_adapter.gd`) fully validates the observer lifecycle and signal behavior. |
| https://github.com/ikostan/SkyLockAssault/issues/955 | Remove high-frequency current_fuel browser synchronization from globals.gd while keeping the fuel data layer platform-agnostic.                                                                                                       | ✅        |                                                                                                                                                                                                                                                                  |
| https://github.com/ikostan/SkyLockAssault/issues/955 | Introduce a dedicated WebTelemetryAdapter that observes FuelResource.fuel_changed, publishes the effective clamped fuel value to window.currentFuel, suppresses redundant updates, and safely handles setup, rebinding, and teardown. | ✅        |                                                                                                                                                                                                                                                                  |
| https://github.com/ikostan/SkyLockAssault/issues/955 | Preserve Playwright-compatible window.currentFuel behavior while avoiding telemetry overhead on native builds and validating the synchronization behavior with automated tests.                                                       | ✅        |                                                                                                                                                                                                                                                                  |

### Possibly linked issues

- **#955**: The PR directly implements the issue’s requested WebTelemetryAdapter, globals cleanup, clamped updates, deduplication, teardown, and E2E contract.

---

## Bot & AI Contributions to PR #985

This pull request received significant automated assistance from bots and AI tools for code review, test generation, coverage reporting, and static analysis.

### @coderabbitai

- Generated the **Summary by CodeRabbit** in the PR description (improvements around fuel persistence/logging and web `window.currentFuel` exposure).
- Performed AI code reviews (CHILL profile, Advanced plan) with no actionable comments in the latest run and multiple LGTM notes.
- Authored commit `0273ef2` (“Add regression tests for web fuel telemetry, scene lifecycle, and settings persistence”).
- Started coding-agent unit-test generation tasks and provided finishing-touch suggestions.

### @sourcery-ai

- Generated the **Summary by Sourcery** covering new features, bug fixes, enhancements, and tests.
- Produced the detailed **Reviewer’s Guide**, including a sequence diagram for web fuel telemetry synchronization and file-level change analysis.
- Performed code review (found issues such as lifecycle/wiring concerns on early commits).
- Co-authored commit `3d27651` (“Update scripts/core/main_scene.gd”).

### @deepsource-io

- Ran **DeepSource Code Review** on the changes (commits `14cd73c`…`37b9908`).
- Delivered a PR Report Card covering Security, Reliability, Complexity, and Hygiene.
- Provided language-specific analysis links (Python/JavaScript) and a full review summary on the DeepSource dashboard.

### @codecov

- Posted the **Codecov Report** comment.
- Confirmed **100% coverage of all modified and coverable lines**.
- Reported project coverage of **63.74%** (unchanged vs base).
- Confirmed all tests successful with no failed tests.
- Compared base (`14cd73c`) to head (`37b9908`).

### @dependabot

- Standard dependency-management bot integration present in the repository workflow (no direct commits or comments observed on this specific PR, but included for complete contributor recognition as requested).

---

## Human Contributor

### @ikostan

- Primary author and owner of the PR.
- Authored the majority of commits, including the core change (“Add web telemetry adapter for fuel sync”), adapter initialization/attachment, priming of telemetry values, type improvements, milestone documentation, GUT tests, and UID files.
- Self-assigned the PR, added labels (`enhancement`, `refactoring`, `architecture`), linked related issues (#955, #472), and added the PR to Milestone 25 and the project board.
- Actively iterated on feedback from the above bots/AI tools.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
