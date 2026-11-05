<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Environment parallax refactor

---

## PR #980 Summary: Environment parallax refactor

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `environment-parallax-refactor` → `main`  
**Linked Issues:** #975 ([CHORE] Documentation and residual cleanup), #954 (Phase 3: Environment & Parallax Refactor), #974 (main_scene inject resources into ParallaxManager)  
**Milestone:** Milestone 24 – Resource-Driven Data Refactoring & Player Stat Architecture  
**Labels:** enhancement, testing, refactoring, QA

### Purpose

Close out Phase 3 parallax work by documenting the dependency-injected observer architecture, confirming legacy Player→Parallax signal coupling is gone, and locking that invariant with a regression test—without reintroducing stale update paths.

### Core Improvements

#### 1. Development guide (`files/docs/Development_Guide.md`)

- Document resource-driven parallax: ownership of **SpeedResource**, **FuelResource**, and **GameSettingsResource**
- Describe injection via `ParallaxManager.setup(...)` and signal-based observation
- Include a `main_scene.gd` composition-root wiring example
- Clean up duplicate top-down movement heading/intro and table spacing

#### 2. Legacy coupling cleanup

- Annotate `main_scene.gd` / `parallax_manager.gd` as free of legacy player-signal coupling and compatibility shims
- Explicit comments that parallax no longer listens to Player `speed_changed` / `fuel_depleted`

#### 3. Regression tests (`test/gut/test_main_scene_parallax_and_performance.gd`)

- Assert `speed_changed` and `fuel_depleted` connections do **not** target `ParallaxManager` when those signals exist
- Guard against null background / missing `ParallaxManager` script so the check cannot pass vacuously
- Preserve existing parallax/performance coverage alongside the new invariant

### Benefits

- Developers have a clear map of who owns parallax inputs and how they are wired
- Prevents silent reintroduction of Player→background signal paths after the #976 observer refactor
- Phase 3 documentation and verification align with the Milestone 24 resource architecture

### Status Notes

Addresses #954 / #975 documentation and legacy-signal regression goals. Sourcery noted that #974’s *implementation* of `setup()` injection was largely delivered in prior work (#976); this PR focuses on docs, residual cleanup annotations, and verification rather than new composition-root wiring.

---

## Reviewer's Guide

Finalizes the environment parallax refactor by documenting its dependency-injected, resource-observer architecture, recording the removal of legacy Player signal coupling, and adding regression coverage that verifies those signals are not connected to `ParallaxManager`.

### File-Level Changes

| Change                                                                                        | Details                                                                                                                                                                                                                                                            | Files                                                                   |
|-----------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------|
| Document the resource-driven, dependency-injected observer architecture for parallax updates. | <ul><li>Describe ownership of speed, fuel, and settings resources.</li><li>Explain `main_scene.gd` injection through `ParallaxManager.setup()` and resource-signal observation.</li><li>Add a scene-wiring example and clean up nearby guide formatting.</li></ul> | `files/docs/Development_Guide.md`                                       |
| Record that legacy Player-to-ParallaxManager coupling and compatibility shims are removed.    | <ul><li>Add explicit documentation comments stating that parallax no longer depends on legacy player signals.</li></ul>                                                                                                                                            | `scripts/core/main_scene.gd`<br/>`scripts/managers/parallax_manager.gd` |
| Add regression coverage for the absence of legacy player signal connections.                  | <ul><li>Validate the background exists and is a `ParallaxManager`.</li><li>Inspect any `speed_changed` and `fuel_depleted` connections and assert they do not target the parallax manager.</li></ul>                                                               | `test/gut/test_main_scene_parallax_and_performance.gd`                  |
| Capture the refactor’s implementation and verification history in milestone documentation.    | <ul><li>Summarize the architecture, cleanup, regression coverage, linked issues, and review context.</li></ul>                                                                                                                                                     | `files/docs/milestones/24/Part_6_Environment_parallax_refactor.md`      |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                        | Addressed | Explanation |
|------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/954 | Update project documentation to describe the resource-driven Observer architecture, dependency ownership, dependency injection through ParallaxManager.setup(), and main_scene.gd composition-root wiring.       | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/954 | Finalize removal of legacy Player-to-ParallaxManager coupling and compatibility-shim references so ParallaxManager no longer depends on Player physics signals.                                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/954 | Add regression coverage confirming that legacy speed_changed and fuel_depleted signals are not connected to the ParallaxManager while preserving existing parallax test coverage.                                | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/974 | Document the resource-driven dependency-injection architecture, including how main_scene.gd passes the authoritative SpeedResource, FuelResource, and GameSettingsResource instances to ParallaxManager.setup(). | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/974 | Ensure ParallaxManager is no longer coupled to legacy Player speed and fuel signals and relies on resource-based observation instead.                                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/974 | Add regression coverage that verifies no legacy Player-to-ParallaxManager signal connections remain in the main scene.                                                                                           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/975 | Update the project documentation to describe the resource-driven Observer architecture, dependency-injection flow, and ownership/data flow between the gameplay resources, main_scene.gd, and ParallaxManager.   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/975 | Finalize regression coverage confirming that legacy Player speed_changed and fuel_depleted signals are no longer connected to ParallaxManager, while ensuring the background node is valid.                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/975 | Complete residual cleanup and close out the refactored parallax architecture without legacy Player-to-ParallaxManager compatibility coupling.                                                                    | ✅        |             |

### Possibly linked issues

- **#472**: PR directly completes the issue’s Phase 3 closure goals: documentation, legacy coupling cleanup, and regression tests.
- **#2**: The PR documents and verifies the exact resource-injection and legacy-coupling removal objectives described by the issue.
- **#975**: The PR directly implements issue #975’s documentation updates and regression coverage for legacy signal removal.

---

## PR #980 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (including feedback that the legacy-signal regression test should assert the background/`ParallaxManager` node is non-null before connection checks).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the parallax documentation and regression-test changes (minimal merge risk).

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **63.82%** vs base; all modified coverable lines covered; all tests successful).

> **Note:** **@dependabot** did not author commits or leave reviews on this PR (no dependency-bump activity observed).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Documented the dependency-injected, observer-based parallax architecture in `Development_Guide.md` (resource ownership, `ParallaxManager.setup()` wiring, main-scene composition); annotated/removed residual legacy player-to-parallax coupling notes; added GUT regression coverage that `speed_changed` / `fuel_depleted` are not connected to `ParallaxManager`; and guarded null background in the parallax test—under Milestone 24 Phase 3 (#954 / #975, related #974).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
