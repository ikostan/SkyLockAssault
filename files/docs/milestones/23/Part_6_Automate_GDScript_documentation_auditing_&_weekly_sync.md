# Automate GDScript documentation auditing and weekly sync
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

## PR #916 Summary: Automate GDScript documentation auditing and weekly sync

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `automated-weekly-gdscript-docstring-standardization-sync` → `main`  
**Linked Issue:** #915 ([FEATURE] Automated Weekly GDScript Docstring Standardization & Sync)  
**Milestone:** Milestone 23 – Settings Architecture & FPS Counter Implementation  
**Labels:** documentation, setup, CI/CD, github actions, github_actions, python, YML

### Purpose

Introduce a fail-closed, deterministic pipeline that audits production GDScript for public-member documentation, generates missing or non-compliant Godot 4 `##` docstrings (via a pinned Gemini model), validates documentation contracts, and syncs changes weekly (or on demand) through an automated pull request.

Introduce a deterministic GDScript documentation auditor (.github/scripts/update_gdscript_docs.py), a strict contract validator (.github/scripts/validate_gdscript_docs.py), and a scheduled GitHub Actions workflow (.github/workflows/weekly_docstrings.yml). The auditor parses GDScript AST (gdtoolkit), classifies members (COMPLIANT/MISSING/NON_COMPLIANT/AMBIGUOUS), enforces a BBCode allowlist, verifies non-doc SHA-256 integrity, and performs transactional atomic writes after generating docs via a pinned Gemini model. The validator enforces placement, parameter tags, and banned constructs. The workflow runs weekly (or on-demand), installs pinned deps, runs the auditor (write), validator, gdlint, Godot headless checks, and opens/updates a PR with any changes.

### Core Components

#### 1. Documentation Auditor (`.github/scripts/update_gdscript_docs.py`)

- Parse GDScript with **gdtoolkit** AST (functions, signals, exports, constants, enums)
- Classify members: `COMPLIANT` / `MISSING` / `NON_COMPLIANT` / `AMBIGUOUS`
- Generate structured docs with a **pinned Gemini** model + Pydantic response validation
- Enforce **BBCode allowlist**, parameter-name checks, and annotation-placement rules
- **Safety:** non-doc SHA-256 integrity, modification allowlists/limits, doc-only diffs
- **Transactional writes** with staged atomic renames and rollback on failure

#### 2. Contract Validator (`.github/scripts/validate_gdscript_docs.py`)

- Require native `##` docs for supported public members (including signals, constants, enums)
- Validate parameter tags, banned Markdown/Doxygen constructs, BBCode usage
- Reject symlinks and paths outside approved production script directories
- Handle `[code]` blocks and case-insensitive `[param]` matching

#### 3. Scheduled CI (`.github/workflows/bi_weekly_gd_docstrings.yml`)

- Weekly schedule **and** manual `workflow_dispatch`
- Pinned checkout, Python setup, Godot, and PR-creation actions (immutable SHAs)
- Pipeline: audit/generate → validate → `gdlint` → Godot headless `--check-only`
- Create or update a dedicated docs-sync branch and PR when changes exist
- Split audit vs generate stages for clearer fail-closed behavior

#### 4. Documentation

- Milestone doc: `files/docs/milestones/23/Part_6_Automate_GDScript_documentation_auditing_&_weekly_sync.md`

#### 5. Milestone 23 Pipeline Resiliency & Quota Updates

* **Pinned Gemini Model & Quota Management**: Updated the pipeline model to `gemini-3.5-flash-lite`, leveraging a higher Free Tier quota (500 RPD / 15 RPM) with robust exponential backoff retry logic and 5-second pacing delays.
* **Chunked Processing Strategy**: Configured single-slot chunking (`chunk_size = 1`) to completely eliminate JSON truncation and prevent member omission during large file processing (e.g., `globals.gd`).
* **Twice-A-Weekly Schedule**: Updated the cron schedule in `.github/workflows/weekly_docstrings.yml` to run bi-weekly on **Sundays and Wednesdays at 00:00 UTC** (`0 0 * * 0,3`).
* **Linter & Formatting Alignment**: Replaced unstable headless Godot script syntax checks with `gdformat --diff --check ./scripts` and `gdlint`, aligning the workflow with the repository's dedicated linting standard.
* **Automatic Line Wrapping & Context Preservation**: Integrated Python's `textwrap` module to automatically wrap injected documentation comments at 95 characters for strict compliance with `gdlint`'s 100-character line-length limit. Updated the LLM prompt to ingest `existing_developer_comments` and mandate `returns` field mapping to preserve technical context and prevent docstring regressions.

### Benefits

- Keeps public GDScript API docs complete and Godot-native without manual drift
- Fail-closed design avoids silent bad generation or non-doc source mutations
- Reproducible weekly sync with pinned tooling and scoped credentials
- Lint + headless Godot checks gate automated PRs before merge consideration

