# Extract in memory parsing helper for settings
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

**PR #841 Summary: Extract in-memory parsing helper for settings**

### Overview

This PR by **@ikostan** refactors the input settings system in SkyLockAssault (Godot-based). It extracts parsing logic into a reusable in-memory helper, improves test coverage/isolation, hardens legacy migration and error handling, and updates several GitHub Actions in CI workflows.

### Key Changes

- **New Features**:
  - Introduced `apply_config_to_input_map()` helper for applying `ConfigFile` input mappings directly to Godot's `InputMap` (pure in-memory, no side effects).
  - Added test-only helpers (`backfill_missing_defaults`, `set_needs_save_for_test`, `needs_save()`) for better test control.

- **Improvements & Bug Fixes**:
  - Better handling of corrupt/unsupported config values while preserving existing bindings.
  - Improved legacy plaintext migration and `_needs_save` flag logic.
  - Refactored `load_input_mappings()` to delegate parsing and clarify responsibilities.
  - Enhanced conflict resolution and normalization of input events.

- **Testing**:
  - Reorganized tests to separate disk I/O from in-memory parsing behavior.
  - Expanded coverage for edge cases (legacy formats, unbound actions, conflicts).

- **CI/CD**:
  - Updated GitHub Actions to newer versions (setup-python, setup-node, markdownlint, release-drafter, CodeQL SARIF upload, etc.).

### Impact

- Cleaner, more testable settings code.
- Reduced coupling between file I/O and parsing logic.
- Improved maintainability and robustness for input configuration.

---

## Reviewer's Guide

Refactors input settings loading to use a reusable in-memory parsing helper, improves test isolation and coverage around legacy/corrupt configs and migration flags, and refreshes several GitHub Actions versions in CI workflows.

### File-Level Changes

| Change                                                                                                                                                              | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Files                                                                                                                                                                                                                                                                                                                                                          |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Extract in-memory ConfigFile→InputMap parsing into a reusable helper and make load_input_mappings an I/O coordinator around it.                                     | <ul><li>Added apply_config_to_input_map(config, actions) to deserialize ConfigFile input mappings into InputMap with conflict detection and a boolean return indicating whether conflicts were resolved.</li><li>Extracted normalization of raw config values into _normalize_input_value, supporting arrays, strings, and ints while logging and skipping unsupported types without clearing existing bindings.</li><li>Refactored load_input_mappings to use Globals.safe_load_config, restore legacy migration metadata, delegate all parsing to apply_config_to_input_map, and then combine its result with _add_missing_defaults to update the internal _needs_save flag.</li><li>Added test-only helpers backfill_missing_defaults, set_needs_save_for_test, and needs_save() to encapsulate default backfilling and internal migration flags for tests.</li></ul>                                                                                                                                                                                          | `scripts/core/settings.gd`                                                                                                                                                                                                                                                                                                                                     |
| Reorganize and extend settings tests to use in-memory parsing for most behaviors while keeping true disk I/O tests focused on persistence and last-device handling. | <ul><li>Updated GUT edge-case tests to construct ConfigFile instances in memory and call Settings.apply_config_to_input_map plus backfill_missing_defaults instead of saving/loading encrypted files for legacy, corrupt, unknown-key, conflict, and migration scenarios.</li><li>Introduced new tests that verify unsupported config value types preserve existing InputMap bindings, that apply_config_to_input_map’s boolean return reflects whether conflicts were resolved, and that the new needs_save test helpers work correctly.</li><li>Split GdUnit tests conceptually into disk I/O persistence tests and in-memory parsing tests, moving old-format, malformed, and type-safety coverage to use apply_config_to_input_map while simplifying path constants and teardown cleanup for removed disk fixtures.</li><li>Replaced direct _needs_save manipulation and assertions in tests with the new set_needs_save_for_test/needs_save helpers and adjusted expectations around when migration saves are triggered for legacy vs new formats.</li></ul> | `test/gut/test_settings_ec.gd`<br/>`test/gdunit4/test_settings.gd`                                                                                                                                                                                                                                                                                             |
| Refresh CI workflows to newer pinned versions of common GitHub Actions used for tooling, linting, and security reporting.                                           | <ul><li>Bumped actions/setup-python to v7 across browser tests, gdlint, CI script tests, and yamllint workflows, and actions/setup-node to v7 in browser coverage conversion.</li><li>Updated DavidAnson/markdownlint-cli2-action to a newer pinned SHA in the README lint workflow.</li><li>Updated release-drafter actions to a newer pinned SHA in both release_drafter and release_drafter_pr workflows.</li><li>Updated github/codeql-action/upload-sarif to a newer v3 SHA in Snyk and Trivy workflows for SARIF uploads.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | `.github/workflows/browser_test.yml`<br/>`.github/workflows/snyk.yml`<br/>`.github/workflows/gdlint.yml`<br/>`.github/workflows/lint_readme.yml`<br/>`.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml`<br/>`.github/workflows/test_ci_scripts.yml`<br/>`.github/workflows/trivy.yml`<br/>`.github/workflows/yamllint.yml` |
| Document the milestone and PR behavior in a new markdown file under docs.                                                                                           | <ul><li>Added a milestone document summarizing the PR’s goals, key changes, file-level impacts, and mapping to related issues, including explicit credit for bot/AI vs human contributions.</li><li>Described how the new apply_config_to_input_map helper, test refactors, and CI updates align with the broader in-memory parsing and testing strategy.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | `files/docs/milestones/22/Part_1_Extract_in_memory_parsing_helper_for_settings.md`                                                                                                                                                                                                                                                                             |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                       | Addressed | Explanation |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/696 | Implement a pure in-memory helper `apply_config_to_input_map` in `settings.gd` and refactor `load_input_mappings` so that disk I/O and metadata handling are separated from parsing, delegating InputMap population to the helper.                                                              | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/696 | Refactor GUT tests in `test_settings_ec.gd` to exercise settings parsing via in-memory `ConfigFile` injection using the new helper, removing disk-based corruption/legacy parsing paths except where real filesystem behavior (e.g., save failure, last_input_device) is explicitly under test. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/696 | Refactor GdUnit4 tests in `test_settings.gd` to use the in-memory parsing helper and `ConfigFile` injection for parsing/error-handling scenarios, separating disk I/O persistence tests from pure parsing tests and avoiding C++ native errors from corrupt disk fixtures.                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/697 | Create a pure-GDScript helper function `apply_config_to_input_map(config: ConfigFile, actions: Array[String])` in `settings.gd` and move the deserialization/InputMap mapping logic from `load_input_mappings` into this helper to decouple parsing from disk I/O.                              | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/697 | Add documentation/comments indicating that the new helper is intended for in-memory processing and testing (separate from disk I/O).                                                                                                                                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/698 | Introduce a dedicated parsing helper (e.g., `apply_config_to_input_map`) that encapsulates the input mapping parsing logic previously implemented inside `Settings.load_input_mappings`.                                                                                                        | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/698 | Refactor `Settings.load_input_mappings` so it acts strictly as an I/O coordinator: reading the config via `Globals.safe_load_config`, restoring metadata, delegating parsing to the new helper, and then handling default backfilling / save flags instead of inlining parsing logic.           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/698 | Update related tests and helpers to use the new parsing helper (`apply_config_to_input_map`) where appropriate, aligning them with the refactored `load_input_mappings` behavior.                                                                                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/699 | Refactor GUT edge-case tests in test_settings_ec.gd (specifically test_ec_04, test_ec_05, test_ec_07, and test_ec_10) to construct in-memory ConfigFile instances and pass them directly to Settings.apply_config_to_input_map() instead of using disk save/load.                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/699 | Ensure that disk saving/loading is reserved only for true filesystem tests (such as test_ec_06_save_fails_gracefully and test_ec_09_last_input_device_validation), removing unnecessary disk I/O from the other GUT edge-case tests in test_settings_ec.gd.                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/700 | Introduce or expose an in-memory helper in settings.gd (e.g., apply_config_to_input_map) that applies a ConfigFile’s input mappings directly to InputMap without disk I/O, suitable for use in tests.                                                                                           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/700 | Refactor GdUnit4 input settings tests in test/gdunit4/test_settings.gd to use in-memory ConfigFile injection with the new helper (especially error-handling/parsing tests like test_load_error_handling), avoiding saving corrupt or malformed files to disk.                                   | ✅        |             |

