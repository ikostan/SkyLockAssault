# Harden global button hook tests and bump security workflow pins
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## Summary

Strengthen tests around global UI audio button hook mechanics and update security-related GitHub Actions pins.

This PR effectively combines human-driven feature work (test hardening for global UI audio hooks) with strong bot/AI support for maintenance and quality assurance. The result is improved test coverage for edge cases in Godot UI hooking mechanics alongside updated, more secure CI pipelines.

Enhancements:

- Broaden global audio hook connection helper to safely handle non-button nodes and optional missing-signal assertions.
- Add coverage to ensure non-button controls, dialog ancestry, and button connection flags comply with global hook policies.

CI:

- Update pinned SHAs for CodeQL SARIF upload, `markdownlint`, and Trivy-related GitHub Actions for security and consistency.

Tests:

- Add new tests to verify non-button nodes are bypassed, dialog ancestry prevents global attachments, and button connections strictly use deferred flags.
- Added broader regression coverage for button and dialog interaction behavior, helping prevent unexpected global event handling issues.

Chores:

- Updated several automated workflow integrations to newer pinned versions, improving the reliability of Markdown, security, and vulnerability scan reporting.

---

## Reviewer's Guide

Extends and hardens global UI hook tests for button audio routing while updating pinned CI workflow dependencies.

### File-Level Changes

| Change                                                                                                                                             | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Files                                                                                                                                                                                                         |
|----------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Refined and generalized helpers for counting global audio button connections to support both button and non-button nodes with safety checks.       | <ul><li>Replaced _get_global_connection_count with _get_button_connection_count that accepts any Node and asserts presence of the pressed signal using fail_test.</li><li>Introduced _get_non_button_connection_count to safely return zero connections for nodes that typically lack a pressed signal.</li><li>Explicitly typed pressed.get_connections results as Array and centralized CONNECT_DEFERRED validation through the require_deferred parameter.</li></ul>                    | `test/gut/test_globals_button_hooks.gd`                                                                                                                                                                       |
| Expanded and tightened global button hook regression tests to enforce filtering rules, dialog ancestry constraints, and deferred connection usage. | <ul><li>Added a test ensuring standard non-button Control nodes are bypassed by strict Button class evaluation using the non-button helper.</li><li>Added a dialog ancestry traversal test that confirms buttons added inside AcceptDialog and ConfirmationDialog do not receive global audio hooks.</li><li>Added a dedicated test asserting that button connections strictly use the CONNECT_DEFERRED flag and updated existing tests to use the new helpers and expectations.</li></ul> | `test/gut/test_globals_button_hooks.gd`                                                                                                                                                                       |
| Updated security-related GitHub Actions workflow pins and added milestone documentation for the changes.                                           | <ul><li>Bumped github/codeql-action/upload-sarif SHA in snyk and trivy workflows to a newer pinned commit.</li><li>Updated DavidAnson/markdownlint-cli2-action to a newer pinned SHA in the README lint workflow.</li><li>Added a milestone document describing the test hardening, CI pin updates, and contributions from bots and humans.</li></ul>                                                                                                                                      | `.github/workflows/snyk.yml`<br/>`.github/workflows/lint_readme.yml`<br/>`.github/workflows/trivy.yml`<br/>`files/docs/milestones/21/Part_6_Harden_global_button_hook_tests_&_bump_security_workflow_pins.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                            | Addressed | Explanation |
|------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/798 | Expand GUT tests in test/gut/test_globals_button_hooks.gd to cover all button filtering rules: non-Button nodes are bypassed, flat Buttons are ignored, Buttons with 'no_global_sound' metadata are skipped, and buttons inside AcceptDialog/ConfirmationDialog are filtered via ancestry traversal. | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/798 | Add a test asserting that global button connections strictly use the CONNECT_DEFERRED flag for thread-safe scene tree interaction.                                                                                                                                                                   | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/798 | Generalize the helper used to count global button audio connections so it can safely handle non-Button nodes and support the new exclusion tests.                                                                                                                                                    | ✅         |             |

### Possibly linked issues

- **#763**: PR implements the requested new GUT tests and helper changes for global UI button hooking mechanics, plus CI updates.

---

**Bots/AI Contributions to PR #809**

### Bot & AI Tool Contributions
This PR benefited from several automated bots and AI-powered code review tools that handled dependency updates, generated summaries, provided iterative feedback, and conducted static analysis:

- **@dependabot[bot]**: Submitted automated dependency update PRs (#807 and #808) that were merged into this branch. Updated pinned SHAs for GitHub Actions workflows:
  - `DavidAnson/markdownlint-cli2-action` (from 23.2.0 to 24.0.0).
  - `github/codeql-action/upload-sarif` (to a newer commit SHA).
  These changes improved security, consistency, and reliability of CI workflows (Markdown linting, Snyk, Trivy, CodeQL).

- **@sourcery-ai**: Provided comprehensive PR summaries, a reviewer's guide, flow diagrams, and multiple rounds of high-quality code review comments. Feedback drove key improvements to the test helper (generalization, safety flags, splitting into `_get_button_connection_count` and `_get_non_button_connection_count`), test assertions, and use of GUT's `fail_test()`. Also generated the initial PR summary highlighting test hardening and CI updates.

- **@coderabbitai**: Delivered a walkthrough summary, change categorization (Chores + Tests), effort estimation, related issue/PR linking, and suggestions. Contributed to overall PR polish and regression coverage emphasis.

- **DeepSourceReview** (via **@deepsource-io** / DeepSource bot): Performed automated code review on the changes (Python/JS analysis), providing a PR Report Card (Security, Reliability, Complexity, Hygiene) and inline comments. Reviewed commits in the range e4d177d...0321d9f.

These tools collectively enhanced test robustness, CI security, and code quality through automated updates, reviews, and iterative refinements.

### Human Contributions
- **@ikostan**: Primary author and contributor. Implemented core changes including:
  - Generalizing and refactoring the `_get_global_connection_count` helper (with safety improvements like `fail_on_missing_signal`).
  - Adding comprehensive GUT regression tests for non-Button nodes, dialog ancestry filtering, and `CONNECT_DEFERRED` enforcement.
  - Merging Dependabot PRs and addressing AI review feedback through follow-up commits (e.g., helper splitting and test simplifications).
  - Overall PR ownership, labeling, milestone/project tracking, and linking to issue #798.

- **@espanakosta-jpg**: No direct commits, reviews, or comments visible in this PR. (If additional context exists outside the main PR page, it can be incorporated.)

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
