<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Refactor fuel and speed dictionaries

---

## PR #950 Summary: Refactor fuel and speed dictionaries

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)  
**Author:** @ikostan  
**Branch:** `refactor-fuel-and-speed-dictionaries` → `main`  
**Linked Issues:** #276 (StatManager refactor), #946 (define StatManager), #947 (state variables / `_ready`), #948 (warning logic cleanup), #949 (behavioral tests)  
**Milestone:** Milestone 24 – Resource-Driven Data Refactoring & Player Stat Architecture  
**Labels:** enhancement, testing, refactoring

### Purpose

Replace unstructured HUD fuel/speed warning dictionaries and shared helpers with reusable, independently controlled `StatManager` instances—preserving warning thresholds and behavior while making blinking, timers, and colors safer and easier to test.

### Core Improvements

#### 1. `StatManager` inner class (`scripts/ui/hud.gd`)

- Owns a **Label**, **Timer**, base/warning colors, and blinking state
- API: `start_blinking`, `stop_blinking`, `toggle_label`, `is_timer_running`
- Defensive `is_instance_valid` checks for nodes being freed
- Theme-aware color overrides and clean stop/reset behavior

#### 2. Dictionary → manager migration

- Remove `_fuel_state` and `_speed_state` dictionaries
- Add `fuel_stat` and `speed_stat`, constructed in `_ready()` with the correct labels, timers, and colors
- Route fuel/speed warning checks and timer callbacks through the respective managers
- Drop redundant blinking/color helper functions
- Add `get_label_text_color` (or equivalent theme-aware access) where needed
- Null-safe public accessors for fuel-warning, speed-warning, and speed-timer status (safe before HUD init)

#### 3. Tests (`test/gdunit4/test_player.gd`)

- Switch assertions to `fuel_stat` / `speed_stat` (and `toggle_label` / `is_blinking`)
- Prove **independent** threshold transitions (fuel changes do not affect speed warnings and vice versa)
- Cover StatManager lifecycle: start/stop manage flag + timer + colors; repeated toggles alternate base/warning colors
- Fix color assertions for the new theme-aware path

### Benefits

- Clearer, typed ownership of per-stat warning UI state
- Independent fuel vs speed blinking without shared dictionary boilerplate
- Safer cleanup when HUD nodes are invalid or freed
- Stronger regression coverage for Milestone 24 warning invariants

### Status Notes

Addresses the StatManager definition, wiring, helper cleanup, null-safe accessors, and behavioral test updates from #276 / #946–#949 under Milestone 24.

---

## Reviewer's Guide

Refactors HUD fuel and speed warning state from dictionaries into independent StatManager instances that safely manage blinking, timers, and label colors, while expanding tests for isolated threshold transitions and the manager lifecycle.

### File-Level Changes

