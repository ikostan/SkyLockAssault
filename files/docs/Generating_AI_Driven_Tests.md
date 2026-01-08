### Generating AI-Driven Tests for Audio Settings in SkyLockAssault

Hey there! Since this is our Godot 4.5 game dev project on Windows 10 64-bit, we'll keep things hands-on and educational. We're building skills in testing Godot HTML5 exports, especially for features like the audio settings menu (sliders for master/music/SFX/weapon/rotors, mute toggles, warning popups, and reset/back buttons). Playwright MCP (Microsoft's AI-driven tool) will help generate end-to-end (E2E) tests automatically, which we can then run, polish, and learn from. This fits perfectly into our learning journey—testing ensures our audio mechanics work smoothly in the browser, like verifying volume changes persist or warnings trigger when trying to adjust muted sliders.

These instructions assume you've cloned the SkyLockAssault repo (e.g., via GitHub Desktop) and have Docker Desktop installed/running on your Win10 machine. If not, start with the Setup Instructions doc in the repo. We'll use our unified Docker image (with Godot, Playwright Python/Node, MCP, and Xvfb for headless testing) to keep everything local and consistent—no need for separate envs.

#### Step 1: Prepare Your Local Environment
- **Clone/Update the Repo**: Open GitHub Desktop, clone https://github.com/ikostan/SkyLockAssault if you haven't, or pull the latest changes. This gets you the latest audio_settings.gd, custom_shell.html (with JS overlays for sliders/mutes), and other assets.
- **Check Custom HTML Template**: Ensure custom_shell.html is in your project (under export templates or res://). It includes invisible overlays like #master-slider, #mute-master, etc., which MCP will interact with via Playwright selectors.
- **Build the Docker Image**: From PowerShell in the repo root (where Dockerfile is):
  ```
  docker build -t skylock-test-env .
  ```
  This builds our image with Godot 4.5, Playwright MCP, and all tools. If you've already built it, skip or use `--no-cache` for updates.
- **Learning Tip**: While building, review the Dockerfile—see how we install Node-based MCP alongside Python Playwright? This teaches multi-tool integration in Godot projects.

#### Step 2: Run the Docker Container Interactively
- Start a container with your repo mounted (from PowerShell in repo root):
  ```
  docker run -it -p 8080:8080 -v ${PWD}:/project --name skylock-mcp skylock-test-env /bin/bash
  ```
  - `-it`: Interactive shell (you're now inside as godotuser).
  - `-p 8080:8080`: Exposes the web server port—access http://localhost:8080 from your Win10 browser later.
  - `-v ${PWD}:/project`: Mounts your local repo to /project inside, so changes persist.
- If the container's already running, attach with `docker exec -it skylock-mcp /bin/bash`.
- **Learning Tip**: This setup mimics a Linux env for CI/CD testing, helping you debug Godot web exports early. Run `godot --version` inside to confirm it's 4.5 stable.

#### Step 3: Export the Game to HTML5 Inside the Container
- Once in the container shell:
  ```
  mkdir -p export/web
  godot --headless --path /project --export-release "Web" export/web/index.html
  ```
- This creates an HTML5 build in /project/export/web (visible on your host machine too, thanks to the mount).
- **Verify the Export**: Check for index.html and the .js/wasm files. Open http://localhost:8080 in your browser later to play/test manually—ensure the audio menu loads (Main Menu > Options > Audio).
- **Learning Tip**: Godot's --headless export is great for automation. Notice how custom_shell.html injects JS callbacks like window.change_master_volume? These bridge Godot signals to browser elements, key for E2E tests.

#### Step 4: Start the Local Web Server
- Still in the container:
  ```
  python3 -m http.server 8080 --directory export/web &
  ```
- Wait 5-10 seconds, then test with `curl http://localhost:8080/index.html` (should return HTML).
- From your Win10 browser, visit http://localhost:8080 to confirm the game runs. Navigate to the audio menu and tweak sliders/mutes—note warnings (e.g., "Unmute Master first") and persistence on reload.
- **Learning Tip**: This simple server simulates itch.io deployment. For audio testing, play sounds in-game to verify changes (e.g., mute SFX and check if weapon/rotor noises stop).

#### Step 5: Generate AI-Driven Tests with Playwright MCP
- In the container (server still running in background):
  ```
  xvfb-run npx mcp generate --url http://localhost:8080 --prompt "Generate E2E Playwright tests for the audio settings menu in this Godot HTML5 game. Focus on: Navigating from main menu to options > audio; Interacting with sliders (#master-slider, #music-slider, #sfx-slider, #weapon-slider, #rotors-slider) by dragging/changing values; Toggling mutes (#mute-master, etc.) and verifying warnings pop up when adjusting muted sliders (e.g., master muted blocks others); Testing reset button restores defaults; Back button exits menu; Changes persist on reload/renavigate. Use expect() for assertions on visibility, values, and console logs if needed. Handle any loading delays with waits."
  ```
- **Key Options**:
  - `--url`: Points to your local game.
  - `--prompt`: Customize this! Be specific about audio elements (from audio_settings.gd and custom_shell.html) to get better AI-generated tests. Add `--model gpt-4` if you want a specific AI (check MCP docs: `npx mcp --help`).
  - `--count 3`: Generate 3 test variations for comparison.
  - `--output tests/mcp-audio`: Save to a folder (e.g., /project/tests/mcp-audio).
- MCP will output .spec.ts files (TypeScript Playwright tests). Review them—e.g., they might include `await page.locator('#master-slider').dragTo(...)` or checks for dialog text like "Warning: To adjust this volume, please unmute...".
- **Learning Tip**: MCP uses AI to "understand" the page via Playwright. Study the generated code: It teaches selectors (e.g., by ID for overlays), async waits for Godot loading, and assertions. This builds your testing skills for Godot web games.

#### Step 6: Run, Polish, and Iterate on Generated Tests
- Run the tests (in container, with Xvfb for headless):
  ```
  xvfb-run npx playwright test tests/mcp-audio/audio-settings.spec.ts --headed  # --headed shows browser for debugging
  ```
- Watch for passes/fails. If failures, edit the .ts files (e.g., add timeouts: `await page.waitForSelector('#audio-back-button', { timeout: 5000 })`).
- Polish:
  - Add more assertions: E.g., check AudioManager states via exposed JS (if window globals are set).
  - Handle flags like master_warning_shown for CI reliability.
  - Integrate with existing tests: Move polished ones to /project/tests/ and run via run_browser_tests.sh.
- Rerun MCP with refined prompts if needed (e.g., "Improve previous tests to cover rotor panning and JS callbacks").
- **Learning Tip**: Debugging here teaches Godot-JS bridging. Use Playwright's trace viewer (`npx playwright show-trace trace.zip`) to visualize steps—great for understanding audio UI flows.

#### Step 7: Clean Up and Next Steps
- Stop the server: `kill %1` (or fg + Ctrl+C).
- Exit container: `exit`.
- Stop/remove: From PowerShell, `docker stop skylock-mcp; docker rm skylock-mcp`.
- Commit polished tests to the repo—add to CI via run_pipeline.sh for auto-runs.
- **Troubleshooting**:
  - MCP errors? Check Node deps (`npm ls playwright-mcp`).
  - Game not loading? Verify export includes audio assets; test manually.
  - Warnings in console? Normal for web (e.g., orientation)—focus on audio logic.
- **Expansion Ideas**: Once comfy, generate tests for fuel/speed (Issue #276) or multiplayer (Issue #34). This scales our learning from basic menus to complex mechanics!

This process keeps our project testable and fun—let's iterate and make SkyLockAssault rock-solid! If issues pop up, check the Docker Local Test Server doc or ping in GitHub Discussions. 🚀
