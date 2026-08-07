# Test Profiling & Metrics Baseline (#776)
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## PR #870 Summary: Implement test profiling & metrics baseline

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `optimize-test-suite-runtime-and-prevent-ci-limit-exhaustion` → `main`  
**Linked Issues:** #776 ([TASK] Test Profiling & Metrics Baseline), Epic #771  
**Milestone:** Milestone 22 – Optimize Test Suite Runtime & Fix Loading Screen  
**Labels:** documentation, enhancement, web, testing, CI/CD, performance, refactoring, python, EPIC, QA

### Purpose

Establish automated profiling infrastructure and a statistical baseline for the Playwright E2E browser test suite. Capture per-test execution duration, overall session metrics, and Godot WASM initialization latency, then export a baseline JSON artifact. This provides the measurable starting point for Epic #771’s goal of ~70% runtime reduction and prevents CI limit exhaustion.

### Core Improvements

#### 1. Pytest Profiling Hooks (`tests/conftest.py`)

- Session-level timing globals and summary counters.
- `pytest_sessionstart` – records session start time and UTC timestamp.
- `pytest_runtest_makereport` (hookwrapper) – records per-test duration, outcome (aggregating setup/call/teardown phases), and optional WASM boot time.
- `pytest_sessionfinish` – computes total session duration, assembles metrics payload, writes `artifacts/metrics_baseline.json`, and cleans up tracked subprocesses.
- Enhanced `pytest_terminal_summary` – prints a human-readable profiling baseline summary alongside existing browser memory metrics.

#### 2. WASM Initialization Latency Helpers (`tests/test_utils.py`)

- Updated `init_page_and_wait_ready` to accept an optional `request`, measure time-to-ready with `time.perf_counter`, attach boot duration to `request.node`, and return the duration.
- New thin wrapper `navigate_and_profile_godot_wasm`.
- Updated `start_game_and_wait_ready` to forward the pytest request object so E2E setup tests automatically record boot time.

#### 3. CI Integration (`.github/workflows/browser_test.yml`)

- Copies `metrics_baseline.json` to a shard-specific artifact name using `matrix.artifact_suffix`.
- Uploads both the raw and shard-prefixed baseline JSON (14-day retention), always running regardless of test outcome.

#### 4. Local Scripts & Artifact Hygiene

- `workspace/run_browser_tests.sh` and `workspace/run_pipeline.sh` updated for consistent artifact preservation, non-fatal venv activation, clearer cleanup, and validation of required Python/Playwright tools.
- Coverage and report files are reliably moved into `artifacts/`.

#### 5. Documentation & Benchmark

- New milestone doc: `files/docs/milestones/22/Part_7_Test_Profiling_&_Metrics_Baseline.md`
  - Describes the profiling standard, KPIs, and role in Epic #771.
  - Includes a table of 5 profiling runs with timestamps and durations.
  - Derived statistics: min / max / mean / **median = 93.16 seconds**.
  - Target runtime post-optimization and deliverables checklist.
- Additional AI Models Summary Matrix documentation added/updated.

#### 6. Tests

- New coverage for metrics baseline export and WASM startup-time measurement (`tests/ci/test_metrics_baseline.py`, updates to `test_utils_test.py`).

### Benefits

- Provides a concrete, reproducible baseline for measuring future optimizations.
- Enables per-test and per-suite runtime tracking across CI shards.
- Captures Godot WASM boot latency as a first-class metric.
- Keeps the project root clean by centralizing all profiling/coverage artifacts.
- Directly supports the Epic #771 runtime-reduction goal.

### Baseline Result

**5-run median suite runtime: 93.16 seconds** (official starting point for optimization work).

---

## 🎯 Baseline Objectives & Key Performance Indicators (KPIs)

- **Profiling Infrastructure:** Centralized session timing, individual test durations, and outcome tracking exported directly to `artifacts/metrics_baseline.json`.
- **Execution Stability:** Verified 100% pass rate across 58 E2E and CI test cases with no flaky or race-dependent failures.
- **Deterministic Benchmark:** Executed 5 consecutive profiling runs in identical environment configurations to eliminate system scheduling noise and calculate a median execution baseline.

---

## 📊 5-Run Profiling Benchmark Results