| Change                                                                                | Details                                                                                                                                                                                                                                                                                                                                                                                                  | Files                                                                   |
|---------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------|
| Encapsulate fuel and speed warning UI state in independent StatManager instances.     | <ul><li>Replace fuel and speed dictionaries with managers owning labels, timers, blinking flags, and colors.</li><li>Move warning activation, cleanup, color toggling, and timer checks into StatManager.</li><li>Initialize separate managers in _ready while preserving existing thresholds and warning behavior.</li><li>Make warning-status accessors null-safe before HUD initialization.</li></ul> | `scripts/ui/hud.gd`                                                     |
| Expand regression coverage for isolated warning transitions and StatManager behavior. | <ul><li>Verify fuel and speed warnings activate and recover independently.</li><li>Update threshold assertions to use the new manager state.</li><li>Test blinking start/stop, timer state, color alternation, and color restoration.</li></ul>                                                                                                                                                          | `test/gdunit4/test_player.gd`                                           |
| Document the refactor, linked implementation goals, and validation scope.             | <ul><li>Record the migration from dictionaries to StatManager instances and the preserved behavior.</li><li>Summarize issue coverage, automated review activity, and test/coverage status.</li></ul>                                                                                                                                                                                                     | `files/docs/milestones/24/Part_1_Refactor_fuel_&_speed_dictionaries.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                        | Addressed | Explanation |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| https://github.com/ikostan/SkyLockAssault/issues/276 | Define a typed inner StatManager class in hud.gd that encapsulates label references, timer state, blinking behavior, color toggling, and defensive handling of invalid nodes.                                                                                                                    | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/276 | Replace the _fuel_state and _speed_state dictionaries and remove redundant HUD blinking/color helpers while routing fuel and speed warning checks and timer callbacks through independent StatManager instances.                                                                                 | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/276 | Provide null-safe HUD status accessors and update tests to validate warning thresholds, independent fuel/speed behavior, and the StatManager blinking lifecycle without regressions.                                                                                                             | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/946 | Define a typed `StatManager` inner class in `hud.gd` that encapsulates blinking state, label colors, timer handling, and safe start, stop, toggle, and timer-running operations.                                                                                                                 | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/947 | Remove the legacy _fuel_state and _speed_state dictionary variables from hud.gd and replace them with typed fuel_stat and speed_stat StatManager variables.                                                                                                                                      | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/947 | Instantiate fuel_stat and speed_stat in _ready() with the appropriate labels, blink timers, base text colors, and warning colors.                                                                                                                                                                | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/948 | Remove the legacy HUD warning helpers (`start_blinking()`, `stop_blinking()`, `_toggle_label()`, and `set_label_text_color()`) after verifying that their callers are migrated or otherwise supported.                                                                                           | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/948 | Refactor fuel and speed warning checks and timer callbacks to use independent `StatManager` instances for starting, stopping, and toggling blinking.                                                                                                                                             | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/948 | Make `is_fuel_warning_active()`, `is_speed_warning_active()`, and `is_speed_timer_running()` null-safe when queried before HUD initialization.                                                                                                                                                   | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/949 | Update the HUD tests to use the new StatManager object syntax instead of the removed fuel and speed state dictionaries.                                                                                                                                                                          | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/949 | Add behavioral tests covering the StatManager blinking lifecycle: starting blinking sets the blinking flag, starts the timer, and applies the warning color; stopping clears the flag, stops the timer, and restores the base color; repeated toggles alternate between warning and base colors. | ✅        |             |
| https://github.com/ikostan/SkyLockAssault/issues/949 | Validate independent fuel and speed warning behavior, including threshold entry and recovery affecting only the corresponding statistic.                                                                                                                                                         | ✅        |             |

### Possibly linked issues

- **#276**: The PR directly implements the issue’s requested inner StatManager refactor, helper removal, null-safe accessors, and behavioral tests.
- **#948**: PR directly implements issue 948 by migrating warning logic to StatManager, removing old helpers, and adding null-safe accessors.
- **#947**: The PR directly implements the issue by replacing dictionaries and constructing fuel_stat and speed_stat in _ready().

---

## PR #950 Summary: Bots / AI Contributions

### AI / Bot Contributors

- **@sourcery-ai**  
  Generated the PR summary and Reviewer’s Guide. Performed code review (including feedback that tests still referenced removed `_fuel_state` / `_speed_state` and `_toggle_label` APIs).

- **@coderabbitai**  
  Generated the PR summary, walkthrough, and poem. Reviewed the StatManager refactor and advised updating tests to use `fuel_stat` / `speed_stat` and `toggle_label()`.

- **@deepsource-io**  
  Performed automated DeepSource Code Review and published a PR Report Card (Security / Reliability / Complexity / Hygiene).

- **@codecov**  
  Posted the Codecov coverage report on the PR (project coverage **60.02%**, **+0.14%** vs base; patch coverage **~79.6%** with 10 lines missing in `hud.gd`; all tests successful).

- **@copilot** (GitHub Copilot)  
  Co-authored the commit introducing the `StatManager` class for HUD warning blinking.

> **Note:** **@dependabot** did not author commits or leave reviews on this PR (no dependency-bump activity observed).

### Human Contributor

- **@ikostan**  
  Primary author of the PR. Introduced the typed inner `StatManager` in `hud.gd`; replaced `_fuel_state` / `_speed_state` dictionaries with independent `fuel_stat` and `speed_stat` instances; centralized blinking, timer, and theme-aware color logic; removed legacy helpers; added null-safe status accessors; and expanded GdUnit4 coverage for independent fuel/speed threshold transitions and StatManager lifecycle behavior under Milestone 24.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
