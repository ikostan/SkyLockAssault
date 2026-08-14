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
