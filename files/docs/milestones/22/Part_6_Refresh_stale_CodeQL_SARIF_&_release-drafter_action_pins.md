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

Refreshes pinned SHAs for several GitHub Actions used in CI workflows (stale issues, release drafting, and SARIF uploads) and documents the maintenance work under Milestone 22.

### File-Level Changes

| Change                                                                                                                          | Details                                                                                                                                                                                                                                                                      | Files                                                                                         |
|---------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| Update stale issue management workflow to the latest pinned actions/stale version and align inline documentation.               | <ul><li>Bump actions/stale from v10.4.0 to v11.0.0 using a new pinned commit SHA in the stale workflow job.</li><li>Simplify and generalize the inline comment about periodically refreshing the pinned SHA away from the old v10.x guidance.</li></ul>                      | `.github/workflows/stale.yml`                                                                 |
| Refresh CodeQL SARIF upload action pins used by Snyk-based security scans.                                                      | <ul><li>Update github/codeql-action/upload-sarif pinned SHA for Snyk Code SARIF uploads in the snyk workflow.</li><li>Update github/codeql-action/upload-sarif pinned SHA for Snyk Open Source SARIF uploads in the snyk workflow.</li></ul>                                 | `.github/workflows/snyk.yml`                                                                  |
| Refresh CodeQL SARIF upload action pin used by Trivy security scanning.                                                         | <ul><li>Update github/codeql-action/upload-sarif pinned SHA for Trivy scan SARIF uploads in the trivy workflow.</li></ul>                                                                                                                                                    | `.github/workflows/trivy.yml`                                                                 |
| Update release-drafter action pins in both main and PR release drafting workflows.                                              | <ul><li>Bump release-drafter/release-drafter to a newer pinned commit in the main release_drafter workflow.</li><li>Bump release-drafter/release-drafter to the same newer pinned commit in the PR-focused release_drafter_pr workflow.</li></ul>                            | `.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml`        |
| Add milestone documentation describing the consolidated GitHub Actions pin refresh and its origin from multiple Dependabot PRs. | <ul><li>Create a Milestone 22 documentation file summarizing the purpose, updated actions, affected workflows, origin of changes, and review notes.</li><li>Include a reviewer’s guide section outlining the file-level changes and contributors (bots and human).</li></ul> | `files/docs/milestones/22/Part_6_Refresh_stale_CodeQL_SARIF_&_release-drafter_action_pins.md` |

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
