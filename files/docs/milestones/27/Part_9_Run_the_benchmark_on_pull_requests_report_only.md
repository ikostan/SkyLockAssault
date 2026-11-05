<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Run the benchmark on pull requests (report-only)

---

## PR #1132 Summary

**Title:** Run the benchmark on pull requests report only  
**PR:** [#1132](https://github.com/ikostan/SkyLockAssault/pull/1132)  
**Branch:** `run-the-benchmark-on-pull-requests-report-only` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1112 – [TASK] Run the benchmark on pull requests (report-only)](https://github.com/ikostan/SkyLockAssault/issues/1112)
- [#1129 – [BUG] Part 8 milestone note is out of date after #1127](https://github.com/ikostan/SkyLockAssault/issues/1129)

**Related:** [#1107 – [EPIC] Automatic CI benchmark baselines](https://github.com/ikostan/SkyLockAssault/issues/1107) (sub-task 5), [#1111](https://github.com/ikostan/SkyLockAssault/issues/1111), [#1113](https://github.com/ikostan/SkyLockAssault/issues/1113), [#1127](https://github.com/ikostan/SkyLockAssault/pull/1127), [#1128](https://github.com/ikostan/SkyLockAssault/pull/1128), [#1131](https://github.com/ikostan/SkyLockAssault/pull/1131)  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** documentation, testing, performance, github actions, github_actions, QA

### Purpose

The `benchmark-accept` label has to be on a PR before it merges, but until now the benchmark ran only after the merge. This PR runs it on pull requests that touch game code or the benchmark itself, so the label is set from real numbers. The run only reports: a worse count shows in the table without failing the PR, and `benchmark-baselines` is not updated.

It also corrects the Part 8 note (#1129), and it carries the weekly GDScript docs from #1131, which merged into this branch.

---

## Key Changes

### 1. Benchmark job in the PR pipeline (`lint_test_on_pull.yml`)

- **`benchmark` filter:** `test/benchmark/**`, `.github/workflows/benchmark.yml` and `export_presets.cfg`, exported by `detect-changes`. `gdscript` excludes all of `test/`, so it cannot see the benchmark's own files.
- **`benchmark` job:** calls `benchmark.yml` when `gdscript == 'true' || benchmark == 'true'`, with `contents: read`.
- **Position:** it needs only `detect-changes`, and no job needs it.

### 2. Tests (`test_pr_path_filters.py`)

- **New (35 cases, 48 in the file):** real paths routed through the filter rules, filter boundaries, the job's exact condition, read-only permissions, no push, no job waiting on the benchmark, no call to the gate, artifact uploads, and no suppressed errors.
- **Existing cases:** all 13 kept.

### 3. Docs

- **`benchmark.yml` header:** names both callers and what a PR run does.
- **`Performance_Benchmark_Guide.md`:** replaces "called only from the main pipeline" with when each pipeline runs it.
- **`Automatic_Benchmark_Baselines.md`:** updates the status and the wording of what PR runs write.

### 4. Part 8 note (#1129)

- **Corrected:** case counts, the final CI result, the label and PR description status, the first `main` run, the #1111 assessment, the contributor lists and the `Merged:` line.
- **Also corrected:** Windows skips from 32 to 37, which the issue did not list.
- **Renamed:** `Part_8_Benchmark_baselines_job_gate_&_accept_path.md`, to use `&` like the other notes.

### 5. Weekly GDScript docs (#1131)

- **Docstrings only, in 5 files:** no game logic changes.
- **`weapon_swapped` (`6b52d15`):** it can also fire when the weapon name changes without an index change, or when the index is clamped.
- **`setting_changed` (`9d72093`):** corrected after review, see Review Decisions.

---

## Design Decisions

- **The job needs only `detect-changes`.** A lint failure elsewhere does not hide the numbers, and no other job waits about 5 minutes for a report.
- **Setup failures stay red.** A job that could not measure or compare still fails, because a missing table must not look like a clean one. `continue-on-error` is not allowed on a job that calls a reusable workflow. `main` has no required status checks, so this does not block a merge.
- **The docs promise less than "nothing is written".** PR runs do write candidate files and upload artifacts. What they never do is update `benchmark-baselines`.
- **The routing tests use a small glob translator.** `paths-filter` cannot run in pytest, so the tests apply its `some-with-excludes` rule to real paths. The 8 boundary cases gave the same results in real `picomatch` with `dot: true`.
- **The filter list is exact.** A test compares the whole set, because a wider pattern spends about 10 runner minutes on PRs that cannot change the numbers.
- **CodeRabbit's tests stayed, with fixes (`72f4cb8`).** The gate check now matches `benchmark_baselines.yml` however it is referenced, the error check also refuses `|| true`, and `_find_step` replaces bare `next()`, the pattern DeepSource flagged on #1127.

---

## Review Decisions

| Reviewer   | Finding                                                    | Decision                                                                                                                                                                                                                                 |
|------------|------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| CodeRabbit | "Nothing is written" is too broad (Minor)                  | **Fixed in `412d80e`:** PR runs write candidate files and upload artifacts. They only leave `benchmark-baselines` alone. CodeRabbit named the guide and `benchmark.yml`; the design doc made the same claim twice, so that is fixed too. |
| CodeRabbit | `setting_changed` is not emitted for every setting (Minor) | **Fixed in `9d72093`, in the wording:** 17 of 22 exports emit it. The doc now names the 5 plain exports. Adding setters would change runtime behavior, which does not belong in a docs fix.                                              |
| CodeRabbit | Generated 11 more tests (`6097271`)                        | **Kept, then tightened in `72f4cb8`:** a full-reference gate call and `\|\| true` both got through, and bare `next()` hid which step was missing. See Design Decisions.                                                                  |
| Sourcery   | Part 8 note was not renamed (#1129, Low)                   | **Fixed in `4f12b56`:** this was a real miss when reported, because the first application of the fix kept the old name.                                                                                                                  |
| Sourcery   | #1112 requirements: 4 of 5 met, 1 to check by hand         | **Confirmed:** `test_pr_path_filters.py` passes in CI (see Verification).                                                                                                                                                                |
| Sourcery   | #1129 requirements: 1 of 3 met, 1 to check by hand         | **Superseded:** written before `4f12b56`. The rename is in, and Markdown Lint passes on the final commit.                                                                                                                                |

---

## Verification

- **PR CI on `72f4cb8` (final commit):** [run 41964350772](https://github.com/ikostan/SkyLockAssault/actions/runs/41964350772): the whole pipeline passes, and `pytest tests/ci/` gives 966 passed. Markdown Lint gives 0 issues, and YAML Lint, GDScript Lint, GUT, GDUnit4 and all browser shards pass.
- **Benchmark on the same run:** Desktop and Web both pass in about 4 to 5 minutes, each showing its table and the "Report only" line. All rows are ✅.
- **Noise seen on real runs:** Web `OBJECT_NODE_COUNT` was 481.6 on `6097271` and 514.3 on `72f4cb8`, with only test and doc changes between them. That is why those averages only warn on web, and it means a 🟢 there can be noise too.
- **Test strength:** breaking 8 key lines on purpose makes the tests fail, including each filter pattern, the output, `||` to `&&`, write permission and a job needing `benchmark`. `|| true` and a full-reference gate call got through CodeRabbit's first version, and fail now.
- **Merge rules:** the branch protection API shows no required status checks on `main`, and the repository has no rulesets.
- **Locally:** `ruff`, `yamllint`, `actionlint` 1.7.12 (CI pins 1.7.7) and markdownlint-cli2 0.23.2 pass. `gdlint` and `gdformat` pass on `game_settings_resource.gd`.
- **Local failures, not from this PR:** `test_injection_readonly_file` also fails without these changes, most likely because the sandbox runs as root. One `test_docstrings_workflow.py` setup hit a 10-second `git clone` timeout, on a different test each run. Both pass in CI.
- **`main` after merge:** to confirm on the first run.

---

## Known Limitations / Follow-ups

- **Count regression:** no count regressed on this PR, so ❌ without a failed pipeline is proven only by `compare.py`'s tests until the first real regression.
- **Docs-only skip:** this PR changes benchmark files, so the skip is proven only by the routing tests until the first docs-only PR.
- **#1128:** still open and carries the older `setting_changed` text. Its commits are already in this PR, so it needs closing or regenerating after this merge.
- **#1113:** removes the committed baselines and rewrites the rest of the benchmark guide, which still says to copy baselines by hand and that counts fail "the job".
- **Reviews:** Sourcery's budget ran out at first and it ran on request. CodeRabbit reached its review limit on the later commits. Qodo reviews were paused, so Qodo did not review it. DeepSource's report gives grade A with no inline comments.

---

## Reviewer's Guide

### File-Level Changes

| Change               | Details                                                                                                                 | Files                                                                                                                                                                                                                |
|----------------------|-------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| PR benchmark job.    | <ul><li>`benchmark` filter and output.</li><li>Read-only job on either filter.</li><li>Nothing depends on it.</li></ul> | `.github/workflows/lint_test_on_pull.yml`                                                                                                                                                                            |
| Header comment.      | <ul><li>Names both callers.</li><li>Says what a PR run does not update.</li></ul>                                       | `.github/workflows/benchmark.yml`                                                                                                                                                                                    |
| Tests.               | <ul><li>35 new cases, 24 by @claude and 11 by CodeRabbit.</li><li>No cases removed.</li></ul>                           | `tests/ci/test_pr_path_filters.py`                                                                                                                                                                                   |
| Benchmark docs.      | <ul><li>When PR runs happen.</li><li>What they report and write.</li></ul>                                              | `files/docs/Performance_Benchmark_Guide.md`<br/>`files/docs/Automatic_Benchmark_Baselines.md`                                                                                                                        |
| Part 8 note (#1129). | <ul><li>Corrected after the merge of #1127.</li><li>Renamed to use `&`.</li></ul>                                       | `files/docs/milestones/27/Part_8_Benchmark_baselines_job_gate_&_accept_path.md`                                                                                                                                      |
| Weekly docs (#1131). | <ul><li>Docstrings only.</li><li>`setting_changed` and `weapon_swapped` wording corrected.</li></ul>                    | `scripts/resources/game_settings_resource.gd`<br/>`scripts/resources/speed_resource.gd`<br/>`scripts/resources/weapon_resource.gd`<br/>`scripts/system/JavaScriptBridgeWrapper.gd`<br/>`scripts/system/OSWrapper.gd` |

### Assessment against linked issues

| Issue                                                   | Objective                                                       | Addressed | Explanation                                                                                           |
|---------------------------------------------------------|-----------------------------------------------------------------|-----------|-------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1112> | A game or benchmark change runs both jobs and shows both tables | ✅        | Both ran on `72f4cb8`, because this PR edits `benchmark.yml`. Game-only routing is tested.            |
| <https://github.com/ikostan/SkyLockAssault/issues/1112> | Docs, YAML or other tests skip them                             | ⏳        | Routing tested. Proven on GitHub at the first docs-only PR.                                           |
| <https://github.com/ikostan/SkyLockAssault/issues/1112> | A count regression shows ❌ and does not fail the pipeline      | ⏳        | Exit code tested in `compare.py`. No count regressed here, so proven on GitHub at the first real one. |
| <https://github.com/ikostan/SkyLockAssault/issues/1112> | Nothing is pushed to `benchmark-baselines` from a PR            | ✅        | Read-only token, no push in `benchmark.yml`, and the gate is not called. All tested.                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1112> | `test_pr_path_filters.py` passes, with existing cases kept      | ✅        | 48 pass in CI: the 13 existing and 35 new.                                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1129> | Every listed row of the Part 8 note is fixed                    | ✅        | `3c326f5`.                                                                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1129> | The file name matches the other notes                           | ✅        | `4f12b56`.                                                                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1129> | Markdown Lint passes                                            | ✅        | 0 issues on `72f4cb8`.                                                                                |

---

## Contributors

### Human contribution (@ikostan)

- Picked up #1112 and #1129, set the order (#1129 first), and applied all the code to the PR branch.
- Merged the weekly docs from #1131 into the branch and clarified `weapon_swapped` there.
- Brought back the CodeRabbit and Sourcery findings for assessment, and asked Sourcery for its guide.
- Commits by @ikostan:
  - `6b52d15` Clarify weapon swap signal semantics
  - `36f6875` Merge pull request #1131
  - `3c326f5` Document benchmark gate merge verification
  - `ed0852e` Run report-only benchmarks on pull requests
  - `412d80e` Clarify benchmark PR artifact uploads
  - `9d72093` Clarify setting change signal behavior
  - `4f12b56` Rename benchmark baselines milestone doc
  - `72f4cb8` Strengthen benchmark workflow path checks

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Workflows**
    - Wrote the `benchmark` filter, output and job, and the `benchmark.yml` header.
    - Checked `main`'s required status checks and rulesets through the API.
  - **Part 8 note (#1129)**
    - Checked each row against CI logs, the PR, the label and the `benchmark-baselines` branch, including the 931 count and the first `main` run.
    - Found the stale Windows skip count, which the issue did not list.
  - **Review findings**
    - Confirmed CodeRabbit's two findings against the code, including the 17 of 22 count, and extended the first to the design doc.
    - Reviewed CodeRabbit's generated tests, showed two breakages getting through, compared the boundary cases with real `picomatch`, and proposed the `72f4cb8` fixes.
    - Checked Sourcery's two by-hand items against CI logs.
  - **Mistakes fixed in this PR**
    - Wrote "nothing is written", which was wrong because PR runs upload artifacts. CodeRabbit caught it.
    - Delivered the first #1112 code as scattered fragments, which were hard to place, then replaced them with complete files.
  - **Docs**
    - Wrote the guide and design doc changes, and this note.

- **Weekly GDScript docs workflow (`bi_weekly_gd_docstrings.yml`)**
  - Generated the docstrings merged through #1131.
  - Commits:
    - `7a9f4cb` docs(gdscript): update and enhance Native BBCode docstrings

- **@coderabbitai**
  - Posted 2 inline comments: "nothing is written" and `setting_changed` (both fixed).
  - Generated 11 test cases on request.
  - Commits:
    - `6097271` Add tests for PR benchmark path filters, gate exclusion, and artifact reporting

- **@sourcery-ai**
  - Skipped a review at first because the review budget was used up.
  - Posted the PR summary and Reviewer's Guide with one sequence diagram.
  - Posted the #1112 and #1129 requirements check, and 1 inline comment on the file name (fixed).

- **@deepsource-io**
  - Python and JavaScript analysis: overall grade A, with no inline comments.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
