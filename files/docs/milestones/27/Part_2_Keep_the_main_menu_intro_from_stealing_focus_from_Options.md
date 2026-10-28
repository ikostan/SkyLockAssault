<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Keep the main-menu intro from stealing keyboard/gamepad focus from Options

---

## PR #1082 Summary

**Title:** Keep the main-menu intro from stealing focus from Options  
**PR:** [#1082](https://github.com/ikostan/SkyLockAssault/pull/1082)  
**Branch:** `fix/main-menu-intro-focus` → `main`  
**Author:** @ikostan (commit authored by Claude)  
**Closes:** #1083

- [#1083 – [BUG] Main-menu intro steals keyboard/gamepad focus from Options when Options is opened before the intro finishes](https://github.com/ikostan/SkyLockAssault/issues/1083)

**Follows:** [#1081](https://github.com/ikostan/SkyLockAssault/pull/1081) (Part 1), where the bug was found while root-causing a CI-only gdUnit4 failure  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** bug, menu  

### Purpose

The main menu's intro waits `intro_delay` (3 s), fades in over `fade_duration` (1 s), then calls `Globals.ensure_initial_focus(start_button, …)`. If the player opens **Options** during those ~4 s, Options focuses its first button, but the intro still runs to the end. Focus is then on none of the main-menu buttons, so `ensure_initial_focus()` moves it to the main menu's `StartButton`, which is hidden behind Options. Arrow keys and the gamepad stop working in Options until the player uses the mouse.

During the first 3 s the menu is fully transparent (`modulate.a = 0`) but still `visible`, so its buttons can be clicked before they can be seen.

Found while root-causing the CI-only `test_options_menu_navigation_sfx` failure on #1081: a main menu leaked by `test_loading_screen.gd` stole focus from a later suite the same way, about 4 s after it loaded.

### Key Changes

- **Intro focus guard** (`scripts/ui/menus/main_menu.gd`)
  - In `_run_fade_in_sequence()`, a third guard after the fade: if `start_button` is no longer visible in the tree (another menu has hidden the main menu), log and return instead of calling `ensure_initial_focus()`
  - GUARD 1 and 2 (menu freed during the delay or the fade) are unchanged
- **Tests** (`test/gdunit4/test_main_menu_intro_focus.gd`, new)
  - `test_intro_does_not_steal_focus_from_options`: opens Options through `Globals.load_options()` during a shortened intro (0.1 s + 0.1 s); after the intro ends, focus is still the Options control and visible
  - `test_intro_focuses_start_button_when_visible`: with nothing opened over it, the intro still focuses `StartButton`
  - `after_test()` frees the Options instance and restores `Globals.hidden_menus` and `Globals.options_open`
- **Generated edge-case tests** (`test/gdunit4/test_main_menu_intro_visibility.gd`, new, CodeRabbit `8fa1b4b`)
  - Runs the real `_run_fade_in_sequence()` through a subclass (`IntroMenu`) with only the nodes `main_menu.gd` binds, so no dialogs, audio or video are set up
  - 11 cases: hiding any ancestor (the root, `Panel`, `VBoxContainer`) or `StartButton` itself keeps an outside button focused; hiding during the fade is still caught; a hidden menu leaves focus unassigned when nothing was focused; a menu shown again before the intro ends still focuses Start; a player's own selection (Options or Quit) inside the visible menu is kept; zero-length intros respect visibility
  - `.uid` files for both new suites (`88fe3c7`, `8fa1b4b`)

### Design Decisions

- **Guard on visibility, not on `Globals.options_open`.** `is_visible_in_tree()` covers every menu that hides the main panel (Options, Key Mapping via `load_key_mapping()`), not only Options, and needs no new state.
- **Skip the grab rather than re-target it.** The menu that hid the main panel already chose its own focus; the main menu has nothing to add. When the player returns, the existing return paths restore focus as before.
- **Decline the dialog guard (CodeRabbit).** Its suggestion to also skip the intro focus while `QuitDialog` or the unbound dialog is open guards against something that cannot happen: those dialogs are embedded windows with their own focus, so `ensure_initial_focus()` (root viewport) cannot take focus from them. Checked with both real ways to press Quit during the intro; CodeRabbit withdrew the finding.
- **Shortened intro in tests.** `intro_delay` and `fade_duration` are exported, so the tests set them to 0.1 s instead of waiting 4 s per test.

### Expected Behavior

| Action                                      | Before                                                   | After                             |
|---------------------------------------------|----------------------------------------------------------|-----------------------------------|
| Options opened during the intro, intro ends | Focus moves to the hidden `StartButton`; keys do nothing | **Focus stays in Options**        |
| Main menu left alone until the intro ends   | `StartButton` focused                                    | `StartButton` focused (unchanged) |
| Options opened after the intro ended        | Options focused                                          | Options focused (unchanged)       |

### Compatibility

- No scene, API, signal or save-format change.
- Only behavior change: the intro no longer focuses `StartButton` while the main menu is hidden.

### Testing

- Reproduced on `main` with the real button and real timings: pressing `OptionsButton` 1 s into the intro, focus was on `AdvancedSettingsButton` (visible); after the intro ended it was on `StartButton` (`is_visible_in_tree() == false`)
- `test_intro_does_not_steal_focus_from_options` fails without the guard and passes with it
- Full gdUnit4 suite (v6.2.0, Godot 4.7.1, `xvfb-run`, coverage plugin stripped, as in CI): **144/144** at `7e2e4c8`; **155/155** at PR head `8fa1b4b` (with CodeRabbit's 11 cases)
- `test_main_menu_intro_visibility.gd`: 11/11 on the PR head; with the guard removed, its first case (`test_hidden_control_keeps_external_focus`, root hidden) fails
- CodeRabbit's dialog finding, checked on the PR head with a shortened intro and Quit pressed during it:
  - Mouse click: `QuitButton` keeps root focus (in the allowed list), so the intro skips the grab; the dialog keeps focus on its own button
  - Web/JS callback (nothing focused): root focus moves to `StartButton` behind the dialog, but the dialog keeps its own focus; Escape still closes it, and focus returns to `QuitButton`
- `gdlint` and `gdformat --check` clean on `main_menu.gd`
- CI on `7e2e4c8`: GUT, gdUnit4, GDScript lint/format and all browser shards green
- [ ] CI on `8fa1b4b`: GUT, gdUnit4, GDScript lint/format and Markdown lint green; one browser shard (Core Web Flows) still running at the time of writing
- [ ] In a running build: launch, click where Options is within ~4 s of the main menu appearing, wait, then use the arrow keys in Options

### Known limitations / follow-ups

- **Suspected second case, not a bug.** The "Unbound Controls" dialog's "Open Key Mapping" path looked like the same bug: its `visibility_changed` handler focuses `StartButton` after the main menu is hidden. A first probe reproduced it, but only because it emitted `confirmed` while the dialog was still visible. With a real OK press, the dialog hides first, so its focus request is queued before Key Mapping's and Key Mapping keeps focus. The fix was dropped before it was pushed, and no issue was filed.
- **PR description** has no `Closes #1083` line yet; the issue is linked in the sidebar.

---

## Reviewer's Guide

Prevents the main-menu intro from stealing keyboard/gamepad focus from a menu opened over it, by skipping the intro's final focus assignment when the Start button is no longer visible in the scene tree. Normal intro focus is unchanged, and new gdUnit4 tests cover both the overlay and the normal case.

### File-Level Changes

| Change                                                   | Details                                                                                                                                                                                                                                  | Files                                                                                          |
|----------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------|
| Skip the intro focus when the main menu has been hidden. | <ul><li>Check <code>start_button.is_visible_in_tree()</code> after the fade.</li><li>Log and return before <code>ensure_initial_focus()</code>.</li><li>GUARD 1 and 2 unchanged.</li></ul>                                               | `scripts/ui/menus/main_menu.gd`                                                                |
| Cover visibility and focus edge cases (generated).       | <ul><li>Any hidden ancestor or <code>StartButton</code> keeps an outside button focused.</li><li>Hidden during the fade, nothing focused, shown again before the end.</li><li>Player's own selection kept; zero-length intros.</li></ul> | `test/gdunit4/test_main_menu_intro_visibility.gd`<br/>`test/gdunit4/*.gd.uid`                  |
| Pin the overlay and normal focus behavior.               | <ul><li>Options opened during a shortened intro keeps focus.</li><li>Intro still focuses <code>StartButton</code> when visible.</li><li>Clean up Options state between tests.</li></ul>                                                  | `test/gdunit4/test_main_menu_intro_focus.gd`                                                   |
| Record the implementation and review context.            | <ul><li>Add the milestone note for this part.</li></ul>                                                                                                                                                                                  | `files/docs/milestones/27/Part_2_Keep_the_main_menu_intro_from_stealing_focus_from_Options.md` |

### Assessment against linked issues

| Issue                                                   | Objective                                                                                  | Addressed | Explanation                                                              |
|---------------------------------------------------------|--------------------------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1083> | The intro does not move focus to `StartButton` when another menu has hidden the main menu. | ✅        | `test_intro_does_not_steal_focus_from_options`; fails without the guard. |
| <https://github.com/ikostan/SkyLockAssault/issues/1083> | The intro still focuses `StartButton` when the main menu is visible.                       | ✅        | `test_intro_focuses_start_button_when_visible`.                          |

---

## Review decisions

| Finding                                                                          | Severity | Decision                       | Reason                                                                                                                                                                                                    |
|----------------------------------------------------------------------------------|----------|--------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| CodeRabbit: do not replace focus while a dialog is open (`main_menu.gd:140–148`) | Minor    | **Declined** (bot withdrew it) | Dialogs are embedded windows with their own focus; the intro's grab only touches the root viewport. Checked with mouse and web/JS Quit presses: the dialog keeps focus and Escape works. Thread resolved. |
| CodeRabbit generated tests: 11 visibility and focus edge cases (`8fa1b4b`)       | –        | **Kept**                       | All pass on the PR head and the first case fails without the guard; they cover ancestors, mid-fade hiding and zero-length intros that the hand-written tests do not.                                      |
| Sourcery: no review on the first push                                            | –        | –                              | The 7-day review budget was used up; the Reviewer's Guide was regenerated on request.                                                                                                                     |

---

## Contribution Summary

### Human contribution (@ikostan)

- **Planning and scope**
  - Asked for a small, real fix to put through its own PR, approved pushing it, and chose to keep it separate from #1081.
- **Implementation and integration**
  - Filed #1083, linked it to the PR, set the labels and milestone, and tried to reproduce the suspected Key Mapping case by hand, which exposed that it was not a real bug.
  - Requested the Sourcery guide and CodeRabbit unit-test generation, relayed CodeRabbit's dialog finding, and declined it on the thread.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Found the bug while tracing the CI-only gdUnit4 failure on #1081, reproduced it on `main` with the real Options button and real intro timings, and wrote the guard and both tests (the regression test fails without the guard).
  - Pushed the branch and opened the PR; the commit is authored by Claude.
  - Investigated a suspected second case (Unbound Controls → Key Mapping) and wrongly reported it as a bug; after the user could not reproduce it, re-checked with a real OK press, confirmed it was a test artifact, and dropped the unpushed fix.
  - Checked CodeRabbit's dialog finding against both real ways to press Quit during the intro, showed the dialog keeps its own focus, and drafted the reply that declined it.
  - Reviewed CodeRabbit's generated suite (11/11 on the PR head, first case fails without the guard) and re-ran the full gdUnit4 suite (155/155).
  - Drafted the #1083 issue text and this note.

- **@sourcery-ai**
  - Generated the PR summary and the Reviewer's Guide with a sequence diagram; the linked-issue assessment marked both #1083 objectives ✅.
  - No review on the first push: the 7-day review budget was used up. The guide was regenerated on request.

- **@coderabbitai**
  - First run hit the free OSS review limit; a later review posted 1 actionable comment (dialog focus, Minor), which it withdrew after the reply ("I conflated root-viewport control focus with the embedded dialog's focus").
  - Unit-test generation: committed `test_main_menu_intro_visibility.gd` with 11 cases (`8fa1b4b`), kept.

- **@deepsource-io**
  - Ran static analysis on `8f8fe8b...8fa1b4b`: grade A overall and in every category; no issues.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