| Profiling Run | Timestamp (UTC)      | Total Duration (sec) | Passed | Failed | Skipped |
|---------------|----------------------|----------------------|--------|--------|---------|
| Run 1         | 2026-08-06T03:07:32Z | 104.5763s            | 58     | 0      | 0       |
| Run 2         | 2026-08-06T03:12:48Z | 93.2269s             | 58     | 0      | 0       |
| Run 3         | 2026-08-06T03:16:32Z | 90.5947s             | 58     | 0      | 0       |
| Run 4         | 2026-08-06T03:19:31Z | 93.1585s             | 58     | 0      | 0       |
| Run 5         | 2026-08-06T03:23:48Z | 92.3970s             | 58     | 0      | 0       |
| Run 6         | 2026-08-07T03:26:26Z | 94.3200s             | 72     | 0      | 0       |

---

## 📈 Statistical Target Analysis

- **Minimum Duration:** `90.5947s`
- **Maximum Duration:** `104.5763s`
- **Mean (Average) Duration:** `94.7907s`
- **Official Median Baseline:** **`93.1585s`**
- **Epic #771 Target (~70% Reduction):** **`<= 27.95s`**

> **Note:** The median runtime of **`93.16s`** establishes our official pre-optimization benchmark. Sub-tasks under Epic `#771` must collectively reduce the median execution duration down to approximately **`27.95s`**.

---

## 🏆 Deliverables Checklist

- [x] Implemented `pytest_sessionstart`, `pytest_runtest_makereport`, and `pytest_sessionfinish` in `tests/conftest.py`.
- [x] Configured direct baseline JSON export to `artifacts/metrics_baseline.json`.
- [x] Integrated Playwright WASM initialization latency helper `navigate_and_profile_godot_wasm()` in `tests/test_utils.py`.
- [x] Updated `workspace/run_browser_tests.sh` and `workspace/run_pipeline.sh` to preserve profiling metrics.
- [x] Updated `.github/workflows/browser_test.yml` to preserve and upload sharded profiling baseline artifacts.
- [x] Conducted 5 consecutive profiling runs and recorded the official median baseline (`93.16s`).

---

## Reviewer's Guide

Introduces a pytest-based profiling infrastructure that records per-test and session-level metrics (including Godot WASM boot time), exports them as a metrics_baseline.json artifact, wires the artifact into CI and local scripts, and documents the new baseline and supporting AI model guidance, backed by targeted tests.

### File-Level Changes

