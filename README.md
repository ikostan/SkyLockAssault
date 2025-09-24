# [Sky Lock Assault](https://ikostan.itch.io/sky-lock-assault)

<!-- markdownlint-disable line-length -->
[![Made with Godot](https://img.shields.io/badge/Made%20with-Godot-478CBF?style=flat&logo=godot%20engine&logoColor=white)](https://godotengine.org)
[![Main Deploy Pipeline](https://github.com/ikostan/SkyLockAssault/actions/workflows/lint_test_deploy.yml/badge.svg)](https://github.com/ikostan/SkyLockAssault/actions/workflows/lint_test_deploy.yml)
![Repo Size](https://img.shields.io/github/repo-size/ikostan/SkyLockAssault)
![Closed Issues](https://img.shields.io/github/issues-closed/ikostan/SkyLockAssault?%2FSkyLockAssault?style=flat-square&label=Issues&color=green)
![Open Issues](https://img.shields.io/github/issues/ikostan/SkyLockAssault?style=flat-square&label=Issues&color=red)
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
2. [Docker Local Test Server](/files/docs/Docker_Local_Test_Server.md)

### Current features:

- Main menu scene (`main_menu.tscn`) with buttons (Start, Resume, Options, Quit).
- Placeholder game level (`game_level.tscn`) for future mechanics.

## Setup Instructions

1. **Clone the Repo**:
   - Use GitHub Desktop: Clone https://github.com/ikostan/SkyLockAssault.
   - Open in Godot 4.5: Launch Godot > Import > Select `project.godot`.

2. **Install Export Templates**:
   - In Godot: Editor > Manage Export Templates > Download for 4.5
     (or manual from https://godotengine.org/download/archive/4.4.1-stable/).
   - Required for Web exports.

3. **Export to Web**:
   - Project > Export > Add Web preset.
   - Export to `export/web/` folder in the project root.
   - This generates index.html, .wasm, .js, etc., for browser testing.
