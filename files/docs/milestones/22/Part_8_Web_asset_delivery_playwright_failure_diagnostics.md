# Web asset delivery Playwright failure diagnostics - #872
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
---

## PR #872 Summary: Web asset delivery & Playwright failure diagnostics

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `web-asset-delivery-playwright-failure-diagnostics` → `main`  
**Linked Issues:** Epic #771, Task #844 (Web Asset Delivery & Playwright Failure Diagnostics)  
**Labels:** testing, CI/CD, GitHub Actions, github_actions, refactoring, QA

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

| Change                                                                                                                                | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Files                                                                                                                                                                                           |
|---------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Centralize Playwright failure diagnostics and outcome-aware artifact retention in pytest hooks and fixtures.                          | <ul><li>Add helpers to determine test/module failure, stop tracing, and finalize videos conditionally based on test outcome.</li><li>Refactor pytest runtest reporting into _determine_final_outcome and _record_test_profiling to track failed node IDs and aggregate durations.</li><li>Update shared_page and page fixtures to start tracing, record video, and route teardown through a unified diagnostics cleanup helper.</li><li>Preserve lifecycle metrics and soft UI reset behavior while adapting to new page fixture naming and teardown flows.</li></ul>                                                | `tests/conftest.py`<br/>`tests/reset_audio_flow_test.py`                                                                                                                                        |
| Improve CI and local HTTP serving for Godot web exports with correct MIME types, caching, threading, and diagnostic artifact hygiene. | <ul><li>Introduce a reusable OptimizedGodotHandler + ThreadedHTTPServer script for serving web exports with COOP/COEP and tuned Cache-Control.</li><li>Replace inline Python HTTP server blocks in CI/local scripts with calls to the shared serve_web_export.py helper.</li><li>Add pre-run cleanup of Playwright trace, screenshot, and video artifacts in CI and local browser test scripts.</li><li>Adjust GitHub Actions browser_test workflow to install Playwright browser dependencies, disable pytest capture, use threaded timeouts, and upload only failure diagnostics with shorter retention.</li></ul> | `.github/scripts/serve_web_export.py`<br/>`.github/workflows/browser_test.yml`<br/>`workspace/run_pipeline.sh`<br/>`workspace/run_browser_tests.sh`<br/>`.github/workflows/test_ci_scripts.yml` |
| Tune nginx and Dockerized web service configuration for optimized, correct delivery of Godot HTML5/WASM assets.                       | <ul><li>Update nginx config to register application/wasm, enable gzip including wasm/JS/CSS/HTML/JSON, and add cache-control rules via asset-type-specific locations.</li><li>Change docker-compose nginx volume to point at the thread-off web export directory and update metadata.</li></ul>                                                                                                                                                                                                                                                                                                                      | `infra/nginx/default.conf`<br/>`infra/docker-compose.yml`                                                                                                                                       |
| Add unit tests for diagnostics and profiling helpers and document the milestone work.                                                 | <ul><li>Add tests validating metrics_baseline exporter behavior and the new profiling helper functions for final outcome and summary counts.</li><li>Introduce tests for the diagnostics cleanup helper to ensure correct retention/purging of traces, screenshots, and videos, including error paths and module-level failures.</li><li>Add milestone documentation summarizing web asset delivery and Playwright failure diagnostics scope, decisions, and linkage to Epic/Task issues.</li></ul>                                                                                                                  | `tests/ci/test_metrics_baseline.py`<br/>`tests/ci/test_conftest_diagnostics.py`<br/>`files/docs/milestones/22/Part_8_Web_asset_delivery_playwright_failure_diagnostics.md`                      |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                                                                                                         | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/771 | Optimize Playwright-based web test runtime and resource usage (including web asset delivery and diagnostics) to help achieve the Epic’s ~70% runtime reduction target without compromising reliability or coverage.                                                                                                                                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/771 | Improve deterministic, event-driven synchronization in browser tests to avoid arbitrary delays or race conditions during Godot HTML5/WASM initialization and UI interactions.                                                                                                                                                                                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/771 | Enhance CI browser-test orchestration with safe parallelization/sharding, robust HTTP serving of web exports, and failure-focused artifact handling that avoids unnecessary overhead and storage usage.                                                                                                                                                                           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/844 | Optimize web asset delivery for Godot HTML5 exports across Python local servers, Nginx, Docker/CI by configuring correct MIME types, cache-control headers, and compression, without regressing the established performance baseline.                                                                                                                                             | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/844 | Implement conditional Playwright diagnostics in pytest (for page and shared_page) and CI scripts/workflows so that traces, screenshots, and videos are retained only for failed tests (including module-scoped failures), HAR recording is preserved, stale artifacts are swept before runs, and CI uploads failure diagnostics separately from coverage/JUnit/profile artifacts. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/844 | Add documentation in the PR explaining the omission of the Cache-Control immutable directive and describing the conditional diagnostic retention strategy.                                                                                                                                                                                                                        | ✅        |             |

### Possibly linked issues

- **#844**: PR fulfills Task #844 by adding WASM headers, caching, gzip, conditional Playwright diagnostics, and failure-only CI artifacts.
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
