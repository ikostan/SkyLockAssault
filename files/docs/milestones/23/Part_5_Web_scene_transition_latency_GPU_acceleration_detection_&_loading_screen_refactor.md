# Web scene transition latency, GPU acceleration detection and loading screen refactor
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

## PR #913 Summary: Fix web loading stalls and add GPU acceleration warning

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `web-export-loading-screen-hangs` → `main`  
**Linked Issues:** #912 (Playwright: UX completion hold & assembly-transfer telemetry) and related web-loading work  
**Milestone:** Milestone 23 – Settings Architecture & FPS Counter Implementation  
**Labels:** bug, enhancement, web, testing, GUI, python, playwright, gdunit4, QA

---

### Purpose

Stop web-export loading screens from appearing to hang, make scene transitions more predictable, warn players when the browser falls back to software WebGL, and lock the behavior in with GdUnit4 + Playwright regression coverage.

### Core Improvements

#### 1. Loading Screen & Scene Transitions

- Reduce artificial min-load delay so the bar does not stall at 100%
- Delta-based progress smoothing (replace asymptotic/lerp-style hang behavior)
- Early `ResourceLoader.exists` checks for missing/invalid `Globals.next_scene`
- Centralized scene-change path with packed-scene validation and direct file fallback
- Reorder caching/reset of `next_scene` relative to the ~1s completion hold to avoid races
- Exclude development/test assets from web export presets

#### 2. GPU Acceleration Detection & Warning (`custom_shell.html`)

- Detect common software WebGL renderers (e.g. SwiftShader / llvmpipe)
- Log active GPU when hardware acceleration is available
- Accessible full-screen warning modal when software rendering is detected
- Keyboard-dismissable; focus restored after acknowledgment so play can continue

#### 3. Web Shell / Pause Menu Bridge

- Expose pause-menu actions (resume, options, main menu) to the browser JS bridge
- Enables reliable browser automation without relying on Escape/keyboard alone

#### 4. Test HTTP Server Hardening

- Suppress expected `BrokenPipeError` / `ConnectionResetError` / `EPIPE` / `ECONNRESET` when clients disconnect mid-transfer
- Cleaner CI logs without hiding real server failures

#### 5. Automated Coverage

**GdUnit4**
- Loading-screen init, progress, transition gating, completion hold, fallback paths
- Pause-menu / related isolation fixes

**Playwright**

- `gpu_detection_modal_test.py` — software-renderer detection, modal UX, accessibility, hardware bypass
- `scene_transition_lifecycle_test.py` — Main Menu ↔ Gameplay ↔ Pause lifecycle, idempotency, performance SLA
- `telemetry_and_hold_test.py` — UX 1.0s hold pacing, assembly-transfer telemetry, boundary handling
- Shared helpers: auto-dismiss GPU modal in headless CI, CDP/V8 coverage, failure artifacts

#### 6. Documentation

- Milestone 23 doc covering transition latency investigation, GPU detection, and loading-screen refactor

### Benefits

- Web loads complete instead of looking frozen at full progress
- Players understand soft-GPU / no-acceleration cases instead of unexplained lag
- More reliable scene transitions and recovery on failed/missing targets
- Quieter, more deterministic browser CI under software rasterizers
- Regression net for loading, GPU modal, transitions, and telemetry

### Status Notes

Addresses web loading-stall / transition reliability work and the Playwright telemetry/hold objectives associated with #912 under Milestone 23.

---

## Reviewer's Guide

