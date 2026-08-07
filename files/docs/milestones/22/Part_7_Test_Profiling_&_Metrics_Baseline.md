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

* **Profiling Infrastructure:** Centralized session timing, individual test durations, and outcome tracking exported directly to `artifacts/metrics_baseline.json`.
* **Execution Stability:** Verified 100% pass rate across 58 E2E and CI test cases with no flaky or race-dependent failures.
* **Deterministic Benchmark:** Executed 5 consecutive profiling runs in identical environment configurations to eliminate system scheduling noise and calculate a median execution baseline.

---

## 📊 5-Run Profiling Benchmark Results

| Profiling Run |   Timestamp (UTC)    | Total Duration (sec) | Passed | Failed | Skipped |
|:-------------:|:--------------------:|:--------------------:|:------:|:------:|:-------:|
|     Run 1     | 2026-08-06T03:07:32Z |      104.5763s       |   58   |   0    |    0    |
|     Run 2     | 2026-08-06T03:12:48Z |       93.2269s       |   58   |   0    |    0    |
|     Run 3     | 2026-08-06T03:16:32Z |       90.5947s       |   58   |   0    |    0    |
|     Run 4     | 2026-08-06T03:19:31Z |       93.1585s       |   58   |   0    |    0    |
|     Run 5     | 2026-08-06T03:23:48Z |       92.3970s       |   58   |   0    |    0    |

---

## 📈 Statistical Target Analysis

* **Minimum Duration:** `90.5947s`
* **Maximum Duration:** `104.5763s`
* **Mean (Average) Duration:** `94.7907s`
* **Official Median Baseline:** **`93.1585s`**
* **Epic #771 Target (~70% Reduction):** **`<= 27.95s`**

> **Note:** The median runtime of **`93.16s`** establishes our official pre-optimization benchmark. Sub-tasks under Epic `#771` must collectively reduce the median execution duration down to approximately **`27.95s`**.

---

## 🏆 Deliverables Checklist

* [x] Implemented `pytest_sessionstart`, `pytest_runtest_makereport`, and `pytest_sessionfinish` in `tests/conftest.py`.
* [x] Configured direct baseline JSON export to `artifacts/metrics_baseline.json`.
* [x] Integrated Playwright WASM initialization latency helper `navigate_and_profile_godot_wasm()` in `tests/test_utils.py`.
* [x] Updated `workspace/run_browser_tests.sh` and `workspace/run_pipeline.sh` to preserve profiling metrics.
* [x] Updated `.github/workflows/browser_test.yml` to preserve and upload sharded profiling baseline artifacts.
* [x] Conducted 5 consecutive profiling runs and recorded the official median baseline (`93.16s`).

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
