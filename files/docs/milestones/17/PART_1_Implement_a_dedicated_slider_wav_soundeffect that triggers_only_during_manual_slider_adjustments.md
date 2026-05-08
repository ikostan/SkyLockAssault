# Milestone 17, Part #1

## **PR Summary: Audio Pipeline, UI Safety, and Test Suite Hardening**

![image][pr-image]

[pr-image]: https://github.com/user-attachments/assets/11c621d7-f78a-44db-b944-37091f64f6d8

### Bug Fixes & UX Safety

* **Invalid Bus Guard:** Added defensive initialization to `VolumeSlider`. If an
  invalid or typoed `bus_name` is detected (`bus_index == -1`), the component
  safely aborts, disables the UI (`editable = false`), and drops mouse/keyboard
  focus (`MOUSE_FILTER_IGNORE`, `FOCUS_NONE`) to prevent silent runtime crashes.
* **Stuck Drag State Resolution:** Implemented a `_notification` listener in
  `VolumeSlider` to catch `NOTIFICATION_FOCUS_EXIT` and
  `NOTIFICATION_WM_WINDOW_FOCUS_OUT`. This guarantees the `_is_dragging` flag
  safely resets even if the system loses focus (e.g., Alt-Tabbing) before a
  mouse release event fires.
* **Accurate Delta Tracking:** Reordered the `_previous_value` assignment inside
  `_handle_slider_sfx` to execute *after* interaction guards. This ensures rogue
  programmatic updates don't artificially advance the delta tracker and swallow
  genuine manual user interactions.

### Performance & Architecture Optimizations

* **Audio Object Pooling:** Refactored `AudioManager` to instantiate a reusable
  pool of `AudioStreamPlayer` nodes (default size 8) on `_ready`. This completely
  eliminates the severe CPU and memory fragmentation churn caused by constantly
  calling `.new()` and `queue_free()` on rapid slider drags.
* **Missing File Caching:** Implemented `_missing_sfx_cache` in `AudioManager`.
  If an audio file fails to load once, the system flags it and short-circuits
  future requests, preventing massive disk I/O spikes and log spam.
* **Sub-Epsilon Jitter Gating:** Added early-return `is_equal_approx` checks at
  the very top of both `_on_value_changed` and `set_value_programmatically`.
  This prevents redundant `AudioServer` backend calculations and stops the
  debounced disk-save timer from spinning up due to micro-jitters from
  controllers or float rounding.
* **Component Encapsulation:** Added public getters (`get_previous_value()`,
  `get_last_sfx_time()`, `is_user_dragging()`) to `VolumeSlider` to allow the
  test suite to validate logic without directly accessing private, underscored
  variables.

### Test Suite Hardening (GUT & GdUnit4)

* **Cross-Suite Leakage Prevention:** Implemented a strict state
  snapshot-and-restore pattern for the `AudioManager` singleton across
  `before_each` and `after_each` lifecycle methods. This isolates test
  environments and prevents stray `user://` disk writes during CI runs.
* **Deterministic Rate-Limit Testing:** Patched flaky CI test runs by forcing
  `_last_sfx_time` artificially into the future, guaranteeing the cooldown guard
  triggers mathematically regardless of thread pauses or garbage collection
  spikes.
* **I/O Mocking:** Replaced live audio playback in tests with a custom,
  duck-typed inline `MockAudioManager` class. This allows the suite to verify
  interaction logic and signal paths instantly without touching the disk or
  generating audio noise.
* **GdUnit4 Registry Bypass:** Explicitly preloaded script resources for test
  initialization to bypass known `class_name` registry parsing bugs in the
  GdUnit4 runner.

---

## Summary by @sourcery-ai & @coderabbitai

Add a dedicated, rate-limited slider sound effect and central SFX playback API
while hardening audio/UI synchronization to avoid feedback loops and noisy
saves.

**New Features:**

* Introduce a dedicated slider UI sound routed through a centralized
  `AudioManager.play_sfx` API with caching and pooling.
* Add a programmatic `VolumeSlider` update API that suppresses sound effects and
  debounced saves for non-interactive changes.
* Define audio constant IDs for common UI sounds like slider, mute toggle, and
  navigation to standardize SFX usage.
* Added slider audio sample and audible feedback for slider interactions
  (@espanakosta-jpg).

**Bug Fixes:**

* Prevent double UI sounds when adjusting focused sliders with keyboard
  navigation inputs.
* Avoid audio spam by rate-limiting slider SFX, ignoring redundant value
  changes, and blocking interactions on invalid audio buses.
