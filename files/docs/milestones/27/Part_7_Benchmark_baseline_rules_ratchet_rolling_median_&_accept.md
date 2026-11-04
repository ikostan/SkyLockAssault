<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Benchmark baseline rules: ratchet, rolling median & accept

---

## PR #1122 Summary

**Title:** Benchmark baseline rules in compare.py: ratchet, rolling median and accept  
**PR:** [#1122](https://github.com/ikostan/SkyLockAssault/pull/1122)  
**Branch:** `benchmark-baseline-rules-in-comparepy-ratchet-rolling-median-and-accept` → `main`  
**Author:** @ikostan  
**Merged:** Nov 3, 2026 as `bd32c63` (final PR commit `a8d3755`)  
**Resolves:**

- [#1109 – [TASK] Benchmark baseline rules in compare.py: ratchet, rolling median and accept](https://github.com/ikostan/SkyLockAssault/issues/1109)

**Related:** [#1107 – [EPIC] Automatic CI benchmark baselines](https://github.com/ikostan/SkyLockAssault/issues/1107) (sub-task 2), [#1110](https://github.com/ikostan/SkyLockAssault/issues/1110), [#1111](https://github.com/ikostan/SkyLockAssault/issues/1111), [#1121](https://github.com/ikostan/SkyLockAssault/pull/1121), [#1123](https://github.com/ikostan/SkyLockAssault/pull/1123), [#1124](https://github.com/ikostan/SkyLockAssault/pull/1124), [#1125](https://github.com/ikostan/SkyLockAssault/pull/1125)  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** documentation, enhancement, tools, testing, performance, dependencies, dependabot, QA

### Purpose

CI benchmark baselines only change by hand, so improvements are never locked in. This PR teaches `test/benchmark/compare.py` the rules the rest of #1107 runs on. It reads a baseline file that also holds recent run history, compares the new results, and writes an updated file.

The rules are plain Python, so each one is tested before any workflow uses it. No workflow calls the new options yet: `benchmark.yml` still compares against the committed version 1 files, which load with an empty history and behave as before. Task 4 (#1111) turns the rules on.

---

## Key Changes

### 1. Version 2 baseline file (`test/benchmark/compare.py`)

| Field       | Holds                                                                                        |
|-------------|----------------------------------------------------------------------------------------------|
| `baseline`  | The count baselines the gate compares against.                                               |
| `history`   | The last 5 recorded runs, passing or accepted: run ID, commit, date and every metric median. |
| `accepted`  | The last accept that raised a count, and what it raised.                                     |
| `seen_runs` | The IDs of recorded runs, up to 500 (not in the issue; see below).                           |
| `profile`   | The platform this file belongs to (not in the issue; see below).                             |

- A version 1 file is read as a baseline with empty history, so task 3 (#1110) can seed the branch from today's files.
- A seed file's `baseline` also holds timings and web objects and nodes. They are the reference only until the first passing or accepted update, and are then dropped.

### 2. The three rules

- **Count ratchet:** a passing run is added to `history`. If the last 3 runs all beat a count's baseline by more than its tolerance, the baseline drops to the worst of the 3. It never rises through this rule.
- **Rolling reference:** timings, plus web `objects_avg` and `nodes_avg`, compare against the median of up to 5 runs in `history`. They only warn, and web objects and nodes are never ratcheted.
- **Accept:** `--accept <id>` raises only the failing counts to this run's values and records the accept. Every other count stays on the ratchet.
- **Failing run:** an unaccepted count failure exits 1 and does not update the baseline file, so the run is not added to `history`. It still appends to `--summary` and writes the `--write-baseline` candidate.

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
- **Invalid results exit 2:** a non-numeric, `NaN` or infinite benchmark metric in any iteration stops the run before anything is written, including under `--report-only`. A metric whose column is absent is still skipped.
- **One file, one platform:** any `--profile` other than the file's own exits 2.
- **`--update` refuses to reseed:** it exits 2 if the file is missing or holds no count baselines, so a bad file cannot reset the gate from the current run.
- **Re-runs change nothing:** a run ID in `seen_runs` adds no history and raises nothing, even after it leaves `history` or carries an accept.
- **Incomplete options are rejected:** `--update` needs `--run-id` and `--profile`, `--accept` needs `--update`, and IDs cannot be empty.

### 5. Tests (`tests/ci/test_benchmark_compare.py`)

- **Existing cases:** all 95 kept unchanged.
- **New:** 108 cases, for 203 in total, 8 of them from CodeRabbit's #1124. They cover each acceptance criterion, re-runs, malformed files, invalid results, profile binding, report-only behaviour and option validation.

### 6. Other files in this PR

- **Doc comments:** `audio_manager.gd`, `sfx_manager.gd` and `fuel_resource.gd`, from the weekly docs PR #1123 and later review edits. Comments only; no code lines changed.
- **`lint_readme.yml`:** Dependabot's bump from #1121 reached this branch and was reverted in `c8b984d`. The action pin matches `main` again, but one comment line was removed.

---

## Design Decisions

- **`--report-only` still writes the `--write-baseline` candidate.** The issue first said "write nothing", but the measure jobs will run report-only, and the accept check in the design doc reads `commit` from that file in the results artifacts. It never updates the baseline: `--update` is rejected. #1109 now says this too.
- **`--commit` was added.** A manual accept runs under a different `GITHUB_SHA` from the run it accepts, so history would otherwise record the wrong commit. It falls back to `GITHUB_SHA`.
- **`seen_runs` was added.** `history` keeps only 5 runs, so it cannot detect an older re-run. GitHub allows re-runs for up to 30 days, and 500 IDs covers far more merges than that.
- **`profile` was added at file level.** The first `--update` records it. Filtering history by profile would still leave a shared file's `seen_runs` mixed, so the file refuses any other profile and history entries stay untagged.
- **A manual accept is named by matching IDs.** If `--accept` equals `--run-id`, the summary says `run <id>`; otherwise `#<id>`. #1111 must pass the failed run's ID to both on the manual path.
- **An unneeded accept keeps the last `accepted` record.** The run is still recorded, and the summary says the accept raised nothing.
- **A gated count missing from the baseline is added at this run's value,** so a new count starts being gated. Web `objects_avg` and `nodes_avg` only warn, so they are not added. The file must still hold at least one count baseline.
- **A recorded run with `--accept` exits 0 and changes nothing,** even if the table shows a failure. Without `--accept` it exits 1.

---

## Review Decisions

| Reviewer   | Finding                                                             | Decision                                                                                                                                                                                                                       |
|------------|---------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| DeepSource | `update_baseline` complexity 20, `main` complexity 17               | **Fixed:** split into helpers. Identical results over 2,048 randomised runs, apart from timestamps and runner.                                                                                                                 |
| DeepSource | Keyword arguments before `*extra` in `update_run`                   | **Fixed:** replaced with a named `accept` parameter.                                                                                                                                                                           |
| DeepSource | Too many positional arguments (7 calls to `update_run`)             | **Fixed:** the calls still used the old format after the helper changed; CI failed the same way until they were updated.                                                                                                       |
| DeepSource | Docstring lines over 88 characters in `compare.py` | **Fixed:** wrapped in `a8d3755`, along with a third long line it had not flagged. |
| Qodo       | Ratchet test could not catch stale history                          | **Fixed:** the runs after the accept now beat the baseline. With a stale-history bug added, the new test fails and the old one passed.                                                                                         |
| Qodo       | Malformed baselines can reset count gates                           | **Fixed:** reproduced, then rejected with exit 2.                                                                                                                                                                              |
| Qodo       | An accepted re-run can raise the gate again                         | **Fixed:** reproduced, then any recorded run changes nothing.                                                                                                                                                                  |
| Qodo       | Older re-runs can count twice in the ratchet                        | **Fixed:** reproduced, then `seen_runs` added.                                                                                                                                                                                 |
| Qodo       | Oversized baseline numbers crash comparison                         | **Fixed:** reproduced, then treated as an invalid metric (exit 2).                                                                                                                                                             |
| Qodo       | `get_muted` doc comment repeats its summary                         | **Fixed:** duplicate line removed.                                                                                                                                                                                             |
| CodeRabbit | Signal docs overstate when `volume_changed` and `mute_toggled` emit | **Fixed:** the docs now name the setters and say direct assignments do not emit.                                                                                                                                               |
| CodeRabbit | Non-finite medians reach the baseline file                          | **Fixed differently:** reproduced a traceback and exit 1 before any write, plus a median that could hide `NaN`. Such results now exit 2. The `allow_nan=False` backstop was declined: every written number is already checked. |
| CodeRabbit | Filter ratchet history by profile                                   | **Fixed differently:** a shared file also mixes rolling medians and `seen_runs`, so the file now records its profile and refuses any other.                                                                                    |
| CodeRabbit | Filter rolling history by profile in `build_reference`              | **Declined:** the profile check already stops a file holding mixed runs, and no version 2 files exist yet, so there are no legacy entries to migrate.                                                                          |
| CodeRabbit | `history` and seed wording leave out accepted runs                  | **Fixed:** the note and the `compare.py` docstring now say passing or accepted.                                                                                                                                                |
| CodeRabbit | "Writes nothing" overstates a failing run                           | **Fixed:** a failing run does not update the baseline file, but still writes the summary and candidate. The note and the `compare.py` docstring now say so.                                                                    |
| CodeRabbit | Missing-count rule also implies web warn-only counts                | **Fixed:** the rule now says gated counts, and that web objects and nodes are not added.                                                                                                                                       |
| CodeRabbit | Verification and assessment table disagree on CI                    | **Fixed:** both say it is still to confirm until CI finishes on the final commit.                                                                                                                                              |
| CodeRabbit | Non-numeric cells drop a metric from the gate                       | **Fixed:** reproduced a 500-save regression passing because one iteration held `n/a`. Such results now exit 2, and so does a short row, which crashed with a `TypeError`.                                                      |
| Sourcery   | Report-only writes the candidate                                    | **Declined:** intentional, see Design Decisions.                                                                                                                                                                               |
| Sourcery   | Workflow changed in a Python-only PR                                | **Fixed in part:** bump reverted; one removed comment remains (see Follow-ups).                                                                                                                                                |
| Sourcery   | Missing run fails to interrupt the ratchet (#1124)                  | **Fixed:** the test now checks the baseline after `r1` and `r2`, and it moves only after `r3`. With a bug added that skips the gap, the test fails.                                                                            |
| Sourcery   | Non-Python changes included                                         | **Expected for the note:** #1107 gives each PR a Part N note. The `.gd` changes are in Follow-ups.                                                                                                                             |

---

## Verification

- **Tests:** `pytest tests/ci/test_benchmark_compare.py` gives 203 passed.
- **Test strength:** breaking each key rule on purpose makes the tests fail: worst-of-3, the run count, the tolerance, the history size, the failing-run block, re-run handling, the file checks, the invalid-results checks and the profile check.
- **Python style:** `ruff check` and `ruff format` clean with the repo's settings.
- **`compare.py` complexity (`radon`):** `main` 8, `update_baseline` 4, highest `render` at 14 and `compare` at 11.
- **Doc comment files:** no non-comment lines changed in the three `.gd` files.
- **PR CI:** `Pull Request Pipeline` passed all 12 jobs on `a8d3755`, including `pytest tests/ci/` with 809 passed.
- **Local limits:** the full `tests/ci/` suite cannot finish locally because `gdtoolkit` is missing, and `test_injection_readonly_file` also fails locally, with the same counts on clean `main`.
- **`main` after merge:** [run 41757389863](https://github.com/ikostan/SkyLockAssault/actions/runs/41757389863) on `bd32c63` passed 25 of 26 jobs, and the itch.io deploy succeeded. **Performance Benchmark / Desktop** failed (see Follow-ups).

---

## Known Limitations / Follow-ups

- **Desktop benchmark failure:** the first `main` run after merge failed on `OBJECT_NODE_COUNT` avg, 509.217 against 503.983 (+5.233, tolerance 5). No game code changed in this PR, and `ee128f9` gave the exact same 509.217, so this looks like runner noise. The cause of the jump is not known. [#1125](https://github.com/ikostan/SkyLockAssault/pull/1125) proposes a desktop tolerance of 6.
- **Scope of #1109:** it says "Python only" and "no workflow files", but this PR merged with one removed comment in `lint_readme.yml` and comment changes in three `.gd` files. `# Pinned to SHA for security (was @v19)` can still be restored on `main`.
- **Issue wording:** #1109 is closed without mentioning `--commit`, `seen_runs`, `profile` or exit 2. Its report-only line was updated. #1111 relies on these, so they are listed below.
- **Markdownlint bump:** v25.0.0 is not on `main`. #1121 was merged into this branch and then reverted, so the bump needs a new PR. The `dependencies` and `dependabot` labels on this PR are out of date.
- **PR description:** merged as the unedited template, which CodeRabbit's description check flagged. This note is the record of the PR.
- **#1111 must:**
  - pass `--profile` on every call, because a report-only run without it can still compare against another platform's history;
  - pass `--commit` with the selected run's SHA on the manual path;
  - pass the failed run's ID to both `--accept` and `--run-id` there;
  - treat exit 2 as a setup failure, not a regression;
  - keep `--write-baseline` in the report-only measure jobs.
- **Seed files:** a seed has no `profile` until its first `--update`, so the wrong profile on that first run is not caught. Task 3 (#1110) and #1111 need to pair each file with its profile.
- **Design doc:** `Automatic_Benchmark_Baselines.md` still says the rules arrive with this issue and that `compare.py` judges every metric against the committed file. It also does not describe `seen_runs`, `profile` or exit 2.
- **Task 6 (#1113):** removes the default `--baseline` path and the committed files, and must rewrite the tests that read them.

---

## Reviewer's Guide

### File-Level Changes

| Change                          | Details                                                                                                                                                                                              | Files                                                                                                              |
|---------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| Baseline rules and file format. | <ul><li>Version 1 and 2 loading with validation.</li><li>Ratchet, rolling median, accept and re-run handling.</li><li>One profile per file.</li><li>New options, exit 2 and summary lines.</li></ul> | `test/benchmark/compare.py`                                                                                        |
| Tests for every rule.           | <ul><li>Existing cases kept.</li><li>New helpers `write_history_file` and `update_run`.</li></ul>                                                                                                    | `tests/ci/test_benchmark_compare.py`                                                                               |
| Doc comment rewrite (no code).  | <ul><li>`:param` tags to `[param]`.</li><li>Clarified audio and SFX behaviour.</li></ul>                                                                                                             | `scripts/managers/audio_manager.gd`<br/>`scripts/managers/sfx_manager.gd`<br/>`scripts/resources/fuel_resource.gd` |
| Workflow comment removed.       | <ul><li>Left over from reverting the Dependabot bump.</li></ul>                                                                                                                                      | `.github/workflows/lint_readme.yml`                                                                                |

### Assessment against linked issues

| Issue                                                   | Objective                                                             | Addressed | Explanation                                                                      |
|---------------------------------------------------------|-----------------------------------------------------------------------|-----------|----------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Version 2 file; version 1 loads with empty history                    | ✅        | `load_baseline`.                                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Ratchet only after 3 runs past tolerance; never rises                 | ✅        | `ratchet_count`.                                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Timings use the median of up to 5 runs and only warn                  | ✅        | `build_reference`.                                                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Unaccepted failure leaves the file unchanged and exits 1              | ✅        | The update path is skipped.                                                      |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Accept raises only failing counts                                     | ✅        | `apply_accept`.                                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | CLI options; report-only never exits 1 and never updates the baseline | ✅        | It still writes the candidate if asked, as #1109 now says.                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | A reason for each baseline that moves                                 | ✅        | Summary lines.                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Default `--baseline` path stays until task 6                          | ✅        | `DEFAULT_BASELINE`.                                                              |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Tests cover the listed cases; existing cases kept                     | ✅        | No lines removed from the test file.                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | `pytest tests/ci/` passes | ✅ | 809 passed in CI on `a8d3755`. |
| <https://github.com/ikostan/SkyLockAssault/issues/1109> | Python only; no workflow files change | ❌ | Merged with one workflow comment removed and three `.gd` comment-only files (see Follow-ups). |

---

## Contributors

### Human contribution (@ikostan)

- Picked up #1109, applied all code to the PR branch, and brought every CI failure and every DeepSource, Qodo, Sourcery and CodeRabbit finding back for assessment.
- Merged Dependabot's #1121, the weekly docs PR #1123 and CodeRabbit's test PR #1124 into the branch, reviewed the doc comments, and reverted the markdownlint bump.
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
  - `7b7bd04` Polish milestone 27 benchmark notes
  - `4f2e010` Update Part_7_Benchmark_baseline_rules_ratchet_rolling_median_&_accept.md
  - `65c77f1` Update audio_manager.gd
  - `e3293e3` Reject non-finite benchmark metrics
  - `6f2ea1d` Bind benchmark baselines to a profile
  - `a228133` Document benchmark profile and safety updates
  - `4a20fe1` Fix ratchet window test run sequence
  - `30249ca` Update test_benchmark_compare.py
  - `3e76534` Merge pull request #1124
  - `a9898c8` Update Part_7_Benchmark_baseline_rules_ratchet_rolling_median_&_accept.md
  - `6d10703` Update Part_7_Benchmark_baseline_rules_ratchet_rolling_median_&_accept.md
  - `bd32c63` Merge pull request #1122

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Rules and format**
    - Wrote the version 2 format, ratchet, rolling reference, accept rule, new options and summary lines from #1109 and the design doc.
    - Found that "report-only writes nothing" conflicts with the accept check, and that a manual accept needs `--commit`.
    - Added the re-run check, the missing-file check and the option validation.
  - **Review findings**
    - Split `update_baseline` and `main` for DeepSource and compared old and new code over 2,048 randomised runs.
    - Reproduced each Qodo bug in `compare.py` before fixing it (malformed file, accepted re-run, older re-run, oversized number) and strengthened the post-accept ratchet test.
    - Traced the workflow change to Dependabot's `1957ed9` and checked which `.gd` changes were comments only.
    - Checked CodeRabbit's findings against the code: reworded the signal docs, replaced its non-finite guard after finding the crash and the hidden `NaN`, proposed the file-level `profile` check instead of filtering history, and tested that the `build_reference` finding was already covered.
    - Reviewed #1124 with mutation testing on a scratch copy: its tests caught two bugs the suite had missed. One test missed a ratchet bug, so its run sequence was corrected.
    - Wrote the over-long docstring lines DeepSource flagged, then wrapped them.
  - **After merge**
    - Compared desktop benchmark values across `main` runs and confirmed no game code changed, then opened #1125.
  - **Docs**
    - Updated the report-only line in #1109.
  - **Commits**
    - `47e0c2f` Add milestone 27 Part 7 note for PR #1122
    - `5473da1` Correct benchmark baseline wording from review (#1109)
    - `8cd737c` Reject non-numeric benchmark metrics (#1109)
    - `d6a3402` Clarify how #1124 was reviewed in Part 7 note
    - `a8d3755` Wrap long benchmark docstring lines (#1109)

- **@sourcery-ai**
  - Posted the PR summary and Reviewer's Guide, with 5 inline comments: report-only, twice (declined); the workflow change, twice (fixed in part); non-Python changes (expected for the note).
  - #1124: posted 1 comment on the missing-run test (fixed).
  - Posted the #1109 requirements check (9 of 12 met, 1 by hand, 1 partly met, 1 not addressed).
  - Skipped one review because the review budget was used up.

- **@qodo-code-review**
  - Posted 6 findings, all fixed: 4 bugs in `compare.py`, 1 weak test, 1 duplicate doc comment.

- **@deepsource-io**
  - Python and JavaScript analysis pass (grade A), with 14 inline comments, all fixed: 2 complexity, 8 `update_run` calls and signature, and 4 for the long docstring lines (2 lines, posted twice).
  - `deepsource-autofix[bot]` authored `4e9a62f` style: format code with Black and isort (#1124).

- **@coderabbitai**
  - Posted the walkthrough, rated merge risk minimal, and flagged the unedited PR description.
  - Posted 9 later comments: the signal docs, non-numeric cells and four note and docstring wording fixes (fixed), non-finite medians and ratchet history (both fixed differently), and rolling history (declined).
  - Authored `866d243` Add benchmark comparison edge case tests (#1124): 5 tests, 8 cases. Reviewed by @claude (Opus 5.5): kept, with one test strengthened.

- **@dependabot**
  - Authored `1957ed9` Bump DavidAnson/markdownlint-cli2-action from 24.2.0 to 25.0.0 (#1121), later reverted on this branch.

- **@github-actions**
  - Committed `6faa5a3` docs(gdscript): update and enhance Native BBCode docstrings, from the weekly docs automation (#1123).

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
