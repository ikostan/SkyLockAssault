<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Benchmark baselines job, gate & accept path

---

## PR #1127 Summary

**Title:** Benchmark workflows baselines job gate and accept path  
**PR:** [#1127](https://github.com/ikostan/SkyLockAssault/pull/1127)  
**Branch:** `benchmark-workflows-baselines-job-gate-and-accept-path` → `main`  
**Author:** @ikostan  
**Merged:** Nov 4, 2026 as `bdba0d7` (final PR commit `39641d5`)  
**Resolves:**

- [#1111 – [TASK] Benchmark workflows: baselines job, gate and accept path](https://github.com/ikostan/SkyLockAssault/issues/1111)

**Related:** [#1107 – [EPIC] Automatic CI benchmark baselines](https://github.com/ikostan/SkyLockAssault/issues/1107) (sub-task 4), [#1109](https://github.com/ikostan/SkyLockAssault/issues/1109), [#1110](https://github.com/ikostan/SkyLockAssault/issues/1110), [#1112](https://github.com/ikostan/SkyLockAssault/issues/1112), [#1113](https://github.com/ikostan/SkyLockAssault/issues/1113)  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** testing, CI/CD, performance, QA

### Purpose

This PR turns on the rules from #1109, so every `main` run maintains the baselines on `benchmark-baselines`. The benchmark jobs now only measure and report. One new job applies the gate, updates both files and pushes once. An intended regression is accepted by a label on the PR or by a manual run.

GitHub only runs this workflow for real after it merges, so the first `main` run was its first real test, and it passed (see Verification).

---

## Key Changes

### 1. Benchmark jobs only report (`benchmark.yml`)

- Both jobs check out `benchmark-baselines` into `baselines/` and run `compare.py --report-only` against `desktop.json` or `web.json`.
- They keep `contents: read`, `persist-credentials: false`, the results artifacts and the `--write-baseline` candidate.
- A job now fails only if it could not measure or compare (`compare.py` exit 2).

### 2. New gate job (`benchmark_baselines.yml`)

| Step                      | What it does                                                                                     |
|---------------------------|--------------------------------------------------------------------------------------------------|
| Select the Run            | Uses this run on a push. A manual run needs `accept: true`, a numeric ID and a trusted run.      |
| Download results          | Downloads both artifacts from the selected run.                                                  |
| Decide the Accept         | Looks up the label on a push. A manual run checks the candidates' commit and accepts by run ID.  |
| Gate and Update Baselines | Runs `compare.py --update` for both platforms, so the summary always shows both tables.          |
| Push Baselines            | Commits `Baselines from run <ID> (<short SHA>)` and pushes once, or nothing if nothing changed.  |

- **Triggers:** `workflow_call` from `lint_test_deploy.yml` and `workflow_dispatch` with `run_id` and `accept`.
- **Limits:** `main` only, 10-minute timeout, and `contents: write`, `pull-requests: read` and `actions: read` on this one job.
- **Failures:** a regression exits 1 and a setup problem exits 2, reported differently. Either one pushes nothing, so one platform's failure also keeps the other's update off the branch.

### 3. Manual accept checks (`.github/scripts/check_benchmark_run.py`)

Before anything changes, the selected run must:

- come from `lint_test_deploy.yml`, by a `push` to `main` in this repository, and have finished;
- have both benchmark jobs passed and its `baselines` job failed;
- still have both artifacts, with the `commit` in each candidate equal to the run's head SHA.

Any failure stops the job, with the reason in the summary.

### 4. Pipeline and lint

- **`lint_test_deploy.yml`:** adds `benchmark_baselines` with `needs: benchmark`. No deploy job depends on it.
- **`yamllint.yml`:** `actionlint` now ignores one message, `unexpected key "queue" for "concurrency" section`.
- **`benchmark-accept` label:** created on the repository by @ikostan.

### 5. Tests

- **`test_check_benchmark_run.py` (new, 54 cases):** each manual accept check on its own, and malformed responses.
- **`test_benchmark_baselines_workflow.py` (new, 53 cases):** workflow rules, plus the real shell steps with the real `compare.py`, a local bare git remote and a stubbed `gh`.
- **`test_workflow_policies.py`:** adds the new workflow, which adds 2 cases, and reads workflow files as UTF-8.
- **Existing cases:** none removed.

### 6. Design doc (`Automatic_Benchmark_Baselines.md`)

- Replaces the open ruleset question with a Seed section: where the values came from, the ruleset outcome, `profile`, and how to handle the branch.
- Updates the status, says a regression fails the `baselines` job, and lists the stricter accept checks.

---

## Design Decisions

- **`queue: max` was added (not in the issue).** The design doc requires it: without it, a newer pending run replaces an older one, and that run drops out of the gate and the history.
- **A manual accept needs a failed `baselines` job.** The design doc only said the benchmark jobs "ran". That let `ee128f9` through, an old green run with `saves` at 61, and accepting it raised the baseline from 0 to 61.
- **Only the PR that merged the commit counts for the label.** The commits API also lists other PRs that contain the commit, so the lookup also matches `merge_commit_sha`.
- **The baselines are checked out after the benchmark runs.** The web preset exports all resources, so JSON files in the project before the export could end up in what is measured.
- **The job installs nothing.** `compare.py` and the check script use only the standard library, so no third-party code runs next to the write token.
- **The scripts checkout keeps no token.** Only the `baselines` checkout can push.
- **A failed label lookup stops the job.** An API error must not count as "no label".
- **The accept checks are a Python script, not inline shell,** so each one can be tested on its own.

---

## Review Decisions

| Reviewer   | Finding                                                | Decision                                                                                                                                                                           |
|------------|--------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| DeepSource | `next()` should be in `try-except` (3 calls, Critical) | **Fixed differently:** a missing step already failed the test, so Critical overstated it. A `find_step` helper and a list check replace `next()` and give a clear failure message. |
| Sourcery   | Require a failed source run                            | **Fixed, stricter:** the `baselines` job must have failed. A run's conclusion would still allow a run that failed for another reason while its gate passed.                        |
| CodeRabbit | Allow `concurrency.queue` in YAML Lint                 | **Fixed:** same approach, with the full message matched so a `queue` key anywhere else is still flagged. CodeRabbit verified it and resolved the thread.                           |
| CodeRabbit | Rewrap design doc line 8                               | **Fixed:** rewrapped. Markdown Lint passes.                                                                                                                                        |
| CodeRabbit | PR description check (warning)                         | **Fixed:** description rewritten, with `Closes #1111`. The warning cleared: the check passes on CodeRabbit's last review.                                                          |

---

## Verification

- **PR CI on `39641d5` (final commit):** [run 41777253058](https://github.com/ikostan/SkyLockAssault/actions/runs/41777253058): `pytest tests/ci/` gives 931 passed with none skipped, so the shell-step tests ran on Linux. Markdown Lint and YAML Lint pass.
- **Test strength:** breaking 28 key lines on purpose makes the tests fail, including the gate's exit code, the label filter, the push, the queue and the permissions. Two got through at first, both about recording the wrong commit on a manual accept, so the test setup was corrected.
- **Real runs through the check script:**
  - `ee128f9` passed before the failed-gate check and is refused now.
  - `bd32c63` is refused because its desktop job failed.
- **Real label lookup:** the commits API on `fb75135` returns #1125 with a matching `merge_commit_sha`, which is what the filter reads.
- **Locally:** `ruff format`, `yamllint`, `actionlint` 1.7.7 and markdownlint-cli2 0.23.2 pass, with the versions CI uses for the last two. `ruff check` flags only `EXE001` on the new script: it has a shebang but is not executable, like the other scripts in that folder.
- **Caught while applying:** one edit dropped the end of both `Compare With Baseline` steps, including `--profile` and `--write-baseline`. `test_benchmark_jobs_only_report` failed before that reached the PR.
- **Windows:** 37 shell-step cases skip on Windows, so only CI runs them.
- **`main` after merge:** [Run 41777577668](https://github.com/ikostan/SkyLockAssault/actions/runs/41777577668) passed on `bdba0d7`, with baseline commit `b0e86c1` and the deploy green. All four first-run items are confirmed:
  - GitHub accepts `queue: max` at job level.
  - `GITHUB_TOKEN` can push to `benchmark-baselines`.
  - The artifact downloads work with `run-id`.
  - The run committed one update naming its run ID and SHA: `Baselines from run 41777577668 (bdba0d7)`.

---

## Known Limitations / Follow-ups

- **Accept paths:** the labelled merge and the manual run are tested with a stubbed `gh` only. Each gets its first real test when first needed.
- **`actionlint` ignore:** 1.7.12 and its `main` branch still reject `queue`. Drop `-ignore` once the pinned version accepts it.
- **Old failed runs:** a run whose gate really failed can still be accepted while its artifacts last, up to 30 days. It takes write access and `accept: true`, so this stays a deliberate decision.
- **Label added late:** adding the label after merge and re-running the failed job would probably also accept, because the job reads the PR's current labels. Not tested on GitHub. It needs write access, so it stays.
- **Design doc:** still does not describe `seen_runs`, `profile` beyond the seed, or exit 2.
- **#1113:** removes the committed baselines and rewrites the benchmark guide, which still says to copy baselines by hand and that counts fail "the job".
- **Reviews:** Sourcery's requirements check ran on `e99865a`, before the failed-gate check, and its budget was used up on this PR. Qodo reviews were paused, so Qodo did not review it.

---

## Reviewer's Guide

### File-Level Changes

| Change                      | Details                                                                                                    | Files                                                                                                                               |
|-----------------------------|------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------|
| Gate and baseline updates.  | <ul><li>One job that writes.</li><li>Label and manual accept.</li><li>Push once, or nothing.</li></ul>     | `.github/workflows/benchmark_baselines.yml`                                                                                         |
| Report-only benchmark jobs. | <ul><li>Compare against the branch.</li><li>Check out after measuring.</li></ul>                           | `.github/workflows/benchmark.yml`                                                                                                   |
| Manual accept checks.       | <ul><li>Run, jobs and artifacts.</li><li>Candidate commits.</li></ul>                                      | `.github/scripts/check_benchmark_run.py`                                                                                            |
| Pipeline and lint.          | <ul><li>Calls the gate after the benchmark.</li><li>Ignores the `queue` message.</li></ul>                 | `.github/workflows/lint_test_deploy.yml`<br/>`.github/workflows/yamllint.yml`                                                       |
| Tests.                      | <ul><li>107 new cases in two files.</li><li>New workflow under policy.</li><li>No cases removed.</li></ul> | `tests/ci/test_benchmark_baselines_workflow.py`<br/>`tests/ci/test_check_benchmark_run.py`<br/>`tests/ci/test_workflow_policies.py` |
| Docs.                       | <ul><li>Seed section.</li><li>Status and accept rules.</li></ul>                                           | `files/docs/Automatic_Benchmark_Baselines.md`                                                                                       |

### Assessment against linked issues

| Issue                                                   | Objective                                                          | Addressed | Explanation                                                                     |
|---------------------------------------------------------|--------------------------------------------------------------------|-----------|---------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1111> | A `main` run commits one update naming its run ID and SHA          | ✅        | Confirmed on the first `main` run: `b0e86c1`.                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1111> | An unaccepted regression fails the job and leaves the branch alone | ⏳        | Tested with a local remote. Proven on GitHub at the first real regression.      |
| <https://github.com/ikostan/SkyLockAssault/issues/1111> | A labelled merge raises only failing counts and records the PR     | ⏳        | Tested with a stubbed `gh`. Proven on GitHub at the first labelled merge.       |
| <https://github.com/ikostan/SkyLockAssault/issues/1111> | A manual run does the same for that run                            | ⏳        | Tested with a stubbed `gh`. Proven on GitHub at the first manual accept.        |
| <https://github.com/ikostan/SkyLockAssault/issues/1111> | Benchmark jobs stay read-only; only `baselines` can write          | ✅        | Checked by `test_only_the_baselines_job_requests_contents_write`.               |
| <https://github.com/ikostan/SkyLockAssault/issues/1111> | Deploys do not depend on the benchmark                             | ✅        | Checked by `test_deploys_do_not_depend_on_the_benchmark`.                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1111> | Policy, pinning and new tests pass; no cases removed               | ✅        | 931 passed in CI on `39641d5`.                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1111> | `benchmark-accept` label created                                   | ✅        | The label exists, with the description #1111 asks for.                          |

---

## Contributors

### Human contribution (@ikostan)

- Picked up #1111 and #1110, created and pushed the `benchmark-baselines` branch by hand, and applied the code to the PR branch.
- Ran the tests on Windows and brought back the encoding error, both lint failures and every DeepSource, Sourcery and CodeRabbit finding for assessment.
- Asked for the seed's origin to be documented, and moved that doc change into this PR.
- Created the `benchmark-accept` label.
- Commits by @ikostan:
  - `ebf1482` Add gated benchmark baseline updates
  - `a73f792` Merge branch into the PR branch
  - `81b3baf` Make benchmark workflow tests fail clearly
  - `57623bf` Merge branch into the PR branch
  - `93a93c7` Document benchmark baseline gate PR
  - `91f838e` Merge branch into the PR branch
  - `39641d5` Test expired duplicate artifact order

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Workflows and checks**
    - Added `queue: max`, which #1111 left out, and the merged-PR-only label filter.
    - Found that the baselines must be checked out after measuring, because the web preset exports all resources.
  - **Tests**
    - Broke 28 key lines on purpose to test the tests, and corrected the test setup when two got through.
    - Traced the Windows collection error to `read_text()` without an encoding in `test_workflow_policies.py`, which was already on `main`.
  - **Mistakes fixed in this PR**
    - Pushed a design doc line over the limit without running markdownlint.
    - Treated `actionlint` rejecting `queue` as a local result without checking that CI runs it, which failed YAML Lint.
  - **Review findings**
    - Assessed each finding against the code. Rated DeepSource's as overstated and proposed the `find_step` fix.
    - Reproduced Sourcery's finding on `ee128f9`, showed `saves` going from 0 to 61, and proposed the stricter `baselines` job check.
  - **Docs**
    - Wrote the Seed section, the other design doc updates and this note, and corrected the note after the merge (#1129).
  - **Commits**
    - `331ba89` Document the benchmark-baselines seed (#1110)
    - `0f003b9` Update the design doc for the baselines job (#1111)
    - `e99865a` Fix the lint failures on the baselines PR (#1111)
    - `ed08f9f` Only accept runs whose baselines job failed (#1111)

- **@sourcery-ai**
  - Posted the PR summary and Reviewer's Guide with two sequence diagrams.
  - Posted 1 inline comment on the manual accept check (fixed, stricter).
  - Posted the #1111 requirements check on `e99865a` (4 of 6 met, 1 to check by hand, 1 partly met).
  - Skipped a review at first because the review budget was used up.

- **@deepsource-io**
  - Python and JavaScript analysis, with 3 inline comments on `next()` (fixed differently).
  - Commits:
    - `6cfb345` style: format code with Black and isort

- **@coderabbitai**
  - Posted the walkthrough and rated merge risk low.
  - Flagged the unedited PR description, then passed the check once it was rewritten.
  - Posted 2 inline comments: the `queue` key and design doc line 8 (both fixed). Verified the `queue` fix and resolved that thread.
  - Commits:
    - `559c953` Add tests for benchmark baseline acceptance and run validation edge cases

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
