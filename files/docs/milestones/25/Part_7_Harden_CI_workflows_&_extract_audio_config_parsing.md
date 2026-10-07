<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Harden CI workflows and extract audio config parsing

---

## PR Summary

**Title:** Harden CI workflows and extract audio config parsing  
**Branch:** `702-feature-extract-in-memory-parsing-helper-for-audiomanage`  
**Author:** @ikostan  
**Linked issues:**

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

### File-Level Changes

| Change                                                  | Details                                                                                                                                                                                                                                                 |
|---------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Extracts audio config parsing into an in-memory helper. | <ul><li>Adds `apply_volumes_from_config()` with type validation and keep-current fallback.</li><li>Reduces `load_volumes()` to read → parse → migrate → sync AudioServer.</li><li>Logs a warning for wrong-type values.</li></ul>                       |
| Extracts and tests the gdUnit4-coverage strip logic.    | <ul><li>Moves the inline Python to `.github/scripts/strip_gdunit4_coverage.py` with an importable `strip_coverage()` and CLI.</li><li>Adds unit and CLI tests for every strip rule and the failure path.</li></ul>                                      |
| Removes unused `checks: write` grants.                  | <ul><li>Reusable test jobs request `contents: read`.</li><li>Caller grants and the deploy pipeline's workflow-level grant removed; header comment updated.</li></ul>                                                                                    |
| SHA-pins remaining mutable action tags.                 | <ul><li>`gdunit4_tests.yml` and `browser_test.yml` pinned with `# vX.Y.Z` comments.</li><li>Version comments added to existing `godot-export` and `codecov-action` pins.</li></ul>                                                                      |
| Hardens browser-test failure paths and startup.         | <ul><li>Test Report and coverage conversion run on failed runs.</li><li>Explicit server readiness tracking; start step no longer probes.</li><li>Node.js 24 for coverage conversion.</li></ul>                                                          |
| Hardens the documentation-sync workflow.                | <ul><li>Optional GitHub App token with fallback and documented workaround.</li><li>Index-based scope check rejecting deletions, new files, and out-of-scope edits.</li><li>Timeout, concurrency group, accurate PR body, twice-weekly naming.</li></ul> |
| Fixes yamllint warnings across the three workflows.     | <ul><li>Comments wrapped, commands split, regex moved into a variable.</li><li>`disable-line` used only for pinned `uses:` lines over 90 characters.</li></ul>                                                                                          |

### Assessment Against Linked Issues

| Issue | Objective                                                                                                                 | Addressed | Notes                                                                                               |
|-------|---------------------------------------------------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------------------------|
| #702  | Create `apply_volumes_from_config(config: ConfigFile)` and move the volume state logic there.                             | ✅        |                                                                                                     |
| #703  | `load_volumes()` only reads the file and delegates parsing to the helper.                                                 | ✅        | Also keeps migration re-save and AudioServer sync, as `load_input_mappings()` does.                 |
| #1003 | yamllint, strip-script extraction and tests, `checks: write`, SHA pinning, coverage-addon tracking check, docstring lint. | ✅        | `git ls-files addons/gdunit4_coverage` returned nothing; the addon is not tracked.                  |
| #1003 | Ubuntu runner strategy (item 7).                                                                                          | ➡️        | Moved to #1008.                                                                                     |
| #1004 | Lint, failure-path reporting, server startup, SHA pinning, Node LTS, cleanup.                                             | ✅        | Coverage converts on failed runs (see Design Decisions). Ubuntu note tracked in #1008.              |
| #1005 | Lint, automation PR validation, accurate PR body, scope check, timeout, concurrency, naming.                              | ✅        | Branch and filename kept (won't fix, see Design Decisions). App token takes effect once configured. |

---

## Contributors: Human, Bots, and AI

### Human contribution (@ikostan)

- Led the audio parsing refactor and the CI follow-up work for #1003, #1004, and #1005; applied, reviewed, and ran all changes.
- Ran the verification that needed repository access (coverage-addon tracking check, pipeline runs).
- Wrote and maintained the linked issues, including splitting the Ubuntu runner work into #1008 and recording status notes and won't-fix decisions.
- Added milestone documentation.

### AI assistance

- **Claude (claude.ai):** drafted `apply_volumes_from_config()` and the `load_volumes()` refactor; the strip script and its tests; the workflow changes for #1003, #1004, and #1005, including SHA lookups and the regression tests; the #1008 issue description; and this milestone doc. All changes were reviewed and adapted by @ikostan.

### Bots

- **@sourcery-ai**
  - Generated the linked-issue assessment, whose findings led to the #1003 and #1005 status notes and the PR-body wording change for the integrity claim.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
