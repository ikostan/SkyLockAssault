# Setup Instructions for Sky Lock Assault

This document covers the initial setup for developing and testing the project
on Windows 10 64-bit.

## Prerequisites

- **Godot Engine**: v4.5 stable (download from
  [godotengine.org/download](https://godotengine.org/download)).
- **GitHub Desktop**: v3.5 (for repo cloning/management).
- **Docker Desktop**: v4.45 (for local web testing).
- **PyCharm Community Edition**: 2024.1.7 (optional, for editing files
  like GDScript/Markdown).
- **Windows PowerShell**: For running Docker commands (built-in).

## Requiring Signed Commits on Main

To enforce security:

1. Go to repo `settings` > `Branches` > Add rule for `main`.
2. Enable "Require signed commits."

This blocks unsigned pushes, ensuring trustworthy Godot exports.

### Step 1: Clone the Repository

1. Open GitHub Desktop.
2. Clone the repo: URL = <https://github.com/ikostan/SkyLockAssault>.
3. Open the project in Godot: Launch Godot > Import > Select
   `project.godot` in the cloned folder.

### Step 2: Install Export Templates

1. In Godot Editor: Go to Editor > Manage Export Templates.
2. Download the templates for version 4.5 (or manually from
   [godotengine.org/download/archive/4.5-stable](https://godotengine.org/download/archive/4.5-stable/)).
3. This enables HTML5/Web exports for Milestone 3 features.

**Troubleshooting**: If templates fail to download, ensure internet access
and restart Godot.

### Step 3: Set Up GDUnit4 for Testing

1. In Godot Editor:
   Go to `AssetLib (top menu) > Search for "GDUnit4" > Install v5.1.1`.
2. Restart Godot to enable.
3. Create a `tests/` folder in the project root for unit tests
   (e.g., `test_quit.gd`).

This is required for automated testing in Milestone 3.

### Step 4: Export to Web (HTML5)

1. In Godot: Project > Export > Add Preset > Select "Web".
2. Set Export Path: `export/web/index.html` (create `export/web/` if needed).
3. Enable "Runnable" and export the project.
4. This generates files like index.html, .wasm for browser deployment.

### Step 5: Local Testing with Docker

1. Install Docker Desktop if not already (from docker.com).
2. In PowerShell: Navigate to repo root > `cd infra/`.
3. Run: `docker compose up -d` (starts a local Nginx server).
4. Open browser: <http://localhost:9090> (view the exported game).
5. Stop: `docker compose down`.

**Notes**: For fullscreen testing, note the harmless console warning on desktop
(ignored per Issue #100). Test quit handling here before itch.io deploy.

### Additional Tools

- **PyCharm**: Open the repo folder for editing `GDScript/Markdown`. No special
  config needed.
- **GitHub Actions**: Enabled via `.github/workflows/`, runs on `push/PR` for
  `lint/test/deploy`.

Once set up, run the game in editor (F5) or web export. For issues, check Godot
console or browser dev tools (F12).
