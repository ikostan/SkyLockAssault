# tests/fuel_depletion_test.py
"""
Fuel Depletion Test (Playwright, Python)
=======================================

Overview
--------
This module provides an end-to-end browser test validating that fuel depletes at the
expected rate after setting game difficulty to 2.0 via the options menu. The test uses
Playwright (sync API) to control a headless Chromium instance, interacts with the Godot
HTML5 build using coordinate-based clicks, and asserts on console log output emitted by
the game.

Test Flow
---------
- Launch headless Chromium with flags favoring software rendering for CI stability.
- Create a CDP session to collect precise V8 coverage (workaround for Python Playwright's
  lack of built-in coverage API) and attach a console listener to capture logs.
- Navigate to http://localhost:8080/index.html and obtain the canvas bounding box.
- Open Options, set Log Level to DEBUG, and return to the main menu.
- Reopen Options and set Difficulty to 2.0 by clicking offsets relative to the canvas
  (coordinates are defined in tests/ui_elements_coords.py).
- Start the level, idle to allow fuel ticks to occur, then assert that the final fuel
  value has dropped below the specified threshold for difficulty 2.0.

Prerequisites
-------------
- Local server hosting the game at http://localhost:8080/index.html.
- Python with pytest and Playwright installed:
  - pip install pytest playwright
  - playwright install chromium
- Game console logs must include strings used in assertions, for example:
  - "Options button pressed."
  - "Options menu loaded."
  - "Back button pressed."
  - "Start Game menu button pressed."
  - "Log level changed to: DEBUG"
  - "Difficulty changed to: 2.0"
  - "Fuel left: <value>"

How It Works
------------
- Coordinates for UI interactions are computed as: canvas bounding box origin + element
  offsets from tests/ui_elements_coords.py. This keeps the test independent from page
  chrome but sensitive to in-canvas layout changes.
- The test idles after starting the level so that the game's fuel timer ticks; it then
  parses the most recent "Fuel left: X" log and asserts a maximum allowed remaining fuel
  to validate depletion under difficulty 2.0.

Artifacts
---------
- v8_coverage_fuel_depletion_test.json: Precise V8 coverage snapshot saved at teardown.
- artifacts/test_fuel_depletion_failure_*.png: Screenshot captured on failure.
- artifacts/test_fuel_depletion_failure_console_logs.txt: Console logs written on failure.

Running
-------
- Execute only this test: pytest -k fuel_depletion_test -q
- If stability issues occur due to rendering or timing, consider increasing waits or
  running in headed mode by setting headless=False in the fixture.

Maintenance Notes
-----------------
- Update tests/ui_elements_coords.py when UI layout changes within the canvas.
- Keep asserted log message strings synchronized with the Godot scripts.
- Adjust the final fuel threshold if game balance changes affect depletion rates.
"""
import os
import time
import pytest
import json  # Added for saving coverage data
from playwright.sync_api import Page
from ui_elements_coords import UI_ELEMENTS  # Import the coordinates dictionary


@pytest.fixture(scope="function")
def page(playwright: "playwright") -> Page:
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


def test_fuel_depletion(page: Page):
    logs: list = []
    cdp_session = None
    try:
        # Start CDP session for V8 JS coverage (workaround for Python Playwright lacking native coverage API)
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage", {"callCount": True, "detailed": True})

        # Set up console log capture
        page.on("console", lambda msg: logs.append({"type": msg.type, "text": msg.text}))
        page.goto("http://localhost:8080/index.html")
        page.wait_for_timeout(2000)

        # Verify canvas and title
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
        page.wait_for_timeout(7000)
        # assert any("Options menu loaded." in log["text"] for log in logs), "Options menu failed to load"

        # Click log level dropdown
        log_dropdown_x = box['x'] + UI_ELEMENTS["log_level_dropdown"]["x"]
        log_dropdown_y = box['y'] + UI_ELEMENTS["log_level_dropdown"]["y"]
        page.mouse.click(log_dropdown_x, log_dropdown_y)
        page.wait_for_timeout(2000)

        # Select DEBUG
        debug_item_x = box['x'] + UI_ELEMENTS["log_level_debug"]["x"]
        debug_item_y = box['y'] + UI_ELEMENTS["log_level_debug"]["y"]
        page.mouse.click(debug_item_x, debug_item_y)
        page.wait_for_timeout(2000)
        assert any("Log level changed to: DEBUG" in log["text"] for log in logs), "Failed to set log level to DEBUG"

        # Back to main menu
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        page.mouse.click(back_x, back_y)
        page.wait_for_timeout(2000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button failed"

        # Open options menu again
        page.mouse.click(options_x, options_y)  # Click Options button
        page.wait_for_timeout(5000)  # Wait for options menu to load
        assert any("Options button pressed." in log["text"] for log in logs), "Options menu not found"
        assert any("Options menu loaded." in log["text"] for log in logs), "Options menu is not loaded"

        # Set difficulty to 2.0 (direct click to slider_2.0 position)
        slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_2.0"]["x"]
        slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_2.0"]["y"]
        page.mouse.move(slider_x, slider_y)  # Move to 2.0 position
        page.mouse.click(slider_x, slider_y)  # Click to set 2.0
        assert any("Difficulty changed to: 2.0" in log["text"] for log in logs), "Expected change to 2.0"

        # Back to main menu
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        page.mouse.click(back_x, back_y)  # Click Back button
        page.wait_for_timeout(2000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

        # Start level
        start_x = box['x'] + UI_ELEMENTS["start_game_button"]["x"]
        start_y = box['y'] + UI_ELEMENTS["start_game_button"]["y"]
        page.mouse.click(start_x, start_y)  # Click Start button
        page.wait_for_timeout(5000)  # Increased for level load
        assert any("Start Game menu button pressed." in log["text"] for log in logs), "Start Game button not found"

        # Simulate idle time for depletion (fuel_timer is 1s default; wait 5s for ~5 ticks)
        page.wait_for_timeout(10000)

        # Assert fuel dropped faster (e.g., parse logs for "Fuel left: X" < expected base)
        fuel_logs = [log["text"] for log in logs if "Fuel left:" in log["text"]]
        assert len(fuel_logs) > 0, "No fuel logs found"
        last_fuel = float(fuel_logs[-1].split("Fuel left: ")[1])  # Parse last value
        assert last_fuel < 95.0, f"Expected faster drop (<95.0), got {last_fuel}"  # Adjusted for 5-unit drop at 2.0x
    except Exception as e:
        # Save screenshot
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_fuel_depletion_failure_{int(time.time())}.png")
        print(f"Test: Fuel depletion test failed: {str(e)}")
        # Save logs to file (in case teardown fixture is skipped)
        log_file = "artifacts/test_fuel_depletion_failure_console_logs.txt"
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
            with open("v8_coverage_fuel_depletion_test.json", "w") as f:
                json.dump(coverage, f)
