<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Remove committed baselines & update the benchmark guide

---

## PR #1155 Summary

**Title:** Move CI baselines to branch-managed files  
**PR:** [#1155](https://github.com/ikostan/SkyLockAssault/pull/1155)  
**Branch:** `remove-committed-baselines-from-main-and-update-the-benchmark-guide` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1113 – [TASK] Remove committed baselines from main and update the benchmark guide](https://github.com/ikostan/SkyLockAssault/issues/1113)
- [#1107 – [EPIC] Automatic CI benchmark baselines](https://github.com/ikostan/SkyLockAssault/issues/1107) (#1113 is its last sub-task)

**Related:** [#1110](https://github.com/ikostan/SkyLockAssault/issues/1110), [#1111](https://github.com/ikostan/SkyLockAssault/issues/1111), [#1112](https://github.com/ikostan/SkyLockAssault/issues/1112), [#1132](https://github.com/ikostan/SkyLockAssault/pull/1132), [#625](https://github.com/ikostan/SkyLockAssault/issues/625)  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** documentation, testing, performance, QA

### Purpose

The CI baselines now live on the `benchmark-baselines` branch, but `main` still held the two old copies, and `compare.py` still used one as its default. This PR removes both files and the default, and rewrites the guide around the automatic baselines.

It also makes the report say only what can happen. A report-only table no longer says counts fail the job, and a run with no baseline says no count can fail.

It finishes the epic: baselines now maintain themselves, with no manual file edits.

---

## Key Changes

### 1. Baselines and `compare.py`

- **Removed:** `test/benchmark/baseline_ci.json` and `baseline_web_ci.json`.
- **`--baseline` has no default:** leaving it out only reports the numbers. `--write-baseline` works without it.
- **`--update` requires `--baseline`:** it stops with a clear error before reading or writing anything.
- **`render_intro`:** the report's intro moved out of `render`, with three wordings: no baseline, report-only and gate.

### 2. PR benchmark job (`lint_test_on_pull.yml`)

- **`needs`:** the job now waits for `browser_tests`, `gdlint`, `readmelint`, `yamllint`, `gdunit4_tests`, `gut_tests` and `ci_script_tests`, as well as `detect-changes`.
- **Condition:** it uses `always()`, and runs only if one of its two filters matches and no needed job failed. This follows `browser_tests`.

### 3. Tests

- **`test_benchmark_compare.py` (24 new cases, 239 in the file):** 9 by @claude and 15 by CodeRabbit. They cover no default baseline, report wording, `--update` without `--baseline`, and web warnings.
- **Rewritten, not removed:** the 14 cases that read the deleted files now use the same numbers from a `CI_SEEDS` constant.
- **`test_pr_path_filters.py` (48 cases, unchanged count):** the benchmark job test now checks the full `needs` list and the new condition.

### 4. Docs

- **`Performance_Benchmark_Guide.md`:** covers how the baselines update, PR runs, both ways to accept a regression, and fetching baselines for a local comparison. The Files table and the CI section no longer name the old files.
- **`Automatic_Benchmark_Baselines.md`:** status is done, and the description of the old files is in the past tense.
- **Part 9 note:** adds the `Merged:` line and the `main` run result, and corrects which commit was the last one with code.

### 5. `Dockerfile`

- **Adds `jq`:** `benchmark_baselines.yml` calls it, so `test_accept_lookup_on_a_push` failed in the local image.

---

## Design Decisions

- **The candidate files keep their names.** `baseline_ci.json` and `baseline_web_ci.json` are still the candidate files in the results artifacts. Renaming them would touch two workflows and three test files, and the manual accept would refuse any run from before the merge. The #1113 criterion now checks for `test/benchmark/baseline` instead of the bare names.
- **The seed numbers moved into the tests.** Those cases can't read `benchmark-baselines` in a CI checkout, and their limits are still worth testing with real measured values.
- **The PR benchmark now waits for the other checks (`583cd70`).** This reverses a Part 9 decision: a lint or test failure now hides the numbers on that PR, and the benchmark starts later.
- **`always()` is required.** Most PRs skip at least one needed job through its path filter, and GitHub would then skip the benchmark too.
- **Local baselines go in `bench_results/`.** Git ignores that folder, so a fetched baseline can't be committed by accident.
- **The guide's fetch names the full ref.** A plain `git fetch origin benchmark-baselines` creates no tracking ref in a single-branch clone.
- **PowerShell gets its own command.** Windows PowerShell's `>` writes UTF-16, and `compare.py` then exits 2, so the guide runs `git show` through `cmd /c`.

---

## Review Decisions

| Reviewer   | Finding                                                      | Decision                                                                                                                                                                                 |
|------------|--------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| CodeRabbit | Do not describe a count gate when no baseline exists (Minor) | **Fixed in `f1d0602`:** the report now says no count can fail.                                                                                                                           |
| CodeRabbit | Remove the committed baseline files (Major)                  | **Fixed in `6141935`:** a real miss when reported, because the deletion did not make it into `4d4074c`. It failed `Run CI Injection Tests`.                                              |
| CodeRabbit | Generated 15 more test cases (`ae88282`)                     | **Kept:** breaking `compare.py` on purpose 6 ways made at least one of them fail each time.                                                                                              |
| Sourcery   | Reports claim a nonexistent gate (Medium)                    | **Fixed in `f1d0602`:** the same finding as CodeRabbit's.                                                                                                                                |
| Sourcery   | Web warnings falsely promise gate failure (Medium)           | **Reworded in `f1d0602`:** overstated, because those rows show ⚠️ and the next line says they only warn. "A worse count shows ❌" was still loose, and now covers only counts marked ❌. |
| Sourcery   | Users load stale baselines (Medium)                          | **Fixed in `373ee25`:** valid for single-branch clones, not normal ones.                                                                                                                 |
| Sourcery   | Old reruns re-enter history (Medium)                         | **Not changed:** the code does this, but it needs 500 recorded `main` runs within GitHub's 30-day re-run limit. The branch gets about one a day.                                         |
| DeepSource | Line too long, 89 > 88 (Minor)                               | **Fixed in `f1d0602`.**                                                                                                                                                                  |
| DeepSource | `next()` should be in `try`/`except` (Critical)              | **Fixed differently in `f3c86f7`:** overstated, since a missing row only fails the test. The test now checks for exactly one row.                                                        |
| DeepSource | `render` has a complexity of 16 (`PY-R1000`, Minor)          | **Fixed in `00cfa4a`:** this was the blocking issue. `radon` gives `render` 12 and `render_intro` 4.                                                                                     |
| DeepSource | Docstring missing for `unexpected_load` (Minor)              | **Fixed in `38fe569`.**                                                                                                                                                                  |

---

## Verification

- **PR CI on `00cfa4a` (final commit):** [run 42144401208](https://github.com/ikostan/SkyLockAssault/actions/runs/42144401208) passes, and `pytest tests/ci/` gives 990 passed. Markdown Lint, YAML Lint, GUT, GDUnit4 and the asset checks pass. DeepSource Python and JavaScript pass, with an overall grade A.
- **Benchmark on the same run:** Desktop and Web both pass in about 5 minutes, compared with baseline commit `1dcb7db` from `benchmark-baselines`. All 24 rows are ✅, and both show the "Report only" line.
- **`always()` on a real run:** the benchmark ran even though `GDScript Lint` and `Browser Functional Tests` were skipped.
- **Test strength:** breaking `compare.py` on purpose made tests fail each time: 4 ways for the @claude tests and 6 for CodeRabbit's.
- **`render_intro`:** old and new `render` gave identical text across 48 combinations of inputs.
- **Commands checked:** the new fetch works in a single-branch clone where the plain one fails. A UTF-16 baseline makes `compare.py` exit 2.
- **Locally:** `ruff`, `yamllint` and markdownlint-cli2 pass.
- **Local failure, not from this PR:** `test_injection_readonly_file` fails in the sandbox and passes in CI, most likely because the sandbox runs as root.
- **`main` after merge:** to confirm on the first run.

---

## Known Limitations / Follow-ups

- **`main` run:** the #1113 criterion that the next run stays green and commits to `benchmark-baselines` can only be checked after the merge.
- **Hidden numbers:** a failed lint or test job now skips the PR benchmark, so that PR shows no table until the failure is fixed.
- **Count regression:** no count regressed on this PR, so ❌ without a failed pipeline is still proven only by `compare.py`'s tests.
- **Part 9 note:** it still says the job needs only `detect-changes`. That was true at that merge, so it stays as history.
- **Local Docker:** `tests/ci/` needs both `safe.directory` entries (`/project` and `/project/.git`), and the image must be rebuilt to pick up `jq`.
- **Reviews:** CodeRabbit reached its review limit on later commits. Qodo reviews were paused, so Qodo did not review it.

---

## Reviewer's Guide

### File-Level Changes

| Change                | Details                                                                                                                         | Files                                                                                         |
|-----------------------|---------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| Remove the baselines. | <ul><li>Both JSON files deleted.</li></ul>                                                                                      | `test/benchmark/baseline_ci.json`<br/>`test/benchmark/baseline_web_ci.json`                   |
| `compare.py`.         | <ul><li>No default baseline.</li><li>`--update` requires `--baseline`.</li><li>`render_intro` and its three wordings.</li></ul> | `test/benchmark/compare.py`                                                                   |
| PR benchmark job.     | <ul><li>Waits for the lint and test jobs.</li><li>`always()` with a failure check on each.</li></ul>                            | `.github/workflows/lint_test_on_pull.yml`                                                     |
| Tests.                | <ul><li>24 new cases, 9 by @claude and 15 by CodeRabbit.</li><li>14 rewritten, no cases removed.</li></ul>                      | `tests/ci/test_benchmark_compare.py`<br/>`tests/ci/test_pr_path_filters.py`                   |
| Benchmark docs.       | <ul><li>Automatic baselines, accepting, PR runs and local fetch.</li></ul>                                                      | `files/docs/Performance_Benchmark_Guide.md`<br/>`files/docs/Automatic_Benchmark_Baselines.md` |
| Part 9 note.          | <ul><li>`Merged:` line and `main` run result.</li></ul>                                                                         | `files/docs/milestones/27/Part_9_Run_the_benchmark_on_pull_requests_report_only.md`           |
| Local image.          | <ul><li>Adds `jq`.</li></ul>                                                                                                    | `Dockerfile`                                                                                  |

### Assessment against linked issues

| Issue                                                   | Objective                                                                 | Addressed | Explanation                                                                                           |
|---------------------------------------------------------|---------------------------------------------------------------------------|-----------|-------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1113> | No baseline JSON under `test/benchmark/`, and nothing references them     | ✅        | Both deleted. The grep finds only milestone notes and one assertion, as the updated criterion allows. |
| <https://github.com/ikostan/SkyLockAssault/issues/1113> | The guide covers the label, manual accept, PR runs and local fetch        | ✅        | New sections in `Performance_Benchmark_Guide.md`.                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1113> | `--write-baseline` works with no `--baseline` (test)                      | ✅        | `test_write_baseline_works_without_baseline_argument`.                                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1113> | `pytest tests/ci/` passes, no test cases removed                          | ✅        | 990 pass in CI, up from 966. The 14 affected cases were rewritten.                                    |
| <https://github.com/ikostan/SkyLockAssault/issues/1113> | The next `main` run stays green and commits to `benchmark-baselines`      | ⏳        | To confirm after the merge.                                                                           |
| <https://github.com/ikostan/SkyLockAssault/issues/1113> | Under `--report-only`, the report does not say counts fail the job (test) | ✅        | `test_report_only_does_not_say_counts_fail_the_job`.                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1113> | The Part 9 note has its `Merged:` line and the `main` run result          | ✅        | Both added.                                                                                           |

---

## Contributors

### Human contribution (@ikostan)

- Picked up #1113, decided to keep the candidate file names and relax the criterion, and applied all the code to the PR branch.
- Made the PR benchmark wait for the other CI checks (`583cd70`).
- Ran `tests/ci/` on Windows and in Docker, and brought back the 19 local failures.
- Commits by @ikostan:
  - `4d4074c` Move CI baselines to branch-managed files
  - `6141935` Add jq and remove CI benchmark baselines
  - `f1d0602` Clarify benchmark report-only wording
  - `583cd70` Gate benchmarks on CI checks
  - `373ee25` Fetch benchmark baseline branch explicitly
  - `50897b9` Run PR benchmarks after filtered jobs skip
  - `f3c86f7` Assert unique benchmark warning row
  - `38fe569` Clarify baseline-loading test helper
  - `00cfa4a` Extract benchmark report intro rendering

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **`compare.py` and tests**
    - Removed the default baseline, added the `--update` check, and wrote the report wording and `render_intro`.
    - Rewrote the 14 cases that read the deleted files, and wrote 9 new cases.
    - Broke the code on purpose to test both its own tests and CodeRabbit's.
  - **Workflow**
    - Showed that `583cd70` would skip the benchmark on most PRs, and wrote the `always()` condition and its test.
  - **Findings outside the issue**
    - Found that the #1113 grep criterion could not pass as written, and edited the issue once @ikostan chose the narrower check.
    - Found that `4d4074c` still held the baseline files, from the failing CI job.
    - Traced the 19 local Docker failures to `safe.directory`, a missing `jq` and the undeleted files.
    - Found that PowerShell's `>` breaks the local fetch, and reproduced the exit 2.
  - **Review findings**
    - Assessed each finding against the code, and rated the web warning and `next()` findings as overstated.
    - Showed the `seen_runs` limit is out of reach in practice, and reviewed CodeRabbit's generated tests.
  - **Mistakes fixed in this PR**
    - Left "Counts fail the job" in the no-baseline report. CodeRabbit and Sourcery caught it.
    - Showed the `Dockerfile` change without saying where it went, so it was pasted into the terminal.
  - **Docs**
    - Wrote the guide and design doc changes, the Part 9 update and this note.

- **@coderabbitai**
  - Posted 2 inline comments: the no-baseline wording and the baseline files (both fixed). Confirmed the `6141935` reply.
  - Generated 15 test cases on request.
  - Reached its review limit on later commits.
  - Commits:
    - `ae88282` Test benchmark reporting and update validation without a baseline

- **@sourcery-ai**
  - Posted the PR summary and Reviewer's Guide.
  - Posted 4 inline comments: 3 fixed and 1 answered without a change.

- **@deepsource-io**
  - Python and JavaScript analysis: overall grade A on the final commit.
  - Posted 3 inline comments, and reported the `render` complexity issue on its dashboard (all fixed).
  - Commits:
    - `72951fe` style: format code with Black and isort

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