* Decouple programmatic volume updates from slider signals and DOM sync to
  prevent audio feedback loops and unnecessary disk writes.

**Enhancements:**

* Refine `VolumeSlider` behavior to track interaction state, guard invalid
  buses, and debounce settings persistence more safely.
* Add SFX caching and an `AudioStreamPlayer` pool in `AudioManager` to reduce
  disk I/O and node churn for UI sounds.
* Document the refactored scripts directory layout and current milestones in the
  README for easier project navigation.
* Centralized SFX playback with caching and validation; added SFX asset IDs.
* Slider refined: programmatic updates avoid side effects; user changes are
  debounced, rate-limited, and suppress navigation sounds when adjusting.

**Tests:**

* Add GUT test coverage for `VolumeSlider` initialization, programmatic guards,
  SFX interaction, and rate-limiting behavior.
* Add GUT tests ensuring audio UI sync from global events and `AudioManager`
  updates bypasses slider signals and debounce timers.
* Add GUT tests validating one-way DOM sync in `AudioWebBridge` to prevent
  HTML-driven feedback into the engine.
* New unit tests covering audio/UI sync, web bridge DOM sync, and slider UX.

---

## Reviewer's Guide

Implements a dedicated, rate-limited slider SFX and central SFX playback API,
refines `VolumeSlider` to distinguish manual vs programmatic updates and handle
invalid buses, suppresses duplicate navigation sounds when keyboard-adjusting
sliders, documents the `scripts/` layout and milestones, and adds GUT tests to
ensure audio/UI/web sync without feedback loops.

### File-Level Changes

<!-- markdownlint-disable line-length -->
| Change                                                                                                                                             | Details                                                                                                                                                                                                                                                             | Files                                                                                          |
|----------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------|
| Refine `VolumeSlider` to gate SFX to genuine user interactions, debounce saves, support safe programmatic updates, and handle invalid audio buses. | Add SFX cooldown, previous-value, and drag-state tracking. Connect input handlers for focus loss. Introduce `set_value_programmatically`. Ensure `_on_value_changed` ignores jitter and plays gated SFX. Guard against invalid bus names. Expose getters for tests. | `scripts/ui/components/volume_slider.gd`                                                       |
| Introduce centralized, cached SFX playback in `AudioManager` for UI sounds.                                                                        | Define constants for SFX directory, cache size, and pool size. Initialize `AudioStreamPlayer` pool in `_ready`. Cache loaded and missing SFX streams to reduce I/O. Implement `play_sfx` API with LRU eviction and bus validation.                                  | `scripts/managers/audio_manager.gd`                                                            |
| Add audio constants for common UI SFX IDs and clarify bus naming.                                                                                  | Add `SFX_SLIDER`, `SFX_MUTE_TOGGLE`, and `SFX_UI_NAVIGATION` constants. Group audio bus name constants for clarity.                                                                                                                                                 | `scripts/resources/audio_constants.gd`                                                         |
| Prevent double UI sounds when using keyboard to adjust sliders by suppressing navigation SFX in that context.                                      | Capture focused control in `Globals._input`. Early-return navigation SFX on `ui_left`/`ui_right` when a Slider is focused to prevent duplicate sounds.                                                                                                              | `scripts/core/globals.gd`                                                                      |
| Document `scripts/` directory structure and update milestones in the README.                                                                       | Add DeepSource to tooling list. Document refactored `scripts/` layout. Add status descriptions for Milestones 14 and 16. Clarify architecture and testing status.                                                                                                   | `README.md`                                                                                    |
| Update existing GDUnit4 tests for `VolumeSlider` to use constants and correct slider configuration.                                                | Preload `VolumeSlider` script resource explicitly. Use `AudioConstants` bus names. Configure `max_value` and step in tests. Tighten debounce timer assertions.                                                                                                      | `test/gdunit4/test_volume_slider.gd`                                                           |
| Add GUT tests covering `VolumeSlider` logic, including programmatic guards, SFX gating, rate limiting, and invalid-bus behavior.                   | Create gut `VolumeSlider` suite isolating side effects. Verify initialization, programmatic, and manual updates. Use mock `AudioManager` to assert SFX playback rules and invalid bus behavior.                                                                     | `test/gut/test_volume_slider.gd`, `test/gut/test_volume_slider.gd.uid`                         |
| Add GUT tests to ensure `AudioWebBridge` DOM sync is one-way and does not create feedback loops.                                                   | Introduce `MockOSWrapper` and `MockJSBridgeWrapper`. Instantiate `AudioWebBridge` with mocks. Test one-way volume and mute state changes to DOM via eval.                                                                                                           | `test/gut/test_audio_web_bridge_dom_sync.gd`, `test/gut/test_audio_web_bridge_dom_sync.gd.uid` |
| Add GUT tests to verify audio/UI sync decoupling between `AudioManager`, sliders, and settings scene.                                              | Instantiate audio settings scene and snapshot state. Assert global volume callbacks update sliders via `set_value_no_signal`. Assert `_sync_ui_from_manager` updates sliders without starting debounce timers.                                                      | `test/gut/test_audio_sync_decoupling.gd`, `test/gut/test_audio_sync_decoupling.gd.uid`         |
| Add import metadata for the new slider SFX asset.                                                                                                  | Add `.import` file for `files/sounds/sfx/slider.wav`.                                                                                                                                                                                                               | `files/sounds/sfx/slider.wav.import`                                                           |
<!-- markdownlint-enable line-length -->

