### Generating AI-Driven Tests for Audio Settings in SkyLockAssault
<!-- markdownlint-disable line-length -->

This guide outlines the process for generating AI-driven tests
using Playwright MCP in a Godot 4.5 project. The focus is on the
audio settings menu, including sliders for master, music, SFX,
weapon, and rotors volumes; mute toggles; warning popups; and
reset/back buttons. All tests use the "Web_thread_off" export
preset due to compatibility issues with multi-threading and the
Python HTTP server.

This setup assumes the SkyLockAssault repository is cloned and
Docker Desktop is installed. The unified Docker image includes
Godot 4.5, Playwright MCP, and Xvfb for headless testing.

#### Step 1: Prepare the Local Environment
- Clone or update the repository from https://github.com/ikostan/SkyLockAssault.
- Verify custom_shell.html is in res:// for JS overlays (e.g., #master-slider, #mute-master).
- Build the Docker image from the repository root (where Dockerfile is):
  ```
  docker build -t skylock-test-env .
  ```

#### Step 2: Run the Docker Container Interactively
- Start the container with the repository mounted:
  ```
  docker run -it -p 8080:8080 -v ${PWD}:/project --name skylock-mcp skylock-test-env /bin/bash
  ```
- To open additional sessions while the container runs (e.g., one for the server, another for MCP):
  ```
  docker exec -it skylock-mcp /bin/bash
  ```

#### Step 3: Export the Game to HTML5 Inside the Container
- In a container shell:
  ```
  mkdir -p web_thread_off
  godot --headless --path /project --export-release "Web_thread_off" web_thread_off/index.html
  ```
- Verify the export in web_thread_off includes index.html and supporting files.

#### Step 4: Start the Local Web Server
- In a container shell:
  ```
  python3 -m http.server 8080 --directory web_thread_off &
  ```
- Confirm readiness with `curl http://localhost:8080/index.html`.
- Access http://localhost:8080 from a host browser to verify the audio menu (Main Menu > Options > Audio).
- To stop the server: `kill %1` or bring to foreground with `fg` then press Ctrl+C.

#### Step 5: Generate AI-Driven Tests with Playwright MCP
- In a separate container shell (using docker exec if needed):
  ```
  xvfb-run npx mcp generate --url http://localhost:8080 --prompt "Generate E2E Playwright tests for the audio settings menu in this Godot HTML5 game. Focus on: Navigating from main menu to options > audio; Interacting with sliders (#master-slider, #music-slider, #sfx-slider, #weapon-slider, #rotors-slider) by dragging/changing values; Toggling mutes (#mute-master, etc.) and verifying warnings pop up when adjusting muted sliders (e.g., master muted blocks others); Testing reset button restores defaults; Back button exits menu; Changes persist on reload/renavigate. Use expect() for assertions on visibility, values, and console logs if needed. Handle any loading delays with waits."
  ```
- Customize the prompt for specific elements from audio_settings.gd and custom_shell.html.
- Use options like `--count 3` or `--output tests/mcp-audio`.

#### Step 6: Run, Polish, and Iterate on Generated Tests
- In a container shell:
  ```
  xvfb-run npx playwright test tests/mcp-audio/audio-settings.spec.ts --headed
  ```
- Edit .spec.ts files for refinements (e.g., add timeouts).
- Rerun MCP with updated prompts as needed.

#### Step 7: Clean Up
- Stop the server as described.
- Exit shells: `exit`.
- Stop and remove the container: `docker stop skylock-mcp; docker rm skylock-mcp`.
- Commit polished tests to the repository for CI integration.

Track issues or discussions on GitHub for further refinements.
<!-- markdownlint-enable line-length -->
