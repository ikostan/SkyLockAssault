<!-- markdownlint-disable MD001 MD013 MD036 MD033 table-column-style -->

# [Sky Lock Assault](https://ikostan.itch.io/sky-lock-assault)

[![Project Start](https://img.shields.io/badge/Project_Start-Jul_28%2C_2025-blue?style=flat-square)](https://github.com/ikostan/SkyLockAssault/commit/c412eb3cea0bbc73f716a14afa678d21c7d4d0d0)
[![Made with Godot](https://img.shields.io/badge/Made%20with-Godot-478CBF?style=flat-square&logo=godot%20engine&logoColor=white)](https://godotengine.org)
[![Godot](https://img.shields.io/badge/Godot-4.7.1-blue?style=flat-square&logo=godot-engine)](https://godotengine.org/)
[![GDScript](https://img.shields.io/badge/Language-GDScript-brightgreen?style=flat-square)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/index.html)
[![Itch.io](https://img.shields.io/badge/Deployment-Itch.io-purple?style=flat-square&logo=itch-dot-io)](https://itch.io/)
![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/ikostan/SkyLockAssault?utm_source=oss&utm_medium=github&utm_campaign=ikostan%2FSkyLockAssault&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)
[![CI/CD](https://github.com/ikostan/SkyLockAssault/actions/workflows/lint_test_deploy.yml/badge.svg?style=flat-square)](https://github.com/ikostan/SkyLockAssault/actions/workflows/lint_test_deploy.yml)
[![Latest Release](https://img.shields.io/github/v/release/ikostan/SkyLockAssault?label=Latest%20Release&style=flat-square&color=brightgreen)](https://github.com/ikostan/SkyLockAssault/releases/latest)
![Last Commit](https://img.shields.io/github/last-commit/ikostan/SkyLockAssault?style=flat-square)
[![Downloads](https://img.shields.io/github/downloads/ikostan/SkyLockAssault/total?style=flat-square&color=brightgreen&label=Downloads)](https://github.com/ikostan/SkyLockAssault/releases)
[![codecov](https://codecov.io/github/ikostan/SkyLockAssault/graph/badge.svg?token=A4O6I72HP0)](https://codecov.io/github/ikostan/SkyLockAssault)
![Repo Size](https://img.shields.io/github/repo-size/ikostan/SkyLockAssault?style=flat-square)
![Closed Issues](https://img.shields.io/github/issues-closed/ikostan/SkyLockAssault?style=flat-square&label=Issues&color=green)
![Open Issues](https://img.shields.io/github/issues/ikostan/SkyLockAssault?style=flat-square&label=Issues&color=red)
[![All Contributors](https://img.shields.io/github/all-contributors/ikostan/SkyLockAssault?color=ee8449&style=flat-square)](#contributors)

**A top-down combat airplane web game** built with Godot 4.X — fuel management,
multiple weapons, multi-level progression, and adjustable difficulty.

Play it now on [itch.io](https://ikostan.itch.io/sky-lock-assault).

![Sky Lock Assault](https://github.com/ikostan/SkyLockAssault/blob/main/files/img/main_menu_2.png)

This is a learning-focused Godot project. We started with a simple main menu
and continue expanding into player controls, enemy AI, and aerial combat.
Source is publicly available under the PolyForm Noncommercial License 1.0.0.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Play Instructions](#play-instructions)
- [Game Assets](#game-assets)
- [Documentation](#documentation)
- [Architecture Highlights](#architecture-highlights)
- [Project Structure](#project-structure)
- [Known Issues](#known-issues)
- [DevOps & Automation](#devops--automation)
- [Testing](#testing)
- [Contributors](#contributors)
- [License](#license)
- [Security](#security)
- [Player Feedback](#player-feedback)

---

## Project Overview

| Item                   | Details                                                                                |
|------------------------|----------------------------------------------------------------------------------------|
| **Godot Version**      | 4.X stable (or compatible)                                                             |
| **Primary OS**         | Windows 10/11 64-bit                                                                   |
| **Supported Browsers** | Chrome 90+, Firefox 88+, Edge 90+ (WebGL 2.0 required)                                 |
| **Known Limitations**  | Mobile touch controls are experimental; fullscreen may not persist on iOS Safari       |
| **Goal**               | Playable top-down shooter with HTML5/Web export, local testing, and itch.io deployment |

### Local development tools

- Docker Desktop (local web testing)
- GitHub Desktop (repo management)
- PyCharm / any editor (file editing)
- Windows PowerShell (Docker commands)

---

## Play Instructions

### Online (itch.io)

1. Visit [ikostan.itch.io/sky-lock-assault](https://ikostan.itch.io/sky-lock-assault)
2. Click **Run game**

### In Godot Editor

1. Open the project
2. Press **F5** to run the main scene (`main_menu.tscn`)
3. Use keyboard/mouse for navigation

### Local Web Testing

1. Export the project to HTML5 (see [Setup Instructions](files/docs/Setup_Instructions.md))
2. From `infra/` in PowerShell: `docker compose up -d`
3. Open <http://localhost:9090>
4. Click **Run game** in the iframe (use fullscreen for immersion; ignore harmless desktop console warnings)

The game is browser-first and landscape-oriented. Mobile support is experimental.

> Tip: While playing, try the options menu — test quit handling
> (platform-specific) and log levels.

---

## Game Assets

| Asset                    | Source                                                                |
|--------------------------|-----------------------------------------------------------------------|
| Empire State Font        | [dafont.com](https://www.dafont.com/empire-state.font?l[]=10&l[]=1)   |
| Pixel Planes Assets Pack | [clavs.itch.io](https://clavs.itch.io/pixel-planes-assets-pack)       |
| Laser Bullets Pack 2020  | [wenrexa.itch.io](https://wenrexa.itch.io/laser2020)                  |
| Free assets collection   | [Csaba Felvegi / chabull](https://opengameart.org/users/chabull)      |
| Royalty-free stock       | [Pixabay](https://pixabay.com/)                                       |
| Music — *Battle Epic*    | [Hot_Dope](https://pixabay.com/music/main-title-battle-epic-241575/)  |
| SFX — *Retro laser 1*    | [Driken5482](https://pixabay.com/sound-effects/retro-laser-1-236669/) |

---

## Documentation

| #  | Document                                                                                                                               |
|----|----------------------------------------------------------------------------------------------------------------------------------------|
| 1  | [Guide to Implementing Versioning](files/docs/Guide_to_Implementing_Versioning.md)                                                     |
| 2  | [Godot Documentation](https://docs.godotengine.org/en/stable/index.html)                                                               |
| 3  | [Development Guide](files/docs/Development_Guide.md)                                                                                   |
| 4  | [Local CI Pipeline for Godot (Docker)](files/docs/Local_CI_Pipeline_for_Godot_Project_using_Docker.md)                                 |
| 5  | [Docker Local Test Server](files/docs/Docker_Local_Test_Server.md)                                                                     |
| 6  | [Setup Instructions](files/docs/Setup_Instructions.md)                                                                                 |
| 7  | [Signing Setup for GitHub Desktop](files/docs/Signing_Setup_GitHub_Desktop.md)                                                         |
| 8  | [Free Web Browser Game Deployment Platforms](files/docs/Platforms_for_Web_Deployment_Guide.md)                                         |
| 9  | [Inspect files saved by a Godot web export](files/docs/howto_inspect_the_files_saved_by_a_Godot_web_export.md)                         |
| 10 | [CI/CD Production Salt Injection & Security Guard Architecture](files/docs/Production_Salt_Injection_&_Security_Guard_Architecture.md) |
| 11 | [Browser DevTools Guide — Verifying Web Save Encryption](files/docs/Browser_DevTools_Guide_Verifying_Web_Save_Encryption.md)           |

### Bots & automation tools used in the repo

- [Dependabot](https://docs.github.com/en/code-security/dependabot)
- [Snyk](https://docs.snyk.io/)
- [Sourcery AI](https://docs.sourcery.ai/)
- [CodeRabbit AI](https://github.com/coderabbitai)
- [LlamaPreview](https://github.com/apps/llamapreview)
- [IMGBOT](https://imgbot.net/docs/)
- [Release Drafter](https://github.com/release-drafter/release-drafter)
- [Close Stale Issues and PRs](https://github.com/actions/stale)
- [All Contributors](https://allcontributors.org/docs/en/bot/installation)
- [DeepSource](https://github.com/deepsource)

---

## Architecture Highlights

- Separation of gameplay logic and UI state
- Resource-based state model (`FuelResource`, `SpeedResource`, `GameSettingsResource`)
- Speed-based gameplay scaling
- Modular audio system with buses
- CI/CD-driven deployment workflow
- Test-driven improvements with GUT
- **Observer-based Settings System**: centralized `GameSettingsResource` that handles automatic persistence and UI synchronization through signals

---

## Project Structure

The `scripts/` directory is organized by purpose:

| Directory            | Contents                                                                               |
|----------------------|----------------------------------------------------------------------------------------|
| `scripts/core/`      | Foundational systems: `game_paths.gd`, `globals.gd`, `main_scene.gd`, `settings.gd`    |
| `scripts/resources/` | Data containers & configuration: `game_settings_resource.gd`, `audio_constants.gd`     |
| `scripts/entities/`  | Game objects: `player.gd`, `bullet.gd`, `weapon.gd`                                    |
| `scripts/system/`    | Platform wrappers: `audio_web_bridge.gd`, `JavaScriptBridgeWrapper.gd`, `OSWrapper.gd` |
| `scripts/managers/`  | Game-loop managers: `audio_manager.gd`, `parallax_manager.gd`, `resource_preloader.gd` |
| `scripts/ui/`        | Interface layer: `hud.gd`; sub-dirs `menus/`, `screens/`, `components/`                |

---

## Known Issues

- Harmless console warning on desktop fullscreen (`NotSupportedError` for
  orientation lock — non-fatal, does not affect gameplay).
- Placeholder level still lacks full mechanics (work in progress):
  - Core loop is functional (movement, fuel, speed, audio)
  - Enemy AI and combat progression are upcoming

Report new issues on [GitHub Issues](https://github.com/ikostan/SkyLockAssault/issues).

---

## DevOps & Automation

- GitHub Actions CI/CD pipeline
- Automated HTML5 build & itch.io deployment
- Codecov coverage tracking
- Snyk security scanning
- Docker-based local web testing
- Release Drafter for automated changelogs

---

## Testing

Sky Lock Assault uses the **GUT (Godot Unit Test)** framework.

### Covered areas

- Input remapping logic
- Fuel system behavior
- Speed system thresholds & UI sync
- Player movement constraints
- Settings observer (signal emission, value clamping, serialization)
- JavaScript bridge communication and web integration reliability

Tests run locally and in CI via GitHub Actions. Coverage is tracked with Codecov.

### How to run tests

- Open Godot → GUT Test Runner, **or**
- Run via the CI pipeline

Testing is required for gameplay logic changes.

---

## Contributors

Thanks to everyone who has contributed!

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://ikostan.com"><img src="https://avatars.githubusercontent.com/u/20955183?v=4&size=100" width="100px" height="100px" alt="Egor Kostan"/><br /><sub><b>Egor Kostan</b></sub></a><br /><a href="https://github.com/ikostan/SkyLockAssault/commits?author=ikostan" title="Code">💻</a> <a href="https://github.com/ikostan/SkyLockAssault/commits?author=ikostan" title="Tests">⚠️</a> <a href="https://github.com/ikostan/SkyLockAssault/commits?author=ikostan" title="Documentation">📖</a> <a href="#infra-ikostan" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#ideas-ikostan" title="Ideas, Planning, & Feedback">🤔</a> <a href="#design-ikostan" title="Design">🎨</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/espanakosta-jpg"><img src="https://avatars.githubusercontent.com/u/261132001?v=4&size=100" width="100px" height="100px" alt="espanakosta-jpg"/><br /><sub><b>espanakosta-jpg</b></sub></a><br /><a href="#audio-espanakosta-jpg" title="Audio contributions (sound effects, UI feedback)">🔊</a> <a href="#design-espanakosta-jpg" title="Design">🎨</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/claude"><img src="https://avatars.githubusercontent.com/u/81847?v=4&size=100" width="100px" height="100px" alt="Claude"/><br /><sub><b>Claude</b></sub></a><br /><a href="https://github.com/ikostan/SkyLockAssault/commits?author=claude" title="Code">💻</a> <a href="https://github.com/ikostan/SkyLockAssault/commits?author=claude" title="Tests">⚠️</a> <a href="https://github.com/ikostan/SkyLockAssault/commits?author=claude" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/apps/copilot-swe-agent"><img src="https://avatars.githubusercontent.com/u/223556219?v=4&size=100" width="100px" height="100px" alt="Copilot"/><br /><sub><b>Copilot</b></sub></a><br /><a href="https://github.com/ikostan/SkyLockAssault/commits?author=Copilot" title="Code">💻</a> <a href="https://github.com/ikostan/SkyLockAssault/commits?author=Copilot" title="Tests">⚠️</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/apps/coderabbitai"><img src="https://avatars.githubusercontent.com/in/347564?v=4&size=100" width="100px" height="100px" alt="CodeRabbit"/><br /><sub><b>CodeRabbit</b></sub></a><br /><a href="https://github.com/ikostan/SkyLockAssault/pulls?q=is%3Apr+reviewed-by%3Acoderabbitai[bot]" title="Reviewed Pull Requests">👀</a> <a href="https://github.com/ikostan/SkyLockAssault/commits?author=coderabbitai[bot]" title="Tests">⚠️</a> <a href="https://github.com/ikostan/SkyLockAssault/commits?author=coderabbitai[bot]" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/apps/sourcery-ai"><img src="https://avatars.githubusercontent.com/in/48477?v=4&size=100" width="100px" height="100px" alt="Sourcery AI"/><br /><sub><b>Sourcery AI</b></sub></a><br /><a href="https://github.com/ikostan/SkyLockAssault/pulls?q=is%3Apr+reviewed-by%3Asourcery-ai[bot]" title="Reviewed Pull Requests">👀</a> <a href="https://github.com/ikostan/SkyLockAssault/commits?author=sourcery-ai[bot]" title="Code">💻</a> <a href="https://github.com/ikostan/SkyLockAssault/commits?author=sourcery-ai[bot]" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/apps/qodo-code-review"><img src="https://avatars.githubusercontent.com/in/484649?v=4&size=100" width="100px" height="100px" alt="Qodo"/><br /><sub><b>Qodo</b></sub></a><br /><a href="https://github.com/ikostan/SkyLockAssault/pulls?q=is%3Apr+reviewed-by%3Aqodo-code-review[bot]" title="Reviewed Pull Requests">👀</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/apps/deepsource-io"><img src="https://avatars.githubusercontent.com/in/16372?v=4&size=100" width="100px" height="100px" alt="DeepSource"/><br /><sub><b>DeepSource</b></sub></a><br /><a href="https://github.com/ikostan/SkyLockAssault/pulls?q=is%3Apr+reviewed-by%3Adeepsource-io[bot]" title="Reviewed Pull Requests">👀</a> <a href="#security-deepsource-io[bot]" title="Security">🛡️</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/apps/deepsource-autofix"><img src="https://avatars.githubusercontent.com/in/57168?v=4&size=100" width="100px" height="100px" alt="DeepSource Autofix"/><br /><sub><b>DeepSource Autofix</b></sub></a><br /><a href="#maintenance-deepsource-autofix[bot]" title="Maintenance">🚧</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/apps/dependabot"><img src="https://avatars.githubusercontent.com/in/29110?v=4&size=100" width="100px" height="100px" alt="Dependabot"/><br /><sub><b>Dependabot</b></sub></a><br /><a href="#infra-dependabot[bot]" title="Infrastructure (Hosting, Build-Tools, etc)">🚇</a> <a href="#security-dependabot[bot]" title="Security">🛡️</a> <a href="#maintenance-dependabot[bot]" title="Maintenance">🚧</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/ImgBotApp"><img src="https://avatars.githubusercontent.com/u/31427850?v=4&size=100" width="100px" height="100px" alt="ImgBot"/><br /><sub><b>ImgBot</b></sub></a><br /><a href="#maintenance-ImgBotApp" title="Maintenance">🚧</a></td>
    </tr>
  </tbody>
</table>
<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

**This project is currently closed to external code contributions.**
However, if you find a bug or have feedback, you are welcome to open a
GitHub issue. See [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

---

## License

This project is **source-available** under the
[PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0).

- Free for noncommercial purposes (personal study, hobby projects, eligible
  noncommercial organizations)
- Modification and redistribution allowed **only** for non-commercial purposes
- **Commercial use is prohibited** without a separate commercial license

For commercial licensing inquiries, open a GitHub issue or contact via X
[@EgorKostan](https://x.com/EgorKostan).

See the [LICENSE](LICENSE) file for full terms.

---

## Security

For details on reporting vulnerabilities and our disclosure process, see
[SECURITY.md](.github/SECURITY.md).

---

## Player Feedback

We value your input! Share thoughts, bugs, or suggestions via:

- [GitHub Discussions](https://github.com/ikostan/SkyLockAssault/discussions) -
  all the hottest features ar here, share your opinion
- [itch.io Comments](https://ikostan.itch.io/sky-lock-assault) — discuss
  gameplay directly on the game page
- [GitHub Issues](https://github.com/ikostan/SkyLockAssault/issues) — bug
  reports and feature requests

<!-- markdownlint-enable MD001 MD013 MD036 MD033 table-column-style -->
