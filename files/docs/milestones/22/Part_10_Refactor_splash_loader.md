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

| Change                                                                                                              | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Files                                                                                                                                      |
|---------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Refactor splash_screen.gd into a three-stage loader pipeline with monotonic progress and guarded scene transitions. | <ul><li>Replace the monolithic _process loop with _ready plus three helpers: _poll_resource_backend, _update_presentation_handler, and _evaluate_transition_router, all invoked from _process(delta).</li><li>Introduce presentation_speed (exported with clamping) and display_target to drive loader_progress via move_toward for linear, frame-rate-independent progress smoothing.</li><li>Rework ResourceLoader threaded status handling using match, updating display_target monotonically via max() on backend progress and marking load_failed on failed or invalid resource states.</li><li>Validate that threaded-loaded resources are PackedScene instances before assigning to scene; on invalid type or null, set load_failed and force display_target to 100 for failure fallback.</li><li>Harden transition routing by gating scene changes on is_scene_loaded/load_failed, min_load_time, a near-100% loader_progress threshold, and transitioning flag, with fallbacks for empty next_scene and invalid PackedScene via change_scene_to_file and DEFAULT_STARTUP_SCENE.</li></ul> | `scripts/ui/screens/splash_screen.gd`                                                                                                      |
| Relax shared test timeout configuration to accommodate longer-running or asynchronous tests.                        | <ul><li>Increase TEST_TIMEOUT default from 5000ms to 7000ms while keeping DEFAULT_TIMEOUT unchanged.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `tests/test_utils.py`                                                                                                                      |
| Add Gut integration tests and milestone documentation to lock in splash screen progress and transition behavior.    | <ul><li>Create a Gut test suite that instantiates the splash screen scene and verifies load_start_time initialization in _ready(), monotonic display_target updates, and linear move_toward convergence affecting both loader_progress and progress_bar value.</li><li>Add tests that exercise backend early-exit when the scene is already loaded, handling of non-PackedScene resources by setting load_failed and forcing display_target to 100, and transition router gating based on min_load_time and progress thresholds.</li><li>Document the refactor, new three-state pipeline, monotonic progress behavior, hardened loading/transition logic, and test coverage in a milestone markdown file for PR #893.</li><li>Register the new Gut test file with a corresponding .uid file so the test runner discovers the suite.</li></ul>                                                                                                                                                                                                                                                      | `test/gut/test_splash_screen.gd`<br/>`files/docs/milestones/22/Part_10_Refactor_splash_loader.md`<br/>`test/gut/test_splash_screen.gd.uid` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                                    | Addressed | Explanation |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/778 | Refactor splash_screen.gd into a three-state presentation pipeline: update _process(delta) to capture frame delta, and split logic into _poll_resource_backend, a presentation handler using move_toward(), and a transition router, with strictly monotonic progress scaling via max() on backend progress. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/778 | Ensure progress animation is smooth and linear, independent of frame rate, and stop polling ResourceLoader.load_threaded_get_status() once the resource reaches its final cache state or failure.                                                                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/778 | Add defensive resource validation: perform an explicit PackedScene type check on ResourceLoader.load_threaded_get() results and protect change_scene_to_packed() with validation and safe fallbacks.                                                                                                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/780 | Implement a GUT unit test suite for splash_screen.gd in test_splash_screen.gd that follows repository test patterns (extends gut test.gd, proper setup/teardown, add_child_autofree, frame awaiting, and type-hinted variables).                                                                             | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/780 | Add unit tests validating monotonic progress behavior and move_toward-based convergent, frame-rate-independent progress resolution for the splash screen.                                                                                                                                                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/780 | Add unit tests validating transition gating mechanics for the splash screen: locked when the progress bar is incomplete and firing when progress reaches full completion under appropriate conditions.                                                                                                       | ✅        |             |

### Possibly linked issues

- **#778**: PR fully implements TASK-01’s three-state pipeline, linear move_toward progress, monotonic scaling, and PackedScene safeguards.

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
