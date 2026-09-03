# Automate GDScript documentation auditing and weekly sync
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

Introduce a deterministic GDScript documentation auditor (.github/scripts/update_gdscript_docs.py), a strict contract validator (.github/scripts/validate_gdscript_docs.py), and a scheduled GitHub Actions workflow (.github/workflows/weekly_docstrings.yml). The auditor parses GDScript AST (gdtoolkit), classifies members (COMPLIANT/MISSING/NON_COMPLIANT/AMBIGUOUS), enforces a BBCode allowlist, verifies non-doc SHA-256 integrity, and performs transactional atomic writes after generating docs via a pinned Gemini model. The validator enforces placement, parameter tags, and banned constructs. The workflow runs weekly (or on-demand), installs pinned deps, runs the auditor (write), validator, gdlint, Godot headless checks, and opens/updates a PR with any changes.

---


---

### Purpose

---

## Reviewer's Guide

This PR introduces a fail-closed AST-based GDScript documentation auditor and validator, then integrates them into a scheduled/manual GitHub Actions workflow that generates guarded docstring-only changes, verifies them with lint and Godot checks, and submits them through an automated pull request.

### File-Level Changes

| Change                                                                                                                                                                                        | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Files                                                                                       |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------|
| Add an AST-based auditor that discovers public GDScript members, classifies documentation coverage, generates missing or non-compliant docstrings, and applies guarded transactional updates. | <ul><li>Parse functions, signals, exports, constants, and enums with gdtoolkit.</li><li>Classify documentation as compliant, missing, non-compliant, or ambiguous, including annotation-placement checks.</li><li>Generate structured documentation through the pinned Gemini model with Pydantic validation and parameter-name checks.</li><li>Restrict edits to documentation lines, verify non-documentation SHA-256 integrity, enforce modification limits, and commit changes with staged atomic renames and rollback.</li></ul> | `.github/scripts/update_gdscript_docs.py`                                                   |
| Add a strict AST-driven documentation contract validator for production GDScript files.                                                                                                       | <ul><li>Require native `##` documentation for all supported public member types.</li><li>Validate parameter references, annotation placement, banned Markdown/Doxygen constructs, and the BBCode allowlist.</li><li>Reject symlinks and paths outside the configured production script subdirectories.</li></ul>                                                                                                                                                                                                                      | `.github/scripts/validate_gdscript_docs.py`                                                 |
| Automate weekly and on-demand documentation synchronization through a pinned GitHub Actions pipeline.                                                                                         | <ul><li>Install pinned Python dependencies and run audit, generation, validation, gdlint, and Godot headless parsing checks.</li><li>Use a pinned checkout, setup, Godot, and pull-request action configuration.</li><li>Create or update a dedicated documentation synchronization branch and pull request based on generated changes.</li></ul>                                                                                                                                                                                     | `.github/workflows/weekly_docstrings.yml`                                                   |
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



---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
