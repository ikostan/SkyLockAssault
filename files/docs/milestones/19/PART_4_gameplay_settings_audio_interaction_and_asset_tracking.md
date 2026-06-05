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

### Core Architectural Axioms:

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
   broadcasts a `setting_changed` signal, the UI reacting inside
   `_on_external_setting_changed()` hooks updates layout positions silently.
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

### Resource Metadata Definitions:

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

### Maintenance Directives for Future Contributors:

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
