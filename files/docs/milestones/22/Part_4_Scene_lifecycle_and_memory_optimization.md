# Scene lifecycle and memory optimization
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
## Summary

**PR #852 – Scene lifecycle and memory optimization**

Optimizes the browser-based Playwright E2E test suite for the Godot HTML5 export by improving scene lifecycle management, reducing resource usage, and increasing observability of Godot engine loading and gameplay flows.

### Key Changes

**Test infrastructure & lifecycle**

- Introduces a module-scoped `shared_page` fixture so most tests reuse a single initialized Playwright page/context instead of reloading the Godot WASM engine per test.
- Adds smarter `init_page_and_wait_ready` helper (uses `domcontentloaded` + `window.godotInitialized` checks; short-circuits when already initialized).
- Stubs native `alert`/`confirm` dialogs to prevent CDP hangs.
- Adds per-test JS heap metrics capture and a consolidated lifecycle/memory summary at the end of the pytest run.
- Centralizes CDP/V8 coverage init/teardown with safe session detach (including for main-menu and audio tests).
- Improves process tracking so only test-spawned HTTP server / Chromium processes are terminated on session finish.
- Explicitly releases WebGL context on shared-page teardown to free GPU memory.

**Local test server & CI hardening**

- Upgrades the HTML5 test server to a threaded HTTP server with address reuse, stricter isolation headers, and improved signal trapping.
- Adds CI-specific Playwright Chromium launch arguments (software GL / ANGLE + SwiftShader, JS heap limits, no-sandbox, no `/dev/shm`) to reduce GPU usage and OOM risk in containers.

**Test refactoring**

- Migrates the majority of E2E tests (audio, volume/mute, difficulty, navigation, fuel, weapon firing, reset flows, etc.) to the shared-page pattern.
- Standardizes navigation and menu flows via shared helpers (`open_options_menu`, `open_audio_menu`, `set_log_level`, etc.).
- Strengthens assertions with deterministic waits, state-persistence checks, and log-based validation while avoiding unnecessary page reloads.
- Retains function-scoped pages where early console/error capture before engine boot is required.

**CI / Security**

- Bumps the pinned `github/codeql-action/upload-sarif` SHA in the Snyk and Trivy workflows for improved security and stability (scan behavior and upload logic otherwise unchanged).

### Related

