# Eliminate arbitrary synchronization delays in Integration & CI tests
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## PR #849 Summary

**Title:** Eliminate arbitrary synchronization delays in integration ci tests  
**Author:** @ikostan  
**Branch:** eliminate-arbitrary-synchronization-delays-in-integration-ci-tests → main  
**Linked Issue:** #846  
**Milestone:** Milestone 22 – Optimize Test Suite Runtime & Fix Loading Screen  
**Status:** Open (as of latest fetch)

### Overview

This PR removes brittle, arbitrary `time.sleep()`-style waits and ad-hoc polling from the Playwright-based browser E2E / integration test suite. It replaces them with deterministic, event-driven synchronization (console-log waits, window-state polling, and shared helper utilities). Supporting changes expose key Godot runtime state to the browser so tests can assert on live values instead of guessing timing.

### Key Changes

#### 1. Godot Web State Exposure (`scripts/core/globals.gd`)

- On web builds, set `window.godotInitialized` and `window.currentLogLevel` during `_ready()`.
- Special-case high-frequency `current_fuel` updates:
  - Push live value to `window.currentFuel` via `JavaScriptBridge`.
  - Log only when log level is `DEBUG`.
  - Skip disk persistence to avoid I/O spam.
- Mirror `current_log_level` changes to `window.currentLogLevel`.
- Guard bulk settings loading so persistence / logging / JS bridge calls are skipped during initialization.
- Use explicit `JSON.stringify` for safer JS bridge values and UTF-8 encodings for file writes.

#### 2. Shared Playwright Helpers (`tests/test_utils.py`)

New reusable utilities that centralize:

- CDP / V8 precise coverage session start
- Page load + Godot readiness wait
- Options / Audio menu navigation
- Log-level and difficulty configuration (with confirming console logs)
- Full “start game and wait ready” orchestration

These helpers eliminate duplicated navigation and wait logic across tests.

#### 3. New / Refactored E2E Tests

| Test                                       | Purpose                                                                                |
|--------------------------------------------|----------------------------------------------------------------------------------------|
| `difficulty_integration_test.py`           | Menu → difficulty 2.0 → gameplay → weapon-fire log verification                        |
| `fuel_depletion_test.py`                   | Difficulty 2.0 + live `window.currentFuel` sampling; asserts strict monotonic decrease |
| `log_level_test.py`                        | Cycle all log levels and assert `window.currentLogLevel` synchronization               |
| `weapon_firing_test.py`                    | Spacebar fire during gameplay; assert “firing with scaled cooldown” console log        |
| `reset_audio_flow_test.py`                 | Stronger reset + persistence log waits + explicit slider-value assertions              |
| `audio_flow_test.py` / `back_flow_test.py` | Migrated to shared helpers; improved failure artifacts                                 |

Legacy copies under `tests/refactor/` were removed to keep a single canonical suite.

#### 4. Documentation

- Updated Part 2 milestone notes with individual test execution timings.
- New Part 3 milestone document: “Eliminate arbitrary synchronization delays in Integration & CI tests”, including a full 13-test suite breakdown (total ~88 s, longest test ~17 s for fuel depletion).

### Benefits

- Far more reliable CI browser runs (no more flaky arbitrary delays).
- Clearer failure diagnostics (screenshots, console logs, HTML dumps, V8 coverage on failure).
- Reduced code duplication and improved maintainability of the E2E suite.
- Live state exposure enables precise assertions that were previously impossible.

### Test Suite Snapshot (from milestone docs)

- **Total duration:** ~88 seconds (13 tests, 0 failures in the recorded run)
- Fastest tests: ~2 s (load / no-error / clean-load)
- Longest test: fuel depletion (~17 s) – waits for real fuel-tick progression

### Related Labels

`enhancement` · `web` · `testing` · `menu` · `refactoring` · `python` · `js` · `QA`

---

By tracking the HTTP server `GET /index.html` request deltas, we can observe the exact execution window and duration of each browser test:

## ⏱️ Individual Test Execution Breakdown

