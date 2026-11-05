<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Fix Gemini parameter docs schema and retries

---

## PR #1057 Summary

**Title:** Fix Gemini parameter docs schema and retries  
**PR:** [#1057](https://github.com/ikostan/SkyLockAssault/pull/1057)  
**Branch:** `bug-gdscript-docs-sync-fails-gemini-cant-fill-dict-typed-parameters-in-response-schema` → `main`  
**Author:** @ikostan  
**Closes:** [#1055 – [BUG] GDScript docs sync fails: Gemini can't fill Dict-typed "parameters" in response schema](https://github.com/ikostan/SkyLockAssault/issues/1055)  
**Follow-up to:** [#1024 – Sync GDScript docs and fix Meta key binding conflicts](https://github.com/ikostan/SkyLockAssault/pull/1024) (introduced the check that exposed the bug)  
**Milestone:** Milestone 26: Comprehensive Architectural Review & Performance Benchmarking  
**Labels:** bug, setup, tools, CI/CD, github actions, github_actions, python  

### Purpose

Get the twice-weekly GDScript documentation sync working again. Every run since Oct 14 failed in `Generate & Inject GDScript Docstrings` on `scripts/core/globals.gd` (`ensure_initial_focus`, 3 parameters) and never reached the PR step. The last good run was Oct 11.

`MemberDoc.parameters` was typed `Optional[Dict[str, str]]` and passed to Gemini as `response_schema`. Gemini's structured output cannot express a map with arbitrary keys, so the model received an object with no properties and had nowhere valid to put parameter descriptions. It either left `parameters` empty or emitted each parameter as a separate member with an empty `summary`.

The dict schema never worked. Before `9eeb16e` (#1024) the generator back-filled the gap with "The X parameter."; #1024 turned that into a retry, which exposed the bug. The retry also resent the identical prompt at `temperature=0.0` without saying what was wrong, so it could not recover.

Synchronizes core GDScript public docstrings with specific Godot 4 Native BBCode while upgrading the documentation updater to process quota-safe ordered batches with fail-closed atomic writes; CI installs and validates the shared generator dependencies, with comprehensive regression coverage.

### Key Changes

- **Response schema** (`.github/scripts/update_gdscript_docs.py`)
  - New `ParamDoc` model (`name`, `description`): identifier check on the name; the description goes through the same Markdown, Doxygen and BBCode validation as the rest of the docstring and must be one non-empty line
  - `MemberDoc.parameters` is now a **required** `List[ParamDoc]`:
    - a list, because Gemini supports a list of typed objects but not a free-form map
    - not `Optional`, because `google-genai` 0.8.0 drops the item schema of a nullable array (Gemini would again not know the entry shape)
    - no default, because the converted schema would otherwise mark the field optional and Gemini could skip it (Sourcery finding)
  - An explicit `null` from the model is coerced to `[]`; a missing key fails validation and is retried
  - Duplicate parameter names are rejected; new `param_map` property gives `{name: description}` to the existing call sites (`find_incomplete_parameters`, `format_doc_lines`, the post-loop checks)
- **Retry loop** (same file)
  - New `find_response_problems()` collects every fixable problem in a schema-valid response: missing requested members, missing or placeholder parameter descriptions, and parameters the signature does not declare (any parameter on a constant, export or enum). New helper `find_unexpected_parameters()`
  - Rejected responses (pydantic validation errors and the problems above) are retried after 5 s with the rejection reason appended to the prompt, capped at 2000 characters. Each retry carries only the latest reason
  - API errors (429, 503, …) keep the exponential backoff (35 s, 70 s) and add no feedback
  - After 3 failed attempts the run still fails closed. The old checks after the loop stay as a fail-closed guard
  - Prompt rules 3 and 6 now describe `parameters` as a list of `{name, description}` entries, empty when the declaration has no parameters
- **Shared dependency pins**
  - New `.github/scripts/requirements-docs.txt`: `google-genai==0.8.0`, `pydantic==2.10.6`, `gdtoolkit==4.5.0`
  - `bi_weekly_gd_docstrings.yml` installs it and keys the pip cache on it (`cache-dependency-path`)
  - `test_ci_scripts.yml` installs it, so `tests/ci/` can import the generator (it exits at import time without these packages)
- **Tests** (`tests/ci/test_update_gdscript_docs.py`, new; 108 cases)
  - Schema: pydantic schema and the schema `google-genai` actually sends (`_transformers.t_schema`) both describe `parameters` as a required array of `{name, description}`; no free-form maps anywhere
  - `ParamDoc` / `MemberDoc` validation: identifiers, descriptions, wrong types, legacy dict shape, null vs missing key, duplicates, case-distinct names
  - `find_incomplete_parameters`, `find_unexpected_parameters`, `find_response_problems`, including signals and ignored extra members
  - `format_doc_lines`: declaration order, 95-column wrapping, signals, no `Returns` on `void`, no empty parameter section
  - `query_gemini_for_docs` with a mocked client: the Oct 18 failure shape, malformed JSON, feedback replaced and length-bounded, separate feedback and backoff, per-chunk scoping and backoff reset, fail-closed after 3 attempts
  - Round trip through `prepare_file_change`: injected docs classify as `COMPLIANT` and the non-doc SHA-256 is unchanged
  - Pins: exact versions, no duplicate package, both workflows install the file on an active (non-comment) line, pip cache keyed on it

### Design Decisions

- **List instead of dict, rather than upgrading `google-genai`.** Newer releases accept full JSON Schema (which supports maps), but that means jumping far past the pinned 0.8.0. The list fix is smaller and works on the current pin.
- **Required, non-nullable field, lenient on `null`.** Required and non-`Optional` is what makes Gemini see the full entry shape and the field as mandatory. Coercing `null` to `[]` keeps parameterless members valid without a retry.
- **Feed problems back instead of aborting.** Every mistake Gemini can correct (wrong shape, missing or filler descriptions, extra parameters, missing member) goes back into the next prompt. Only exhausted retries fail the run.
- **Short delay for rejected responses.** The 35 s / 70 s backoff exists for quota errors; a rejected response retries after 5 s.
- **One pins file for both workflows.** The test workflow needs the same packages as the generator; a single file prevents drift.

### Compatibility

- CI scripts, workflows and CI tests only; no gameplay, scene or runtime change
- The generated docstring format (`## [param name]: …`) is unchanged, so `validate_gdscript_docs.py` needs no change
- `test_ci_scripts.yml` installs three more packages for the CI test job

### Testing

- `tests/ci/test_update_gdscript_docs.py`: 108 passed; also 108 passed in three random-order runs
- Against the script at the first PR head (`6f2bfc0`), 20 of the final tests fail (required `parameters`, retried response problems); against the original `main` script, the first version of the suite failed 30 of 39
- Mutation checks: commenting out the workflow install or adding a duplicate pin fails the matching test
- Existing `tests/ci/test_docstrings_workflow.py` passes on the branch
- `update_gdscript_docs.py --audit` still runs: 36 files, 127 public members, 82 actionable slots in 24 files
- black, isort and pyflakes clean on the new test file
- CI on the first head (`19fa4fb`): CI/CD Infrastructure Tests (including the new suite), Markdown Lint and YAML Lint passed; GUT, GDUnit4, browser tests and gdlint skipped by the path filter (no `.gd` changes)
- [ ] CI green on the final head
- [ ] Real run: `workflow_dispatch` of the docs sync; `ensure_initial_focus` gets `[param candidate]`, `[param allowed_controls]` and `[param context]`; the automation PR passes the docs validator, gdlint and gdformat

---

## Reviewer's Guide

Replaces the Dict-typed `parameters` field in the Gemini response schema with a required list of validated `{name, description}` entries, so Gemini can fill parameter docs. Turns every fixable response problem into retry feedback with a short delay while keeping exponential backoff for API errors. Shares the documentation dependency pins between the docs and CI-test workflows, and adds a regression suite for the schema, validation, formatting, retry loop and pins.

### File-Level Changes

| Change                                                                                                           | Details                                                                                                                                                                                                                                                                                                                                | Files                                                                                                                                   |
|------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| Make parameter docs fillable by Gemini.                                                                          | <ul><li>Add <code>ParamDoc</code> and make <code>MemberDoc.parameters</code> a required <code>List[ParamDoc]</code>.</li><li>Coerce explicit <code>null</code> to <code>[]</code>; reject duplicates; add <code>param_map</code>.</li><li>Update the call sites and prompt rules 3 and 6.</li></ul>                                    | `.github/scripts/update_gdscript_docs.py`                                                                                               |
| Retry rejected responses with feedback.                                                                          | <ul><li>Add <code>find_unexpected_parameters</code> and <code>find_response_problems</code> and run them inside the retry loop.</li><li>Append the latest rejection reason (max 2000 chars) to the next prompt; 5 s delay.</li><li>Keep 35 s / 70 s backoff, without feedback, for API errors; fail closed after 3 attempts.</li></ul> | `.github/scripts/update_gdscript_docs.py`                                                                                               |
| Share the documentation dependency pins.                                                                         | <ul><li>Add <code>requirements-docs.txt</code>.</li><li>Install it in both workflows; key the docs workflow's pip cache on it.</li></ul>                                                                                                                                                                                               | `.github/scripts/requirements-docs.txt`<br/>`.github/workflows/bi_weekly_gd_docstrings.yml`<br/>`.github/workflows/test_ci_scripts.yml` |
| Add regression coverage.                                                                                         | <ul><li>Schema (pydantic and <code>google-genai</code>-converted), model validation, response checks, formatting, mocked retry loop, round-trip injection, dependency pins.</li></ul>                                                                                                                                                  | `tests/ci/test_update_gdscript_docs.py`                                                                                                 |
| Record the implementation and review context.                                                                    | <ul><li>Add the milestone note for this part.</li></ul>                                                                                                                                                                                                                                                                                | `files/docs/milestones/26/Part_6_Fix_Gemini_parameter_docs_schema_and_retries.md`                                                       |
| Make documentation writes quota-aware, ordered, and fail-closed across bounded multi-file batches.               | <ul><li>Increase per-run limits to five files and 30 documentation slots while pacing Gemini requests.</li><li>Select a contiguous queue prefix without skipping oversized files.</li><li>Prepare every file before atomically committing the batch, leaving the working tree untouched on preparation failure.</li></ul>              | `.github/scripts/update_gdscript_docs.py`<br/>`tests/ci/test_update_gdscript_docs.py`                                                   |
| Replace generic GDScript API documentation with specific Godot 4 Native BBCode descriptions.                     | <ul><li>Clarify parameter meanings for focus, menu, logging, scene, version, encryption, and configuration helpers.</li><li>Document configuration return structure and encryption error/fallback behavior.</li><li>Normalize formatting and remove redundant generic return text.</li></ul>                                           | `scripts/core/globals.gd`                                                                                                               |
| Ensure CI environments install the shared documentation-generator dependencies wherever documentation tests run. | <ul><li>Install documentation requirements in the browser CI and include them in the pip cache key.</li><li>Add validation that all workflows running CI documentation tests reference the shared requirements file.</li></ul>                                                                                                         | `.github/workflows/browser_test.yml`<br/>`tests/ci/test_update_gdscript_docs.py`                                                        |
| Add regression coverage for batching, quota limits, atomicity, ordering, and CI dependency configuration.        | <ul><li>Test file and slot caps, oversized-first-file handling, defaults, empty queues, and quota-safe pacing.</li><li>Test ordered multi-file preparation and prevention of commits after a later-file failure.</li><li>Validate workflow dependency installation and exact documentation dependency pins.</li></ul>                  | `tests/ci/test_update_gdscript_docs.py`                                                                                                 |

### Assessment against linked issues

| Issue                                                   | Objective                                                                        | Addressed | Explanation                                                                                                 |
|---------------------------------------------------------|----------------------------------------------------------------------------------|-----------|-------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1055> | Gemini returns a description for every required parameter.                       | ✅        | The schema now has a required list of `{name, description}` entries; confirm with a real run (see Testing). |
| <https://github.com/ikostan/SkyLockAssault/issues/1055> | Retries can fix a rejected response.                                             | ✅        | The rejection reason is fed back; tested with the Oct 18 failure shape.                                     |
| <https://github.com/ikostan/SkyLockAssault/issues/1055> | `update_gdscript_docs.py` is covered by tests that run in `test_ci_scripts.yml`. | ✅        | 108 cases; the CI test job installs the docs dependencies.                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1055> | Docs dependency pins live in one file used by both workflows.                    | ✅        | `requirements-docs.txt`; guarded by tests.                                                                  |
| <https://github.com/ikostan/SkyLockAssault/issues/1055> | The scheduled docs sync completes green and opens or updates the automation PR.  | ⏳        | Pending the first real run after merge.                                                                     |

---

## Contribution Summary

### Human contribution (@ikostan)

- **Investigation and scope**
  - Spotted that the docs sync had stopped working, supplied the failing run log, and filed #1055 with the root cause, fix plan, tests and acceptance criteria, in Milestone 26.
- **Implementation and integration**
  - Opened the dedicated branch and PR, applied the generator, workflow, pins and test changes, and committed every iteration.
  - Extended the test suite with further validation, retry and backoff cases and accepted CodeRabbit's generated tests.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Traced the failing runs to the Dict-typed response schema and to `9eeb16e` (#1024), which turned the old placeholder back-fill into a hard failure.
  - Found that `google-genai` 0.8.0 drops the item schema of an `Optional` list, and switched `parameters` to a required list.
  - Verified the Sourcery findings against the converted schema and drafted the fixes (required `parameters`, retried response problems, test hardening) and the fix for the DeepSource finding.

- **Gemini** (`gemini-3.5-flash-lite`, inside the docs pipeline)
  - Produced the failing responses in the Oct 14 and Oct 18 runs: empty `parameters`, then each parameter as a separate empty-summary member.

- **@sourcery-ai**
  - Ran the review (passed).
  - Posted four Medium findings, all valid and fixed: omitted `parameters` accepted as empty, unexpected parameters aborting instead of retrying, a commented-out install passing the workflow test, and conflicting pins passing the pins test.

- **@coderabbitai**
  - Authored `acc2e12` (`Expand GDScript documentation tests for parameter validation, retry feedback, and backoff behavior`).

- **@deepsource-io** (DeepSource / deepsource-autofix)
  - Authored `19fa4fb` (`style: format code with Black and isort`).
  - Posted one Critical (bug risk) finding: mutable default argument `FOCUS_PARAMS` in `param_entries`. Not reachable (the helper never mutates it), fixed anyway with a `None` default.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
