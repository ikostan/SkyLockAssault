<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# E2E playwright tests for webgl fps counter

---

## PR #943 Summary: E2E Playwright tests for WebGL FPS counter

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `e2e-playwright-tests-for-webgl-fps-counter` → `main`  
**Linked Issue:** #926 ([FEATURE] E2E Playwright Tests for WebGL FPS Counter)  
**Milestone:** Milestone 23 – Settings Architecture & FPS Counter Implementation  
**Labels:** web, CI/CD, python, QA, playwright

### Purpose

Wire the production WebGL FPS toggle through the browser DOM ↔ Godot JavaScript bridge into persistent settings, and lock the behavior with Playwright end-to-end tests (runtime transitions, hard-reload persistence, and clean browser/engine execution).

### Core Improvements

#### 1. Web FPS bridge (`custom_shell.html` + `advanced_settings.gd`)

- FPS checkbox overlay in the web Advanced Settings UI
- `window.toggleFps` bridge callback registered/unregistered with menu lifecycle
- Initialize DOM control from `Globals.settings.show_fps`
- Sync in-engine checkbox, persist on change, handle reset / leave-menu cleanup
- Robust JS argument parsing (arrays, string `"true"`/`"false"`, booleans; empty-payload guards)

#### 2. Playwright E2E (`tests/fps_counter_e2e_test.py`)

- Boot production WebGL/WASM export; wait for Godot + JS bridge readiness
- Exercise **OFF → ON → OFF** through the production overlay
- Verify persistence across **two hard page reloads** (isolated browser state)
- Monitor uncaught JS / page errors and fatal WebGL/WASM/Godot failures (narrow non-fatal allowlist)
- IDBFS / Emscripten filesystem sync before reload assertions
- Coverage collection and failure diagnostics (screenshots, HTML, console logs)

#### 3. Test container download speed (`Dockerfile`)

- Install **aria2**; use `aria2c -x 16 -s 16` for Godot **4.7.1** binary and export templates
- Official godot-builds release URLs
- Retain **SHA512** verification, extract, and cleanup steps

#### 4. Documentation

- Milestone doc: `files/docs/milestones/23/Part_10_E2E_playwright_tests_for_webgl_fps_counter.md`

### Benefits

- Web players can toggle the FPS counter from the browser UI with state that survives reloads
- DOM, in-engine control, and persisted config stay synchronized
- Production-path E2E coverage for the Milestone 23 FPS feature on WebGL
- Faster, still-verified Godot downloads in the test image

### Status Notes

Addresses #926: production DOM/bridge exercise, observable runtime state, dual hard-reload persistence, and fatal-error monitoring with diagnostics under Milestone 23.

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

## PR #943 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (including web-feature guards for JS bridge setup on non-Web platforms, and IDBFS persistence wait timing in E2E tests).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the WebGL FPS bridge, Playwright E2E suite, and Docker download changes.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@deepsource-autofix**  
  Authored automated style/format commits (`style: format code with Black and isort`).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **~59.90%**; patch coverage lower on web-bridge paths; review of missing lines requested).

- **@copilot** (GitHub Copilot)  
  Co-authored commits for JS array/string parsing in the FPS toggle callback and improved FPS E2E logging/failure diagnostics.

> **Note:** **@dependabot** did not author commits or leave reviews on this PR (no dependency-bump activity observed).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Wired the WebGL FPS overlay control (`custom_shell.html`) through the Godot JS bridge to persistent `show_fps` settings in Advanced Settings; added Playwright E2E coverage for OFF↔ON transitions, hard-reload persistence, console/fatal-error monitoring, IDBFS sync, and failure artifacts; hardened callback argument parsing and empty-payload guards; sped up verified Godot 4.7.1 downloads in the test container via **aria2** parallel transfers; and documented the work under Milestone 23 (`Part_10_E2E_playwright_tests_for_webgl_fps_counter.md`).

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
