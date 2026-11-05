<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Skip web export and browser tests on PRs that only change Godot test files

---

## PR #1033 Summary

**Title:** Skip web export and browser tests on PRs that only change Godot test files  
**PR:** [#1033](https://github.com/ikostan/SkyLockAssault/pull/1033)  
**Branch:** `skip-web-export-and-browser-tests-on-prs-that-only-change-godot-test-files` → `main`  
**Author:** @ikostan  
**Linked issue:** [#1018 – [FEATURE] Skip web export and browser tests on PRs that only change Godot test files](https://github.com/ikostan/SkyLockAssault/issues/1018)  
**Follow-up to:** [#1017 – Harden CI workflows and isolate audio parsing tests](https://github.com/ikostan/SkyLockAssault/pull/1017)  
**Milestone:** Milestone 26: Comprehensive Architectural Review & Performance Benchmarking  
**Labels:** enhancement, testing, CI/CD, github actions, github_actions, YML  

### Purpose

Stop PRs that only change Godot test files (`test/**`) from running the web export, the three Playwright browser shards and gdlint. The web export drops `test/*` (`exclude_filter` in `export_presets.cfg`), so those files can never affect the game the browser tests exercise, and `gdlint.yml` only checks `./scripts`.

Since #1017, `detect-changes` diffs the **whole PR** against `pull_request.base.sha` on every run. That is intended (cancelled runs can no longer hide changes), but it made the old `test/**` → `gdscript` mapping more expensive: once a PR touched `test/`, **every** later push, docs-only ones included, ran the web export and all browser shards.

### Key Changes

- **Path filters** (`.github/workflows/lint_test_on_pull.yml`, `Filter Paths` step)
  - `predicate-quantifier: "some-with-excludes"` added, so `!` patterns exclude files instead of matching them
  - `gdscript` now ends with `'!test/**'`; the old `'test/**'` include is removed
  - New `godot_tests` filter containing `'test/**'`, exported from `detect-changes` as `godot_tests`
- **Job conditions** (same file)
  - `gdunit4_tests` and `gut_tests` run on `gdscript || godot_tests || <own workflow>`
  - `gdlint`, `browser_tests` and `ci_script_tests` are unchanged; with `test/**` gone from `gdscript`, gdlint and the browser suite now skip test-only PRs
- **Regression guard** (`tests/ci/test_pr_path_filters.py`, new)
  - Asserts the quantifier, the `'!test/**'` exclusion, the `godot_tests` filter and output, which jobs read `godot_tests`, and that only `gdscript` carries a `!` pattern
  - Fails if either the quantifier or `'!test/**'` is removed (both verified by mutation)
- **Dependency bumps merged into the branch** (Dependabot)
  - `actions/setup-node` 7.0.0 → 7.1.0 (`browser_test.yml`, #1031)
  - `release-drafter/release-drafter` 7.9.0 → 7.10.0 (`release_drafter.yml`, `release_drafter_pr.yml`, #1032)

### Design Decisions

- **Exclude inside `gdscript`, not with a second filter.** paths-filter evaluates each filter as "did any changed file match?". Excluding `test/**` inside `gdscript` makes the decision per file, so a test file can never turn `gdscript` on. ANDing `gdscript` with a separate "anything outside `test/`" filter (CodeRabbit's suggestion) is decided per filter: a PR changing `test/**` plus a README would still run the browser suite, and gdlint would still run on test-only PRs.
- **`some-with-excludes` is required.** Under the default `some` quantifier a `!` pattern is just another pattern that counts as a match, so `'!test/**'` alone would match every file outside `test/` and turn `gdscript` on for every PR, docs-only ones included.
- **Verified against the pinned action.** `src/filter.ts` at the pinned paths-filter SHA (`ceb8a2b`, v4.0.3) implements `some-with-excludes` as: a file counts if it matches at least one include pattern and no exclude pattern; an exclusion is final. Patterns are matched with picomatch, `dot: true`.
- **Other filters unaffected.** The quantifier applies to every filter in the step, but no other filter has a `!` pattern, so their results are unchanged. The new test enforces that.

### Expected Behavior

| PR changes only…                             | gdlint | GDUnit4 | GUT     | Browser |
| -------------------------------------------- | ------ | ------- | ------- | ------- |
| `test/gut/*.gd`                              | skip   | **run** | **run** | skip    |
| `scripts/**/*.gd`                            | run    | run     | run     | run     |
| `scenes/*.tscn` / `*.tres` / `project.godot` | run    | run     | run     | run     |
| `test/**` + `scripts/**`                     | run    | run     | run     | run     |
| `**/*.md` only                               | skip   | skip    | skip    | skip    |
| `.github/workflows/browser_test.yml`         | skip   | skip    | skip    | run     |

A `.tscn` or `.tres` file under `test/` follows the `test/**` row: unit tests only.

### Compatibility

- No gameplay or runtime change; CI configuration and CI tests only
- Real game changes (`.gd` outside `test/`, `.tscn`, `.tres`, `project.godot`) still trigger all four jobs
- Docs-only and workflow-only PRs behave exactly as before
- `lint_test_deploy.yml` (main pipeline) has no path filtering and still runs everything

### Testing

- Simulated every row of the table above through paths-filter's matching logic (picomatch, `dot: true`, include/exclude split as in `src/filter.ts`): all match
- `tests/ci/test_pr_path_filters.py`: 10 passed; each test-breaking mutation (quantifier removed, `'!test/**'` removed) fails 2 tests
- `test_workflow_policies.py`, `test_gdunit4_workflow.py`, `test_runner_pinning.py` and the new file: 82 passed against the edited workflow
- yamllint (`.yamllint.yaml`): no warnings on `lint_test_on_pull.yml`
- ruff check / ruff format: clean on the new test file
- [ ] Real PR: a change to one file under `test/gut/` runs GUT and GDUnit4 and skips gdlint and browser tests
- [ ] Same PR: a docs-only push runs the same jobs (the whole-PR diff still sees the test change)
- [ ] Real PR: a change to one file under `scripts/` runs all four jobs

### Follow-ups

- Whether `test/` should be linted by gdlint/gdformat is a separate question, out of scope here
- The browser workflow's "CI & Security" shard runs `tests/ci/*.py`; those tests are also run by `test_ci_scripts.yml`, so the shard duplicates them

---

## Reviewer's Guide

Splits Godot test files out of the PR pipeline's `gdscript` change filter so test-only PRs run the GUT and GDUnit4 suites but skip gdlint, the web export and the browser shards. The exclusion is done per file with paths-filter's `some-with-excludes` quantifier and a new `godot_tests` output, and a structural pytest guard keeps the mapping and the quantifier from regressing.

### File-Level Changes

| Change                                                    | Details                                                                                                                                                                                                                                                                                                                    | Files                                                                                                                           |
|-----------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| Route Godot test-only changes to the unit-test jobs only. | <ul><li>Enable <code>some-with-excludes</code> on the paths-filter step.</li><li>Exclude <code>test/**</code> from <code>gdscript</code> and add a <code>godot_tests</code> filter and output.</li><li>Run GDUnit4 and GUT on <code>godot_tests</code>; leave gdlint and browser tests on <code>gdscript</code>.</li></ul> | `.github/workflows/lint_test_on_pull.yml`                                                                                       |
| Guard the filter mapping against regressions.             | <ul><li>Parse the workflow and the nested <code>filters:</code> YAML string.</li><li>Assert quantifier, exclusion, new filter/output, job wiring, and that only <code>gdscript</code> uses <code>!</code> patterns.</li></ul>                                                                                              | `tests/ci/test_pr_path_filters.py`                                                                                              |
| Bump pinned GitHub Actions (Dependabot).                  | <ul><li><code>actions/setup-node</code> 7.0.0 → 7.1.0.</li><li><code>release-drafter/release-drafter</code> 7.9.0 → 7.10.0.</li></ul>                                                                                                                                                                                      | `.github/workflows/browser_test.yml`<br/>`.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml` |
| Record the implementation and review context.             | <ul><li>Add the milestone note for this part.</li></ul>                                                                                                                                                                                                                                                                    | `files/docs/milestones/26/Part_2_Skip_web_export_&_browser_tests_on_godot_test_only_PRs.md`                                     |

### Assessment against linked issues

| Issue                                                   | Objective                                                                                                             | Addressed | Explanation                                                 |
|---------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|-----------|-------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1018> | A PR changing only files under `test/` runs GUT and GDUnit4, and skips gdlint, the web export and all browser shards. | ✅        | Verified by simulation; confirm on a real PR (see Testing). |
| <https://github.com/ikostan/SkyLockAssault/issues/1018> | A PR changing any game file still runs all four jobs.                                                                 | ✅        |                                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1018> | Docs-only and workflow-only PRs behave exactly as before.                                                             | ✅        |                                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1018> | New `tests/ci/` checks pass, and fail if `'!test/**'` or the quantifier is removed.                                   | ✅        |                                                             |
| <https://github.com/ikostan/SkyLockAssault/issues/1018> | YAML Lint shows no new warnings.                                                                                      | ✅        |                                                             |

---

## PR #1033 Summary: Bots / AI Contributions

### Human contribution (@ikostan)

- Opened issue #1018 with the analysis, implementation plan and acceptance criteria, self-assigned it and added it to Milestone 26.
- Opened the PR, merged the Dependabot bumps into the branch, applied the filter split and regression test, and triaged the bot review comments.
- Notable commits by @ikostan:
  - `Merge pull request #1031` (`43958fb`), `Merge pull request #1032` (`5583b82`), `Merge pull request #1034` (`2faf03f`)
  - `ci: skip web export and browser tests on Godot-test-only PRs (#1018)` (`<sha>`)

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Verified the `some-with-excludes` semantics against `src/filter.ts` at the pinned paths-filter SHA.
  - Simulated the expected-behavior table and CodeRabbit's alternative through paths-filter's matching logic, and drafted the replies to the Sourcery and CodeRabbit findings.

- **@sourcery-ai**
  - Generated "Summary by Sourcery" (CI: pinned action updates).
  - Posted one review comment (Medium): Godot-only PRs run browser tests. Valid; fixed in the caller.

- **@coderabbitai**
  - Generated "Summary by CodeRabbit".
  - Posted one outside-diff comment (Minor) with a suggested `non_godot_test` fix. The issue is valid and fixed; the suggested fix was declined (see Review decisions).

- **@dependabot**
  - Opened the bumps merged into this branch: `actions/setup-node` 7.0.0 → 7.1.0 (#1031, `9dd38a9`) and `release-drafter/release-drafter` 7.9.0 → 7.10.0 (#1032, `b6518ae`).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
