# Refresh stale, CodeQL SARIF, and release-drafter action pins
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

## PR #868 Summary: Refresh stale, CodeQL SARIF, and release-drafter action pins

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan (consolidating Dependabot updates)  
**Branch:** `maintenance` → `main`  
**Milestone:** Milestone 22 – Optimize Test Suite Runtime & Fix Loading Screen  
**Labels:** CI/CD, dependencies, github actions, dependabot, github_actions

### Purpose

Routine security and maintenance update that refreshes pinned GitHub Actions SHAs across several CI workflows. Keeps third-party actions on current, verified commits to reduce supply-chain risk while preserving existing workflow behavior.

### Changes

#### Updated Actions

| Action                              | Previous  | New                  | Workflows Affected                              |
|-------------------------------------|-----------|----------------------|-------------------------------------------------|
| `actions/stale`                     | 10.4.0    | **11.0.0**           | `.github/workflows/stale.yml`                   |
| `release-drafter/release-drafter`   | 7.6.0     | **7.7.0**            | `release_drafter.yml`, `release_drafter_pr.yml` |
| `github/codeql-action/upload-sarif` | older SHA | **newer pinned SHA** | `snyk.yml`, `trivy.yml`                         |

#### File-Level Details

- **`.github/workflows/stale.yml`** – Bumped to `actions/stale@v11.0.0` (new major version) and cleaned up related comments.
- **`.github/workflows/release_drafter.yml`** & **`release_drafter_pr.yml`** – Updated Release Drafter pin.
- **`.github/workflows/snyk.yml`** – Refreshed CodeQL SARIF upload pin for both Code and Open Source scans.
- **`.github/workflows/trivy.yml`** – Refreshed CodeQL SARIF upload pin for security-scan results.

### Origin of Changes

The individual version bumps were originally opened by **@dependabot** as separate PRs (#865, #866, #867). This PR consolidates those updates into a single, reviewable change set.

### Benefits

- Keeps CI tooling on current, security-reviewed action versions.
- Reduces exposure to known issues in older action releases.
- Maintains consistent pinning strategy (commit SHAs) across the repository.
- Minimal risk – pure dependency pin updates with no functional logic changes.

### Review Notes

- Trivial review effort (~5 minutes).
- Sourcery and CodeRabbit both flagged a minor comment-update needed in `stale.yml` (version guidance still referenced the old v10.x series); this was addressed in a follow-up commit.

---

## Reviewer's Guide

This PR performs maintenance on GitHub Actions workflows by updating pinned action SHAs for security and compatibility, primarily for SARIF uploads, release drafting, and stale issue management.

### File-Level Changes

| Change                                                                                            | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Files                                                                                                                                                                                       |
|---------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Refresh pinned SHAs for third-party GitHub Actions to newer, secure versions across CI workflows. | <ul><li>Update github/codeql-action upload-sarif SHA in snyk workflow for both Code and Open Source SARIF uploads.</li><li>Update github/codeql-action upload-sarif SHA in trivy workflow for security scan SARIF uploads.</li><li>Update release-drafter action SHA in the main release_drafter workflow to a newer commit.</li><li>Update release-drafter action SHA in the release_drafter_pr workflow to a newer commit.</li><li>Update actions/stale action SHA in the stale workflow from v10.4.0 to v11.0.0.</li></ul> | `.github/workflows/snyk.yml`<br/>`.github/workflows/trivy.yml`<br/>`.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml`<br/>`.github/workflows/stale.yml` |

---

## PR #868 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@dependabot**  
  Authored the core dependency bump commits:
  - `actions/stale` from 10.4.0 → 11.0.0
  - `release-drafter/release-drafter` from 7.6.0 → 7.7.0
  - `github/codeql-action/upload-sarif` to a newer pinned SHA  
  These were originally opened as separate Dependabot PRs (#865, #866, #867) and consolidated here.

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (suggested updating inline comments in `stale.yml` to reflect the new v11.0.0 pin). Also updated the PR title.

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Performed code review with an actionable comment on updating the version-guidance note in `.github/workflows/stale.yml`.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene) with analyzer status for Python and JavaScript.

### Human Contributor

- **@ikostan**  
  Primary maintainer of the PR. Merged the individual Dependabot PRs into this branch, self-assigned the work, applied labels (`CI/CD`, `dependencies`, `github actions`, `dependabot`, `github_actions`), added it to Milestone 22 and the project board, and made the follow-up commit updating `stale.yml` (addressing review feedback on version comments).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
