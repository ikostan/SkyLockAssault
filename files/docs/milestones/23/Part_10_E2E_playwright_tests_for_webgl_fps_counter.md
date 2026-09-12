<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# 

---



---

## Reviewer's Guide

This PR wires the WebGL FPS control through the browser overlay and Godot JavaScript bridge, then validates toggling, state synchronization, encrypted persistence, reload behavior, and clean runtime execution with Playwright E2E tests; the CI image also switches verified Godot downloads to parallel aria2c transfers.

### File-Level Changes

| Change                                                                                                                                             | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Files                                                           |
|----------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------|
| Adds Playwright end-to-end coverage for the WebGL FPS setting, including runtime toggling, persistence, reload behavior, and failure diagnostics.  | <ul><li>Adds tests for WebGL startup, JS bridge readiness, OFF/ON/OFF transitions, console errors, and persisted state across two hard reloads.</li><li>Adds console/page-error monitoring, engine-specific allowlists, V8 coverage collection, Emscripten filesystem synchronization, and failure artifacts.</li><li>Uses the production HTML checkbox and JavaScript bridge to exercise the setting.</li></ul>                                                                          | `tests/fps_counter_e2e_test.py`                                 |
| Connects the WebGL FPS checkbox to the Godot advanced-settings implementation and keeps DOM, in-engine state, and persisted settings synchronized. | <ul><li>Adds the DOM checkbox and onchange callback that invokes window.toggleFps.</li><li>Registers and unregisters the Godot JavaScript callback, initializes the overlay from Globals.settings.show_fps, and hides it on menu exit.</li><li>Updates the Godot CheckButton and settings persistence when JavaScript receives toggle values, including handling bridged arrays, strings, and booleans.</li><li>Synchronizes the DOM checkbox when advanced settings are reset.</li></ul> | `custom_shell.html`<br/>`scripts/ui/menus/advanced_settings.gd` |
| Optimizes Godot and export-template downloads used by the test container while retaining checksum verification.                                    | <ul><li>Installs aria2 and replaces wget downloads with parallel aria2c downloads from the godot-builds release location.</li><li>Continues validating downloaded artifacts with the official SHA512 sums before installation.</li></ul>                                                                                                                                                                                                                                                  | `Dockerfile`                                                    |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                  | Addressed | Explanation |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/926 | Add Playwright E2E coverage that boots the production WebGL/WASM export, waits for Godot and JavaScript bridge readiness, and exercises the FPS toggle through the production DOM/JavaScript bridge in both OFF-to-ON and ON-to-OFF directions.                                            | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/926 | Verify that FPS setting changes are observable in the running application and persist correctly across two hard page reloads, with isolated browser state.                                                                                                                                 | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/926 | Monitor browser and Godot/WebGL runtime output during startup, interaction, and reloads, failing on uncaught JavaScript errors, pageerror events, initialization failures, and other fatal errors while narrowly allowing documented non-fatal messages and retaining failure diagnostics. | ✅        |             |

### Possibly linked issues

- **#926**: PR directly implements issue #926's requested Playwright tests, FPS DOM bridge, runtime toggling, reload persistence, and error monitoring.

---



---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
