<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Persist only schema-backed settings & separate benchmark results

---

## PR #1098 Summary

**Title:** Persist only schema-backed settings  
**PR:** [#1098](https://github.com/ikostan/SkyLockAssault/pull/1098)  
**Branch:** `architect-review-region-1-core-architecture` → `main`  
**Author:** @ikostan
**Resolves:**

- [#616 – [ARCHITECT-REVIEW] Region 1: Core Architecture & Global State Evaluation](https://github.com/ikostan/SkyLockAssault/issues/616)

**Related:** [#1079 – Performance Baseline (Part 1 of 2)](https://github.com/ikostan/SkyLockAssault/issues/1079), [#617 – Region 2: Custom Resources & Persistence Security](https://github.com/ikostan/SkyLockAssault/issues/617), follow-ups [#1100](https://github.com/ikostan/SkyLockAssault/issues/1100)–[#1105](https://github.com/ikostan/SkyLockAssault/issues/1105), [#1099 – Python lint in CI](https://github.com/ikostan/SkyLockAssault/issues/1099)  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** testing, refactoring, QA

### Purpose

The Region 1 review (#616) of `globals.gd`, `settings.gd` and `game_paths.gd` found one real bug: `Globals._on_setting_changed` saved `settings.cfg` for **every** `setting_changed` signal. The player mirrors `current_fuel` into the settings resource on every fuel tick, so during flight the game decrypted, re-encrypted and rewrote `settings.cfg` once per second (on the web, an IndexedDB sync each time), even though `current_fuel` is never written to the file.

This PR limits saves and logs to `persisted_schema` keys, closes the small #616 cleanups in the same file, fixes the benchmark counter that assumed every signal was a save, and gives benchmark results one folder layout. The larger refactors the review found are filed as #1100–#1105.

---

## Key Changes

### 1. Settings persistence (`scripts/core/globals.gd`)

- **Schema filter.** `_on_setting_changed` returns early, with no log and no save, for any key not in `persisted_schema`. Runtime state on the resource (`current_fuel`, speeds, thresholds) no longer touches the disk. Persisted keys (`current_log_level`, `difficulty`, `enable_debug_logging`, `max_fuel`, `show_fps`) still save immediately.
- **Clamp warning on load.** `difficulty` and `max_fuel` have no schema bounds and rely on the resource setters to clamp. `_load_settings` now compares the applied value with the disk value and logs a WARNING when a setter changed it. The clamping itself is unchanged.
- **Mockable JavaScript bridge.** The three `JavaScriptBridge.eval` calls go through `js_bridge_wrapper` (`JavaScriptBridgeWrapper`), like the menu scripts.
- **Dead check removed.** `Engine.is_editor_hint()` in `_ready()` could never be true there (the function already returned for the editor).
- **Docs.** The header lists what Globals owns today and the autoload order contract (Globals first; Settings and AudioManager call `Globals.safe_load_config()` in `_ready()`). `previous_scene` is documented as a test seam.

### 2. GUT coverage (`test/gut/`)

- **`test_globals_fuel_telemetry.gd`:** the three cases from Milestone 25 Part 2 asserted that `current_fuel` saves and logs (the source of the per-tick save). They were rewritten for the new contract, not removed: fuel causes no save and no log; bulk loading still suppresses side effects; after loading, only persisted keys save.
- **New `test_globals_setting_change_filter.gd`:** each persisted key saves once and logs exactly once; nine runtime properties and unknown names never save or log; the filter follows schema extensions; a simulated minute of fuel ticks through the real resource signals causes zero saves; a log-level change makes no bridge call on native builds. CodeRabbit added two cases for the benchmark counter: only persisted keys count, and only while measuring; the count follows schema extensions.
- **`test_globals_settings_serialization.gd`:** a clamped disk value (difficulty 8.0 → 2.0, −10.0 → 0.5, max_fuel 0.25 → 1.0) logs the WARNING with the exact text; in-range and int-to-float values log none. CodeRabbit added two cases: a value clamped to the boundary the setting already holds is still reported (the check does not depend on `setting_changed` firing), and the warning names the on-disk key when the schema uses an alias.

### 3. Benchmark save counter (`test/benchmark/benchmark_runner.gd`)

The runner counted every `setting_changed` signal as one save. After the fix the signals still fire every fuel tick but no longer save, so the counter now counts only `persisted_schema` keys, the same filter Globals uses.

### 4. Benchmark results layout (`test/benchmark/run_desktop.py`, `run_web.py`, `.github/workflows/benchmark.yml`)

- All runners default to `bench_results/<kind>/<name or timestamp>`, one folder per kind of run that is comparable: `desktop`, `docker` (detected through `/.dockerenv`), `web_headless`, `web_headed`.
- New `--name` option replaces the timestamp (e.g. `baseline`, `before_616`); `--out` still writes to any exact folder.
- Docker runs need no extra mount: the mounted project folder puts results in `bench_results/docker/` on the host.
- CI writes to `bench_results/ci/desktop` and `bench_results/ci/web`; artifact names are unchanged.
- **New `tests/ci/test_benchmark_output_paths.py`:** Docker detection, default folders per kind, `--name`, and `--out` precedence for both runners. CodeRabbit added: a relative `--out` is kept as given even with `--name`; `run_web.py --no-export --name` picks the headless folder without a Godot path; `--runs 0` and `-1` are still rejected when output options are given; an empty name falls back to a timestamp.

### 5. Documentation (`README.md`, `files/docs/Performance_Benchmark_Guide.md`)

- README: only `persisted_schema` keys are saved; the autoload order is a contract.
- Guide: the saves metric counts persisted-setting changes (expected 0 now, about 60 before #616); new "Where results go" section; all `C:/temp/bench` examples moved under `bench_results/`; web export templates added to the prerequisites; Step 4 shows the real Godot path and expected duration.
- Guide, Part 2 rerun: new "Running before and after" section. The "before" commit predates `--name`, so that run uses `--out` into this project's `bench_results/`; the Docker "before" command mounts that folder as `/results`.

---

## Benchmark Results

Same machine, Godot 4.7.1-stable, medians of 3 valid runs each.

**Desktop (Docker on WSL2, headless):** baseline `578b950` vs this PR at `8b98b32`

| Metric                               |          Baseline |        After #616 | Change |
|--------------------------------------|------------------:|------------------:|-------:|
| Physics, worst frame per second, avg |          2.053 ms |          0.812 ms |   −60% |
| Physics, worst frame per second, p95 |          3.921 ms |          1.132 ms |   −71% |
| Physics, worst frame per second, max |          6.280 ms |          1.340 ms |   −79% |
| Process, worst frame per second, avg |          0.482 ms |          0.431 ms |   −11% |
| Frame interval p95                   |          17.74 ms |          17.58 ms |   same |
| Objects / nodes / resources avg      | 2,543 / 503 / 206 | 2,543 / 503 / 206 |   same |
| Orphans / reload object growth       |            0 / +9 |            0 / +9 |   same |

`FuelTimer` runs on the physics callback, so the old once-per-second save landed inside a physics step and was that second's worst physics frame. "Settings saves" still read 61 in this run because it predates the counter fix (`33d86d6`).

**Web (Chromium, headless, software rendering):** Oct 29 run (before #616) vs `90b315a`

| Metric                     |  Before |   After | Change |
|----------------------------|--------:|--------:|-------:|
| Settings saves in 60 s     |      61 |   **0** |  −100% |
| Frame interval avg         | 21.8 ms | 18.1 ms |   −17% |
| Dropped frames (> 33.4 ms) |     109 |      72 |   −34% |
| Objects avg                |   2,277 |   2,280 |   same |
| Orphans / reload growth    |   0 / 0 |   0 / 0 |   same |

Headless web timings vary widely between runs (the Oct 29 runs alone spread 18–23 ms avg, 70–151 dropped frames), so only the counts are conclusive there. Against the committed CI web baseline, `compare.py --profile web` reports 0 count regressions (saves 60 → 0, nodes 516 → 501).

---

## Review Decisions

| Finding                                                                                                | Severity | Decision                          | Reason                                                                                                                                                                                                                                                                                                                                                 |
|--------------------------------------------------------------------------------------------------------|----------|-----------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Sourcery: runtime `current_fuel` remains on disk; remove all non-schema keys from `[Settings]` on save | Medium   | **Declined**                      | Only builds from Apr 6–9, 2026 (`5c393d1a`..`0f9350ac`) ever wrote `current_fuel`; no build since reads it, and this PR does not change `_save_settings`. Pruning non-schema keys would break the forward-compatibility contract tested by `test_save_preserves_other_managers_and_unknown_settings` (`[Settings] future_option` must survive a save). |
| Sourcery: remove `previous_scene` as #616 asked                                                        | Low      | **Declined**                      | `test_audio_settings_interaction.gd` blanks it so Back with an empty `hidden_menus` stack does not replace the GUT runner's scene. Documented as a test seam; the #616 description was updated to match.                                                                                                                                               |
| Sourcery: no test for the clamped-load warning                                                         | Low      | **Fixed** (`243c884`)             | The clamp tests had been left out of the first push; added to `test_globals_settings_serialization.gd`.                                                                                                                                                                                                                                                |
| Sourcery: `..._saves_and_logs_once` passes on duplicate logs                                           | Medium   | **Fixed** (`243c884`)             | Now also asserts `log_message` is called exactly once.                                                                                                                                                                                                                                                                                                 |
| DeepSource: missing docstrings in `test_benchmark_output_paths.py` (9)                                 | Minor    | **Fixed** (`34f17f5`)             | One-line docstrings on every test; DeepSource Python analysis passes on the PR head.                                                                                                                                                                                                                                                                   |
| CodeRabbit: the "before" worktree predates `--name`, so the Part 2 command fails                       | Major    | **Fixed**                         | Real: `--name` is added by this PR. The "before" run now uses `--out` (supported by the older runners).                                                                                                                                                                                                                                                |
| CodeRabbit: the Docker "before" `--out ../SkyLockAssault/...` path is outside the mount                | Major    | **Fixed**                         | Real: inside the container that path is outside `/project` and would vanish with `--rm`. The command now mounts this project's `bench_results/` as `/results` and writes to `/results/docker/before`.                                                                                                                                                  |
| Guide edits from `90b315a` overwritten by `bf334f7`                                                    | —        | **Fixed**                         | Found while fixing the CodeRabbit findings: the layout commit's guide was based on `main` and dropped the saves-metric, design-decision, prerequisites and Step 4 changes. Restored.                                                                                                                                                                   |
| #616 review: delete `previous_scene`; add schema `min`/`max` for `difficulty` and `max_fuel`           | —        | **Changed during implementation** | `previous_scene` is a test seam (above). Schema bounds would reject out-of-range disk values instead of clamping them, which `test_load_still_uses_resource_validation_for_unbounded_schema_fields` asserts; the clamp is kept and now logged instead.                                                                                                 |
| #616 review: debounce the difficulty slider                                                            | —        | **Deferred**                      | With the filter, a slider drag costs a few saves only while the menu is open. Debouncing needs flush points on web (closing a tab never sends `WM_CLOSE`).                                                                                                                                                                                             |

---

## Verification

- **GUT:** 834/834 locally on Godot 4.7.1 (822 before + 12 new, 4 of them from CodeRabbit) and in CI.
- **gdUnit4:** 155/155 locally and in CI.
- **CI on `34f17f5`:** all checks green: GUT, GDUnit4, GDScript lint and format, YAML and Markdown lint, CI/CD infrastructure tests, and all browser shards (Build Web Artifact, Core Web Flows, CI & Security, Refactor Suite).
- **`tests/ci`:** benchmark output path tests 23/23 (15 + 8 cases from CodeRabbit), plus the compare, workflow policy and runner pinning tests, pass.
- **Benchmarks:** desktop (Docker) 3/3 valid; web headless 3/3 valid, with 0 settings saves; one real desktop run confirmed the new `bench_results/desktop/<name>/` folder.
- **Lint:** gdlint and gdformat on the GDScript; black, isort and ruff on the Python; yamllint on the workflow; markdownlint-cli2 on the guide.

---

## Known Limitations / Follow-ups

- **CI benchmark baselines** still expect 61 (desktop) and 60 (web) saves. `compare.py` reports 0 as 🟢 better, so nothing fails, but refresh `baseline_ci.json` and `baseline_web_ci.json` from the first `main` run after this merge.
- **Desktop saves = 0 not yet measured.** The Docker run above predates the counter fix; rerun it to record 0.
- **Web timing comparison:** rerun with `--headed` on the 120 Hz screen and compare with the headed baseline (`web_20261029_193600`); headless runs only prove the counts.
- **The desktop A/B baseline (`578b950`) is 20 commits behind this PR** (mostly benchmark and CI tooling). For the Part 2 report, rerun the baseline on `d176f86`, this PR's direct parent.
- **Difficulty slider debounce:** deferred (see Review Decisions).
- **#617:** a failed decrypt deletes the whole `settings.cfg` (bindings and audio too), and rotating `PRODUCTION_SALT` would trigger that for every web player. Documented there with a proposed fix.
- **#1095:** GUT suites still overwrite or delete the real `user://settings.cfg` when run locally.
- **#1100–#1105 (Milestone 29):** MenuStack, Settings owns its state, Bindings API, SettingsStore (single decrypt at boot), Log/SceneLoader split, GamePaths adopt-or-remove.
- **#1099 (Milestone 28):** Python lint and format gate (ruff) in CI.

---

## Reviewer's Guide (Sourcery)

*Based on Sourcery's guide, which covered the first commit only; rows for the later commits were added.*

The PR makes settings persistence schema-driven: runtime-only changes no longer produce logs or encrypted disk writes, loaded values that are clamped now generate warnings, and browser bridge calls use a mockable wrapper. Documentation records the autoload ordering contract, while focused GUT regressions cover filtering, loading, signals, and native/web bridge behavior.

### File-Level Changes

| Change                                                                                                                                      | Details                                                                                                                                                                                                                                                                                                                                      | Files                                                                                                                                                                                                         |
|---------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Restrict settings side effects to schema-backed properties while preserving web synchronization and warning about clamped persisted values. | <ul><li>Return early for runtime-only or unknown setting notifications, avoiding logging and encrypted disk writes.</li><li>Continue mirroring log-level changes through the injectable JavaScript bridge on web builds.</li><li>Compare loaded values with post-setter values and emit warnings when resource setters clamp them.</li></ul> | `scripts/core/globals.gd`                                                                                                                                                                                     |
| Make JavaScript bridge access testable and clarify initialization dependencies.                                                             | <ul><li>Replace direct bridge calls with a mockable wrapper stored on the Globals autoload.</li><li>Document Globals-first autoload ordering and the persistence/runtime-state boundary.</li></ul>                                                                                                                                           | `scripts/core/globals.gd`<br/>`README.md`                                                                                                                                                                     |
| Add regression coverage for schema-driven persistence filtering and runtime behavior.                                                       | <ul><li>Verify persisted keys save and log once while runtime and unknown keys do neither.</li><li>Cover bulk-loading suppression, schema extensions, resource signal behavior, native bridge behavior, and the clamped-load warning.</li></ul>                                                                                              | `test/gut/test_globals_fuel_telemetry.gd`<br/>`test/gut/test_globals_setting_change_filter.gd`<br/>`test/gut/test_globals_setting_change_filter.gd.uid`<br/>`test/gut/test_globals_settings_serialization.gd` |
| Count only persisted settings saves in the benchmark.                                                                                       | <ul><li>Apply the same `persisted_schema` filter as Globals to the saves counter.</li><li>Unit-test the counter (measuring window, runtime and unknown keys, schema extensions).</li></ul>                                                                                                                                                   | `test/benchmark/benchmark_runner.gd`<br/>`test/gut/test_globals_setting_change_filter.gd`                                                                                                                     |
| Separate benchmark results by run type.                                                                                                     | <ul><li>Default to `bench_results/<kind>/<name or timestamp>` with Docker detection and a `--name` option.</li><li>Move CI results to `bench_results/ci/desktop` and `bench_results/ci/web`.</li><li>Cover default folders, naming and `--out` precedence.</li></ul>                                                                         | `test/benchmark/run_desktop.py`<br/>`test/benchmark/run_web.py`<br/>`.github/workflows/benchmark.yml`<br/>`tests/ci/test_benchmark_output_paths.py`                                                           |
| Update the benchmark guide.                                                                                                                 | <ul><li>Saves metric after #616, results layout, web templates prerequisite, updated examples.</li><li>Part 2 "before" runs use `--out`; Docker mounts the results folder.</li></ul>                                                                                                                                                         | `files/docs/Performance_Benchmark_Guide.md`                                                                                                                                                                   |
| Record the PR in the Milestone 27 notes.                                                                                                    | <ul><li>Summary of the changes, benchmark results, review decisions, verification and contributors.</li></ul>                                                                                                                                                                                                                                | `files/docs/milestones/27/Part_5_Persist_only_schema_backed_settings_&_separate_benchmark_results.md`                                                                                                         |

### Assessment against linked issues

| Issue                                                  | Objective                                                                                                                      | Addressed | Explanation                                                           |
|--------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/616> | Do not log or persist changes for keys outside `persisted_schema`.                                                             | ✅        |                                                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/616> | Remove the dead check, route bridge calls through the wrapper, warn on clamped loads, document Globals and the autoload order. | ✅        |                                                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/616> | Tests: fuel causes no save or log; persisted keys save once; a clamped disk value logs a WARNING.                              | ✅        | Clamp tests added in `243c884`.                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/616> | Keep `previous_scene` as a test seam and document it.                                                                          | ✅        | The issue originally asked to delete it; updated after review.        |
| <https://github.com/ikostan/SkyLockAssault/issues/616> | File and link the follow-up issues; write the milestone note; CI green.                                                        | ✅        | #1100–#1105 linked in #616; this note; all checks green on `34f17f5`. |

---

## Contributors

### Human contribution (@ikostan)

- Asked for the #616 review against the production code and comments, and flagged the proposed scope as too much work, which led to one small PR plus follow-up issues.
- Ran the Docker desktop and headless web benchmarks before and after the fix, and asked for one `bench_results/` layout for all result kinds.
- Spotted that the engine version in #616 was outdated (4.5, not 4.7.1) and asked about the other files in `scripts/core/` (`main_scene.gd` is reviewed in #620).
- Asked for Python static analysis after the DeepSource docstring findings (filed as #1099).
- Applied, reviewed and pushed all changes, and answered the Sourcery review threads.
- Commits by @ikostan:
  - `8b98b32` Persist only schema-backed settings
  - `33d86d6` Count only persisted settings saves
  - `90b315a` Update benchmark guide for persisted settings
  - `bf334f7` Separate benchmark results by run type
  - `243c884` Test settings clamp warning behavior
  - `34f17f5` Document benchmark output path tests

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Reviewed #616 and its comments against the production code at `d176f86`: confirmed every open checklist item, found that the save-on-every-change bug was a once-per-second encrypted write during flight, and found the unconditional `tree_exited` handler, the never-reassigned `previous_scene`, the `Globals.settings` write from `player.gd`, and the debug-export salt behaviour.
  - Rewrote the #616 description (scope, checkpoint answers, action items, deferred work), later added the `main_scene.gd` note, the `previous_scene` change and the follow-up links.
  - Posted the decrypt-wipe and salt-rotation finding on #617.
  - Compared the Docker and web benchmark results, traced the physics improvement to `FuelTimer` running on the physics callback, and found that the benchmark counted signals instead of saves.
  - Wrote the `bench_results/<kind>/<name>` layout, its tests and the guide updates.
  - Assessed the Sourcery, DeepSource and CodeRabbit findings: drafted the two declines (including the Apr 6–9 history check), and fixed the clamp test, the exact log count, the 9 docstrings and the two Part 2 rerun commands.
  - Reviewed CodeRabbit's added tests (`172eb14`) and ran them: GUT 834/834, output path tests 23/23.
  - Caused and then restored the guide edits lost in `bf334f7` (the layout version of the guide was built on `main`).
  - Filed #1099 and #1100–#1105.

- **@sourcery-ai**
  - Generated the PR summary and the Reviewer's Guide (first commit only; extended above).
  - Posted 4 review comments: 2 fixed, 2 declined. Resolved both declined threads after the replies.
  - Posted the #616 requirements checklist, which flagged the missing clamp test, the follow-up issues and this note.

- **@deepsource-io**
  - Posted 9 review comments (missing docstrings in `test_benchmark_output_paths.py`); all fixed. Python and JavaScript analysis pass on the PR head (grade A).
  - `deepsource-autofix[bot]` authored `3edd0ca` style: format code with Black and isort (CodeRabbit's new Python tests).

- **@coderabbitai**
  - Authored `172eb14` Add tests for benchmark save counting, output paths, and settings clamp warnings (on request): 4 GUT tests (benchmark counter ×2, clamp warning at the boundary, clamp warning with a disk alias) and 4 pytest tests (8 cases) for the output paths. Reviewed by @claude (Opus 5.5): all kept unchanged.
  - Posted the PR summary and walkthrough.
  - Posted 2 review comments on the guide's Part 2 rerun commands (both Major): `--name` does not exist in the "before" revision, and the Docker `--out` path was outside the mounted folder. Both fixed.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
