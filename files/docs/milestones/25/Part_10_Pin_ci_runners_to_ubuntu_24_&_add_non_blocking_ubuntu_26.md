<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Pin CI runners to ubuntu-24.04 and add a non-blocking Ubuntu 26.04 test run

---

## PR #1023 Summary

**Title:** Pin CI runners to ubuntu-24.04 and add a non-blocking Ubuntu 26.04 test run  
**Author:** @ikostan  
**Linked issue:** [#1008 – [FEATURE] Pin CI runners to ubuntu-24.04 and add a non-blocking Ubuntu 26.04 test run](https://github.com/ikostan/SkyLockAssault/issues/1008)  
**Milestone:** Milestone 25: Resource Migration & Audio Decoupling  
**Labels:** documentation, enhancement, CI/CD, github actions  

### Purpose

Stabilize CI by pinning runners to Ubuntu 24.04 (instead of floating `ubuntu-latest`) and add an advisory Ubuntu 26.04 run of the full test suite on pushes to `main`, so the newer runner image is exercised without blocking the security scans or the itch.io deploy.

### Key Changes

- **Runner pinning**
  - Replace `ubuntu-latest` with `ubuntu-24.04` across all workflows
  - Add a `runner` input (default `ubuntu-24.04`) to reusable test workflows (`gdunit4_tests`, `gut_tests`, `test_ci_scripts`, `browser_test`)
- **Ubuntu 26.04 advisory run**
  - New reusable `test_suite.yml` runs GDUnit4, GUT, CI/CD infrastructure tests, and browser tests on one runner
  - `lint_test_deploy.yml` calls it twice in parallel: `tests_ubuntu_24` (gates CodeQL/Snyk/Trivy and deploy) and `tests_ubuntu_26` (advisory; nothing depends on it)
  - Runs on pushes to `main` only; PRs stay on 24.04
  - Configurable `upload_coverage` on browser tests so the 26.04 run does not upload to Codecov
  - Runner-specific artifact names and Playwright cache key (`RUNNER_SUFFIX`) prevent collisions between the two runs
- **Workflow wiring validation**
  - actionlint 1.7.7 (checksum-verified) added to `yamllint.yml`
- **Regression tests**
  - `tests/ci/test_runner_pinning.py` guards: no `ubuntu-latest`, `runner` inputs and defaults, artifact/cache isolation, coverage toggle, `test_suite.yml` composition, the advisory 26.04 call, and scans gated on 24.04
  - `tests/ci/test_browser_test_workflow.py` updated for the runner-specific failure-artifact name
- **Related chores**
  - License header updates to PolyForm-Noncommercial-1.0.0 on remaining files (merged via related relicense work)
  - Milestone documentation for the runner migration

### Intent / Behavior

- CI and deploy gates stay on Ubuntu 24.04
- Ubuntu 26.04 results are advisory only: if the 26.04 run fails, the "Main CI/CD Pipeline" run shows red, but the scans and the deploy still complete
- The first 26.04 result arrives after merge (the run only executes on pushes to `main`)
- Coverage uploads, artifacts, and caches do not cross-contaminate between runner versions

### Review Notes

- @sourcery-ai – summary + Reviewer's Guide
- @coderabbitai – review / autofix support
- @deepsource-io – automated review + style autofix commit

---

## Reviewer's Guide

The PR stabilizes CI by replacing floating Ubuntu runners with Ubuntu 24.04, centralizing required tests in a reusable parameterized suite, and adding an isolated Ubuntu 26.04 advisory run. Runner-aware artifact and cache names prevent cross-version collisions, actionlint and structural pytest guards validate workflow wiring, and the touched CI, infrastructure, and test files receive updated PolyForm license identifiers.

### File-Level Changes

| Change                                                                                                       | Details                                                                                                                                                                                                                                                                                                                                                                                                                       | Files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
|--------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Pin GitHub Actions workflows to Ubuntu 24.04 while exposing runner selection for reusable test workflows.    | <ul><li>Replace floating ubuntu-latest assignments with ubuntu-24.04 across project workflows.</li><li>Add configurable runner inputs, defaulting to ubuntu-24.04, to the unit, infrastructure, and browser test workflows.</li></ul>                                                                                                                                                                                         | `.github/workflows/bi_weekly_gd_docstrings.yml`<br/>`.github/workflows/browser_test.yml`<br/>`.github/workflows/codeql.yml`<br/>`.github/workflows/deploy_to_itch.yml`<br/>`.github/workflows/gdlint.yml`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`<br/>`.github/workflows/lint_readme.yml`<br/>`.github/workflows/lint_test_on_pull.yml`<br/>`.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml`<br/>`.github/workflows/snyk.yml`<br/>`.github/workflows/stale.yml`<br/>`.github/workflows/test_ci_scripts.yml`<br/>`.github/workflows/trivy.yml` |
| Consolidate the required test gates and advisory Ubuntu 26.04 coverage through a shared reusable test suite. | <ul><li>Introduce test_suite.yml to orchestrate GDUnit4, GUT, CI infrastructure, and browser tests on one selected runner.</li><li>Run the suite on Ubuntu 24.04 as the required gate and Ubuntu 26.04 as an independent advisory run.</li><li>Keep CodeQL, Snyk, and Trivy dependent only on the Ubuntu 24.04 suite.</li><li>Disable 26.04 Codecov uploads while preserving coverage uploads for the required run.</li></ul> | `.github/workflows/test_suite.yml`<br/>`.github/workflows/lint_test_deploy.yml`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Isolate artifacts and Playwright caches between Ubuntu runner versions.                                      | <ul><li>Add a runner-derived suffix to build, report, diagnostic, and test artifacts.</li><li>Include the runner suffix in the Playwright cache key.</li><li>Make browser coverage upload conditional on the reusable workflow input.</li></ul>                                                                                                                                                                               | `.github/workflows/browser_test.yml`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`<br/>`tests/ci/test_browser_test_workflow.py`                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Add structural regression coverage and workflow wiring validation for the CI migration.                      | <ul><li>Assert runner pinning, reusable workflow inputs, artifact/cache isolation, coverage behavior, suite composition, and advisory dependency boundaries.</li><li>Install actionlint with a verified checksum and run it from the YAML lint workflow.</li><li>Verify the PR pipeline continues using the Ubuntu 24.04 defaults.</li></ul>                                                                                  | `tests/ci/test_runner_pinning.py`<br/>`.github/workflows/yamllint.yml`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Relicense the affected source, test, infrastructure, and CI files under PolyForm-Noncommercial-1.0.0.        | <ul><li>Replace GPL-3.0-or-later SPDX identifiers in scripts, workflows, Docker/infrastructure files, and test sources.</li></ul>                                                                                                                                                                                                                                                                                             | `.github/scripts/flatten_export.sh`<br/>`.github/scripts/patch_index_js.sh`<br/>`.github/scripts/serve_web_export.py`<br/>`Dockerfile`<br/>`obsolete/godot_4.5_stable/Dockerfile`<br/>`infra/docker-compose.yml`<br/>`workspace/run_pipeline.sh`<br/>`tests/conftest.py`<br/>`test/gdunit4/test_audio_manager.gd`<br/>`test/gut/test_audio_integration.gd`                                                                                                                                                                                                                                                                  |
| Document the runner migration and the Ubuntu 26.04 advisory run.                                             | <ul><li>Add milestone notes for this part.</li></ul>                                                                                                                                                                                                                                                                                                                                                                          | `files/docs/milestones/25/Part_10_Pin_ci_runners_to_ubuntu_24_&_add_non_blocking_ubuntu_26.md`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

### Assessment against linked issues

| Issue                                                 | Objective                                                                                                                                                                                                                    | Addressed | Explanation |
|-------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/1008 | Pin all GitHub Actions workflows to Ubuntu 24.04 instead of the floating `ubuntu-latest` label.                                                                                                                              | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/1008 | Run the complete test suite on Ubuntu 26.04 in parallel with the required Ubuntu 24.04 suite, while keeping Ubuntu 24.04 as the gate for security scans and deployment and ensuring the 26.04 run does not block those jobs. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/1008 | Make reusable test workflows configurable by runner, prevent cross-runner artifact/cache collisions and Codecov contamination, and validate the workflow wiring with regression tests and actionlint.                        | ✅        |             |

### Possibly linked issues

- **#1008**: PR #1023 directly implements issue #1008 by pinning runners and adding an advisory Ubuntu 26.04 full-test run.

---

## PR #1023 Summary: Bots / AI Contributions

**PR:** [Pin CI runners to ubuntu-24.04 and add a non-blocking Ubuntu 26.04 test run](https://github.com/ikostan/SkyLockAssault/pull/1023)  
**Title:** Pin CI runners to ubuntu-24.04 and add a non-blocking Ubuntu 26.04 test run  
**Author / primary contributor:** @ikostan  
**Linked issue:** #1008  

### Human contribution (@ikostan)

- Authored the core CI work: pinned workflows to `ubuntu-24.04`, added configurable `runner` / `upload_coverage` inputs on reusable test workflows, replaced the initial standalone canary with the dual-runner `test_suite.yml`, added actionlint and regression tests for runner pinning, and handled related license/header and workflow cleanup.
- Notable commits by @ikostan include:
  - Merge of relicense PR (`90856b3`)
  - `ci: pin runners to ubuntu-24.04 and add non-blocking Ubuntu 26.04 canary` (`dccae1d`) — co-authored with Claude
  - `Update .gitignore` (`85d85f5`)
  - Follow-ups: remove the canary workflow, dual-runner test suite wiring, actionlint in yamllint, tests, docs (`e2e2230`, `3390c9e`, `d0deb77`, `43ff328`, `9b4e006`, `f165cbf`)
  - Relicense commit (`97ea7c4`) — co-authored with Claude
- Added the PR to Milestone 25, self-assigned, applied labels (documentation, enhancement, CI/CD, github actions), and linked issue #1008.

### Bots / AI contributions

- **@coderabbitai**  
  - Participated with review/autofix messaging and finishing-touches support on the PR.

- **@sourcery-ai**  
  - Generated "Summary by Sourcery" (features, bug fixes, enhancements, CI, tests, chores).  
  - Produced Reviewer's Guide with flow diagram and file-level change analysis.  
  - Posted review-related activity (including rate-limit notices on this PR).

- **@deepsource-io** (DeepSource / DeepSourceReview / deepsource-autofix)  
  - Ran automated code review and posted PR Report Card (Security / Reliability / Complexity / Hygiene) with analyzer links.  
  - Authored style fix commit: `style: format code with Black and isort` (`1575fc9`).

- **Claude Opus 5.5**  
  - Listed as AI co-author (`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`) on `dccae1d` and `97ea7c4`.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->