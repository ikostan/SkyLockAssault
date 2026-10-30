<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Centralize SFX cache diagnostics & add performance benchmarks

---

## PR #1094 Summary

**Title:** Centralize SFX cache insertion and add diagnostics  
**PR:** [#1094](https://github.com/ikostan/SkyLockAssault/pull/1094)  
**Branch:** `implement-public-diagnostic-helpers-for-sfx-core-and-decouple-test-suite` → `main`  
**Author:** @ikostan
**Resolves:**

- [#726 – [TASK] Implement Public Diagnostic Helpers for SFX Core and Decouple Test Suite](https://github.com/ikostan/SkyLockAssault/issues/726)
- [#1079 – [TASK] Performance Baseline: Capture Pre-Refactor Metrics (Part 1 of 2)](https://github.com/ikostan/SkyLockAssault/issues/1079)

**Related:** [#625 – Part 2 of 2](https://github.com/ikostan/SkyLockAssault/issues/625), [#1095 – GUT suites overwrite the real settings file](https://github.com/ikostan/SkyLockAssault/issues/1095)  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** testing, performance, refactoring, GUT, QA

### Purpose

Two pieces of groundwork before the Milestone 27 architecture refactor (#616–#621):

1. **#726:** give `SfxManager` a public diagnostic API, so the GUT suites stop reading its private cache and pool fields and the refactor can change those internals without breaking tests.
2. **#1079:** build a repeatable benchmark for desktop and web, record the pre-refactor baseline, and run it in CI, so Part 2 (#625) can measure what the refactor changed.

---

## Key Changes

### 1. SFX cache and diagnostics (#726) (`scripts/managers/sfx_manager.gd`)

- **One cache insertion path.** `play_sfx()` and the new test hook both go through `_store_in_cache()`, which evicts the least recently used entry when the cache is full and refreshes the recency of an existing key. Before, test seeding wrote to the cache directly and skipped eviction.
- **Read-only diagnostics:** `get_cached_sfx_count()`, `is_sfx_cached()`, `is_sfx_missing()`, `get_missing_sfx_count()`, `get_cached_sfx_names()` (LRU order) and `get_sfx_pool_players()` (returns a copy, so callers cannot change the pool).
- **Reset:** `clear_diagnostic_caches()` clears the cache and the missing-asset list.
- **Debug-only test hooks:** `cache_sfx_for_test()` and `clear_sfx_pool_for_test()` do nothing in release builds.
- **Cleanup split:** `cleanup_for_test()` is now `clear_diagnostic_caches()` + `_free_sfx_pool()` + `_initialize_sfx_pool()`.

### 2. GUT suites moved to the public API (#726) (`test/gut/`)

- `test_audio_sfx_centralization.gd`, `test_sfx_manager.gd`, `test_audio_settings_comprehensive.gd`, `test_audio_signal_decoupling.gd`, `test_volume_change_callers.gd` and `test_audio_constants_discoverability.gd` no longer touch `_sfx_cache`, `_missing_sfx` or `_sfx_pool`. No test cases were removed.
- **New suite `test_sfx_cache_diagnostics.gd`:** LRU ordering, eviction, recency refresh, missing-asset suppression, cache reset during playback, pool teardown and rebuild, and copy isolation of the returned pool.

### 3. Benchmark runner (#1079) (`test/benchmark/benchmark_runner.gd`, `.tscn`)

One run takes about 80 seconds and changes no gameplay code:

- **Fixed scenario:** difficulty 0.5, log level INFO, default volumes, 60 FPS cap on desktop. Every saved setting (`max_fuel`, `enable_debug_logging`, `show_fps` as well) is pinned, so a value in the player's settings file cannot change the run.
- **Gameplay:** loads `main_scene.tscn` directly, holds `speed_up` and fires continuously (a press event every frame; the weapon cooldown decides the shots). 5 s warm-up, then 60 s measured.
- **Reload loop:** loads and frees the scene 10 times and records orphans and the object count each time.
- **Metrics:** wall-clock frame interval every frame; once per second the worst `TIME_PROCESS` and `TIME_PHYSICS_PROCESS` of that second, FPS, static memory, object, node, resource and orphan counts, and settings saves.
- **Valid run:** fuel and ammo above 0 and the plane at max speed at the end.
- **Output:** `BENCH,...` console lines on every platform; CSV files on desktop. Samples are buffered and printed after the measured window, so the output does not affect the timings.
- **Settings safety (desktop):** backs up `settings.cfg` before the run and restores it after. It refuses to start if an old backup exists, aborts before changing anything if the backup fails, keeps the backup if the restore fails, and reports that run as failed (exit code 3).
- **1 s pause before quitting**, so the audio server releases the rotor sound playbacks; without it Godot reported them as leaked at exit.

### 4. Desktop runner (#1079) (`test/benchmark/run_desktop.py`)

- Runs the benchmark N times (default 3), checks each run, adds derived metrics (stutter counts, memory growth, reload object growth) and writes `runs.csv` and `medians.md`.
- **Returning-player start state:** moves the player's settings aside, creates a settings file with two short game launches, and copies it in before every run. `--fresh` starts without a settings file instead. The returning-player state is what exposes the reload leak.
- **Safety checks:** stops if a backup from an interrupted run exists, checks that both setup launches succeed, deletes old CSVs before each run, requires all four CSVs with data, and puts the player's settings back at the end. Git calls time out after 10 s.
- Standard library only; works natively on Windows and inside the project Docker image.

### 5. Web runner (#1079) (`test/benchmark/run_web.py`, `export_presets.cfg`, `project.godot`)

- **New `Web_benchmark` preset:** a copy of `Web_thread_off` that keeps `test/benchmark/` in the build and sets the `benchmark` feature tag. `run/main_scene.benchmark` opens the benchmark only in that build; the `Web` (itch.io) and `Web_thread_off` builds are unchanged.
- **One command:** exports the preset as a debug build, serves it locally, runs the benchmark N times in Chromium (Playwright), each in a fresh browser context, and writes the same CSVs, `runs.csv` and `medians.md` as the desktop runner.
- Headless with software rendering by default (like the browser tests); `--headed` uses a visible window and the GPU.
- The web build cannot write files, so the runner prints the per-frame intervals as one `BENCH,frames` line.

### 6. CI benchmark (#1079) (`.github/workflows/benchmark.yml`, `lint_test_deploy.yml`, `test/benchmark/compare.py`)

- **Two jobs in parallel** in the main pipeline (push to `main`, after the Ubuntu 24.04 tests): **Desktop** and **Web**. The web job downloads the export templates (checked against the release's SHA-512) and installs Playwright Chromium.
- **`compare.py`:** takes the median of the runs and compares it with a committed baseline (`baseline_ci.json`, `baseline_web_ci.json`). Count metrics (settings saves, objects, orphans, reload leak) **fail** the job when worse beyond a small tolerance; timing metrics only **warn**, because shared runners are noisy and have no GPU. The table goes to the run's Summary page; `--write-baseline` produces the next baseline file.
- **Not blocking deploys** until the game is playable.
- `benchmark.yml` is under the workflow policy tests (job and step timeouts).

### 7. Guide (`files/docs/Performance_Benchmark_Guide.md`)

Step-by-step instructions for desktop (native and Docker), web, and CI; output files; how to read the results; run-to-run variance; how to rerun for Part 2; design decisions; troubleshooting.

### 8. gdUnit4-coverage leftovers (`project.godot`)

The coverage plugin is no longer used. Its plugin entry was removed, and the leftover session hook and `[gdunit4_coverage]` section were removed with it (the hook points at a deleted addon and makes gdUnit4 fail loading it).

---

## Baseline Results (#1079)

Posted on #1079 ([full](https://github.com/ikostan/SkyLockAssault/issues/1079#issuecomment-6513724567), [short](https://github.com/ikostan/SkyLockAssault/issues/1079#issuecomment-6513753157)), with the raw CSVs attached. Medians of 3 valid runs:

| | Desktop (Docker, headless) | Web (Chromium, GPU) |
|---|---:|---:|
| Frame time avg | 16.7 ms (60 FPS) | 8.3 ms (120 FPS) |
| Frame time p95 | 17.7 ms | 10.2 ms |
| Dropped frames | 0 | 0 |
| Settings saves per minute | 61 | 60 |
| Objects (avg) | 2,542 | 2,287 |
| Orphan nodes | 0 | 0 |
| Reload loop object growth (10 reloads) | +9 | 0 |

**Main findings for the refactor:**

- The game saves `settings.cfg` about once per second during gameplay (the fuel value is mirrored into the settings).
- Desktop leaks 9 objects per 10 reloads when a settings file exists; it does not happen without one.

**Environment findings:**

- Native Windows runs were noisy (19–59 dropped frames per run); the same build in Docker was stutter-free. Docker is the primary desktop environment; Part 2 must use the same image and limits.
- Headless web runs (software rendering) vary too much for timings; the headed GPU run is the web baseline.

---

## Review Decisions

| Finding | Severity | Decision | Reason |
|---|---|---|---|
| CodeRabbit: the migrated tests call diagnostic APIs missing from `sfx_manager.gd` | Major | **Fixed** (`a786a11`) | Real: the first push of `sfx_manager.gd` lacked several methods the tests used. |
| CodeRabbit: keep the gdunit4_coverage plugin enabled in `project.godot` | Minor | **Declined**; leftovers removed (`d53d951`) | The plugin is no longer used. Removing only the plugin entry left a session hook pointing at a deleted addon, so the hook and settings section were removed too. |
| CodeRabbit: a saved `max_fuel` changes the scenario | Major | **Fixed** (`578b950`) | Real: `max_fuel` is a saved setting. All saved settings are now pinned. |
| CodeRabbit: settings backup and restore copies are not checked | Major | **Fixed** (`578b950`) | The run aborts before changing anything if the backup fails, and keeps the backup if the restore fails. |
| CodeRabbit: guide option table breaks the Markdown line limit | Major | **Fixed** | Table converted to a list. |
| CodeRabbit: require fresh, complete CSV output | Minor | **Fixed** (`b5a5185`) | Old CSVs are deleted before each run; all four must have data. |
| CodeRabbit: bound the git subprocess calls | Minor | **Fixed** (`b5a5185`) | 10 s timeout, reported as "unknown". |
| CodeRabbit: an existing backup makes the script delete the current settings | Major | **Fixed** (`b5a5185`) | The script stops instead. |
| CodeRabbit: a failed settings restore is reported as a valid run | Major | **Fixed** (`3421c33`) | Reported as invalid, exit code 3. |
| CodeRabbit: a failed setup launch can still produce the fixture | Minor | **Fixed** (`564f37c`) | Both launches must exit 0 and leave the settings file. |
| CodeRabbit: the runner backup from an earlier invocation is deleted | Major | **Fixed** (`564f37c`) | The script refuses to start while it exists and deletes only its own runs' backups. |
| DeepSource: docstring lines too long (4) | Minor | **Fixed** | Rewrapped to 79 characters. |
| DeepSource: process started with a partial executable path (2) | Minor | **Fixed** | `git` and Godot are resolved with `shutil.which`. |
| DeepSource: missing docstrings in `run_web.py` (2) | Minor | **Fixed** (`69767de`) | |
| Sourcery guide: #1079 harness "not addressed" because `TIME_PROCESS` is sampled per second | — | **Not a gap** | Godot updates `TIME_PROCESS` and `TIME_PHYSICS_PROCESS` once per second with the worst frame of that second, so per-frame values are not available. The runner records that per-second worst value and measures every frame with the wall-clock frame interval. The #1079 text still asks for per-frame `TIME_PROCESS`; see Follow-ups. |
| Sourcery guide: #1079 baseline "not recorded" | — | **Done after the guide** | The baseline and CSVs were posted on #1079. |

---

## Verification

- **Desktop benchmark:** 3/3 valid runs natively on Windows and in Docker; settings file byte-identical before and after (returning-player and `--fresh`).
- **Web benchmark:** 3/3 valid runs headless and 3/3 headed on Windows; 2/2 headless on Linux.
- **Safety paths tested:** a leftover backup makes `run_desktop.py` and `benchmark_runner.gd` stop without touching any file. A failed restore could not be forced in the test environment (root), so the exit-code-3 path was reviewed, not run.
- **`tests/ci`:** benchmark `compare.py` tests (10), workflow policy and runner pinning tests pass.
- **Lint:** gdlint and gdformat on the GDScript changes; black, isort and ruff on the Python; yamllint on the workflows; markdownlint-cli2 0.23.2 on the guide.
- **Not yet run:** the two CI benchmark jobs themselves; they run only from the main pipeline, so the first run is after this PR merges.

---

## Known Limitations / Follow-ups

- **CI baselines:** after the first `main` run, commit `baseline_ci.json` and `baseline_web_ci.json` from the `benchmark-results` and `benchmark-web-results` artifacts. Until then both jobs only report.
- **#1079 text** still asks for per-frame `TIME_PROCESS` / `TIME_PHYSICS_PROCESS`, which Godot does not provide; it should describe the per-second worst value plus the per-frame wall-clock interval.
- **Web start state differs from desktop:** web runs start without saved settings, so the reload leak does not show on web. Compare web with web only.
- **Web frame rate follows the monitor** (120 Hz on the baseline PC); Part 2 must use the same screen.
- **`inject_ci_flag.py`** replaces the feature tags of every preset with `ci`. It is not used by the benchmark job, but would remove the `benchmark` tag if it ever were.
- **#1095:** several GUT suites still overwrite or delete the real `user://settings.cfg` when run locally.
- **Docker image ID** is not recorded in the baseline comment.

---

## Reviewer's Guide (Sourcery)

*Based on Sourcery's guide, with the #1079 assessment corrected (see Review Decisions).*

The PR centralizes SFX cache insertion to make normal loading and test seeding share correct LRU eviction and recency behavior, adds controlled diagnostics and lifecycle test hooks, migrates audio tests away from private manager state with expanded regression coverage, and introduces documented desktop/web performance benchmarks with median-based CI comparison and artifact reporting.

### File-Level Changes

| Change                                                                                                                                                     | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
|------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Centralize SFX cache insertion and expose controlled diagnostics and test hooks while preserving LRU semantics and pool lifecycle behavior.                | <ul><li>Route normal playback and debug cache seeding through a shared insertion helper that evicts the least-recently-used entry and refreshes replacements.</li><li>Add read-only cache, missing-asset, pool, playback, and cache-reset APIs; add debug-only cache seeding and pool-clearing hooks.</li><li>Refactor cleanup to separate cache clearing, pool freeing, and pool reinitialization.</li></ul>                                                                                                                                                                                              | `scripts/managers/sfx_manager.gd`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Modernize audio regression coverage to exercise SfxManager through public black-box APIs and add comprehensive cache diagnostics tests.                    | <ul><li>Replace direct access to private cache, missing-entry, and pool fields with diagnostics, playback, and test-only APIs.</li><li>Cover LRU ordering, eviction, recency refresh, missing-asset suppression, cache reset during playback, pool teardown/rebuild, and returned-copy isolation.</li><li>Preserve coverage for playback overlap, player reuse, routing, freed-player resilience, and cleanup behavior.</li></ul>                                                                                                                                                                          | `test/gut/test_audio_constants_discoverability.gd`<br/>`test/gut/test_audio_settings_comprehensive.gd`<br/>`test/gut/test_audio_sfx_centralization.gd`<br/>`test/gut/test_audio_signal_decoupling.gd`<br/>`test/gut/test_sfx_cache_diagnostics.gd`<br/>`test/gut/test_sfx_manager.gd`<br/>`test/gut/test_volume_change_callers.gd`                                                                                                                                                                                  |
| Add a repeatable desktop and web performance benchmark harness with machine-readable results, median aggregation, baseline comparison, and CI integration. | <ul><li>Run a fixed gameplay, input, reload, object-count, memory, and settings-save scenario through desktop Godot or a Web benchmark export in Playwright Chromium.</li><li>Generate per-run CSVs, summaries, medians, and validated-run reports while backing up and restoring desktop settings.</li><li>Compare count metrics as CI failures and noisy timing metrics as warnings, with optional baseline generation and summary output.</li><li>Add a reusable, checksum-verified GitHub Actions workflow for parallel desktop and web benchmarks, artifacts, and workflow policy coverage.</li></ul> | `.github/workflows/benchmark.yml`<br/>`.github/workflows/lint_test_deploy.yml`<br/>`export_presets.cfg`<br/>`files/docs/Performance_Benchmark_Guide.md`<br/>`project.godot`<br/>`test/benchmark/benchmark_runner.gd`<br/>`test/benchmark/benchmark_runner.gd.uid`<br/>`test/benchmark/benchmark_runner.tscn`<br/>`test/benchmark/compare.py`<br/>`test/benchmark/run_desktop.py`<br/>`test/benchmark/run_web.py`<br/>`tests/ci/test_benchmark_compare.py`<br/>`tests/ci/test_workflow_policies.py`<br/>`.gitignore` |
| Record the PR in the Milestone 27 notes.                                                                                                                   | <ul><li>Add a summary of the changes, baseline results, review decisions, verification and contributors.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | `files/docs/milestones/27/Part_4_Centralize_SFX_cache_diagnostics_&_add_performance_benchmarks.md`                                                                                                                                                                                                                                                                                                                                                                                                                  |

### Assessment against linked issues

| Issue                                                   | Objective                                                                                                                                                                                                                    | Addressed | Explanation                                                                                                                                                                                                  |
|---------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/726>  | Expose the requested public SfxManager cache and missing-asset diagnostics, cache reset, and a debug-only cache seeding hook that shares play_sfx()'s LRU insertion and eviction behavior.                                   | ✅        |                                                                                                                                                                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/726>  | Refactor the in-scope GUT suites to avoid direct access to private SfxManager cache and pool fields, preserving coverage and using narrowly scoped test hooks where needed for otherwise-unexpressible pool lifecycle cases. | ✅        |                                                                                                                                                                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1079> | Provide a repeatable, runnable benchmark harness for the pinned gameplay scenario on desktop and web, including safe handling of settings and run validity checks.                                                           | ✅        | Sourcery marked this ❌ because `TIME_PROCESS` is sampled once per second. Godot only updates it once per second (worst frame of that second); per-frame timing is covered by the wall-clock frame interval. |
| <https://github.com/ikostan/SkyLockAssault/issues/1079> | Capture and publish the pre-refactor baseline with the commit, Godot version, environment details, median results, and raw CSV data.                                                                                         | ✅        | Posted on #1079 after the guide was generated, with both zips attached.                                                                                                                                      |

---

## Contributors

### Human contribution (@ikostan)

- Scoped #726 and #1079, decided to keep both on one PR, and chose the benchmark environments (Docker for desktop, GPU browser for web) and the CI policy (report only until the game is playable).
- Ran every native, Docker and web benchmark, reported the stutter and leak warnings that led to the fixes, and recorded the baseline.
- Applied, reviewed and pushed the changes, and triaged every review comment.
- Notable commits by @ikostan:
  - `8164773` Centralize SFX cache updates and diagnostics
  - `a786a11` Expose SFX diagnostics and pool reset for tests
  - `8f9fd4a` Add gameplay performance benchmark harness
  - `9523c35` Add desktop benchmark runner and reports
  - `36d1832` Add desktop performance benchmark guide
  - `e181842` Prime returning-player benchmark settings
  - `e567214` Add benchmark comparison tooling
  - `b5a5185` Validate benchmark outputs and protect settings
  - `578b950` Make benchmark settings runs deterministic
  - `ed3ea2d` Add Playwright web benchmark runner

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Diagnosed the harness problems found while running it: held `fire` firing only once, double-parsed input events, `TIME_PROCESS` repeating per frame, the audio playbacks reported as leaked at exit, and the default-settings reset hiding the reload leak.
  - Found that the GUT suites re-encrypt or delete the real settings file and filed #1095.
  - Assessed and fixed the CodeRabbit and DeepSource findings, declined the gdunit4_coverage suggestion, and removed the plugin's leftovers.
  - Posted the baseline comments on #1079, fixed the self-references in #625 and linked the two issues.
  - Commits: `4de25a0` (diagnostics suite review fixes, pushed on request), `d53d951`, `e0be872`, `9855cf5`, `3421c33`, `564f37c`, `69767de`.

- **@coderabbitai**
  - Authored `9d509b3` Add regression tests for SFX cache diagnostics, eviction, and reset behavior (the base of `test_sfx_cache_diagnostics.gd`).
  - Posted 11 review comments (6 Major, 5 Minor): 10 fixed, 1 declined (keep the coverage plugin enabled).
  - Posted the PR walkthrough and summary comments.

- **@sourcery-ai**
  - Generated the PR summary and the Reviewer's Guide (on request); two of its #1079 assessments are corrected above.
  - Could not review the code: the weekly review budget was used up.

- **@deepsource-io**
  - Posted 8 review comments (docstring length, partial executable paths, missing docstrings); all fixed.
  - `deepsource-autofix[bot]` authored `f5fa86f` style: format code with Black and isort.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