| Test File                                                   | Start Time | End Time   | Approx. Duration |
|-------------------------------------------------------------|------------|------------|------------------|
| `tests/audio_flow_test.py`                                  | `19:16:01` | `19:16:06` | ~5.0s            |
| `tests/back_flow_test.py` *(includes 1 page reload)*        | `19:16:06` | `19:16:15` | ~9.0s            |
| `tests/difficulty_flow_test.py`                             | `19:16:15` | `19:16:24` | ~9.0s            |
| `tests/difficulty_integration_test.py`                      | `19:16:24` | `19:16:32` | ~8.0s            |
| `tests/fuel_depletion_test.py`                              | `19:16:32` | `19:16:49` | ~17.0s           |
| `tests/load_main_menu_test.py`                              | `19:16:49` | `19:16:51` | ~2.0s            |
| `tests/log_level_test.py`                                   | `19:16:51` | `19:16:55` | ~4.0s            |
| `tests/navigation_to_audio_test.py`                         | `19:16:55` | `19:17:00` | ~5.0s            |
| `tests/no_error_logs_test.py`                               | `19:17:00` | `19:17:02` | ~2.0s            |
| `tests/reset_audio_flow_test.py` *(includes 1 page reload)* | `19:17:02` | `19:17:12` | ~10.0s           |
| `tests/validate_clean_load_test.py`                         | `19:17:12` | `19:17:14` | ~2.0s            |
| `tests/volume_sliders_mutes_test.py`                        | `19:17:14` | `19:17:20` | ~6.0s            |
| `tests/weapon_firing_test.py`                               | `19:17:20` | `19:17:28` | ~8.0s            |

### Key Execution Highlights

* **Total Suite Duration:** **87.91 seconds** (13 passed, 0 failed).
* **Longest Test:** `tests/fuel_depletion_test.py` (~17.0s) due to waiting for dynamic fuel consumption ticks.
* **Fastest Tests:** `load_main_menu_test.py`, `no_error_logs_test.py`, and `validate_clean_load_test.py` (~2.0s each) which evaluate immediately upon engine initialization.

---



---

## PR #849 Summary: Bots / AI Contributions

**PR Title:** Eliminate arbitrary synchronization delays in integration ci tests  
**Link:** https://github.com/ikostan/SkyLockAssault/pull/849

### Bots & AI Contributors

The following bots/AI tools actively contributed to this PR (reviews, summaries, autofixes, and co-authored commits). Their GitHub handles are listed in the standard format so they appear correctly in the contributors list:

- **@sourcery-ai**  
  Generated the official PR summary (“Summary by Sourcery”), produced the Reviewer’s Guide (including sequence diagrams and file-level change analysis), performed code reviews, and left actionable feedback on issues such as duplicated web-initialization blocks and repeated CDP coverage setup/teardown patterns across the new Playwright tests.

- **@coderabbitai**  
  Generated the “Summary by CodeRabbit”, performed multiple code reviews, left maintainability/style comments (including docstring length and missing docstrings), co-authored several commits (e.g. updates to `tests/reset_audio_flow_test.py`, `tests/difficulty_integration_test.py`, and `tests/test_utils.py`), and provided pre-merge checks / finishing-touch suggestions.

- **@deepsource-io** (DeepSourceReview)  
  Ran DeepSource Code Review on the PR (multiple times as commits landed). Posted the overall PR Report Card (Security / Reliability / Complexity / Hygiene), analyzer status for Python & JavaScript, and linked to the full review on the DeepSource dashboard. Also left inline review comments on style, maintainability, and code-quality findings.

- **@deepsource-autofix** (DeepSource Autofix)  
  Automatically authored multiple style-only commits that applied Black + isort formatting fixes after human and other bot changes (e.g. commits `459847f`, `c12aee6`, `2db0adb`, `d8f462a`, `05d02d4`, `0ef65dc`, `eb8406e`).

- **@Copilot** (GitHub Copilot)  
  Co-authored the commit that initialized `cdp_session` / `coverage_started` defaults and moved `start_game_and_wait_ready` into the try block to prevent `UnboundLocalError` in the finally clause (`3180fc3`).

> Note: No `@dependabot` activity was present on this PR.

### Human Contributor

#### @ikostan

Primary author of the PR. Authored the vast majority of commits, including:

- Milestone documentation (Part 2 & Part 3) documenting the elimination of arbitrary synchronization delays and per-test execution timings.
- Core changes in `scripts/core/globals.gd` (web state exposure for `currentFuel` / `currentLogLevel`, guards against high-frequency fuel I/O & log spam, JSBridge synchronization).
- New deterministic Playwright E2E tests (`difficulty_integration_test.py`, `fuel_depletion_test.py`, `log_level_test.py`, `weapon_firing_test.py`).
- Shared test utilities (`tests/test_utils.py`) that replace brittle waits with deterministic polling / event-driven helpers.
- Refactors of existing audio / back-navigation flow tests and removal of legacy `tests/refactor/` duplicates.
- Ongoing iteration in response to bot feedback (style clean-ups, assertion tightening, CDP session safety, UTF-8 encoding, etc.).

Also managed labels, milestone assignment, project board status, and linked the related issue (#846).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
