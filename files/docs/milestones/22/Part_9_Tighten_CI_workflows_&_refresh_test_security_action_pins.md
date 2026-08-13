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
