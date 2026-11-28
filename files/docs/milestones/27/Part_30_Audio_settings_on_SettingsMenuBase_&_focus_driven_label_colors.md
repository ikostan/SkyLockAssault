<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Audio settings on SettingsMenuBase, and focus-driven label colors

---

## PR Summary

**Title:** Move Audio settings onto SettingsMenuBase and stop polling label colors  
**PR:** TBD  
**Branch:** TBD → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1180 – [FEATURE] Move Audio settings onto SettingsMenuBase and stop polling label colors](https://github.com/ikostan/SkyLockAssault/issues/1180)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `GUT`, `audio`, `enhancement`, `gdunit4`, `refactoring`

### Purpose

A sub-issue of #621 (Region 6: Presentation & View Layers). It covers the Audio part of the finding "Three settings sub-menus don't use `SettingsMenuBase`" and the finding "Label colors are polled every frame".

`audio_settings.gd` extended `Control` and kept its own copies of what `SettingsMenuBase` already does:

| Duplicated piece | Audio before                                                                     | Now                                                |
|------------------|----------------------------------------------------------------------------------|----------------------------------------------------|
| Back path        | `_on_back_button_pressed()` popped the stack itself, with no double-press guard  | `_go_back()`                                       |
| Unexpected exit  | `_on_tree_exited()`                                                              | Base `_teardown()`                                 |
| Signal cleanup   | Manual `is_connected()` / `disconnect()` for `AudioManager` and `AudioWebBridge` | `safe_connect()`, disconnected on teardown         |
| Setup            | Own `process_mode`, `tree_exited` and `_intentional_exit`                        | Base `_ready()`                                    |
| Focus            | Direct `Globals.ensure_initial_focus()` with a 14-control list                   | `_grab_initial_focus()` and the focus hooks        |
| Label colors     | Six labels recolored every frame in `_process()`                                 | Recolored on `focus_entered` / `focus_exited` only |

For the player: a double-tapped Back (or Godot Back plus browser Back in one frame) restores one menu, not two, and on web an unexpected exit now hides the Audio overlay and shows the Options buttons. Volume, mute, Reset and the warning dialogs behave as before.

---

## Confirm-first results

All three points were checked against `main` (`4e4a44d`) before any code changed. Points 2 and 3 use the new GUT suite (Key Change 5), run first against the old code.

- **1. Only Options opens Audio: confirmed.**
  - The only production reference to `audio_settings.tscn` is the `audio_scene` preload in `options_menu.gd:24`. `GamePaths.AUDIO_SETTINGS_SCENE` is used only by tests.
  - Both ways in (the Audio button and the JS callback `_on_audio_pressed_js()`, `options_menu.gd:302`) go through `_on_audio_settings_button_pressed()` → `_open_sub_menu()` (`options_menu.gd:408-428`).
  - One detail differs from the issue: `_open_sub_menu()` adds Audio to the tree first (`:421`) and pushes Options right after (`:422`), in the same call. Audio's `_ready()` doesn't touch the stack, so Options is always on `hidden_menus` before Back can be pressed.
  - So the `Globals.previous_scene` fallback (old `:209-210`) can't run in the game. It was removed; the base's "No hidden menu to show." path replaces it.
- **2. Label colors: confirmed.** ASL-01 to ASL-05 (a label is yellow while its slider or mute button has focus, white otherwise, including the initial focus and focus leaving the menu) pass on the old `_process()` code and on the new focus-signal code, unchanged.
- **3. Audio overlay hiding: confirmed on Back, not on unexpected exit.**
  - **Back:** the old code hid the Audio overlay and showed the five Options buttons (through `restore_options_menu_dom()`). ASL-11 passes before and after.
  - **Unexpected exit:** the old `_on_tree_exited()` disconnected signals and restored the menu, but **never hid the Audio overlay or showed the Options buttons**, so on web both stayed wrong until the next menu change. ASL-12 failed on the old code and passes now. This is the "unexpected exit also restores the Options overlay" change the issue expected, plus the Audio overlay hide.
- **Issue line numbers had moved** after #1152, #1154 and #1165: Back is at `:174-212`, `_process()` at `:303-320`, `_on_tree_exited()` at `:415-442`, `_intentional_exit` at `:14`, and the focus list at `:134-150`.
- **Baseline on `main`:** the 9 Audio-related GUT suites the issue lists (plus `test_hidden_menu_stack.gd`, `test_audio_web_bridge.gd` and `test_settings_menu_base.gd`) 132/132.

---

## Key Changes

### 1. Extend the base (`audio_settings.gd`)

- `extends SettingsMenuBase`, with `super()` first in `_ready()`.
- Removed the local `_intentional_exit` and the `process_mode` / `tree_exited` setup.

### 2. Tracked connections

- Warning dialog `confirmed` / `canceled`, mute `toggled` and `gui_input`, slider `gui_input`, the Back and Reset buttons, `AudioManager.volume_changed` / `mute_toggled`, and the bridge's `web_back_requested` / `web_reset_requested` all go through `safe_connect()`.
- Deleted `_on_tree_exited()`: the base disconnects every tracked signal and restores the menu on teardown.

### 3. Base exit path and hooks

- `_on_back_button_pressed()` (Godot Back and browser Back) now only calls `_go_back()`.
- `_get_menu_name()` returns "Audio Settings"; `_get_initial_focus_control()` returns `master_slider`; `_get_focus_controls()` returns the same 14 controls; `_grab_initial_focus()` replaces the direct `ensure_initial_focus()` call.
- `_on_previous_menu_restored()` keeps the old focus restoration unchanged (Options' Audio button, or Start in a main-menu `Panel`). Replacing those name checks is #1100.
- `_get_overlay_ids()` returns `[]`, because `AudioWebBridge` owns the Audio overlay. `_cleanup()` hides it with `toggle_dom_visibility(false)`. The base shows `OPTIONS_MENU_OVERLAY_IDS` on both exit paths, which replaces the `restore_options_menu_dom()` fallback (and the `toggle_dom_visibility` / `_web_bridge` checks on the previous menu, which no menu has).
- The bridge is cached in `_audio_web_bridge` in `_ready()`, so `_cleanup()` reaches it after Audio has left the tree. This replaces the old `Engine.get_main_loop()` lookup.
- Removed the `previous_scene` fallback (confirm-first point 1).

### 4. Label colors without polling

- Deleted `_process()` and `_update_label_colors()`.
- `_connect_label_focus()` connects each slider's and mute button's `focus_entered` and `focus_exited` to `_update_label_color()`, bound to that bus's label, and sets the color once in `_ready()`.
- Same colors, now named constants: `LABEL_FOCUS_COLOR` (`f5f50d`) and `LABEL_IDLE_COLOR` (`ffffff`).

### 5. Tests

**No test case was removed.**

- **New `test/gut/test_audio_settings_lifecycle.gd` (13 tests):**
  - ASL-01 / 02: focusing each slider, and each mute button, highlights only its own label.
  - ASL-03: Back or Reset focused leaves every label white.
  - ASL-04: on open, the Master slider has focus and only its label is yellow.
  - ASL-05: focus released turns the label white.
  - ASL-06: after Audio leaves the tree (still alive), nothing on `AudioManager.volume_changed` / `mute_toggled` or the bridge's `web_back_requested` / `web_reset_requested` targets it.
  - ASL-07: two Back presses in one frame restore only one menu.
  - ASL-08: Godot Back plus browser Back in one frame restore only one menu.
  - ASL-09: a freed entry above Options is skipped and Options is shown.
  - ASL-10: Audio defines no `_process()` and isn't processing.
  - ASL-11 / 12: on Back and on unexpected exit, the Audio overlay is hidden once and the five Options buttons are shown once.
  - ASL-13: Back with an empty stack closes Audio and hides its overlay, without showing the Options buttons.
  - The web cases use an `AudioWebBridge` double at `/root/AudioWebBridge` and one JS bridge double shared by the bridge and the menu, so the same assertions run against the old code (Options buttons through the bridge) and the new code (through the base).
- **Comments only:** `test/gut/test_hidden_menu_stack.gd` (HMS-07 and `before_each()` no longer mention the removed `previous_scene` fallback).

### 6. Comments

- `globals.gd`: `previous_scene` is documented as no longer read by any menu.
- `settings_menu_base.gd`: header now says Gameplay and Audio use the base.

---

## Design Decisions

- **The handler name `_on_back_button_pressed()` stays.** The gdUnit4 and GUT suites call it directly, and the bridge signal connects to it. It is a one-line wrapper around `_go_back()`, like Gameplay's.
- **The Audio overlay is hidden in `_cleanup()`, not in the Back handler.** That gives one place for both exit paths, as the issue asks. On Back it runs when the node leaves the tree at the end of the same frame, so in the browser the Audio overlay and the Options buttons still switch in one step.
- **The bridge is cached, not looked up during teardown.** `get_node_or_null("/root/...")` doesn't work once the node is out of the tree; the old code needed a main-loop fallback for that.
- **Focus handling recomputes the pair's state.** Moving focus from a slider to its own mute button fires `focus_exited` (nothing focused yet, label white) and then `focus_entered` (label yellow), so the final color is always right without tracking which control left.
- **`restore_options_menu_dom()` stays in `AudioWebBridge`.** Nothing in the game calls it now, but bridge and JS cleanup is out of scope (deferred to the JS separation work), and TC-AWB-15 to 17 still test it.

---

## Verification

Run locally with Godot 4.7.1-stable, GUT 9.7.1 and gdUnit4 v6.2.0, set up as `gut_tests.yml` and `gdunit4_tests.yml` do. `gdlint ./scripts` and `gdformat --check ./scripts` as in CI.

| State                                          | Result                                                                                  |
|------------------------------------------------|-----------------------------------------------------------------------------------------|
| `main` (`4e4a44d`), 9 Audio-related GUT suites | 132/132                                                                                 |
| `main`, new ASL suite                          | 9/13: ASL-07, 08, 10 fail (expected new behavior), ASL-12 fails (confirm-first point 3) |
| Change, same 9 suites + ASL suite              | 145/145                                                                                 |
| Change, full GUT suite                         | 1,324/1,324 (123 scripts, 16,409 asserts)                                               |
| Change, full gdUnit4 suite                     | 170/170, including `test_audio_settings.gd` (4) and `test_audio_unexpected_exit.gd` (1) |
| `gdlint` / `gdformat --check`                  | Pass                                                                                    |

- **Breaking the new code on purpose** (local copy, undone after each run) shows the new suite catches it:

| Change                                                   | Fails                                    |
|----------------------------------------------------------|------------------------------------------|
| `focus_exited` not connected                             | ASL-01, 02, 03, 05                       |
| `_cleanup()` doesn't hide the Audio overlay              | ASL-11, 12, 13                           |
| Back clears `_intentional_exit` before `_go_back()`      | ASL-07, 08                               |
| Bridge `web_back_requested` connected without tracking   | ASL-06                                   |

- **Not run locally:** Playwright (`navigation_to_audio_test.py`, `volume_sliders_mutes_test.py`, `reset_audio_flow_test.py`, `audio_flow_test.py`, `back_flow_test.py`, `no_error_logs_test.py`), the benchmark and the manual itch.io check.

---

## Review

TBD.

---

## Known Limitations / Follow-ups

- **Manual itch.io check still to do:** open and close Audio from the main menu and the pause menu; focus returns to the Audio button, and labels highlight as you move.
- **Benchmark:** the scenario is unchanged; check the PR table.
- **Line count:** the issue expected about 80 fewer lines. The duplicated logic is gone (138 lines removed), but the file is about the same length (657 lines, was 655), because the hook overrides and the label helpers added 140 lines, mostly doc comments.
- **`Globals.previous_scene` is now unused in production.** `test_audio_settings_interaction.gd`, `test_hidden_menu_stack.gd` and ASL-13 still blank it. It can be removed together with those lines in a later small change.
- **`AudioWebBridge.restore_options_menu_dom()` is now unused in production** (kept, see Design Decisions); remove it in the JS separation work.
- **Next in #621:** #1182 (Advanced) and #1181 (Key Mapping) onto `SettingsMenuBase`, then #1183 (shared loader).

---

## Reviewer's Guide

### File-Level Changes

| Change          | Details                                                                                                                                                                                                 | Files                                                                                                           |
|-----------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| Audio menu.     | <ul><li>Extends `SettingsMenuBase`; tracked connections; base Back / teardown; focus hooks.</li><li>`_cleanup()` hides the Audio overlay.</li><li>Label colors follow focus; no `_process()`.</li></ul> | `scripts/ui/menus/audio_settings.gd`                                                                            |
| Comments.       | <ul><li>`previous_scene` no longer read; base header lists Audio.</li></ul>                                                                                                                             | `scripts/core/globals.gd`<br/>`scripts/ui/menus/settings_menu_base.gd`<br/>`test/gut/test_hidden_menu_stack.gd` |
| GUT tests.      | <ul><li>New ASL suite (13).</li></ul>                                                                                                                                                                   | `test/gut/test_audio_settings_lifecycle.gd`                                                                     |
| Milestone note. | <ul><li>This note.</li></ul>                                                                                                                                                                            | `files/docs/milestones/27/Part_30_Audio_settings_on_SettingsMenuBase_&_focus_driven_label_colors.md`            |

### Assessment against linked issues

| Issue                                                   | Objective                                                                                      | Addressed | Explanation                                            |
|---------------------------------------------------------|------------------------------------------------------------------------------------------------|-----------|--------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1180> | The confirm-first results are recorded on the PR                                               | ✅        | Confirm-first results.                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1180> | `audio_settings.gd` extends `SettingsMenuBase`, no duplicated exit, teardown or signal cleanup | ✅        | Key Changes 1-3.                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1180> | Label colors change on focus, with no `_process()`                                             | ✅        | Key Change 4; ASL-01 to 05 and ASL-10.                 |
| <https://github.com/ikostan/SkyLockAssault/issues/1180> | Volume, mute, Reset and warnings behave as before                                              | ✅        | Full GUT and gdUnit4 suites; manual check still to do. |
| <https://github.com/ikostan/SkyLockAssault/issues/1180> | All GUT, gdUnit4, Playwright and lint jobs pass, with no test cases removed                    | ⏳        | GUT, gdUnit4 and lint pass locally; Playwright in CI.  |
| <https://github.com/ikostan/SkyLockAssault/issues/1180> | The PR's milestone note is added under `files/docs/milestones/`                                | ✅        | This note.                                             |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1180 from the #621 (Region 6) review, with the confirm-first steps, the implementation plan and the test list.
- Picked #1180 as the next PR.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Confirm-first**
    - Traced every way Audio is opened, and found that Options pushes itself onto the stack right after adding Audio (not before), which doesn't change the result.
    - Ran the label color and overlay cases against the old code, and found that an unexpected exit never hid the Audio overlay or showed the Options buttons.
    - Found the moved line numbers.
  - **Tests**
    - Wrote the 13 ASL tests, ran them before and after the change, and broke the new code on purpose to confirm they catch regressions.
  - **Verification**
    - Ran the full GUT and gdUnit4 suites, `gdlint` and `gdformat`.
    - Wrote this note.
