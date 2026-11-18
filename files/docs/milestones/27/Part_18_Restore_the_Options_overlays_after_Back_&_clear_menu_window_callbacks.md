<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Restore the Options overlays after Back & clear menu window callbacks

---

## PR #_fill in_ Summary

**Title:** Restore the Options overlays after Back and clear menu window callbacks  
**PR:** _fill in_  
**Branch:** `architect-review-region-3` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1165 – [BUG] Web test overlay shows wrong Options buttons after Audio or Controls → Back](https://github.com/ikostan/SkyLockAssault/issues/1165)
- [#1166 – [BUG] Web test callbacks stay on window after menus are freed](https://github.com/ikostan/SkyLockAssault/issues/1166)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** _fill in_

### Purpose

This PR covers both sub-issues of Region 3 (#618). After it, the epic has no open work. Both parts are about the HTML overlay and the `window.*` callbacks that exist only so Playwright can drive the menus in CI; players don't use them, and they'll be split out of production builds later.

**Part A: Wrong Options buttons after Audio or Controls → Back (#1165).** Two Back paths used hand-written ID lists:

- Audio → Back falls through to `AudioWebBridge.restore_options_menu_dom()`, whose list left out `controls-button`.
- Controls → Back showed `difficulty-slider`, a Gameplay control, and left out `gameplay-button`.

**Part B: Callbacks stay on `window` after menus are freed (#1166).** Options, Main and Pause never cleared their callbacks. Key Mapping cleared its callback only on the Back path. A test could call into a menu that no longer existed.

Done in that order, as #1166 asks, because both parts change `key_mapping.gd`.

---

## Confirm-first results

Both issues asked to check the code-reading claims against `main` (`64ef072`) before any fix. The new Playwright and GUT tests were run on unchanged code first.

### #1165

| Check                                                                             | Result on `main`                                         |
|-----------------------------------------------------------------------------------|----------------------------------------------------------|
| After Audio → Back, is `controls-button` hidden?                                  | **Yes.** The other four Options buttons are shown.       |
| After Controls → Back, is `difficulty-slider` shown and `gameplay-button` hidden? | **Yes, both.** The other four Options buttons are shown. |

Both paths were broken, so both are in the fix.

### #1166, question 1: do the callbacks really stay?

| Menu        | Check                                                      | Result on `main`                               |
|-------------|------------------------------------------------------------|------------------------------------------------|
| Main        | After Start, `startPressed`/`optionsPressed`/`quitPressed` | **Stay** (all `function`)                      |
| Pause       | After returning to the Main menu, the 4 Pause callbacks    | **Stay** (all `function`)                      |
| Options     | After Options → Back, the 5 Options callbacks              | **Stay** (all `function`)                      |
| Key Mapping | Back path                                                  | Cleared (as the issue said)                    |
| Key Mapping | Unexpected exit (no Back)                                  | **Stays**: `main` has no `_exit_tree()` for it |

All four menus are in the fix.

### #1166, question 2: can clearing on exit erase a new instance's callbacks?

Tested with the simple cleanup (fix steps 1–3), reopening each menu in the **same frame** as its exit, which is the tightest case:

| Case                                                | Result with the simple cleanup                                                                                                                                        |
|-----------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Options reopened straight after Back                | **Keeps** the new callbacks. Options clears them in `_teardown()`, which Back runs synchronously.                                                                     |
| Main menu loaded again after the game               | **Keeps** them. The old menu is freed long before the new one loads.                                                                                                  |
| Pause menu created again for a new game             | **Keeps** them, for the same reason.                                                                                                                                  |
| Controls (Key Mapping) reopened straight after Back | **Loses** `controlsBackPressed`: Back clears it straight away, but the old instance's `_exit_tree()` runs at the end of the frame, after the new instance registered. |

So the guard from fix step 4 is added, for Key Mapping only. See Design Decisions.

---

## Key Changes

### Part A: Restore exactly the Options overlays (#1165)

#### 1. `restore_options_menu_dom()` (`audio_web_bridge.gd`)

- Shows `SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS` with one `eval()` built by `SettingsMenuBase._build_overlay_js(ids, [])`, instead of four `eval()` calls from its own list.

#### 2. Key Mapping Back (`key_mapping.gd`)

- New `returned_to_options` flag, set when the menu popped from the stack is an `OptionsMenu`.
- One `eval()` built by `_build_overlay_js(visible_ids, ["controls-back-button"])`: it shows the five `OPTIONS_MENU_OVERLAY_IDS` only when Back returns to Options, and always hides `controls-back-button`.
- `difficulty-slider` is no longer touched.
- Opened from the main menu's "Unbound Controls" dialog (`Globals.load_key_mapping(ui_panel)` pushes the main menu's `Panel`), Back shows none of the Options buttons. The same holds when no hidden menu exists.

#### 3. Tests (#1165)

- **`test_audio_web_bridge.gd` (14 → 16 cases):** new TC-AWB-15 (one `eval()`, exactly the five IDs including `controls-button`, nothing hidden) and TC-AWB-16 (no `eval()` when `js_window` is null).
- **New `test_key_mapping_web_overlays.gd` (4 cases, wrapper doubles):**
  - KM-WEB-01: Back to Options shows exactly the five IDs, hides `controls-back-button`, and doesn't mention `difficulty-slider`.
  - KM-WEB-02: off web, Back makes no `eval()` call and doesn't touch `window`.
  - KM-WEB-03: with no hidden menu, Back shows none of the five and still hides `controls-back-button`.
  - KM-WEB-04: opened from the main menu, Back shows none of the five, still hides `controls-back-button`, and shows the main menu again.
- **`tests/back_flow_test.py` (1 → 2 tests):** new `test_back_restores_options_overlays` (BACK-05, BACK-06). Each Back path checks the computed `display` of all five Options buttons and of `difficulty-slider`, and reports every wrong one. It uses a fresh page, so it doesn't depend on where `test_back_flow` leaves the shared page.

### Part B: Clear menu window callbacks (#1166)

#### 1. One cleanup helper per menu

Each follows `gameplay_settings.gd`'s `_unset_gameplay_settings_window_callbacks()`: it sets the menu's `window.*` callbacks to `null`, returns early off web or without a window, and is safe to call twice.

| Menu        | Helper                                    | Called from                                        |
|-------------|-------------------------------------------|----------------------------------------------------|
| Options     | `_unset_options_menu_window_callbacks()`  | `_teardown()` (Back, and `_exit_tree()`)           |
| Key Mapping | `_unset_key_mapping_window_callbacks()`   | The Back path (as before) and a new `_exit_tree()` |
| Main        | `_unset_main_menu_window_callbacks()`     | New `_exit_tree()`                                 |
| Pause       | `_unset_pause_menu_window_callbacks()`    | New `_exit_tree()`                                 |

#### 2. Supporting changes

- **Options (`options_menu.gd`):** `js_window` is now a member (it was a local in `_ready()`), so the cleanup can reach it. It and the five `*_cb` fields are `Variant` instead of `JavaScriptObject`, so tests can inject the wrapper doubles the menu already supports.
- **Main and Pause (`main_menu.gd`, `pause_menu.gd`):** the window is stored in a new `_js_window: Variant` member. They still call `JavaScriptBridge` directly; the switch to the wrappers is deferred to the JS separation work, as the issue says.
- **Callback refs are dropped one call later.** Each helper clears `window` at once and drops the stored `*_cb` refs with `call_deferred()`. See Design Decisions.
- **Key Mapping guard:** new `_window_callbacks_unset` flag, so an instance clears `window` at most once.

#### 3. Tests (#1166)

- **New `test_menu_window_callbacks.gd` (15 cases).** Options and Key Mapping use wrapper doubles. Main and Pause inject the `window` Dictionary that `_ready()` stores on web.
  - **Options:** exit clears all five and drops the refs one frame later (WCB-01); Back clears them before the deferred free (WCB-02); reopening straight after Back keeps the new instance's callbacks (WCB-03); off web nothing is written (WCB-04); twice is safe (WCB-05).
  - **Key Mapping:** Back clears and keeps the running callback's ref until the call returns (WCB-06); an unexpected exit clears (WCB-07); reopening in the same frame as Back keeps the new callback (WCB-08); off web (WCB-09); twice is safe (WCB-10).
  - **Main:** exit clears all three (WCB-11); off web no window is stored, and the cleanup is safe twice (WCB-12); a reloaded menu keeps its callbacks (WCB-13).
  - **Pause:** exit clears all four (WCB-14); off web and twice (WCB-15).
- **New `tests/menu_window_callbacks_test.py` (3 tests):**
  - PW-CB-01: after Start, the Main callbacks are `null`; after returning, the Pause callbacks are `null` and the reloaded Main menu's work; a second game's Pause callbacks work.
  - PW-CB-02: after Options → Back and Controls → Back, their callbacks are `null`; reopened menus work.
  - PW-CB-03: Controls and Options reopened in the same JS call as their Back keep working callbacks.
- **`tests/scene_transition_lifecycle_test.py` (2 tests rewritten, none removed):** PW-TRANS-03 and PW-TRANS-04 fire three presses in one JS call. The first press frees the menu, which now clears the `window` property, so presses 2 and 3 threw `TypeError: ... is not a function`. Both now capture the callback before the burst, so all three presses still reach the leaving menu. A probe confirmed it: 3 presses reached Godot and the main scene initialized once.

---

## Design Decisions

### Part A (#1165)

- **One `eval()` per Back.** `_build_overlay_js()` escapes the IDs and is what `SettingsMenuBase` already uses, so the list and the JS format can't drift from the other settings menus.
- **"Returned to Options" means the popped menu `is OptionsMenu`.** That's the same check Key Mapping already used for focus, so the overlays and focus agree.

### Part B (#1166)

- **Key Mapping guard: clear at most once, not "only if it's still ours".** Step 4 suggests clearing a callback only if it still belongs to this instance. Comparing `window.controlsBackPressed` with the stored callback can't work: Godot wraps every JS object it reads in a new `JavaScriptObjectImpl` (`_js2variant()` in 4.7.1), so the two never compare equal. Instead, an instance that has already cleared `window` (on Back) doesn't clear it again in `_exit_tree()`. Anything registered after that belongs to a newer instance. The other menus don't need the flag: Options already tears down once (`_torn_down`), and Main and Pause are freed long before a new instance loads.
- **Refs are dropped with `call_deferred()`.** Several exits run inside one of the menu's own callbacks: Options and Key Mapping Back pressed from JS, Start (the scene change removes the main menu at once), and Main Menu from Pause. Dropping the stored ref there frees the `JavaScriptObject` whose callback is still running. Godot 4.7.1's `_callback()` doesn't read the object after the call returns, so it worked, but that's an engine detail to rely on. A deferred drop runs after the call. If the node is freed first, the deferred call is skipped with no error, and the refs go with the node (checked with a probe on 4.7.1).
- **Main and Pause check `_js_window`, not `OS.get_name()`.** `_js_window` is only set on web, so the result is the same, and GUT can test the helper by injecting a window.
- **PW-CB-03 reopens in the same JS call.** That's the tightest version of "reopened straight after", and the only one where the old exit can overlap the new registration.

---

## Verification

Run locally with Godot 4.7.1-stable and GUT 9.7.1, using the same commands as `gut_tests.yml`. The web build is the `Web_thread_off` preset, built the way `browser_test.yml` does (plugins disabled, test salt, `ci` feature flag, `patch_index_js.sh`), served by `serve_web_export.py`, with Playwright 1.63 Chromium. `gdformat --check` and `gdlint` as in CI.

- **Totals:**

| State                    | GUT scripts | GUT tests | GUT asserts | Playwright (Core Web Flows) |
|--------------------------|-------------|-----------|-------------|-----------------------------|
| `main` (`64ef072`, base) | 107         | 991       | 10,950      | 65                          |
| This PR                  | 109         | 1,012     | 11,052      | 69                          |

- **Test counts per changed file (`main` → this PR):**

| File                                  | Framework  | Cases                |
|---------------------------------------|------------|----------------------|
| `test_audio_web_bridge.gd`            | GUT        | 14 → 16              |
| `test_key_mapping_web_overlays.gd`    | GUT        | new, 4               |
| `test_menu_window_callbacks.gd`       | GUT        | new, 15              |
| `back_flow_test.py`                   | Playwright | 1 → 2                |
| `menu_window_callbacks_test.py`       | Playwright | new, 3               |
| `scene_transition_lifecycle_test.py`  | Playwright | 6 → 6 (2 rewritten)  |

- **No test cases removed.**
- **The checkbox to "update the existing `restore_options_menu_dom()` test" in #1165:** no such test existed anywhere in `test/`. TC-AWB-15 and TC-AWB-16 are new.
- **Suites the issues name:** `navigation_to_audio_test.py`, `difficulty_flow_test.py`, `back_flow_test.py`, `scene_transition_invariants_test.py`, `scene_transition_lifecycle_test.py`, `no_error_logs_test.py` (Playwright), `test_gameplay_settings_lifecycle.gd`, `test_pause_menu.gd`, `test_main_menu_audio.gd` and the Key Mapping suites (GUT) all pass.
- **Mutation checks:**
  - Without the Key Mapping guard, WCB-08 fails.
  - Without Key Mapping's `_exit_tree()`, WCB-07 fails.
  - With Key Mapping's old hand-written list, 3 of the 4 KM-WEB cases fail.
- **Full GUT suite:** 1,012/1,012, same 3 warnings as `main`.
- **Full Playwright Core Web Flows:** 69 passed, including the 4 new tests and the 2 rewritten ones.
- **CI & Security shard (local):** 1,122 of 1,123 pass. `test_salt_injection.py::test_injection_readonly_file` fails only because the sandbox runs as root, which can write read-only files; it passed in CI on the last PR.
- **GDScript lint and format:** `gdlint scripts` and `gdformat --check scripts` pass.
- **PR run:** _fill in after CI._

---

## Known Limitations / Follow-ups

- **The overlay's `onclick` handlers read `window.*` on every click.** With callbacks now cleared, a second click on a menu's overlay in the same frame as the first (before the next menu registers) throws a `TypeError` in the browser console instead of reaching the leaving menu. No test clicks that fast. Making the handlers null-safe belongs with the JS separation work, which #1165 and #1166 leave the overlay to.
- **Main and Pause still call `JavaScriptBridge` directly,** so their GUT tests can't run the real web registration. They inject the window that `_ready()` stores on web; Playwright PW-CB-01 covers the real path.
- **The Key Mapping guard assumes one Key Mapping at a time,** which is true today: opening it hides the menu that opened it.
- **#618 can close** once this merges.

---

## Reviewer's Guide

### File-Level Changes

| Change                        | Details                                                                                                                     | Files                                                                                                                             |
|-------------------------------|-----------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| A: Audio → Back restore list. | <ul><li>`OPTIONS_MENU_OVERLAY_IDS` in one `eval()`.</li></ul>                                                               | `scripts/system/audio_web_bridge.gd`                                                                                              |
| A: Controls → Back overlays.  | <ul><li>Five Options buttons only when returning to Options.</li><li>`difficulty-slider` no longer shown.</li></ul>         | `scripts/ui/menus/key_mapping.gd`                                                                                                 |
| A: Tests.                     | <ul><li>2 GUT cases added, 1 new GUT suite (4 cases).</li><li>1 Playwright test added.</li></ul>                            | `test/gut/test_audio_web_bridge.gd`<br/>`test/gut/test_key_mapping_web_overlays.gd`<br/>`tests/back_flow_test.py`                 |
| B: Options callbacks.         | <ul><li>Cleared in `_teardown()`.</li><li>`js_window` member; `Variant` fields.</li></ul>                                   | `scripts/ui/menus/options_menu.gd`                                                                                                |
| B: Key Mapping callback.      | <ul><li>New `_exit_tree()`; clear-once guard.</li></ul>                                                                     | `scripts/ui/menus/key_mapping.gd`                                                                                                 |
| B: Main and Pause callbacks.  | <ul><li>New `_exit_tree()`; `_js_window` member.</li></ul>                                                                  | `scripts/ui/menus/main_menu.gd`<br/>`scripts/ui/menus/pause_menu.gd`                                                              |
| B: Tests.                     | <ul><li>1 new GUT suite (15 cases), 1 new Playwright suite (3 tests).</li><li>2 Playwright burst tests rewritten.</li></ul> | `test/gut/test_menu_window_callbacks.gd`<br/>`tests/menu_window_callbacks_test.py`<br/>`tests/scene_transition_lifecycle_test.py` |
| Milestone note.               | <ul><li>This note.</li></ul>                                                                                                | `files/docs/milestones/27/Part_18_Restore_the_Options_overlays_after_Back_&_clear_menu_window_callbacks.md`                       |

### Assessment against linked issues

| Issue                                                   | Objective                                                             | Addressed | Explanation                                                                               |
|---------------------------------------------------------|-----------------------------------------------------------------------|-----------|-------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1165> | Confirm-first results recorded on the PR                              | ✅         | See Confirm-first results.                                                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1165> | Both Back paths restore exactly the five Options buttons              | ✅         | BACK-05/06 in the browser; TC-AWB-15 and KM-WEB-01.                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1165> | Both use `OPTIONS_MENU_OVERLAY_IDS` instead of hand-written lists     | ✅         | TC-AWB-15 and KM-WEB-01 compare against `_build_overlay_js(OPTIONS_MENU_OVERLAY_IDS, …)`. |
| <https://github.com/ikostan/SkyLockAssault/issues/1166> | Confirm-first results recorded, for both questions                    | ✅         | See Confirm-first results.                                                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1166> | Every menu that registers `window.*` callbacks clears them when freed | ✅         | PW-CB-01/02 in the browser; WCB-01, 07, 11, 14.                                           |
| <https://github.com/ikostan/SkyLockAssault/issues/1166> | Reopening a menu keeps its callbacks working                          | ✅         | PW-CB-01/02/03; WCB-03, 08, 13.                                                           |
| <https://github.com/ikostan/SkyLockAssault/issues/1166> | Desktop builds are unaffected                                         | ✅         | Off-web cases WCB-04, 09, 12, 15 and KM-WEB-02; full GUT suite passes.                    |
| Both                                                    | All GUT, Playwright and lint jobs pass, no cases removed              | ⏳         | Pass locally; PR run to confirm.                                                          |
| Both                                                    | The PR's milestone note is added                                      | ✅         | This note.                                                                                |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1165 and #1166 and set their scope, including the confirm-first steps.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Planning**
    - Checked that the code #1165 points at was still as described after PR #1206, and found the `restore_options_menu_dom()` test the issue mentions doesn't exist.
  - **Verification**
    - Ran the full GUT suite, the full Core Web Flows Playwright suite, the CI & Security shard, `gdformat` and `gdlint` locally, and mutation-tested the guard, the new `_exit_tree()` and the overlay list.
    - Wrote this note.
