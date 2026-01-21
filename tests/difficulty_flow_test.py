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
- Click #options-button, wait for options loaded (via log), set #log-level-select to DEBUG, set #difficulty-slider to 2.0, click #back-button.
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
import time
import json
from playwright.sync_api import Page


def test_difficulty_flow(page: Page) -> None:
    """
    Main test for difficulty flow using DOM overlays.

    Test that invisible HTML overlays allow passthrough clicks to Godot UI.

    Verifies overlays are present, invisible, and do not block events (via log check after click).
    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg) -> None:
        """
        Console message handler.
        :param msg: The console message.
        :type msg: Any
        :rtype: None
        """
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)
    try:
        # Start CDP session for V8 JS coverage (workaround for Python Playwright lacking native coverage API)
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage", {"callCount": True, "detailed": True})

        page.goto("http://localhost:8080/index.html", wait_until="networkidle", timeout=3000)
        # Wait for Godot engine init (ensures 'godot' object is defined)
        page.wait_for_timeout(3000)
        page.wait_for_function("() => window.godotInitialized", timeout=3000)

        # Verify canvas and title to ensure game is initialized
        canvas = page.locator("canvas")
        page.wait_for_selector("canvas", state="visible", timeout=5000)
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found on page"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Check element present
        page.wait_for_selector('#options-button', state='visible', timeout=1500)
        assert page.evaluate("document.getElementById('options-button') !== null")

        # Check invisible (opacity 0)
        opacity: str = page.evaluate("window.getComputedStyle(document.getElementById('options-button')).opacity")
        assert opacity == '0', f"Expected opacity 0, got {opacity}"

        # Check pointer-events none
        pointer_events: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('options-button')).pointerEvents")
        assert pointer_events == 'none', f"Expected pointer-events none, got {pointer_events}"

        # Wait main menu (function check for ID)
        page.wait_for_function("() => document.getElementById('options-button') !== null",
                               timeout=5000)  # Longer for stalls
        # Open options menu
        page.click("#options-button", force=True, timeout=2500)
        display_style = page.evaluate("window.getComputedStyle(document.getElementById('log-level-select')).display")
        assert display_style == 'block', "Options menu not loaded (display not set to block)"

        # Set log level to DEBUG (index 0) - directly call the exposed callback
        # (bypasses event for reliability in automation)
        pre_change_log_count = len(logs)
        page.evaluate("window.changeLogLevel([0])")
        page.wait_for_timeout(1500)
        new_logs = logs[pre_change_log_count:]
        assert any("Log level changed to: DEBUG" in log["text"] for log in new_logs), "Failed to set log level to DEBUG"
        assert any(
            "log level changed to: debug" in log["text"].lower() for log in new_logs), "Failed to set log level to DEBUG"
        assert any(
            "settings saved" in log["text"].lower() for log in new_logs), "Failed to save the settings"

        # Set difficulty to 2.0 - directly call the exposed callback (bypasses event for reliability in automation)
        pre_change_log_count = len(logs)
        page.evaluate("window.changeDifficulty([2.0])")
        page.wait_for_timeout(1500)
        new_logs = logs[pre_change_log_count:]
        assert any(
            "difficulty changed to: 2.0" in log["text"].lower() for log in new_logs), "Failed to set difficulty to 2.0"
        assert any(
            "settings saved" in log["text"].lower() for log in new_logs), "Failed to save the settings"

        # Back to main menu
        pre_change_log_count = len(logs)
        page.evaluate("window.optionsBackPressed([])")
        page.wait_for_timeout(1500)
        new_logs = logs[pre_change_log_count:]
        assert any("back button pressed." in log["text"].lower() for log in new_logs), "Back button not found"

        # Start game
        page.wait_for_selector('#start-button', state='visible', timeout=1500)
        pre_change_log_count = len(logs)
        pre_poll_log_count = len(logs)
        page.click("#start-button", force=True)
        page.wait_for_timeout(5000)  # Sometimes it takes longer time to pass the loading screen
        new_logs = logs[pre_change_log_count:]
        assert any(
            "start game menu button pressed." in log["text"].lower() for log in new_logs), "Start Game button not found"
        assert any(
            "initializing main scene..." in log["text"].lower() for log in new_logs), "Game scene not found"

        # Poll for loading start log to confirm transition to loading screen
        start_time = time.time()
        while time.time() - start_time < 30:
            if any("loading started successfully." in log["text"].lower() for log in logs[pre_poll_log_count:]):
                break
            time.sleep(0.5)
        else:
            raise TimeoutError("Loading screen did not start")

        # Poll for scene loaded log from loading_screen.gd
        start_time = time.time()
        while time.time() - start_time < 30:
            if any("scene loaded successfully." in log["text"].lower() for log in logs[pre_poll_log_count:]):
                break
            time.sleep(0.5)
        else:
            raise TimeoutError("Main scene not loaded")

        # Refocus canvas to ensure input capture
        page.wait_for_selector("canvas", state="visible", timeout=5000)
        page.click("canvas")

        # Simulate fire (press Space)
        pre_change_log_count = len(logs)
        page.keyboard.press("Space")
        page.wait_for_timeout(3000)
        new_logs = logs[pre_change_log_count:]
        # Verify scaled cooldown in logs (fire_rate 0.15 * 2.0 = 0.3)
        assert any("firing with scaled cooldown: 0.3" in log["text"].lower() for log in
                   new_logs), "Scaled cooldown not found in logs"

    except Exception as e:
        print(f"Test: 'test_difficulty_flow' failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        # Artifact on failure
        timestamp = int(time.time())
        page.screenshot(path=f"artifacts/test_difficulty_failure_screenshot_{timestamp}.png")

        log_file: str = f"artifacts/test_difficulty_failure_console_logs_{timestamp}.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
            print(f"Console logs saved to {log_file}")

        with open(f"artifacts/test_difficulty_failure_html_{timestamp}.html", "w") as f:
            f.write(page.content())

        print(f"Failure logs: artifacts/test_difficulty_failure_console_logs_{timestamp}.txt. Error: {e}")
        raise
    finally:
        if cdp_session:
            # Stop V8 coverage and save to file (even on failure)
            coverage = cdp_session.send("Profiler.takePreciseCoverage")['result']
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_difficulty_flow_test.json", "w") as f:
                json.dump(coverage, f)
