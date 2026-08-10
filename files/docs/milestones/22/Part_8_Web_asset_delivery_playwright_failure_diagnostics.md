# Web asset delivery playwright failure diagnostics- #872
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
