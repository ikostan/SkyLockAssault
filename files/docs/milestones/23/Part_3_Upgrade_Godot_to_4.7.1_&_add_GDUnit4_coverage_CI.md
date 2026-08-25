# Upgrade Godot to 4.7.1 and add GDUnit4 coverage CI
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

Upgrade the project to Godot 4.7.1 and add resilient GDUnit4 code coverage reporting to the CI pipeline.

New Features:

- Add GDUnit4 coverage profiling to CI, including LCOV aggregation and Codecov uploads for coverage and test results.

Enhancements:

- Upgrade project tooling and CI workflows to Godot 4.7.1 with engine version and checksum validation.
- Update GDUnit4 and GUT test dependencies to newer releases.
- Improve GDUnit4 CI reliability by isolating test suites into memory-conscious batches and supporting unauthenticated runs without Codecov secrets.
- Align Codecov configuration with GDUnit4 coverage reporting and exclude test and addon sources from coverage.
- Refresh the development container with Godot 4.7.1 and updated export templates and testing dependencies.

---

## Reviewer's Guide

This PR upgrades the project and all containerized, testing, browser, CI, and deployment environments from Godot 4.6.3 to 4.7.1, refreshes the GDUnit4/GUT dependencies, and substantially redesigns GDUnit4 CI to generate merged GDScript LCOV coverage with optional Codecov uploads while tightening engine verification and scan integrations.

### File-Level Changes

| Change                                                                                                                                              | Details                                                                                                                                                                                                                                                                                                                                                                                         | Files                                                                                                                                                                                                                                                                                                                                                     |
|-----------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Standardize the project, CI workflows, container image, and deployment tooling on Godot 4.7.1 with verified binaries and matching export templates. | <ul><li>Updated engine versions and SHA-256 validation inputs across reusable test, pull-request, release, browser, and itch.io deployment workflows.</li><li>Updated the Docker image to install Godot 4.7.1, its export templates, and matching GDUnit4/GUT versions.</li><li>Added runtime engine-version parity checks and bundled Godot licensing and copyright notices.</li></ul>         | `.github/workflows/browser_test.yml`<br/>`.github/workflows/deploy_to_itch.yml`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`<br/>`.github/workflows/lint_test_deploy.yml`<br/>`.github/workflows/lint_test_on_pull.yml`<br/>`Dockerfile`<br/>`bin/godot-COPYRIGHT.txt`<br/>`bin/godot-LICENSE.txt`<br/>`project.godot` |
| Replace the GDUnit4 test workflow with coverage-aware, resilient test execution and optional Codecov reporting.                                     | <ul><li>Install GDUnit4 6.2.0, the GDUnit4 coverage extension, gdcov, xvfb, and lcov dynamically for Godot 4.7 compatibility.</li><li>Run GDUnit4 suites in two-file micro-batches with isolated test staging, then restore the suite and merge LCOV tracefiles.</li><li>Archive coverage and test reports and upload them to Codecov only when an authentication token is available.</li></ul> | `.github/workflows/gdunit4_tests.yml`                                                                                                                                                                                                                                                                                                                     |
| Refresh coverage configuration and simplify coverage ownership around GDScript production code.                                                     | <ul><li>Configure an auto-targeted GDUnit4 coverage flag for scripts while excluding tests and addons.</li><li>Remove browser JavaScript coverage mappings and browser/GUT-specific Codecov test-report uploads.</li></ul>                                                                                                                                                                      | `.codecov.yml`<br/>`.github/workflows/browser_test.yml`<br/>`.github/workflows/gut_tests.yml`                                                                                                                                                                                                                                                             |
| Update dependency and security-scan workflow integrations for the upgraded toolchain.                                                               | <ul><li>Upgrade GUT from 9.5.0 to 9.7.1 and GDUnit4 from 6.1.3 to 6.2.0.</li><li>Pin CodeQL SARIF uploads in Snyk and Trivy workflows to the newer action revision.</li></ul>                                                                                                                                                                                                                   | `Dockerfile`<br/>`.github/workflows/gut_tests.yml`<br/>`.github/workflows/snyk.yml`<br/>`.github/workflows/trivy.yml`                                                                                                                                                                                                                                     |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                   | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/890 | Upgrade the project’s Godot engine from 4.6.3 to 4.7.1-stable across the Docker development environment, project metadata, CI workflows, and deployment configuration.      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/890 | Ensure CI downloads and validates the Godot 4.7.1 binaries, verifies engine version parity, and uses compatible refreshed GUT/GDUnit4 tooling.                              | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/890 | Enable native GDUnit4 gdcov coverage execution under Godot 4.7.1 and integrate merged LCOV coverage and test-report uploads with Codecov.                                   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/891 | Upgrade the project’s GUT dependency to v9.7.1, including the bundled/containerized tooling where GUT is installed.                                                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/891 | Update the GUT CI workflow to use Godot 4.7.1-stable and dynamically download and configure GUT v9.7.1 during test setup.                                                   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/891 | Verify that the GUT test suite remains compatible with Godot 4.7.1-stable and completes successfully in headless CI without new errors or failures.                         | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/892 | Upgrade gdUnit4 to version 6.2.0 across the project's CI and containerized development environments.                                                                        | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/892 | Install and enable gdUnit4-coverage version 0.1.4 as a GDExtension for coverage profiling, including headless CI execution with the gdcov runner.                           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/892 | Generate valid LCOV coverage output from CI test runs, merge and sanitize batch tracefiles, archive the result, and optionally upload coverage and test results to Codecov. | ✅        |             |

### Possibly linked issues

- **#TASK-1**: PR directly implements the issue’s Godot 4.7.1 migration, including Docker, CI workflows, checksums, parity checks, and project metadata.

---



---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
