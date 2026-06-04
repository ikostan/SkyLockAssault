# Update Godot export action pin and configure Codecov token

## Summary

Update CI workflows to use the latest pinned Godot export action and
ensure test reports upload correctly to Codecov.

### CI

- Bump the pinned SHA of the firebelley/godot-export GitHub Action
  across browser tests, CodeQL analysis, and itch.io deployment workflows.
- Set the Codecov upload step in the GUT tests workflow to use the
  `CODECOV_TOKEN` secret for authenticated report uploads.

### Chores

  - Updated build and export automation dependencies to maintain
    compatibility and reliability.
  - Enhanced CI/CD pipeline security by properly configuring token access
    for automated code coverage reporting.

---

## Reviewer's Guide

Updates CI workflows to use a newer pinned revision of the
firebelley/godot-export GitHub Action and ensures the Codecov upload step
has the required token set via environment variables.


### File-Level Changes

<!-- markdownlint-disable MD013 MD033 table-column-style -->
| Change                                                                                                | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                      | Files                                                                                                              |
|-------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| Bump the pinned firebelley/godot-export GitHub Action SHA across workflows to a newer revision.       | <ul><li>Update the godot-export action reference in the browser_test workflow to the new commit SHA while keeping Godot 4.5 download URLs unchanged.</li><li>Update the godot-export action reference in the codeql workflow to the new commit SHA, preserving existing Godot build URLs and comments.</li><li>Update the godot-export action reference in the deploy_to_itch workflow to the new commit SHA, keeping export configuration intact.</li></ul> | `.github/workflows/browser_test.yml`<br/>`.github/workflows/codeql.yml`<br/>`.github/workflows/deploy_to_itch.yml` |
| Fix Codecov upload configuration so reports are sent with the explicit token from repository secrets. | <ul><li>Set CODECOV_TOKEN environment variable for the Codecov upload step in the gut_tests workflow, sourcing it from GitHub Actions secrets.</li><li>Leave the rest of the test report discovery and upload logic unchanged.</li></ul>                                                                                                                                                                                                                     | `.github/workflows/gut_tests.yml`                                                                                  |
<!-- markdownlint-enable MD013 MD033 table-column-style -->

---

## Bots/AI Contributions Summary for PR #736

This PR focuses on CI/CD maintenance: updating the pinned SHA for the 
`firebelley/godot-export` GitHub Action across multiple workflows and
configuring the `CODECOV_TOKEN` for authenticated coverage uploads.
It received valuable support from automated bots and AI tools for dependency
management, summarization, and code quality review.

### Automated Bots & AI Tools

- **@dependabot[bot]**: Initiated and managed the major version bump of `firebelley/godot-export` from 7.0.0 to 8.0.0, including the automated commit and PR creation for the dependency update. This ensured the workflows stayed current with the latest action features and security improvements.
- **@sourcery-ai**: Generated a clear PR summary and reviewer's guide, highlighting the action version bump across workflows and the Codecov token configuration. Also assisted with title generation and overall review structure.
- **@coderabbitai**: Provided a focused summary emphasizing CI/CD reliability improvements, security enhancements through proper token handling, and maintenance of build/export automation.
- **@deepsource-io**: Conducted automated static code analysis and code review on the workflow changes. Provided an overall grade across Security, Reliability, Complexity, and Hygiene categories, along with inline comments and a full review report.

These tools contributed to better documentation, reviewer guidance,
dependency security, and code health validation.

### Human Maintainers

- **@ikostan**: Primary contributor and PR author. Coordinated the changes,
  updated the pinned commit SHAs for the Godot export action in `browser_test.yml`,
  `codeql.yml`, and `deploy_to_itch.yml`, configured the `CODECOV_TOKEN`
  environment variable in `gut_tests.yml`, added a detailed reviewer's guide with
  Mermaid flowchart, and integrated the updates into the project milestone.

---
