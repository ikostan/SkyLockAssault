# [Sky Lock Assault](https://ikostan.itch.io/sky-lock-assault)

<!-- markdownlint-disable line-length -->
[![Made with Godot](https://img.shields.io/badge/Made%20with-Godot-478CBF?style=flat&logo=godot%20engine&logoColor=white)](https://godotengine.org)
[![Godot](https://img.shields.io/badge/Godot-4.5-blue?logo=godot-engine)](https://godotengine.org/)
[![GDScript](https://img.shields.io/badge/Language-GDScript-brightgreen)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/index.html)
[![Itch.io](https://img.shields.io/badge/Deployment-Itch.io-purple?logo=itch-dot-io)](https://itch.io/)
[![CI/CD](https://github.com/ikostan/SkyLockAssault/actions/workflows/lint_test_deploy.yml/badge.svg)](https://github.com/ikostan/SkyLockAssault/actions/workflows/lint_test_deploy.yml)
![Repo Size](https://img.shields.io/github/repo-size/ikostan/SkyLockAssault)
![Closed Issues](https://img.shields.io/github/issues-closed/ikostan/SkyLockAssault?%2FSkyLockAssault?style=flat-square&label=Issues&color=green)
![Open Issues](https://img.shields.io/github/issues/ikostan/SkyLockAssault?style=flat-square&label=Issues&color=red)
[![Known Vulnerabilities](https://snyk.io/test/github/ikostan/SkyLockAssault/badge.svg)](https://snyk.io/test/github/ikostan/SkyLockAssault)
<!-- markdownlint-enable line-length -->

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
  * `Docker Desktop v4.45` for local testing
  * `GitHub Desktop v3.5` for repo management 
  * `PyCharm 2024.1.7 (Community Edition)` for file editing
  * `Windows PowerShell` for running Docker commands
- **Goal**: Build a playable top-down shooter with web deployment in mind—export
  to HTML5/Web, test locally, deploy to itch.io.

## Game Assets

- [Empire State Font](https://www.dafont.com/empire-state.font?l[]=10&l[]=1)
- [Pixel Planes Assets Pack](https://clavs.itch.io/pixel-planes-assets-pack)

## Documentation

1. [Guide to Implementing Versioning](/files/docs/Guide_to_Implementing_Versioning.md)
2. [Godot v4.5 Docs](https://docs.godotengine.org/en/stable/index.html)
2. [Development Guide](files/docs/Development_Guide.md)
3. [Docker Local Test Server](/files/docs/Docker_Local_Test_Server.md)
4. [Setup Instructions](/files/docs/Setup_Instructions.md)
5. [Signing Setup for GitHub Desktop](/files/docs/Signing_Setup_for_GitHub_Desktop.md)
6. BOTS:
   - [Dependabot](https://docs.github.com/en/code-security/dependabot)
   - [Snyk](https://docs.snyk.io/)
   - [Sourcery AI](https://docs.sourcery.ai/)
   - [IMGBOT](https://imgbot.net/docs/)
   - [Release Drafter](https://github.com/release-drafter/release-drafter?tab=readme-ov-file#readme)

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

### Play Instructions

- **In Godot Editor**: Open the project > Press F5 to run the main scene
  (`main_menu.tscn`). Use keyboard/mouse for navigation.
- **Local Web Testing**: After exporting to HTML5 (see Setup),
  cd to `infra/` in `PowerShell` > `docker compose up -d` > 
  Open http://localhost:9090 in browser. Click "Run game" iframe;
  use fullscreen for immersion (ignore desktop console warnings).
- **Online on itch.io**:
  1. Visit [ikostan.itch.io/sky-lock-assault](https://ikostan.itch.io/sky-lock-assault)
  2. Click "Run game". 
- The game supports browser play; mobile-friendly with landscape orientation.

For learning: Test quit handling (platform-specific) and log levels in options
menu during play.

### Current features:

- Main menu scene (`main_menu.tscn`) with buttons (Start, Resume, Options, Quit).
- Placeholder game level (`game_level.tscn`) for future mechanics.
- Add options menu with log level settings accessible from main and pause menus.
- Implement fade-in animations for main menu UI panels

### Features Roadmap

- **Current**: 
  * Main menu with Start/Resume/Options/Quit; 
  * placeholder game level; 
  * fade-in animations; 
  * web export/testing with Docker.
  * itch.io CI/CD integration.
- **Planned**: 
  * Fuel management (timer-based depletion/refuel); 
  * multiple weapons (guns/missiles with switching); 
  * multi-level progression; 
  * adjustable difficulty (enemy spawn rates); 
  * enemy AI (pathing/assaults); scoring/HUD.
- **Future Milestones**:
  * Mobile exports, 
  * audio, 
  * particle effects,

Track progress via [Milestones](https://github.com/ikostan/SkyLockAssault/milestones).

### Known Issues

- Harmless console warning on desktop fullscreen 
  (NotSupportedError for orientation lock—ignored as non-fatal; doesn't affect gameplay).
- Placeholder level lacks mechanics—work in progress.
- Report new issues on [GitHub](https://github.com/ikostan/SkyLockAssault/issues).

### How to Contribute

- Fork the repo and create a branch for your changes.
- Follow GDScript best practices; test in editor and web export.
- Open a Pull Request with details.
- See [CONTRIBUTING.md](/CONTRIBUTING.md) for full guidelines.