- Closes / addresses [#773 – [TASK] Scene Lifecycle and Memory Optimization](https://github.com/ikostan/SkyLockAssault/issues/773)
- Supports Milestone 22: Optimize Test Suite Runtime & Fix Loading Screen
- Related epic: [#771 – Optimize Test Suite Runtime and Prevent CI Limit Exhaustion](https://github.com/ikostan/SkyLockAssault/issues/771)

### Impact

Reduces redundant Godot WASM boots, lowers memory/GPU pressure in CI and local runs, improves test reliability and observability, and hardens cleanup so orphaned processes and WebGL resources no longer leak across the suite.

---

## Reviewer's Guide

Refactors Playwright E2E tests to reuse a shared browser page and centralized Godot initialization, adds per-test memory and process lifecycle tracking, hardens browser/server teardown for GPU and JS heap leaks, and updates CI browser flags and SARIF upload actions for stability and security.

### File-Level Changes

| Change                                                                                                                                                | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Files                                                                                                                                                                                                                                                                                                                                                                                |
|-------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Standardize E2E tests on a shared Playwright page fixture and centralized Godot initialization helper to reduce redundant engine boots and flakiness. | <ul><li>Introduce a module-scoped shared_page fixture that boots the Godot WASM game once per module, stubs blocking dialogs, and explicitly releases WebGL context on teardown.</li><li>Update most tests to depend on shared_page instead of per-test page, adjusting console listener registration, navigation, selectors, and expectations accordingly.</li><li>Enhance init_page_and_wait_ready to short-circuit when the page is already initialized and to use domcontentloaded plus minimal canvas checks instead of networkidle.</li></ul>                                                                       | `tests/conftest.py`<br/>`tests/test_utils.py`<br/>`tests/reset_audio_flow_test.py`<br/>`tests/volume_sliders_mutes_test.py`<br/>`tests/difficulty_flow_test.py`<br/>`tests/audio_flow_test.py`<br/>`tests/navigation_to_audio_test.py`<br/>`tests/back_flow_test.py`<br/>`tests/fuel_depletion_test.py`<br/>`tests/difficulty_integration_test.py`<br/>`tests/weapon_firing_test.py` |
| Improve test lifecycle observability and cleanliness with memory metrics and scoped listeners/coverage.                                               | <ul><li>Add an autouse capture_lifecycle_metrics fixture to record JS heap usage after tests using page.performance.memory when available.</li><li>Ensure console listeners and CDP coverage sessions are registered and cleaned up explicitly in tests that use shared_page or page, including detach calls and exception guards.</li><li>Document and preserve function-scoped page usage for critical startup-error detection tests that must attach listeners before engine boot.</li></ul>                                                                                                                           | `tests/conftest.py`<br/>`tests/load_main_menu_test.py`<br/>`tests/validate_clean_load_test.py`<br/>`tests/no_error_logs_test.py`<br/>`tests/audio_flow_test.py`<br/>`tests/log_level_test.py`                                                                                                                                                                                        |
| Refine high-level flow tests around audio, options, and gameplay to use shared helpers and stronger, less brittle assertions.                         | <ul><li>Replace manual page.goto/wait_for_function sequences with init_page_and_wait_ready or start_game_and_wait_ready where appropriate.</li><li>Consolidate audio/options navigation flows via helper functions like open_options_menu, open_audio_menu, and set_log_level, and adjust assertions to use wait_for_function for DOM state rather than direct value asserts.</li><li>Simplify and tighten some log expectations and slider value checks, including looping over bus IDs instead of hard-coding repeated assertions.</li></ul>                                                                            | `tests/reset_audio_flow_test.py`<br/>`tests/volume_sliders_mutes_test.py`<br/>`tests/difficulty_flow_test.py`<br/>`tests/audio_flow_test.py`<br/>`tests/navigation_to_audio_test.py`<br/>`tests/back_flow_test.py`<br/>`tests/fuel_depletion_test.py`<br/>`tests/difficulty_integration_test.py`<br/>`tests/weapon_firing_test.py`<br/>`tests/test_utils.py`                         |
| Harden browser and HTTP server behavior for CI and local runs to reduce OOM, GPU issues, and hanging servers.                                         | <ul><li>Extend the session-scoped browser_instance fixture to accept override launch arguments via a CI-specific browser_type_launch_args fixture, and default to software GL and disabled GPU.</li><li>Configure CI Playwright Chromium flags (ANGLE + swiftshader, js heap cap, no-sandbox, no /dev/shm) and thread-based HTTP server with address reuse to avoid container OOMs and server bind failures.</li><li>Ensure test teardown explicitly loses WebGL context on the shared page to free GPU memory and uses a pytest_sessionfinish hook to terminate tracked subprocess PIDs from tests or scripts.</li></ul> | `tests/conftest.py`<br/>`tests/ci/conftest.py`<br/>`workspace/run_browser_tests.sh`                                                                                                                                                                                                                                                                                                  |
| Update security scanning workflows to use newer pinned CodeQL SARIF upload actions.                                                                   | <ul><li>Bump github/codeql-action/upload-sarif SHA pins in Snyk and Trivy workflows while preserving conditions and inputs.</li><li>Keep scan behavior, SARIF paths, and upload logic unchanged aside from the action version.</li><li>Align comments to emphasize periodic refresh of the pinned v3 action for security stability.</li></ul>                                                                                                                                                                                                                                                                             | `.github/workflows/snyk.yml`<br/>`.github/workflows/trivy.yml`                                                                                                                                                                                                                                                                                                                       |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                   | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| <https://github.com/ikostan/SkyLockAssault/issues/773> | Refactor Playwright browser, context, and page fixtures to reduce unnecessary browser launches and Godot WASM initialization cycles while preserving deterministic test isolation.                                          | ✅        |             |
| <https://github.com/ikostan/SkyLockAssault/issues/773> | Improve lifecycle teardown and resource management (WebGL/canvas, Playwright contexts/pages, local HTTP server, and spawned processes) and add basic lifecycle/memory monitoring to prevent leaks during repeated E2E runs. | ✅        |             |
| <https://github.com/ikostan/SkyLockAssault/issues/773> | Update the specified web E2E tests to use the new shared lifecycle patterns (including lighter-weight navigation and reset mechanisms) without changing their functional assertions or coverage.                            | ✅        |             |

### Possibly linked issues

- **#[TASK] Scene Lifecycle and Memory Optimization**: PR introduces shared Playwright fixtures, lifecycle metrics, teardown, and server/Chromium config changes matching the optimization task.
- **#771**: PR adds shared page lifecycle, memory metrics, HTTP server and CI Chromium optimizations, directly supporting the epic’s runtime and resource goals.

---

## 🤖 Bot & AI Contributions

This pull request includes substantial automated and AI-assisted contributions focused on dependency updates, code style enforcement, static analysis, and AI-powered code reviews/summaries.

### Summary of Activity

- **Dependency management:** Automated bump of the GitHub CodeQL `upload-sarif` action SHA in Snyk and Trivy workflows for security and stability.
- **Code formatting & style:** Multiple automated commits applying Black and isort formatting fixes across Python test files.
- **AI code review & summarization:** Generated PR summaries, reviewer’s guides, flow diagrams, and detailed review feedback on test lifecycle, shared page fixtures, cleanup patterns, and coverage assertions.
- **Static analysis:** Code quality / reliability review with PR report card (Security, Reliability, Complexity, Hygiene) and inline findings.

### Contributors

- **@dependabot** – Authored the dependency bump commit for `github/codeql-action/upload-sarif`.
- **@deepsource-autofix** – Authored multiple “style: format code with Black and isort” commits.
- **@deepsource-io** – Performed DeepSource Code Review (static analysis on Python/JavaScript changes) with full review report and PR report card.
- **@sourcery-ai** – Generated the “Summary by Sourcery”, Reviewer’s Guide (including lifecycle flowchart), and detailed review comments with suggestions on process cleanup, fixture centralization, and canvas/title assertions.
- **@coderabbitai** – Generated the “Summary by CodeRabbit”, pre-merge checks, poem, and overall PR analysis covering CI/security, tests, and chores.
- **@Copilot** – Co-authored commits related to browser launch args handling and CDP/console listener cleanup.

## 👤 Human Contribution

- **@ikostan** – Primary author and driver of the PR. Implemented the core scene lifecycle and memory optimizations (shared Playwright page fixture, smarter Godot initialization, per-test JS heap metrics, robust CDP/V8 coverage teardown, threaded HTTP test server improvements, process tracking/cleanup, CI Chromium flags for reduced GPU/OOM risk, and refactoring of E2E tests to use shared helpers and deterministic waits). Linked issue #773, managed labels/milestone/project board, and iterated on the changes based on bot feedback.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
