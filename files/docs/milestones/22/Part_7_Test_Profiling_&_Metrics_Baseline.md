# Test Profiling & Metrics Baseline (#776)
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## 📋 Overview

Task **#776** establishes the official profiling standard, automated timing infrastructure, and statistical baseline for the Playwright E2E browser test suite running against the Godot Web export (`Web_thread_off`). This baseline serves as the official measurement benchmark for tracking progress toward Epic **#771's ~70% runtime reduction goal**.

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

- [x] Implemented `pytest_sessionstart`, `pytest_runtest_makereport`, and `pytest_sessionfinish` in `tests/conftest.py`.
- [x] Configured direct baseline JSON export to `artifacts/metrics_baseline.json`.
- [x] Integrated Playwright WASM initialization latency helper `navigate_and_profile_godot_wasm()` in `tests/test_utils.py`.
- [x] Updated `workspace/run_browser_tests.sh` and `workspace/run_pipeline.sh` to preserve profiling metrics.
- [x] Updated `.github/workflows/browser_test.yml` to preserve and upload sharded profiling baseline artifacts.
- [x] Conducted 5 consecutive profiling runs and recorded the official median baseline (`93.16s`).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
