<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Implement SettingsMenuBase for Standardized Signal & Web Cleanup

---



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

Introduces SettingsMenuBase to consolidate signal, web-overlay, focus, menu-stack, and teardown behavior, migrates Gameplay Settings to the new hooks, and adds regression tests for lifecycle edge cases; the author reports 55 tests passing with a temporary GUT stand-in, so real GUT execution remains required before merge.

### File-Level Changes

| Change                                                                      | Details                                                                                                                                                                                                                                                                                                                                                                                                                      | Files                                                                                     |
|-----------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| Extract shared settings-menu lifecycle behavior into a reusable base class. | <ul><li>Add tracked, idempotent signal connection and disconnection helpers.</li><li>Centralize tree-exit teardown, subclass cleanup hooks, menu-stack restoration, and Back-button re-entrancy handling.</li><li>Centralize web overlay show/hide generation and pause-proof process configuration.</li><li>Provide virtual hooks for menu identity, overlays, focus, restoration behavior, and subclass cleanup.</li></ul> | `scripts/ui/menus/settings_menu_base.gd`<br/>`scripts/core/game_paths.gd`                 |
| Migrate Gameplay Settings to the standardized base-class contract.          | <ul><li>Extend SettingsMenuBase and call its common setup from _ready().</li><li>Replace local signal guards and exit cleanup with safe_connect() and base teardown.</li><li>Declare gameplay overlay IDs and implement focus, menu-name, restoration, and cleanup hooks.</li><li>Delegate Back handling to _go_back() while retaining JavaScript callback registration and removal.</li></ul>                               | `scripts/ui/menus/gameplay_settings.gd`                                                   |
| Expand exit-path coverage and add isolated base-class tests.                | <ul><li>Update gameplay exit tests for cross-platform restoration and idempotent teardown.</li><li>Add regression coverage for duplicate Back events, signal safety, cleanup ordering, overlay generation, stale stack entries, and settings-resource preservation.</li><li>Use a dynamically generated probe subclass with injected JavaScript and OS doubles to test the base independently.</li></ul>                     | `test/gut/test_gameplay_settings_exit_paths.gd`<br/>`test/gut/test_settings_menu_base.gd` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                 | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/480 | Create a reusable SettingsMenuBase extending Control that centralizes safe signal cleanup, web overlay updates, hidden-menu stack navigation, focus management, and intentional/unexpected exit handling. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/480 | Refactor gameplay_settings.gd to inherit from SettingsMenuBase while preserving its behavior and avoiding changes to Globals.settings data structures.                                                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/480 | Add tests covering cleanup ordering, idempotent subclass cleanup, _intentional_exit semantics, and Globals.hidden_menus behavior on both Back-button and unexpected tree-exit paths.                      | ✅        |             |

### Possibly linked issues

- **#480**: PR directly implements issue #480's requested SettingsMenuBase and preserves tested Back and unexpected-exit behavior.
- **#480**: The PR directly implements issue #480's lifecycle teardown requirements and adds tests covering callback cleanup, stack restoration, and web cleanup.

---



---

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
