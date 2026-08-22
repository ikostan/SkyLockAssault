# Expand CI regression tests for Playwright diagnostics and web assets
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

## PR #877 Summary: Expand CI regression tests for Playwright diagnostics and web assets

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Opened by:** @coderabbitai (unit-test generation requested by @ikostan)  
**Branch:** `coderabbitai/utg/e683743` → `main`  
**Related:** Follow-up to #872 (Web asset delivery & Playwright failure diagnostics); supports #776 profiling/metrics goals  
**Labels:** testing, CI/CD, QA (and related project board tracking)

### Purpose

Expand and stabilize CI regression coverage around Playwright failure diagnostics, browser-test workflow structure, web asset delivery (HTTP headers/caching/WASM MIME), Nginx and Docker Compose config, and reset-audio flow timeout protection—so the behaviors introduced in #872 (and related CI hygiene) are locked in by automated tests.

### Core Additions

#### 1. Browser workflow structure (`tests/ci/test_browser_test_workflow.py`)

- Parse `.github/workflows/browser_test.yml` via PyYAML
- Assert shard job serves the thread-off web export via `serve_web_export.py`
- Verify pre-run purge of stale `trace_*` / `failure_*` / `video_*` artifacts
- Check pytest flags (verbosity, no-capture, thread timeout, JUnit XML)
- Confirm failure-only diagnostic upload (`if: failure()`, limited retention) and that unconditional screenshot/coverage upload was removed

#### 2. Playwright diagnostics unit suite (`tests/ci/test_playwright_diagnostics.py`)

- Isolated conftest state + temp `ARTIFACTS_DIR`
- Cover `_is_test_failed`, `_stop_tracing`, `_finalize_video`, `_cleanup_context_diagnostics`
- Validate outcome aggregation (`_determine_final_outcome`) and profiling (`_record_test_profiling`), including later extensions for skipped and teardown-failure cases

#### 3. Web asset delivery (`tests/ci/test_web_asset_delivery.py`)

- Load `OptimizedGodotHandler` / `ThreadedHTTPServer` from the serve script
- Assert `application/wasm` MIME, Cache-Control by path type, COOP/COEP, query-string-safe classification
- Verify daemon threads / address reuse and diagnostic artifact cleanup lines in shell scripts

#### 4. Infra config guards

- **Docker Compose** (`test_docker_compose_config.py`): `godot_web_server` mounts `export/web_thread_off`; copyright year range
- **Nginx** (`test_nginx_config.py`): wasm MIME, gzip, COOP/COEP, Cache-Control locations, port 8080, structural sanity

#### 5. Reset-flow & timeouts

- Marker regression: `test_reset_flow` carries `@pytest.mark.timeout(90)` (`test_reset_audio_flow_markers.py`)
- Stabilize `reset_audio_flow_test.py` (FS sync fallback, `TEST_TIMEOUT`-based waits, tighter log matching)
- Adjust shared `TEST_TIMEOUT` default (10s) in `test_utils.py`

#### 6. CI / tooling support

- Install `pyyaml` and `pytest-timeout` in `test_ci_scripts` workflow
- Refresh CodeQL SARIF upload pins in Snyk/Trivy workflows (via Dependabot merge)
- Milestone doc scaffold under `files/docs/milestones/23/`

### Benefits

- Protects failure-only diagnostics, caching/MIME policy, and infra mounts from silent regression
- Makes profiling and diagnostic helper behavior unit-testable and isolated
- Reduces flakiness in audio reset flow and timeout handling
- Documents the CI expansion for Milestone tracking

### Origin

Opened by **@coderabbitai** as generated unit tests requested from the #872 discussion; substantially refined and stabilized by **@ikostan** with review input from **@sourcery-ai**, **@deepsource-io**, and formatting from **@deepsource-autofix**.

---



---

## PR #877 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@coderabbitai**  
  Primary author of the PR (opened as “CodeRabbit Generated Unit Tests”). Authored the initial generated regression suite covering Playwright diagnostics, browser workflow structure, web asset delivery, Nginx config, Docker Compose mounts, and reset-flow timeout markers. Assigned the PR and linked it back to the related diagnostics work in #872.

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review with feedback on brittle substring/regex structural assertions and suggestions to harden profiling coverage (skipped outcomes, teardown failures).

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@deepsource-autofix**  
  Authored multiple automated style/format commits (`style: format code with Black and isort`) throughout the PR lifecycle.

- **@dependabot**  
  Authored the `github/codeql-action/upload-sarif` pin bump commit (later merged into this branch).

### Human Contributor

- **@ikostan**  
  Requested the unit-test generation (from #872). Merged the Dependabot pin update, stabilized audio/reset-flow timing and synchronization, refined Playwright diagnostics and web-asset delivery tests, documented Nginx config tests, added milestone documentation, updated CI script workflow dependencies, and iteratively hardened the generated suite across many follow-up commits.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
