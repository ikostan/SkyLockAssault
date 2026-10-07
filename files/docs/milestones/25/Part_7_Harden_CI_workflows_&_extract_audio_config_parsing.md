<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Harden CI workflows and extract audio config parsing

---

## PR Summary

**Title:** Harden CI workflows and extract audio config parsing  
**Branch:** `702-feature-extract-in-memory-parsing-helper-for-audiomanage`  
**Author:** @ikostan  
**Linked issues:**

- [#701 – [Epic] Phase 3: Decouple AudioManager Parsing](https://github.com/ikostan/SkyLockAssault/issues/701) (parent epic; this PR covers its first two sub-tasks)
- [#702 – [FEATURE] Extract in-memory parsing helper for AudioManager](https://github.com/ikostan/SkyLockAssault/issues/702)
- [#703 – [FEATURE] Refactor load_volumes to use new parsing helper](https://github.com/ikostan/SkyLockAssault/issues/703)
- [#1003 – [BUG] CI workflow cleanup after gdUnit4-coverage removal](https://github.com/ikostan/SkyLockAssault/issues/1003)
- [#1004 – [BUG] browser_test.yml: lint warnings, skipped reports on failure, flaky server startup, and pinning gaps](https://github.com/ikostan/SkyLockAssault/issues/1004)
- [#1005 – [BUG] bi_weekly_gd_docstrings.yml: lint warnings, unvalidated automation PRs, and scope-check gap](https://github.com/ikostan/SkyLockAssault/issues/1005)

**Milestone:** Milestone 25: Resource Migration & Audio Decoupling  
**Labels:** enhancement, refactoring, bug, CI/CD  

### Purpose

Two related pieces of work in one PR:

1. **Audio parsing (Phase 3 of the #589 decoupling).** Separate `AudioManager`'s config parsing from its file I/O, the same way #589 did for `Settings`. The parser now works on an in-memory `ConfigFile`, so its error handling can be tested without disk access or the encryption layer.
2. **CI follow-ups to #1002.** Make the GDUnit4, browser-test, and documentation-sync workflows lint-clean, least-privilege, and fully SHA-pinned; fix failure-path reporting and a flaky server startup; and close a scope-check gap in the docstring automation.

### Key Changes

- **Audio config parsing** (`scripts/managers/audio_manager.gd`, #702 / #703)
  - New `apply_volumes_from_config(config: ConfigFile)` applies volume and mute values from an in-memory `ConfigFile`. Volumes must be `float` or `int`, mute flags must be `bool`; missing or wrong-type keys keep the bus's current value.
  - `load_volumes()` is now an I/O coordinator: read and decrypt via `Globals.safe_load_config`, delegate parsing to the helper, re-save legacy plaintext files encrypted, and sync AudioServer via `apply_all_volumes()`.
  - `test/gut/test_error_edge_cases.gd` updated for invalid audio settings.
- **GDUnit4 workflow** (`gdunit4_tests.yml`, #1003)
  - Inline strip script extracted to `.github/scripts/strip_gdunit4_coverage.py`; 12 yamllint `line-length` warnings fixed without new `yamllint disable` comments.
  - `checkout` and `upload-artifact` pinned to commit SHAs.
- **Permissions** (#1003)
  - Unused `checks: write` removed from `gdunit4_tests.yml`, `gut_tests.yml`, both caller jobs in `lint_test_on_pull.yml`, and the workflow level of `lint_test_deploy.yml`. The reusable test jobs now request `contents: read` only.
- **Browser tests** (`browser_test.yml`, #1004)
  - yamllint warnings fixed; "Test Report" runs on failure (`always()`); the four coverage-conversion steps run on failed runs (`!cancelled()`), so the LCOV and Codecov steps have data.
  - Server start step only launches the server; the wait loop tracks readiness explicitly (fixes the off-by-one that failed a server answering on attempt 20).
  - All actions SHA-pinned with `# vX.Y.Z` comments; Node.js 20 (EOL) → 24 for coverage conversion; install step renamed to "Install Python Dependencies" and re-indented.
- **Documentation sync** (`bi_weekly_gd_docstrings.yml`, #1005)
  - Optional GitHub App token so automation PRs trigger the PR pipeline, with `GITHUB_TOKEN` fallback and a documented close/reopen workaround in the PR body.
  - Scope check stages everything (`git add -A`) and checks the index: rejects deletions, new files, and out-of-scope edits.
  - `timeout-minutes: 30`, a `concurrency` group, accurate PR body claims (`gdformat`, not Godot headless checks), and "Twice-Weekly" naming.
- **Tests**
  - `tests/ci/test_strip_gdunit4_coverage.py`: strip rules (plugin first/middle/last/only, session hook incl. dangling comma, section removal, idempotency, failure path, CLI exit codes).
  - `tests/ci/test_gdunit4_workflow.py`: strip step uses the script, no `checks` permission, actions SHA-pinned.
  - `tests/ci/test_browser_test_workflow.py`: two assertions updated for the new behavior; five regression guards added for #1004.
- **Documentation**
  - This milestone doc: `files/docs/milestones/25/Part_7_Harden_CI_workflows_&_extract_audio_config_parsing.md`

### Design Decisions

- **Helper leaves AudioServer alone.** `apply_volumes_from_config()` only updates AudioManager state; `load_volumes()` still calls `apply_all_volumes()`. Keeping engine calls out of the helper is what makes it testable in memory. It does emit `volume_changed` / `mute_toggled` through `set_bus_state()`, as loading always did, and its doc comment says so.
- **No return value.** `apply_config_to_input_map()` returns a bool because it feeds `_needs_save`; audio has no equivalent, so the helper returns `void`.
- **Warnings for bad values.** Wrong-type values now log a `WARNING` (previously skipped silently), matching the settings helper. This is the only behavior change in the audio refactor.
- **`checks: write` removed from GUT too.** #1003 asked to check whether `gut_tests.yml` still needed it; no workflow in the repo uses the Checks API, so it was removed everywhere. The called workflow and its callers must change together, because GitHub rejects a called workflow that requests more than its caller grants.
- **Coverage on failed runs.** #1004 left this open. The LCOV upload (`always()`) and Codecov (`!cancelled()`) steps were already set to run on failure, so the conversion steps now match them.
- **New files rejected by the docstring scope check.** The generator only edits existing scripts, and a new `.gd` file would also skip the contract validator, which only checks tracked files.
- **Integrity claim kept.** The PR body's "byte-for-byte" claim is enforced by `update_gdscript_docs.py` (SHA-256 of non-documentation bytes, fail-closed), not by the validator; the body now names the script.
- **Names kept.** The `automation/weekly-gdscript-docs` branch and `bi_weekly_gd_docstrings.yml` filename are unchanged: renaming the branch would orphan an open automation PR, and milestone docs reference the filename.

### Deferred / Follow-ups

- **#1008** – Pin all workflows to `ubuntu-24.04` and add a non-blocking Ubuntu 26.04 canary (moved out of #1003 item 7).
- **GitHub App setup** for #1005: repo variable `DOCS_BOT_CLIENT_ID` and secret `DOCS_BOT_PRIVATE_KEY`. Until then, automation PRs still use `GITHUB_TOKEN`.
- **Version comments to confirm:** `firebelley/godot-export` (`# v8.0.0`) and `codecov/codecov-action` (`# v7.1.1`) comments come from earlier milestone docs, not from the SHAs themselves.
- **Node 24 LCOV parity:** compare `lcov-report-*` artifacts with a pre-change run.

### Compatibility

- Audio loading behavior is unchanged: same type rules, same keep-current-value fallback, same signals, same legacy migration and AudioServer sync. Existing saves load as before.
- Both pipelines call the changed workflows with the same inputs as before.
- Pinned action SHAs match the tags the workflows already used, so the code that runs is the same.

### Testing

- All new and updated `tests/ci/` suites pass (18 strip/workflow tests, 12 browser-workflow tests). The strip-script tests were mutation-checked: removing the dangling-comma fix, the section removal, or the leftover check each causes failures.
- The strip step and the warnings-disable step were run against the real `project.godot`; output matches the previous inline version.
- The wait loop was exercised with the server answering on attempts 1 and 20 (pass) and never (fails with a clear message).
- The docstring scope check was exercised in a scratch repo: an in-scope edit passes; a new file, an out-of-scope edit, and a deletion each fail.
- A yamllint-equivalent line-length check reports 0 warnings for `gdunit4_tests.yml`, `browser_test.yml`, and `bi_weekly_gd_docstrings.yml`; final confirmation is the YAML Lint job on this PR.
- Existing GUT/GDUnit4 audio suites that call `load_volumes()` (including the #707–#709 persistence tests) run through the refactored loader.

---

## Reviewer's Guide

The PR extracts AudioManager's config parsing into a pure in-memory helper and turns `load_volumes()` into an I/O coordinator. On the CI side it fixes lint warnings, removes an unused permission, SHA-pins actions, hardens failure-path reporting and server startup in the browser tests, and closes a scope-check gap in the docstring automation, with regression tests for each.

The browser CI workflow separates system package installation from Python dependencies and adds bounded timeouts, apt retries, and pip upgrades/retry settings to reduce flaky dependency setup failures.

### File-Level Changes

| Change                                                                              | Details                                                                                                                                                                                                                                                                                                                                             | Files                                                                                                                                                                                                                                                                                                        |
|-------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Extract audio configuration parsing from file I/O into a testable in-memory helper. | <ul><li>Add typed volume and mute parsing with current-state fallback for missing or invalid values.</li><li>Refactor loading to coordinate decryption, parsing, legacy migration, and AudioServer synchronization.</li><li>Update edge-case coverage for invalid audio settings.</li></ul>                                                         | `scripts/managers/audio_manager.gd`<br/>`test/gut/test_error_edge_cases.gd`                                                                                                                                                                                                                                  |
| Harden GDUnit4 CI after removing the coverage addon.                                | <ul><li>Extract project configuration cleanup into a reusable CLI script with fail-closed leftover-reference detection.</li><li>Add unit and CLI coverage for plugin lists, hooks, sections, idempotency, and failure behavior.</li><li>Remove unnecessary Checks API permissions and pin workflow actions to commit SHAs.</li></ul>                | `.github/scripts/strip_gdunit4_coverage.py`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`<br/>`.github/workflows/lint_test_on_pull.yml`<br/>`.github/workflows/lint_test_deploy.yml`<br/>`tests/ci/test_strip_gdunit4_coverage.py`<br/>`tests/ci/test_gdunit4_workflow.py` |
| Improve browser workflow reliability and diagnostics.                               | <ul><li>Separate server startup from explicit readiness polling, including correct final-attempt handling.</li><li>Run test reports and coverage conversion on failed-but-not-cancelled runs.</li><li>Pin actions, move coverage conversion to Node.js 24, and add structural regression checks.</li></ul>                                          | `.github/workflows/browser_test.yml`<br/>`tests/ci/test_browser_test_workflow.py`                                                                                                                                                                                                                            |
| Close documentation-sync automation validation and reliability gaps.                | <ul><li>Serialize runs, cap execution time, and optionally use a GitHub App token to trigger downstream PR checks.</li><li>Stage changes before validation and reject deletions, additions, and edits outside the allowed production scope.</li><li>Update schedule naming and generated PR messaging, while fixing workflow lint issues.</li></ul> | `.github/workflows/bi_weekly_gd_docstrings.yml`                                                                                                                                                                                                                                                              |
| Document the combined audio refactor and CI hardening work.                         | <ul><li>Record implementation decisions, compatibility expectations, testing evidence, and deferred Ubuntu/GitHub App follow-ups.</li></ul>                                                                                                                                                                                                         | `files/docs/milestones/25/Part_7_Harden_CI_workflows_&_extract_audio_config_parsing.md`                                                                                                                                                                                                                      |
| Make browser-test system package setup explicit and more resilient.                 | <ul><li>Moved libxml2-utils installation into a dedicated step.</li><li>Configured noninteractive apt execution, retries, and a five-minute timeout.</li></ul>                                                                                                                                                                                      | `.github/workflows/browser_test.yml`                                                                                                                                                                                                                                                                         |
| Harden Python dependency installation against transient network and tooling issues. | <ul><li>Added an eight-minute step timeout and upgraded pip before installing requirements.</li><li>Disabled progress output and configured 60-second pip timeouts with three retries.</li></ul>                                                                                                                                                    | `.github/workflows/browser_test.yml`                                                                                                                                                                                                                                                                         |

### Assessment Against Linked Issues

| Issue | Objective                                                                                                                                                                                             | Addressed | Notes                                                                                         |
|-------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------------------|
| #702  | Create a pure-GDScript `apply_volumes_from_config(config: ConfigFile)` helper that parses volume and mute settings from an in-memory `ConfigFile`.                                                    | ✅        |                                                                                               |
| #702  | Move AudioManager's volume state application logic from file-loading code into the new helper while preserving handling of missing or invalid values.                                                 | ✅        |                                                                                               |
| #702  | Keep `load_volumes()` focused on file I/O and runtime synchronization, delegating configuration parsing to the in-memory helper.                                                                      | ✅        |                                                                                               |
| #703  | Refactor `AudioManager.load_volumes()` so it acts strictly as an I/O coordinator, reading the configuration through `Globals.safe_load_config` and delegating parsing to `apply_volumes_from_config`. | ✅        | Also keeps the migration re-save and AudioServer sync, as `load_input_mappings()` does.       |
| #703  | Move audio volume and mute parsing into a reusable in-memory `ConfigFile` helper while preserving valid-value handling, current-state fallback, legacy migration, and AudioServer synchronization.    | ✅        |                                                                                               |
| #1003 | Make the CI workflows lint-clean by resolving the specified line-length issues in `gdunit4_tests.yml` and `bi_weekly_gd_docstrings.yml` without inappropriate lint suppressions.                      | ✅        | `disable-line` used only for pinned `uses:` lines, as the issue specifies.                    |
| #1003 | Extract the gdUnit4-coverage cleanup logic into a dedicated script and add CI tests covering plugin removal, session-hook cleanup, section removal, idempotency, and failure handling.                | ✅        |                                                                                               |
| #1003 | Remove unused `checks: write` permissions, pin actions to full commit SHAs with version comments, and verify that the gdUnit4-coverage addon is not tracked or redistributed.                         | ✅        | `git ls-files addons/gdunit4_coverage` returned nothing; the addon is not tracked.            |
| #1003 | Decide on an Ubuntu runner strategy (item 7).                                                                                                                                                         | ➡️        | Moved to #1008.                                                                               |
| #1004 | Make `browser_test.yml` lint-clean and consistently pin all GitHub Actions to full commit SHAs with version comments.                                                                                 | ✅        |                                                                                               |
| #1004 | Ensure test summaries and coverage diagnostics are produced on failed test runs, while avoiding skipped coverage processing.                                                                          | ✅        | Coverage converts on failed runs (see Design Decisions).                                      |
| #1004 | Make browser-test web-server startup reliable and complete the requested cleanup, including updating Node.js, fixing indentation/naming, and explicitly deferring the runner-version change.          | ✅        | Runner version tracked in #1008.                                                              |
| #1005 | Make the documentation-sync workflow lint-clean, use accurate PR-body claims, and align its displayed name and schedule terminology.                                                                  | ✅        | Branch and filename kept (won't fix, see Design Decisions).                                   |
| #1005 | Add timeout and concurrency protections and use a GitHub App token when configured so generated PRs trigger the normal pull-request pipeline, while documenting the fallback workaround.              | ✅        | The App token takes effect once `DOCS_BOT_CLIENT_ID` / `DOCS_BOT_PRIVATE_KEY` are configured. |
| #1005 | Close the documentation scope-check gap by staging all generated changes and rejecting deletions, new files, or modifications outside the permitted GDScript subtrees.                                | ✅        |                                                                                               |

---

## PR #1007 Summary: Bots / AI Contributions

### Human contribution (@ikostan)

- Authored the core work: extracted in-memory audio configuration parsing (`apply_volumes_from_config`) from `AudioManager.load_volumes()`, hardened multiple CI workflows (GDUnit4, browser tests, docs sync), tightened permissions, pinned actions to commit SHAs, and added regression tests/docs.
- Notable commits by @ikostan include:
  - `Refactor audio config loading` (`dbefe2d`)
  - `Strip gdUnit4 coverage from CI config` (`0e8373f`)
  - `Fix docs workflow validation and lint` (`f07a083`)
  - `Tighten GitHub workflow permissions` / related permission cleanups (`8178a91`, `a737337`, `6be1899`)
  - `Pin actions and harden browser CI workflow` (`c5d77b3`)
  - `Prevent overlapping GDScript doc sync runs` (`d50063b`)
  - Documentation and follow-up robustness commits (`65ff25b`, `b852dc2`, `7d1a216`, `eed5e91`, `a84a930`, etc.)
- Added the PR to Milestone 25, self-assigned, applied labels (bug, enhancement, CI/CD, github actions, refactoring, YML), and linked related issues.
- Led the audio parsing refactor and the CI follow-up work for #1003, #1004, and #1005; applied, reviewed, and ran all changes.
- Ran the verification that needed repository access (coverage-addon tracking check, pipeline runs).
- Wrote and maintained the linked issues, including splitting the Ubuntu runner work into #1008 and recording status notes and won't-fix decisions.
- Added milestone documentation.

### AI assistance

- **Claude (claude.ai):** drafted `apply_volumes_from_config()` and the `load_volumes()` refactor; the strip script and its tests; the workflow changes for #1003, #1004, and #1005, including SHA lookups and the regression tests; the #1008 issue description; and this milestone doc. All changes were reviewed and adapted by @ikostan.

### Bots / AI contributions

- **@coderabbitai**  
  - Generated “Summary by CodeRabbit”.  
  - Performed code review, walkthrough, pre-merge checks, and finishing-touches / coding-agent support.  
  - Committed: `Add regression tests for CI workflows, coverage cleanup, and audio config parsing` (`dc85cf0`).

- **@sourcery-ai**  
  - Generated “Summary by Sourcery” (features, bug fixes, enhancements, CI, docs, tests).
  - Generated the Reviewer's Guide: the file-level changes table and the linked-issue assessment used above, and flagged #701 as a possibly linked issue.
  - Posted reviews / title guidance (note: review budget temporarily exhausted on the PR).
  - Its earlier assessment findings led to the #1003 and #1005 status notes and the PR-body wording change for the integrity claim.

- **@deepsource-io** (DeepSource / DeepSourceReview / deepsource-autofix)  
  - Ran automated code review and posted PR Report Card (Security / Reliability / Complexity / Hygiene) with analyzer links.  
  - Authored two style/format commits via autofix:  
    - `style: format code with Black and isort` (`28521ae`)  
    - `style: format code with Black and isort` (`4d1dc2b`)

- **@codecov**  
  - Indirectly impacted: the PR continues the removal/cleanup of gdUnit4-coverage tooling and related coverage paths (building on prior Codecov simplification). No new primary coverage report comment was the focus of this PR.

- **@dependabot**  
  - No direct commits, dependency bumps, or review comments observed on this specific PR.

- **@github-copilot-cli** (GitHub Copilot)  
  - No co-authored commits, reviews, or direct contributions observed on this specific PR.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
