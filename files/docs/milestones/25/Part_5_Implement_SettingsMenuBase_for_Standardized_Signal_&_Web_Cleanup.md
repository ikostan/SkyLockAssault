<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Implement SettingsMenuBase for Standardized Signal & Web Cleanup

---

## PR #996 Summary

**Title:** Implement SettingsMenuBase for Standardized Signal & Web Cleanup  
**Author:** @ikostan  
**Linked issue:** [#480 – [FEATURE] Implement SettingsMenuBase for Standardized Signal & Web Cleanup](https://github.com/ikostan/SkyLockAssault/issues/480)  
**Milestone:** Milestone 25: Resource Migration & Audio Decoupling  
**Labels:** enhancement, web, testing, refactoring, GUT, QA  

### Purpose

Introduce a reusable `SettingsMenuBase` that centralizes signal management, web-overlay updates, focus handling, menu-stack navigation, and teardown logic for settings sub-menus. Migrate Gameplay Settings onto the new base while preserving its public/test-facing interface.

### Key Changes

- **New base class** (`scripts/ui/menus/settings_menu_base.gd`)
  - `safe_connect` / `safe_disconnect` with tracked connections and safe teardown (handles already-freed emitters)
  - `update_web_overlays(visible_ids, hidden_ids)` – single eval, no-op off-web
  - `_go_back()` – intentional exit path (pop one menu, focus hook, overlay swap, `queue_free`)
  - `_teardown()` – idempotent, ordered cleanup (subclass `_cleanup` → disconnect signals → conditional stack restore → overlays)
  - Virtual hooks for menu name, overlay IDs, focus controls, restoration, and cleanup
- **Migration**
  - `gameplay_settings.gd` now extends `SettingsMenuBase` (≈ −173 lines)
  - Public/test-facing members preserved
  - `GamePaths.SETTINGS_MENU_BASE` added
  - `Globals.settings` data structures left untouched
- **Intentional behavior changes**
  1. Unexpected exit restores previous menu on all platforms (not just web)
  2. Teardown is idempotent
  3. Back is re-entrancy-guarded (duplicate presses pop only once)
  4. JS callbacks cleared in `_cleanup()` on tree exit (one frame later)
  5. Freed entries on `hidden_menus` no longer abort the exit path
- **Tests**
  - New `test/gut/test_settings_menu_base.gd` (SMB-01…14)
  - Updated `test_gameplay_settings_exit_paths.gd` (GS-EXIT-03/06 flipped, GS-EXIT-07 added)
- **Docs**
  - Milestone documentation under `files/docs/milestones/25/`

### Follow-ups (out of scope)

- Migrate `advanced_settings.gd` and `audio_settings.gd` onto the base

### Testing / Coverage

- Author reports 55 tests passing (temporary GUT stand-in; real GUT recommended before merge)
- Codecov: patch ≈ 56.5%, project ≈ 61.7%

### Review Notes

- @sourcery-ai – summary + Reviewer’s Guide (sequence/flow diagrams)
- @coderabbitai – summary, review comments, architecture notes
- @deepsource-io – automated review + PR Report Card
- @codecov – coverage report
- @github-copilot-cli – co-authored ownership fix for `safe_connect`

### Status

Implements #480. Ready for review once remaining comments (e.g. mixed freed/live stack edge case) and real GUT runs are addressed.

---

## Detailed PR description

### What

- **New `scripts/ui/menus/settings_menu_base.gd`** (`class_name SettingsMenuBase`, extends `Control`), shared by settings sub-menus:
  - `safe_connect(signal, callable)` connects once and tracks the connection. `safe_disconnect(signal, callable)` is safe when the emitter has already been freed (it checks `Signal.get_object()`) or when the connection is missing. Tracked connections are removed automatically on teardown.
  - `update_web_overlays(visible_ids, hidden_ids)` replaces the hand-written `js_bridge_wrapper.eval(...)` blocks. It does a single eval, emits exactly the same statement format as before, and does nothing off web or when both lists are empty.
  - `_go_back()` is the Back-button path. It sets `_intentional_exit`, pops one `Globals.hidden_menus` entry, calls the focus hook, swaps the overlays, then calls `queue_free()`.
  - `_teardown()`, reached via `tree_exited`, runs at most once. Order: subclass `_cleanup()`, then the tracked signal disconnects, then a stack restore (unexpected exit only), then the overlay swap.
  - `_grab_initial_focus()` goes through `Globals.ensure_initial_focus`.
  - Virtual hooks: `_get_menu_name`, `_get_overlay_ids`, `_get_previous_menu_overlay_ids` (defaults to the Options overlays), `_get_initial_focus_control`, `_get_focus_controls`, `_on_previous_menu_restored` (Back path only), `_cleanup`.
- **`gameplay_settings.gd` now extends `SettingsMenuBase`.** Net change is -173 lines. Its public and test-facing members are unchanged (`_on_tree_exited`, `_on_gameplay_back_button_pressed`, `_intentional_exit`, `js_window`, the `*_cb` refs, and so on).
- `GamePaths.SETTINGS_MENU_BASE` added.
- `Globals.settings` and its data structures are untouched (SMB-12 asserts this).

### Intentional behavior changes

1. **An unexpected exit off web now restores the previous menu.** Before, the stack restore sat inside the web-only branch. Audio, Advanced and `Globals._on_options_exited_unexpectedly()` already restore on every platform. GS-EXIT-03 is flipped.
2. **Teardown is idempotent.** Before, each unintentional `_on_tree_exited()` call popped another menu. GS-EXIT-06 is flipped.
3. **Back is re-entrancy guarded.** Two Back presses before the menu is freed (for example the Godot button and the DOM overlay in the same frame) now pop only once. New test: GS-EXIT-07.
4. **On the Back path, the JS `window.*` callbacks are now cleared in `_cleanup()` on tree exit**, one frame later than before. Before, they were cleared immediately in the Back handler. The guard from (3) makes a DOM click during that frame a no-op. This also keeps the callback refs alive while a JS-initiated Back is still running.
5. **A freed entry on `hidden_menus` no longer aborts the exit.** Popping straight into a typed `var prev_menu: Node` raised "Trying to assign invalid previously freed instance" and stopped the function, which I reproduced on 4.7.1. The base now pops into a `Variant` first. New test: SMB-09. `advanced_settings.gd` and `audio_settings.gd` still have this pattern until they migrate.

### Tests

- New `test/gut/test_settings_menu_base.gd` (SMB-01…12) tests the base class through a probe subclass.
- `test_gameplay_settings_exit_paths.gd`: GS-EXIT-03 and GS-EXIT-06 are flipped as their comments instructed, and GS-EXIT-07 is added.
- No other existing test needed changes.

### Follow-ups (out of scope)

- Migrate `advanced_settings.gd` and `audio_settings.gd` onto the base.

---

## Reviewer's Guide

Adds SettingsMenuBase to centralize settings-menu signals, overlays, focus, navigation, and teardown; migrates Gameplay Settings while preserving its interface; and adds focused regression tests for cleanup ordering, exit-path behavior, re-entrancy, stale menu entries, and data safety.

### File-Level Changes

| Change                                                                                                        | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Files                                                                                                 |
|---------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| Introduce a reusable base class for settings-menu lifecycle management.                                       | <ul><li>Track only signal connections created through safe_connect and disconnect them safely during teardown.</li><li>Centralize web overlay JavaScript generation, focus initialization, hidden-menu restoration, and Back handling.</li><li>Make teardown and Back actions idempotent, while skipping freed stack entries and preserving cleanup ordering.</li><li>Expose virtual hooks for menu-specific identity, overlays, focus, restoration, and cleanup.</li></ul> | `scripts/ui/menus/settings_menu_base.gd`<br/>`scripts/core/game_paths.gd`                             |
| Migrate Gameplay Settings to the shared lifecycle contract without changing its public/test-facing interface. | <ul><li>Extend SettingsMenuBase and delegate common setup, Back handling, focus, overlay, and exit cleanup to the base.</li><li>Replace local signal guards and teardown logic with safe_connect and _cleanup hooks.</li><li>Retain JavaScript callback registration while clearing callbacks during teardown.</li></ul>                                                                                                                                                    | `scripts/ui/menus/gameplay_settings.gd`                                                               |
| Add regression coverage for standardized lifecycle behavior and intentional exit changes.                     | <ul><li>Test signal ownership, freed emitters, cleanup ordering, idempotency, Back re-entrancy, stale stack entries, overlay output, focus hooks, and settings-resource preservation.</li><li>Update gameplay exit expectations for non-web restoration and one-time teardown.</li></ul>                                                                                                                                                                                    | `test/gut/test_settings_menu_base.gd`<br/>`test/gut/test_gameplay_settings_exit_paths.gd`             |
| Document the implementation and review considerations for the milestone.                                      | <ul><li>Record the new base-class contract, behavior changes, test scope, and follow-up migration work.</li></ul>                                                                                                                                                                                                                                                                                                                                                           | `files/docs/milestones/25/Part_5_Implement_SettingsMenuBase_for_Standardized_Signal_&_Web_Cleanup.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                             | Addressed | Explanation |
|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/480 | Create a reusable SettingsMenuBase extending Control that centralizes safe signal connection and disconnection, web overlay updates, hidden-menu stack navigation, focus management, and intentional versus unexpected exit handling. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/480 | Refactor gameplay_settings.gd to inherit from SettingsMenuBase while preserving its existing public/test-facing behavior and leaving Globals.settings data structures unchanged.                                                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/480 | Add regression tests for cleanup ordering and idempotency, _intentional_exit semantics, and hidden_menus behavior on both Back-button and unexpected tree-exit paths.                                                                 | ✅        |             |

### Possibly linked issues

- **#480**: PR directly fulfills issue #480 by introducing SettingsMenuBase, migrating gameplay settings, and testing both exit paths.
- **#480**: The PR directly implements issue #480’s requested lifecycle tests and teardown behavior, including callbacks, stack restoration, and web cleanup.

---

## PR #996 Summary: Bots / AI Contributions

**PR:** [Implement SettingsMenuBase for Standardized Signal & Web Cleanup](https://github.com/ikostan/SkyLockAssault/pull/996)  
**Title:** Implement SettingsMenuBase for Standardized Signal & Web Cleanup  
**Author / primary contributor:** @ikostan  
**Linked issue:** #480  

### Human contribution (@ikostan)

- Authored the core implementation of `SettingsMenuBase` (`scripts/ui/menus/settings_menu_base.gd`), migrated `gameplay_settings.gd` onto it (~173 lines removed), added `GamePaths.SETTINGS_MENU_BASE`, and wrote/updated GUT coverage (`test_settings_menu_base.gd`, exit-path tests).
- Commits primarily by @ikostan:
  - `I've implemented #480` (`98ec741`)
  - `Add SettingsMenuBase lifecycle cleanup` (`c3aa4f6`)
  - `Skip freed entries when restoring hidden menus` (`2bae2fd`)
- Co-authored one commit with Copilot (see below).
- Added the PR to Milestone 25, self-assigned, applied labels (enhancement, web, testing, refactoring, GUT, QA), and linked issue #480.

### Bots / AI contributions

- **@coderabbitai**  
  - Generated “Summary by CodeRabbit” (bug fixes + refactor overview).  
  - Performed code review with actionable comments (e.g., mixed freed/live stack restoration), walkthrough, architecture/merge-risk notes, and finishing-touches / autopilot support.

- **@sourcery-ai**  
  - Generated “Summary by Sourcery” (new features, bug fixes, enhancements, docs, tests).  
  - Produced Reviewer’s Guide with sequence + flow diagrams and file-level change analysis.  
  - Posted code reviews and suggestions.

- **@deepsource-io** (DeepSource / DeepSourceReview)  
  - Ran automated code review on the PR range.  
  - Posted PR Report Card (Security / Reliability / Complexity / Hygiene) and linked full analyzer results (Python & JavaScript).

- **@codecov**  
  - Posted coverage report: patch coverage ≈ 56.48% (47 missing lines); project coverage 61.74% (−2.05%); all tests successful. Highlighted coverage on `settings_menu_base.gd` and `gameplay_settings.gd`.

- **@github-copilot-cli** (GitHub Copilot)  
  - Co-authored the commit `Don't track pre-existing signal connections` (`4aa2ed8`)  
    (`Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`).  
  - Clarified `safe_connect` ownership so pre-existing connections are not tracked/owned by the base class, plus related docs and test.

- **@dependabot**  
  - No direct commits, dependency bumps, or review comments observed on this specific PR.

### Notes

All listed accounts are given in the standard GitHub-accepted forms (`@dependabot`, `@deepsource-io`, `@sourcery-ai`, `@codecov`, `@github-copilot-cli`, `@coderabbitai`) so they can be recognized in the repository’s contributors list where applicable. Human work is isolated under @ikostan.

---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
