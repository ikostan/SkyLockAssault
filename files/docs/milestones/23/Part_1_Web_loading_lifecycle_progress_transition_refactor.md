# Web loading lifecycle progress transition refactor
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

## PR #895 Summary: Web loading lifecycle progress transition refactor

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `web-loading-lifecycle-progress-transition-refactor` → `main`  
**Linked Issues:** #777, #779, #781 (and related Epic web-loading goals)  
**Milestone:** Milestone 22 – Optimize Test Suite Runtime & Fix Loading Screen  
**Labels:** enhancement, web, testing, CI/CD, GUI, refactoring, EPIC, QA

### Purpose

Improve the HTML5/WASM web loading lifecycle: add accurate assembly-transfer telemetry, harden loading-overlay accessibility and focus behavior, normalize shell handlers, and introduce a Playwright suite that validates the full splash → game transition path (including telemetry math and DOM/canvas invariants).

### Core Improvements

#### 1. Telemetry-Aware Engine Config (`custom_shell.html`)

- Wrap `$GODOT_CONFIG` in a `customConfig` that injects `onProgress(current, total)`
- Log `"Telemetry - Assembly Transfer: X%"` with floor math and a guard for `total === 0`
- Initialize `Engine` with the merged config; keep `startGame()` async
- Set `window.godotInitialized = true` on successful start

#### 2. Loading Overlay Accessibility & Focus

- ARIA attributes on the loading container: `role="status"`, `aria-live="polite"`, `aria-busy="true"`
- On hide: set `aria-hidden="true"` and `aria-busy="false"`
- Transfer focus to `#canvas` after engine init for keyboard accessibility

#### 3. Shell Handler Cleanup

- Normalize options / controls / audio / advanced / gameplay back & reset button handlers
- Consistent `window.*Pressed([])` calls (no extraneous args or noisy inline comments)

#### 4. Shared Test Config (`tests/test_utils.py`)

- Raise default `TEST_TIMEOUT` from 7000 ms → **10000 ms** to reduce flakiness on slower WASM startups

#### 5. Playwright Splash Transition Suite (`tests/splash_transition_flow_test.py`)

**Unit-style telemetry checks**
- Extract `onProgress` from `custom_shell.html` and run it in isolation
- Validate percentage math, flooring, and zero-total edge cases

**E2E flow**

- Boot HTML5 export, track console telemetry events
- Assert progress values in 0–100 and non-decreasing progression
- Verify canvas layout (bounding box width/height > 0), overlay teardown, ARIA state, focus transfer
- Confirm `window.godotInitialized` remains true after overlay hide
- Capture failure artifacts (screenshot, logs, DOM snapshot) and V8 coverage via CDP

### Benefits

- Observable, accurate WASM download progress for debugging and UX
- Better accessibility (screen-reader status + post-load focus)
- Automated regression coverage for the critical splash → game path
- Cleaner, more consistent shell event wiring
- Reduced flakiness for slow web/WASM initialization under CI

### Status Notes

