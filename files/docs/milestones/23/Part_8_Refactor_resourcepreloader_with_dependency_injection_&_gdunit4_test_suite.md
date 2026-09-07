<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Refactor `resource_preloader.gd` with dependency injection and add gdunit4 test suite

---



---

## Reviewer's Guide

Refactors ResourcePreloader behind testable wrappers, centralizes its diagnostics with severity-aware logging, adds broad GdUnit4 coverage for runtime/editor and resource-loading behavior, and includes the suite in the CI manager test domain.

### File-Level Changes

| Change                                                                                                                                     | Details                                                                                                                                                                                                                                                                                                                     | Files                                                                                       |
|--------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Introduces overridable seams for editor-state detection and texture loading, and routes preloader diagnostics through centralized logging. | <ul><li>Added wrappers for editor checks and resource loads to enable controlled subclass-based tests.</li><li>Replaced direct console output with debug, warning, and error project log messages.</li><li>Preserved PNG-only discovery while reporting scan counts, file lists, and load failures.</li></ul>               | `scripts/managers/resource_preloader.gd`                                                    |
| Adds comprehensive GdUnit4 coverage for ResourcePreloader runtime, editor, scanning, loading, and failure behavior.                        | <ul><li>Tests default state and runtime guards for the reload setter and ready lifecycle.</li><li>Tests invalid directories, non-PNG filtering, valid asset loading, and failed texture loads.</li><li>Uses a fake subclass to simulate editor mode and injected load failures, with temporary-directory cleanup.</li></ul> | `test/gdunit4/test_resource_preloader.gd`<br/>`test/gdunit4/test_resource_preloader.gd.uid` |
| Integrates ResourcePreloader tests into the CI manager/system test domain.                                                                 | <ul><li>Updates filename-based test partitioning to include preloader tests in manager batches.</li><li>Excludes preloader tests from settings and UI domain discovery to avoid duplicate execution.</li></ul>                                                                                                              | `.github/workflows/gdunit4_tests.yml`                                                       |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                    | Addressed | Explanation |
|------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/930 | Refactor ResourcePreloader to support dependency injection and isolate editor-state checks and resource loading behind testable wrappers.                                                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/930 | Add a comprehensive GdUnit4 test suite covering initialization, runtime and editor lifecycle behavior, directory validation, PNG filtering, successful loading, and failed resource loading. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/930 | Integrate the new ResourcePreloader tests into CI and improve diagnostics for scanning, loading, and failure conditions.                                                                     | ✅        |             |

### Possibly linked issues

- **#[TEST]**: The PR directly implements the issue’s ResourcePreloader wrappers, fake dependency injection tests, logging, CI integration, and nine test cases.

---



---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
