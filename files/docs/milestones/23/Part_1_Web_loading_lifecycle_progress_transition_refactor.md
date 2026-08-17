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

| Change                                                                                                                                                           | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Files                                                                                   |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------|
| Inject telemetry-aware onProgress callback into the engine configuration and adjust loading lifecycle behavior around engine startup/failure.                    | <ul><li>Wrap $GODOT_CONFIG in a customConfig object that adds an onProgress(current, total) callback computing a floored percentage and guarding total>0.</li><li>Instantiate Engine with customConfig instead of raw $GODOT_CONFIG.</li><li>On successful startGame(), hide the loading UI, clean up ARIA attributes, set aria-hidden and aria-busy, remove role and aria-live, focus the canvas, and set window.godotInitialized=true.</li><li>On startGame() failure, mark aria-busy=false on the loading UI and show an alert to the user.</li></ul>                                                                                                                                                                                                                                                                                        | `custom_shell.html`                                                                     |
| Improve accessibility of the loading overlay and ensure post-load focus transfer to the canvas.                                                                  | <ul><li>Add role="status", aria-live="polite", and aria-busy="true" to the loading div for screen-reader status updates.</li><li>When the engine has initialized, hide the loading div, set aria-hidden="true" and aria-busy="false", and remove live-region attributes.</li><li>Programmatically focus the #canvas element after initialization to make the game keyboard-accessible.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                | `custom_shell.html`                                                                     |
| Normalize options UI back/reset button handlers to use consistent callback invocations.                                                                          | <ul><li>Update click handlers for options, controls, audio, advanced, and gameplay back/reset buttons to call their corresponding window.*Pressed([]) functions without inline comments or extraneous arguments.</li><li>Ensure all handlers use an empty array argument consistently.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | `custom_shell.html`                                                                     |
| Relax shared Playwright test timeout configuration to better accommodate slower web/WASM initialization.                                                         | <ul><li>Increase TEST_TIMEOUT default from 7000ms to 10000ms in the shared test utilities module.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `tests/test_utils.py`                                                                   |
| Add a Playwright-based splash transition and telemetry test suite, including isolated unit-style tests for the onProgress callback and a comprehensive E2E flow. | <ul><li>Implement helpers to extract the onProgress function source from custom_shell.html and execute it in an isolated JS context via page.evaluate.</li><li>Add fast unit tests verifying telemetry percentage math, flooring of fractional percentages, and suppression of logs when total==0.</li><li>Implement helpers that validate telemetry log progression and format, canvas visibility and bounding box dimensions, overlay teardown and ARIA state, focus transfer to the canvas, and window.godotInitialized invariants.</li><li>Add a test_splash_transition_flow that wires console/pageerror listeners, navigates to the HTML5 export, waits for window.godotInitialized, asserts telemetry and DOM invariants, captures artifacts (screenshot, logs, DOM HTML) on failure, and saves V8 coverage via CDP utilities.</li></ul> | `tests/splash_transition_flow_test.py`                                                  |
| Document the web loading lifecycle progress transition refactor and its relation to milestones and issues.                                                       | <ul><li>Add a milestone documentation file summarizing the PR purpose, core improvements, test suite additions, linked issues, and bot/human contribution notes.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      | `files/docs/milestones/23/Part_1_Web_loading_lifecycle_progress_transition_refactor.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                                                                        | Addressed | Explanation |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/777 | Implement telemetry-aware engine initialization hooks in the HTML custom shell to track progressive WebAssembly/binary streaming progress independently of the visual loading bar.                                                                                                                                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/777 | Improve the loading overlay’s visibility, ARIA/accessibility state, and focus behavior to coordinate with engine startup and mitigate WebGL layout/black-flash issues during the splash-to-canvas transition.                                                                                                                                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/777 | Add an automated Playwright-based browser test suite that validates the splash/loading transition flow, including telemetry logging behavior, canvas/DOM invariants, and absence of critical startup faults.                                                                                                                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/779 | Refactor custom_shell.html engine initialization to use a consolidated customConfig object derived from $GODOT_CONFIG, injecting an onProgress(current, total) callback that logs "Telemetry - Assembly Transfer: X%" and binding it via var engine = new Engine(customConfig).                                                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/779 | Adjust the initialization lifecycle in custom_shell.html so that web loading progress is observable in the console, the engine binds cleanly to the WebGL canvas, and the #loading overlay is torn down with appropriate accessibility attributes (e.g., aria-hidden) once application initialization finishes.                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/781 | Create tests/splash_transition_flow_test.py using Python + Playwright that follows project testing conventions, including explicit type annotations and importing shared lifecycle dependencies (e.g., test_utils).                                                                                                                              | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/781 | Implement an end-to-end Playwright flow that establishes a CDP session for V8 coverage, injects console logging hooks to capture and filter "Telemetry - Assembly Transfer:" events, and enforces a synchronization chain asserting #loading visibility, waiting for window.godotInitialized, and validating #canvas rendering/overlay teardown. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/781 | Add a defensive failure trap in the splash transition test that catches exceptions and writes runtime crash state artifacts (timestamped screenshots, console/page-error logs, and DOM HTML snapshots) into the shared artifacts/ directory.                                                                                                     | ✅        |             |

### Possibly linked issues

- **#EPIC**: PR fulfills epic’s HTML shell telemetry, accessibility, and Playwright E2E testing requirements for web loading lifecycle.
- **#TASK-02**: PR introduces customConfig with onProgress telemetry in custom_shell.html and refines loading overlay/ARIA per TASK-02.

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
