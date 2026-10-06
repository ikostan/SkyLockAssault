<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Refactor Settings Serialization to Table-Driven Schema

---

## PR #1002 Summary

**Title:** Refactor settings serialization to table driven schema  
**PR:** [#1002](https://github.com/ikostan/SkyLockAssault/pull/1002)  
**Author:** @ikostan  
**Linked issue:** [#470 – [FEATURE] Refactor Settings Serialization to Table-Driven Schema](https://github.com/ikostan/SkyLockAssault/issues/470)  
**Milestone:** Milestone 25: Resource Migration & Audio Decoupling  
**Labels:** enhancement, refactoring  

### Purpose

Replace hand-written settings load/save logic with a centralized, table-driven schema in `Globals`. Adding a persisted setting becomes a one-entry change. The schema validates types and (where defined) ranges, preserves current values for missing or invalid entries, keeps legacy on-disk keys, and protects configuration sections owned by other managers.

This implements the rescoped version of #470: the original "Migrate to ResourceSaver" proposal was dropped because of the security risk of loading `.tres` files from `user://` and the encryption constraints, so persistence stays on encrypted `ConfigFile` storage.

### Key Changes

- **Table-driven schema** (`scripts/core/globals.gd`)
  - `persisted_schema` maps each persisted property to its on-disk key, accepted types, optional cast, and optional bounds.
  - `_load_settings()` iterates the schema and skips missing keys, wrong types, and values outside schema-defined bounds, retaining current values in each case.
  - `_save_settings()` iterates the schema while preserving encryption, legacy plaintext migration, other managers' sections, and unknown entries.
  - Both loops guard against schema entries that do not match a `GameSettingsResource` property; on save this prevents `ConfigFile.set_value(..., null)` from erasing an existing key.
- **Regression tests**
  - New GUT suite `test/gut/test_globals_settings_serialization.gd` covering legacy aliases, type casting, bounds, partial and failed loads, observer suppression, schema extension, encrypted round-trips, plaintext migration, and preservation of unrelated sections.
- **CI changes** (bundled here because they were needed to get this PR green, rather than split into separate PRs)
  - **GDUnit4 coverage removed.** The gdUnit4-coverage trial build is capped at 20 files, and its maintainer considers micro-batching around that cap a circumvention of the trial restriction. The GDUnit4 workflow therefore no longer installs coverage tooling, micro-batches suites, merges LCOV tracefiles, or uploads to Codecov; it runs all suites in a single pass.
  - **Plugin kept locally, stripped in CI.** The coverage plugin stays enabled in the committed `project.godot` for local editor use. A CI step removes its plugin entry, session hook, and `[gdunit4_coverage]` section from the CI checkout only, and fails if any reference remains.
  - **`CODECOV_TOKEN` scope.** Removed from the GDUnit4 workflow and its call sites only. GUT and browser test coverage uploads are unchanged.
  - **Release Drafter.** Action bumped from 7.7.0 to 7.9.0 (Dependabot, #1001); config migrated from the deprecated `categories[*].labels` and `version-resolver.*.labels` fields to `when` conditions and `type: version-resolver` categories. Version bump behavior is unchanged.
  - **Docstring workflow.** yamllint fixes (quoting, `truthy`, `empty-values`) in `bi_weekly_gd_docstrings.yml`.
- **Documentation**
  - This milestone doc: `files/docs/milestones/25/Part_6_Refactor_Settings_Serialization_to_Table_Driven_Schema.md`

### Design Decisions

- **Schema naming.** Implemented as `static var persisted_schema` rather than `static var PERSISTED` as written in #470. gdlint's `class-variable-name` rule requires snake_case for class-scope variables. A `const` was considered and rejected: const dictionaries are read-only, and the test suite extends and replaces the schema to verify the one-entry-change contract. Production code treats the schema as read-only.
- **Reject vs. clamp.** Out-of-range `log_level` values are rejected (current value kept), because the pre-refactor code already rejected them. `difficulty` and `max_fuel` have no schema bounds and still pass through to the resource setters, which clamp them. This keeps the resource as the single source of truth for those ranges, and clamping preserves player intent if an older build allowed a wider range. Covered by `test_load_still_uses_resource_validation_for_unbounded_schema_fields`.
- **Property guard.** `prop in settings` is the supported Godot 4 way to test whether an object has a property (`String in Object`). A bot review flagged it as an unsupported membership check; that was a false positive.
- **Logging.** Rejected values now log a `WARNING`; the previous code skipped them silently.

### Compatibility

- On-disk key names are unchanged (e.g. `current_log_level` is still stored as `log_level`), so existing player saves keep loading.
- Missing or invalid persisted values continue to preserve current values; this behavior is unchanged, now enforced by the schema.
- Sections owned by other managers (audio, input) and unknown entries are preserved on save.
- Plaintext → encrypted migration behavior is unchanged.

### Testing

- New GUT regression suite for the serialization contract (see above).
- Existing suites named in #470 re-run with no regressions: `test_settings_observer.gd`, `test_settings_migration.gd`, `test_preserve_other_sections.gd`, `test_basic_save_load_without_other_settings.gd`.
- GDUnit4 suites run in a single pass without coverage collection.

---

## Reviewer's Guide

The PR centralizes global settings load/save behavior in a validated table-driven schema, preserving current values and unrelated configuration across legacy, encrypted, and migration paths, with comprehensive regression tests. It also removes gdUnit4 coverage tooling from CI (trial restriction), migrates the Release Drafter config off deprecated fields, and adds milestone documentation.

### File-Level Changes

| Change                                                                                  | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Files                                                                                                                                                                                                                                                                        |
|-----------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Replaces manual settings persistence with a validated, table-driven schema.             | <ul><li>Defines disk aliases, accepted types, casts, optional bounds, and persistence order centrally.</li><li>Loads only present, correctly typed values within schema-defined bounds; fields without bounds rely on resource setter clamping.</li><li>Suppresses observer side effects during bulk loading.</li><li>Saves schema-defined properties while preserving legacy migration behavior, other managers' sections, and unknown entries.</li><li>Guards against schema entries that do not correspond to resource properties.</li></ul> | `scripts/core/globals.gd`                                                                                                                                                                                                                                                    |
| Adds regression coverage for settings serialization compatibility and failure behavior. | <ul><li>Covers aliases, type casting, bounds, partial or failed loads, observer suppression, encrypted round trips, plaintext migration, schema extensions, and preservation of unrelated configuration.</li><li>Verifies invalid values do not trigger setters or erase existing data.</li></ul>                                                                                                                                                                                                                                               | `test/gut/test_globals_settings_serialization.gd`<br/>`test/gut/test_globals_settings_serialization.gd.uid`                                                                                                                                                                  |
| Removes gdUnit4 coverage collection and its Codecov integration from CI.                | <ul><li>Runs the complete GDUnit4 suite in one pass instead of coverage micro-batches.</li><li>Removes the trial coverage addon download, LCOV aggregation, Codecov upload steps, and the GDUnit4 `CODECOV_TOKEN` wiring; test reports and artifact uploads are retained.</li><li>Strips coverage plugin references from the CI checkout's `project.godot`; the committed file keeps the plugin for local use.</li></ul>                                                                                                                        | `.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/lint_test_deploy.yml`<br/>`.github/workflows/lint_test_on_pull.yml`                                                                                                                                             |
| Updates release automation configuration and documents the refactor.                    | <ul><li>Migrates Release Drafter category and version-resolution syntax off deprecated fields and updates the action pin.</li><li>Applies YAML quoting and lint fixes to the scheduled documentation workflow.</li><li>Adds milestone documentation describing schema behavior, design decisions, and compatibility guarantees.</li></ul>                                                                                                                                                                                                       | `.github/release-drafter.yml`<br/>`.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml`<br/>`.github/workflows/bi_weekly_gd_docstrings.yml`<br/>`files/docs/milestones/25/Part_6_Refactor_Settings_Serialization_to_Table_Driven_Schema.md` |

### Assessment Against Linked Issue #470

| Objective                                                                                                                                                                                                                     | Addressed | Notes                                                                   |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------------------------------------------------------------------|
| Define a centralized table-driven persistence schema mapping each persisted setting to its unchanged on-disk key, accepted types, casts, and validation bounds.                                                               | ✅        | Named `persisted_schema` instead of `PERSISTED` (see Design Decisions). |
| Refactor `_load_settings()` to iterate the schema, preserve current values for missing or invalid entries, apply casts and bounds, suppress observers during bulk loading, and retain legacy plaintext loading and migration. | ✅        |                                                                         |
| Refactor `_save_settings()` to iterate the schema while preserving encrypted `ConfigFile` storage, legacy migration, unrelated manager sections, unknown entries, and the existing file layout.                               | ✅        |                                                                         |
| Run the existing GUT suites to confirm no regressions.                                                                                                                                                                        | ✅        | See Testing.                                                            |

---

## Contributors: Human, Bots, and AI

### Human contribution (@ikostan)

- Led the table-driven settings serialization refactor in `scripts/core/globals.gd`, the CI changes, and the follow-up fixes (YAML lint, Release Drafter config, schema rename).
- Added milestone documentation.
- Notable commits:
  - `Add table-driven settings persistence` (`cc0bbe7`)
  - `Simplify GDUnit4 CI workflow` (`501a389`)
  - `Remove Codecov secret from lint workflow` (`e0b863d`)
  - `Create Part_6_Refactor_Settings_Serialization_to_Table_Driven_Schema.md` (`7c364ff`)
  - Merge of the Dependabot bump (`7b64515`)
  - Cleanup and fix commits (`e6ddaca`, `b66acbe`, `c29f0cb`, `5450792`, `0d283b6`, `d6a903e`, etc.)
- Added the PR to Milestone 25, self-assigned, applied labels, and linked #470.

### AI assistance

- **Claude (claude.ai):** drafted the schema and load/save loops in `globals.gd`, the simplified `gdunit4_tests.yml` and its CI strip step, the Release Drafter config migration, the yamllint fixes, and the `persisted_schema` rename. All changes were reviewed and adapted by @ikostan.

### Bots

- **@dependabot**
  - Authored `Bump release-drafter/release-drafter from 7.7.0 to 7.9.0` (`36a8a8a`), merged into this PR via #1001.
- **@coderabbitai**
  - Generated the CodeRabbit summary, code review, and walkthrough.
  - Committed `Add regression tests for Globals settings serialization and migration` (`0fb82cb`).
- **@sourcery-ai**
  - Generated the Sourcery summary and Reviewer's Guide.
  - Posted code review comments, including CI and workflow notes; one High-severity finding (`prop in settings`) was a false positive (see Design Decisions).
- **@deepsource-io**
  - Ran automated code review and posted the PR Report Card (Security / Reliability / Complexity / Hygiene) with links to the full Python and JavaScript analyzer results.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->