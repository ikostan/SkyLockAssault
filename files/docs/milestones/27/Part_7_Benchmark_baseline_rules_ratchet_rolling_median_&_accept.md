<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Benchmark baseline rules: ratchet, rolling median & accept

---

## PR #1122 Summary

**Title:** Benchmark baseline rules in compare.py: ratchet, rolling median and accept  
**PR:** [#1122](https://github.com/ikostan/SkyLockAssault/pull/1122)  
**Branch:** `benchmark-baseline-rules-in-comparepy-ratchet-rolling-median-and-accept` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1109 – [TASK] Benchmark baseline rules in compare.py: ratchet, rolling median and accept](https://github.com/ikostan/SkyLockAssault/issues/1109)

**Related:** [#1107 – [EPIC] Automatic CI benchmark baselines](https://github.com/ikostan/SkyLockAssault/issues/1107) (sub-task 2), [#1110](https://github.com/ikostan/SkyLockAssault/issues/1110), [#1111](https://github.com/ikostan/SkyLockAssault/issues/1111), [#1121](https://github.com/ikostan/SkyLockAssault/pull/1121), [#1123](https://github.com/ikostan/SkyLockAssault/pull/1123)  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** documentation, enhancement, tools, testing, performance, dependencies, dependabot, QA

### Purpose

CI benchmark baselines only change by hand, so improvements are never locked in. This PR teaches `test/benchmark/compare.py` the rules the rest of #1107 runs on. It reads a baseline file that also holds recent run history, compares the new results, and writes an updated file.

The rules are plain Python, so each one is tested before any workflow uses it. No workflow calls the new options yet: `benchmark.yml` still compares against the committed version 1 files, which load with an empty history and behave as before. Task 4 (#1111) turns the rules on.

---

## Key Changes

### 1. Version 2 baseline file (`test/benchmark/compare.py`)

| Field        | Holds                                                                  |
|--------------|------------------------------------------------------------------------|
| `baseline`   | The count baselines the gate compares against.                         |
| `history`    | The last 5 passing runs: run ID, commit, date and every metric median. |
| `accepted`   | The last accept that raised a count, and what it raised.               |
| `seen_runs`  | The IDs of recorded runs, up to 500 (not in the issue; see below).     |

- A version 1 file is read as a baseline with empty history, so task 3 (#1110) can seed the branch from today's files.
- A seed file's `baseline` also holds timings and web objects and nodes. They are the reference only until the first passing run, and are then dropped.

### 2. The three rules

- **Count ratchet:** a passing run is added to `history`. If the last 3 runs all beat a count's baseline by more than its tolerance, the baseline drops to the worst of the 3. It never rises through this rule.
- **Rolling reference:** timings, plus web `objects_avg` and `nodes_avg`, compare against the median of up to 5 runs in `history`. They only warn, and web objects and nodes are never ratcheted.
- **Accept:** `--accept <id>` raises only the failing counts to this run's values and records the accept. Every other count stays on the ratchet.
- **Failing run:** an unaccepted count failure exits 1 and writes nothing, so the run is not added to `history`.

### 3. Command line and summary

- **New options:** `--update <path>`, `--accept <id>`, `--run-id <id>`, `--commit <sha>` and `--report-only`.
- **Unchanged:** `--results`, `--summary`, `--profile`, `--title`, `--write-baseline` and the default `--baseline` path.
- **Summary:** each moved baseline gets a line saying why:
  - `saves: 61 → 2 (3 runs past tolerance)`
  - `objects_avg: raised to 2,840 (accepted in #123)`
  - `objects_avg: raised to 2,840 (accepted in run 412)` for a manual accept
  - `saves: added at 61 (new metric)`

### 4. Safety checks beyond the issue

- **Malformed baselines exit 2:** missing or empty metrics, non-numeric values, `NaN` or oversized numbers, or a broken `history` or `seen_runs`.
- **`--update` refuses to reseed:** it exits 2 if the file is missing or holds no count baselines, so a bad file cannot reset the gate from the current run.
- **Re-runs change nothing:** a run ID in `seen_runs` adds no history and raises nothing, even after it leaves `history` or carries an accept.
- **Incomplete options are rejected:** `--update` needs `--run-id` and `--profile`, `--accept` needs `--update`, and IDs cannot be empty.

### 5. Tests (`tests/ci/test_benchmark_compare.py`)

- **Existing cases:** all 95 kept unchanged.
- **New:** 65 cases, for 160 in total. They cover each acceptance criterion, re-runs, malformed files, report-only behaviour and option validation.

### 6. Other files in this PR

- **Doc comments:** `audio_manager.gd`, `sfx_manager.gd` and `fuel_resource.gd`, from the weekly docs PR #1123 and later review edits. Comments only; no code lines changed.
- **`lint_readme.yml`:** Dependabot's bump from #1121 reached this branch and was reverted in `c8b984d`. The action pin matches `main` again, but one comment line was removed.

---

## Design Decisions

- **`--report-only` still writes the `--write-baseline` candidate.** The issue says "write nothing", but the measure jobs will run report-only, and the accept check in the design doc reads `commit` from that file in the results artifacts. It never updates the baseline: `--update` is rejected.
- **`--commit` was added.** A manual accept runs under a different `GITHUB_SHA` from the run it accepts, so history would otherwise record the wrong commit. It falls back to `GITHUB_SHA`.
- **`seen_runs` was added.** `history` keeps only 5 runs, so it cannot detect an older re-run. GitHub allows re-runs for up to 30 days, and 500 IDs covers far more merges than that.
- **A manual accept is named by matching IDs.** If `--accept` equals `--run-id`, the summary says `run <id>`; otherwise `#<id>`. #1111 must pass the failed run's ID to both on the manual path.
- **An unneeded accept keeps the last `accepted` record.** The run is still recorded, and the summary says the accept raised nothing.
- **A count missing from the baseline is added at this run's value,** so a new count starts being gated. The file must still hold at least one count baseline.
- **A recorded run with `--accept` exits 0 and changes nothing,** even if the table shows a failure. Without `--accept` it exits 1.

---

## Review Decisions

| Reviewer   | Finding                                               | Decision                                                                                                                               |
|------------|-------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| DeepSource | `update_baseline` complexity 20, `main` complexity 17 | **Fixed:** split into helpers. Identical results over 2,048 randomised runs, apart from timestamps and runner.                         |
| DeepSource | Keyword arguments before `*extra` in `update_run`     | **Fixed:** replaced with a named `accept` parameter.                                                                                   |
| Qodo       | Ratchet test could not catch stale history            | **Fixed:** the runs after the accept now beat the baseline. With a stale-history bug added, the new test fails and the old one passed. |
| Qodo       | Malformed baselines can reset count gates             | **Fixed:** reproduced, then rejected with exit 2.                                                                                      |
| Qodo       | An accepted re-run can raise the gate again           | **Fixed:** reproduced, then any recorded run changes nothing.                                                                          |
| Qodo       | Older re-runs can count twice in the ratchet          | **Fixed:** reproduced, then `seen_runs` added.                                                                                         |
| Qodo       | Oversized baseline numbers crash comparison           | **Fixed:** reproduced, then treated as an invalid metric (exit 2).                                                                     |
| Qodo       | `get_muted` doc comment repeats its summary           | **Fixed:** duplicate line removed.                                                                                                     |
| Sourcery   | Report-only writes the candidate                      | **Declined:** intentional, see Design Decisions.                                                                                       |
| Sourcery   | Workflow changed in a Python-only PR                  | **Fixed in part:** bump reverted; one removed comment remains (see Follow-ups).                                                        |

---

## Verification

- **Tests:** `pytest tests/ci/test_benchmark_compare.py` gives 160 passed.
- **Test strength:** breaking each key rule on purpose makes the tests fail: worst-of-3, the run count, the tolerance, the history size, the failing-run block, re-run handling and the file checks.
- **Python style:** `ruff check` and `ruff format` clean with the repo's settings.
- **`compare.py` complexity (`radon`):** `main` 7, `update_baseline` 4, highest `render` at 14 and `compare` at 11.
- **Doc comment files:** no non-comment lines changed in the three `.gd` files.
- **Still to confirm:** `pytest tests/ci/` and all PR checks on the final commit. Locally the full suite cannot finish because `gdtoolkit` is missing; `test_injection_readonly_file` also fails locally, with the same counts on clean `main`. CodeRabbit reported GUT and CI injection checks skipped on timeout during its review.

---

## Known Limitations / Follow-ups

- **Scope of #1109:** it says "Python only" and "no workflow files". To meet that, restore `# Pinned to SHA for security (was @v19)` in `lint_readme.yml`, and either move the `.gd` comment changes to their own PR or change the wording.
- **Issue wording:** update #1109 for `--commit`, `seen_runs`, exit 2 and the report-only candidate.
- **Markdownlint bump:** v25.0.0 is not on `main`. #1121 was merged into this branch rather than `main`, so the bump needs a new PR. The `dependencies` and `dependabot` labels no longer apply here.
- **PR description:** still the unedited template, which CodeRabbit's description check flagged.
- **#1111 must:**
  - pass `--commit` with the selected run's SHA on the manual path;
  - pass the failed run's ID to both `--accept` and `--run-id` there;
  - treat exit 2 as a setup failure, not a regression;
  - keep `--write-baseline` in the report-only measure jobs.
- **Design doc:** `Automatic_Benchmark_Baselines.md` still says the rules arrive with this issue and that `compare.py` judges every metric against the committed file. It also does not describe `seen_runs` or exit 2.
- **Task 6 (#1113):** removes the default `--baseline` path and the committed files, and must rewrite the tests that read them.

---

## Reviewer's Guide

### File-Level Changes

| Change                          | Details                                                                                                                                                                | Files                                                                                                              |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| Baseline rules and file format. | <ul><li>Version 1 and 2 loading with validation.</li><li>Ratchet, rolling median, accept and re-run handling.</li><li>New options, exit 2 and summary lines.</li></ul> | `test/benchmark/compare.py`                                                                                        |
| Tests for every rule.           | <ul><li>Existing cases kept.</li><li>New helpers `write_history_file` and `update_run`.</li></ul>                                                                      | `tests/ci/test_benchmark_compare.py`                                                                               |
| Doc comment rewrite (no code).  | <ul><li>`:param` tags to `[param]`.</li><li>Clarified audio and SFX behaviour.</li></ul>                                                                               | `scripts/managers/audio_manager.gd`<br/>`scripts/managers/sfx_manager.gd`<br/>`scripts/resources/fuel_resource.gd` |
| Workflow comment removed.       | <ul><li>Left over from reverting the Dependabot bump.</li></ul>                                                                                                        | `.github/workflows/lint_readme.yml`                                                                                |

### Assessment against linked issues

| Issue                                                   | Objective                                                 | Addressed | Explanation                                                                      |
|---------------------------------------------------------|-----------------------------------------------------------|-----------|----------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Version 2 file; version 1 loads with empty history        | ✅        | `load_baseline`.                                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Ratchet only after 3 runs past tolerance; never rises     | ✅        | `ratchet_count`.                                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Timings use the median of up to 5 runs and only warn      | ✅        | `build_reference`.                                                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Unaccepted failure leaves the file unchanged and exits 1  | ✅        | The update path is skipped.                                                      |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Accept raises only failing counts                         | ✅        | `apply_accept`.                                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | CLI options; report-only never exits 1 and writes nothing | 🟡        | Never updates the baseline, but writes the candidate on purpose.                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | A reason for each baseline that moves                     | ✅        | Summary lines.                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Default `--baseline` path stays until task 6              | ✅        | `DEFAULT_BASELINE`.                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Tests cover the listed cases; existing cases kept         | ✅        | No lines removed from the test file.                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | `pytest tests/ci/` passes                                 | ⏳        | Confirmed by CI on the final commit.                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Python only; no workflow files change                     | ❌        | One workflow comment and three `.gd` comment-only files remain (see Follow-ups). |

---

## Contributors

### Human contribution (@ikostan)

- Picked up #1109, applied all code to the PR branch, and brought every CI failure and every DeepSource, Qodo and Sourcery finding back for assessment.
- Merged Dependabot's #1121 and the weekly docs PR #1123 into the branch, reviewed the doc comments, and reverted the markdownlint bump.
- Commits by @ikostan:
  - `12031c4` Add rolling benchmark baseline updates
  - `cae5c9a` Merge pull request #1121
  - `4dc1ab3` Clarify audio manager volume behavior docs
  - `b956413` Clarify active SFX lookup ordering
  - `ae8cf34` Clarify audio mute and config behavior
  - `82ed5c2` Update sfx_manager.gd
  - `db567b0` Merge pull request #1123
  - `e3d1a4c` Refactor benchmark baseline updates
  - `7c5b7b0` Support --accept in benchmark update tests
  - `e4789b5` Update test_benchmark_compare.py
  - `723e299` Test baseline ratchet after acceptance
  - `3a77de2` Remove duplicate audio manager docstring
  - `efbb4b4` Harden benchmark baseline updates
  - `c8b984d` Update markdownlint action pin
  - `af0ccef` Handle oversized benchmark metrics

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Rules and format**
    - Wrote the version 2 format, ratchet, rolling reference, accept rule, new options and summary lines from #1109 and the design doc.
    - Found that "report-only writes nothing" conflicts with the accept check, and that a manual accept needs `--commit`.
    - Added the re-run check, the missing-file check and the option validation.
  - **Tests**
    - Wrote the 65 new cases and checked them by breaking each key rule on purpose.
  - **Review findings**
    - Split `update_baseline` and `main` for DeepSource and compared old and new code over 2,048 randomised runs.
    - Reproduced each Qodo bug in `compare.py` before fixing it (malformed file, accepted re-run, older re-run, oversized number) and strengthened the post-accept ratchet test.
    - Traced the workflow change to Dependabot's `1957ed9` and checked which `.gd` changes were comments only.

- **@sourcery-ai**
  - Posted the PR summary and Reviewer's Guide, with 2 inline comments: report-only (declined) and the workflow change (fixed in part).
  - Posted the #1109 requirements check (9 of 12 met, 1 by hand, 1 partly met, 1 not addressed).
  - Skipped one review because the review budget was used up.

- **@qodo-code-review**
  - Posted 6 findings, all fixed: 4 bugs in `compare.py`, 1 weak test, 1 duplicate doc comment.

- **@deepsource-io**
  - Python and JavaScript analysis pass (grade A), with 3 inline comments, all fixed.

- **@coderabbitai**
  - Posted the walkthrough with no actionable comments, rated merge risk minimal, and flagged the unedited PR description.

- **@dependabot**
  - Authored `1957ed9` Bump DavidAnson/markdownlint-cli2-action from 24.2.0 to 25.0.0 (#1121), later reverted on this branch.

- **@github-actions**
  - Committed `6faa5a3` docs(gdscript): update and enhance Native BBCode docstrings, from the weekly docs automation (#1123).

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
