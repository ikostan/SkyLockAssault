# tests/difficulty_flow_test.py
"""
Difficulty State Test (Playwright + UI Automation with DOM Overlays)
====================================================================

Overview
--------
Robust E2E test: Sets difficulty=2.0 via UI (click #options-button, set #difficulty-slider), starts game, simulates fire, verifies persistence (cooldown via log).
No coords - DOM overlays for IDs.

Test Flow
---------
- Navigate, wait #options-button.
- Click #options-button, set #log-level-select to DEBUG, set #difficulty-slider to 2.0, click #back-button.
- Click #start-button, simulate fire (Space), parse cooldown log (0.15*2.0=0.3).
- CDP V8 coverage saved.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k difficulty_flow_test -q

Artifacts
---------
v8_coverage_difficulty_flow_test.json, artifacts/test_difficulty_failure_*.png/txt
"""

import os
import re
import time
import json
import pytest
from playwright.sync_api import Page, Playwright
from .ui_elements_coords import UI_ELEMENTS  # Import the coordinates dictionary


@pytest.fixture(scope="function")
def page(playwright: Playwright) -> Page:
    """
    Fixture for browser page setup with CDP for coverage.

    :param playwright: The Playwright instance.
    :type playwright: Playwright
    :return: The configured page object.
    :rtype: Page
    """
    browser = playwright.chromium.launch(headless=False, args=[
        "--enable-unsafe-swiftshader",
        "--disable-gpu",
        "--use-gl=swiftshader"
    ])

    context = browser.new_context(
        viewport={"width": 1280, "height": 720},
        record_har_path="artifacts/har.har"  # Optional network trace
    )
    page = context.new_page()
    # CDP for V8 coverage
    cdp_session = None  # Initialize to None outside try
    try:
        cdp_session = context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage",
                         {"callCount": False,
                          "detailed": True})
    except Exception:
        pass
    yield page
    browser.close()


