# Web asset delivery Playwright failure diagnostics - #872
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
---

## PR #872 Summary: Web asset delivery & Playwright failure diagnostics

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `web-asset-delivery-playwright-failure-diagnostics` → `main`  
**Linked Issues:** Epic #771, Task #844 (Web Asset Delivery & Playwright Failure Diagnostics)  
**Labels:** testing, CI/CD, github actions, github_actions, refactoring, QA

### Purpose

Improve Playwright E2E test reliability and debuggability while optimizing delivery of Godot HTML5/WASM web assets. The PR adds failure-only diagnostics (traces, screenshots, videos) and tunes local/CI HTTP servers plus nginx for correct MIME types, caching, compression, and cross-origin isolation.

### Core Improvements

#### 1. Failure-Only Playwright Diagnostics (`tests/conftest.py`)

- New centralized helper `_cleanup_context_diagnostics` that:
  - On **failure**: captures full-page screenshot, stops tracing and saves `trace_*.zip`, keeps video as `video_*.webm`
  - On **success**: stops tracing without saving, deletes any recorded video, produces zero diagnostic artifacts
- Enabled tracing + video recording for both module-scoped `shared_page` and function-scoped `page` fixtures
- Robust teardown order (screenshot → stop trace → close context → save/delete video) with warning-based error handling
- Preserved existing WebGL `loseContext` cleanup and `@pytest.mark.record_har` support

#### 2. Optimized Web Asset Delivery

**Local / CI Python servers** (`workspace/run_browser_tests.sh`, `workspace/run_pipeline.sh`):

- Replaced simple handler with `OptimizedGodotHandler`
- Registered `application/wasm` MIME type
- Differentiated `Cache-Control`:
  - `.wasm` / `.pck` / `.js` → `public, max-age=3600`
  - HTML entrypoints → `no-cache, must-revalidate`
  - Other static assets → `public, max-age=1800`
- Switched to `ThreadedHTTPServer` for better concurrency
- Kept COOP/COEP headers for cross-origin isolation

**Nginx** (`infra/nginx/default.conf`):

- Registered `application/wasm`
- Enabled `gzip` + `gzip_static` (including wasm in `gzip_types`)
- Matching Cache-Control and COOP/COEP location blocks
- Simplified MIME / types configuration

**Docker Compose** (`infra/docker-compose.yml`):

- Updated volume mount from `../export/web` → `../export/web_thread_off`
- Copyright year refreshed to 2025–2026

### Omission of `immutable` Cache-Control Directive

The `Cache-Control` header for static web export assets (`.wasm`, `.pck`, `.js`, `.css`) is configured as `public, max-age=3600` without the `immutable` directive for the following reasons:

* **Prevent Stale Asset Persistence:** The `immutable` directive prevents browsers from sending revalidation requests even on manual page refreshes.
* **Build & Deployment Safety:** Omitting `immutable` ensures that when Godot Web exports are updated or re-exported without changing filenames, clients and CI runners do not permanently cache stale WASM or PCK binaries.

#### 3. CI & Local Artifact Hygiene

- Pre-test cleanup of stale `trace_*.zip`, `failure_*.png`, and `video_*.webm` in both shell scripts and the workflow
- GitHub Actions upload step now runs only on `if: failure()`, uploads only diagnostic artifacts, uses shard-specific naming (`test-failures-${{ matrix.artifact_suffix }}`), and retains them for 7 days
- Existing coverage, JUnit, Codecov, and metrics-baseline uploads left untouched

### Benefits

- Dramatically better failure debugging with traces + screenshots + video while keeping the artifacts directory clean on green runs
- Faster, more reliable loading of Godot web exports (correct WASM MIME, long-lived caching for binaries, revalidation for HTML)
- Reduced CI storage and noise from diagnostic artifacts
- Consistent asset-delivery behavior across local scripts, CI, nginx, and Docker

### Status Notes

Fully addresses the web-asset delivery and Playwright failure-diagnostics objectives of Task #844 / Epic #771.

---

## Reviewer's Guide

Enhances Playwright test failure diagnostics and optimizes web asset delivery across local, CI, and Docker environments by centralizing outcome-aware tracing/video/screenshot handling, refining pytest profiling, and tuning HTTP/nginx server behavior and GitHub Actions artifact handling.

### File-Level Changes

