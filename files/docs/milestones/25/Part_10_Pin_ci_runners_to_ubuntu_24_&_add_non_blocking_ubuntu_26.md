<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Pin ci runners to ubuntu 2404 and add a non blocking ubuntu 2604 canary

---

## PR #1023 Summary

**Title:** Pin ci runners to ubuntu 2404 and add a non blocking ubuntu 2604 canary  
**Author:** @ikostan  
**Linked issue:** [#1008 – [FEATURE] Pin CI runners to ubuntu-24.04 and add a non-blocking Ubuntu 26.04 test run](https://github.com/ikostan/SkyLockAssault/issues/1008)  
**Milestone:** Milestone 25: Resource Migration & Audio Decoupling  
**Labels:** documentation, enhancement, CI/CD, github actions  

### Purpose

Stabilize CI by pinning runners to Ubuntu 24.04 (instead of floating `ubuntu-latest`) and add an advisory Ubuntu 26.04 canary path so newer runner images can be exercised without blocking required PR or deploy gates.

### Key Changes

- **Runner pinning**
  - Replace `ubuntu-latest` with `ubuntu-24.04` across standard workflows
  - Add a `runner` input (default `ubuntu-24.04`) to reusable test workflows (`gdunit4_tests`, `gut_tests`, `test_ci_scripts`, `browser_test`)
- **Ubuntu 26.04 canary (advisory)**
  - Independent canary workflow (manual + weekly) running the same test suites on `ubuntu-26.04`
  - Not wired into blocking PR/deploy pipelines
  - Configurable `upload_coverage` on browser tests so the canary does not upload to Codecov
  - Artifact/cache naming isolated to avoid collisions across runner versions
- **Regression tests**
  - `tests/ci/test_runner_pinning.py` guards pinning, canary isolation, coverage behavior, and pipeline separation
- **Related chores**
  - License header updates to PolyForm-Noncommercial-1.0.0 on remaining files (merged via related relicense work)
  - Workflow/docs refinements (canary rework, dual-runner wiring, yamllint, documentation)

### Intent / Behavior

- Required CI and deploy gates stay on Ubuntu 24.04
- Ubuntu 26.04 results are advisory only
- Coverage uploads and caches do not cross-contaminate between runner versions

### Review Notes

- @sourcery-ai – summary + Reviewer’s Guide
- @coderabbitai – review / autofix support
- @deepsource-io – automated review + style autofix commit
- @codecov – affected via configurable coverage upload for canary path
- @dependabot, @github-copilot-cli – no direct contributions observed on this PR  
  (some commits co-authored with Claude Opus 5.5, separate from GitHub Copilot)

---



---

## PR #1023 Summary: Bots / AI Contributions

**PR:** [Pin ci runners to ubuntu 2404 and add a non blocking ubuntu 2604 canary](https://github.com/ikostan/SkyLockAssault/pull/1023)  
**Title:** Pin ci runners to ubuntu 2404 and add a non blocking ubuntu 2604 canary  
**Author / primary contributor:** @ikostan  
**Linked issue:** #1008  

### Human contribution (@ikostan)

- Authored the core CI work: pinned workflows to `ubuntu-24.04`, added configurable `runner` / `upload_coverage` inputs on reusable test workflows, introduced (and later refined) the Ubuntu 26.04 canary approach, added regression tests for runner pinning, and handled related license/header and workflow cleanup.
- Notable commits by @ikostan include:
  - Merge of relicense PR (`90856b3`)
  - `ci: pin runners to ubuntu-24.04 and add non-blocking Ubuntu 26.04 canary` (`dccae1d`) — co-authored with Claude
  - `Update .gitignore` (`85d85f5`)
  - Follow-ups: remove/rework canary, dual-runner test suite wiring, yamllint, docs (`e2e2230`, `3390c9e`, `d0deb77`, `43ff328`, `9b4e006`, etc.)
  - Relicense commit (`97ea7c4`) — co-authored with Claude
- Added the PR to Milestone 25, self-assigned, applied labels (documentation, enhancement, CI/CD, github actions), and linked issue #1008.

### Bots / AI contributions

- **@coderabbitai**  
  - Participated with review/autofix messaging and finishing-touches support on the PR.

- **@sourcery-ai**  
  - Generated “Summary by Sourcery” (features, bug fixes, enhancements, CI, tests, chores).  
  - Produced Reviewer’s Guide with flow diagram and file-level change analysis.  
  - Posted review-related activity (including rate-limit notices on this PR).

- **@deepsource-io** (DeepSource / DeepSourceReview / deepsource-autofix)  
  - Ran automated code review and posted PR Report Card (Security / Reliability / Complexity / Hygiene) with analyzer links.  
  - Authored style fix commit: `style: format code with Black and isort` (`1575fc9`).

- **@codecov**  
  - Indirectly impacted: browser-test workflow gained a configurable `upload_coverage` input so the Ubuntu 26.04 canary path does not upload to Codecov; isolation of coverage behavior is part of the PR design and regression tests.

- **@dependabot**  
  - No direct commits, dependency bumps, or review comments observed on this specific PR.

- **@github-copilot-cli** (GitHub Copilot)  
  - No co-authored commits, reviews, or direct contributions observed on this specific PR.  
  - Note: some commits list **Claude Opus 5.5** (`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`) as an AI co-author; that is separate from `@github-copilot-cli`.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
