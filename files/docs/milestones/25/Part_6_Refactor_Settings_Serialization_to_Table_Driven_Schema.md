<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Refactor Settings Serialization to Table-Driven Schema

---

## PR #1002 Summary

**Title:** Refactor settings serialization to table driven schema  
**Author:** @ikostan  
**Linked issue:** [#470 – [FEATURE] Refactor Settings Serialization to Table-Driven Schema](https://github.com/ikostan/SkyLockAssault/issues/470)  
**Milestone:** Milestone 25: Resource Migration & Audio Decoupling  
**Labels:** enhancement, refactoring  

### Purpose
Replace hand-written settings load/save logic with a centralized, table-driven schema in `Globals`. The schema validates types and ranges, preserves defaults for missing/invalid values, keeps legacy key compatibility, and protects unrelated configuration sections owned by other managers.

### Key Changes
- **Table-driven schema** (`scripts/core/globals.gd`)
  - `persisted_schema` (formerly `PERSISTED`) maps each persisted property to its on-disk key, accepted types, optional casts, and validation bounds
  - `_load_settings()` iterates the schema, skips missing/invalid/out-of-range values, and retains current defaults
  - `_save_settings()` iterates the schema while preserving encryption, legacy migration, other managers’ sections, and unknown entries
- **Regression tests**
  - New comprehensive GUT coverage in `test/gut/test_globals_settings_serialization.gd` (legacy aliases, type conversion, bounds, partial/failed loads, observer suppression, schema extension, encrypted round-trips, migration, preservation of unrelated sections)
- **CI simplification**
  - GDUnit4 workflow no longer installs trial coverage tooling or performs Codecov uploads
  - Removed LCOV aggregation / micro-batching; runs suites in a single pass
  - Cleaned up `CODECOV_TOKEN` secret references
  - Release Drafter action bumped (via Dependabot) and related config fixes
- **Documentation**
  - Milestone doc: `files/docs/milestones/25/Part_6_Refactor_Settings_Serialization_to_Table_Driven_Schema.md`

### Intent / Compatibility
- Invalid or missing persisted values no longer overwrite defaults
- Settings owned by other managers (audio, input, etc.) and unknown entries are preserved
- Backward-compatible with existing save keys and plaintext → encrypted migration behavior

### Testing / Coverage
- Extensive new GUT regression suite for the serialization contract
- Codecov integration intentionally removed from the GDUnit4 path as part of CI simplification

---



---

## Reviewer's Guide

Refactors global settings persistence around a validated table-driven schema that protects defaults and unrelated configuration data, adds extensive compatibility regression tests, and simplifies CI by dropping coverage collection and Codecov uploads.

### File-Level Changes

| Change                                                                                       | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Files                                                                                                                                                                                  |
|----------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Introduces a table-driven, validated schema for global settings persistence.                 | <ul><li>Centralizes disk aliases, accepted types, casts, bounds, and persistence order in `PERSISTED`.</li><li>Replaces hand-written load/save logic with schema iteration and schema/property consistency checks.</li><li>Rejects invalid, missing, or out-of-range values while retaining current defaults.</li><li>Preserves other managers’ sections and unknown settings by reloading the existing configuration before saves.</li><li>Maintains bulk-load observer suppression and plaintext migration behavior.</li></ul> | `scripts/core/globals.gd`                                                                                                                                                              |
| Adds regression coverage for the settings serialization contract and compatibility behavior. | <ul><li>Tests legacy aliases, type conversion, bounds, partial and failed loads, observer suppression, and unknown entries.</li><li>Tests schema extension, missing resource properties, encrypted round trips, migration, and preservation of unrelated sections.</li><li>Verifies invalid values do not trigger setters or overwrite defaults.</li></ul>                                                                                                                                                                       | `test/gut/test_globals_settings_serialization.gd`                                                                                                                                      |
| Simplifies CI test execution by removing trial coverage tooling and Codecov integration.     | <ul><li>Runs all GDUnit4 suites in one pass instead of domain micro-batches.</li><li>Removes coverage extension, LCOV merging, Codecov upload, coverage secrets, and related setup.</li><li>Retains Godot verification, test report artifact upload, and workspace test restoration.</li></ul>                                                                                                                                                                                                                                   | `.github/workflows/gdunit4_tests.yml`                                                                                                                                                  |
| Updates release automation dependencies and adds milestone documentation.                    | <ul><li>Pins both Release Drafter workflows to a newer commit.</li><li>Adds a milestone document for the settings serialization refactor.</li></ul>                                                                                                                                                                                                                                                                                                                                                                              | `.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml`<br/>`files/docs/milestones/25/Part_6_Refactor_Settings_Serialization_to_Table_Driven_Schema.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                            | Addressed | Explanation |
|------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/470 | Define a table-driven `Globals.gd` persistence schema mapping each persisted property to its unchanged on-disk key, accepted types, casts, and validation bounds.                                                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/470 | Refactor `_load_settings()` to iterate over the schema, preserve defaults for missing or invalid values, apply configured casts and bounds validation, and retain legacy plaintext loading and migration behavior.   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/470 | Refactor `_save_settings()` to iterate over the schema while preserving encryption, legacy migration behavior, other managers' sections, unknown configuration entries, and the existing shared `ConfigFile` layout. | ✅        |             |

### Possibly linked issues

- **#[FEATURE] Refactor Settings Serialization to Table-Driven Schema**: The PR directly implements the requested table-driven Globals serialization, validation, legacy compatibility, safe saves, and regression coverage.

---

## PR #1002 Summary: Bots / AI Contributions

**PR:** [Refactor settings serialization to table driven schema](https://github.com/ikostan/SkyLockAssault/pull/1002)  
**Title:** Refactor settings serialization to table driven schema  
**Author / primary contributor:** @ikostan  
**Linked issue:** #470  

### Human contribution (@ikostan)

- Authored the core table-driven settings serialization refactor in `scripts/core/globals.gd` (schema-driven load/save with type/range validation, defaults preservation, and compatibility with existing keys).
- Added milestone documentation, simplified GDUnit4 CI (removed coverage tooling / Codecov integration), cleaned up workflows, and performed follow-up fixes (YAML lint, release-drafter config, schema rename, etc.).
- Notable commits by @ikostan include:
  - Merge of the Dependabot bump (`7b64515`)
  - `Create Part_6_Refactor_Settings_Serialization_to_Table_Driven_Schema.md` (`7c364ff`)
  - `Add table-driven settings persistence` (`cc0bbe7`)
  - `Simplify GDUnit4 CI workflow` (`501a389`)
  - `Remove Codecov secret from lint workflow` (`e0b863d`)
  - Multiple cleanup / fix commits (`e6ddaca`, `b66acbe`, `c29f0cb`, `5450792`, `0d283b6`, `d6a903e`, etc.)
- Added the PR to Milestone 25, self-assigned, applied labels (enhancement, refactoring), and linked issue #470.

### Bots / AI contributions

- **@dependabot**  
  - Authored the dependency bump commit: `Bump release-drafter/release-drafter from 7.7.0 to 7.9.0` (`36a8a8a`).  
  - That change was merged into this PR via #1001.

- **@coderabbitai**  
  - Generated “Summary by CodeRabbit”.  
  - Performed code review, walkthrough, and finishing-touches / coding-agent support.  
  - Committed: `Add regression tests for Globals settings serialization and migration` (`0fb82cb`).

- **@sourcery-ai**  
  - Generated “Summary by Sourcery” (features, bug fixes, enhancements, CI, docs, tests).  
  - Produced Reviewer’s Guide with sequence diagrams and file-level change analysis.  
  - Posted multiple code reviews and suggestions (including CI/workflow notes).

- **@deepsource-io** (DeepSource / DeepSourceReview)  
  - Ran automated code review on the PR range.  
  - Posted PR Report Card (Security / Reliability / Complexity / Hygiene) and linked full analyzer results (Python & JavaScript).

- **@codecov**  
  - Directly impacted by this PR: GDUnit4 coverage collection, LCOV aggregation, and Codecov uploads were removed from CI; the `CODECOV_TOKEN` secret was also cleaned up from related workflows.  
  - No new coverage report comment from the bot was the primary focus; the contribution is the deliberate removal/simplification of Codecov integration.

- **@github-copilot-cli** (GitHub Copilot)  
  - No co-authored commits, reviews, or direct contributions observed on this specific PR.

---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
