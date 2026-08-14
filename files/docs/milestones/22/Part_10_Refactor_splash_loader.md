# Refactor splash loader; add monotonic progress & tests- #893
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
---

## PR #893 Summary: Refactor splash loader; add monotonic progress & tests

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `implement-three-state-presentation-pipeline-in-splash_screengd` → `main`  
**Linked Issue:** #778 ([TASK] TASK-01: Implement Three-State Presentation Pipeline in splash_screen.gd)  
**Milestone:** Milestone 22 – Optimize Test Suite Runtime & Fix Loading Screen  
**Labels:** enhancement, web, GUI, frontend

### Purpose

Restructure `splash_screen.gd` into a clear three-state presentation pipeline that separates resource polling, UI progress presentation, and scene-transition routing. Deliver strictly monotonic, deterministic progress updates and harden loading/transition behavior with validation and fallbacks. Add Gut integration tests to lock in the new behavior.

Restructure `splash_screen.gd` to separate concerns: polling backend, presentation smoothing, and transition routing. Add display_target and presentation_speed; use move_toward for deterministic, linear UI progress and ensure strictly monotonic display_target updates from threaded loader progress. Improve ResourceLoader handling (match on status), validate PackedScene on load, set load_failed on errors, and provide fallbacks (DEFAULT_STARTUP_SCENE or direct file load). Add defensive checks before change_scene_to_packed and ensure transitions respect min_load_time. Add Gut integration tests (test/gut/test_splash_screen.gd + .uid) covering monotonic scaling, presentation convergence, backend early-exit, invalid-resource handling, and transition timing.

### Core Improvements

#### 1. Three-State Pipeline (`scripts/ui/screens/splash_screen.gd`)

Replaced the monolithic `_process` loop with three focused responsibilities:

| Stage                                                  | Responsibility                                                                                                                                   |
|--------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| **Backend polling** (`_poll_resource_backend`)         | Query `ResourceLoader.load_threaded_get_status`, update `display_target` monotonically via `max()`, handle `THREAD_LOAD_*` statuses              |
| **Presentation** (`_update_presentation_handler`)      | Drive `loader_progress` toward `display_target` with `move_toward(..., presentation_speed * delta)` for linear, frame-rate-independent smoothing |
| **Transition routing** (`_evaluate_transition_router`) | Gate scene change on loaded/failed state, `min_load_time` elapsed, progress ≈ 100%, and not already transitioning                                |

#### 2. Deterministic & Monotonic Progress

- New state: `display_target` and `presentation_speed`
- Backend progress only raises `display_target` (never decreases)
- UI progress uses `move_toward` instead of `lerp` for predictable linear convergence
- On load failure / invalid resource, force `display_target = 100.0` so the bar still completes and fallback routing can run

#### 3. Hardened Loading & Transitions

- Explicit `match` on ResourceLoader status values
- Validate loaded resource is a `PackedScene` before use; set `load_failed` otherwise
- Defensive checks (`is_instance_valid`, type check) before `change_scene_to_packed`
- Fallbacks:
  - Empty `next_scene` → `DEFAULT_STARTUP_SCENE`
  - Load failure / validation failure → direct `change_scene_to_file(target_path)`
- Transitions respect `min_load_time` so the splash is visible for a minimum duration

#### 4. Gut Integration Tests (`test/gut/test_splash_screen.gd`)

Coverage includes:
- Monotonic `display_target` behavior under decreasing backend progress
- Linear `move_toward` convergence tied to delta and `presentation_speed`
- Backend early-return when already loaded
- Invalid / non-PackedScene resource handling (`load_failed` + progress forced to 100)
- Transition router respects `min_load_time` even when progress is complete

### Benefits

- Clear separation of concerns makes the splash loader easier to reason about and extend
- Progress bar no longer jumps backward or stalls due to non-monotonic backend reports
- Safer scene transitions with explicit validation and fallback paths
- Automated tests protect against regressions in progress, failure handling, and timing

### Status Notes

