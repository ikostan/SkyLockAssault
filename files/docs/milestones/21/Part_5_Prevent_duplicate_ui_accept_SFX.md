# Prevent duplicate ui_accept SFX and expand input guard tests
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

Strengthen UI input audio guarding and documentation around CI maintenance workflows to prevent duplicate confirmation sounds and capture recent automation updates.

**Overall Impact**: The PR strengthens audio input handling to prevent duplicates, expands test coverage for UI controls (buttons, sliders, LineEdit, TextEdit, etc.), and documents bot/AI-driven CI maintenance. Automation significantly reduced manual effort while maintaining quality.

---

Bug Fixes:

- Ensure global ui_accept audio is bypassed when focused interactive controls handle their own confirmation sounds to avoid double-triggered audio.

Enhancements:

- Refactored UI input guard tests to use a shared helper and expanded coverage to additional controls including sliders, buttons, and text inputs.
- Added a functional test to verify that deferred button press hooks correctly route audio playback through AudioManager.

Documentation:

- Documented CI maintenance and workflow dependency updates in a milestone maintenance note, including the role of bots and AI tools in keeping GitHub Actions up to date.
- Added a maintenance update covering workflow dependency refreshes, pinned action revisions, and reviewer guidance.

Tests

- Added coverage to verify button presses trigger audio feedback.
- Added checks to ensure the global accept action does not play sounds while editing text in input fields.

---

## Reviewer's Guide

Adds regression tests and helpers around UI confirmation audio safeguards, verifies deferred button press audio routing, documents CI workflow maintenance, and clarifies the ui_accept focus guard in Globals.

### File-Level Changes

| Change                                                                                                          | Details                                                                                                                                                                                                                                                                                                                                                                                                                                            | Files                                            |
|-----------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------|
| Refactor and extend UI input guard tests to cover more focused controls while reducing duplication.             | <ul><li>Introduce _assert_focus_blocks_ui_accept helper to centralize setup, input dispatch, and assertions for focused controls.</li><li>Update existing tests for CheckButton, HSlider, Button, and TextureButton to use the new helper.</li><li>Add new regression tests ensuring LineEdit and TextEdit focus suppress global ui_accept audio.</li><li>Tidy comments around focus handling and navigation coverage in the test suite.</li></ul> | `test/gut/test_globals_input_guards.gd`          |
| Add functional coverage ensuring button press hooks trigger AudioManager playback through deferred connections. | <ul><li>Create a test that instantiates a standard Button, registers it via existing tracking, and clears audio state.</li><li>Emit the pressed signal and yield one frame to allow deferred connections to execute.</li><li>Assert that AudioManager reports SFX playback as a result of the button press hook.</li></ul>                                                                                                                         | `test/gut/test_globals_button_hooks.gd`          |
| Clarify the intent of the ui_accept focus guard in the global input handler.                                    | <ul><li>Add comments documenting that focused interactive controls bypass the global ui_accept loop to avoid double-triggered confirmation sounds.</li></ul>                                                                                                                                                                                                                                                                                       | `scripts/core/globals.gd`                        |
| Document CI workflow maintenance and bot/AI contributions for the milestone.                                    | <ul><li>Add a Maintenance markdown document summarizing updates to pinned GitHub Actions versions for caching, release drafting, and SARIF uploads.</li><li>Describe the roles of automated tools and human contributors in the CI maintenance process.</li><li>Provide a reviewers guide summarizing file-level CI workflow changes for the milestone.</li></ul>                                                                                  | `files/docs/milestones/21/Part_4_Maintenance.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                       | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/787 | Ensure that pressing ui_accept (Enter/Space or controller equivalent) on standard menu buttons plays the confirmation audio exactly once by preventing the global input handler from triggering audio when an interactive control (e.g., BaseButton) has focus. | ✅         |             |
| https://github.com/ikostan/SkyLockAssault/issues/787 | Add regression tests that cover UI input audio safeguards (focused controls bypass global ui_accept playback) and verify that button press hooks correctly trigger AudioManager playback via deferred connections.                                              | ✅         |             |

---

**Bots/AI Contributions to PR #803**

This PR primarily addresses a UI confirmation audio double-trigger bug for `ui_accept` events (linked to issue #787), adds/enhances GUT unit tests for global audio hooks and input guards, and includes maintenance documentation for CI workflow updates. While human oversight integrated the changes, bots and AI tools handled the bulk of dependency updates, code reviews, summaries, refactoring suggestions, and quality checks.

### AI/Bot Contributors
- **@dependabot** — Primary driver of CI dependency updates (e.g., bumping `actions/cache` from v5 to v6, refreshing pinned SHAs for `release-drafter/release-drafter` and `github/codeql-action/upload-sarif` across multiple workflows like `browser_test.yml`, `deploy_to_itch.yml`, security scans, etc.). Automated commits were merged into this PR.
- **@sourcery-ai** — Generated automated PR summaries, reviewer's guides, enhancement suggestions, and contributed to documentation refinements (e.g., workflow count fixes in `Part_4_Maintenance.md`). Provided structured analysis of changes, related PR context, and estimated review effort.
- **@coderabbitai** — Delivered detailed walkthroughs, file-level summaries, nitpick comments (e.g., test refactoring for duplication in input guards), actionable suggestions, and poems. Co-authored commits for test updates and improvements based on review feedback. Also suggested finishing touches like unit test generation.
- **@deepsource-io** (DeepSourceReview) — Performed automated code reviews with a PR Report Card covering Security, Reliability, Complexity, and Hygiene for Python/JavaScript analyzers. Provided inline comments and overall quality validation.

These tools collectively managed most technical updates, validation, documentation polishing, and review processes, showcasing effective automation for CI hygiene and test coverage.

### Human Contributors
- **@ikostan** — Opened the PR, implemented the core bug fix in `globals.gd`, added/expanded tests (`test_globals_button_hooks.gd`, `test_globals_input_guards.gd`), created and refined the maintenance doc (`Part_4_Maintenance.md`), merged bot contributions, applied labels (bug, testing, CI/CD, etc.), self-assigned, and handled milestone/project tracking.
- **@espanakosta-jpg** — No direct commits or reviews visible in this PR's timeline (potential upstream or related context contributions).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