### Possibly linked issues

- **#N/A**: PR adds apply_config_to_input_map, refactors load_input_mappings, and converts settings error-path tests to pure in-memory.
- **#UNKNOWN**: The PR implements apply_config_to_input_map in settings.gd, refactors load_input_mappings, and updates tests per the issue.

---

**Bots/AI Contributors to PR #841**

This PR includes significant automation and AI-assisted contributions alongside human work.

### Bot/AI Contributions

- **@dependabot[bot]**: Multiple dependency update commits for GitHub Actions (e.g., `actions/setup-node`, `actions/setup-python`, `release-drafter/release-drafter`, `github/codeql-action/upload-sarif`, `DavidAnson/markdownlint-cli2-action`). These refreshed CI workflows to newer pinned versions.
- **@sourcery-ai**: Provided a detailed PR summary highlighting new features (e.g., `apply_config_to_input_map` helper), bug fixes, enhancements, test improvements, and CI updates.
- **@coderabbitai**: Offered a summary focusing on chores (CI/automation updates), refactoring of input-mapping handling, and expanded tests for parsing/backfilling.
- **@Copilot**: Collaborated on at least one commit involving refactoring input config normalization logic.

(DeepSourceReview / @deepsource-io was not visibly active in the commits, summaries, or reviews for this specific PR based on available details, though it is integrated in the repository.)

### @ikostan Contributions

@ikostan drove the core changes as the primary author:
- Refactored input settings loading by extracting a reusable in-memory parsing helper (`apply_config_to_input_map` and supporting methods like `_normalize_input_value`).
- Improved test isolation (disk I/O vs. pure in-memory parsing), added test-only helpers, hardened legacy migration/corner-case handling, and updated documentation/sequence diagrams.
- Performed merges of Dependabot PRs and various follow-up refinements to settings.gd, tests, and workflows.

This structure ensures bots/AI are properly credited in GitHub's contributors list while separating human effort.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
