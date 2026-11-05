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

Make AudioManager edge-case tests deterministic: the corrupt-value case (TC-SL-22) now parses an in-memory `ConfigFile` with no filesystem side effects, and the suite restores all singleton state it mutates. Also harden CI workflows (APT option handling, PR path-filter base) and clear the remaining yamllint line-length warnings.

### Key Changes

- **Audio test isolation** (`test/gut/test_error_edge_cases.gd`)
  - Suite-level snapshot/restore of the AudioManager config path, every bus's volume/mute state, `Globals.settings.difficulty`, and the `Globals._is_loading_settings` autosave guard, restored to the values found at suite start (not defaults)
  - TC-SL-22: corrupt volume/mute values for every bus tested via an in-memory `ConfigFile` passed to `apply_volumes_from_config`
  - Invalid values are ignored; live bus state, config path, and disk remain unchanged
  - Centralized cleanup of generated test config files
  - Audio buses are created before defaults are applied in `before_each()`
- **CI hardening**
  - APT options passed as Bash arrays (not shell-split strings) in `browser_test.yml` and `gdunit4_tests.yml`, which also clears their yamllint line-length warnings
  - `base` removed from the paths-filter step in `lint_test_on_pull.yml`, so every run diffs the whole PR against `pull_request.base.sha`; previously a run cancelled by a newer docs-only push could let GDScript changes skip the test jobs
  - SHA-pin comment re-wrapped to clear the remaining line-length warning in `lint_test_on_pull.yml`
- **Chores**
  - Added the missing `test/gut/test_audio_config_parsing.gd.uid`
  - Relicensed `test/gut/test_error_edge_cases.gd` to PolyForm-Noncommercial-1.0.0

### Intent / Behavior

- Prevent cross-test leakage of singleton, audio-bus, config-path, or temp-file state
- Ensure corrupt audio config never overwrites current settings or writes to disk
- Make CI package installs more robust, and make PR change detection cover the whole PR on every run, so cancelled runs cannot hide changes

### Testing

- Expanded TC-SL-22 to cover invalid volume and mute values on every configured bus
- Local GUT run (Godot 4.7.1, GUT 9.7.1): 622/622 passing
- Teardown fixes verified with probe suites run before and after this one: the old teardown left defaults / a forced `false` guard, the new one restores the entry values
- yamllint: 0 warnings across `.github/workflows/`
- Behaviour change to note: once a PR touches GDScript, every later push to it runs the GDScript test jobs, including docs-only pushes

### Review Notes

- @sourcery-ai – summary + Reviewer’s Guide
- @coderabbitai – summary, review, pre-merge checks
- @deepsource-io – automated review + PR Report Card
- @dependabot, @codecov, @github-copilot-cli – no direct contributions observed on this PR

---

## Reviewer's Guide

The PR improves audio test isolation and determinism by validating corrupted ConfigFile data entirely in memory, checking on every bus that invalid settings preserve live state, and restoring singleton, audio, difficulty and autosave-guard state after the suite. (Exhaustive type coverage lives in `test_audio_config_parsing.gd`.) It also hardens CI package-install argument handling and ensures PR path filtering compares the full pull request to its base revision.

### File-Level Changes

| Change                                                                                                          | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Files                                                                                  |
|-----------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| Refactor audio error and edge-case tests to parse in-memory configuration and restore all mutated global state. | <ul><li>Pass ConfigFile objects directly to the parser to avoid disk writes and crypto-layer involvement.</li><li>Expand corrupted-value coverage across every configured audio bus and verify existing values remain unchanged.</li><li>Snapshot and restore config path, difficulty, audio bus state and the autosave guard around the suite, and remove generated test files.</li><li>Ensure test audio buses exist before applying initialized defaults.</li></ul> | `test/gut/test_error_edge_cases.gd`<br/>`test/gut/test_audio_config_parsing.gd.uid`    |
| Make APT option passing robust in CI installation steps.                                                        | <ul><li>Represent apt-get options as shell arrays to preserve argument boundaries across update and install commands.</li><li>Keeps every line within yamllint's 90-character limit.</li></ul>                                                                                                                                                                                                                                                                         | `.github/workflows/browser_test.yml`<br/>`.github/workflows/gdunit4_tests.yml`         |
| Make pull-request path filtering evaluate the complete PR against its base commit.                              | <ul><li>Remove the <code>base: github.event.before</code> input, so local diff mode (<code>token: ""</code>) compares against <code>pull_request.base.sha</code> on every run. The existing full-history checkout is kept; only its comment changed.</li><li>Re-wrap the SHA-pin comment to clear the line-length warning.</li><li>Prevent later docs-only pushes or cancelled runs from hiding earlier GDScript changes.</li></ul>                                    | `.github/workflows/lint_test_on_pull.yml`                                              |
| Update the affected test file's license identifier.                                                             | <ul><li>Replace the GPL-3.0-or-later SPDX identifier with PolyForm-Noncommercial-1.0.0.</li></ul>                                                                                                                                                                                                                                                                                                                                                                      | `test/gut/test_error_edge_cases.gd`                                                    |
| Document the CI hardening and audio test-isolation implementation.                                              | <ul><li>Record the purpose, behavior, testing scope, linked issues, and review context.</li></ul>                                                                                                                                                                                                                                                                                                                                                                      | `files/docs/milestones/25/Part_9_Harden_CI_workflows_&_isolate_audio_parsing_tests.md` |