Fully addresses the objectives of TASK-01 (#778): three-state pipeline, `move_toward` linear progress, monotonic scaling, and PackedScene validation with safe fallbacks.

---

## Reviewer's Guide

Refactors the splash screen loader into a three-stage pipeline (backend polling, presentation, and transition routing), introduces deterministic monotonic progress handling, hardens scene-loading fallbacks, slightly adjusts test timeouts, and adds Gut integration tests documenting and locking in the new behavior.

### File-Level Changes

| Change                                                                                                                                                     | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Files                                                                                                                                      |
|------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Refactor splash_screen.gd into a 3-stage pipeline with monotonic, deterministic progress and safer transitions.                                            | <ul><li>Replaced monolithic _process with _poll_resource_backend, _update_presentation_handler, and _evaluate_transition_router, called from _process.</li><li>Introduced presentation_speed (export) and display_target, driving loader_progress via move_toward for linear, frame-rate-independent progress.</li><li>Reworked threaded ResourceLoader status handling using match, including THREAD_LOAD_IN_PROGRESS, THREAD_LOAD_LOADED, FAILED, and INVALID_RESOURCE states.</li><li>Added PackedScene type validation and is_instance_valid checks before change_scene_to_packed, marking load_failed and falling back to change_scene_to_file when validation fails.</li><li>Ensured transitions only occur once loader/failed flags are set, min_load_time has elapsed, loader_progress ≈ 100%, and a DEFAULT_STARTUP_SCENE fallback is used when Globals.next_scene is empty.</li></ul> | `scripts/ui/screens/splash_screen.gd`                                                                                                      |
| Tweak shared test timeout configuration to accommodate longer Gut integration tests.                                                                       | <ul><li>Increased TEST_TIMEOUT default from 5000ms to 7000ms to prevent premature timeouts in slower or asynchronous tests.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | `tests/test_utils.py`                                                                                                                      |
| Add Gut integration tests for splash screen lifecycle, progress pipeline, backend safeguards, and transition timing, plus documentation for the milestone. | <ul><li>Introduced a Gut test suite that instantiates the splash scene and validates load_start_time initialization, monotonic display_target behavior, and move_toward-based linear convergence.</li><li>Added tests ensuring backend polling early exits when already loaded, marks load_failed and forces display_target to 100 for non-PackedScene resources, and that the transition router respects min_load_time.</li><li>Documented the refactor and tests in a milestone markdown file, including purpose, core improvements, benefits, and AI/human contributor notes.</li><li>Added a corresponding .uid file for the new Gut test scene/file registration.</li></ul>                                                                                                                                                                                                                | `test/gut/test_splash_screen.gd`<br/>`files/docs/milestones/22/Part_10_Refactor_splash_loader.md`<br/>`test/gut/test_splash_screen.gd.uid` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                                                       | Addressed | Explanation |
|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/778 | Refactor splash_screen.gd into a three-state presentation pipeline: update _process(delta) to capture frame delta, separate backend polling, presentation handling, and transition routing, use move_toward() for linear, frame-rate-independent progress, and ensure monotonic progress scaling via max() on backend progress. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/778 | Harden resource loading and scene transition logic: stop polling ResourceLoader once the resource reaches its final cache state, validate that loaded resources are PackedScene instances before use, and protect change_scene_to_packed() with defensive checks and fallbacks.                                                 | ✅        |             |

### Possibly linked issues

- **#TASK-01**: PR restructures splash_screen.gd into the requested three-state pipeline with move_toward, monotonic progress, and defensive checks.

---

## PR #893 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review with suggestions (e.g., relaxing the exact `loader_progress == 100.0` check for `move_toward` convergence, and considering exposing `presentation_speed` as an exported variable).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Conducted code review with actionable feedback (including test isolation for Globals settings and ensuring backend-path tests actually exercise the polled code).

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Implemented the three-state splash loader refactor (backend polling, presentation smoothing with `move_toward` / monotonic `display_target`, and transition routing), hardened ResourceLoader / PackedScene validation and fallbacks, added Gut integration tests covering monotonic progress, presentation convergence, early-exit, invalid resources, and min-load-time gating, and iteratively refined the implementation across multiple commits.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
