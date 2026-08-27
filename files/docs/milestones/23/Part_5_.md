# Web scene transition latency, GPU acceleration detection and loading screen refactor
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

## PR #910 Summary: Web scene transition latency, GPU acceleration detection & loading screen optimization

**Repository:** [ikostan/SkyLockAssault](https://github.com/ikostan/SkyLockAssault)

**Author:** @ikostan

**Branch:** `fix-web-scene-transition-latency-and-loading-screen-freeze` → `main`

**Linked Issues:** #829 (Web export loading screen hangs at 80% and 90% during scene transitions)

**Milestone:** Milestone 23 – Settings Architecture & FPS Counter Implementation

**Labels:** bug, web, performance, GUI, refactoring, QA, ux

### Purpose

Diagnose and resolve the multi-second loading screen freeze observed during scene transitions in HTML5/WebGL exports, harden the web shell against browser-level software rasterization (`SwANGLE`), and refactor `loading_screen.gd` to eliminate artificial progress-bar stalls while introducing predictable visual pacing.

---

### Core Improvements

#### 1. Performance Profiling & Root Cause Isolation (`Trace-20260827T115425.json`)

* **Trace Analysis:** DevTools performance recording revealed that **10,628.7 ms (73.2%)** of the 11-second transition freeze was consumed by the browser's **`Commit`** phase and GPU process queue flushing, whereas Godot engine iteration (`MainLoop_runner`) accounted for only **2,604.5 ms (17.9%)**.
* **Root Cause:** Browser graphics hardware acceleration was disabled in client settings (`chrome://gpu`), forcing Chromium into CPU software emulation via **`SwANGLE`** over the `Microsoft Basic Render Driver`. The CPU was bottlenecked attempting to software-rasterize WebGL calls and compile shaders during scene initialization.
* **Verification:** Re-enabling hardware acceleration in browser settings eliminated the 10.6-second `Commit` lock and returned scene transition times to sub-second speeds.

#### 2. Pre-Boot GPU Detection & Warning Modal (`custom_shell.html`)

* Added an auto-executing WebGL context query before engine initialization inspecting `WEBGL_debug_renderer_info`.
* Detects known CPU software rasterizers (`SwiftShader`, `llvmpipe`, `Software Rasterizer`, `Microsoft Basic Render Driver`).
* Renders an accessible, centered modal dialogue over a full-screen dimmed backdrop (`rgba(30, 30, 30, 0.85)`):
* Centered warning header and icon (`⚠️ Performance Warning`).
* Left-aligned explanatory notice advising the player to enable Hardware Acceleration in browser settings.
* Centered confirmation button (`"I Understand / Continue"`) to dismiss the modal and proceed to the game.

#### 3. In-Engine Lifecycle Telemetry & Benchmark

* Implemented microsecond-precision timing hooks across the scene transition lifecycle:
* **`.instantiate()` Latency:** **13 ms**
* **Tree Insertion & `_ready()` Callbacks:** **28 ms** (including dynamic weapon loading, rotor startup, fuel initialization, HUD signal binding, and pause menu instantiation)
* **Total Scene Swap Overhead:** **41 ms total**
* Conclusively proved that node allocation, script compilation, and child scene instantiation are not bottlenecks under WebAssembly.

#### 4. Progress Smoothing & Transition Pacing (`loading_screen.gd`)

* **Linear Progress Movement:** Replaced frame-rate dependent `lerp(..., 0.1)` with delta-scaled `move_toward(loader_progress, target_progress, delta * 120.0)` to eliminate asymptotic slow-motion crawls between 80% and 99%.
* **Reduced Artificial Delays:** Lowered `min_load_time` from `3.0s` to `0.3s` (`0.2s` for native), preventing fast loads from stalling at 80%–90%.
* **Intentional 1.0s Completion Hold:** Added `await get_tree().create_timer(1.0).timeout` once the progress bar visually fills to 100%, giving players clear visual confirmation of completion before entering gameplay.
* **Architecture Validation:** Verified that multi-threaded Web export (Config A) and synchronous sub-scene loading (`res://scenes/bullet.tscn`) perform within acceptable thresholds (<15 ms) without requiring matrix bypasses or structural refactoring.



---

### Benefits

* **Instant Scene Transitions:** Resolves the 11-second transition freeze and ensures smooth scene swaps across all game modes.
* **Fail-Safe Player UX:** Proactively warns players running unaccelerated browsers with clear instructions rather than allowing the game to silently freeze or stutter.
* **Predictable Progress UI:** Progress bar advances smoothly at constant speed across all monitor refresh rates (60Hz, 120Hz, 144Hz) with a clean 1.0-second completion hold.
* **Validated Web Performance:** Quantified in-engine swap overhead at 41 ms, validating the multi-threaded PWA export preset.

---

## Reviewer's Guide

This PR resolves the scene transition stall on HTML5 exports by detecting unaccelerated browser environments, providing user-facing remediation in `custom_shell.html`, profiling in-engine swap latencies, and modernizing progress bar smoothing and completion pacing in `loading_screen.gd`.

### File-Level Changes

| Change                                                                                     | Details                                                                                                                                                                                                                                                                                                                                                                    | Files                                                                                                                         |
|--------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Implement pre-boot GPU software rasterizer detection and warning modal UI.                 | Query `WEBGL_debug_renderer_info` on startup for software renderers (`Microsoft Basic Render Driver`, `SwiftShader`, `llvmpipe`).Display centered warning modal with centered title, left-aligned guidance text, centered action button, and dimmed backdrop overlay (`rgba(30, 30, 30, 0.85)`).Allow users to acknowledge the warning and continue engine initialization. | `custom_shell.html`                                                                                                           |
| Refactor loading screen lifecycle, progress smoothing, and completion hold.                | Replace asymptotic `lerp(..., 0.1)` with delta-independent `move_toward(..., delta * 120.0)`.Reduce `min_load_time` from 3.0s to 0.3s on Web to prevent holding completed loads.Add an explicit 1.0s hold (`await create_timer(1.0).timeout`) at 100% before swapping scenes.Measure and log instantiation and tree-entry latencies.                                       | `scripts/loading_screen.gd`<br>                                                                                               |
| Document Web transition latency diagnosis, GPU detection, and loading screen optimization. | Record root cause analysis, trace metrics, in-engine benchmarks, and shell UI architecture for Milestone 23 documentation.                                                                                                                                                                                                                                                 | `files/docs/milestones/23/Part_5_Web_scene_transition_latency_GPU_acceleration_detection_&_loading_lifecycle_optimization.md` |

---

### Assessment Against Linked Issues

| Issue                                                                                                        | Objective                                                                                            | Addressed | Explanation                                                                                                                         |
|--------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------|-----------|-------------------------------------------------------------------------------------------------------------------------------------|
| [https://github.com/ikostan/SkyLockAssault/issues/829](https://github.com/ikostan/SkyLockAssault/issues/829) | Investigate and eliminate multi-second hangs at 80% and 90% during scene transitions on Web exports. | ✅        | Isolated root cause to disabled browser GPU hardware acceleration (`SwANGLE` software rasterizer) and resolved 10.6s `Commit` lock. |

|
| [https://github.com/ikostan/SkyLockAssault/issues/829](https://github.com/ikostan/SkyLockAssault/issues/829) | Implement granular timestamped logging to isolate resource locks, asset loading, or process frame bottlenecks. | ✅ | Added lifecycle telemetry proving `.instantiate()` (13 ms) and tree insertion (28 ms) total only 41 ms in-engine.

 |
| [https://github.com/ikostan/SkyLockAssault/issues/829](https://github.com/ikostan/SkyLockAssault/issues/829) | Prevent perceived visual stalls at 100% and provide smooth progress bar progression. | ✅ | Replaced asymptotic `lerp()` with linear `move_toward()`, reduced `min_load_time`, and added an intentional 1.0s completion pause.

 |
| [https://github.com/ikostan/SkyLockAssault/issues/829](https://github.com/ikostan/SkyLockAssault/issues/829) | Safeguard web players against software rendering performance degradation. | ✅ | Added client-side GPU query and warning modal in `custom_shell.html` with instructions to enable Hardware Acceleration. |

---

### In-Engine vs. Browser Latency Breakdown

| Execution Layer             | Component / Phase                          | Measured Latency | Assessment                                                          |
|-----------------------------|--------------------------------------------|------------------|---------------------------------------------------------------------|
| **Browser (Software Mode)** | `Commit` & GPU Buffer Flush (`SwANGLE`)    | **10,628.7 ms**  | **Root Cause:** Software rasterizer lockup on scene initialization. |
| **Browser (Hardware Mode)** | `Commit` & Compositor Flush (Hardware GPU) | **< 20 ms**      | Fully optimized; smooth frame transition.                           |
| **Engine (Godot 4.7.1)**    | Raw Resource Fetch (`load_threaded_get`)   | **< 5 ms**<br>   | Efficient threaded byte ingestion.                                  |

|
| **Engine (Godot 4.7.1)** | Node Instantiation (`.instantiate()`) | **13 ms**<br> | Negligible allocation overhead.

 |
| **Engine (Godot 4.7.1)** | Tree Entry & `_ready()` Callbacks | **28 ms**<br> | Sub-scenes, signals, HUD, and audio initialize cleanly.

 |
| **UX Pacing** | Intentional Completion Pause (`create_timer`) | **1,000 ms**<br> | Dedicated visual hold at 100% before gameplay begins.

 |

---

## PR #910 Summary: Bots / AI Contributions

### AI / Bot Contributors

* **@sourcery-ai**
Generated the PR summary, structural breakdown, and Reviewer’s Guide. Conducted code reviews and suggested improvements for progress smoothing and transition error handling.
* **@coderabbitai**
Generated the PR walkthrough and summary. Reviewed the loading lifecycle refactor, WebGL hardware acceleration detection hooks, and CSS styling consistency.
* **@deepsource-io**
Performed automated static analysis and validated code health across modified HTML/JavaScript and GDScript components.
* **@deepsource-autofix**
Enforced formatting and style compliance across GDScript and web shell assets.

### Human Contributor

* **@ikostan**
Primary author of the PR. Conducted DevTools performance trace analysis to isolate the 10.6s `Commit` software rasterizer bottleneck; implemented pre-boot GPU hardware acceleration detection and modal UI in `custom_shell.html`; engineered microsecond lifecycle profiling in `loading_screen.gd`; refactored progress interpolation from asymptotic `lerp` to delta-scaled `move_toward`; tuned visual completion pacing with a 1.0s hold; validated export matrix configurations and reverse transition teardowns; and authored Milestone 23 documentation.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
