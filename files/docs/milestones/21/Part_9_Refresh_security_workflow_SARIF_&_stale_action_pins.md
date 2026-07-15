# 🏁 Refresh security workflow SARIF and stale action pins
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

This pull request performs routine maintenance on the project's GitHub Actions workflows to keep security scanning and stale-issue automation up to date.

### Key Changes

- **Updated pinned SHAs for security tools**:
  - Bumped `github/codeql-action/upload-sarif` to a newer commit (8096e4f...) in:
    - `.github/workflows/snyk.yml` (for both Code and Open Source scans)
    - `.github/workflows/trivy.yml` (for vulnerability scanning)
  - Bumped `actions/stale` from `v10.3.0` to `v10.4.0` in `.github/workflows/stale.yml`.
- Added explanatory inline comments in the Snyk and Trivy workflows documenting the pinned `upload-sarif` action (tied to CodeQL v3) and the recommendation to refresh SHAs periodically for security/stability.
- No changes to workflow logic, schedules, permissions, scan commands, conditions, or reporting behavior.

### Purpose

These updates maintain best practices for GitHub Actions by using fresh, pinned commit SHAs (instead of mutable tags) while preserving the existing secure configuration. This reduces supply-chain risk and keeps automated security tooling current.

---

## Reviewer's Guide

Maintenance PR updating pinned SHAs for GitHub Actions security/stale workflows while preserving behavior, plus minor inline documentation for pinning rationale.

### File-Level Changes

| Change                                                                                                     | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Files                                                                                    |
|------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------|
| Refresh pinned CodeQL SARIF upload action used by Snyk and Trivy workflows and document pinning rationale. | <ul><li>Update github/codeql-action/upload-sarif SHA for Snyk Code SARIF upload step to 8096e4f9571939c23cbd19018c44c665f90096af</li><li>Update github/codeql-action/upload-sarif SHA for Snyk Open Source SARIF upload step to 8096e4f9571939c23cbd19018c44c665f90096af</li><li>Update github/codeql-action/upload-sarif SHA for Trivy SARIF upload step to 8096e4f9571939c23cbd19018c44c665f90096af</li><li>Add comments explaining alignment with CodeQL v3, security pinning to SHAs, and recommendation to refresh pins periodically in Snyk and Trivy workflows</li></ul> | `.github/workflows/snyk.yml`<br/>`.github/workflows/trivy.yml`                           |
| Update stale-issue workflow to newer pinned actions/stale release.                                         | <ul><li>Bump actions/stale from pinned SHA for v10.3.0 to pinned SHA for v10.4.0</li><li>Retain existing stale issue/PR configuration, messages, and behavior</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                         | `.github/workflows/stale.yml`                                                            |
| Add milestone documentation describing the workflow pin refresh and review context.                        | <ul><li>Create milestone document summarizing the purpose and key changes of the PR</li><li>Document bot/AI and human contributions to the PR and reiterate that workflow behavior is unchanged</li></ul>                                                                                                                                                                                                                                                                                                                                                                       | `files/docs/milestones/21/Part_9_Refresh_security_workflow_SARIF_&_stale_action_pins.md` |

---

**Bots/AI Contributions to PR #824**

This PR focuses on maintenance of GitHub Actions workflows: updating pinned SHAs for `github/codeql-action/upload-sarif` (in Snyk and Trivy workflows) and `actions/stale` (to v10.4.0), while preserving configuration, security scanning behavior, and stale-issue handling. No functional changes to workflows were made beyond the pin refreshes and minor documentation comments.

### Bot/AI Contributors

- **@dependabot** — Automated dependency updates. Created and signed commits bumping `actions/stale` from 10.3.0 to 10.4.0 and updating the `github/codeql-action/upload-sarif` SHA across relevant workflows.
- **@sourcery-ai** — AI code reviewer. Generated PR summary, reviewer's guide, and high-level feedback suggesting inline comments for pinned SHAs and potential centralization of the upload-sarif reference (addressed in a follow-up commit). Reviewed changes as non-actionable in the final pass.
- **@coderabbitai** — AI code reviewer. Provided a concise chore-focused summary highlighting the security scanning and stale workflow updates with no behavior changes.
- **@deepsource-io** (DeepSourceReview) — Automated code analysis. Performed a full review of changes (Python/JavaScript analyzers) and generated a PR report card with inline comments where applicable.

### @ikostan Contributions (Human)

@ikostan drove the overall PR:

- Created the PR and handled merges from main/dependabot branches.
- Self-assigned, labeled (dependencies, CI/CD, github-actions, etc.), and milestone/project tracking.
- Addressed Sourcery feedback by adding explanatory inline comments documenting the pinned `upload-sarif` SHA (tied to CodeQL v3) and the need for periodic refreshes in `snyk.yml` and `trivy.yml`.
- Final commit (`b338252`) for annotation/documentation with no functional impact.
- Reacted to bot/AI summaries and reviews.

These contributions reflect a collaborative maintenance workflow combining automated dependency management (@dependabot), multi-AI review layers (@sourcery-ai, @coderabbitai, @deepsource-io), and targeted human oversight (@ikostan). The PR keeps workflows secure and up-to-date with minimal disruption.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
