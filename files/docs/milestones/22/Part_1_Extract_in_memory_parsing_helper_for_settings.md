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

| Change | Details | Files |
| ------ | ------- | ----- |
| Introduce an in-memory input mapping parser and delegate load_input_mappings to it, with explicit default backfilling and migration metadata handling. | <ul><li>Added apply_config_to_input_map(config, actions) to parse ConfigFile input mappings into InputMap with conflict detection and resolution.</li><li>Extracted normalization of config values into _normalize_input_value, supporting arrays, strings, and ints while logging and skipping unsupported types.</li><li>Updated load_input_mappings to use Globals.safe_load_config, restore LEGACY_MIGRATION_KEY metadata, call apply_config_to_input_map, and then aggregate _needs_save based on conflicts and _add_missing_defaults.</li><li>Added test-only helpers backfill_missing_defaults, set_needs_save_for_test, and needs_save to encapsulate _needs_save and default backfilling for tests.</li></ul> | `scripts/core/settings.gd` |
| Reorganize and extend settings tests to distinguish disk persistence from pure in-memory parsing, ensuring safer handling of legacy, corrupt, and edge-case configs. | <ul><li>Updated Gut tests to use apply_config_to_input_map and backfill_missing_defaults instead of writing/reading encrypted files where possible, and to avoid touching real CONFIG_PATH except where explicitly required.</li><li>Added new tests for unsupported config value types preserving existing bindings, conflict resolution return semantics, and public helpers around _needs_save.</li><li>Refactored GdUnit tests into two sections (disk I/O persistence vs in-memory parsing), moving old-format and malformed-deserialization cases to direct apply_config_to_input_map usage.</li><li>Replaced direct _needs_save mutation/assertions with set_needs_save_for_test and needs_save helpers, and simplified test file constant lists for removed disk-based scenarios.</li></ul> | `test/gut/test_settings_ec.gd`<br/>`test/gdunit4/test_settings.gd` |
| Refresh CI workflow dependencies to newer, pinned versions for Python, Node, markdown linting, release drafting, and SARIF uploads. | <ul><li>Bumped actions/setup-python from v6 to v7 across multiple workflows (browser_test, gdlint, test_ci_scripts, yamllint).</li><li>Bumped actions/setup-node from v6 to v7 in browser_test coverage conversion job.</li><li>Updated DavidAnson/markdownlint-cli2-action to a newer pinned SHA in lint_readme.</li><li>Updated release-drafter action to a newer pinned SHA in release_drafter and release_drafter_pr workflows.</li><li>Updated github/codeql-action/upload-sarif to a newer v3 SHA in snyk and trivy workflows.</li></ul> | `.github/workflows/browser_test.yml`<br/>`.github/workflows/snyk.yml`<br/>`.github/workflows/gdlint.yml`<br/>`.github/workflows/lint_readme.yml`<br/>`.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml`<br/>`.github/workflows/test_ci_scripts.yml`<br/>`.github/workflows/trivy.yml`<br/>`.github/workflows/yamllint.yml` |

### Assessment against linked issues

| Issue | Objective | Addressed | Explanation |
| ------ | ------- | ----- | ----- |
| https://github.com/ikostan/SkyLockAssault/issues/696 | Introduce a pure-GDScript helper `apply_config_to_input_map` that accepts an in-memory `ConfigFile` and applies its input mappings to Godot's `InputMap` without performing any disk I/O. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/696 | Refactor `load_input_mappings` in `settings.gd` so that it is responsible only for disk I/O, migration/metadata handling, and default backfilling, delegating all parsing and InputMap population to the new helper. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/696 | Refactor settings tests (`test_settings_ec.gd` for GUT and `test_settings.gd` for GdUnit4) so that parsing/error-handling logic is exercised via in-memory `ConfigFile` injection using the new helper, minimizing or removing disk-based corruption scenarios that can trigger C++ native errors. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/697 | Create a pure-GDScript helper function `apply_config_to_input_map(config: ConfigFile, actions: Array[String])` in `settings.gd` and move deserialization/InputMap mapping logic from `load_input_mappings` into this helper. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/697 | Add documentation comments indicating that the new helper is intended for in-memory processing and testing (decoupled from disk I/O). | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/698 | Introduce a dedicated parsing helper (e.g., apply_config_to_input_map) that encapsulates the input mapping parsing logic previously implemented inside Settings.load_input_mappings. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/698 | Refactor Settings.load_input_mappings to act strictly as an I/O coordinator: reading the config via safe_load_config, restoring metadata, delegating parsing to the new helper, and handling default backfilling/save flags without inlined parsing logic. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/698 | Update tests and related helpers to use the new in-memory parsing helper and test-only wrappers, ensuring separation of concerns between disk I/O and parsing behavior. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/699 | Refactor GUT edge-case tests in test_settings_ec.gd (specifically test_ec_04, test_ec_05, test_ec_07, test_ec_10) to use in-memory ConfigFile instances passed directly to an in-memory parsing helper instead of performing disk I/O (save/load, encryption). | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/699 | Introduce and use a reusable in-memory ConfigFile parsing helper in Settings (e.g., apply_config_to_input_map) so tests can validate parsing logic without touching the filesystem or C++ encryption/decryption routines. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/699 | Keep true filesystem behavior tests (such as save-failure and last_input_device validation tests like test_ec_06_save_fails_gracefully and test_ec_09_last_input_device_validation) using disk saving/loading while isolating them from in-memory parsing tests. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/700 | Introduce an in-memory helper in Settings (e.g., apply_config_to_input_map) that applies a ConfigFile’s input mappings to InputMap without disk I/O. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/700 | Refactor GdUnit4 input settings tests in test_settings.gd to use the in-memory helper and ConfigFile injection instead of saving/loading files to disk for input mapping behavior. | ✅ |  |
| https://github.com/ikostan/SkyLockAssault/issues/700 | Update error-handling and edge-case tests (e.g., malformed/corrupt input strings) to run via in-memory parsing rather than disk-based fixtures, ensuring they validate safe behavior under the new parsing flow. | ✅ |  |

### Possibly linked issues

- **#[FEATURE] Extract in-memory parsing helper for Settings**: PR implements the requested apply_config_to_input_map in settings.gd, refactors load_input_mappings, and updates tests accordingly.
- **#696**: The PR delivers the in-memory parsing helper, refactors load_input_mappings, and updates both test suites per the epic.
- **#N/A**: PR delivers apply_config_to_input_map, decouples file I/O from parsing, and converts error-path tests to pure in-memory.

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
