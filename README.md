# Sky Lock Assault

## A top-down online web browser game built with Godot 4.4

This is a dedicated Godot v4.4 game dev project on Windows 10 64-bit OS.
We'll be learning game dev here, starting with a simple main menu and expanding
to core mechanics like player controls, enemy AI, and assaults in the sky.
The repo is open-source at [SkyLockAssault](https://github.com/ikostan/SkyLockAssault).

## Project Overview

- **Godot Version**: 4.4.1 stable (or compatible).
- **OS**: Windows 10 64-bit.
- **Tools**: Docker Desktop v4.45 for local testing, GitHub Desktop v3.5
  for repo management.
- **Goal**: Build a playable top-down shooter with web deployment in mind—export
  to HTML5/Web, test locally, deploy to itch.io.

Current features:

- Main menu scene (`main_menu.tscn`) with buttons (Start, Resume, Options, Quit).
- Placeholder game level (`game_level.tscn`) for future mechanics.

## Setup Instructions

1. **Clone the Repo**:
   - Use GitHub Desktop: Clone https://github.com/ikostan/SkyLockAssault.
   - Open in Godot 4.4: Launch Godot > Import > Select `project.godot`.

2. **Install Export Templates**:
   - In Godot: Editor > Manage Export Templates > Download for 4.4.1
     (or manual from https://godotengine.org/download/archive/4.4.1-stable/).
   - Required for Web exports.

3. **Export to Web**:
   - Project > Export > Add Web preset.
   - Export to `export/web/` folder in the project root.
   - This generates index.html, .wasm, .js, etc., for browser testing.

## Docker Local Test Server

To mimic itch.io hosting locally (for testing Web exports in browsers like Chrome/Firefox
without uploading every time), we use a Docker-based Nginx server. This handles static
files with required headers for Godot Web (e.g., COEP/COOP for WASM security). It's
great for learning deployment flows before GitHub CI/CD pushes to itch.io.

### Prerequisites

- Docker Desktop v4.45 installed and running
  (download from https://www.docker.com/products/docker-desktop/).
- Project exported to `export/web/` (see above).
- infra/ folder in project root with:
  - `docker-compose.yml`
  - `nginx/default.conf` (no .txt extension—rename via File Explorer if needed).

### docker-compose.yml Content

Paste this into `infra/docker-compose.yml` (use 2 spaces for indentation, no tabs):
<!-- markdownlint-disable-line MD013 -->

```yaml
services:
  godot_web_server:
	image: nginx:latest
	container_name: sky_lock_assault_server
	ports:
	  - "9090:80"  # Local port 9090 to container 80; change if conflicted (e.g., to 8080:80)
	restart: unless-stopped
	volumes:
	  - ../export/web:/usr/share/nginx/html:ro  # Mount your Web export folder read-only
	  - ./nginx:/etc/nginx/conf.d  # Mount custom Nginx config folder
```

### Nginx Config (default.conf)

Paste this into `infra/nginx/default.conf`(rename from .txt via File Explorer if Godot adds it):

```nginx
server {
	listen 80;
	server_name localhost;

	add_header Cross-Origin-Embedder-Policy 'require-corp';
	add_header Cross-Origin-Opener-Policy 'same-origin';

	location / {
		root /usr/share/nginx/html;
		index index.html index.htm;
		try_files $uri $uri/ =404;

		types {
			application/wasm wasm;
			text/html html;
			application/javascript js;
			text/css css;
		}
	}
}
```

<!-- markdownlint-enable-line MD013 -->

### Running the Docker Server

1. Open PowerShell or cmd as admin (search "PowerShell", right-click > Run as administrator).
2. Navigate to infra folder:

   ```bash
   cd C:\Users\super\Documents\GitHub\SkyLockAssault\infra
   ```
3. Start the container (detached mode):
   ```bash
   docker compose up -d
   ```
   - First run pulls Nginx (may take a minute).
   - Check status: `docker ps` (should show sky_lock_assault_server running).
4. Test in browser: http://localhost:9090
   - Your game menu should load. Click Start to test game_level (even if placeholder).
   - Use browser dev tools (F12) to check console for errors (e.g., WASM loading).
5. Stop the container:
   ```bash
   docker compose down
   ```
6. Restart after changes (e.g., new export):
   ```bash
   docker compose restart
   ```
7. View logs for debugging:
   ```bash
   docker logs sky_lock_assault_server
   ```
   - Look for no errors like "default.conf not found."

### Troubleshooting

- **Empty compose file error**: Check indentation in docker-compose.yml—use spaces, not tabs.
  Recreate file if corrupted.
- **Config not found in logs**: Ensure default.conf (no .txt) is in infra/nginx/. Restart Docker Desktop
  if mounts fail.
- **Port conflict**: Change ports line to e.g., "8080:80" if 9090 is used.
- **No game loads**: Confirm export/web/ has files (re-export). Test manually with Python:
  `python -m http.server 8000 --directory export/web`, browse http://localhost:8000.
- **WASM errors in browser**: Headers in config fix most—inspect network tab.
- **Docker not starting**: Ensure Docker Desktop is running (tray icon green). Restart PC if issues.

This Docker setup promotes good habits for learning web game deployment—test locally, then automate with
GitHub Actions for itch.io.
