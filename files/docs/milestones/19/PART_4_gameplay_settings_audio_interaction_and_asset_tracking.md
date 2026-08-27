# 📝 Gameplay Settings Audio Interaction & Asset Tracking Architecture

This technical document records the architecture, behavioral boundaries,
and runtime asset dependencies introduced by the focus-gated audio
feedback system within the Gameplay Settings menu. This log ensures
long-term system maintainability and guards critical assets against
automated cleanup or build pruning tools.

---

## 🚀 1. UI Architecture & Design Principles

The difficulty adjustment pipeline within `gameplay_settings.gd` utilizes
real-time interactive audio feedback to improve player responsiveness
across native and web-exported platforms. To align with the architectural
design patterns established within the Audio Settings menu, the
implementation operates under a strict **Mute Signal Isolation and
Decoupling Pattern**.

### Core Architectural Axioms

* **Focus-Gated Control:** Audio playback is strictly decoupled from the
  low-level data engine layer. Sound effects are never permitted to fire
  automatically from generic value mutation listeners.
* **Gated Pathway Verification:** Audio execution triggers only when an
  explicit, user-driven interaction vector is authenticated via the viewport
  focus system or a verified external API token.
* **Pipeline Parity:** External interaction vectors (such as HTML5 browser
  overlays via JavaScript) do not duplicate or independently mutate state;
  they route safely into the native internal interaction handling pipeline
  to maintain identical validation rules.

---

## 🔄 2. Interaction Pipelines: Behavioral Division

To maintain deterministic execution states during tests, configuration
restoration, and real-time gameplay updates, the system enforces an absolute
separation between **Interactive Pathways** (audible) and **Silent Pathways**
(programmatic).

### 🟢 Interactive Pathways (Audible Feedback)

The following operations represent intentional human interactions. Each
discrete event must invoke exactly one audio playback event via
`AudioManager.play_sfx("slider")`:

1. **Mouse Interaction:** Dragging or clicking the physical
   `DifficultyHSlider` node bar while the control captures active mouse
   input.
2. **Keyboard & Controller Navigation:** Utilizing the D-Pad, arrow keys,
   or analog controls to shift slider increments while the node possesses
   viewport layout focus (`has_focus()`).
3. **Gameplay Reset Button:** Pressing the layout `ResetButton` control
   element. This bypasses localized focus restrictions by explicitly passing
   an interactive intent flag to reset variables back to default states
   (`1.0`).
4. **Verified JS Overlay Interactions:** Incoming signals from the
   WebAssembly runtime browser layout (`_on_change_difficulty_js()`).
   These bypass localized viewport check gates using an explicit parameter
   token override since external DOM nodes cannot hold local Godot UI focus.

### 🔴 Silent Pathways (Absolute Silence)

The following operations represent programmatic synchronization, lifecycle
state management, or automated testing loops. These blocks **must remain
completely silent** and are protected against audio leakage:

1. **Menu Initialization:** Instantiating the scene container and executing
   `_ready()` loops to synchronize variables with global configuration
   singletons.
2. **Save & Configuration Synchronization:** Real-time data updates loading
   from or saving to disk using the `Globals.settings` configuration
   serialization layer.
3. **External Observer Reactivity:** When the underlying settings resource
   broadcasts a `setting_changed` signal, and the UI reacts inside the
   `_on_external_setting_changed()` hook, it updates layout positions silently.
4. **Recursive Loop Mitigation:** Programmatic updates applied to UI
   controls utilize Godot’s native `set_value_no_signal()` method rather
   than direct property modification, ensuring that layout changes do not
   trigger duplicate handlers or audio signals.
5. **Automated Setup Flows:** Headless test runner executions (such as
   automated GUT unit suites) mocking environment profiles.

---

## 📦 3. Explicit Runtime Asset Dependency Registration

To prevent automated pruning tools, resource optimization scripts, or export
exclusion whitelists from accidentally dropping required audio assets during
project compilation, the explicit relationship mapping below is formally
registered:

