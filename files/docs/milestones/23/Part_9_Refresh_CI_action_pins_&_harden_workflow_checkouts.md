<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Refresh CI action pins and harden workflow checkouts

---

## PR #941 Summary: Refresh CI action pins and harden workflow checkouts

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan (consolidates @dependabot bumps)  
**Branch:** `maintenance` → `main`  
**Related:** Merges Dependabot PRs #938, #939, #940 (plus #937 sync from main)  
**Milestone:** Milestone 23 – Settings Architecture & FPS Counter Implementation  
**Labels:** CI/CD, dependencies, github actions, dependabot, github_actions

### Purpose

Modernize pinned GitHub Actions across the repository’s automation and tighten checkout security by disabling credential persistence where appropriate—without changing workflow logic or job behavior.

### Core Improvements

#### 1. Action pin refreshes (via Dependabot, merged here)

| Action                              | From  | To        |
|-------------------------------------|-------|-----------|
| **actions/checkout**                | 4.2.2 | **7.0.1** |
| **actions/setup-python**            | 5.4.0 | **7.0.0** |
| **peter-evans/create-pull-request** | 7.0.8 | **8.1.1** |

Applied consistently across CI surfaces, including:

- Docs / docstrings (`bi_weekly_gd_docstrings.yml`)
- Browser, GDUnit4, GUT, and CI-script tests
- Lint (gdlint, yamllint, lint_readme)
- Security (CodeQL, Snyk, Trivy)
- Deploy (`deploy_to_itch.yml`)

#### 2. Checkout hardening

- Set `persist-credentials: false` on applicable `actions/checkout` steps to reduce credential exposure in downstream job steps

#### 3. Small fixes / docs

- Correct configured **gdcov** coverage-tool path for local/CI test execution
- Milestone documentation for this maintenance work under Milestone 23
- Project configuration version metadata touch-up as noted in the PR summary

### Benefits

- Predictable, up-to-date Action revisions across validation, testing, security, and deploy jobs
- Slightly stronger CI security posture (no lingering checkout credentials)
- Clearer local coverage tooling path
- Low runtime risk: workflow inputs and job structure largely unchanged

### Status Notes

Maintenance PR focused on dependency/security hygiene for GitHub Actions under Milestone 23. Sourcery/CodeRabbit noted minor annotation consistency (e.g. inline version comments matching pinned SHAs) as follow-up polish rather than functional blockers.

---

## Reviewer's Guide

This maintenance PR updates GitHub Actions to newer pinned releases across the repository, disables unnecessary checkout credential persistence to reduce CI credential exposure, and documents the maintenance while adjusting related coverage configuration and project metadata. Workflow job logic and inputs are intended to remain unchanged.

### File-Level Changes

| Change                                                                                                                             | Details                                                                                                                                                                                                                            | Files                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
|------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Refresh pinned GitHub Actions versions across CI, security, testing, linting, documentation, deployment, and automation workflows. | <ul><li>Update checkout action references to v7.0.1, including SHA-pinned uses where already pinned.</li><li>Update Python setup action references to v7.0.0.</li><li>Update pull-request creation automation to v8.1.1.</li></ul> | `.github/workflows/bi_weekly_gd_docstrings.yml`<br/>`.github/workflows/browser_test.yml`<br/>`.github/workflows/codeql.yml`<br/>`.github/workflows/deploy_to_itch.yml`<br/>`.github/workflows/gdlint.yml`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`<br/>`.github/workflows/lint_readme.yml`<br/>`.github/workflows/snyk.yml`<br/>`.github/workflows/test_ci_scripts.yml`<br/>`.github/workflows/trivy.yml`<br/>`.github/workflows/yamllint.yml` |
| Harden workflow checkout security by preventing persisted GitHub credentials where downstream steps do not need them.              | <ul><li>Add persist-credentials: false to applicable checkout steps.</li><li>Retain existing full-history, ref, and checkout behavior where required by workflows.</li></ul>                                                       | `.github/workflows/gdlint.yml`<br/>`.github/workflows/lint_readme.yml`<br/>`.github/workflows/snyk.yml`<br/>`.github/workflows/test_ci_scripts.yml`<br/>`.github/workflows/bi_weekly_gd_docstrings.yml`<br/>`.github/workflows/browser_test.yml`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`                                                                                                                                                      |
| Record the CI maintenance work and associated project configuration updates.                                                       | <ul><li>Add Milestone 23 documentation describing action upgrades and checkout hardening.</li><li>Adjust the configured coverage-tool path and project metadata.</li></ul>                                                         | `files/docs/milestones/23/Part_9_Refresh_CI_action_pins_&_harden_workflow_checkouts.md`<br/>`project.godot`                                                                                                                                                                                                                                                                                                                                                                           |

---

## PR #941 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@dependabot**  
  Authored the core dependency-bump commits:
  - `actions/checkout` **4.2.2 → 7.0.1**
  - `peter-evans/create-pull-request` **7.0.8 → 8.1.1**
  - `actions/setup-python` **5.4.0 → 7.0.0**  
  (Merged into this branch via #938, #939, and #940.)

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (including a nitpick on a stale `create-pull-request` version annotation in workflow comments).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the action-pin refresh and checkout hardening (low merge risk; feedback on version annotations / checkout consistency).

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **60.47%**, **+1.70%** vs base; all modified coverable lines covered; all tests successful).

### Human Contributor

- **@ikostan**  
  Primary owner of the PR. Consolidated the Dependabot bumps into this maintenance branch (merges of #937–#940), fixed the `gdcov` coverage path, bumped the PR-creation action and added Milestone 23 documentation, and hardened CI by disabling credential persistence on checkouts across documentation, testing, linting, security, and deployment workflows.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
