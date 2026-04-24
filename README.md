# [Sky Lock Assault](https://ikostan.itch.io/sky-lock-assault)

<!-- markdownlint-disable line-length -->
[![Project Start](https://img.shields.io/badge/Project_Start-Jul_28%2C_2025-blue?style=flat-square)](https://github.com/ikostan/SkyLockAssault/commit/c412eb3cea0bbc73f716a14afa678d21c7d4d0d0)
[![Made with Godot](https://img.shields.io/badge/Made%20with-Godot-478CBF?style=flat-square&logo=godot%20engine&logoColor=white)](https://godotengine.org)
[![Godot](https://img.shields.io/badge/Godot-4.5-blue?style=flat-square&logo=godot-engine)](https://godotengine.org/)
[![GDScript](https://img.shields.io/badge/Language-GDScript-brightgreen?style=flat-square)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/index.html)
[![Itch.io](https://img.shields.io/badge/Deployment-Itch.io-purple?style=flat-square&logo=itch-dot-io)](https://itch.io/)
![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/ikostan/SkyLockAssault?utm_source=oss&utm_medium=github&utm_campaign=ikostan%2FSkyLockAssault&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)
[![CI/CD](https://github.com/ikostan/SkyLockAssault/actions/workflows/lint_test_deploy.yml/badge.svg?style=flat-square)](https://github.com/ikostan/SkyLockAssault/actions/workflows/lint_test_deploy.yml)
[![Latest Release](https://img.shields.io/github/v/release/ikostan/SkyLockAssault?label=Latest%20Release&style=flat-square&color=brightgreen)](https://github.com/ikostan/SkyLockAssault/releases/latest)
![Last Commit](https://img.shields.io/github/last-commit/ikostan/SkyLockAssault?style=flat-square)
[![Downloads](https://img.shields.io/github/downloads/ikostan/SkyLockAssault/total?style=flat-square&color=brightgreen&label=Downloads)](https://github.com/ikostan/SkyLockAssault/releases)
[![codecov](https://codecov.io/gh/ikostan/SkyLockAssault/graph/badge.svg?token=A4O6I72HP0)](https://codecov.io/gh/ikostan/SkyLockAssault)
![Repo Size](https://img.shields.io/github/repo-size/ikostan/SkyLockAssault?style=flat-square)
![Closed Issues](https://img.shields.io/github/issues-closed/ikostan/SkyLockAssault?style=flat-square&label=Issues&color=green)
![Open Issues](https://img.shields.io/github/issues/ikostan/SkyLockAssault?style=flat-square&label=Issues&color=red)
[![Known Vulnerabilities](https://snyk.io/test/github/ikostan/SkyLockAssault/badge.svg)](https://snyk.io/test/github/ikostan/SkyLockAssault)
[![All Contributors](https://img.shields.io/github/all-contributors/ikostan/SkyLockAssault?color=ee8449&style=flat-square)](#contributors)

## A top-down online web browser game built with Godot 4.5

![Sky Lock Assault](https://github.com/ikostan/SkyLockAssault/blob/main/files/img/main_menu_2.png)

Combat airplane web game with fuel management, multiple weapons, multi-level,
and adjustable difficulty.

This is a dedicated Godot v4.5 game dev project on Windows 10 64-bit OS.
We'll be learning game dev here, starting with a simple main menu and expanding
to core mechanics like player controls, enemy AI, and assaults in the sky.
The repo is open-source at [SkyLockAssault](https://github.com/ikostan/SkyLockAssault).

You can play this game on [Itch.io](https://ikostan.itch.io/sky-lock-assault)

## Project Overview

- **Godot Version**: 4.5 stable (or compatible).
- **OS**: `Windows 10 64-bit`.
- **Tools**:
  - `Docker Desktop v4.45` for local testing
  - `GitHub Desktop v3.5` for repo management
  - `PyCharm 2024.1.7 (Community Edition)` for file editing
  - `Windows PowerShell` for running Docker commands
- **Supported Browsers**: Chrome 90+, Firefox 88+, Edge 90+ (WebGL 2.0 required)
- **Known Limitations**: Mobile touch controls are experimental; fullscreen may not
  persist on iOS Safari
- **Goal**: Build a playable top-down shooter with web deployment in mind—export
  to HTML5/Web, test locally, deploy to itch.io.

## Game Assets

- [Empire State Font](https://www.dafont.com/empire-state.font?l[]=10&l[]=1)
- [Pixel Planes Assets Pack](https://clavs.itch.io/pixel-planes-assets-pack)
- [Assets Free Laser Bullets Pack 2020](https://wenrexa.itch.io/laser2020)
- Csaba Felvegi aka "chabull" free assets collection, [see here](https://opengameart.org/users/chabull)
- [Pixabay: royalty free stock](https://pixabay.com/)
- Music:
  - [Battle Epic](https://pixabay.com/music/main-title-battle-epic-241575/) by [Hot_Dope](https://pixabay.com/users/hot_dope-27442149/)
  - [Retro laser 1](https://pixabay.com/sound-effects/retro-laser-1-236669/) by [Driken5482](https://pixabay.com/users/driken5482-45721595/)

## Documentation

1. [Guide to Implementing Versioning](/files/docs/Guide_to_Implementing_Versioning.md)
2. [Godot v4.5 Docs](https://docs.godotengine.org/en/stable/index.html)
3. [Development Guide](files/docs/Development_Guide.md)
4. [Local CI Pipeline for Godot Project using Docker](/files/docs/Local_CI_Pipeline_for_Godot_Project_using_Docker.md)
5. [Docker Local Test Server](/files/docs/Docker_Local_Test_Server.md)
6. [Setup Instructions](/files/docs/Setup_Instructions.md)
7. [Signing Setup for GitHub Desktop](/files/docs/Signing_Setup_GitHub_Desktop.md)
8. BOTS:
   - [Dependabot](https://docs.github.com/en/code-security/dependabot)
   - [Snyk](https://docs.snyk.io/)
   - [Sourcery AI](https://docs.sourcery.ai/)
   - [CodeRabbit AI](https://github.com/coderabbitai)
   - [LlamaPreview](https://github.com/apps/llamapreview)
   - [IMGBOT](https://imgbot.net/docs/)
   - [Release Drafter](https://github.com/release-drafter/release-drafter?tab=readme-ov-file#readme)
   - [Close Stale Issues and PRs](https://github.com/actions/stale)
   - [AllContributors GitHub App](https://allcontributors.org/docs/en/bot/installation)
   - [DeepSource](https://github.com/deepsource)
9. [Free Web Browser Game Deployment Platforms](files/docs/Platforms_for_Web_Deployment_Guide.md)
<!-- markdownlint-enable line-length -->

## Roadmap

Here's a high-level plan for upcoming features. Contributions welcome!

- **v0.2: Completed Foundations** - Project import, Docker local testing,
  basic input actions, top-down movement, main menu, quit handling for browser,
  HTML5 export and testing, GitHub Actions CI/CD to Itch.io (complete).
- **v0.3: Expansion** - Add levels, weapons, player feedback integration.
- **v0.4: Post-MVP Refinements** - Performance optimization, audio polish, bug fixes.
- **v0.5: Ongoing Development** - Feedback gathering, minor updates, release tagging.
- Future: Multiplayer elements, AI enemies, mobile export
  (post-launch based on community input).

## Contributing

Pull requests welcome for mechanics like enemy AI, levels, or web optimizations!
Fork the repo and submit your ideas. See [CONTRIBUTING](CONTRIBUTING.md) for
guidelines (create if needed).

## Player Feedback

We value your input to improve Sky Lock Assault! Share your thoughts via:

- [Itch.io Comments](https://ikostan.itch.io/sky-lock-assault) – Discuss
  gameplay, bugs, or suggestions directly on the game's page.

## Security

For details on reporting vulnerabilities and our disclosure process, see
[SECURITY.md](/.github/SECURITY.md).

---

## License

This project is licensed under the GNU General Public License v3.0 or
later (GPL-3.0-or-later) - see the [LICENSE](LICENSE) file for details.

Commercial use is allowed under GPLv3 terms, which require that any
distributed derivatives or combined works remain open source and provide
source code to users. For closed-source commercial alternatives without
these GPL requirements, a separate license is available upon request.

### Key Terms

- **Open Source**: You can view, modify, and distribute the code freely,
  as long as derivatives remain under GPLv3.
- **Commercial Use**: Allowed under GPLv3 (with source code obligations
  for distributions). Closed-source commercial use requires a separate license.
- **Contact**: For custom licenses, trademark use (e.g., "Sky Lock Assault"),
  or inquiries, reach out via GitHub issues or X @EgorKostan.

---

## Architecture Highlights

- Separation of gameplay logic and UI state
- Centralized stat tracking (fuel/speed dictionaries)
- Speed-based gameplay scaling
- Modular audio system with buses
- CI/CD-driven deployment workflow
- Test-driven improvements with GUT
- Observer-based Settings System: Centralized GameSettingsResource that handles
  automatic persistence and UI synchronization through signals.


### Project Structure (`scripts/`)

Post-Refactor Phase 4 (PR `#582`), the root `scripts/` directory has been fully
reorganised into purpose-specific sub-directories:
<!-- markdownlint-disable MD013 -->
| Directory            | Contents                                                                                                                                                                                     |
|----------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `scripts/core/`      | Foundational systems: `game_paths.gd` (centralised path registry), `globals.gd`, `main_scene.gd`, `settings.gd`                                                                              |
| `scripts/resources/` | Data containers & configuration: `game_settings_resource.gd`, `audio_constants.gd`                                                                                                           |
| `scripts/entities/`  | Game objects: `player.gd`, `bullet.gd`, `weapon.gd`                                                                                                                                          |
| `scripts/system/`    | Platform wrappers & integrations: `audio_web_bridge.gd`, `JavaScriptBridgeWrapper.gd`, `OSWrapper.gd`                                                                                        |
| `scripts/managers/`  | Game-loop managers: `audio_manager.gd`, `parallax_manager.gd`, `resource_preloader.gd`                                                                                                       |
| `scripts/ui/`        | Interface layer: `hud.gd`; sub-dirs `menus/` (main, pause, options, audio, gameplay, key-mapping, advanced), `screens/` (splash, loading), `components/` (volume slider, input remap button) |
<!-- markdownlint-enable MD013 -->
---

## 🟢 Current Development Status

**Milestone:** Milestone 14
**Status:** Stable gameplay loop with synced UI systems and GUT-based unit testing.
**Active Focus:** Gameplay expansion (AI enemies, multiplayer, levels).

### Current features

- Main menu scene with buttons (Start, Resume, Options, Quit).
- Placeholder game level for future mechanics and game testing.
- Options menu with log level settings, accessible from main and pause menus.
- Pause menu with buttons (Main Menu, Options, Resume).
- Player scene with CharacterBody2D, ShaderBody, CollisionShape, and FuelTimer.
- Fade-in animations for main menu UI panels.
- Fuel system including fuel level progress bar with dynamic color gradients
  (green to yellow to red/dark red) and low-fuel blinking warnings.
- Basic weapon system.
- Difficulty settings.
- Game controls input remapping.
- Fuel management (timer-based depletion scaled by speed, base drain, and difficulty;
  refuel not yet implemented).
- Basic adjustable difficulty (affects fire rate, fuel depletion, and more).
- Basic sound effects & background music.
- Airplane Rotor Sound (Stereo SFX) + Rotor Animation, with reusable helpers and
  rotors stopping on zero fuel.
- Audio Buses & Panning (L/R Split).
- Options Menu: Rotors Volume Slider.
- Multi-Thread support enabled.
- Player movement refactor: Lateral-only motion with acceleration-based forward/back
  speed control, clamped between min/max speeds.
- Speed system with progress bar, dynamic color changes (green normal, yellow caution,
  red/dark red danger based on thresholds), and low/over-speed blinking warnings.
- Centralized fuel/speed tracking via dictionaries for gameplay and UI integration.
- Fully synchronized Input Remapping system:
  - UI reflects saved bindings
  - Conflict-safe remapping logic
  - Persistent across sessions
- Improved Options Menu behavior:
  - Shared between Main Menu and Pause Menu
  - Live updates to audio and gameplay settings
- UI state consistency across scene transitions
- Automatic Settings Persistence: Settings (including log levels, difficulty, and
  debug flags) auto-save to disk via Globals.gd whenever a change is detected in
  the resource.
- Real-time UI Synchronization: UI components dynamically observe the settings resource,
  ensuring that any external changes are immediately reflected in the menus.
- UI navigation sounds integrated with a dedicated Menu SFX bus.
- Hardened JavaScript bridge (`AudioWebBridge` and gameplay settings bridge)
  to ensure robust communication between the Godot engine and the web browser
  environment.

### Features Roadmap

- **Completed (Merged via Recent PRs)**:
  - Fuel management with timer-based depletion scaled by speed/difficulty (PR #288).
  - Player movement refactor: Lateral-only controls with acceleration/deceleration,
    min/max speed clamping (PR #288).
  - Speed system with progress bar, dynamic color gradients (green normal, yellow
    caution, red/dark red danger), and low/over-speed blinking warnings
    (PR #275 and #288).
  - Rotor SFX/animation with volume sliders and zero-fuel stopping (prior PRs).
  - Refactor player movement integrations
    (e.g., speed-based fuel drain, UI sync) – Issue #169.
  - Add procedural random parallax background for speed-based
    scrolling – Issue #273.
  - Switch testing from GDUnit4 to GUT for better coverage – Issues #282, #283.
  - GitHub Wiki for documentation/learning resources – Issue #284.
  - Version tagging in CI/CD – Issue #285.
  - Dynamic speed bar color changes (partially merged in PR #275/#288,
    but full threshold logic ongoing) – Issue #286.
  - Improve input mappings with conflict handling and unbound warnings:
    - Conflict detection + confirmation dialog when assigning already-used inputs.
    - Per-device tracking, last-used device persistence, and device-aware
      remap prompts.
    - HUD warnings for unbound critical controls during gameplay.
    - Support opening key-mapping menu directly from other menus.
    - Expanded tests for input remap and settings behaviors.
  - Ensure menu navigation bindings & legacy input migration:
    - Guaranteed binding of core navigation actions (ui_accept, ui_up, etc.).
    - Initial focus management for gameplay/options menus and restored focus flows.
    - Improved keyboard/gamepad input label generation and legacy config migration.
    - Updated default gamepad throttle mappings to match expectations.
    - Expanded test coverage around menu navigation and input handling.
  - Enable keyboard & d-pad navigation for audio settings and key mappings:
    - Full keyboard + gamepad navigation support for audio settings.
    - Focus highlighting on volume rows and unified accept action for slider/toggle.
    - Better modifier key handling (Ctrl/Shift/Alt/Meta) in remapping UI.
    - Refined conflict handling in key remapping logic and focus restoration
      from audio → main menu.
    - CI/tooling version bumps and asset import config additions.
  - Documented the observer-based settings system and pinned CI actions for
    pipeline stability (PR #488).
  - Hardened the gameplay settings JavaScript bridge and added comprehensive GUT
    test coverage (PR #500).
  - Integrated UI navigation sounds, a dedicated Menu SFX bus, and the
    `AudioWebBridge` (PR #479).

---

## Milestones

## Input & Navigation Improvements (Milestone 12)

Milestone 12 focused on making the game more navigable and responsive
to user input devices:

### Input Remapping

- Conflict detection dialog when assigning existing bindings
- Per-device last input selection persists between sessions
- Critical control warnings if actions are unbound
- Remap menu accessible from all relevant UI paths

### Menu Navigation

- Keyboard + gamepad (D-Pad) support for all menu flows
- Guaranteed core navigation actions remain bound
- Focus restoration when leaving submenus (Audio → Options → Main)
- Modifier key respect (Ctrl/Shift/Alt/Meta) in remapping UI

### Audio Settings Controls

- Use keyboard/gamepad accept action for sliders and toggles
- Focus highlighting for better visual feedback
- Unified UI interactions without relying on the mouse
- Modular audio system with dedicated buses (including a specific
  Menu SFX bus) and an `AudioWebBridge` for seamless web environment
  synchronization.

### Godot Resource Migration

- Replaced hard-coded globals with a `GameSettingsResource`
- Easier inspector-based editing and persistence
- Safer loading with fallback on corrupted configs

### Known Limitations

- Some complex menu flows may still rely on the mouse until additional
  focus neighbors are defined.
- Modifier-aware remapping requires explicit key+modifier press for
  unique bindings.

###  Milestone 14

**Status:** Stable gameplay loop with synced UI systems and GUT-based
unit testing.
**Active Focus:** Gameplay expansion (AI enemies, multiplayer, levels).
**Version:** v0.9.18

### Milestone 16

**Status:** Stable gameplay loop with fully refactored script architecture, 
synced UI systems, and GUT-based unit testing.
**Active Focus:** Gameplay expansion (AI enemies, multiplayer, levels).

Track progress via [Milestones](https://github.com/ikostan/SkyLockAssault/milestones).

---

### Known Issues

- Harmless console warning on desktop fullscreen
  (NotSupportedError for orientation lock—ignored as non-fatal; doesn't affect gameplay).
- Placeholder level lacks mechanics—work in progress:
  - Core gameplay loop functional (movement, fuel, speed, audio)
  - Enemy AI and combat progression are upcoming.
- Report new issues on [GitHub](https://github.com/ikostan/SkyLockAssault/issues).

---

## DevOps & Automation

- GitHub Actions CI/CD pipeline
- Automated HTML5 build & Itch.io deployment
- Codecov integration
- Snyk security scanning
- Docker-based local web testing
- Release Drafter for automated changelogs

---

## Testing

Sky Lock Assault uses **GUT (Godot Unit Test)** framework for automated testing.

- Unit tests cover:
  - Input remapping logic
  - Fuel system behavior
  - Speed system thresholds & UI sync
  - Player movement constraints
- Tests run locally and in CI via GitHub Actions.
- Coverage is tracked with Codecov.
- Settings Observer Tests: Dedicated GUT test suite validates signal emission, value
  clamping (e.g., difficulty limits), and successful serialization to the user's
  disk.
- JavaScript bridge communication and web integration reliability

Run tests locally:

- Open Godot
- Use GUT Test Runner
- Or run via CI pipeline

Testing is a core part of development and required for gameplay logic changes.

---

### Play Instructions

- **In Godot Editor**: Open the project > Press F5 to run the main scene
  (`main_menu.tscn`). Use keyboard/mouse for navigation.
- **Local Web Testing**: After exporting to HTML5 (see Setup),
  cd to `infra/` in `PowerShell` > `docker compose up -d` >
  Open <http://localhost:9090> in browser. Click "Run game" iframe;
  use fullscreen for immersion (ignore desktop console warnings).
- **Online on itch.io**:
  1. Visit [ikostan.itch.io/sky-lock-assault](https://ikostan.itch.io/sky-lock-assault)
  2. Click "Run game".
- The game supports browser play; mobile-friendly with landscape orientation.

For learning: Test quit handling (platform-specific) and log levels in options
menu during play.

---

### 🙌 How to Contribute

- Fork the repo and create a branch for your changes.
- Follow GDScript best practices; test in editor and web export.
- Open a Pull Request with details.
- See [CONTRIBUTING.md](/CONTRIBUTING.md) for full guidelines.
- **Join the Discussions**: Chat about ideas, ask questions on web exports, or suggest
  features at [GitHub Discussions](https://github.com/ikostan/SkyLockAssault/discussions).

We use the following labels to organize contributions:

- `good first issue` — beginner friendly
- `documentation` — improvements to docs
- `feature` — gameplay or UI work

Please create a branch per issue and reference the issue number in your PR title.

---

### Contributors

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