Addresses the telemetry, overlay/ARIA lifecycle, and Playwright E2E objectives of the linked tasks (#777, #779, #781) under the web loading lifecycle epic.

---

## Reviewer's Guide

Refactors the HTML5 custom shell’s web loading lifecycle by adding telemetry-aware engine configuration, improving accessibility and focus management for the loading overlay and canvas, tightening options menu handlers, and introducing Playwright-based tests that validate the splash transition flow and onProgress telemetry math.

### File-Level Changes

| Change                                                                                          | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Files                                  |
|-------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------|
| Add telemetry-aware Engine configuration and lifecycle handling for the web loading flow.       | <ul><li>Wrap $GODOT_CONFIG in a customConfig object that injects an onProgress(current, total) callback.</li><li>Implement percentage computation with floor math and guard against total=0 to avoid invalid output.</li><li>Initialize the Engine with customConfig and keep startGame asynchronous for stability.</li><li>Mark window.godotInitialized on successful engine start and log startup status.</li></ul>                                                                                                                                                                                                                                                                             | `custom_shell.html`                    |
| Improve loading overlay accessibility, focus transfer, and state teardown after initialization. | <ul><li>Add ARIA role/status attributes (role='status', aria-live='polite', aria-busy='true') to the loading container.</li><li>Update the loading overlay hide sequence to also set aria-hidden='true' and aria-busy='false'.</li><li>Transfer focus to the game canvas (#canvas) after successful engine initialization to improve keyboard accessibility.</li></ul>                                                                                                                                                                                                                                                                                                                            | `custom_shell.html`                    |
| Clean up options menu button handlers in the custom shell.                                      | <ul><li>Normalize click handlers for options, controls, audio, advanced, and gameplay back/reset buttons by removing trailing inline comments.</li><li>Ensure each handler calls the corresponding window.*Pressed([]) function with a consistent empty-array payload.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                  | `custom_shell.html`                    |
| Adjust shared test timeout configuration for Playwright-based suites.                           | <ul><li>Increase TEST_TIMEOUT default value from 7000ms to 10000ms to reduce flakiness for slower startup scenarios.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | `tests/test_utils.py`                  |
| Introduce a Playwright-based splash transition and telemetry test suite for the web export.     | <ul><li>Add helpers to extract the onProgress telemetry function source from custom_shell.html and execute it in isolation within the browser context.</li><li>Add fast unit-style tests that validate percentage math, flooring behavior, and total=0 edge cases for the telemetry callback.</li><li>Add E2E helpers that assert telemetry progression, canvas rendering invariants, loading overlay teardown, ARIA state updates, and focus transfer to the canvas.</li><li>Implement a comprehensive test_splash_transition_flow that boots the HTML5 export, tracks console telemetry, enforces invariants, captures artifacts on failure, and saves V8 coverage via CDP utilities.</li></ul> | `tests/splash_transition_flow_test.py` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                           | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/777 | Implement engine initialization telemetry hooks in the HTML5 custom shell configuration so that WebAssembly/binary streaming progress is reported safely and accurately (including edge cases like zero total).                                                                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/777 | Coordinate the loading overlay’s visibility and focus behavior with engine startup to avoid visual flicker/black frames and to correctly mark and tear down the loading UI (including ARIA/accessibility state updates).                                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/777 | Add an automated Playwright-based browser test suite that validates the splash/loading transition flow, telemetry logging behavior, DOM/canvas invariants, and absence of critical startup errors.                                                                                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/779 | Refactor the engine initialization in custom_shell.html to use a consolidated customConfig derived from $GODOT_CONFIG, inject an onProgress(current, total) callback that logs "Telemetry - Assembly Transfer: X%" to the console, and initialize the engine via new Engine(customConfig).          | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/779 | Ensure the initialization lifecycle properly manages the loading overlay and accessibility/DOM behavior so that the engine binds cleanly to the WebGL canvas, the #loading element is removed/hidden, and appropriate ARIA attributes are set once initialization finishes.                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/781 | Implement tests/splash_transition_flow_test.py using Playwright, matching project conventions (type annotations, shared test_utils, and lifecycle dependencies).                                                                                                                                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/781 | Instrument the Playwright E2E test with a CDP session for V8 coverage, custom console logging to track "Telemetry - Assembly Transfer:" events, and a robust synchronization chain that asserts #loading visibility, waits for window.godotInitialized, and validates #canvas rendering/visibility. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/781 | Implement a defensive failure trap that catches exceptions during the splash transition flow test and writes artifacts (screenshot, console/page-error logs, and DOM snapshot) into the shared artifacts/ directory.                                                                                | ✅        |             |

### Possibly linked issues

- **#EPIC**: PR adds HTML shell telemetry hook, accessibility, and Playwright tests, directly addressing epic’s web loading lifecycle goals.
- **#TASK-02**: PR introduces customConfig with onProgress telemetry, binds it to Engine(), and refines loading overlay/ARIA per TASK-02.

---

## PR #895 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review with suggestions (e.g., gating noisy `onProgress` console logging behind a debug flag, and relaxing strict monotonicity checks to allow equal consecutive progress values).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Conducted code reviews. Authored the “CodeRabbit Generated Unit Tests” commit and co-authored a later test update commit.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@deepsource-autofix**  
  Authored multiple automated style/format commits (`style: format code with Black and isort`) to enforce Black + isort consistency.

- **@copilot** (GitHub Copilot)  
  Co-authored the commit that enhanced splash transition telemetry checks (regex parsing of progress marks, bounds/monotonic assertions, and related test hardening).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Implemented the web loading lifecycle refactor: custom `onProgress` telemetry in `custom_shell.html`, ARIA accessibility and canvas focus handling for the loading overlay, normalized options button handlers, increased shared test timeouts, and the full Playwright `splash_transition_flow_test.py` suite (telemetry unit checks, E2E flow, canvas/ARIA invariants, failure artifacts, V8 coverage). Authored the majority of commits and iteratively refined the implementation and tests.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
