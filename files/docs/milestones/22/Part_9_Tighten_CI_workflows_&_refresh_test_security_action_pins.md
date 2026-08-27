# Tighten CI workflows and refresh test/security action pins - #884
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
---

## PR #884 Summary: Tighten CI workflows and refresh test/security action pins

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan (consolidating Dependabot updates)  
**Branch:** `maintenance` → `main`  
**Milestone:** Milestone 22 – Optimize Test Suite Runtime & Fix Loading Screen  
**Labels:** CI/CD, dependencies, github actions, dependabot, github_actions, good first issue

### Purpose

Routine CI maintenance that refreshes pinned GitHub Actions SHAs for security and reliability, and tightens Codecov upload conditions so coverage reporting is skipped cleanly when the token is unavailable (e.g., Dependabot or third-party PRs).

### Changes

#### Updated Actions

| Action                                | Previous  | New                  | Workflows Affected      |
|---------------------------------------|-----------|----------------------|-------------------------|
| `DavidAnson/markdownlint-cli2-action` | 24.1.0    | **24.2.0**           | `lint_readme.yml`       |
| `aquasecurity/trivy-action`           | 0.34.0    | **0.36.0**           | `trivy.yml`             |
| `actions/download-artifact`           | v7        | **v8**               | `browser_test.yml`      |
| `github/codeql-action/upload-sarif`   | older SHA | **newer pinned SHA** | `snyk.yml`, `trivy.yml` |

#### Workflow Tightening

- **`.github/workflows/gut_tests.yml`**  
  Codecov upload step now runs only when the workflow succeeds **and** `secrets.CODECOV_TOKEN != ''`. Token is passed via environment variable for cleaner handling. This prevents failures on Dependabot/third-party PRs that lack the secret while still uploading coverage for regular runs.

#### File-Level Summary

- `gut_tests.yml` – Conditional Codecov guard + env-var token usage
- `snyk.yml` / `trivy.yml` – Refreshed CodeQL SARIF upload pins (and Trivy action pin)
- `browser_test.yml` – Bumped `actions/download-artifact` to v8
- `lint_readme.yml` – Bumped markdownlint-cli2-action

### Origin of Changes

The individual version bumps were opened by **@dependabot** as separate PRs (#880–#883). This PR consolidates them and adds the Codecov conditional logic.

### Benefits

- Keeps security-scanning and linting actions on current, vetted commits
- Avoids noisy CI failures on PRs that cannot access `CODECOV_TOKEN`
- Maintains consistent SHA-pinning strategy across the repository
- Low-risk maintenance with no functional test or application logic changes

### Review Notes

Small, low-effort PR focused purely on CI hygiene and dependency pins.

---

## Reviewer's Guide

This PR performs routine CI workflow maintenance by tightening Codecov upload conditions and refreshing pinned GitHub Action SHAs for test, lint, and security workflows, plus documenting the changes in the milestone notes.

### File-Level Changes

| Change                                                                                                                                     | Details                                                                                                                                                                                                                                                                                                                                                                                                  | Files                                                                                         |
|--------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| Make Codecov upload in GUT test workflow conditional on the presence of a non-empty CODECOV_TOKEN secret and use the env var consistently. | <ul><li>Add shell guard to skip Codecov upload when CODECOV_TOKEN is missing or empty (e.g., Dependabot or external PRs).</li><li>Switch Codecov upload-process token usage from direct secrets reference to the CODECOV_TOKEN environment variable.</li><li>Keep existing logic for locating and uploading the gut_junit.xml report file.</li></ul>                                                     | `.github/workflows/gut_tests.yml`                                                             |
| Refresh pinned SHAs for security-related SARIF upload and scanning actions to newer secure versions.                                       | <ul><li>Update github/codeql-action/upload-sarif to a newer pinned SHA in Snyk workflows for both Code and Open Source SARIF uploads.</li><li>Update aquasecurity/trivy-action to a newer pinned commit for filesystem security scans.</li><li>Update github/codeql-action/upload-sarif to the same newer pinned SHA in the Trivy workflow for uploading Trivy results.</li></ul>                        | `.github/workflows/snyk.yml`<br/>`.github/workflows/trivy.yml`                                |
| Update CI utility actions to current versions for artifact download and README linting.                                                    | <ul><li>Bump actions/download-artifact from v7 to v8 in the browser test workflow for downloading the web build artifact.</li><li>Bump DavidAnson/markdownlint-cli2-action to a newer pinned commit for Markdown linting of README and docs.</li></ul>                                                                                                                                                   | `.github/workflows/browser_test.yml`<br/>`.github/workflows/lint_readme.yml`                  |
| Add milestone documentation summarizing the CI workflow tightening and action pin refresh, including bot/AI contributor notes.             | <ul><li>Create a new milestone documentation markdown file describing the purpose, updated actions, workflow changes, and benefits of the PR.</li><li>Document origin of changes from multiple Dependabot PRs and list bot/AI contributors and the human maintainer.</li><li>Align the documentation with Milestone 22 and project management metadata (labels, branch info, repository link).</li></ul> | `files/docs/milestones/22/Part_9_Tighten_CI_workflows_&_refresh_test_security_action_pins.md` |

---

## PR #884 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@dependabot**  
  Authored the core dependency bump commits:
  - `DavidAnson/markdownlint-cli2-action` 24.1.0 → 24.2.0
  - `aquasecurity/trivy-action` 0.34.0 → 0.36.0
  - `actions/download-artifact` v7 → v8
  - `github/codeql-action/upload-sarif` to a newer pinned SHA  
  These originated as separate Dependabot PRs (#880–#883) and were consolidated here.

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (approved the changes) and updated the PR title.

- **@coderabbitai**  
  Generated the PR summary covering the workflow updates and conditional Codecov handling.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

### Human Contributor

- **@ikostan**  
  Primary maintainer of the PR. Merged the individual Dependabot PRs into this branch, added the conditional `secrets.CODECOV_TOKEN != ''` guard in `gut_tests.yml` (so Codecov uploads are skipped gracefully for Dependabot/third-party PRs), self-assigned the work, applied labels (`CI/CD`, `dependencies`, `github actions`, `dependabot`, `github_actions`, `good first issue`), and added it to Milestone 22 and the project board.

---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