This PR addresses web loading stalls by coordinating loading progress with scene-transition readiness, adding recovery paths and a completion hold, warning users when WebGL is software-rendered before boot, exposing pause controls for browser interaction, and strengthening web export/CI behavior with broad regression coverage and documentation.

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                | Addressed | Explanation |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/829 | Prevent Web export scene transitions from appearing to hang at approximately 80% and 90%, including eliminating artificial loading delays and making progress completion and scene swapping predictable.                                                                 | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/829 | Handle browser-side software WebGL rendering that causes severe transition stalls by detecting likely software renderers before engine startup and informing users how to enable hardware acceleration.                                                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/829 | Improve reliability of the affected web transition workflow, including return-to-main-menu behavior, interrupted web requests, and regression coverage for loading and scene lifecycle behavior.                                                                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/909 | Add a dedicated GDUnit4 loading-screen regression suite covering initialization guards, valid and invalid threaded resource-loading paths, progress interpolation and clamping, transition gating, idempotency, completion delay, global cleanup, and fallback recovery. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/909 | Ensure loading-screen lifecycle behavior supports deterministic, bounded asynchronous testing, including explicit invalid-path handling, linear delta-scaled progress movement, minimum-load-time enforcement, and the 1.0-second completion hold.                       | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/909 | Provide complete automated coverage and test isolation suitable for CI, with per-test global-state restoration, bounded polling, lifecycle cleanup checks, and coverage of failure and recovery paths.                                                                   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/910 | Add the Playwright GPU detection and warning-modal test suite at tests/gpu_detection_modal_test.py, covering software renderers, hardware bypass, missing WebGL capabilities, case-insensitive matching, exception safety, dismissal, and keyboard accessibility.        | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/910 | Implement or expose the pre-boot WebGL software-rasterizer detection and accessible warning modal behavior required by the test contracts, including pausing boot until dismissal and restoring canvas focus afterward.                                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/910 | Ensure the new modal does not break existing browser-based flows and that web-export test infrastructure can handle the warning and client disconnects reliably.                                                                                                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/911 | Add the requested Playwright test suite at `tests/scene_transition_lifecycle_test.py` covering forward and reverse scene transitions, transition performance, duplicate-trigger behavior, and multi-cycle re-entry.                                                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/911 | Verify lifecycle teardown and idempotency invariants, including the absence of duplicate Main Menu/gameplay scenes and the correct removal or retention of gameplay, HUD, player, and UI nodes during transitions.                                                       | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/911 | Validate persistent browser lifecycle invariants: `window.godotInitialized` stays true and the `#canvas` retains positive dimensions at startup, after gameplay initialization, and after Main Menu re-entry.                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/912 | Add a Playwright test validating that the loading screen remains at 100% for approximately 1.0 seconds before the scene swap.                                                                                                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/912 | Add Playwright coverage proving assembly-transfer progress telemetry is finite, bounded, monotonic non-decreasing, and reaches 100% without exceeding it.                                                                                                                | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/912 | Add Playwright coverage exercising the production onProgress handler with zero, negative, excessive, and non-finite inputs, verifying safe handling without uncaught errors or invalid telemetry.                                                                        | ✅        |             |

### Possibly linked issues

- **#829**: The PR directly fixes issue #829 through loading-screen timing/progress changes and a software GPU warning modal.
- **#N/A**: The PR directly implements the issue’s Playwright GPU detection, modal dismissal, accessibility, and robustness test plan.
- **#unknown**: The PR addresses the epic’s core web loading lifecycle refactor, including progress pacing, scene transition gating, telemetry, and automated validation.

---

## PR #913 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Left review comments on the web loading, GPU warning, and related test changes (later limited by review budget / diff-size caps on this large PR).

- **@coderabbitai**  
  Generated the PR summary. Performed code review with actionable feedback (e.g. pause-menu test cleanup for `Globals.next_scene`, and tightening GPU-modal wait/click exception handling in Playwright helpers).

- **@deepsource-io**  
  Performed automated DeepSource Code Review and left review comments on the PR.

- **@deepsource-autofix**  
  Authored multiple automated style/format commits (`style: format code with Black and isort`) throughout the PR lifecycle.

- **@copilot** (GitHub Copilot)  
  Co-authored commits hardening GPU-warning modal handling in Playwright tests and refining scene-transition test logging/waits.

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Fixed web loading stalls (progress completion, scene-transition handling, fallbacks), added software-WebGL / GPU acceleration detection and accessible warning modal, exposed pause-menu actions to the web JS bridge, silenced expected client-disconnect noise in the test HTTP server, excluded dev/test assets from web exports, and added broad GdUnit4 + Playwright coverage (GPU modal, scene lifecycle, telemetry/UX hold, loading-screen robustness) with extensive iterative CI/test stabilization and documentation under Milestone 23.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
