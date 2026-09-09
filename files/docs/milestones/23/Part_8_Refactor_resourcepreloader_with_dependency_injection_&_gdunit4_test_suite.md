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

ResourcePreloader is refactored with overridable editor and loading seams, clearer severity-aware diagnostics, and safer PNG scanning; a broad GdUnit4 suite exercises runtime/editor and success/failure paths, with CI partitioning and milestone documentation updated accordingly.

### File-Level Changes

| Change                                                                                                         | Details                                                                                                                                                                                                                                                                                                 | Files                                                                                                                                                    |
|----------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| Introduces dependency-injection seams and centralized diagnostics while preserving editor-only PNG preloading. | <ul><li>Wraps editor detection and resource loading in overridable methods for test doubles.</li><li>Replaces direct prints with severity-aware Globals.log_message calls.</li><li>Hardens directory scanning, filters non-PNG files, clears prior resources, and reports scan/load outcomes.</li></ul> | `scripts/managers/resource_preloader.gd`                                                                                                                 |
| Adds comprehensive GdUnit4 coverage for ResourcePreloader lifecycle and texture-loading behavior.              | <ul><li>Covers default state, runtime guards, editor reload behavior, directory errors, filtering, successful loads, and injected failures.</li><li>Uses a FakePreloader plus temporary filesystem fixtures and cleanup.</li></ul>                                                                      | `test/gdunit4/test_resource_preloader.gd`<br/>`test/gdunit4/test_resource_preloader.gd.uid`                                                              |
| Integrates the new tests into CI and documents the refactor.                                                   | <ul><li>Assigns preloader tests to the manager/system domain and excludes them from settings and UI discovery to prevent duplicate runs.</li><li>Adds Milestone 23 implementation and review documentation.</li></ul>                                                                                   | `.github/workflows/gdunit4_tests.yml`<br/>`files/docs/milestones/23/Part_8_Refactor_resourcepreloader_with_dependency_injection_&_gdunit4_test_suite.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                      | Addressed | Explanation |
|------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/930 | Refactor ResourcePreloader to isolate editor-state detection and resource loading behind injectable test wrappers while preserving editor-only PNG preloading behavior.                        | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/930 | Add a comprehensive GdUnit4 test suite covering initialization, runtime and editor lifecycle guards, directory validation, non-PNG filtering, successful loading, and failed resource loading. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/930 | Integrate the ResourcePreloader tests into CI and document the refactoring and test coverage.                                                                                                  | ✅        |             |

### Possibly linked issues

- **#930**: The PR directly implements issue #930 through injectable wrappers, nine tests, diagnostics improvements, and CI integration.

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
