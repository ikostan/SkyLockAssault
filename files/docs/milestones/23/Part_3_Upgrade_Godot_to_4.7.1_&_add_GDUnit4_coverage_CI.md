# Upgrade Godot to 4.7.1 and add GDUnit4 coverage CI
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

## PR #902 Summary: Upgrade Godot to 4.7.1 and add GDUnit4 coverage CI

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `upgrade-godot-engine-to-471-stable` → `main`  
**Linked Issues:** #890 (Godot 4.7.1 upgrade), #891 (GUT v9.7.1), #892 (GDUnit4 v6.2.0 + coverage)  
**Milestone:** Milestone 23 – Settings Architecture & FPS Counter Implementation  
**Labels:** setup, tools, testing, CI/CD, integration, godot-upgrade, github actions, github_actions, CODECOV, GUT, QA, gdunit4

### Purpose

Upgrade the engine and test toolchain from Godot **4.6.3** to **4.7.1-stable**, refresh GUT and GDUnit4 for compatibility, and add resilient GDUnit4 code-coverage collection in CI (batched runs, merged LCOV, optional Codecov uploads).

### Core Improvements

#### 1. Godot 4.7.1 Across the Stack

- Project metadata, export templates, and runtime version-parity checks
- CI workflows: GDUnit4, GUT, browser tests, lint/test, deploy-to-itch, PR lint
- Development container (`Dockerfile`) aligned to 4.7.1 with matching templates
- Binary integrity: SHA verification and engine version checks in CI
- Bundled Godot license/copyright notices under `bin/`

#### 2. Test Framework Refresh

| Tool                 | Version                            |
|----------------------|------------------------------------|
| **GDUnit4**          | **v6.2.0**                         |
| **GUT**              | **v9.7.1**                         |
| **gdUnit4-coverage** | **v0.1.4** (GDExtension + `gdcov`) |

#### 3. GDUnit4 Coverage CI (`.github/workflows/gdunit4_tests.yml`)

- Install coverage GDExtension; resolve compatible `gdcov` runner
- Run under `xvfb`; stage suites in **two-file isolated batches** (stability)
- Capture per-batch LCOV, merge/sanitize paths → `final_coverage.lcov`
- Archive coverage + test reports as artifacts
- **Optional Codecov upload** only when `CODECOV_TOKEN` is present (safe for forks/Dependabot)
- Align reporting to production GDScript (`scripts/`), exclude tests and addons

#### 4. Codecov & Reporting Config

- Updated `.codecov.yml` (GDUnit4 flag, path filters)
- Removed legacy browser/GUT Codecov upload steps where superseded
- Token-gated install/upload so CI stays green without credentials

#### 5. Security / Pins

- Refreshed CodeQL SARIF upload pins in Snyk/Trivy workflows (via Dependabot merge)

#### 6. Documentation

- Milestone doc: `files/docs/milestones/23/Part_3_Upgrade_Godot_to_4.7.1_&_add_GDUnit4_coverage_CI.md`

### Benefits

- Single supported engine version (4.7.1) across local, CI, and deploy
- Native GDUnit4 coverage with mergeable LCOV and optional Codecov visibility
- More reliable GDUnit runs via batch isolation
- Safer CI for forks (no hard failure on missing Codecov token)
- Clearer coverage signal focused on production game scripts

### Status Notes

Addresses the objectives of #890, #891, and #892 for the engine upgrade, GUT/GDUnit4 refresh, and coverage CI under Milestone 23.

---

### File-Level Changes

