<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Add test result summaries to the CI run page

---

## PR #1175 Summary

**Title:** Add test result summaries to the ci run page  
**PR:** [#1175](https://github.com/ikostan/SkyLockAssault/pull/1175)  
**Branch:** `add-test-result-summaries-to-the-ci-run-page` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1156 – [TASK] Add test result summaries to the CI run page](https://github.com/ikostan/SkyLockAssault/issues/1156)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** CI/CD, documentation, github actions, github_actions, python, QA, testing

### Purpose

Seeing what failed in a test job meant opening the job and searching its log, or downloading an artifact. The benchmark jobs already showed that a table on the run's **Summary** page is quicker to read.

This PR adds a results table for each test job: GUT, GDUnit4, `tests/ci/` and each browser shard. A run with no results must not look clean either: a crash before the tests start, a shard that ran nothing, or a runner that stopped early now shows ⚠️, never ✅.

---

## Key Changes

### 1. The reporter (`.github/scripts/test_summary.py`)

- **New script, standard library only:** `--title`, `--results <path or glob>` and an optional `--summary <file>` to append to. The report is also printed to the job log.
- **Report:** a status line, a table of passed, failed, errors, skipped and total, the failing tests with the first line of each message, and the 5 slowest tests in a collapsed `<details>` section.
- **Formats:** a `testsuites` root (GUT, gdUnit4, pytest) or a single `testsuite` root, in pytest's default xunit2 or the browser job's `junit_family=legacy`. Nested suites are counted under either root.
- **Status line:** ✅ only when at least one test ran and nothing failed or went missing. ❌ for failures and errors. ⚠️ for no XML, unreadable XML, XML with another root, 0 tests, or tests the XML declares but has no result for.
- **Not-run tests:** the leaf suites' `tests` attribute is compared with the `testcase` elements. gdUnit4 stops at the first failing test unless it runs with `-c`, so its XML can declare 4 tests and hold 1 result; the report says "3 tests declared in the XML have no result".
- **GUT tests with no assertions:** GUT marks them `status="no asserts"` (risky). They stay counted as passed, with a "⚠️ N GUT test(s) made no assertions." note. The verdict doesn't change.
- **Always exits 0:** bad arguments, a crash, or an unwritable summary file never fail the step. A crash is reported on the page as ⚠️.

| Status | When                                                                      |
|--------|---------------------------------------------------------------------------|
| ✅      | At least one test, no failures or errors, no problems, no missing results |
| ❌      | At least one failure or error                                             |
| ⚠️     | No XML matched, unreadable or non-JUnit XML, 0 tests, or tests not run    |

### 2. Workflows

A **Test Results Summary** step with `if: "always()"`, after each test step:

| Job            | Workflow              | XML it reads                   | Title                                      |
|----------------|-----------------------|--------------------------------|--------------------------------------------|
| GUT            | `gut_tests.yml`       | `gut-reports/*/gut_junit.xml`  | `GUT unit tests${RUNNER_SUFFIX}`           |
| GDUnit4        | `gdunit4_tests.yml`   | `reports/report_*/results.xml` | `GDUnit4 unit tests${RUNNER_SUFFIX}`       |
| `tests/ci/`    | `test_ci_scripts.yml` | `reports/ci-scripts/junit.xml` | `CI/CD infrastructure tests (tests/ci/)`   |
| Browser shards | `browser_test.yml`    | `artifacts/junit.xml`          | `Browser tests: ${SUITE}${RUNNER_SUFFIX}`  |

- **`test_ci_scripts.yml`:** `pytest tests/ci/` now writes `--junitxml=reports/ci-scripts/junit.xml`. It wrote no XML before.
- **`gdunit4_tests.yml`:** confirmed that gdUnit4 6.2.0 writes `reports/report_<n>/results.xml` (`report_1` on a fresh runner).
- **`browser_test.yml`:** removed the old xmllint "Test Report" step and the "Install System Dependencies" step, which only installed `libxml2-utils` for it. Each shard now makes one less `apt-get` call.

### 3. Tests (`tests/ci/`)

- **`test_test_summary.py` (new, 108 tests):**
  - counts and messages from a real XML sample for each job;
  - fail-fast and not-run detection, the GUT no-assertions note, the `testsuite` root;
  - missing, unreadable, non-JUnit and 0-test XML never showing ✅;
  - rendering: table, slowest tests, `|` in table cells, backtick runs in code spans, message length, failure cap;
  - always exiting 0, appending to the summary, printing to the log;
  - workflow wiring: `if: "always()"`, the XML paths, shard titles, `python3`, no `uses`, unchanged permissions, the gdUnit4 upload glob and the empty-shard here-doc;
  - 23 cases generated by CodeRabbit (`f1dca52`): nested suites, missing or non-integer counts, mixed outcomes in one test case, unnamed tests, bad and zero durations, the recursive glob, a read error on one file, the message and failure limits, and a crash while rendering.
- **`tests/ci/data/test_summary/` (new):** 5 XML samples, real output of the tools each job runs:
  - `gut_junit.xml`: GUT 9.7.1 on Godot 4.7.1-stable.
  - `gdunit4_results.xml`: gdUnit4 6.2.0 with `-c`.
  - `gdunit4_fail_fast.xml`: the same suite without `-c`, as CI runs it (4 declared, 1 result).
  - `pytest_xunit2.xml` and `pytest_legacy.xml`: pytest 9.1.1.
- **`test_browser_test_workflow.py`:** `test_test_report_runs_even_when_tests_fail` now checks the new step. New guard `test_xmllint_report_and_its_apt_install_were_removed`. No cases removed.

### 4. Docs

- **`Local_CI_Pipeline_for_Godot_Project_using_Docker.md`:** new "Test Result Summaries on the Run Page" section: what each table shows, the four jobs and their XML, the status rules, and how to run the script locally.

### 5. Also in this PR (not #1156)

The branch carries 8 commits that are not on `main`, so the PR shows them too:

- **Docstrings:** the bi-weekly GDScript docs run (#1172, `81386e9`) and `d1d9704` "Clarify input remap and slider docs": `audio_web_bridge.gd`, `web_telemetry_adapter.gd`, `input_remap_button.gd`, `volume_slider.gd`, `hud.gd`. Comments only, no code change.
- **Dependabot:** `markdownlint-cli2-action` 24.2.0 → 25.0.0 (#1173) and `create-pull-request` 8.1.1 → 8.1.2 (#1174).
- **Merges:** #1164, #1172, #1173, #1174.

---

## Design Decisions

- **Report only.** Like `test/benchmark/compare.py --report-only`, the script always exits 0. The test step alone decides whether the job passes, so the summary can neither fail a job nor hide a failure.
- **Counts come from `testcase` elements.** GUT's suite `failures` attribute counts failed asserts, not tests (3 in the sample, for 2 failed tests).
- **Messages:** pytest puts the message in the `message` attribute and the traceback in the text. GUT (`message="failed"`) and gdUnit4 (`message="FAILED: res://…:9"`) put it in the text. A message attribute that only names the outcome or location falls back to the text's first line.
- **No ✅ without evidence.** A run shows ✅ only when tests ran, nothing failed, every file was read, and every declared test has a result.
- **Text stays inside code spans.** Names and messages render as code spans whose fence is one backtick longer than the longest backtick run, so a name or message can't turn the rest of the line into Markdown. In the slowest-tests table, `|` is escaped as `\|`.
- **`python3` from the runner image.** It's there even if a step before `setup-python` failed. The shard name reaches the script through `env`, not pasted into it.
- **One summary step per test job, no combined table.** A combined table needs an extra job to collect the results (out of scope in #1156).
- **Removing xmllint in this PR.** The new step replaces the old report, and dropping `apt-get` removes a known way for the shard to hang on a dead mirror. This goes slightly beyond the steps #1156 lists.
- **gdUnit4 stays fail-fast.** Adding `-c` was considered and left out: the table flags the tests that didn't run instead.
- **The empty "Refactor Suite" shard shows ⚠️.** `tests/refactor/` has no tests yet, so the warning is accurate and goes away once it does.
- **Samples listed by name.** With a glob, missing samples made the script test skip instead of fail, as on the first PR run.
- **CodeRabbit's generated tests kept.** All 23 test real behavior. Two were changed to read the script's limits (`MAX_MESSAGE`, `MAX_FAILURES`) instead of hardcoding 200 and 50.

---

## Review Decisions

| Reviewer   | Finding                                                          | Decision                                                                                                                                                                                                                                                                                                |
|------------|------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Sourcery   | CI summary tests lack fixtures (Critical)                        | **Fixed in `d2e645e`:** the 5 XML samples were missing from the branch, which caused all 18 failures on the first PR run.                                                                                                                                                                               |
| CodeRabbit | Commit the five XML fixtures (Major)                             | **Fixed in `d2e645e` and `5acb995`:** the samples were added, then listed by name with `test_every_sample_is_present`, so a missing sample fails instead of skipping the script test.                                                                                                                   |
| Sourcery   | CI test step fails before reporting (Critical)                   | **Not applied:** pytest creates the `--junitxml` parent directory itself (`os.makedirs` in `LogXML.pytest_sessionfinish`). The first PR run, on a fresh runner, logged `generated xml file: …/reports/ci-scripts/junit.xml`.                                                                            |
| Sourcery   | Backticks expose failure text as Markdown (Medium)               | **Fixed in `5d2dc3b`:** the code-span fence is one backtick longer than the longest run in the text. 4 new test cases.                                                                                                                                                                                  |
| Sourcery   | Incorrect artifact path passes the check (Medium)                | **Fixed in `c28da42`:** the test matches `reports/report_1/results.xml` against each upload pattern with the upload action's glob rules, instead of a substring check.                                                                                                                                  |
| Sourcery   | Malformed empty-shard XML passes the check (Medium)              | **Fixed in `c28da42`:** the tests read the here-doc from `browser_test.yml` and parse it whole. The `EMPTY_SHARD_XML` copy was removed.                                                                                                                                                                 |
| DeepSource | Call to `next()` should be wrapped in `try-except` (Critical ×3) | **Fixed in `7eb901d`, differently:** `find_step()` and an assert with a message replace the 3 `next()` calls, so a missing match fails clearly instead of with a bare `StopIteration`. `try-except` would have hidden it.                                                                               |
| DeepSource | Docstring missing for `explode` (Minor)                          | **Fixed in `5acb995`.**                                                                                                                                                                                                                                                                                 |
| CodeRabbit | Use supported tags for the event types (Minor)                   | **Won't fix (owner):** valid. `validate_gdscript_docs.py` reports 3 unapproved tags in `get_matching_event()`. The docstring came from `d1d9704`, not #1156.                                                                                                                                            |
| CodeRabbit | Generated 23 test cases (`f1dca52`)                              | **Kept.** One found a real bug: under a single `testsuite` root, nested suites weren't counted, so the not-run check was off. **Fixed in `e6b0aee`:** `declared_tests()` now walks the root itself too. **Reworked in `4f4042f`:** two tests read the script's limits instead of hardcoding 200 and 50. |
| DeepSource | Formatting of the generated tests                                | **Fixed by autofix in `5a6eb23`** (Black and isort).                                                                                                                                                                                                                                                    |

---

## Verification

- **Real tool output:** the samples come from runs of Godot 4.7.1-stable with GUT 9.7.1 and gdUnit4 6.2.0, and of pytest 9.1.1, on a small sample suite. The gdUnit4 report path and fail-fast behavior were confirmed there.
- **Real suites through the script:** the full GUT suite (874 tests) rendered "✅ All 874 tests passed." with its 5 slowest tests. A full `tests/ci/` run rendered its failure with name and message.
- **First PR run (`329b97f`, Pull Request Pipeline #3202):** the Test Results Summary step succeeded in the GUT, GDUnit4 and `tests/ci/` jobs, and ran after the `tests/ci/` test step failed (the 18 failures from the missing samples). The browser shards were skipped in that run.
- **Later PR runs:** the runs on `d2e645e`, `5acb995`, `5d2dc3b` and `f1dca52` were cancelled by newer pushes.
- **PR run on `c28da42` (Pull Request Pipeline):** every job succeeded: GUT, GDUnit4, `tests/ci/`, all three browser shards (Core Web Flows, Refactor Suite, CI & Security) and both benchmarks. The Test Results Summary step succeeded in each test job. The run as a whole shows as cancelled.
- **PR run on `5a6eb23`:** failed in the `tests/ci/` job, as expected: CodeRabbit's tests without the `declared_tests()` fix, so `test_nested_suite_counts_only_leaf_declarations[testsuite]` fails there.
- **PR run on `76a11b5` (after `e6b0aee` and `4f4042f`):** every test job passed: GUT, GDUnit4, `tests/ci/` and all three browser shards. The benchmarks were still running when this note was updated.
- **Locally on the final code:** `tests/ci/test_test_summary.py` 108 passed, and the full `tests/ci/` run passed except `test_injection_readonly_file`, which fails only when tests run as root (sandbox). yamllint, black and markdownlint are clean.
- **Tests catch the bugs:** breaking the code on purpose made the tests fail each time:
  - deleting the samples: 20 failures, none skipped;
  - an indented `<?xml` line in the empty-shard here-doc;
  - a `reports/**/results.html` upload path.
- **Tests catch the bugs (CodeRabbit):** before the `declared_tests()` fix, `test_nested_suite_counts_only_leaf_declarations[testsuite]` failed with 0 declared tests instead of 3.
- **Not verified:** the rendered tables on the Summary page (viewed signed out, where GitHub shows no job summaries), and a failing test on a real run after the samples were added.

---

## Known Limitations / Follow-ups

- **gdUnit4 fail-fast:** a failing gdUnit4 run lists only the first failing test, plus a note on how many didn't run.
- **Refactor Suite shard:** shows "⚠️ No tests ran" on every run until `tests/refactor/` has tests.
- **GUT risky tests:** counted as passed, so the table can disagree with GUT's own "Passing Tests" count. The note shows how many.
- **`input_remap_button.gd` docstring:** fails `validate_gdscript_docs.py` with 3 unapproved tags (won't fix in this PR). The bi-weekly docs run may flag or rewrite it.
- **Path filters:** a PR that changes only `test_summary.py` runs the `tests/ci/` job, but not GUT, GDUnit4 or the browser shards, so their tables appear only when their own files change.
- **Extra commits:** 8 commits not on `main` (docstrings, Dependabot bumps, merges) are part of this PR.
- **PR description:** still the unfilled template. Sourcery and CodeRabbit added their summaries below it.
- **Out of scope (#1156):** a combined table across jobs, and comparing test counts with `main` to flag disappearing tests.
- **Reviews:** Qodo reviews were paused, so Qodo didn't review this PR.

---

## Reviewer's Guide

### File-Level Changes

| Change                    | Details                                                                                                                                                                                    | Files                                                                                                                                                                                                                                                                                            |
|---------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Reporter.                 | <ul><li>JUnit parsing and counts, nested suites included.</li><li>Status rules and not-run detection.</li><li>GUT no-assertions note.</li><li>Markdown rendering, always exit 0.</li></ul> | `.github/scripts/test_summary.py`                                                                                                                                                                                                                                                                |
| Workflow steps.           | <ul><li>Test Results Summary step with `if: "always()"`.</li><li>`--junitxml` for `tests/ci/`.</li></ul>                                                                                   | `.github/workflows/gut_tests.yml`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/test_ci_scripts.yml`<br/>`.github/workflows/browser_test.yml`                                                                                                                                 |
| xmllint removal.          | <ul><li>Old "Test Report" step removed.</li><li>"Install System Dependencies" (`libxml2-utils`) removed.</li><li>Test rewritten, new guard.</li></ul>                                      | `.github/workflows/browser_test.yml`<br/>`tests/ci/test_browser_test_workflow.py`                                                                                                                                                                                                                |
| Tests and samples.        | <ul><li>108 tests, 23 of them generated by CodeRabbit.</li><li>5 real XML samples.</li></ul>                                                                                               | `tests/ci/test_test_summary.py`<br/>`tests/ci/data/test_summary/gut_junit.xml`<br/>`tests/ci/data/test_summary/gdunit4_results.xml`<br/>`tests/ci/data/test_summary/gdunit4_fail_fast.xml`<br/>`tests/ci/data/test_summary/pytest_xunit2.xml`<br/>`tests/ci/data/test_summary/pytest_legacy.xml` |
| Docs.                     | <ul><li>Test Result Summaries section.</li></ul>                                                                                                                                           | `files/docs/Local_CI_Pipeline_for_Godot_Project_using_Docker.md`                                                                                                                                                                                                                                 |
| Docstrings (not #1156).   | <ul><li>Native BBCode docstrings, no code change.</li></ul>                                                                                                                                | `scripts/system/audio_web_bridge.gd`<br/>`scripts/system/web_telemetry_adapter.gd`<br/>`scripts/ui/components/input_remap_button.gd`<br/>`scripts/ui/components/volume_slider.gd`<br/>`scripts/ui/hud.gd`                                                                                        |
| Action bumps (not #1156). | <ul><li>`markdownlint-cli2-action` 25.0.0.</li><li>`create-pull-request` 8.1.2.</li></ul>                                                                                                  | `.github/workflows/lint_readme.yml`<br/>`.github/workflows/bi_weekly_gd_docstrings.yml`                                                                                                                                                                                                          |

### Assessment against linked issues

| Issue                                                   | Objective                                                                       | Addressed | Explanation                                                                                                                             |
|---------------------------------------------------------|---------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1156> | All four test jobs show a results table on a real run's Summary page            | 🟡        | On `c28da42`, the step succeeded in all four jobs and all three browser shards. The rendered tables are still to check while signed in. |
| <https://github.com/ikostan/SkyLockAssault/issues/1156> | Each browser shard shows its own table                                          | ✅         | On `c28da42`, each shard ran its own step, titled with its suite name.                                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1156> | A failing test appears with its name and message, also when the test step fails | ✅         | Tested with every sample. On `329b97f`, the step ran after the `tests/ci/` test step failed.                                            |
| <https://github.com/ikostan/SkyLockAssault/issues/1156> | Missing, unreadable and 0-test XML each say so, never ✅                         | ✅         | Tested, plus non-JUnit XML and tests that didn't run.                                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1156> | The script always exits 0                                                       | ✅         | Tested with failing samples, bad arguments, a crash and an unwritable summary file.                                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1156> | The parser is tested with a real XML sample from each of the four jobs          | ✅         | Real output of each job's tool and version, from a small sample suite.                                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1156> | Permissions don't change, and no third-party action is added                    | ✅         | Tested: permissions unchanged, no `uses` in the summary steps.                                                                          |
| <https://github.com/ikostan/SkyLockAssault/issues/1156> | `pytest tests/ci/` passes; no test cases removed                                | ✅         | Passed on `76a11b5`, with the `declared_tests()` fix. One test was rewritten, none removed.                                             |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1156 and set its scope and acceptance criteria.
- Decided the open questions: gdUnit4 stays fail-fast, GUT tests with no assertions get a note without changing the counts, the empty Refactor Suite shard keeps its ⚠️, and the xmllint report goes in this PR.
- Brought back the CI log and every DeepSource, Sourcery and CodeRabbit finding for assessment, and applied all the code to the PR branch.
- Checked locally that the sample XML files had never been created, added them, and answered the Sourcery `--junitxml` thread and the CodeRabbit docstring thread.
- Had Claude review CodeRabbit's generated tests, and applied the `declared_tests()` fix and the two reworked tests.
- Commits by @ikostan:
  - #1156:
    - `7fea0a3` Add JUnit test summaries to CI runs
    - `c81d7ff` Report GUT tests with no assertions
    - `329b97f` Remove xmllint from browser test workflow
    - `d2e645e` Add test summary XML fixtures
    - `7eb901d` Test GUT no-assertion summaries
    - `5acb995` Make test summary fixtures explicit
    - `5d2dc3b` Handle backtick runs in Markdown code spans
    - `c28da42` Verify browser shard XML and report globs
    - `e6b0aee` Simplify test suite traversal
    - `4f4042f` Use configured limits in summary tests
    - `27788d4` Document CI test summary implementation
    - `76a11b5` Document nested-suite summary fixes
  - Not #1156:
    - `d1d9704` Clarify input remap and slider docs
    - `19d2f3d` Merge pull request #1164 from ikostan/main
    - `44e27e7` Merge pull request #1172 from ikostan/automation/weekly-gdscript-docs
    - `93da30f` Merge pull request #1173 (markdownlint-cli2-action 25.0.0)
    - `a6cb5ae` Merge pull request #1174 (create-pull-request 8.1.2)

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Real samples**
    - Ran Godot 4.7.1-stable with GUT 9.7.1 and gdUnit4 6.2.0, and pytest 9.1.1 in both XML formats, to capture the 5 samples.
    - Found that gdUnit4 stops at the first failing test without `-c`, that GUT's suite `failures` attribute counts asserts, and that GUT and gdUnit4 keep the message in the element text.
    - Ran the real GUT suite and the real `tests/ci/` run through the script.
  - **Open questions**
    - Raised gdUnit4 fail-fast, GUT risky tests, the empty shard and the redundant xmllint step, with a recommendation for each.
  - **Review findings**
    - Checked each DeepSource, Sourcery and CodeRabbit finding against the code. Wrote the fixes for 8 findings. Showed the Sourcery `--junitxml` finding was wrong, with pytest's source and the PR's own log. Confirmed the CodeRabbit docstring finding with `validate_gdscript_docs.py`.
  - **CodeRabbit's generated tests**
    - Ran all 23 against the script: 22 passed, and 1 exposed the nested-suite bug. Wrote the `declared_tests()` fix and changed two tests to read the script's limits.

- **@sourcery-ai**
  - Posted the PR summary, the Reviewer's Guide and the linked-issue check (12 of 14 met, 2 to check by hand).
  - Posted 5 inline comments: 4 fixed, 1 answered without a change.

- **@coderabbitai**
  - Posted the walkthrough, the pre-merge checks and the PR summary.
  - Posted 2 actionable comments: 1 fixed, 1 won't fix.
  - Generated 23 test cases; one found the nested-suite bug.
  - Commits:
    - `f1dca52` Add regression tests for test summary parsing and reporting edge cases

- **@deepsource-io**
  - Python and JavaScript analysis on `e841d24...c28da42`.
  - Posted 4 inline comments: 3 `next()` calls and 1 missing docstring, all fixed.
  - Commits:
    - `5a6eb23` style: format code with Black and isort

- **@dependabot**
  - Commits:
    - `fd6b830` Bump DavidAnson/markdownlint-cli2-action from 24.2.0 to 25.0.0
    - `7c2d1b5` Bump peter-evans/create-pull-request from 8.1.1 to 8.1.2

- **@qodo-code-review**
  - Reviews were paused for this user, so Qodo didn't review this PR.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