### Assessment against linked issues

| Issue                                                   | Objective                                                                                                                                                                                                | Addressed | Explanation                                                                                                                                                                                       |
|---------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/704>  | Refactor the audio manager corrupt-volume tests in `test_error_edge_cases.gd` to construct an in-memory `ConfigFile` containing invalid volume data and pass it directly to `apply_volumes_from_config`. | ✅        |                                                                                                                                                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/704>  | Verify that corrupt volume and mute values are safely ignored, leaving existing audio state unchanged across all configured buses.                                                                       | ✅        |                                                                                                                                                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/704>  | Ensure the tests avoid writing configuration files or invoking the C++ encryption layer, preventing related crashes.                                                                                     | ✅        |                                                                                                                                                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1010> | Remove all yamllint line-length warnings from `.github/workflows/lint_test_on_pull.yml` while preserving valid YAML and workflow behavior.                                                               | ✅        | Warnings cleared. Behaviour intentionally changes for follow-up pushes, which now diff against the PR base (see next rows).                                                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1010> | Correct the `dorny/paths-filter` configuration so pull-request path detection consistently compares the complete PR against its base commit, including after subsequent pushes.                          | ✅        |                                                                                                                                                                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1010> | Verify whether the existing `base` expression is effective and remove it, along with its associated justification, if it is unnecessary or could produce incorrect comparisons.                          | ✅        | The issue's premise was wrong: with `token: ""`, paths-filter does honour `base` on `pull_request`. It was removed because diffing against `github.event.before` let cancelled runs hide changes. |

### Possibly linked issues

- **#704**: PR directly implements the issue by testing corrupt audio volumes through an in-memory ConfigFile without file writes.

Outside #1010's scope, the same PR also clears the line-length warnings in `gdunit4_tests.yml` (L48) and `browser_test.yml` (L161).

---

## PR #1017 Summary: Bots / AI Contributions

### Human contribution (@ikostan)

- Owned and committed the work: isolated AudioManager edge-case tests (in-memory `ConfigFile` parsing, suite-level state snapshot/restore, no disk writes on corrupt values), APT option handling in CI workflows (array-based args), and the PR paths-filter base fix. The changes were drafted with @claude (see below) and reviewed and applied by @ikostan.
- Notable commits by @ikostan include:
  - `Stabilize audio config edge-case tests` (`b3398b8`)
  - `Update test_error_edge_cases.gd` (`712882e`)
  - `Fix PR paths-filter base handling` (`3bc22e8`)
  - `Fix apt-get options in CI workflow` (`16d2473`)
  - `Fix browser test apt installs` (`160e205`)
  - Follow-ups addressing Sourcery review: `Restore bus state in error tests` (`50aebb7`), `Fix PR path filter baseline logic` (`a387472`), `Fix test cleanup for settings restore` (`2cf8c47`)
  - This summary: `Harden CI workflows and isolate audio tests` (`f70ef1a`)
- Added the PR to Milestone 25, self-assigned, applied labels (refactoring, GUT), and linked related issues.

### Bots / AI contributions

- **@claude** (Claude Code)  
  - Drafted the TC-SL-22 rewrite, the suite snapshot/restore, and the yamllint and APT fixes in the three workflows.  
  - Investigated the paths-filter `base` behaviour against the action's source and drafted the fixes for the three Sourcery review comments.  
  - Ran the GUT suite, the probe suites and yamllint locally. No commits on the PR are authored by Claude.

- **@coderabbitai**  
  - Generated “Summary by CodeRabbit”.  
  - Performed code review, walkthrough, pre-merge checks, and finishing-touches / autopilot support.  
  - Flagged the SPDX change on `test_error_edge_cases.gd`; the change is intentional (the project is PolyForm Noncommercial), so no change was made.

- **@sourcery-ai**  
  - Generated “Summary by Sourcery” (bug fixes, enhancements, CI, tests, chores).  
  - Produced Reviewer’s Guide with file-level change analysis and assessment against linked issues.  
  - Posted code reviews and suggestions: three valid findings (bus state restored to defaults, cancelled runs hiding changes in path filtering, autosave guard forced to `false`), all fixed in the follow-up commits.

- **@deepsource-io** (DeepSource / DeepSourceReview)  
  - Ran automated code review on the PR range.  
  - Posted PR Report Card (Security / Reliability / Complexity / Hygiene) and linked full analyzer results (Python & JavaScript).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
