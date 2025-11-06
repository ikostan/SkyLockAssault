# tests/difficulty_integration_test.py
"""
Difficulty Integration Test (Playwright, Python)
================================================

Overview
--------
This module contains an end-to-end integration test that verifies difficulty selection
propagates correctly from the options menu into gameplay. The test automates the browser
with Playwright (sync API), drives the Godot HTML5 export via mouse/keyboard, and
asserts on console log messages emitted by the game to validate behavior.

Specifically, the test:
- Loads the game at http://localhost:8080/index.html and verifies the canvas and title.
- Opens Options, sets Log Level to DEBUG to surface detailed logs.
- Sets Difficulty to 2.0 by clicking fixed offsets relative to the game canvas
  (see tests/ui_elements_coords.py for coordinates).
- Returns to the main menu and starts the game.
- Fires the weapon and idles to allow fuel consumption.
- Asserts on expected logs for log level change, navigation, weapon cooldown scaling,
  and fuel depletion under the chosen difficulty. It also records JavaScript coverage via
  the Chrome DevTools Protocol (CDP) as a workaround for missing Playwright Python coverage API.

Prerequisites
-------------
- A local server hosting the game at http://localhost:8080/index.html (see files/docs/Docker_Local_Test_Server.md).
- Python with pytest and Playwright installed. Example:
  - pip install pytest playwright
  - playwright install chromium
- The Godot HTML5 build should emit console logs used by this test, including:
  - "Options button pressed."
  - "Options menu loaded."
  - "Back button pressed."
  - "Start Game menu button pressed."
  - "Log level changed to: DEBUG"
  - "Difficulty changed to: 2.0"
  - "Firing with scaled cooldown: 1.0"
  - "Fuel left: <value>"

How It Works
------------
- The test uses a headless Chromium browser with flags to favor software rendering on CI
  ("--enable-unsafe-swiftshader", "--disable-gpu", "--use-gl=swiftshader").
- It creates a CDP session to start precise JavaScript coverage collection for V8, then
  listens to browser console events to gather logs for assertions.
- UI interactions use absolute coordinates calculated as: canvas bounding box origin +
  element offset from tests/ui_elements_coords.py. This makes the test resilient to
  page chrome but sensitive to layout changes inside the canvas.
- Assertions rely on the presence of specific console log messages and on a fuel
  threshold check (final fuel must be < 85.0 after idling under difficulty 2.0).

Artifacts
---------
- coverage_difficulty_integration_test.json: V8 coverage captured via CDP and saved at teardown.
- artifacts/test_difficulty_integration_failure_*.png: Screenshot on failure.
- artifacts/test_difficulty_integration_failure_console_logs.txt: Console logs on failure.

Running the Test
----------------
- Run only this test: pytest -k difficulty_integration_test -q
- Breakdown of the Command
    * `pytest`: The command to run pytest, the Python testing framework used for your Playwright
    tests (e.g., difficulty_integration_test.py).
    * `-k difficulty_integration_test`: Filters tests to run only those whose names
    (function, class, or module) contain the substring difficulty_integration_test.
    In your project, this matches the test_difficulty_integration function in
    tests/difficulty_integration_test.py, ensuring only this test runs.
    * `-q`: Short for --quiet, reduces pytest’s output to minimal information, showing only a
    summary (e.g., dots for passing tests, F for failures) instead of detailed logs.
    This is useful for quick runs or CI environments where you want concise output.
- If the game loads slowly (WASM/scene init), the test includes generous waits, but you
  may extend timeouts if your environment is slower.
- For debugging, consider running the browser in headed mode by adjusting the fixture
  to headless=False.

Maintenance Notes
-----------------
- If UI layout changes, update tests/ui_elements_coords.py to match new element offsets.
- Keep asserted log strings in sync with the Godot scripts (options_menu.gd, main_menu.gd,
  weapon.gd, etc.).
- Balance changes to fuel or weapon cooldown may require adjusting thresholds or asserted
  log values.
"""

import os
import time
import pytest
import json  # For saving coverage data
from playwright.sync_api import Page
from ui_elements_coords import UI_ELEMENTS  # Import the coordinates dictionary


@pytest.fixture(scope="function")
def page(playwright: "playwright") -> Page:
    """
    Provision a Chromium Page for each test run.

    Launches headless Chromium with SwiftShader-friendly flags for CI stability and
    uses a fixed 1280x720 viewport to keep canvas-relative UI coordinates stable.

    Returns
    -------
    Page
        A Playwright Page instance bound to a fresh browser context.
    """
    browser = playwright.chromium.launch(
        headless=True,
        args=["--enable-unsafe-swiftshader", "--disable-gpu", "--use-gl=swiftshader"]
    )
    context = browser.new_context(viewport={"width": 1280, "height": 720})
    page = context.new_page()
    yield page
    page.close()
    context.close()
    browser.close()