| Change                                                                                                                                  | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Files                                                                                                     |
|-----------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| Centralize Playwright failure diagnostics and outcome-aware artifact retention in pytest fixtures and hooks.                            | <ul><li>Introduce helpers to determine test/module failure, stop tracing, and finalize videos conditionally based on outcome.</li><li>Extend shared_page and page fixtures to start tracing, record videos, and route teardown through a unified diagnostics cleanup helper.</li><li>Track failed node IDs during setup/call and use them for module-scoped fixtures and profiling data.</li><li>Refactor test profiling recording into dedicated helpers that compute final outcome, aggregate durations, and update summary counts.</li><li>Adjust lifecycle metrics and soft UI reset fixtures to work with updated page fixture naming and teardown flows.</li></ul> | `tests/conftest.py`<br/>`tests/reset_audio_flow_test.py`                                                  |
| Improve CI/local web servers for Godot HTML5/WASM exports with correct MIME types, caching, and threading, and ensure artifact hygiene. | <ul><li>Replace simple HTTP handlers with OptimizedGodotHandler that registers application/wasm and applies differentiated Cache-Control policies.</li><li>Use threaded HTTP servers for browser tests in CI and local scripts, preserving COOP/COEP headers.</li><li>Clean up stale Playwright diagnostic artifacts (trace, failure screenshots, videos) before each browser test run.</li><li>Adjust pytest invocation in GitHub Actions to disable capture, use threaded timeouts, and run verbosely for browser tests.</li></ul>                                                                                                                                     | `.github/workflows/browser_test.yml`<br/>`workspace/run_pipeline.sh`<br/>`workspace/run_browser_tests.sh` |
| Tune nginx and Dockerized web service configuration for optimized and correct delivery of web assets.                                   | <ul><li>Update nginx config to register application/wasm, enable gzip (including wasm and JS), and add cache-control rules per asset type via location blocks.</li><li>Switch docker-compose nginx web volume to the thread-off export target directory and refresh copyright metadata.</li></ul>                                                                                                                                                                                                                                                                                                                                                                        | `infra/nginx/default.conf`<br/>`infra/docker-compose.yml`                                                 |
| Document the web asset delivery and Playwright failure diagnostics milestone.                                                           | <ul><li>Add milestone documentation summarizing the PR’s purpose, technical changes, benefits, and AI/bot contributions.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | `files/docs/milestones/22/Part_8_Web_asset_delivery_playwright_failure_diagnostics.md`                    |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Addressed | Explanation |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/771 | Optimize Playwright web test execution and web asset delivery (MIME types, caching, compression, threaded servers) to improve runtime and resource efficiency within the Epic #771 scope.                                                                                                                                                                                                                                                                                                                                                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/771 | Implement centralized, failure-only Playwright diagnostics (traces, screenshots, videos) via pytest fixtures and helpers, with deterministic teardown behavior for both module-scoped and function-scoped browser contexts.                                                                                                                                                                                                                                                                                                                                             | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/771 | Integrate failure-focused diagnostics and web delivery optimizations into CI and local workflows (GitHub Actions, shell scripts, Docker/nginx) including artifact cleanup, selective upload of failure artifacts, and consistent cross-origin isolation for Godot HTML5/WASM exports.                                                                                                                                                                                                                                                                                   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/844 | Configure local Python servers, nginx, and Dockerized web service for Godot HTML5 export assets with correct MIME types, caching headers, and compression (application/wasm for .wasm, Cache-Control public,max-age=3600 for .wasm/.pck/.js, no-cache,must-revalidate for .html, and gzip enabled in nginx).                                                                                                                                                                                                                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/844 | Implement conditional Playwright diagnostics in pytest fixtures: a unified teardown helper for page/shared_page that enables tracing and video on context creation, captures full-page failure screenshots before stopping tracing, closes the context before video retention/deletion, retains trace_*.zip/failure_*.png/video_*.webm only on failed tests (including module-scoped failures), discards diagnostics on passing runs, and preserves HAR recording for tests marked with @pytest.mark.record_har.                                                        | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/844 | Configure CI and local scripts for diagnostics and artifact handling: pre-run sweeps in run_browser_tests.sh, run_pipeline.sh, and the GitHub Actions workflow to purge stale trace_*, failure_*, video_* artifacts; adjust browser_test.yml to upload only failure diagnostics (trace_*.zip, failure_*.png, video_*.webm) gated by if: failure() while keeping coverage, Codecov, JUnit XML, and profiling uploads separate; and add documentation explaining the omission of the immutable Cache-Control directive and the conditional diagnostic retention strategy. | ✅        |             |

### Possibly linked issues

- **#844**: PR fulfills Task #844 by configuring headers, MIME, gzip, conditional Playwright traces/screenshots/videos, and CI artifact sweeps.

---

## PR #872 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review on the Playwright diagnostics and web-asset delivery changes.

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Conducted code review with feedback on the failure diagnostics, server caching, and artifact handling.

- **@deepsource-io**  
  Performed automated DeepSource Code Review, published a PR Report Card (Security / Reliability / Complexity / Hygiene), and left review comments.

- **@deepsource-autofix**  
  Authored multiple automated style/format commits (`style: format code with Black and isort`) to enforce Black + isort consistency across Python files.

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Implemented failure-only Playwright diagnostics (traces, screenshots, videos retained only on failure; cleaned on success), optimized local/CI HTTP servers and nginx for Godot web assets (WASM MIME type, differentiated Cache-Control, gzip), updated Docker Compose volume mounts, added pre-run artifact cleanup, and adjusted the GitHub Actions workflow to upload failure diagnostics only. Authored all substantive commits and iteratively refined the fixtures and server configuration.

---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
