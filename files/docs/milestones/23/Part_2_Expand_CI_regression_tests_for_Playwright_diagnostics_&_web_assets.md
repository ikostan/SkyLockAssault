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

## Reviewer's Guide

Expands CI regression coverage around Playwright diagnostics, browser workflow and web asset delivery, while tightening reset-audio flow timing and updating CI/security workflows and milestone docs.

### File-Level Changes

| Change                                                                                                                                                                                                        | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Files                                                                                                                                                                                                                  |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Add structural tests for the browser_test GitHub Actions workflow to lock in server startup, artifact cleanup, pytest flags, and failure-only diagnostics upload behavior.                                    | <ul><li>Parse .github/workflows/browser_test.yml via PyYAML and expose test-shard steps via fixtures</li><li>Assert serve_web_export.py is used to start the security-isolated HTTP server on the thread-off export with a health check</li><li>Verify pre-run artifact directory creation and purge of trace_*, failure_*, and video_* diagnostics</li><li>Check sharded pytest invocation includes verbosity, no-capture, thread-based timeout, and JUnit XML output</li><li>Ensure diagnostics artifact upload runs only on failure with limited retention and excludes coverage JSON, and that the old always-run screenshot/coverage upload step is gone</li><li>Confirm unrelated always() artifact uploads (LCOV, test report, profiling baseline) remain unchanged</li></ul>                                                                                                                                                                                                                                                                                                                                 | `tests/ci/test_browser_test_workflow.py`                                                                                                                                                                               |
| Introduce structural tests for Docker Compose and Nginx infra configs to guard web export mounts, MIME types, cache policies, security headers, and port bindings.                                            | <ul><li>Load infra/docker-compose.yml via PyYAML and assert presence of godot_web_server service</li><li>Verify godot_web_server volume now mounts export/web_thread_off and no longer mounts export/web</li><li>Check nginx config directory volume remains mounted</li><li>Assert docker-compose copyright header text reflects the updated 2025-2026 range</li><li>Read infra/nginx/default.conf as raw text and sanity-check balanced braces</li><li>Assert application/wasm MIME registration and gzip/gzip_types configuration including wasm and common static asset types</li><li>Verify server-level COOP/COEP headers and per-location Cache-Control policies for wasm/js/pck, HTML, and root, plus root try_files behavior and listen 8080</li></ul>                                                                                                                                                                                                                                                                                                                                                      | `tests/ci/test_docker_compose_config.py`<br/>`tests/ci/test_nginx_config.py`                                                                                                                                           |
| Add a comprehensive unit test suite for Playwright diagnostics helpers and profiling logic in tests.conftest to validate failure detection, artifact handling, and summary accounting.                        | <ul><li>Isolate mutable conftest state per test via fixture that snapshots and restores ARTIFACTS_DIR, _FAILED_NODEIDS, _TEST_PROFILING_DATA, and _SUMMARY_COUNTS into a tmp directory</li><li>Exercise _is_test_failed across combinations of setup/call failures, module-level failures, and include_module_failures flag semantics</li><li>Validate _stop_tracing behavior for success vs failure paths and warning emission when tracing.stop raises</li><li>Verify _finalize_video behavior for None, success, and failure cases, including warnings on save/delete errors</li><li>Test _cleanup_context_diagnostics for failed and passing tests, handling of screenshot and context close failures, and module-scoped shared-page behavior choosing the correct failed nodeid</li><li>Cover _determine_final_outcome for all combinations of setup/call/teardown failed/skipped precedence</li><li>Cover _record_test_profiling aggregation of durations, outcomes, WASM boot time rounding, failed nodeid registration, skipped behavior, teardown failure handling, and cumulative summary counts</li></ul> | `tests/ci/test_playwright_diagnostics.py`                                                                                                                                                                              |
| Add CI tests and guards around the optimized web asset delivery server and pipeline scripts, including MIME, caching, isolation headers, threaded server settings, and shell-based artifact cleanup behavior. | <ul><li>Dynamically load OptimizedGodotHandler, ThreadedHTTPServer, and mimetypes from .github/scripts/serve_web_export.py and assert application/wasm MIME registration</li><li>Parametrically verify Cache-Control headers per asset type, including handling of query-string cache busters, and that COOP/COEP headers are set on responses</li><li>Ensure ThreadedHTTPServer uses daemon threads and allow_reuse_address for robust CI runs</li><li>Read workspace run_browser_tests.sh and run_pipeline.sh to assert they invoke serve_web_export.py</li><li>Extract and snapshot the artifact cleanup rm -f line to assert it targets trace_*.zip, failure_*.png, and video_*.webm and is guarded with \| \| true</li><li>Functionally execute the extracted cleanup line under bash against a temp artifacts directory to ensure only diagnostics are removed and other artifacts (junit.xml, metrics, coverage) remain, and that running the cleanup on an empty directory is a safe no-op</li></ul>                                                                                                         | `tests/ci/test_web_asset_delivery.py`                                                                                                                                                                                  |
| Add a regression test to ensure the reset-audio flow test keeps its timeout marker and harden the reset_audio_flow_test implementation and shared timeouts.                                                   | <ul><li>Introduce a small test module to introspect tests.reset_audio_flow_test.test_reset_flow and assert a pytest.mark.timeout marker is present with value 90 seconds and no kwargs</li><li>In reset_audio_flow_test, expand the pre-reload storage sync to first try GodotFS.sync and fall back to Module.FS.syncfs with a Promise-based wrapper when available, with warning logging on failure</li><li>Replace the fixed 500ms wait_for_timeout after sync with TEST_TIMEOUT-based wait, and narrow the post-reload console wait condition to the 'applied loaded' log only</li><li>Adjust a subsequent expect call to use DEFAULT_TIMEOUT instead of TEST_TIMEOUT for slider checks</li><li>Lower the default TEST_TIMEOUT from 15000ms to 10000ms in tests.test_utils while leaving DEFAULT_TIMEOUT unchanged</li></ul>                                                                                                                                                                                                                                                                                      | `tests/ci/test_reset_audio_flow_markers.py`<br/>`tests/reset_audio_flow_test.py`<br/>`tests/test_utils.py`                                                                                                             |
| Update CI workflows and documentation to support the new tests and keep security tooling pins current.                                                                                                        | <ul><li>Install pyyaml and pytest-timeout in the test_ci_scripts GitHub Actions workflow so the new CI tests can run</li><li>Refresh pinned github/codeql-action/upload-sarif SHAs in Snyk and Trivy workflows to a newer v3 commit for SARIF uploads</li><li>Add a milestone documentation file under files/docs/milestones/23 summarizing PR #877 purpose, core additions, benefits, and AI/bot vs human contributions</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `.github/workflows/test_ci_scripts.yml`<br/>`.github/workflows/snyk.yml`<br/>`.github/workflows/trivy.yml`<br/>`files/docs/milestones/23/Part_2_Expand_CI_regression_tests_for_Playwright_diagnostics_&_web_assets.md` |

### Possibly linked issues

- **#872**: The PR directly locks this issue’s web asset and conditional Playwright diagnostics behaviors into automated CI regression tests.

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
