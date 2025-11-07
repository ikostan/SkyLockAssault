# tests/difficulty_flow_test.py
"""
Difficulty Flow Test (Playwright, Python)
========================================

Overview
--------
This end-to-end browser test validates the user flow of setting game difficulty to 2.0
from the options menu and verifying that the change takes effect when starting the game.
It uses Playwright (sync API) to drive a headless Chromium instance, interacts with the
Godot HTML5 build via coordinate-based clicks, listens for console logs, and records V8
coverage through the Chrome DevTools Protocol (CDP).

Test Flow
---------
- Launch headless Chromium with software rendering-friendly flags for CI stability.
- Create a CDP session to capture precise JavaScript coverage and subscribe to console logs.
- Navigate to http://localhost:8080/index.html, verify the canvas is visible and the title contains "SkyLockAssault".
- Open Options, set log level to DEBUG, and return to the main menu.
- Reopen Options and set Difficulty to 2.0 by clicking offsets relative to the canvas
  (coordinates defined in tests/ui_elements_coords.py).
- Start the game; after the level loads, simulate a weapon fire (Space).
- Assert presence of key console logs for navigation, difficulty change, and weapon
  cooldown scaling under difficulty 2.0.

Prerequisites
-------------
- Local server hosting the game at http://localhost:8080/index.html.
- Python with pytest and Playwright installed:
  - pip install pytest playwright
  - playwright install chromium
- The HTML5 build must emit the console logs used by this test, e.g.:
  - "Options button pressed."
  - "Options menu loaded."
  - "Back button pressed."
  - "Start Game menu button pressed."
  - "Loading main game scene..."
  - "Log level changed to: DEBUG"
  - "Difficulty changed to: 2.0"
  - "Firing with scaled cooldown: 1.0"

How It Works
------------
- Absolute click positions are calculated as: canvas bounding box origin + offsets from
  tests/ui_elements_coords.py. This makes the flow robust against page chrome but
  sensitive to in-canvas layout shifts.
- The test asserts on the presence of log messages to validate that UI interactions and
  gameplay state changes occurred as expected.
- Precise V8 coverage is collected via CDP and saved at teardown for optional analysis.

Artifacts
---------
- v8_coverage_difficulty_flow_test.json: Precise V8 coverage dump.
- artifacts/test_difficulty_failure_*.png: Failure screenshot.
- artifacts/test_difficulty_failure_console_logs.txt: Failure console logs.

Running
-------
- Execute only this test: pytest -k difficulty_flow_test -q
- Increase waits or switch to headed mode (headless=False) if timing is tight in your environment.

Maintenance Notes
-----------------
- Update tests/ui_elements_coords.py if menu layout changes; keep asserted log strings in
  sync with the Godot scripts (main_menu.gd, options_menu.gd, weapon.gd).
- Adjust asserted strings/thresholds if gameplay balance or log text changes.
"""

import os
import re
import time
import json  # Added for saving coverage data
import pytest
from playwright.sync_api import Page
from .ui_elements_coords import UI_ELEMENTS  # Import the coordinates dictionary


@pytest.fixture(scope="function")
def page(playwright: "playwright") -> Page:
    """
    Provide a fresh Chromium Page per test.

    Launches headless Chromium with SwiftShader flags for CI stability and creates
    a context with a fixed 1280x720 viewport to keep UI coordinates stable.

    Returns
    -------
    Page
        A Playwright Page instance tied to the created browser context.
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


def test_difficulty_flow(page: Page):
    """
    Set difficulty to 2.0 via options and validate gameplay effect.

    Uses canvas-relative clicks from ``tests/ui_elements_coords.py`` and asserts
    on console logs for navigation, difficulty change, and weapon cooldown
    scaling. Captures precise V8 coverage via CDP and persists it at teardown.
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
        page.wait_for_timeout(10000)  # Increased significantly for WASM/scene init

        # Verify canvas and title to ensure game is initialized
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
        assert any("Options menu loaded." in log["text"] for log in logs), "Options menu is not loaded"

        # Drag slider to 2.0 (position derived from stable UI coordinates)
        slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_2.0"]["x"]
        slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_2.0"]["y"]
        page.mouse.click(slider_x, slider_y)  # Move to 2.0 position
        page.wait_for_timeout(3000)
        assert any("Difficulty changed to: 2.0" in log["text"] for log in logs), "Expected change to 2.0"

        # Back to main menu
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        page.mouse.click(back_x, back_y)  # Click Back button
        page.wait_for_timeout(3000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

        # Start game
        start_x = box['x'] + UI_ELEMENTS["start_game_button"]["x"]
        start_y = box['y'] + UI_ELEMENTS["start_game_button"]["y"]
        page.mouse.click(start_x, start_y)  # Click Start button
        page.wait_for_timeout(5000)
        assert any("Start Game menu button pressed." in log["text"] for log in logs), "Start Game button not found"
        assert any("Loading main game scene..." in log["text"] for log in logs), "Main game scene is failed to load"

        # Wait for level load, simulate fire (Space) -> expect doubled cooldown log
        page.wait_for_timeout(3000)
        page.keyboard.press("Space")
        # Extract cooldown logs
        cooldown_logs = [log["text"] for log in logs if "Firing with scaled cooldown:" in log["text"]]
        assert cooldown_logs, "No cooldown log found"
        # Improved regex: Specifically match the number after "cooldown: "
        match = re.search(r"Firing with scaled cooldown: ([\d.]+)", cooldown_logs[-1])
        assert match, "Could not parse cooldown value"
        cooldown_value = float(match.group(1))
        print(f"Parsed cooldown value: {cooldown_value}")  # For debug during runs
        assert abs(cooldown_value - 0.3) < 0.01, f"Expected ~0.3, got {cooldown_value}"
    except Exception as e:
        # Save screenshot
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_difficulty_failure_{int(time.time())}.png")
        print(f"Test: Difficulty flow test failed: {str(e)}")
        # Save logs to file (in case teardown fixture is skipped)
        log_file = "artifacts/test_difficulty_failure_console_logs.txt"
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
            with open("v8_coverage_difficulty_flow_test.json", "w") as f:
                json.dump(coverage, f)
