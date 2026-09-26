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

Refactors parallax integration around dependency injection and resource observers, removing legacy player-signal coupling; updates the development guide with the new wiring model and adds a regression test for disconnected legacy signals.

### File-Level Changes

| Change                                                                                                   | Details                                                                                                                                                                                                              | Files                                                                   |
|----------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------|
| Document the dependency-injected, observer-based parallax architecture and its scene-composition wiring. | <ul><li>Describe resource ownership, injection through `ParallaxManager.setup()`, and signal-based observation.</li><li>Add a `main_scene.gd` wiring example and clarify related documentation formatting.</li></ul> | `files/docs/Development_Guide.md`                                       |
| Explicitly remove and document the legacy player-to-parallax signal coupling.                            | <ul><li>Annotate the main scene and parallax manager as free of legacy coupling and compatibility shims.</li></ul>                                                                                                   | `scripts/core/main_scene.gd`<br/>`scripts/managers/parallax_manager.gd` |
| Add regression coverage ensuring parallax no longer listens to legacy player signals.                    | <ul><li>Inspect `speed_changed` and `fuel_depleted` connections and assert neither targets `ParallaxManager`.</li></ul>                                                                                              | `test/gut/test_main_scene_parallax_and_performance.gd`                  |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                         | Addressed | Explanation                                                                                                                                                                                                                                                                              |
|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| https://github.com/ikostan/SkyLockAssault/issues/954 | Update Development_Guide.md to document the resource-driven, dependency-injected Observer architecture for ParallaxManager, including the main_scene.gd wiring flow.                              | ✅        |                                                                                                                                                                                                                                                                                          |
| https://github.com/ikostan/SkyLockAssault/issues/954 | Finalize regression coverage verifying that legacy Player-to-Parallax signal coupling has been removed.                                                                                           | ✅        |                                                                                                                                                                                                                                                                                          |
| https://github.com/ikostan/SkyLockAssault/issues/954 | Complete the Phase 3 closure documentation and cleanup associated with the decoupled environment/parallax architecture.                                                                           | ✅        |                                                                                                                                                                                                                                                                                          |
| https://github.com/ikostan/SkyLockAssault/issues/974 | Document the dependency-injected, observer-based ParallaxManager architecture and its composition-root wiring.                                                                                    | ✅        |                                                                                                                                                                                                                                                                                          |
| https://github.com/ikostan/SkyLockAssault/issues/974 | Add regression coverage confirming that legacy Player-to-ParallaxManager speed and fuel signal connections have been removed.                                                                     | ✅        |                                                                                                                                                                                                                                                                                          |
| https://github.com/ikostan/SkyLockAssault/issues/975 | Update project documentation to describe the resource-driven observer pattern, dependency-injection flow, and ownership/data flow between gameplay resources, main_scene.gd, and ParallaxManager. | ✅        |                                                                                                                                                                                                                                                                                          |
| https://github.com/ikostan/SkyLockAssault/issues/975 | Preserve and verify the existing behavior and regression coverage after the cleanup, including validation that ParallaxManager no longer depends on legacy Player signals.                        | ✅        |                                                                                                                                                                                                                                                                                          |

### Possibly linked issues

- **#[FEATURE] Phase 3: Environment & Parallax Refactor**: The PR adds the planned Development Guide documentation and regression test for legacy signal removal, matching Phase 3 closure.
- **#2**: The PR implements the issue’s documented resource injection architecture and regression tests for disconnected legacy signals.
- **#3**: The PR documents the refactored architecture and tests removal of legacy Player-to-ParallaxManager signal coupling described by issue 3.

<!-- Generated by sourcery-ai[bot]: end review_guide -->

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
