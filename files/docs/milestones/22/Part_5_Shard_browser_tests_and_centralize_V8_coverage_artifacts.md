# Shard browser tests and centralize V8 coverage artifacts
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## PR #859 Summary: Shard browser tests and centralize V8 coverage artifacts

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `parameterize-local-browser-test-runner-enable-native-headless-execution` → `main`  
**Linked Issues:** #854, #855, #856, #857, #858 (and related to #774 / Epic #771)  
**Milestone:** Milestone 22 – Optimize Test Suite Runtime & Fix Loading Screen  
**Labels:** enhancement, testing, CI/CD, github actions, github_actions, refactoring, QA

### Purpose

Restructure the Playwright browser E2E testing pipeline to reduce overall CI runtime, improve reliability, and centralize artifacts. The single long-running browser test job is split into a reusable web-build job plus parallel matrix shards, while V8 coverage, reports, and screenshots are standardized under an `artifacts/` directory for both CI and local runs.

### Core Improvements

#### 1. Sharded Browser Test Workflow (`.github/workflows/browser_test.yml`)

- Introduced dedicated **build-web** job that:
  - Performs the Godot web export once
  - Generates `export/web_thread_off/build_manifest.json` (contains `commit_sha` + `godot_version`)
  - Uploads the entire web build as a short-lived artifact (`godot-web-build`)
- Converted the test job into a **matrix of shards** (`fail-fast: false`):
  - Core Web Flows (`tests/*_test.py`)
  - Refactor Suite (`tests/refactor/*.py`, allow empty)
  - CI & Security (`tests/ci/*.py`)
- Each shard downloads the web-build artifact, validates the manifest SHA against `${{ github.sha }}`, runs only its suite, and uploads suite-scoped JUnit / LCOV / screenshots / coverage artifacts with distinct Codecov flags/names.
- Reduced per-shard timeout and improved coverage conversion (V8 → Istanbul → LCOV) to read from `artifacts/`.

#### 2. Centralized Artifacts & V8 Coverage

- New shared constants and helper in `tests/test_utils.py`:
  - `PROJECT_ROOT` / `ARTIFACTS_DIR`
  - `save_v8_coverage(cdp_session, test_name)` – collects precise V8 coverage via CDP, sanitizes filenames, writes `v8_coverage_*.json` into `artifacts/`, and handles falsy sessions / empty payloads / write errors gracefully.
- Updated fixtures (`tests/conftest.py`, `tests/ci/conftest.py`) so HAR files, temp dirs, and coverage land under `artifacts/`.
- Added dedicated test suite `tests/ci/test_v8_coverage_utils.py` covering success paths, edge cases, and error handling.
- `.gitignore` updated to ignore `artifacts/`, coverage JSONs, and backup files.

#### 3. Local Browser Test Runner (`workspace/run_browser_tests.sh`)

- Added positional arguments: `TEST_TARGET` (default `tests/`) and `SUITE_NAME` (default `all`).
- Reuses existing web export when present (skips redundant Godot export).
- Switched to native Playwright headless execution (removed `xvfb-run`).
- Writes suite-scoped HTML + JUnit reports into `artifacts/`.
- Improved cleanup trap: moves stray coverage files, removes backups, propagates pytest exit code.

#### 4. Broader CI Hardening

- Standardized quoting, permissions, `persist-credentials: false`, and safer path/URL handling across:
  - `gut_tests.yml`, `gdunit4_tests.yml`
  - `deploy_to_itch.yml` (archive integrity, Butler verification, version injection)
  - `trivy.yml`, `codeql.yml`, `lint_test_deploy.yml`, `release_drafter.yml`, `stale.yml`
- Improved Godot binary download/verification and Codecov CLI usage in unit-test workflows.
- Refined `workspace/run_pipeline.sh` for web-server and pytest handling.

#### 5. Documentation

- Added / updated milestone documentation under `files/docs/milestones/22/` (including Part_5 for this work) with clearer formatting and links.

### Benefits