### Dependency Mapping Matrix

```text
[Dependent UI Script Component]
 res://scripts/ui/menus/gameplay_settings.gd

       └── Refers to Runtime Identifier: "slider"
       
[Target Live Audio Asset Resource]
 res://files/sounds/sfx/slider.wav

```

### Resource Metadata Definitions

* **Asset Path:** `res://files/sounds/sfx/slider.wav`
* **Import Profile Configuration:** Controlled via tracking metadata
  at `res://files/sounds/sfx/slider.wav.import`.
* **Runtime Deployment Target:** Mapped to the
  `AudioConstants.BUS_SFX_MENU` mixer channel backend through the
  centralized pool allocation routing configuration.

---

## 🛡️ 4. Asset Protection & Pruning Safeguards

The sound asset `slider.wav` is flagged as an **actively referenced
runtime gameplay UI dependency**.

### Maintenance Directives for Future Contributors

* **Exclusion from Optimization Suites:** This file **is unsafe to remove**
  or exclude during asset compression passes, engine pruning commands, or
  build export optimization cycles.
* **No Direct File Tracing Checks:** Pruning tools checking files strictly
  via direct script `load()` or `preload()` paths will miss this asset, as
  it is requested dynamically through an abstraction layer string identifier
  (`"slider"`). Do not delete this asset based solely on a lack of static
  reference lines inside the codebase.
* **Deprecation Protection:** If the Gameplay Settings menu layout is
  altered in future refactors, this asset must remain preserved in storage
  unless all focus-gated slider workflows across the option menus are
  completely eliminated.

---

## ⚠️ 5. Regression Prevention Notes

When engineering updates or extending features under this layout ecosystem,
future developers must respect these defensive constraints to prevent
breaking system stability:

1. **Why Generic `value_changed` Signals Cannot Play Audio:**
Attaching an audio hook directly to a standard slider signal creates an
immediate architectural loop vulnerability. Because code modifications to a
slider's layout re-trigger its `value_changed` signal, programmatic setups
(like reading a save file) will cause sound effects to blast during
initialization or lock the loop into infinite recursion.
2. **Why JS Overlays Require Explicit Intent Passing:**
When a game export is displayed in a browser canvas, clicking an HTML overlay
button interacts directly with the page DOM, meaning Godot's localized
viewport focus tracking returns `false`. By adding
`is_interactive: bool = false` parameter, the web overlay can cleanly
override the focus gate token, ensuring identical state behavior without
splitting the pipeline into separate logic wrappers.
3. **Why Headless Audio Isolation Matters:**
Automated unit tests running inside headless CI/CD systems run without
physical audio server drivers or sound hardware cards. Isolating audio calls
into guarded blocks checking for a valid `AudioManager` prevents testing
environments from crashing due to null pointer engine executions.

---

### 📝 Acceptance Criteria Verification Status

* [x] Gameplay Settings audio interaction behavior is documented.
* [x] Focus-gated interaction architecture is documented.
* [x] Silent synchronization behavior is documented.
* [x] JS overlay interaction routing behavior is documented.
* [x] Explicit dependency mapping to `slider.wav` is recorded.
* [x] Asset pruning protection notes are added.
* [x] Documentation reflects actual runtime implementation behavior.
* [x] Future contributors can identify the dependency relationship without
  code tracing.

---

## 🔍 6. Reviewer's Guide

Implements focus-gated audio feedback for the gameplay difficulty slider,
adds helper APIs on the AudioManager, introduces GUT tests to validate
interactive vs programmatic behavior, and documents the new audio
interaction architecture and related CI maintenance work.

### File-Level Changes

