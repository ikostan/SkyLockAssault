# Docker Local Test Server

To mimic itch.io hosting locally (for testing Web exports in browsers like Chrome/Firefox
without uploading every time), we use a Docker-based Nginx server. This handles static
files with required headers for Godot Web (e.g., COEP/COOP for WASM security). It's
great for learning deployment flows before GitHub CI/CD pushes to itch.io.

## Prerequisites

- Docker Desktop v4.45 installed and running
  (download from https://www.docker.com/products/docker-desktop/).
- Project exported to `export/web/` (see above).
- infra/ folder in project root with:
  - `docker-compose.yml`
  - `nginx/default.conf` (no .txt extension—rename via File Explorer if needed).

### How-to Guides

<!-- markdownlint-disable MD033 -->
<details>
  <summary><b>Docker file: docker-compose.yml</b></summary>

Paste this into `infra/docker-compose.yml` (use 2 spaces for indentation, no tabs):

<!-- markdownlint-disable line-length -->

```yaml
services:
  godot_web_server:
    image: nginxinc/nginx-unprivileged:1.27-alpine  # Switch to unprivileged image; handles non-root natively
    container_name: sky_lock_assault_server
    ports:
      - "127.0.0.1:9090:8080"  # Map host 9090 to container 8080 (unprivileged default)
    restart: unless-stopped
    volumes:
      - ../export/web:/usr/share/nginx/html:ro
      - ./nginx:/etc/nginx/conf.d
    # Remove 'user: "nginx:nginx"' - image runs as non-root by default
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "8080"]  # Update to probe port 8080
      interval: 30s
      timeout: 10s
      retries: 3
```
</details>

<details>
  <summary><b>Nginx Config: default.conf</b></summary>

Paste this into `infra/nginx/default.conf`(rename from .txt via File Explorer if Godot adds it):

```nginx
server {
    listen 8080;  # Change from 80 to match unprivileged default
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
</details>
<!-- markdownlint-enable line-length -->
<details>
  <summary><b>Running the Docker Server</b></summary>

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
</details>
<details>
  <summary><b>Troubleshooting</b></summary>

- **Empty compose file error**: Check indentation in docker-compose.yml—use spaces,
  not tabs. Recreate file if corrupted.
- **Config not found in logs**: Ensure default.conf (no .txt) is in infra/nginx/.
  Restart Docker Desktop if mounts fail.
- **Port conflict**: Change ports line to e.g., "8080:80" if 9090 is used.
- **No game loads**: Confirm export/web/ has files (re-export). Test manually with
  Python:
  ```bash
  python -m http.server 8000 --directory export/web
  ```
- browse http://localhost:8000.
- **WASM errors in browser**: Headers in config fix most—inspect network tab.
- **Docker not starting**: Ensure Docker Desktop is running (tray icon green).
  Restart PC if issues.

This Docker setup promotes good habits for learning web game deployment—test locally,
then automate with GitHub Actions for itch.io.
</details>
<!-- markdownlint-enable MD033 -->