def test_difficulty_flow(page: Page) -> None:
    """
    Main test for difficulty flow using DOM overlays.

    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []

    def on_console(msg) -> None:
        """
        Console message handler.

        :param msg: The console message.
        :type msg: Any
        :rtype: None
        """
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    cdp_session = None  # Initialize to None outside try
    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage",
                         {"callCount": False,
                          "detailed": True})
    except:
        pass

    try:
        page.goto("http://localhost:8080/index.html", wait_until="networkidle")
        page.wait_for_timeout(10000)  # Bump for GPU stalls/load

        # Wait for Godot engine init (ensures 'godot' object is defined)
        page.wait_for_function("() => window.godotInitialized", timeout=90000)

        # Verify canvas and title to ensure game is initialized
        canvas = page.locator("canvas")
        page.wait_for_selector("canvas", state="visible", timeout=7000)
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found on page"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Wait main menu (function check for ID)
        page.wait_for_function("() => document.getElementById('options-button') !== null", timeout=90000)  # Longer for stalls

        # Open options menu
        page.click("#options-button", force=True)
        page.wait_for_timeout(3000)

        # Wait options (ID check for log select and slider)
        # page.wait_for_function("() => document.getElementById('log-level-select') !== null && "
        #                       "document.getElementById('difficulty-slider') !== null", timeout=60000)

        # Wait for callbacks to be set (exposed by GDScript)
        # page.wait_for_function("() => typeof window.changeLogLevel !== 'undefined'", timeout=30000)

        # Set log level to DEBUG (index 0) - call the callback
        # page.evaluate("window.changeLogLevel([0])")
        # Click log level dropdown
        log_dropdown_x = box['x'] + UI_ELEMENTS["log_level_dropdown"]["x"]
        log_dropdown_y = box['y'] + UI_ELEMENTS["log_level_dropdown"]["y"]
        page.mouse.click(log_dropdown_x, log_dropdown_y)
        page.wait_for_timeout(5000)

        # Select DEBUG
        debug_item_x = box['x'] + UI_ELEMENTS["log_level_debug"]["x"]
        debug_item_y = box['y'] + UI_ELEMENTS["log_level_debug"]["y"]
        page.mouse.click(debug_item_x, debug_item_y)
        page.wait_for_timeout(5000)  # Bump wait for log propagation
        assert any("Log level changed to: DEBUG" in log["text"] for log in logs), "Failed to set log level to DEBUG"

        # Back to main menu
        page.click("#back-button", force=True)
        page.wait_for_timeout(3000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

        # Reopen options menu
        page.click("#options-button", force=True)
        page.wait_for_timeout(5000)  # Wait for options menu to load
        assert any("Options button pressed." in log["text"] for log in logs), "Options menu not found"
        assert any("Options menu loaded." in log["text"] for log in logs), "Options menu is not loaded"

        # Wait for callbacks again (since options reloaded)
        page.wait_for_function("() => typeof window.changeDifficulty !== 'undefined'", timeout=30000)

        # Set difficulty=2.0 - call the callback
        assert any("Difficulty changed to: 2.0" in log["text"] for log in logs), "Expected change to 2.0"

        # Back to main menu
        page.click("#back-button", force=True)
        page.wait_for_timeout(3000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

        # Click START GAME (force)
        page.click("#start-button", force=True)
        page.wait_for_timeout(5000)
        assert any("Start Game menu button pressed." in log["text"] for log in logs), "Start Game button not found"
        assert any("Loading main game scene..." in log["text"] for log in logs), "Main game scene is failed to load"

        # Simulate fire (Space)
        page.keyboard.press("Space")
        page.wait_for_timeout(1000)  # Log emission

        # Parse cooldown log (0.15 * 2.0 = 0.3)
        cooldown_logs: list[str] = [log["text"] for log in logs if "Firing with scaled cooldown:" in log["text"]]
        assert cooldown_logs, "No fire cooldown log"
        match = re.search(r"Firing with scaled cooldown:\s*([\d.]+)", cooldown_logs[-1])
        assert match, "Parse failed on: " + cooldown_logs[-1]
        cooldown_value: float = float(match.group(1))
        print(f"Parsed cooldown: {cooldown_value}")
        assert abs(cooldown_value - 0.3) < 0.01, f"Expected 0.3 (0.15*2.0), got {cooldown_value}"

    except Exception as e:
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_difficulty_failure_{int(time.time())}.png")
        log_file: str = f"artifacts/test_difficulty_failure_console_logs_{int(time.time())}.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        print(f"Failure logs: {log_file}. Error: {e}")

        page.screenshot(path="artifacts/local_failure.png")
        html_content: str = page.content()
        html_file: str = f"artifacts/test_difficulty_failure_html_{int(time.time())}.html"
        with open(html_file, "w", encoding="utf-8") as f:
            f.write(html_content)
        print(f"Failure HTML dump: {html_file}")

        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_difficulty_flow_test.json", "w") as f:
                json.dump(coverage, f, indent=2)

def test_overlay_click_passthrough(page: Page) -> None:
    """
    Test that invisible HTML overlays allow passthrough clicks to Godot UI.

    Verifies overlays are present, invisible, and do not block events (via log check after click).

    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []

    def on_console(msg) -> None:
        """
        Console message handler for logs.

        :param msg: The console message.
        :type msg: Any
        :rtype: None
        """
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    page.goto("http://localhost:8080/index.html", wait_until="networkidle")
    page.wait_for_timeout(10000)  # Bump for load

    # Verify canvas and title to ensure game is initialized
    canvas = page.locator("canvas")
    page.wait_for_selector("canvas", state="visible", timeout=7000)
    box: dict[str, float] | None = canvas.bounding_box()
    assert box is not None, "Canvas not found on page"

    # Wait for Godot engine init (ensures 'godot' object is defined)
    page.wait_for_function("() => window.godotInitialized", timeout=90000)

    # Check element present
    assert page.evaluate("document.getElementById('options-button') !== null")

    # Check invisible (opacity 0)
    opacity: str = page.evaluate("window.getComputedStyle(document.getElementById('options-button')).opacity")
    assert opacity == '0', f"Expected opacity 0, got {opacity}"

    # Open options menu
    page.click("#options-button", force=True)
    page.wait_for_timeout(3000)

    # Set difficulty=2.0 - call the callback
    # Click log level dropdown
    log_dropdown_x = box['x'] + UI_ELEMENTS["log_level_dropdown"]["x"]
    log_dropdown_y = box['y'] + UI_ELEMENTS["log_level_dropdown"]["y"]
    page.mouse.click(log_dropdown_x, log_dropdown_y)
    page.wait_for_timeout(5000)

    # Select DEBUG
    debug_item_x = box['x'] + UI_ELEMENTS["log_level_debug"]["x"]
    debug_item_y = box['y'] + UI_ELEMENTS["log_level_debug"]["y"]
    page.mouse.click(debug_item_x, debug_item_y)
    page.wait_for_timeout(5000)
    assert any("Log level changed to: DEBUG" in log["text"] for log in logs), "Failed to set log level to DEBUG"

    # Wait options (ID check for log select and slider)
    # page.wait_for_function("() => document.getElementById('log-level-select') !== null && "
    #                       "document.getElementById('difficulty-slider') !== null", timeout=60000)

    # Wait for callbacks to be set (exposed by GDScript)
    # page.wait_for_function("() => typeof window.changeLogLevel !== 'undefined'", timeout=30000)

    # Back to main menu
    page.click("#back-button", force=True)
    page.wait_for_timeout(3000)
    assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

    # Check pointer-events none
    pointer_events: str = page.evaluate("window.getComputedStyle(document.getElementById("
                                        "'options-button')).pointerEvents")
    assert pointer_events == 'none', f"Expected pointer-events none, got {pointer_events}"

    # Simulate click on overlay—should trigger Godot log (force to bypass)
    page.click("#options-button", force=True)
    page.wait_for_timeout(2000)
    assert any("Options button pressed." in log["text"] for log in logs), "Options menu not found"
    assert any("Options menu loaded." in log["text"] for log in logs), "Options menu is not loaded"