<!-- markdownlint-disable MD013 MD033 table-column-style -->
| Change                                                                                                                                 | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Files                                                                                                                                                                                           |
|----------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Gate difficulty slider SFX behind focus/interaction checks and ensure reset and JS paths are treated as interactive.                   | <ul><li>Extend _on_difficulty_value_changed to accept an is_interactive flag defaulting to false.</li><li>Determine slider focus state and compute a should_play_audio flag based on focus or the interactive override.</li><li>Invoke a new_play_slider_sfx helper when audio should play, and route reset button and JS callbacks through the handler with the interactive flag set to true.</li><li>Add an AudioManager presence/method check in _play_slider_sfx to avoid crashes in headless/test environments and log when unavailable.</li></ul>                 | `scripts/ui/menus/gameplay_settings.gd`                                                                                                                                                         |
| Expose AudioManager pool inspection and control helpers used by tests.                                                                 | <ul><li>Add is_any_sfx_playing to report whether any pooled AudioStreamPlayer is currently playing.</li><li>Add get_active_sfx_playback_count to count active SFX channels.</li><li>Add stop_all_sfx to stop playback and clear streams on all pooled AudioStreamPlayers.</li></ul>                                                                                                                                                                                                                                                                                      | `scripts/managers/audio_manager.gd`                                                                                                                                                             |
| Add GUT tests covering gameplay settings audio behavior across interactive, programmatic, reset, and JS paths with safe audio mocking. | <ul><li>Instantiate the gameplay settings scene with a deterministic Globals.settings and a real or dummy AudioManager.</li><li>Provide helper methods to clear SFX, query if sound is playing, and use AudioManager’s new APIs.</li><li>Test that initialization and programmatic changes are silent, interactive/focused and JS override paths play audio, reset emits exactly one SFX, and malformed JS inputs do not change difficulty or play sound.</li><li>Introduce a DummyAudioManager class to satisfy test calls when the real autoload is missing.</li></ul> | `test/gut/test_gameplay_settings_audio.gd`<br/>`test/gut/test_gameplay_settings_audio.gd.uid`                                                                                                   |
| Document the gameplay settings audio interaction architecture and CI workflow maintenance for Godot export and Codecov.                | <ul><li>Describe focus-gated vs silent pathways for the difficulty slider, including JS overrides and reset behavior.</li><li>Record the runtime dependency mapping from gameplay_settings.gd to the slider.wav asset and outline asset-pruning safeguards and regression-prevention notes.</li><li>Document CI changes updating the pinned firebelley/godot-export action SHA across workflows and configuring the CODECOV_TOKEN for Codecov uploads, along with a reviewer’s guide and bots/AI contribution notes.</li></ul>                                           | `files/docs/milestones/19/PART_4_gameplay_settings_audio_interaction_and_asset_tracking.md`<br/>`files/docs/milestones/19/PART_3_Update_Godot_export_action_pin_and_configure_Codecov_token.md` |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                                                                                                                                                                       | Addressed | Explanation |
|------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| <https://github.com/ikostan/SkyLockAssault/issues/728> | Implement focus-gated audio feedback for the difficulty slider (using slider.wav via AudioManager) for all intentional user interactions, including focused native UI (mouse/keyboard/controller), reset button, and JavaScript web bridge, while routing JS interactions through the same native handler.                                      | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/728> | Ensure all programmatic and synchronization pathways for the difficulty setting (initialization, config restoration, lifecycle sync, scripted mutations, reopening the menu) remain silent by bypassing the interaction layer and using set_value_no_signal() for UI updates where applicable, with explicit typing on new code paths.          | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/728> | Add automated tests and documentation describing the gameplay settings audio interaction architecture (focus gating, JS routing, silent vs interactive pathways) and explicitly track the dependency on slider.wav.                                                                                                                             | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/729> | Refactor the difficulty slider pipeline so that audio feedback (slider.wav) is only played for verified interactive operations (focused native UI, JS overlay with explicit override, and gameplay reset) while all initialization, restoration, and programmatic synchronizations remain completely silent.                                    | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/729> | Ensure the JavaScript overlay difficulty change path reuses the same internal interaction handler as native UI input, forwarding an explicit interaction override while preserving existing JS validation, bounds checking, and behavior.                                                                                                       | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/729> | Preserve or improve defensive programming practices (instance checks, logging, type and bounds validation) with explicit datatypes for new code, and document and test the new gameplay settings audio interaction behavior.                                                                                                                    | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/730> | Implement a deterministic GUT automated test suite for the difficulty slider audio behavior (initialization silence, focus-gated interaction, silent programmatic updates, reset behavior, JS override path, and invalid JS input) as specified in TC-GUT-DIFF-01 through TC-GUT-DIFF-06.                                                       | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/730> | Align gameplay_settings.gd difficulty slider audio behavior with the specified architecture: audio plays only for verified interactive/focus-gated events (local UI, reset button, JS override) and remains silent for programmatic/synchronization paths.                                                                                      | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/730> | Ensure the test infrastructure is isolation-safe and headless-friendly by providing audio manager helpers and cleanup to prevent audio leakage, race conditions, and dependence on real audio hardware.                                                                                                                                         | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/731> | Document the Gameplay Settings audio interaction architecture and behavior, clearly distinguishing interactive (audible) pathways from silent synchronization pathways, including focus-gated behavior and JS overlay routing, in project documentation.                                                                                        | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/731> | Record an explicit runtime dependency mapping between res://scripts/ui/menus/gameplay_settings.gd and res://files/sounds/sfx/slider.wav, including notes that slider.wav is an active runtime dependency and unsafe to remove during asset cleanup or export optimization, so contributors can identify this without code tracing.              | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/731> | Establish reusable guidance and regression-prevention notes for future interactive UI audio systems, explaining why audio is not attached directly to generic value_changed signals, why synchronization remains silent, why JS overlays require explicit routing, and how this relates to asset tracking (especially for web/CI environments). | ✅         |             |
<!-- markdownlint-enable MD013 MD033 table-column-style -->

