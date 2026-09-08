<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Refactor `resource_preloader.gd` with dependency injection and add gdunit4 test suite

---

## PR #931 Summary: Refactor ResourcePreloader with dependency injection and add GdUnit4 test suite

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `refactor-resourcepreloader-with-dependency-injection-and-add-gdunit4-test-suite` → `main`  
**Linked Issue:** #930 ([TEST] Refactor ResourcePreloader with Dependency Injection and Add GdUnit4 Test Suite)  
**Milestone:** Milestone 23 – Settings Architecture & FPS Counter Implementation  
**Labels:** testing, refactoring, QA, gdunit4

### Purpose
Make `ResourcePreloader` unit-testable by isolating editor-state and resource-loading behavior behind injectable seams, improve severity-aware diagnostics, and add a full GdUnit4 suite integrated into the CI manager test domain—without changing the intended editor-only PNG preload behavior.

### Core Improvements

#### 1. Testable seams (`scripts/managers/resource_preloader.gd`)

- `_is_in_editor()` — wraps `Engine.is_editor_hint()` for subclass override
- `_load_resource(path)` — wraps `load()` so tests can inject successes/failures
- Enables a `FakePreloader` subclass for controlled editor/runtime simulation

#### 2. Diagnostics & scanning behavior

- Replace ad-hoc prints with **`Globals.log_message`** (DEBUG / WARNING / ERROR)
- Report directory validity, file counts, discovered file lists, successful loads, and failed texture loads
- Preserve **PNG-only** discovery; skip unsupported files
- Clear existing preloaded resources before reload; assign unique IDs when adding bush/decor textures
- Hardened directory scanning (including fixes for file listing / traversal)

#### 3. GdUnit4 coverage (`test/gdunit4/test_resource_preloader.gd`)

- Initialization and default state
- Runtime vs editor lifecycle (`_ready`, force-reload guards)
- Invalid directory handling
- Non-PNG filtering
- Successful texture loading
- Injected load-failure paths
- Temporary-directory fixtures and cleanup via FakePreloader

#### 4. CI integration (`.github/workflows/gdunit4_tests.yml`)

- Include preloader tests in the **manager/system** domain batches
- Exclude from settings/UI domain discovery to avoid duplicate runs

#### 5. Documentation

- Milestone doc for the ResourcePreloader refactor under Milestone 23

### Benefits

- Editor preload logic is safely exercisable in headless unit tests
- Clearer, leveled logs for scan/load failures in development
- Strong regression net for a previously hard-to-test manager
- Coverage lift on `resource_preloader.gd` (reported **~96%** on this PR; project coverage **~60.5%**, **+1.7%** vs base)

### Status Notes

Fully addresses #930: DI wrappers, comprehensive GdUnit4 suite, improved diagnostics, and CI domain integration under Milestone 23.

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

## PR #931 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (including feedback on texture directory scanning / file listing). Multiple review passes as the preloader and tests evolved.

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the ResourcePreloader DI refactor and GdUnit4 suite (LGTM-style feedback; minimal merge risk).

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **60.45%**, **+1.69%** vs base; all modified coverable lines covered; `resource_preloader.gd` **96.07%** / **+91.99%**; all tests successful).

> **Note:** **@dependabot** did not author commits or leave reviews on this PR (no dependency-bump activity observed).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Refactored `ResourcePreloader` with testable seams (`_is_in_editor`, `_load_resource`) for dependency injection; routed diagnostics through severity-aware `Globals.log_message`; preserved PNG-only editor texture scanning with clearer scan/load/failure reporting; added a comprehensive GdUnit4 suite (FakePreloader, lifecycle, directory validation, filtering, success/failure paths); integrated tests into the CI manager domain without duplicates; fixed texture directory scanning; and documented the work under Milestone 23.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