- Significantly lower wall-clock CI time via parallel shards and single web-build reuse.
- Stronger integrity guarantees (commit-SHA validation of web artifacts).
- Cleaner project root and consistent artifact layout for both CI and local development.
- More reliable coverage collection and reporting (per-suite flags, collision-free filenames).
- Improved maintainability and security posture of multiple GitHub Actions workflows.

### Status Notes

Fully addresses the linked sub-tasks for parameterizing the local runner, separating the web-build job, introducing matrix sharding, centralizing V8 coverage, and enabling merged coverage reporting.

---

## Reviewer's Guide

Restructures browser E2E testing around a reusable web build artifact and sharded Playwright suites, centralizes artifacts/ usage for coverage and reports (CI and local), and hardens Godot-related workflows and deployment with integrity checks and cleaner configuration.

### File-Level Changes

| Change                                                                                                                                                                                   | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Files                                                                                                                                                                                                                                                                                |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Split browser_test workflow into a dedicated web build artifact job and a sharded test matrix that consumes the artifact, with integrity validation and per-suite reporting/coverage.    | <ul><li>Rename single test job to build-web and reduce its timeout, keeping export/patch steps focused on producing export/web_thread_off.</li><li>Generate a build_manifest.json tying the web build to commit SHA and Godot version, and upload export/web_thread_off as a short-lived reusable artifact.</li><li>Introduce test-shard matrix with suite-specific test paths and artifact_suffix, wiring PW_TIMEOUT via env and enforcing allow_empty semantics for optional suites.</li><li>Download the web build artifact in test-shard, validate the manifest SHA against github.sha, then run pytest only on files matching the suite’s test_path, writing JUnit XML into artifacts/ and handling empty suites gracefully.</li><li>Adjust coverage conversion to read V8 coverage from artifacts/ (fallback to root), augment .nyc_output filenames with shard counters, and upload LCOV artifacts and test reports with suite-scoped names/flags to Codecov.</li><li>Standardize artifact uploads (JUnit, screenshots, coverage) per shard using artifacts/ and matrix.artifact_suffix-derived names.</li></ul>                                                                                                                                            | `.github/workflows/browser_test.yml`                                                                                                                                                                                                                                                 |
| Parameterize and harden the local browser test runner script to reuse existing web exports, run native headless Playwright without xvfb, and centralize artifacts and coverage handling. | <ul><li>Add positional arguments TEST_TARGET and SUITE_NAME with defaults (tests/ and all) to control which tests run and how artifacts are named.</li><li>Skip Godot web export if EXPORT_DIR/index.html already exists, otherwise perform a headless export; afterwards restore modified files defensively and purge temporary backups and root-level v8_coverage files.</li><li>Refine cleanup_server trap to also remove backup files and move stray v8_coverage_*.json into PROJECT_DIR/artifacts on exit.</li><li>Replace xvfb-run + pytest tests/ (with ignores) by direct pytest invocation on TEST_TARGET with HTML and JUnit reports written to artifacts/report_{SUITE_NAME}.{html,xml}.</li><li>Move coverage JSONs into artifacts/ after pytest, summarize results from the suite-scoped report XML, and propagate pytest’s exit code so failures correctly fail the script.</li></ul>                                                                                                                                                                                                                                                                                                                                                                | `workspace/run_browser_tests.sh`                                                                                                                                                                                                                                                     |
| Standardize Godot unit test workflows (GUT and GDUnit4) and deployment workflow for itch.io with safer configuration, integrity checks, and clearer CLI usage.                           | <ul><li>Normalize workflow_call inputs and permissions to quoted strings and disable checkout credential persistence across gut_tests and gdunit4_tests.</li><li>Refactor Godot binary download/verification into URL/ZIP_NAME variables, use the provided SHA256 for validation, and ensure binary is unzipped/moved via variable references.</li><li>Update GUT and GDUnit4 installation steps to use explicit URL variables and clean temporary addon directories, then run tests with more readable multi-line Godot invocations.</li><li>Add steps in gut_tests to locate latest report directory, list contents, upload gut-reports artifacts, and upload JUnit reports to Codecov via the CLI with explicit flags and name.</li><li>In deploy_to_itch, quote workflow inputs, reformat version injection sed operations for readability, tighten archive_directory safety checks, verify Web.zip integrity and absence of placeholder salt, cache and download Butler with integrity verification, and use environment variables for butler push arguments.</li><li>Use consistent quoted refs and parameters across auxiliary workflows (trivy, codeql, lint_test_deploy, release_drafter) for YAML robustness and security tooling integration.</li></ul> | `.github/workflows/gut_tests.yml`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/deploy_to_itch.yml`<br/>`.github/workflows/trivy.yml`<br/>`.github/workflows/codeql.yml`<br/>`.github/workflows/lint_test_deploy.yml`<br/>`.github/workflows/release_drafter.yml` |
| Centralize Playwright test artifacts and coverage collection under artifacts/, and add targeted tests for V8 coverage utilities and HAR recording behavior.                              | <ul><li>Introduce PROJECT_ROOT and ARTIFACTS_DIR in tests.test_utils and implement save_v8_coverage(cdp_session, test_name) to collect coverage via CDP, normalize test names, and write v8_coverage_*.json into artifacts/ with defensive error handling.</li><li>Update tests/ci/conftest.py repo_tmp fixture to create temporary directories under ARTIFACTS_DIR (instead of PROJECT_ROOT), yielding relative paths while keeping the project root clean.</li><li>In tests/conftest.py, add PROJECT_ROOT/ARTIFACTS_DIR setup and use ARTIFACTS_DIR for HAR file output in the page fixture when record_har is enabled.</li><li>Add tests/ci/test_v8_coverage_utils.py to cover save_v8_coverage behavior for falsy sessions, successful writes, empty payloads, CDP errors, file write errors, and filename sanitization using tmp_path and patching ARTIFACTS_DIR.</li><li>Update copyright year in tests/conftest.py and add a minimal docs stub file under files/docs/milestones/22/Part_5_.md for documentation structure.</li></ul>                                                                                                                                                                                                                        | `tests/test_utils.py`<br/>`tests/ci/conftest.py`<br/>`tests/conftest.py`<br/>`tests/ci/test_v8_coverage_utils.py`<br/>`files/docs/milestones/22/Part_5_.md`                                                                                                                          |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                       | Addressed | Explanation |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/774 | Configure GitHub Actions Playwright browser testing workflow to run sharded test suites via a matrix (with explicit per-suite path patterns and fail-fast: false) so tests execute concurrently on isolated workers.                                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/774 | Generate the Godot HTML5/WASM web build artifact once per pipeline run, upload/share it across test shards, and validate its integrity (e.g., commit SHA, Godot version) before each shard uses it.                                                                                             | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/774 | Update the local Playwright browser test runner script to use native headless execution (without xvfb/display server), parameterize test target/suite selection, and centralize artifact/coverage output handling.                                                                              | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/854 | Parameterize workspace/run_browser_tests.sh with positional arguments TEST_TARGET (defaulting to tests/) and SUITE_NAME (defaulting to all) for targeted sub-suite execution while preserving existing defaults.                                                                                | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/854 | Add logic in workspace/run_browser_tests.sh to reuse existing compiled web build artifacts in export/web_thread_off/ when present, skipping redundant Godot export steps.                                                                                                                       | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/854 | Remove xvfb-run from the local browser test runner, run pytest directly using native Playwright headless execution, and generate suite-scoped JUnit XML and HTML reports under artifacts/ with filenames incorporating SUITE_NAME.                                                              | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/855 | Refactor .github/workflows/browser_test.yml to separate Godot Web export into a dedicated build-web job that performs export, flattening, and security patching once per pipeline run, with downstream tests reusing the built artifact instead of rebuilding.                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/855 | Inject export/web_thread_off/build_manifest.json containing commit_sha (from ${{ github.sha }}) and godot_version, and upload export/web_thread_off as a pipeline artifact named godot-web-build via actions/upload-artifact@v7.                                                                | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/855 | Configure downstream test runner jobs to download the godot-web-build artifact and validate that build_manifest.json’s commit_sha matches ${{ github.sha }}, halting tests with a clear error message if the SHA does not match.                                                                | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/856 | Configure `.github/workflows/browser_test.yml` to partition Playwright E2E tests into three explicit matrix shards (Core Web Flows, Refactor Suite, CI & Security) with `fail-fast: false`, and run pytest against the matrix-selected `test_path` on parallel runners.                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/856 | Scope JUnit XML, LCOV coverage artifacts, screenshots/coverage JSON, and Codecov flags/names per shard using matrix-specific suffixes to avoid path overlap and artifact overwrites between shards.                                                                                             | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/856 | Ensure filesystem and coverage isolation for Playwright suites by centralizing test artifacts (JUnit, HTML reports, V8 coverage) under an artifacts directory and reading coverage from that location in CI and local runs.                                                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/857 | Refactor the web browser test CI workflow into a sharded pipeline (separate web build job + test matrix shards) to reduce overall runtime while keeping execution within GitHub Actions runner limits.                                                                                          | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/857 | Configure coverage collection and Codecov uploads so that coverage from the three Playwright suites (core, refactor, CI/security) is tagged and can be merged into a unified project coverage report.                                                                                           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/857 | Align local browser test runner and Playwright test utilities with the sharded CI setup by standardizing artifact storage (including V8 coverage) and enabling native headless execution without xvfb.                                                                                          | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/858 | Centralize Playwright V8 coverage outputs and related pytest artifacts so that coverage JSON files (v8_coverage_*.json) are written into the artifacts/ directory and CI coverage conversion workflows read from that location.                                                                 | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/858 | Update the local browser test runner (workspace/run_browser_tests.sh) teardown to keep the project root clean by deleting export_presets.cfg.bak, moving/removing transient v8_coverage_*.json files, and ensuring test-generated reports (HTML/XML) and coverage artifacts land in artifacts/. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/858 | Ensure repository configuration (e.g., .gitignore and related settings) protects against committing generated artifacts by ignoring artifacts/, v8_coverage_*.json, and backup files (*.bak).                                                                                                   | ✅        |             |

### Possibly linked issues

- **#Sub-Task 1/5**: PR implements the issue’s run_browser_tests.sh argument handling, export reuse, xvfb removal, and suite-scoped artifacts.
- **#TASK**: PR splits browser workflow into build+matrix shards, reuses validated web artifacts, and updates local runner to native headless.
- **#771**: PR adds web build artifacts, sharded Playwright suites, and native headless runner, directly advancing the epic’s runtime and CI goals.

---

## PR #859 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review with suggestions (including adding dedicated tests for the new `save_v8_coverage` helper and edge-case handling). Co-authored a commit updating `.github/workflows/trivy.yml`.

- **@coderabbitai**  
  Generated the PR summary and detailed walkthrough/poem. Conducted code reviews and co-authored a commit updating `.gitignore`.

- **@deepsource-io**  
  Performed automated DeepSource Code Review, published a PR Report Card (Security / Reliability / Complexity / Hygiene), and provided analyzer status for Python and JavaScript.

- **@deepsource-autofix**  
  Authored multiple automated style/format commits (`style: format code with Black and isort`) to enforce Black + isort consistency across Python files.

- **@copilot** (GitHub Copilot)  
  Co-authored commits related to JUnit artifact uploads and improvements to the web-test pipeline / reporting.

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Implemented the core changes: splitting the browser test workflow into a reusable `build-web` job + matrix-based test shards, centralizing V8 coverage and test artifacts under `artifacts/`, adding the `save_v8_coverage` utility + tests, parameterizing the local runner for native headless execution and suite targeting, hardening multiple CI workflows (GUT, GDUnit4, deploy, Trivy, CodeQL, etc.), and creating/updating milestone documentation. Authored the vast majority of commits and addressed review feedback.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
