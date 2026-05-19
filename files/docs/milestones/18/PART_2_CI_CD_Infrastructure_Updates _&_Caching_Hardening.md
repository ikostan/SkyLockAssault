# PR Summary: CI/CD Infrastructure Updates & Caching Hardening

## Description

This PR stabilizes and secures the GitHub Actions deployment and testing
pipelines by upgrading core deployment tooling, mitigating supply-chain
risks, and permanently resolving persistent cache de-synchronization
issues.

**Key Updates & Technical Decisions:**

* **Butler CLI Upgrade & Domain Migration:** Bumped the itch.io Butler
  CLI to `15.27.0`. Addressed a silent upstream breakage by migrating
  the download endpoint from the retired `broth.itch.ovh` domain to the
  active `broth.itch.zone` domain.
* **Supply-Chain Security:** Introduced strict SHA-256 checksum
  validation for the downloaded Butler binary. The version
  (`BUTLER_VERSION`) and its corresponding hash (`BUTLER_SHA256`) are
  now centralized and co-located in the workflow `env` block to ensure
  they are updated together, preventing future desynchronization.
* **Bulletproofed Playwright Caching:** Completely refactored the
  Playwright browser cache key logic in `browser_test.yml`. Instead
  of hashing `requirements.txt` or relying on brittle CLI string
  parsing (e.g., `awk '{print $2}'`), the workflow now securely
  extracts the exact installed package version using Python's
  `importlib.metadata`. This guarantees the cache key strictly matches
  the installed binary, eliminating `Executable doesn't exist` errors.
  Playwright is also bumped to `1.60.0`.
* **Deliberate Infrastructure Constraints:** Intentionally rejected
  automated suggestions to make the Butler cache key OS-dynamic
  (`${{ runner.os }}`). Because the workflow explicitly targets and
  downloads the `linux-amd64` payload for an `ubuntu-latest` runner,
  the cache key remains hardcoded to `Linux` to prevent cross-platform
  contamination if the runner OS is ever modified.

---

## File-Level Changes

<!-- markdownlint-disable line-length table-column-style -->
| Change                                                                                                             | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Files                                                  |
|--------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------|
| Upgrade Butler CLI in the deployment workflow and make its setup cache- and version-aware with integrity checks.   | Introduce a `BUTLER_VERSION` environment variable to pin the Butler CLI version centrally in the workflow.Update the Butler cache key to include OS and the pinned Butler version, and reset the cache namespace (v1).Add a conditional step that downloads the Butler archive only on cache misses, including SHA-256 checksum verification before extraction.Refine the Butler setup step to set execute permissions, verify the Butler version explicitly, and then place its directory on PATH. | `.github/workflows/deploy_to_itch.yml`                 |
| Stabilize Playwright browser caching by keying it off the installed Playwright CLI version and upgrade Playwright. | Add a workflow step that extracts the Playwright CLI version and exposes it as an output for subsequent steps.Change the Playwright browser cache key to use the runner OS and detected Playwright version instead of hashing requirements.txt.Upgrade the Playwright Python dependency from 1.58.0 to 1.60.0 to align with the new caching strategy.                                                                                                                                               | `.github/workflows/browser_test.yml``requirements.txt` |

---

## Assessment against linked issues

