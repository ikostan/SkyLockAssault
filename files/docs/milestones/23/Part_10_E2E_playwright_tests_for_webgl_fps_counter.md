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

The PR wires the WebGL FPS setting through the production browser overlay and Godot JavaScript bridge, including initialization, synchronization, persistence, reset, and cleanup, then validates the behavior with Playwright tests covering runtime transitions, reload persistence, and fatal-error diagnostics. It also speeds up verified Godot downloads in the test container and documents the work.

### File-Level Changes

| Change                                                                                           | Details                                                                                                                                                                                                                                                                                                                               | Files                                                                            |
|--------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| Adds Playwright coverage for WebGL FPS behavior, persistence, and runtime stability.             | <ul><li>Boots the production WebGL export and waits for Godot/bridge readiness.</li><li>Exercises OFF→ON→OFF transitions through the production overlay and verifies persisted state across two hard reloads.</li><li>Captures console/page errors, coverage, Emscripten filesystem synchronization, and failure artifacts.</li></ul> | `tests/fps_counter_e2e_test.py`                                                  |
| Connects the browser FPS control to Godot state and lifecycle management.                        | <ul><li>Adds the production checkbox and onchange bridge call.</li><li>Initializes, updates, resets, and hides the DOM control with the Advanced Settings menu.</li><li>Registers and unregisters the toggleFps callback while synchronizing the in-engine control and persisted setting.</li></ul>                                   | `custom_shell.html`<br/>`scripts/ui/menus/advanced_settings.gd`                  |
| Improves the test container's Godot download performance while preserving artifact verification. | <ul><li>Installs aria2 and uses parallel downloads for the Godot binary and export templates.</li><li>Retains SHA512 checksum validation before installation.</li></ul>                                                                                                                                                               | `Dockerfile`                                                                     |
| Documents the implementation and review scope for the WebGL FPS bridge and E2E tests.            | <ul><li>Records the covered behavior, file-level changes, and issue objectives.</li></ul>                                                                                                                                                                                                                                             | `files/docs/milestones/23/Part_10_E2E_playwright_tests_for_webgl_fps_counter.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                               | Addressed | Explanation |
|------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/926 | Add Python/Playwright E2E coverage that boots the production WebGL/WASM export, waits for Godot and JavaScript bridge readiness, and exercises the FPS control through the production DOM/JavaScript bridge in both OFF-to-ON and ON-to-OFF directions. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/926 | Verify that FPS state changes are observable in the running application and persist correctly across two hard page reloads using isolated browser state.                                                                                                | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/926 | Detect uncaught JavaScript errors, Playwright page errors, WebGL/WASM or fatal Godot runtime failures, while narrowly allowlisting non-fatal messages and retaining failure diagnostics.                                                                | ✅        |             |

### Possibly linked issues

- **#926**: The PR adds the requested production DOM bridge, Godot synchronization, Playwright coverage, reload persistence checks, and runtime error monitoring.

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
