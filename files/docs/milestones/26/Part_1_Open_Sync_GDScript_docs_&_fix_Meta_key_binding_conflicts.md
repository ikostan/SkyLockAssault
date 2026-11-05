<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# PR #1024: Sync GDScript docs and fix Meta key binding conflicts

**PR:** [ikostan/SkyLockAssault#1024](https://github.com/ikostan/SkyLockAssault/pull/1024)  
**Opened by:** github-actions[bot] (automated twice-weekly docs sync)  
**Human follow-up:** @ikostan  
**Type:** Documentation sync + docs-pipeline hardening + input-binding bugfix

> **Note:** this PR started as a docs-only automation PR but now also contains a **code change**
> (`events_match` in `scripts/core/settings.gd`). Review it as a behavior change, not docs only.

---

## Purpose

Synchronize the Settings public documentation to Godot 4 Native BBCode, fix the docs pipeline so it
stops producing inaccurate or low-quality docstrings, and fix Meta-key binding comparisons so
Meta-modified keys are distinct from the same key without Meta.

## Root cause of the docs problems

Review found two docstrings that contradicted the code (`apply_config_to_input_map` claimed to be
"pure" without side effects; `get_event_label` claimed PlayStation labels). Both claims were stale
comments already on `main`. The generator sent Gemini only the **first 15 lines** of each function,
so it never saw the code that disproved them and kept the old wording (and in one case broadened it).
The prompt also told it to preserve existing comments unconditionally.

Other generator defects visible in the diff: duplicated `Returns Returns`, `Returns No return value.`
on `void` functions, and placeholder parameter descriptions (`The x parameter.`), which the generator
itself back-filled when the model omitted a parameter.

## Key changes

### Documentation (`scripts/core/settings.gd`)

- Converted Settings public member docs to Native BBCode (`##`).
- Corrected the two inaccurate docstrings: `apply_config_to_input_map` now documents its InputMap
  side effects; `get_event_label` states that joypad labels are Xbox-style for every controller.
- `get_conflicting_actions` now states that only `ACTIONS` is checked, and why.
- [ ] Remaining generator artefacts fixed (`Returns Returns` in `get_event_device_type` and
  `needs_save`, `Returns` on void `save_input_mappings`, 13 placeholder `[param]` descriptions).
  *If not fixed in this PR, the next docs sync regenerates them automatically.*

### Docs pipeline (`.github/scripts/update_gdscript_docs.py`, `validate_gdscript_docs.py`)

- **Full context:** the model now receives the whole function body (capped at 200 lines) and the
  declared return type.
- **Prompt rules:** code is the source of truth over stale comments; never broaden claims; `void`
  functions get no return text; return text must not start with "Returns"; no filler parameter text.
- **Formatter guard:** strips a duplicated leading "Returns" and never writes a Returns line for `void`.
- **Validator rules:** rejects `Returns Returns`, Returns lines on `void` functions, and placeholder
  parameter descriptions.
- **Self-healing classifier:** existing docstrings with those defects are marked `NON_COMPLIANT` and
  regenerated instead of failing the validator.
- **Retry instead of filler:** missing or placeholder parameter descriptions from the model trigger a
  retry (up to 3 attempts, 35 s then 70 s backoff); after that the run fails closed with the reason.
- DeepSource formatted both scripts with Black/isort (`daf5918`).

### Meta key binding fix (`scripts/core/settings.gd`)

- `events_match` now compares `meta_pressed`, matching `serialize_event`, `deserialize_event` and
  `get_event_label`, which already handled Meta.
- **User-visible impact:** previously Meta+Q and Q counted as the same binding (Cmd+Q vs Q on macOS).
  The remap UI reported a false conflict, and on load `apply_config_to_input_map` silently unbound
  the other action.

### Regression tests (`test/gut/test_events_match_meta.gd`)

- Meta+key and the plain key do not match (fails without the fix).
- Meta+key still matches itself.
- `get_conflicting_actions` does not report Meta+Q as conflicting with Q (fails without the fix).
- Meta survives a serialize/deserialize round trip.
- Each test restores the global InputMap afterwards.

## Review decisions

| Finding (Sourcery) | Decision | Reason |
|---|---|---|
| `apply_config_to_input_map` has global side effects | Fixed (docstring) | The "pure" claim was stale; the function intentionally writes to InputMap. It only avoids file I/O and `_needs_save`. |
| `events_match` ignores Meta | Fixed (code + test) | Real bug, present on `main` before this PR. |
| `get_conflicting_actions` checks only `ACTIONS` | **Won't fix (by design)**, docstring clarified | Checking all InputMap actions would include Godot built-ins (`ui_select`, `ui_cancel`, `ui_text_*`) that share common keys: false conflicts, and on load those built-ins would be unbound, breaking UI navigation. |
| PlayStation buttons get Xbox labels | Docstring fixed; brand detection **deferred** | Brand-specific labels are a feature, not a docs fix. Default bindings use `device = -1` (any controller), so a label can't always be tied to one brand. Follow-up: #___ |

## Verification

- [ ] `tests/ci/test_docstrings_workflow.py` passes on the final branch (re-run after `daf5918`).
- [ ] `validate_gdscript_docs.py scripts/core/settings.gd` passes on the final branch.
- [ ] gdlint and gdformat pass.
- [ ] GUT suite passes, including `test_events_match_meta.gd` (tests 1 and 3 fail without the fix).

## After merge

- The audit reports about 70 actionable slots across 23 files (21 missing, 49 non-compliant, mostly old
  placeholder parameters now caught by the new rule). That is under the 100-slot limit.
- The generator fixes one file per run; at twice a week that takes about 3 months. Trigger the
  workflow manually to clear it faster (overlapping runs queue, they don't collide).
- A run where the model keeps omitting a parameter now fails closed after 3 attempts instead of
  writing filler.

## Known limitations / follow-ups

- The docs validator runs only in the docs workflow, not in regular PR CI.
- The validator rejects paths outside `scripts/`, so test files are never checked.
- `has_doc_quality_defects` (generator) and `check_function_doc_quality` (validator) duplicate the
  same rules and must be kept in sync; a shared module would remove the drift risk.
- PlayStation / brand-specific joypad labels: #___

## Reviewer's Guide (Sourcery)

This PR synchronizes Settings documentation to Godot Native BBCode, strengthens generation and validation against stale or low-quality model output, and fixes input-binding equality so Meta-modified keys no longer collide with plain keys, with focused regression tests and global InputMap cleanup.

### File-Level Changes

| Change | Details | Files |
|---|---|---|
| Harden the automated GDScript documentation generation and validation pipeline. | <ul><li>Provide generators with complete function-body context and declared return types.</li><li>Reject duplicated return text, return docs on void functions, and placeholder parameter descriptions.</li><li>Retry incomplete model-generated parameters instead of injecting filler text.</li><li>Preserve the non-comment source integrity allowlist while synchronizing docs.</li></ul> | `.github/scripts/update_gdscript_docs.py`<br/>`.github/scripts/validate_gdscript_docs.py` |
| Synchronize Settings public documentation with Godot 4 Native BBCode and correct several behavioral descriptions. | <ul><li>Convert legacy parameter/type/return annotations to Native BBCode tags.</li><li>Document event matching, conflict scope, serialization, persistence, and InputMap side effects.</li><li>Clarify return behavior and remove stale or duplicated claims.</li></ul> | `scripts/core/settings.gd` |
| Make Meta-modified key bindings distinct from otherwise identical key bindings. | <ul><li>Include meta_pressed in InputEventKey equality checks used by matching and conflict detection.</li><li>Add regression coverage for Meta/plain key matching, conflict handling, state restoration, and serialization round trips.</li></ul> | `scripts/core/settings.gd`<br/>`test/gut/test_events_match_meta.gd`<br/>`test/gut/test_events_match_meta.gd.uid` |
| Record the implementation and review context for the documentation and input-binding work. | <ul><li>Add a milestone note summarizing documentation synchronization, pipeline hardening, Meta-key behavior, and test coverage.</li></ul> | `files/docs/milestones/26/Part_1_Sync_GDScript_docs_and_fix_Meta_key_binding_conflicts.md` |

---

## Contributors

### Human contribution (@ikostan)

- Authored follow-up work on top of the automated docs sync: fixed Meta-key handling in input-binding comparisons, improved GDScript documentation quality checks, and merged main into the branch.
- Notable commits by @ikostan:
  - `d30ddaa` Match Meta in input event comparisons
  - `9eeb16e` Improve GDScript documentation quality checks
  - `843c049` Merge pull request #1026 from ikostan/main
- Triaged the review comments (fixed two, declined two by design) and drove the Meta-key and docs-pipeline hardening beyond the initial automation PR.

### Bots / AI contributions

- **github-actions[bot]**
  - Opened the PR as the automated twice-weekly GDScript documentation sync.
  - Committed the initial docs update `docs(gdscript): update and enhance Native BBCode docstrings` (`e141be0`).

- **Gemini** (`gemini-3.5-flash-lite`, inside the docs pipeline)
  - Generated the docstrings in `e141be0`. Its output contained the defects found in review (stale "pure" claim, broadened "Xbox and PlayStation" claim, `Returns Returns`, placeholder parameters).

- **@claude (Opus 5.5)**
  - Analyzed the Sourcery review findings and separated docstring issues, by-design behavior, and real code bugs.
  - Identified the root cause of the inaccurate docstrings in the generation pipeline.
  - Proposed fixes for the Settings docstrings, the Meta-key comparison, the regression tests, and the docs generator and validator.
  - Verified the changes with gdlint, gdformat, the docs contract validator, and the CI workflow tests.

- **@sourcery-ai**
  - Generated "Summary by Sourcery" (bug fixes, enhancements, documentation, tests).
  - Produced the Reviewer's Guide with sequence diagrams and file-level change analysis.
  - Posted code reviews with four actionable comments: docs purity claim, conflict scope, PlayStation labels, and Meta matching; plus title and guide updates.

- **@coderabbitai**
  - Participated with review/autofix messaging, help/commands, and finishing-touches support on the PR.

- **@deepsource-io** (DeepSource / DeepSourceReview / deepsource-autofix)
  - Ran automated code review and posted the PR Report Card (Security / Reliability / Complexity / Hygiene) with analyzer links.
  - Authored the style fix commit `style: format code with Black and isort` (`daf5918`) on the pipeline scripts.

- **@dependabot, @codecov, @github-copilot-cli**
  - No direct contributions observed on this PR. Docs generation uses Gemini in the pipeline, which is separate from GitHub Copilot.

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->