| Issue                                                                                                        | Objective                                                                                                                                                    | Addressed | Explanation |
|--------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| [https://github.com/ikostan/SkyLockAssault/issues/614](https://github.com/ikostan/SkyLockAssault/issues/614) | Update the deployment workflow to pin Butler to version 15.27.0 and adjust the cache key accordingly.                                                        | ✅         |             |
| [https://github.com/ikostan/SkyLockAssault/issues/614](https://github.com/ikostan/SkyLockAssault/issues/614) | Add a conditional download step that fetches the Butler 15.27.0 Linux binary on cache miss in the deployment workflow.                                       | ✅         |             |
| [https://github.com/ikostan/SkyLockAssault/issues/614](https://github.com/ikostan/SkyLockAssault/issues/614) | Ensure the workflow sets up and executes Butler 15.27.0 (including a version check) so deployments run with the updated binary without update notifications. | ✅         |             |
<!-- markdownlint-enable line-length table-column-style -->

---

## Contributions

**@ikostan’s Contributions to PR #654**

### Key Contributions:

* Created the PR, self-assigned it, linked to issue #614, and
  provided full documentation.
* **.github/workflows/deploy_to_itch.yml**: Upgraded Butler
  to **15.27.0**, updated download URL, added centralized 
  `BUTLER_VERSION` + `BUTLER_SHA256` env vars, implemented
  version-aware caching, conditional download on cache miss,
  SHA-256 integrity verification, and proper setup (`chmod`,
  version check, PATH).
* **.github/workflows/browser_test.yml**: Added Playwright
  version extraction step and updated cache key to use exact
  version for stability.
* **requirements.txt**: Bumped `playwright` to **1.60.0**.
* Made deliberate design choices (e.g., Linux-specific Butler
  cache key) and addressed bot feedback while preserving project
  constraints.

All commits authored by @ikostan. This PR improves deployment 
reliability, caching stability, and supply-chain security.

---

**Bots/AI Contributions Summary for PR #654** (Upgrade Itch.io Butler
Tooling to v15.27.0 in Deployment Pipeline).

### Key AI/Bot Contributors

These tools provided automated summaries, reviews, suggestions, and
static analysis. The PR author (@ikostan) explicitly noted rejecting
some bot suggestions (e.g., making the Butler cache key fully OS-dynamic,
since the pipeline requires linux-amd64).

* **@sourcery-ai** (Sourcery): Generated a detailed PR summary, bug
  fixes/enhancements list, build changes, reviewer's guide, walkthrough,
  estimated review effort, suggested labels, and a poem. Provided code
  review comments on issues like quoted `if` conditions, hard-coded
  versions, Linux-specific assumptions vs. OS-parameterized cache keys,
  and duplication of version strings. Suggested centralizing
  `BUTLER_VERSION` via `env` (which was implemented).
* **@coderabbitai** (CodeRabbit): Provided a concise summary of
  chores/enhancements (Butler upgrade, caching improvements, conditional
  download, version verification, Playwright pinning to 1.60.0). Posted
  actionable review comments (e.g., hardening downloads with
  retries/checksums) and supported iterative fixes between commits.
* **DeepSource** / **@deepsource-io** (or **@deepsource-bot**):
  Performed static analysis and code quality review on changes
  (Python/JS where applicable). Generated a PR Report Card with grades
  for Security, Reliability, Complexity, and Hygiene, plus inline comments
  and a full review link. This aligns with the repo's established use of
  DeepSource for automated checks.

### Overall Impact and Nuances

* **Positive Contributions**: These bots accelerated review by catching
  potential issues (e.g., version skew, conditional step evaluation,
  caching reliability) early. They generated structured documentation
  (summaries, guides) that improved PR clarity and maintainability.
  Security additions (checksums) and caching fixes directly addressed
  real pipeline problems.
* **Human Oversight**: @ikostan drove the core changes, intentionally
  overrode some suggestions for project-specific constraints (e.g.,
  Linux-only Butler binary), and incorporated others (e.g., env-based
  versioning, Playwright version extraction via Python). This hybrid
  approach—AI for speed/spotting edge cases, human for context—worked well.
* **Edge Cases/Related Considerations**: Bots flagged cross-OS risks and
  duplication, which could cause future maintenance issues or cache
  pollution. The final implementation uses pinned versions, explicit
  checks, and conditional logic to minimize flakiness in GitHub Actions.
  No major breaking changes; improvements focus on reliability and
  supply-chain security.
* **Broader Implications**: Demonstrates effective use of AI code tools
  in a Godot/CI-heavy repo. Future PRs could leverage commands like
  `@sourcery-ai review` or similar for faster iterations. DeepSource
  adds ongoing hygiene without manual effort.

---

**Full Contributors List (for GitHub recognition)**: 
@ikostan, @sourcery-ai, @coderabbitai, @deepsource-io (or @deepsource-bot).