### Assessment against linked issues

<!-- markdownlint-disable line-length table-column-style -->
| Issue                                                  | Objective                                                                                                                                                                                                                                                                                                                                    | Addressed |
|--------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|
| <https://github.com/ikostan/SkyLockAssault/issues/456> | Update README.md to document the refactored scripts/ directory structure introduced in the Milestone 16 work, improving project navigation and onboarding.                                                                                                                                                                                   | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/456> | Update README.md milestone documentation to reflect the current status and focus of Milestone 16 (and related recent milestones), so the README serves as an up-to-date hub for tracking project progress.                                                                                                                                   | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/563> | Add a dedicated slider.wav SFX asset and hook it into the audio system via AudioManager and AudioConstants so it can be requested explicitly.                                                                                                                                                                                                | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/563> | Update VolumeSlider so that it plays the dedicated slider SFX only during genuine manual user interactions (mouse drag or focused keyboard adjustments), with rate limiting, while programmatic updates do not trigger SFX or immediate saves.                                                                                               | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/563> | Ensure UI/web-bridge-driven volume sync uses programmatic slider updates that bypass value_changed signals, preventing slider SFX and debounce saves during automated changes.                                                                                                                                                               | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/564> | Add the slider.wav audio file to the project’s SFX sound library so it is imported by Godot and available via the filesystem.                                                                                                                                                                                                                | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/564> | Integrate the new slider.wav sound into the UI so that volume slider interactions use this dedicated sound (instead of the generic navigation SFX), proving the asset is correctly accessible and wired into the audio system.                                                                                                               | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/565> | Add an AudioManager.play_sfx API that plays non-positional SFX with caching, defaulting to the SFX_Menu bus, validating/falling back on invalid buses, and safely handling missing files without crashes.                                                                                                                                    | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/565> | Integrate VolumeSlider to play the dedicated slider SFX via AudioManager.play_sfx only on genuine user interactions (mouse drag / keyboard focus), not on programmatic changes, while routing through the SFX_Menu bus and avoiding performance or feedback-loop issues.                                                                     | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/566> | Connect VolumeSlider to centralized AudioManager.play_sfx("slider") so that manual slider adjustments (mouse drag/click, including when cursor leaves bounds, and keyboard/gamepad when focused) play slider.wav, while programmatic changes do not trigger any SFX.                                                                         | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/566> | Add robust guards around SFX playback in VolumeSlider: a delta guard using _previous_value and is_equal_approx() so no sound plays when the effective value does not change, and rate limiting using Time.get_ticks_msec() with a ~60ms cooldown to throttle sounds during rapid sliding.                                                    | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/566> | Ensure slider feedback respects the SFX_Menu audio path and mute hierarchy by routing through the new AudioManager.play_sfx API (using the SFX_SLIDER ID on the SFX_Menu bus) and by providing a programmatic update path that bypasses value_changed signals to avoid initialization/sync sound storms and unnecessary saves.               | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/567> | Ensure that programmatic volume sync in audio_settings.gd (e.g., in_on_global_volume_changed and_sync_ui_from_manager) updates HSliders via a no-signal path (set_value_no_signal or equivalent) so that slider SFX and debounced saves are not triggered during web/config-driven sync.                                                     | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/567> | Ensure AudioWebBridge updates the HTML DOM directly for volume/mute sync (pure JS property assignment) without causing events/signals that feed back into Godot sliders.                                                                                                                                                                     | ✅         |
| <https://github.com/ikostan/SkyLockAssault/issues/567> | Add automated GUT tests that verify audio sync decoupling: calling the audio settings scene’s _on_global_volume_changed and _sync_ui_from_manager updates the relevant HSlider.value while the save_debounce_timer remains stopped, and add tests validating that AudioWebBridge DOM sync is one-way (JS-only) and does not re-emit signals. | ✅         |
<!-- markdownlint-enable line-length table-column-style -->

