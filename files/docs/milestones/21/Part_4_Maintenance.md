# Maintenance
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

## Summary

Overall, this PR highlights a mature CI maintenance workflow where bots and AI tools drive most of the technical updates and validation, with human oversight for integration and project alignment. The result is more reliable and up-to-date GitHub Actions usage with minimal manual effort.

Update CI workflows to use newer pinned action versions for caching, release drafting, and security report uploads.

CI:

- Bump actions/cache from v5 to v6 across workflows that cache pip, Playwright, and Butler artifacts.
- Update github/codeql-action/upload-sarif to a newer pinned commit in Snyk and Trivy security workflows.
- Refresh release-drafter action in release drafting workflows to a newer pinned commit.

Chores:

- Updated several automated workflows to use newer, supported action versions.
- Refreshed release and security scanning integrations to pinned revisions for more reliable runs.

---

## Reviewer's Guide

This PR performs maintenance on CI workflows by updating pinned versions of actions/cache, release-drafter, and github/codeql-action/upload-sarif across several GitHub Actions workflows to newer, presumably patched SHAs and major versions.

### File-Level Changes

| Change                                                                                                                 | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Files                                                                                                                                                                                                                                                                                                                 |
|------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Update GitHub Actions workflow dependencies to newer pinned versions for caching, release drafting, and SARIF uploads. | <ul><li>Bump actions/cache from v5 to v6 for PIP and Playwright caches in browser_test.yml, gdlint.yml, deploy_to_itch.yml, and yamllint.yml to use the latest major cache implementation.</li><li>Update github/codeql-action/upload-sarif pinned SHA in snyk.yml and trivy.yml to a newer commit while keeping version alignment and security pinning.</li><li>Update release-drafter/release-drafter pinned SHA in release_drafter.yml and release_drafter_pr.yml to a newer commit, maintaining SHA pinning for reproducibility.</li></ul> | `.github/workflows/browser_test.yml`<br/>`.github/workflows/snyk.yml`<br/>`.github/workflows/deploy_to_itch.yml`<br/>`.github/workflows/gdlint.yml`<br/>`.github/workflows/release_drafter.yml`<br/>`.github/workflows/release_drafter_pr.yml`<br/>`.github/workflows/trivy.yml`<br/>`.github/workflows/yamllint.yml` |

---

**Bots/AI Contributions to PR #796**

This PR performs routine maintenance by updating pinned versions of several GitHub Actions in CI/CD workflows (primarily bumping `actions/cache` from v5 to v6, along with refreshed SHAs for `release-drafter/release-drafter` and `github/codeql-action/upload-sarif`). The changes touch eight workflow files to improve caching reliability, security scanning, and release drafting.

### AI/Bot Contributors

- **@dependabot** — Primary contributor of the dependency update commits. Automated multiple version bumps (e.g., `actions/cache`, `release-drafter`, and CodeQL SARIF uploader) and created related PRs that were merged into this one.
- **@sourcery-ai** — Provided an automated PR summary, reviewer's guide, and positive code review. Generated detailed analysis of changes, estimated review effort, and offered interactive commands for further assistance.
- **@coderabbitai** — Delivered a comprehensive walkthrough of the changes, including file-level summaries, related PR context, and helpful finishing touches suggestions.
- **@deepsource-io** (DeepSourceReview) — Performed automated code review across Python and JavaScript analyzers, providing a PR Report Card (covering Security, Reliability, Complexity, and Hygiene) and inline comments where applicable.

These tools collectively handled the bulk of the commit history, summaries, reviews, and quality checks, demonstrating effective use of automation for dependency maintenance and CI hygiene.

### Human Contributors

- **@ikostan** — Opened the PR, performed merges of the Dependabot branches, applied labels (CI/CD, dependencies, github_actions), self-assigned, and managed project/milestone tracking.
- **@espanakosta-jpg** — (No direct commits or reviews visible in the PR timeline; contribution may be in related context or upstream work.)

---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
