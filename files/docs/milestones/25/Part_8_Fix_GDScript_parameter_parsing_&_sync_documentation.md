<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Fix GDScript parameter parsing and sync documentation

---

## PR Summary

**Title:** Fix GDScript parameter parsing and sync documentation  
**PR:** [#1009](https://github.com/ikostan/SkyLockAssault/pull/1009)  
**Branch:** `automation/weekly-gdscript-docs` → `main`  
**Opened by:** @github-actions (automated docs sync); assigned to and completed by @ikostan  
**Related PRs:**

- [#1014 – fix(ci): stop lambda args leaking into GDScript param contracts](https://github.com/ikostan/SkyLockAssault/pull/1014)
- [#1015 – Fix/docs lambda param leak](https://github.com/ikostan/SkyLockAssault/pull/1015) (merged into this branch)

**Milestone:** Milestone 25: Resource Migration & Audio Decoupling  
**Labels:** documentation, bug, enhancement, tools, CI/CD, refactoring, python  
**Size:** 3 files, +127 / −44

### Purpose

Two related pieces of work in one PR:

1. **Weekly documentation sync.** The scheduled docstring workflow standardized public GDScript docs in `scripts/core/main_scene.gd` to Godot 4 Native BBCode (`##`).
2. **Parser fix exposed by that sync.** The generated docs for `setup_bushes_layer()` and `setup_decor_layer()` advertised a `[param id]` that neither function accepts. The cause was a shared bug in the generator and the validator: both treated lambda arguments inside a function body as parameters of the function itself. Because the validator had the same flaw, the bogus parameter passed validation.

### Key Changes

- **Docs generator** (`.github/scripts/update_gdscript_docs.py`)
  - `extract_parameters_from_ast()` now inspects only the direct children of the function's own `func_header > func_args` node instead of walking the whole subtree with `iter_subtrees()`.
  - Unwraps `static_func_def` to reach the underlying function definition.
  - Handles `...rest` variadic arguments whether the name sits on the variadic node or on the regular/typed arg node it wraps.
  - Returns `([], True)` for parameterless functions and `([], False)` for malformed or unrecognized argument nodes, so the caller can skip the function safely.
  - Adds a shared `FUNC_ARG_RULES` set and a `_first_name_token()` helper.
- **Docs validator** (`.github/scripts/validate_gdscript_docs.py`)
  - `extract_params()` rewritten with the same header-scoped logic, including static and variadic handling.
  - Docstring notes it must stay in sync with `extract_parameters_from_ast()`.
- **Documentation** (`scripts/core/main_scene.gd`)
  - Removed the invalid `[param id]` from `setup_bushes_layer()` and `setup_decor_layer()`.
  - Descriptions now state that each function clears and repopulates its layer from texture-preloader resources whose IDs begin with `bush_` / `decor_`.
  - Decor docs list the per-element randomization: position, scale, texture, cardinal rotation, and horizontal/vertical flip.
  - `[param viewport]` documents pixel units: `x` bounds horizontal placement; `y` × `parallax_screens_tall` sets the layer height and the mirroring interval.
- **Formatting**
  - Black/isort formatting applied by DeepSource autofix.

### Design Decisions

- **Header-scoped extraction.** Walking the full subtree also collected lambda arguments (e.g. the `id` in `arr.filter(func(id: String) -> bool: ...)`) and returned names bottom-up rather than in source order. Reading only `func_header > func_args` gives exactly the declared parameters, in order.
- **Generator fails closed, validator stays lenient.** On an unrecognized argument node the generator returns `([], False)` so it never writes docs it cannot vouch for. The validator skips the node and keeps going. This divergence is intentional for now but means a future grammar change could make the two disagree (see Follow-ups).
- **Two copies kept.** The generator and validator each keep their own implementation, as before; the cross-reference in the validator's docstring flags that they must change together.

### Follow-ups

- Share a single parameter-extraction implementation between the generator and the validator, or align their handling of unrecognized argument nodes.
- Add a `tests/ci/` regression test covering lambda arguments, static functions, and both variadic AST shapes, so the leak cannot return unnoticed.

### Compatibility

- No gameplay or runtime behavior change. Only docstrings and CI documentation tooling are affected.
- Non-comment source in `main_scene.gd` is byte-for-byte unchanged, enforced by `update_gdscript_docs.py`.
- Functions without lambdas produce the same parameter lists as before.

### Testing

- The automation PR body reports passing the documentation contract validator, `gdlint`, and Godot headless checks.
- DeepSource Python and JavaScript analyzers passed; overall grade A (Security, Reliability, Complexity, Hygiene).
- Both Sourcery review comments (invalid `[param id]`, missing viewport sizing contract) are resolved.

---

## Reviewer's Guide

Synchronizes public GDScript docstrings with Godot 4 Native BBCode and hardens documentation tooling by extracting only declared function parameters—including static and variadic forms—while excluding nested lambda arguments; layer setup documentation now describes resource selection and generated sprite properties.

The layer setup docs also drop the undeclared `[param id]` entries and document the viewport's pixel units and sizing role. Reviewers should focus on keeping the two parsers aligned and on the docstrings' accuracy against the implementations.

### File-Level Changes

| Change                                                                                                                          | Details                                                                                                                                                                                                                                                                                                                                                                           | Files                                                                                     |
|---------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| Make GDScript function-parameter extraction AST-scoped and support static, typed, inferred, regular, and variadic declarations. | <ul><li>Inspect only the function header’s direct argument list to exclude lambda parameters from function bodies.</li><li>Handle static function AST wrappers and variadic argument nesting.</li><li>Keep documentation update and validation parsers aligned, with graceful failure for malformed or unsupported argument nodes.</li></ul>                                      | `.github/scripts/update_gdscript_docs.py`<br/>`.github/scripts/validate_gdscript_docs.py` |
| Clarify native BBCode documentation for generated bush and decor layer content.                                                 | <ul><li>Document clearing and repopulating layers from texture-preloader resources selected by ID prefixes.</li><li>Describe generated sprite placement, scale, texture, rotation, and flip behavior.</li><li>Remove the undeclared `[param id]` entries.</li><li>Document the viewport's pixel units and how `x` and `y` drive placement, layer height, and mirroring.</li></ul> | `scripts/core/main_scene.gd`                                                              |

### Assessment Against Linked Issues

No issues are linked to this PR. The parser fix was developed in #1014 and merged into this branch via #1015.

---

## PR #1009 Summary: Bots / AI Contributions

### Human contribution (@ikostan)

- Self-assigned the automation PR, applied labels (documentation, bug, enhancement, tools, CI/CD, refactoring, python), and added it to Milestone 25.
- Traced the invalid `[param id]` flagged by Sourcery back to the shared parser bug and fixed it in both scripts.
- Notable commits:
  - `Clarify parallax layer docs` (`4da79da`)
  - `fix(ci): stop lambda args leaking into GDScript param contracts` (`9bce46a`)
  - `Merge pull request #1015 from ikostan/fix/docs-lambda-param-leak` (`6191c85`)
  - `Merge branch 'automation/weekly-gdscript-docs'` (`3f6cf3a`)
- Requested the Sourcery Reviewer's Guide and title regeneration.
- Added milestone documentation.

### AI assistance

- **Claude (claude.ai):** co-authored `fix(ci): stop lambda args leaking into GDScript param contracts` (`9bce46a`) and drafted this milestone doc. All changes were reviewed and adapted by @ikostan.

### Bots / AI contributions

- **@github-actions**
  - Opened the PR from the scheduled docstring workflow on `automation/weekly-gdscript-docs`.
  - Produced the initial Native BBCode sync, `docs(gdscript): update and enhance Native BBCode docstrings` (`0ef3225`), including the bogus `[param id]` that exposed the parser bug.

- **@sourcery-ai**
  - Generated "Summary by Sourcery" (bug fixes, enhancements, documentation).
  - Produced the Reviewer's Guide with sequence and flow diagrams and the file-level changes table used above.
  - Posted two review comments: the undeclared `[param id]` and the missing viewport sizing contract. Both are resolved.
  - Regenerated the PR title from `docs(gdscript): Sync Native BBCode docstrings` to the current title.

- **@deepsource-io** (DeepSource / DeepSourceReview / deepsource-autofix)
  - Ran automated code review (`bfea3ce...6191c85`) and posted the PR Report Card: grade A across Security, Reliability, Complexity, and Hygiene; Python and JavaScript analyzers passed.
  - Authored `style: format code with Black and isort` (`9789750`) via autofix.

- **@coderabbitai**
  - Review skipped automatically because the PR was opened by a bot user; no review comments or commits.

- **@codecov**
  - No coverage report comment observed on this PR.

- **@dependabot**
  - No direct commits, dependency bumps, or review comments observed on this specific PR.

- **@github-copilot-cli** (GitHub Copilot)
  - No co-authored commits, reviews, or direct contributions observed on this specific PR.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
