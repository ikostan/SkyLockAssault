# Replace brittle waits with deterministic polling
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## PR #845 Summary: Replace brittle waits with deterministic polling

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `code-audits-asynchronous-refactoring` → `main`  
**Linked Issue:** [#772 – [TASK] Code Audits & Asynchronous Refactoring](https://github.com/ikostan/SkyLockAssault/issues/772)  
**Milestone:** Milestone 22 – Optimize Test Suite Runtime & Fix Loading Screen  
**Labels:** `enhancement`, `testing`, `refactoring`, `python`, `QA`

### Purpose

Eliminate timing-dependent flakiness in the Playwright browser E2E test suite by replacing all fixed-duration waits (`page.wait_for_timeout()`, arbitrary sleeps) with deterministic, state-based synchronization. The changes make tests wait for actual engine readiness, DOM visibility, or console-log events instead of relying on brittle timeouts.

### Core Improvements

#### 1. Deterministic Waiting & Assertions

- Replaced every `page.wait_for_timeout()` with:
  - `page.wait_for_function()` for Godot initialization (`window.godotInitialized === true`) and DOM style/display checks
  - Playwright `expect(locator).to_be_visible()` for canvas, buttons, and overlays
- Introduced reusable `wait_for_console_log(logs, predicate, start_idx, page)` helper that polls captured console messages with a predicate until the condition is met or a timeout occurs
- Standardized console-log assertions (lower-cased matching, structured waiting) across volume, reset, audio, difficulty, back-navigation, and navigation tests
- Strict equality check for Godot readiness (`=== true` instead of truthy)

#### 2. Shared Test Utilities & Fixtures

- Extracted common helpers and timeout constants into new module `tests/test_utils.py`
- Centralized `DEFAULT_TIMEOUT` / `TEST_TIMEOUT` (environment-configurable)
- Restructured `tests/conftest.py`:
  - Session-scoped `browser_instance` fixture (single Chromium launch with GPU/WebGL flags)
  - Function-scoped isolated `BrowserContext` + `Page` per test
  - Optional HAR recording support via marker
  - Full type annotations (`Browser`, `BrowserContext`, `Page`, `Generator`, etc.)

#### 3. Test Coverage Stabilization

Affected test files (all converted to deterministic waits):

- `tests/audio_flow_test.py`
- `tests/volume_sliders_mutes_test.py`
- `tests/reset_audio_flow_test.py`
- `tests/difficulty_flow_test.py`
- `tests/back_flow_test.py`
- `tests/navigation_to_audio_test.py`
- `tests/load_main_menu_test.py`
- `tests/no_error_logs_test.py`
- `tests/validate_clean_load_test.py`

Improvements include:

- Explicit waiting for callback availability (`window.xxxPressed`)
- Verification of menu transitions via `getComputedStyle(...).display`
- Persistence checks after back-navigation and slider changes
- Stricter “no unexpected errors” verification with clearer failure diagnostics (screenshots + captured logs)

#### 4. Browser Test Runner Hardening (`workspace/run_browser_tests.sh`)

- Added `git config --global --add safe.directory` to avoid “dubious ownership” errors in containers
- Simplified and made robust the `git restore` of `export_presets.cfg` and `globals.gd`
- Signal-aware cleanup (`trap` on `EXIT`/`INT`/`TERM`) for the background HTTP server
- Increased server readiness polling frequency and timeout with clearer failure messages
- Improved pytest invocation formatting and report-generation comments
- Removed manual `kill` of server PID in favor of trap-based cleanup

#### 5. Code Quality & Maintainability

- Added comprehensive type hints (`Any`, `Callable`, `Generator`, `Dict`, `List`, `Optional`)
- Removed verbose/redundant comments and outdated docstrings
- Normalized imports and formatting (multiple Black + isort passes)
- Extracted duplicated helpers (e.g. `has_save_log`) into the shared utility module

#### 6. Micro-Polling & Test Runner Hardening (Final Review Pass)

- **Clock & Exception Safety (`tests/test_utils.py`):**
  - Updated `wait_for_console_log` to measure elapsed polling time via `time.monotonic()`.
  - Replaced `pytest.fail()` with `AssertionError` in `wait_for_console_log` to prevent timeout exceptions from bypassing test-level artifact capture (`except Exception:`).
  - Centralized `has_save_log()` helper to check for encrypted/plaintext save entries.

- **Race Condition & Persistence Fixes:**
  - Synchronized `toggleMuteMaster([1])` and `toggleMuteSfx([1])` steps in `tests/audio_flow_test.py` with deterministic log polling.
  - Added save-log synchronization prior to `page.reload()` in `tests/reset_audio_flow_test.py` (`STATE-01`) to guarantee async disk flushes complete before page reloads.
  - Standardized callback argument signatures across test files (e.g. `window.audioPressed([])`).

- **V8 Coverage Teardown Resilience:**
  - Added `coverage_started` state tracking and isolated CDP profiler teardown in `finally` blocks using `try...except` handling, ensuring coverage harvesting failures never mask primary test assertion failures.

### Benefits

- Dramatically reduced flakiness caused by race conditions and variable load times
- Faster overall suite runtime (shared browser launch + tighter, condition-driven waits)
- Better isolation between tests while keeping startup overhead low
- Clearer failure diagnostics and more maintainable test code
- Improved CI reliability for browser-based E2E runs

### ⏱️ Individual Test Execution Breakdown

The HTTP server request deltas reflect observed request-to-request wall-clock intervals (inclusive of browser initialization, page reloads, test teardown, and server scheduling overhead):

| Test File                                                   | Start Time | End Time   | Approx. Duration |
|-------------------------------------------------------------|------------|------------|------------------|
| `tests/audio_flow_test.py`                                  | `03:31:38` | `03:31:43` | **~5.0s**        |
| `tests/back_flow_test.py` *(includes 1 page reload)*        | `03:31:43` | `03:31:52` | **~9.0s**        |
| `tests/difficulty_flow_test.py`                             | `03:31:52` | `03:32:01` | **~9.0s**        |
| `tests/load_main_menu_test.py`                              | `03:32:01` | `03:32:03` | **~2.0s**        |
| `tests/navigation_to_audio_test.py`                         | `03:32:03` | `03:32:08` | **~5.0s**        |
| `tests/no_error_logs_test.py`                               | `03:32:08` | `03:32:10` | **~2.0s**        |
| `tests/reset_audio_flow_test.py` *(includes 1 page reload)* | `03:32:10` | `03:32:20` | **~10.0s**       |
| `tests/validate_clean_load_test.py`                         | `03:32:20` | `03:32:22` | **~2.0s**        |
| `tests/volume_sliders_mutes_test.py`                        | `03:32:22` | `03:32:27` | **~5.0s**        |

---

## Reviewer's Guide

Refactors Playwright-based E2E tests and the browser test runner to replace brittle fixed timeouts with deterministic state-based polling, introduce reusable console-log waiting helpers, improve fixtures and typing, and harden the CI shell script and server startup behavior.

### File-Level Changes

| Change                                                                                                                                | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Files                                                                                                                                                                                                                                                                                                                           |
|---------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Introduce deterministic console-log polling helpers and replace ad-hoc log assertions based on fixed waits.                           | <ul><li>Add a wait_for_console_log(predicate, start_idx, timeout_ms) helper in multiple tests to poll captured console logs until a predicate matches or the timeout elapses.</li><li>Use wait_for_console_log instead of page.wait_for_timeout() followed by manual log slicing for all log-based assertions in volume, reset, audio, difficulty, back-flow, and navigation tests.</li><li>Standardize console assertion patterns to rely on lowercased log text and structured waiting, reducing log handling duplication and flakiness.</li></ul>                                                                                                                                                                  | `tests/volume_sliders_mutes_test.py`<br/>`tests/reset_audio_flow_test.py`<br/>`tests/audio_flow_test.py`<br/>`tests/difficulty_flow_test.py`<br/>`tests/back_flow_test.py`<br/>`tests/navigation_to_audio_test.py`                                                                                                              |
| Replace arbitrary page.wait_for_timeout() calls with deterministic Playwright waits and expect() assertions for DOM and engine state. | <ul><li>Remove initial splash-scene waits and instead wait for window.godotInitialized === true using page.wait_for_function in all affected tests.</li><li>Switch canvas and overlay visibility checks from page.wait_for_selector() and manual style evaluation to expect(locator).to_be_visible() and page.wait_for_function() on specific style/display values.</li><li>Use page.wait_for_function() to verify slider value changes and menu transitions instead of time-based sleeps, including difficulty, audio back navigation, and reset flows.</li></ul>                                                                                                                                                    | `tests/volume_sliders_mutes_test.py`<br/>`tests/reset_audio_flow_test.py`<br/>`tests/audio_flow_test.py`<br/>`tests/difficulty_flow_test.py`<br/>`tests/back_flow_test.py`<br/>`tests/navigation_to_audio_test.py`<br/>`tests/load_main_menu_test.py`<br/>`tests/no_error_logs_test.py`<br/>`tests/validate_clean_load_test.py` |
| Refine Godot initialization and DOM overlay checks to be explicit and robust.                                                         | <ul><li>Change initialization checks from truthy window.godotInitialized to strict window.godotInitialized === true for all tests.</li><li>Ensure main-menu and options DOM overlays are asserted using Playwright expect() and explicit style checks, rather than comments or loose visibility assumptions.</li><li>Tighten checks around gameplay/audio/options menu transitions by explicitly asserting display style changes (block/none) after back and navigation actions.</li></ul>                                                                                                                                                                                                                            | `tests/volume_sliders_mutes_test.py`<br/>`tests/reset_audio_flow_test.py`<br/>`tests/audio_flow_test.py`<br/>`tests/difficulty_flow_test.py`<br/>`tests/back_flow_test.py`<br/>`tests/navigation_to_audio_test.py`<br/>`tests/load_main_menu_test.py`<br/>`tests/validate_clean_load_test.py`                                   |
| Restructure pytest fixtures to reuse a session-scoped browser and provide function-scoped, isolated contexts and pages.               | <ul><li>Introduce a session-scoped browser_instance fixture that launches Chromium once with the required GPU/WebGL flags and yields the Browser.</li><li>Refactor the page fixture to depend on browser_instance, creating a new BrowserContext and Page per test, with optional HAR recording based on a record_har marker.</li><li>Add typing to fixtures (Browser, BrowserContext, Page, Generator, pytest.FixtureRequest, pytest.Config) and clean up browser lifecycle to close only contexts per test and the browser at session end.</li></ul>                                                                                                                                                                | `tests/conftest.py`                                                                                                                                                                                                                                                                                                             |
| Improve typing, imports, and comment clarity across tests.                                                                            | <ul><li>Add typing imports such as Any, Callable, Generator, Dict, List, Optional where appropriate and annotate console handlers and helper functions.</li><li>Import pytest and Playwright expect API in tests that use them, and remove redundant or overly verbose docstrings and comments that no longer reflect behavior.</li><li>Normalize DEFAULT_TIMEOUT/TEST_TIMEOUT definitions and remove outdated comments about fallback behavior or CLI feature flags that are now enforced elsewhere.</li></ul>                                                                                                                                                                                                       | `tests/volume_sliders_mutes_test.py`<br/>`tests/reset_audio_flow_test.py`<br/>`tests/audio_flow_test.py`<br/>`tests/difficulty_flow_test.py`<br/>`tests/back_flow_test.py`<br/>`tests/navigation_to_audio_test.py`<br/>`tests/conftest.py`                                                                                      |
| Harden the browser test runner shell script for CI reliability and cleanup.                                                           | <ul><li>Configure git safe.directory for the project path to avoid dubious ownership errors in containers before running modifications.</li><li>Simplify git restore to restore both export_presets.cfg and globals.gd in a single command with error checking.</li><li>Add a trap on EXIT/INT/TERM to reliably kill the background HTTP server, increase server readiness polling frequency and timeout, and restructure the curl-based readiness loop with clear failure messaging.</li><li>Reformat the pytest invocation with line breaks for readability and explicitly comment the report generation section.</li><li>Remove manual kill of SERVER_PID at the end in favor of the trap-based cleanup.</li></ul> | `workspace/run_browser_tests.sh`                                                                                                                                                                                                                                                                                                |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                | Addressed | Explanation |
|------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| <https://github.com/ikostan/SkyLockAssault/issues/772> | Refactor Playwright browser tests in tests/ to replace arbitrary static waits (e.g., page.wait_for_timeout/time.sleep) with deterministic synchronization using Playwright wait_for_function/expect and console-log/event predicates, while preserving existing assertions and behavior. | ✅        |             |
| <https://github.com/ikostan/SkyLockAssault/issues/772> | Streamline pytest fixtures in tests/conftest.py to use an optimized browser lifecycle (session-scoped browser, function-scoped contexts/pages) and improve maintainability.                                                                                                              | ✅        |             |
| <https://github.com/ikostan/SkyLockAssault/issues/772> | Improve workspace/run_browser_tests.sh to reduce unnecessary startup/readiness overhead and make CI/browser test execution more robust (server startup checks, cleanup, Git safety, etc.).                                                                                               | ✅        |             |

### Possibly linked issues

- **#TASK**: PR directly addresses the test wait refactors, fixture lifecycle changes, and runner optimizations specified in the issue.
- **#N/A**: PR implements audio_flow_test with WARN-01–03 using DOM overlays and log assertions, matching the feature request.

---

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer's Guide. Performed code review identifying duplication of `wait_for_console_log`, suggesting extraction to a shared utility, recommending Playwright locator assertions over raw JS `wait_for_function` checks, and noting potential tracing cleanup for session-scoped browser fixtures.
- **@coderabbitai**  
  Generated the PR summary and detailed walkthrough. Conducted multiple rounds of code review with actionable suggestions (timeout centralization, helper extraction, assertion improvements, shell-script hardening). Co-authored commits updating `workspace/run_browser_tests.sh`.
- **@deepsource-io**  
  Performed automated code review, published a PR Report Card (Security / Reliability / Complexity / Hygiene), and provided analysis status for Python and JavaScript.
- **@deepsource-autofix**  
  Authored multiple automated style/format commits (`style: format code with Black and isort`) to enforce formatting consistency across test files.

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Implemented the core refactor (deterministic polling with `wait_for_function` / `expect()`, `wait_for_console_log` helper, session-scoped browser + function-scoped contexts, type hints, and hardened `run_browser_tests.sh`). Authored the majority of commits, addressed review feedback, extracted shared utilities to `tests/test_utils.py`, and created supporting documentation.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