### Possibly linked issues

* **#566**: They match: PR wires `VolumeSlider` to `AudioManager.play_sfx` with
  interaction gating, rate-limiting, and programmatic-change guards as
  specified.
* **#FEATURE Verify Signal Decoupling for Web and UI Sync**: They match exactly:
  PR adds `set_value_no_signal`-based sync, DOM-only web updates, and the
  specified GUT decoupling tests.
* **#565**: They both implement a dedicated `slider.wav` sound for manual
  slider changes, excluding automated web-bridge or programmatic updates.

---

Here is a summary of **@ikostan**’s contributions as the author and primary
developer of PR #578:

### Core Feature Implementation

* **Targeted Audio Feedback:** Implemented a dedicated `slider.wav` sound
  effect that triggers exclusively during genuine, manual user interactions
  (e.g., active mouse dragging or keyboard focus), completely silencing
  redundant audio during programmatic UI syncs.

**Architecture & Performance Optimization (`AudioManager`)**

* **Centralized SFX API:** Built a robust `play_sfx` method to handle all
  non-positional UI audio routing safely.
* **Asset Caching:** Implemented an LRU (Least Recently Used) cache for
  audio streams to eliminate disk I/O stutter during gameplay, alongside
  a "missing SFX" cache to prevent the engine from repeatedly attempting
  to load broken file paths.
* **Object Pooling:** Refactored audio playback to utilize a
  pre-instantiated pool of `AudioStreamPlayer` nodes, drastically
  reducing node instantiation churn, CPU overhead, and memory fragmentation.

**UI Component Hardening (`VolumeSlider`)**

* **Decoupled Syncing:** Created the `set_value_programmatically` API to
  safely update slider visuals and backend audio servers without emitting
  the `value_changed` signal, breaking potential audio feedback loops.
* **Audio Spam Prevention:** Engineered a strict 3-tier guard system to
  block audio spam.
* **Guard 1:** Verifying a float-safe delta change.
* **Guard 2:** Validating active user interaction to prevent rogue scripts
  from triggering sounds.
* **Guard 3:** Enforcing a strict 60ms rate limit to protect the user's ears
  during rapid slider movement.

* **Fail-Safes:** Added defensive initialization checks to instantly disable
  the UI component, push editor warnings, and drop focus if an invalid audio
  bus name is detected, preventing silent runtime crashes.

### Test-Driven Reliability (GUT Framework)

* **Comprehensive Coverage:** Wrote extensive unit tests verifying
  initialization, programmatic update guards, and the interaction/rate-limiting
  logic of the `VolumeSlider`.
* **Deterministic CI Strategies:** Ensured time-based tests (like the 60ms
  rate limiter) are completely deterministic by pushing evaluation timestamps
  into the future, preventing flaky failures on slow CI runners.
* **State Isolation:** Implemented strict snapshot-and-restore patterns for
  the `AudioManager` singleton during `before_each` and `after_each` test
  phases to guarantee zero cross-suite state leakage.
* **I/O Mocking:** Designed custom inline mock classes (`MockAudioManager`)
  to intercept and assert audio calls during testing, verifying complex
  state logic without triggering actual sound playback or disk reads.

---

**Summary of the automated and AI-driven contributions to PR #578:**

**@sourcery-ai** Generated the primary PR summary, detailing the new features
(dedicated slider sound effect, `AudioManager.play_sfx` API), bug fixes (audio
spam rate-limiting, fixing feedback loops), and added GUT test coverage.

* Provided architectural feedback, reminding the team to verify if `.import`
  files should be source-controlled and to standardize the SFX folder
  structure (`files/sounds/sfx/`).
* Identified a copy-paste error in the `test_volume_slider.gd` suite and
  suggested adding an early-return short-circuit in
  `VolumeSlider.set_value_programmatically` to prevent redundant backend calls.

### @coderabbitai

* Conducted a detailed code review, specifically identifying a latent
  state-machine bug in `scripts/ui/components/volume_slider.gd`. It noted
  that committing `_previous_value` before the interaction and cooldown
  guards could allow non-interactive programmatic changes to mask real
  user interactions, and provided a refactoring suggestion to fix it.

### @deepsource-io

* Participated in the automated review pipeline to scan for code quality,
  potential anti-patterns, and static analysis issues across the new Godot
  GDScript additions.