def test_difficulty_integration(page: Page):
    """
    Full flow validation that difficulty 2.0 affects gameplay systems.

    The test navigates menus, sets log level to DEBUG, selects difficulty 2.0 using
    canvas-relative clicks from ``tests/ui_elements_coords.py``, and verifies via
    console logs that cooldown scaling and fuel consumption reflect the selected
    difficulty. It also captures V8 coverage through CDP and stores it at teardown.
    """
    logs: list = []
    cdp_session = None
    try:
        # Start CDP session for V8 JS coverage (workaround for Python Playwright lacking native coverage API)
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage", {"callCount": True, "detailed": True})

        # Set up console log capture
        page.on("console", lambda msg: logs.append({"type": msg.type, "text": msg.text}))

        # Navigate to game and wait for load
        page.goto("http://localhost:8080/index.html")
        page.wait_for_timeout(10000)  # Increased to match passing tests; allows time for WASM/init/delays
        # Optional: Add explicit wait for Godot initialization if set in main_menu.gd _ready()
        page.wait_for_function("() => window.godotInitialized", timeout=1000)

        # Verify canvas and title to ensure the game is initialized
        canvas = page.locator("canvas")
        page.wait_for_selector("canvas", state="visible", timeout=7000)
        box = canvas.bounding_box()
        assert box, "Canvas not found on page"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Set log level to DEBUG
        # Open options menu
        options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
        options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
        page.mouse.click(options_x, options_y)
        page.wait_for_timeout(3000)
        # assert any("Options menu loaded." in log["text"] for log in logs), "Options menu failed to load"

        # Click log level dropdown
        log_dropdown_x = box['x'] + UI_ELEMENTS["log_level_dropdown"]["x"]
        log_dropdown_y = box['y'] + UI_ELEMENTS["log_level_dropdown"]["y"]
        page.mouse.click(log_dropdown_x, log_dropdown_y)
        page.wait_for_timeout(3000)

        # Select DEBUG
        debug_item_x = box['x'] + UI_ELEMENTS["log_level_debug"]["x"]
        debug_item_y = box['y'] + UI_ELEMENTS["log_level_debug"]["y"]
        page.mouse.click(debug_item_x, debug_item_y)
        page.wait_for_timeout(3000)
        assert any("Log level changed to: DEBUG" in log["text"] for log in logs), "Failed to set log level to DEBUG"

        # Back to main menu
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        page.mouse.click(back_x, back_y)
        page.wait_for_timeout(3000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

        # Open options menu again
        page.mouse.click(options_x, options_y)  # Click Options button
        page.wait_for_timeout(5000)  # Wait for options menu to load
        assert any("Options button pressed." in log["text"] for log in logs), "Options menu not found"
        # Assert that no unexpected error messages are present in the logs
        unexpected_errors = [
            log for log in logs
            if any(
                error_keyword in log["text"]
                for error_keyword in ["Error", "Exception", "Traceback"]
            )
        ]
        assert not unexpected_errors, f"Unexpected error messages found in logs: {unexpected_errors}"
        assert any("Options menu loaded." in log["text"] for log in logs), "Options menu is not loaded"

        # Set difficulty to 2.0 (absolute position derived from stable UI coordinates)
        slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_2.0"]["x"]
        slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_2.0"]["y"]
        page.mouse.click(slider_x, slider_y)  # Click to set 2.0
        page.wait_for_timeout(3000)
        assert any("Difficulty changed to: 2.0" in log["text"] for log in logs), "Change to 2.0 failed"

        # Back to main menu
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        page.mouse.click(back_x, back_y)  # Click Back button
        page.wait_for_timeout(3000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

        # Start level
        start_x = box['x'] + UI_ELEMENTS["start_game_button"]["x"]
        start_y = box['y'] + UI_ELEMENTS["start_game_button"]["y"]
        page.mouse.click(start_x, start_y)  # Click Start button
        page.wait_for_timeout(5000)  # Increased for level load
        assert any("Start Game menu button pressed." in log["text"] for log in logs), "Start Game button not found"

        # Simulate fire to assert cooldown scaling, then idle to accumulate fuel logs
        page.keyboard.press("Space")
        page.wait_for_timeout(5000)
        assert any("Firing with scaled cooldown: 0.3" in log["text"] for log in logs), "Weapon scaling failed: expected 0.3 (0.15 × 2.0)"

        page.wait_for_timeout(10000)
        fuel_logs = [log for log in logs if "Fuel left:" in log["text"]]
        assert len(fuel_logs) > 0, "No fuel logs"

        last_fuel = float(fuel_logs[-1]["text"].split("Fuel left: ")[1])
        assert last_fuel < 85.0, f"Fuel scaling failed: got {last_fuel}"
    except Exception as e:
        # Save screenshot
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_difficulty_integration_failure_{int(time.time())}.png")
        print(f"Test: Difficulty integration test failed: {str(e)}")
        # Save logs to file (in case teardown fixture is skipped)
        log_file = "artifacts/test_difficulty_integration_failure_console_logs.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        print(f"Console logs saved to {log_file}")
        raise
    finally:
        if cdp_session:
            # Stop V8 coverage and save to file (even on failure)
            coverage = cdp_session.send("Profiler.takePreciseCoverage")['result']
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_difficulty_integration_test.json", "w") as f:
                json.dump(coverage, f)
