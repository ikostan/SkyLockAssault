# tests/load_main_menu_test.py
"""
Main Menu Load Test (Playwright + UI Automation with DOM Overlays)
=================================================================

Overview
--------
E2E test: Verifies Godot HTML5 build loads main menu in browser. Ensures network idle, canvas visibility, godotInitialized flag (from main_menu.gd _ready()), and title contains "SkyLockAssault".

No coords - DOM overlays for verification.

Test Flow
---------
- Navigate to index.html, wait networkidle.
- Wait canvas visible.
- Wait window.godotInitialized (signals _ready() complete).
- Assert title.
- CDP V8 coverage saved.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k load_main_menu_test -q

Artifacts
---------
v8_coverage_load_main_menu_test.json, artifacts/test_load_main_menu_failure_*.png/txt
"""

import os
import time
import json
from playwright.sync_api import Page


def test_load_main_menu(page: Page) -> None:
    """
    Main test for main menu load using DOM overlays.

    Verifies canvas visibility, godotInitialized flag, and title.

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
        :rtype: None
        """
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)
    try:
        # Start CDP session for V8 JS coverage (workaround for Python Playwright lacking native coverage API)
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage", {"callCount": True, "detailed": True})

        page.goto("http://localhost:8080/index.html", wait_until="networkidle", timeout=5000)
        # Wait for Godot engine init (ensures 'godot' object is defined)
        page.wait_for_timeout(3000)
        page.wait_for_function("() => window.godotInitialized", timeout=5000)

        # Verify canvas and title to ensure game is initialized
        canvas = page.locator("canvas")
        page.wait_for_selector("canvas", state="visible", timeout=5000)
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found on page"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Since the DOM overlays are now central to the web flow,
        # consider also asserting that the main-menu overlay elements are present
        # and visible (similar to navigation_to_audio_test):
        page.wait_for_selector('#start-button', state='visible', timeout=1500)
        assert page.evaluate("document.getElementById('start-button') !== null")
        page.wait_for_selector('#options-button', state='visible', timeout=1500)
        assert page.evaluate("document.getElementById('options-button') !== null")
        page.wait_for_selector('#quit-button', state='visible', timeout=1500)
        assert page.evaluate("document.getElementById('quit-button') !== null")

    except Exception as e:
        print(f"Test: 'test_load_main_menu' failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        # Artifact on failure
        timestamp = int(time.time())
        page.screenshot(path=f"artifacts/test_load_main_menu_failure_screenshot_{timestamp}.png")

        log_file: str = f"artifacts/test_load_main_menu_failure_console_logs_{timestamp}.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
            print(f"Console logs saved to {log_file}")

        with open(f"artifacts/test_load_main_menu_failure_html_{timestamp}.html", "w") as f:
            f.write(page.content())

        print(f"Failure logs: artifacts/test_load_main_menu_failure_console_logs_{timestamp}.txt. Error: {e}")
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")['result']
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_load_main_menu_test.json", "w") as f:
                json.dump(coverage, f)
