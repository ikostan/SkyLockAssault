<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Restore the Options overlays after Back & clear menu window callbacks

---

## PR #1210 Summary

**Title:** System abstractions web interoperability hardening  
**PR:** <https://github.com/ikostan/SkyLockAssault/pull/1210>  
**Branch:** `system-abstractions-web-interoperability-hardening` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1165 – [BUG] Web test overlay shows wrong Options buttons after Audio or Controls → Back](https://github.com/ikostan/SkyLockAssault/issues/1165)
- [#1166 – [BUG] Web test callbacks stay on window after menus are freed](https://github.com/ikostan/SkyLockAssault/issues/1166)
- [#618 – [ARCHITECT-REVIEW] Region 3: System Abstractions & Web Interoperability Hardening](https://github.com/ikostan/SkyLockAssault/issues/618) (epic; its remaining findings are tracked in #1184)

**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** `documentation`, `refactoring`, `EPIC`

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

- **`test_audio_web_bridge.gd` (14 → 17 cases):** new TC-AWB-15 (one `eval()`, exactly the five IDs including `controls-button`, nothing hidden) and TC-AWB-16 (no `eval()` when `js_window` is null). TC-AWB-17 (no window, then the window again: no `eval()`, then one `eval()` in the global context) was added by CodeRabbit (see Review fixes).
- **New `test_key_mapping_web_overlays.gd` (11 cases, wrapper doubles):**
  - KM-WEB-01: Back to Options shows exactly the five IDs, hides `controls-back-button`, and doesn't mention `difficulty-slider`.
  - KM-WEB-02: off web, Back makes no `eval()` call and doesn't touch `window`.
  - KM-WEB-03: with no hidden menu, Back shows none of the five and still hides `controls-back-button`.
  - KM-WEB-04: opened from the main menu, Back shows none of the five, still hides `controls-back-button`, and shows the main menu again.
  - KM-WEB-05: a second Back in the same frame changes neither the menu stack nor the overlays. Added for the review fix below.
  - KM-WEB-06 to KM-WEB-08: an unexpected exit hides `controls-back-button`; an exit after Back, or by an older instance, leaves the overlays alone. Added for the review fix below.
  - KM-WEB-09: with two Key Mappings open, the older one's Back shows no Options buttons; the newer one's Back shows them. Added for the review fix below.
  - KM-WEB-10: a freed entry on top of the stack is skipped, so Back shows the next valid menu and hides `controls-back-button` (#1211). KM-WEB-11: two Back calls through the JS entry point with no menu on the stack make one overlay update. Both added by CodeRabbit (see Review fixes).
- **`tests/back_flow_test.py` (1 → 2 tests):** new `test_back_restores_options_overlays` (BACK-05, BACK-06). Each Back path checks the computed `display` of all five Options buttons and of `difficulty-slider`, and reports every wrong one. It uses a fresh page, so it doesn't depend on where `test_back_flow` leaves the shared page. Before each Back it waits for the five Options buttons to be hidden while the submenu is shown, so it sees them change from `none` to `block` (see Review fixes).

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
- **Main and Pause (`main_menu.gd`, `pause_menu.gd`):** the window is stored in a new `_js_window: Variant` member. They still call `JavaScriptBridge` directly; the switch to the wrappers is deferred to the JS separation work, as the issue says. Their callback fields are `Variant` too (see Review fixes), so tests can seed them.
- **Callback refs are dropped one call later.** Each helper clears `window` at once and drops the stored `*_cb` refs with `call_deferred()`. See Design Decisions.
- **Key Mapping guard:** new `static var _window_callback_owner_id`, set when an instance registers its callback. An instance clears `window.controlsBackPressed` only while it owns the slot.

#### 3. Tests (#1166)

- **New `test_menu_window_callbacks.gd` (24 cases).** Options and Key Mapping use wrapper doubles. Main and Pause inject the `window` Dictionary that `_ready()` stores on web.
  - **Options:** exit clears all five and drops the refs one frame later (WCB-01); Back clears them before the deferred free (WCB-02); reopening straight after Back keeps the new instance's callbacks (WCB-03); off web nothing is written (WCB-04); twice is safe (WCB-05).
  - **Key Mapping:** Back clears and keeps the running callback's ref until the call returns (WCB-06); an unexpected exit clears (WCB-07); reopening in the same frame as Back keeps the new callback (WCB-08); off web (WCB-09); twice is safe (WCB-10).
  - **Main:** exit clears all three (WCB-11); off web no window is stored, and the cleanup is safe twice (WCB-12); the old menu's deferred cleanup leaves a newer menu's callbacks alone (WCB-13).
  - **Pause:** exit clears all four (WCB-14); off web and twice (WCB-15).
  - **Two Key Mappings open at once:** the older one's exit (WCB-16) or Back (WCB-17) keeps the newer one's callback, and the newer one still clears it on exit. Added for the second review fix below.
  - **Options reopened through `Globals.load_options()`:** the old instance's exit keeps the new one tracked, open and with its parent on the stack (WCB-18). Added for the review fix below.
  - **Added by CodeRabbit (see Review fixes):** Options cleanup with no window still drops its refs (WCB-19) and its deferred drop keeps later registrations (WCB-20); a tracked Options that is out of the tree counts as exited (WCB-21); repeated Key Mapping cleanup keeps a later owner (WCB-22); Main cleanup with no window still drops its refs (WCB-23); Pause's deferred drop keeps later registrations (WCB-24).
- **New `tests/menu_window_callbacks_test.py` (4 tests):**
  - PW-CB-01: after Start, the Main callbacks are `null`; after returning, the Pause callbacks are `null` and the reloaded Main menu's work; a second game's Pause callbacks work.
  - PW-CB-02: after Options → Back and Controls → Back, their callbacks are `null`; reopened menus work.
  - PW-CB-03: Controls and Options reopened in the same JS call as their Back keep working callbacks. Each check waits for the old instance's "(left the tree)" exit log, so it runs after the old cleanup. It also checks that the old exit logs no "Options instance exited unexpectedly" warning and that the reopened Options' Back logs "Showing menu" (see Review fixes).
  - PW-CB-04: Options Back clicked twice through the DOM in one JS task. The callback must already be `null` between the two clicks, the second click does nothing and throws no page error, and after reopening a DOM-dispatched click on Back still navigates. Added for the review fix below.
- **`tests/scene_transition_lifecycle_test.py` (2 tests rewritten, none removed):** PW-TRANS-03 and PW-TRANS-04 fire three presses in one JS call. The first press frees the menu, which now clears the `window` property, so presses 2 and 3 threw `TypeError: ... is not a function`. Both now capture the callback before the burst, so all three presses still reach the leaving menu. A probe confirmed it: 3 presses reached Godot and the main scene initialized once. PW-TRANS-03 also counts accepted Start requests (see Review fixes). PW-TRANS-04 also counts ignored Main Menu presses and fails on Godot errors.

### Review fixes (CodeRabbit)

- **`custom_shell.html`, Options Back overlay:** the handler now calls `window.optionsBackPressed && window.optionsBackPressed([])`, like the Pause handlers. Options Back clears `window.optionsBackPressed` straight away, so a second activation in the same frame threw `TypeError: window.optionsBackPressed is not a function`. PW-CB-04 failed that way before the fix and passes after it.
- **`key_mapping.gd`, owner of `window.controlsBackPressed`:** Options' `_open_sub_menu()` has no guard, and Options stays alive while Key Mapping is open, so a second `controlsPressed` call opens a second Key Mapping that takes over the slot. The first instance's flag (`_window_callbacks_unset`) was still false, so its Back or exit cleared the newer instance's callback. Ownership is now tracked by instance ID (`_window_callback_owner_id`), which replaces the flag and also covers the same-frame reopen (WCB-08). An instance that no longer owns the slot only releases its own ref. WCB-16 and WCB-17 failed before the fix and pass after it.
- **`tests/menu_window_callbacks_test.py`, PW-CB-03 waits:** the test slept a fixed 500 ms after each same-frame Back and reopen before checking the new callbacks. If the old instance hadn't left the tree by then, the check could pass before the old cleanup ran, and miss the bug it tests for. It now waits for the old instance's exit log instead. Key Mapping's `_exit_tree()` gains a "Key Mapping menu exited (left the tree)." log, and Options' existing `_exit_tree()` log becomes "Options menu exited (left the tree).". The old text is still a prefix, so the tests that match "options menu exited" are unaffected, and `_teardown()`'s own "Options menu exited." line on Back doesn't satisfy the wait. With Key Mapping's owner check removed, PW-CB-03 now fails at the Controls check.
- **`main_menu.gd`, one transition request per Start burst:** `_on_start_pressed()` had no re-entry guard, so each press in a burst called `Globals.load_scene_with_loading()`. In 4.7.1, `change_scene_to_node()` instantiates the new loading screen and `queue_delete()`s the pending one each time, so a burst of three built three loading screens and played the accept sound three times; only one mounted, which is why PW-TRANS-03 still passed. A new `_start_transition_requested` flag is set when Start requests the game scene, and later presses log "Start Game ignored: transition already requested." and return before the sound and the request. The "Unbound Controls" dialog path doesn't set it. PW-TRANS-03 now also asserts 3 presses reached Godot, 1 accepted request ("Start Game transition requested.") and 2 ignored presses. New GUT test `test_start_burst_requests_one_transition` in `test_main_menu_audio.gd` checks that a second press makes no request and plays no sound. Without the guard, both fail.
- **`key_mapping.gd`, second Back before the menu is freed:** `_intentional_exit` was set only at the end of `_on_controls_back_button_pressed()`, just before `queue_free()`, and nothing checked it on entry. A second Back in the same frame (a double press, or a JS burst through a captured `controlsBackPressed`) popped the stack again: from Main → Options → Key Mapping it showed the main menu as well and hid the Options overlay buttons again. Back now checks and sets `_intentional_exit` first, and later calls log "Back ignored: controls menu is already closing." and return. New GUT test KM-WEB-05 runs Back twice in one frame and checks that Options is shown, the main menu stays hidden and on the stack, and the overlays stay as the first Back left them. It failed on all four checks before the fix.
- **`key_mapping.gd`, Back button left shown on an unexpected exit:** `_ready()` shows `#controls-back-button`, but only Back hid it again. With `_exit_tree()` now clearing `window.controlsBackPressed`, an exit without Back left a shown button whose handler throws a `TypeError`. `_exit_tree()` now also hides the button, but only while this instance still owns the slot: after Back (which already hid it and reset the owner), or once a newer Key Mapping took over, the button is the newer instance's. Key Mapping is added to the root, so in the game only Back removes it; unexpected exits come from tests and from quitting. New GUT tests: KM-WEB-06 (unexpected exit hides the button, failed before the fix), KM-WEB-07 (exit after Back doesn't touch the overlays again) and KM-WEB-08 (an older instance's exit leaves the newer one's button shown). Hiding on every exit fails KM-WEB-07 and KM-WEB-08.
- **`key_mapping.gd`, shared Back button on an older instance's Back:** Back always hid `controls-back-button`. With two Key Mappings open, the older one's Back hid the button the newer one still uses. Back now hides it only if this instance owns `window.controlsBackPressed`, or no instance does, and skips the `eval()` when there is nothing to change. The Options overlay restore is unchanged. WCB-17 now also checks that the older Back sends no hide for the button; it failed before the fix.
- **`test_menu_window_callbacks.gd`, tests that couldn't fail:**
  - **WCB-11 and WCB-14** checked that Main's and Pause's callback refs are dropped, but off web those refs are always null, since a `JavaScriptObject` can't be created there (`ClassDB.can_instantiate()` is false and `create_callback()` returns null). The tests now seed the refs and check that they survive the current call and are null one frame later. For that, Main's and Pause's callback fields are now `Variant`, as Options' already were. Without the deferred ref drop, WCB-11, WCB-13 and WCB-14 fail.
  - **WCB-13** wrote values to the fake window and read them back, which proved nothing. Rewritten (not removed): a newer registration is written after the old main menu exits but before its deferred ref drop runs, and must survive that drop. Real web registration is covered by PW-CB-01.
- **`test_menu_window_callbacks.gd` and `test_key_mapping_web_overlays.gd`, log level:** both set `current_log_level` in `before_each()` and `after_each()`. That setting is persisted, so every test saved `user://settings.cfg` twice and left the level at DEBUG. The override isn't needed and is removed from both. 14 older suites use the same pattern; they aren't changed here.
- **`tests/back_flow_test.py`, BACK-05/06:** the test never checked that the Options buttons were hidden while Audio or Controls was open, so a Back handler that never restored anything would pass if the buttons simply stayed shown. It also slept 500 ms after each Back, having waited only for the submenu to close. A new `_wait_for_overlays()` helper waits for a set of elements to be shown and another to be hidden, in one browser-side check, and on timeout fails with every element's state. Before each Back it now waits for the submenu control to be shown and the five Options buttons hidden. After Back it waits for the five to be shown and the submenu control and `difficulty-slider` hidden. Both sleeps are gone. Checked with mutant builds: with Options no longer hiding `controls-button` on submenu open, the test fails at "Audio opened"; with the old Audio restore list, it fails at "Audio -> Back".
- **`globals.gd`, the old Options' exit reset the reopened one:** `load_options()` connects each Options instance's `tree_exited` to `_on_options_exited_unexpectedly()`, which pops `hidden_menus` and clears `options_open` and `options_instance` without checking which instance exited. With Options reopened in the same frame as its Back, the old instance left the tree after the new one opened, so the handler popped and showed the new one's parent and cleared its state. The new Options then had no parent to restore on Back. The handler now returns when the tracked `options_instance` is still in the tree, since the exiting node must then be an older one. It still resets when the tracked instance itself exits, so the gdUnit4 teardown test, which drives it with a dummy node, is unchanged. This handler predates the PR; PW-CB-03, added here, is what reopens Options in the same frame. New GUT test WCB-18 reopens Options through `Globals.load_options()` in the same frame and checks that the new instance stays tracked and open, its parent stays hidden on the stack, and its Back restores the parent; it failed on all four checks before the fix. PW-CB-03 now also checks that no "Options instance exited unexpectedly" warning follows the old exit, and that the reopened Options' Back logs "Showing menu"; it failed on the first check before the fix.
- **`pause_menu.gd`, Main Menu burst after the scene change:** the first `mainMenuPressed` changes the scene, which takes the Pause menu out of the tree at once. PW-TRANS-04's captured callback still reached it on presses 2 and 3, where `get_tree()` returned null and logged `ERROR: Parameter "data.tree" is null`; each press also requested the main menu again. PW-TRANS-04 never checked for errors, so it passed. `_on_back_to_main_button_pressed()` now returns when the menu is no longer in the tree, logging "Back To Main Menu ignored: pause menu already left the tree." PW-TRANS-04 now asserts 3 presses reached Godot, 2 were ignored and no Godot error was logged during the burst; it failed (0 ignored) before the fix. New GUT test PM-06 in `test_pause_menu.gd` calls the handler on a Pause menu outside the tree and checks that no second request is made; without the guard it fails on the `data.tree` error.
- **`key_mapping.gd`, Options buttons shown over a newer Key Mapping:** with two Key Mappings opened from Options, Options is on the stack twice. The older one's Back popped an Options entry and showed the five Options overlay buttons while the newer Key Mapping was still open. Back now shows them only when it returns to Options and this instance owns the Back button; otherwise the overlays are left alone. The newer one's Back, as owner, then shows them and hides its button. New GUT test KM-WEB-09 checks both steps; it failed on all five buttons before the fix.
- **`tests/menu_window_callbacks_test.py`, PW-CB-04 checks:** the test read `window.optionsBackPressed` only after both clicks, so it couldn't tell whether cleanup ran before the second click. It now records the callback's state between the two clicks, in the same `evaluate`, and asserts it was `null`; with the cleanup deferred to the next frame (mutant build) it fails. Its last step used `click(force=True)`, but the overlay buttons have `pointer-events: none`: a probe showed `elementFromPoint` at the button's centre returns the Godot `canvas`, so that click went through Godot's own Back button, not the DOM handler. It now uses `dispatch_event("click")` on the element. A third comment, asking to guard the Options Back `onclick`, was written against `28c8734`; the guard has been in `custom_shell.html` since `389aae4`.
- **`test_main_menu_audio.gd`, Start burst test:** it marked itself pending when the test profile had unbound critical controls, so such a run couldn't detect a missing guard; and its first-press check could pass if `Globals.next_scene` already held the gameplay path. It now binds every critical action for the keyboard itself (a test key for any action without one) and asserts Start will load the game. The original bindings and device are saved on the test instance and restored in `after_each()`, so they're put back even if the test stops partway (checked by injecting a script error after the bindings change); and it puts a sentinel in `Globals.next_scene` before the first press and asserts the press replaces it with the gameplay path. With a critical action unbound beforehand, the test still runs and passes; with Start setting the flag but never calling the loader (mutant), it fails on the first-press check.
- **CodeRabbit's generated tests (`33aa20e`) and `key_mapping.gd`, freed entry on the menu stack:** CodeRabbit added nine regression tests to `test_audio_web_bridge.gd`, `test_key_mapping_web_overlays.gd` and `test_menu_window_callbacks.gd`. Eight passed. The ninth failed: with a freed entry on top of `Globals.hidden_menus`, `var prev_menu: Node = Globals.hidden_menus.pop_back()` in Key Mapping's Back raised "Trying to assign invalid previously freed instance" and Back stopped there (overlays not updated, callback not cleared, menu not freed). The line predates this PR. Back now pops into a `Variant`, skips freed entries and shows the next valid menu, the same rule as `SettingsMenuBase`; the test (KM-WEB-10) now expects that. The same typed `pop_back()` in nine other places is tracked in #1211. All nine tests were kept and given the suites' IDs and doc format (TC-AWB-17, KM-WEB-10/11, WCB-19 to WCB-24), the callback-suite tests were moved into their menu sections, and the Pause test's comment was corrected (Pause's cleanup runs in `_exit_tree()` during the Main Menu scene change, not inside Resume).

### Other changes in this PR

- **`scripts/resources/weapon_resource.gd`:** docstring update to `get_weapon_name()` from the weekly GDScript docs sync (`fe3276c`, #1209). No code change.
- **`tests/menu_window_callbacks_test.py`:** formatted by DeepSource (Black and isort, `314282b`). No test change.
- **CodeRabbit's generated tests:** committed by CodeRabbit as `33aa20e` (see Review fixes).

---

## Design Decisions

### Part A (#1165)

- **One `eval()` per Back.** `_build_overlay_js()` escapes the IDs and is what `SettingsMenuBase` already uses, so the list and the JS format can't drift from the other settings menus.
- **"Returned to Options" means the popped menu `is OptionsMenu`.** That's the same check Key Mapping already used for focus, so the overlays and focus agree.

### Part B (#1166)

- **Key Mapping guard: track the owner in GDScript, not by comparing callbacks.** Step 4 suggests clearing a callback only if it still belongs to this instance. Comparing `window.controlsBackPressed` with the stored callback can't work: Godot wraps every JS object it reads in a new `JavaScriptObjectImpl` (`_js2variant()` in 4.7.1), so the two never compare equal. Instead, a static `_window_callback_owner_id` records which instance last registered; Back and `_exit_tree()` clear the slot only for that instance. The first version used a per-instance "cleared once" flag, which missed two Key Mappings open at once (see Review fixes). The other menus don't need a guard: Options already tears down once (`_torn_down`), and Main and Pause are freed long before a new instance loads.
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
| This PR                  | 109         | 1,031     | 11,143      | 70                          |

- **Test counts per changed file (`main` → this PR):**

| File                                  | Framework  | Cases                |
|---------------------------------------|------------|----------------------|
| `test_audio_web_bridge.gd`            | GUT        | 14 → 17              |
| `test_key_mapping_web_overlays.gd`    | GUT        | new, 11              |
| `test_menu_window_callbacks.gd`       | GUT        | new, 24              |
| `back_flow_test.py`                   | Playwright | 1 → 2                |
| `menu_window_callbacks_test.py`       | Playwright | new, 4               |
| `scene_transition_lifecycle_test.py`  | Playwright | 6 → 6 (2 rewritten)  |
| `test_main_menu_audio.gd`             | GUT        | 1 → 2                |
| `test_pause_menu.gd`                  | GUT        | 5 → 6                |

- **No test cases removed.**
- **The checkbox to "update the existing `restore_options_menu_dom()` test" in #1165:** no such test existed anywhere in `test/`. TC-AWB-15 and TC-AWB-16 are new.
- **Suites the issues name:** `navigation_to_audio_test.py`, `difficulty_flow_test.py`, `back_flow_test.py`, `scene_transition_invariants_test.py`, `scene_transition_lifecycle_test.py`, `no_error_logs_test.py` (Playwright), `test_gameplay_settings_lifecycle.gd`, `test_pause_menu.gd`, `test_main_menu_audio.gd` and the Key Mapping suites (GUT) all pass.
- **Mutation checks:**
  - Without the Key Mapping owner check, WCB-08, WCB-16 and WCB-17 fail.
  - Without the Start guard, `test_start_burst_requests_one_transition` and PW-TRANS-03 fail (3 accepted requests).
  - Without the Pause out-of-tree guard, PM-06 and PW-TRANS-04 fail.
  - With Key Mapping's old typed `pop_back()`, KM-WEB-10 fails on the freed-instance error.
  - Without Key Mapping's `_exit_tree()`, WCB-07 fails.
  - With Key Mapping's old hand-written list, 3 of the 4 KM-WEB cases fail.
- **Full GUT suite:** 1,031/1,031, same 3 warnings as `main`.
- **gdUnit4 suite (local, set up as `gdunit4_tests.yml` does):** 164/164, including `test_options_teardown.gd`, which drives the Options exit handler.
- **Full Playwright Core Web Flows:** 70 passed, including the 5 new tests and the 2 rewritten ones.
- **CI & Security shard (local):** 1,122 of 1,123 pass. `test_salt_injection.py::test_injection_readonly_file` fails only because the sandbox runs as root, which can write read-only files; it passed in CI on the last PR.
- **GDScript lint and format:** `gdlint scripts` and `gdformat --check scripts` pass.
- **PR run:** _fill in after CI._

---

## Known Limitations / Follow-ups

- **Two more overlay handlers can throw on a second click.** Options Back is now guarded (see Review fixes). Start (`start-button`) and Controls → Back (`controls-back-button`) still call `window.*` unguarded, and their menus clear those callbacks on the same press, so a second click in the same frame throws a `TypeError` in the console. The other handlers only hide their menu, so their callbacks stay set. No test clicks that fast. Making all handlers null-safe belongs with the JS separation work (#1184).

- **Main and Pause still call `JavaScriptBridge` directly,** so their GUT tests can't run the real web registration. They inject the window and seed the callback refs that `_ready()` stores on web; Playwright PW-CB-01 covers the real path.
- **Options can open a second Key Mapping.** `_open_sub_menu()` has no guard against a repeated `controlsPressed` call. Hiding Options doesn't prevent it: `window.controlsPressed` stays callable while Key Mapping is open. The Key Mapping cleanup doesn't depend on a single instance (the slot owner is tracked by instance ID; WCB-16/17, KM-WEB-08), but the second instance also pushes Options onto `Globals.hidden_menus` a second time. Not changed here: only a repeated `window.controlsPressed` call reaches it, and nothing in the game makes one.
- **The same freed-entry pop elsewhere:** `options_menu.gd`, `audio_settings.gd` (2), `advanced_settings.gd` (2) and `globals.gd` (4) still pop `hidden_menus` into a typed `Node`, so a freed entry stops those functions too. Tracked in #1211, which proposes one `Globals.pop_hidden_menu()` helper for all of them.
- **#618 can close** once this merges.

---

## Reviewer's Guide

### File-Level Changes

| Change                        | Details                                                                                                                     | Files                                                                                                                                                             |
|-------------------------------|-----------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| A: Audio → Back restore list. | <ul><li>`OPTIONS_MENU_OVERLAY_IDS` in one `eval()`.</li></ul>                                                               | `scripts/system/audio_web_bridge.gd`                                                                                                                              |
| A: Controls → Back overlays.  | <ul><li>Five Options buttons only when returning to Options.</li><li>`difficulty-slider` no longer shown.</li></ul>         | `scripts/ui/menus/key_mapping.gd`                                                                                                                                 |
| A: Tests.                     | <ul><li>3 GUT cases added, 1 new GUT suite (11 cases).</li><li>1 Playwright test added.</li></ul>                            | `test/gut/test_audio_web_bridge.gd`<br/>`test/gut/test_key_mapping_web_overlays.gd`<br/>`tests/back_flow_test.py`                                                 |
| B: Options callbacks.         | <ul><li>Cleared in `_teardown()`.</li><li>`js_window` member; `Variant` fields.</li></ul>                                   | `scripts/ui/menus/options_menu.gd`                                                                                                                                |
| B: Key Mapping callback.      | <ul><li>New `_exit_tree()`; slot owner tracked by instance ID.</li></ul>                                                    | `scripts/ui/menus/key_mapping.gd`                                                                                                                                 |
| B: Main and Pause callbacks.  | <ul><li>New `_exit_tree()`; `_js_window` member.</li></ul>                                                                  | `scripts/ui/menus/main_menu.gd`<br/>`scripts/ui/menus/pause_menu.gd`                                                                                              |
| B: Tests.                     | <ul><li>1 new GUT suite (24 cases), 1 new Playwright suite (4 tests).</li><li>2 Playwright burst tests rewritten.</li></ul> | `test/gut/test_menu_window_callbacks.gd`<br/>`tests/menu_window_callbacks_test.py`<br/>`tests/scene_transition_lifecycle_test.py`                                 |
| Review fix: Options Back.     | <ul><li>Guarded call, like the Pause handlers.</li></ul>                                                                    | `custom_shell.html`                                                                                                                                               |
| Review fix: exit logs.        | <ul><li>"(left the tree)" exit logs in Key Mapping and Options.</li></ul>                                                   | `scripts/ui/menus/key_mapping.gd`<br/>`scripts/ui/menus/options_menu.gd`<br/>`tests/menu_window_callbacks_test.py`                                                |
| Review fix: Start guard.      | <ul><li>One transition request per Start burst.</li></ul>                                                                   | `scripts/ui/menus/main_menu.gd`<br/>`test/gut/test_main_menu_audio.gd`<br/>`tests/scene_transition_lifecycle_test.py`                                             |
| Review fix: Back re-entry.    | <ul><li>Second Back before the free is ignored.</li></ul>                                                                   | `scripts/ui/menus/key_mapping.gd`<br/>`test/gut/test_key_mapping_web_overlays.gd`                                                                                 |
| Review fix: exit overlay.     | <ul><li>Unexpected exit hides the Back button (owner only).</li></ul>                                                       | `scripts/ui/menus/key_mapping.gd`<br/>`test/gut/test_key_mapping_web_overlays.gd`                                                                                 |
| Review fix: shared Back.      | <ul><li>Older Back leaves a newer instance's button shown.</li></ul>                                                        | `scripts/ui/menus/key_mapping.gd`                                                                                                                                 |
| Review fix: test checks.      | <ul><li>Seeded refs (`Variant` fields), WCB-13 rewritten, no log-level writes.</li></ul>                                    | `scripts/ui/menus/main_menu.gd`<br/>`scripts/ui/menus/pause_menu.gd`<br/>`test/gut/test_menu_window_callbacks.gd`<br/>`test/gut/test_key_mapping_web_overlays.gd` |
| Review fix: BACK-05/06 waits. | <ul><li>Options buttons hidden before Back; no fixed sleeps.</li></ul>                                                      | `tests/back_flow_test.py`                                                                                                                                         |
| Review fix: Options exit.     | <ul><li>Old instance's exit leaves the reopened Options alone.</li></ul>                                                    | `scripts/core/globals.gd`<br/>`test/gut/test_menu_window_callbacks.gd`<br/>`tests/menu_window_callbacks_test.py`                                                  |
| Review fix: Pause burst.      | <ul><li>Main Menu presses after the scene change are ignored.</li></ul>                                                     | `scripts/ui/menus/pause_menu.gd`<br/>`test/gut/test_pause_menu.gd`<br/>`tests/scene_transition_lifecycle_test.py`                                                 |
| Review fix: Options overlays. | <ul><li>Only the owner's Back shows the Options buttons.</li></ul>                                                          | `scripts/ui/menus/key_mapping.gd`<br/>`test/gut/test_key_mapping_web_overlays.gd`                                                                                 |
| Review fix: freed stack entry.| <ul><li>Back skips freed entries (#1211); CodeRabbit's 9 tests tidied.</li></ul>                                            | `scripts/ui/menus/key_mapping.gd`<br/>`test/gut/test_audio_web_bridge.gd`<br/>`test/gut/test_key_mapping_web_overlays.gd`<br/>`test/gut/test_menu_window_callbacks.gd`|
| Docstring sync.               | <ul><li>`get_weapon_name()` return value documented.</li></ul>                                                              | `scripts/resources/weapon_resource.gd`                                                                                                                            |
| Milestone note.               | <ul><li>This note.</li></ul>                                                                                                | `files/docs/milestones/27/Part_18_Restore_the_Options_overlays_after_Back_&_clear_menu_window_callbacks.md`                                                       |

### Assessment against linked issues

| Issue                                                   | Objective                                                             | Addressed | Explanation                                                                               |
|---------------------------------------------------------|-----------------------------------------------------------------------|-----------|-------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1165> | Confirm-first results recorded on the PR                              | ✅         | See Confirm-first results.                                                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1165> | Both Back paths restore exactly the five Options buttons              | ✅         | BACK-05/06 in the browser; TC-AWB-15 and KM-WEB-01.                                       |
| <https://github.com/ikostan/SkyLockAssault/issues/1165> | Both use `OPTIONS_MENU_OVERLAY_IDS` instead of hand-written lists     | ✅         | TC-AWB-15 and KM-WEB-01 compare against `_build_overlay_js(OPTIONS_MENU_OVERLAY_IDS, …)`. |
| <https://github.com/ikostan/SkyLockAssault/issues/1166> | Confirm-first results recorded, for both questions                    | ✅         | See Confirm-first results.                                                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1166> | Every menu that registers `window.*` callbacks clears them when freed | ✅         | PW-CB-01/02 in the browser; WCB-01, 07, 11, 14.                                           |
| <https://github.com/ikostan/SkyLockAssault/issues/1166> | Reopening a menu keeps its callbacks working                          | ✅         | PW-CB-01/02/03/04; WCB-03, 08, 13, 16, 17.                                                |
| <https://github.com/ikostan/SkyLockAssault/issues/1166> | Desktop builds are unaffected                                         | ✅         | Off-web cases WCB-04, 09, 12, 15 and KM-WEB-02; full GUT suite passes.                    |
| Both                                                    | All GUT, Playwright and lint jobs pass, no cases removed              | ⏳         | Pass locally; PR run to confirm.                                                          |
| Both                                                    | The PR's milestone note is added                                      | ✅         | This note.                                                                                |

---

## Contributors

### Human contribution (@ikostan)

- Filed #1165 and #1166 and set their scope, including the confirm-first steps.
- Applied the changes in `6936da5`, generated the `.uid` files and aligned the note's tables.
- Brought in the weekly GDScript docs sync (#1209), including the `get_weapon_name()` docstring (`fe3276c`).

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Planning**
    - Checked that the code #1165 points at was still as described after PR #1206, and found the `restore_options_menu_dom()` test the issue mentions doesn't exist.
  - **Confirm-first**
    - Built the web export as CI does and ran the new Playwright checks on `main`: both #1165 paths and all four #1166 menus were broken as described.
    - Ran question 2 with the simple cleanup and found the Key Mapping same-frame case, then added the guard.
  - **Verification**
    - Ran the full GUT suite, the full Core Web Flows Playwright suite, the CI & Security shard, `gdformat` and `gdlint` locally, and mutation-tested the guard, the new `_exit_tree()` and the overlay list.
    - Wrote this note and the PR description, and checked Sourcery's linked-issues report against #618.
  - **Review fixes**
    - Confirmed CodeRabbit's Options Back finding with a failing DOM-click test (PW-CB-04), guarded the handler, and found which other handlers have the same problem (Start, Controls → Back).
    - Confirmed CodeRabbit's Key Mapping ownership finding with failing tests (WCB-16/17). Replaced the clear-once flag with an instance-ID owner, since comparing the callbacks themselves can't work in Godot.
    - Replaced PW-CB-03's fixed 500 ms waits with waits for the old instances' exit logs, and showed with a mutant build that PW-CB-03 now catches a missing owner check. Checked that the PW-TRANS-01 timing failures seen locally happen with and without this change (machine drift near the 2.5 s limit).
    - Confirmed in Godot 4.7.1's `change_scene_to_node()` that each repeated Start built and discarded a loading screen, added the Start guard, extended PW-TRANS-03 and added a GUT test, and mutation-tested both.
    - Confirmed CodeRabbit's Key Mapping Back re-entry finding with a failing GUT test (KM-WEB-05) and moved the `_intentional_exit` check and set to the start of Back.
    - Confirmed CodeRabbit's unexpected-exit overlay finding (KM-WEB-06), hid the button only while the instance owns the slot, and added KM-WEB-07/08 so hiding on every exit is caught.
    - Confirmed the shared-Back-button finding (WCB-17), and that three test checks couldn't fail (checked that `JavaScriptObject` can't be created off web); seeded the refs, rewrote WCB-13 and mutation-tested the ref drop. Removed the persisted log-level override from the two new suites.
    - Replaced BACK-05/06's fixed sleeps with one condition-based overlay wait, added the "hidden before Back" checks, and showed with two mutant builds that each check catches its bug.
    - Confirmed CodeRabbit's Options exit finding with failing GUT (WCB-18) and Playwright (PW-CB-03) checks, guarded `_on_options_exited_unexpectedly()` without changing its signature, and ran the gdUnit4 suite locally to cover its existing test.
    - Probed the reverse burst in the browser (two `data.tree` errors), added the Pause out-of-tree guard, extended PW-TRANS-04 to fail on Godot errors, added PM-06, and mutation-tested both.
    - Confirmed the Options-overlays-over-a-newer-Key-Mapping finding with a failing GUT test (KM-WEB-09) and gated the overlay show on ownership.
    - Tightened PW-CB-04 (callback state between the clicks, DOM-dispatched click after reopening), showed with a probe that the forced click hit the canvas, and mutation-tested the new check.
    - Reviewed and ran CodeRabbit's nine generated tests, found that one exposed the freed-entry pop in Key Mapping's Back, fixed it, filed #1211 for the other nine places (confirming two with GUT), commented on this PR, and gave the nine tests IDs, docs and their sections.
    - Gave the Start burst GUT test its own keyboard bindings and a first-press sentinel, and checked both against an unbound profile and a mutant that never calls the loader. Moved the input restore into `after_each()` after CodeRabbit's follow-up, and checked it with an injected script error.
- **@sourcery-ai**
  - Wrote the PR summary and Reviewer's Guide.
  - Checked the linked issues: #1165 and #1166 met, apart from CI to check by hand. #618 showed 3 of 10 because its body still listed findings that moved to #1185–#1188.
  - No code review: the 7-day review budget was used up.
- **@deepsource-io / @deepsource-autofix**
  - Static analysis of the Python and JavaScript changes: no issues reported.
  - Formatted `tests/menu_window_callbacks_test.py` with Black and isort (`314282b`).
- **@coderabbitai**
  - Reviewed on request, since it doesn't review this repo automatically.
  - Found that the Options Back overlay handler throws on a second activation after cleanup (fixed, see Review fixes).
  - Found that an older Key Mapping could clear a newer one's `controlsBackPressed` (fixed, see Review fixes).
  - Nitpick: PW-CB-03's fixed 500 ms waits could check the new callbacks before the old cleanup ran (fixed, see Review fixes).
  - Nitpick: PW-TRANS-03 couldn't see repeated Start requests, since only one scene mounts (fixed, see Review fixes).
  - Found that a second Key Mapping Back before the menu is freed popped the menu stack again (fixed, see Review fixes).
  - Found that an unexpected Key Mapping exit left `#controls-back-button` shown without a callback (fixed, see Review fixes).
  - Found that an older Key Mapping's Back hid the newer one's Back button, that WCB-11/13/14 couldn't fail, and that the new suites saved settings through the log-level override (all fixed, see Review fixes).
  - Found that BACK-05/06 never checked the Options buttons were hidden before Back, and slept 500 ms instead of waiting for the restored state (fixed, see Review fixes).
  - Found that the old Options' `tree_exited` handler reset a same-frame reopened Options (fixed, see Review fixes).
  - Found that the Pause menu's Main Menu handler touched `get_tree()` after leaving the tree during a burst (fixed, see Review fixes).
  - Found that an older Key Mapping's Back showed the Options buttons over a newer one (fixed, see Review fixes).
  - Found that PW-CB-04 couldn't tell when cleanup ran and that its forced click bypassed the DOM handler (fixed, see Review fixes).
  - Committed nine regression tests (`33aa20e`); one exposed the freed-entry pop in Key Mapping's Back (fixed here; the rest is #1211).
  - Found that the Start burst GUT test could go pending on an unbound profile and that its first-press check could pass without a request (fixed, see Review fixes).
- **@qodo-code-review:** no review; Qodo reviews are paused.