### Possibly linked issues

* **#728**: The PR implements the requested focus-gated difficulty slider
  audio behavior, JS bridge routing, reset handling, and validation/tests.
* **#728**: PR directly implements the epic’s difficulty slider audio
  behavior, including focus-gating, JS pathway reuse, and silent sync.

---

## 🤖 7. Bots/AI Contributions Summary for PR #738

This PR implements focus-gated audio feedback for the gameplay difficulty
slider using `slider.wav`, adds supporting utilities to the AudioManager,
introduces a comprehensive GUT test suite, and includes detailed milestone
documentation (including cross-references to recent CI updates). It
received strong support from automated bots and AI tools for code
summarization, documentation refinement, and quality review.

### Automated Bots & AI Tools

* **@sourcery-ai**: Actively contributed to multiple documentation updates
  (co-author on several commits) and provided the primary PR summary.
  Highlighted new features (focus-gated slider audio), enhancements
  (AudioManager utilities for SFX pool control), tests (GUT suite for
  interactive vs. silent paths), and documentation (architecture, asset
  tracking, and CI milestone notes).
* **@coderabbitai**: Delivered a concise summary focusing on new features
  (conditional audio playback for user interactions), expanded test coverage
  (interactive, programmatic, reset, and JS paths), documentation
  improvements, and related chores.
* **@deepsource-io**: Performed automated static code analysis and code
  review across the changes in `gameplay_settings.gd`, `audio_manager.gd`,
  tests, and documentation. Provided an overall grade across Security,
  Reliability, Complexity, and Hygiene categories, along with inline comments
  and a full review report.

These tools enhanced reviewer guidance, ensured documentation completeness,
validated code quality, and helped maintain architectural consistency with
prior audio infrastructure work.

### Human Maintainers

* **@ikostan**: Primary contributor and PR author. Led the full implementation,
  including focus/interaction-gated audio logic in the difficulty slider
  pipeline, AudioManager extensions (`is_any_sfx_playing`, `stop_all_sfx`,
  etc.), safe headless/test helpers, comprehensive GUT test suite (covering
  focus, JS overrides, reset button, and silent programmatic paths),
  DummyAudioManager for test isolation, sequence diagrams, asset dependency
  tracking for `slider.wav`, and milestone documentation tying together audio
  design and CI maintenance.

---
