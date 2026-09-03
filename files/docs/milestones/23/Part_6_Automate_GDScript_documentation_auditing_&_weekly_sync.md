# Automate GDScript documentation auditing and weekly sync
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

Introduce a deterministic GDScript documentation auditor (.github/scripts/update_gdscript_docs.py), a strict contract validator (.github/scripts/validate_gdscript_docs.py), and a scheduled GitHub Actions workflow (.github/workflows/weekly_docstrings.yml). The auditor parses GDScript AST (gdtoolkit), classifies members (COMPLIANT/MISSING/NON_COMPLIANT/AMBIGUOUS), enforces a BBCode allowlist, verifies non-doc SHA-256 integrity, and performs transactional atomic writes after generating docs via a pinned Gemini model. The validator enforces placement, parameter tags, and banned constructs. The workflow runs weekly (or on-demand), installs pinned deps, runs the auditor (write), validator, gdlint, Godot headless checks, and opens/updates a PR with any changes.

---


---

### Purpose

---

## Reviewer's Guide


---



---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
