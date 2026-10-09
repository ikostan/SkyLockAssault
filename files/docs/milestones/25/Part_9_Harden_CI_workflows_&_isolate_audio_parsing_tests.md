<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Harden CI workflows and isolate audio parsing tests

---

## PR #1017 Summary

**Title:** Harden CI workflows and isolate audio parsing tests  
**Author:** @ikostan  
**Linked issues:** [#704 – Refactor GUT audio manager tests to use in-memory ConfigFile](https://github.com/ikostan/SkyLockAssault/issues/704), [#1010 – yamllint line-length warnings in lint_test_on_pull.yml](https://github.com/ikostan/SkyLockAssault/issues/1010)  
**Milestone:** Milestone 25: Resource Migration & Audio Decoupling  
**Labels:** refactoring, GUT  

### Purpose

Make AudioManager edge-case tests deterministic by using in-memory configuration parsing (no filesystem side effects) and proper suite-level state isolation, while hardening CI workflows for reliable APT option handling and correct PR path-filter basing.

### Key Changes

- **Audio test isolation** (`test/gut/test_error_edge_cases.gd`)
  - Suite-level snapshot/restore of AudioManager singleton, difficulty, and audio-bus state
  - Corrupt volume/mute values tested via in-memory `ConfigFile` passed to `apply_volumes_from_config`
  - Invalid values are ignored; live bus state, config path, and disk remain unchanged
  - Centralized cleanup of generated files; added test UID
- **CI hardening**
  - APT options passed as Bash arrays (not shell-split strings) in `browser_test.yml` and `gdunit4_tests.yml`
  - PR paths-filter base simplified to `github.event.before` with documented fallback behavior (`lint_test_on_pull.yml`)
- **Chores**
  - Updated test resource UID and license metadata

### Intent / Behavior

- Prevent cross-test leakage of singleton, audio-bus, config-path, or temp-file state
- Ensure corrupt audio config never overwrites current settings or writes to disk
- Make CI package installs and PR change detection more robust across opened/synchronized events

### Testing

- Expanded coverage for invalid volume/mute values across all configured buses
- Improved cleanup and state restoration for isolated test runs

### Review Notes

- @sourcery-ai – summary + Reviewer’s Guide
- @coderabbitai – summary, review, pre-merge checks
- @deepsource-io – automated review + PR Report Card
- @dependabot, @codecov, @github-copilot-cli – no direct contributions observed on this PR

---

## Reviewer's Guide

The PR improves audio test isolation and determinism by validating corrupted ConfigFile data entirely in memory, exhaustively checking that invalid settings preserve live state, and restoring singleton/audio/difficulty state after the suite. It also hardens CI package-install argument handling and ensures PR path filtering compares the full pull request to its base revision.

### File-Level Changes

| Change                                                                                                          | Details                                                                                                                                                                                                                                                                                                                                                                                                                        | Files                                                                               |
|-----------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| Refactor audio error and edge-case tests to parse in-memory configuration and restore all mutated global state. | <ul><li>Pass ConfigFile objects directly to the parser to avoid disk writes and crypto-layer involvement.</li><li>Expand corrupted-value coverage across every configured audio bus and verify existing values remain unchanged.</li><li>Snapshot and restore config path, difficulty, audio bus state, and test files around the suite.</li><li>Ensure test audio buses exist before applying initialized defaults.</li></ul> | `test/gut/test_error_edge_cases.gd`<br/>`test/gut/test_audio_config_parsing.gd.uid` |
| Make APT option passing robust in CI installation steps.                                                        | <ul><li>Represent apt-get options as shell arrays to preserve argument boundaries across update and install commands.</li></ul>                                                                                                                                                                                                                                                                                                | `.github/workflows/browser_test.yml`<br/>`.github/workflows/gdunit4_tests.yml`      |
| Make pull-request path filtering evaluate the complete PR against its base commit.                              | <ul><li>Use a full-history checkout and local diff mode without github.event.before as the base.</li><li>Prevent later docs-only pushes or cancelled runs from hiding earlier GDScript changes.</li></ul>                                                                                                                                                                                                                      | `.github/workflows/lint_test_on_pull.yml`                                           |
| Update the affected test file's license identifier.                                                             | <ul><li>Replace the GPL-3.0-or-later SPDX identifier with PolyForm-Noncommercial-1.0.0.</li></ul>                                                                                                                                                                                                                                                                                                                              | `test/gut/test_error_edge_cases.gd`                                                 |

### Assessment against linked issues

| Issue                                                 | Objective                                                                                                                                                                                                | Addressed | Explanation |
|-------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/704  | Refactor the audio manager corrupt-volume tests in `test_error_edge_cases.gd` to construct an in-memory `ConfigFile` containing invalid volume data and pass it directly to `apply_volumes_from_config`. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/704  | Verify that corrupt volume and mute values are safely ignored, leaving existing audio state unchanged across all configured buses.                                                                       | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/704  | Ensure the tests avoid writing configuration files or invoking the C++ encryption layer, preventing related crashes.                                                                                     | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/1010 | Remove all yamllint line-length warnings from `.github/workflows/lint_test_on_pull.yml` while preserving valid YAML and workflow behavior.                                                               | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/1010 | Correct the `dorny/paths-filter` configuration so pull-request path detection consistently compares the complete PR against its base commit, including after subsequent pushes.                          | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/1010 | Verify whether the existing `base` expression is effective and remove it, along with its associated justification, if it is unnecessary or could produce incorrect comparisons.                          | ✅        |             |

### Possibly linked issues

- **#704**: PR directly implements the issue by testing corrupt audio volumes through an in-memory ConfigFile without file writes.
- **#704**: PR refactors audio error-edge tests to call apply_volumes_from_config with in-memory corrupted ConfigFile data, matching the issue.

---

## PR #1017 Summary: Bots / AI Contributions

### Human contribution (@ikostan)

- Authored the core work: isolated AudioManager edge-case tests (in-memory `ConfigFile` parsing, suite-level state snapshot/restore, no disk writes on corrupt values), fixed APT option handling in CI workflows (array-based args), and corrected PR paths-filter base logic.
- Notable commits by @ikostan include:
  - `Stabilize audio config edge-case tests` (`b3398b8`)
  - `Update test_error_edge_cases.gd` (`712882e`)
  - `Fix PR paths-filter base handling` (`3bc22e8`)
  - `Fix apt-get options in CI workflow` (`16d2473`)
  - `Fix browser test apt installs` (`160e205`)
  - Follow-ups: `Restore bus state in error tests` (`50aebb7`), `Fix PR path filter baseline logic` (`a387472`), `Fix test cleanup for settings restore` (`2cf8c47`)
- Added the PR to Milestone 25, self-assigned, applied labels (refactoring, GUT), and linked related issues.

### Bots / AI contributions

- **@coderabbitai**  
  - Generated “Summary by CodeRabbit”.  
  - Performed code review, walkthrough, pre-merge checks, and finishing-touches / autopilot support.

- **@sourcery-ai**  
  - Generated “Summary by Sourcery” (bug fixes, enhancements, CI, tests, chores).  
  - Produced Reviewer’s Guide with file-level change analysis and assessment against linked issues.  
  - Posted code reviews and suggestions (including state-restoration feedback).

- **@deepsource-io** (DeepSource / DeepSourceReview)  
  - Ran automated code review on the PR range.  
  - Posted PR Report Card (Security / Reliability / Complexity / Hygiene) and linked full analyzer results (Python & JavaScript).

- **@codecov**  
  - No direct coverage report or commits observed on this specific PR (coverage tooling had already been simplified/removed in earlier work).

- **@dependabot**  
  - No direct commits, dependency bumps, or review comments observed on this specific PR.

- **@github-copilot-cli** (GitHub Copilot)  
  - No co-authored commits, reviews, or direct contributions observed on this specific PR.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