### Status Notes

Fully addresses #915: deterministic auditor/injector, documentation contracts and source-safety invariants, and a reproducible weekly/manual CI sync workflow under Milestone 23.

---

## Reviewer's Guide

This PR introduces a fail-closed AST-based GDScript documentation auditor and validator, then integrates them into a scheduled/manual GitHub Actions workflow that generates guarded docstring-only changes, verifies them with lint and Godot checks, and submits them through an automated pull request.

### File-Level Changes

| Change                                                                                                                                                                                        | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Files                                                                                       |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Add an AST-based auditor that discovers public GDScript members, classifies documentation coverage, generates missing or non-compliant docstrings, and applies guarded transactional updates. | <ul><li>Parse functions, signals, exports, constants, and enums with gdtoolkit.</li><li>Classify documentation as compliant, missing, non-compliant, or ambiguous, including annotation-placement checks.</li><li>Generate structured documentation through the pinned Gemini model with Pydantic validation and parameter-name checks.</li><li>Restrict edits to documentation lines, verify non-documentation SHA-256 integrity, enforce modification limits, and commit changes with staged atomic renames and rollback.</li></ul> | `.github/scripts/update_gdscript_docs.py`                                                   |
| Add a strict AST-driven documentation contract validator for production GDScript files.                                                                                                       | <ul><li>Require native `##` documentation for all supported public member types.</li><li>Validate parameter references, annotation placement, banned Markdown/Doxygen constructs, and the BBCode allowlist.</li><li>Reject symlinks and paths outside the configured production script subdirectories.</li></ul>                                                                                                                                                                                                                      | `.github/scripts/validate_gdscript_docs.py`                                                 |
| Automate weekly and on-demand documentation synchronization through a pinned GitHub Actions pipeline.                                                                                         | <ul><li>Install pinned Python dependencies and run audit, generation, validation, gdlint, and Godot headless parsing checks.</li><li>Use a pinned checkout, setup, Godot, and pull-request action configuration.</li><li>Create or update a dedicated documentation synchronization branch and pull request based on generated changes.</li></ul>                                                                                                                                                                                     | `../../../../.github/workflows/bi_weekly_gd_docstrings.yml`                                 |
| Document the new automated GDScript documentation auditing and synchronization process.                                                                                                       | <ul><li>Describe the auditor, validator, integrity safeguards, model generation, scheduled workflow, and verification stages.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                               | `files/docs/milestones/23/Part_6_Automate_GDScript_documentation_auditing_&_weekly_sync.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                              | Addressed | Explanation |
|------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/915 | Implement a deterministic auditor and injector that scans only approved production GDScript directories, identifies missing or non-compliant documentation for public members, preserves compliant docstrings, and injects only Godot 4 `##` documentation comments.   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/915 | Enforce documentation contracts and source-safety guarantees, including Native BBCode validation, parameter-reference checks, deterministic ambiguity handling, modification allowlists, non-documentation source integrity verification, and modification thresholds. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/915 | Provide a reproducible weekly and manually-triggerable CI pipeline with pinned tooling and model dependencies, fail-closed validation and headless checks, scoped Gemini credentials, and automated PR creation targeting the `docs` branch.                           | ✅        |             |

### Possibly linked issues

- **#915**: The PR directly implements issue #915's requested documentation pipeline, validators, safety invariants, and scheduled sync workflow.

---

## PR #916 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (including transactional-commit / atomicity feedback). Co-authored workflow and auditor updates (e.g. `bi_weekly_gd_docstrings.yml`, `update_gdscript_docs.py`).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the documentation auditing pipeline and pre-merge checks (including docstring-coverage feedback on the new Python tooling).

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@deepsource-autofix**  
  Authored multiple automated style/format commits (`style: format code with Black and isort`) across the PR lifecycle.

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **55.01%**; all modified coverable lines covered; all tests successful).

- **@copilot** (GitHub Copilot)  
  Co-authored the commit adding signal-parameter support in the GDScript doc tooling.

> **Note:** **@dependabot** did not author commits or leave reviews on this PR (no dependency-bump activity observed).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Implemented the deterministic GDScript documentation auditor (`update_gdscript_docs.py`), strict contract validator (`validate_gdscript_docs.py`), and weekly/on-demand GitHub Actions workflow (`bi_weekly_gd_docstrings.yml`); added integrity safeguards (non-doc SHA-256, modification allowlists, transactional writes, BBCode allowlist, fail-closed validation); pinned Actions/tooling; expanded coverage for signals/constants/enums and annotation placement; and documented the system under Milestone 23 (`Part_6_Automate_GDScript_documentation_auditing_&_weekly_sync.md`).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