| Change                                                                                           | Details                                                                                                                                                                                                                                                                                                                                                                                      | Files                                                                                                                                                                                                                                                                                                                                                     |
|--------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Standardize engine and test tooling on Godot 4.7.1 with integrity and compatibility checks.      | <ul><li>Updated reusable CI, browser, deployment, release, and development-container versions and checksums.</li><li>Added Godot runtime version-parity validation and refreshed export templates.</li><li>Upgraded GDUnit4 to 6.2.0 and GUT to 9.7.1; bundled Godot license notices.</li></ul>                                                                                              | `.github/workflows/browser_test.yml`<br/>`.github/workflows/deploy_to_itch.yml`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`<br/>`.github/workflows/lint_test_deploy.yml`<br/>`.github/workflows/lint_test_on_pull.yml`<br/>`Dockerfile`<br/>`bin/godot-COPYRIGHT.txt`<br/>`bin/godot-LICENSE.txt`<br/>`project.godot` |
| Add resilient GDUnit4 coverage generation and reporting to CI.                                   | <ul><li>Installs the GDUnit4 coverage GDExtension, dynamically resolves the compatible gdcov runner, and runs tests under xvfb.</li><li>Stages GDUnit4 suites in two-file batches, captures LCOV tracefiles, merges and sanitizes them, and restores the full test tree.</li><li>Archives coverage/test reports and skips Codecov installation/uploads when no token is available.</li></ul> | `.github/workflows/gdunit4_tests.yml`                                                                                                                                                                                                                                                                                                                     |
| Align coverage configuration with production GDScript sources and update reporting integrations. | <ul><li>Configures a GDUnit4 Codecov flag for scripts and excludes tests and addons.</li><li>Removes browser JavaScript coverage mappings and legacy browser/GUT Codecov report-upload steps.</li><li>Updates pinned CodeQL SARIF upload action revisions.</li></ul>                                                                                                                         | `.codecov.yml`<br/>`.github/workflows/browser_test.yml`<br/>`.github/workflows/gut_tests.yml`<br/>`.github/workflows/snyk.yml`<br/>`.github/workflows/trivy.yml`                                                                                                                                                                                          |
| Document the engine migration, dependency refresh, and coverage CI design.                       | <ul><li>Records the implementation approach and file-level changes.</li><li>Maps the changes to the associated upgrade and testing objectives.</li></ul>                                                                                                                                                                                                                                     | `files/docs/milestones/23/Part_3_Upgrade_Godot_to_4.7.1_&_add_GDUnit4_coverage_CI.md`                                                                                                                                                                                                                                                                     |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                      | Addressed | Explanation |
|------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/890 | Upgrade the project’s Godot engine from 4.6.3 to 4.7.1-stable across the Docker development environment, project metadata, CI workflows, browser and deployment workflows, and export tooling. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/890 | Ensure CI uses verified Godot 4.7.1 binaries, performs engine-version parity checks, and refreshes the GUT and GDUnit4 dependencies for compatibility with the upgraded engine.                | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/890 | Enable native GDUnit4 coverage execution under Godot 4.7.1, including gdcov setup, batched test execution, merged LCOV generation, artifact retention, and optional Codecov uploads.           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/891 | Upgrade GUT to v9.7.1 wherever it is installed or configured, including the containerized development environment.                                                                             | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/891 | Update the GUT CI workflow to use Godot 4.7.1-stable and dynamically download and configure GUT v9.7.1 during test setup.                                                                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/891 | Ensure the GUT test suite runs successfully under Godot 4.7.1-stable in headless CI with no test failures or newly introduced engine/plugin errors.                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/892 | Upgrade gdUnit4 to version 6.2.0 in the project’s CI and containerized development environments.                                                                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/892 | Install and enable gdUnit4-coverage version 0.1.4 as a GDExtension and configure headless CI execution with the gdcov runner.                                                                  | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/892 | Produce valid LCOV coverage from GDUnit4 test runs, including batch aggregation and path sanitization, and make the resulting report available for optional Codecov upload.                    | ✅        |             |

### Possibly linked issues

- **#TASK-1**: The PR directly implements the issue’s Godot 4.7.1 upgrade across environments and adds compatible coverage CI.

---

## PR #902 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Documented the Godot 4.7.1 upgrade path, GDUnit4 coverage CI design (batched runs, LCOV merge, optional Codecov), and mapped changes to linked upgrade/testing issues.

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the engine/toolchain upgrade, coverage batching, and reporting configuration.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@dependabot**  
  Authored the `github/codeql-action/upload-sarif` pin bump (merged via #904 into this branch).

- **@codecov**  
  Posted the Codecov coverage report on the PR (coverage diff, file impact, test status). Target of the optional LCOV/test-report uploads configured in this PR (token-gated so fork/Dependabot runs can skip cleanly).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Upgraded the project, Docker/dev container, CI, browser tests, and itch.io deploy paths from Godot 4.6.3 → **4.7.1-stable** with checksum and version-parity checks; refreshed **GDUnit4 v6.2.0** and **GUT v9.7.1**; enabled gdUnit4-coverage / `gdcov`; redesigned GDUnit4 CI for isolated two-file batches, merged/sanitized LCOV, artifact retention, and optional Codecov uploads; aligned `.codecov.yml` to production GDScript sources (excluding tests/addons); bundled Godot license notices; and documented the work under Milestone 23.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