| Change                                                                                                                                                    | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Files                                                                                                               |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| Add session-level profiling hooks and baseline JSON export to pytest and surface a human-readable summary in the terminal output.                         | <ul><li>Initialize global session state, per-test profiling storage, and summary counters for Task #776.</li><li>Implement pytest_sessionstart to capture suite start time and UTC timestamp.</li><li>Implement pytest_runtest_makereport hookwrapper to aggregate setup/call/teardown durations, compute final test outcome, and attach optional WASM boot timings.</li><li>Implement pytest_sessionfinish to compute total duration, serialize metrics (timestamp, summary counts, per-test records) to artifacts/metrics_baseline.json, and then terminate tracked subprocess PIDs.</li><li>Enhance pytest_terminal_summary to print the profiling baseline overview and confirm the metrics_baseline.json path alongside existing lifecycle memory metrics.</li><li>Add docstrings and minor typing tweaks to existing fixtures for clarity and consistency.</li></ul> | `tests/conftest.py`                                                                                                 |
| Measure and expose Godot WASM initialization latency through helper utilities and ensure E2E setup can record boot times.                                 | <ul><li>Extend init_page_and_wait_ready to accept an optional pytest request, measure boot time via time.perf_counter, attach the duration to request.node._wasm_boot_time, and return the value.</li><li>Introduce navigate_and_profile_godot_wasm as a thin wrapper around init_page_and_wait_ready for explicit profiling calls.</li><li>Update start_game_and_wait_ready to forward the pytest request so E2E setup captures WASM boot latency.</li><li>Add unit tests to validate boot-time measurement behavior and wrapper delegation, including already-initialized pages and None request handling.</li></ul>                                                                                                                                                                                                                                                     | `tests/test_utils.py`<br/>`tests/test_utils_test.py`                                                                |
| Add targeted tests for the metrics_baseline exporter and the pytest hook behavior to ensure schema and aggregation correctness.                           | <ul><li>Create a helper to invoke pytest_sessionfinish with controlled module state and a temporary artifacts directory.</li><li>Verify metrics_baseline.json is written with the expected top-level keys, summary counts, and per-test records matching the provided payload.</li><li>Ensure file I/O failures during metrics export raise a UserWarning without breaking the session.</li><li>Exercise pytest_runtest_makereport as a hookwrapper across setup/call/teardown phases to verify aggregated duration, outcome, and WASM boot time handling.</li></ul>                                                                                                                                                                                                                                                                                                       | `tests/ci/test_metrics_baseline.py`                                                                                 |
| Integrate metrics_baseline.json into the browser test CI workflow and ensure profiling artifacts are preserved per shard.                                 | <ul><li>Add a step that copies artifacts/metrics_baseline.json to a shard-specific filename using matrix.artifact_suffix when present.</li><li>Upload both the raw and shard-suffixed baseline JSON as a dedicated metrics-baseline artifact with 14-day retention, always running regardless of test outcome.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `.github/workflows/browser_test.yml`                                                                                |
| Improve local pipeline and browser test scripts to validate Python/Playwright availability and centralize coverage and report artifacts under artifacts/. | <ul><li>Reset and clean reports directories at pipeline start, and move stray coverage and reports into artifacts/ (including gdunit-reports) during cleanup.</li><li>Switch pytest invocations to python3 -m pytest and gate execution on presence of the venv activate script plus successful pytest/playwright import checks.</li><li>Adjust gdunit report handling so reports/ is moved into artifacts/gdunit-reports both in the pipeline and browser test scripts.</li><li>Update comments and copyright headers to reflect the new behavior and year range.</li></ul>                                                                                                                                                                                                                                                                                               | `workspace/run_pipeline.sh`<br/>`workspace/run_browser_tests.sh`                                                    |
| Relax GDUnit4 workflow assumptions about report location and upload consolidated report artifacts from both root and artifacts.                           | <ul><li>Update the step that finds the latest GDUnit report directory to search both reports/report_*and artifacts/gdunit-reports/report_*.</li><li>Expand the upload-artifact path configuration to include reports/**and artifacts/gdunit-reports/** with if-no-files-found set to ignore.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `.github/workflows/gdunit4_tests.yml`                                                                               |
| Add documentation describing the test profiling baseline, benchmark results, and local AI model recommendations for development workflows.                | <ul><li>Introduce a milestone document outlining the profiling infrastructure, KPIs, 5-run benchmark statistics (including the 93.16s median), and deliverables for Epic #771.</li><li>Add an AI Models Summary Matrix that recommends local LLM and image models, hardware fit, and installation order tailored to Godot, Python, and game-development tasks.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | `files/docs/milestones/22/Part_7_Test_Profiling_&_Metrics_Baseline.md`<br/>`files/docs/AI_Models_Summary_Matrix.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                          | Addressed | Explanation |
|------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| <https://github.com/ikostan/SkyLockAssault/issues/776> | Implement automated profiling infrastructure for Playwright E2E browser tests that captures per-test execution durations, overall session timing, and Godot WASM initialization latency, and exports these metrics as reproducible baseline artifacts (e.g., metrics_baseline.json in artifacts/). | ✅        |             |
| <https://github.com/ikostan/SkyLockAssault/issues/776> | Persist profiling outputs and baseline statistics (including multiple runs and median runtime) in version-controlled documentation and CI artifacts so they can be compared against future optimizations.                                                                                          | ✅        |             |
| <https://github.com/ikostan/SkyLockAssault/issues/776> | Integrate profiling into the CI/web test pipeline to help identify runtime bottlenecks such as browser initialization, WASM boot, and slow test flows, while preserving existing test behavior and coverage.                                                                                       | ✅        |             |

### Possibly linked issues

- **#776**: PR implements pytest hooks, WASM timing, CI artifacts, and docs to create the requested profiling baseline.

---

## PR #870 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review with suggestions (including adding tests for WASM boot-timing helpers and aligning the metrics baseline path between pytest export and CI).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Conducted code reviews with actionable feedback (e.g., aggregating pytest setup/call/teardown phases for accurate metrics, validating Python/Playwright availability in scripts, and improving artifact handling).

- **@deepsource-io**  
  Performed automated DeepSource Code Review, published a PR Report Card (Security / Reliability / Complexity / Hygiene), and left multiple review comments across commits.

- **@deepsource-autofix**  
  Authored multiple automated style/format commits (`style: format code with Black and isort`) to enforce Black + isort consistency.

- **@copilot** (GitHub Copilot)  
  Co-authored the commit that added tests for the metrics baseline exporter.

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Implemented the full test profiling & metrics baseline infrastructure (pytest hooks for per-test duration, session metrics, and Godot WASM initialization latency; export of `metrics_baseline.json` to `artifacts/`; CI artifact preservation/upload across shards; updates to `test_utils.py`, shell scripts, and workflow). Authored the milestone documentation (including 5-run benchmark results with a median of 93.16 s), added supporting tests, and iteratively addressed review feedback.

---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
