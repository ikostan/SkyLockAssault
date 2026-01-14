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
import pytest
from playwright.sync_api import Page, Playwright


@pytest.fixture(scope="function")
def page(playwright: Playwright) -> Page:
    """
    Fixture for browser page setup with CDP for coverage.

    :param playwright: The Playwright instance.
    :type playwright: Playwright
    :return: The configured page object.
    :rtype: Page
    """
    browser = playwright.chromium.launch(headless=True, args=[
        "--enable-unsafe-swiftshader",
        "--disable-gpu",
        "--use-gl=swiftshader",
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
        cdp_session.send("Profiler.startPreciseCoverage", {"callCount": False, "detailed": True})
    except:
        pass
    yield page
    # Save coverage on teardown
    if cdp_session:
        try:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")
            coverage_path = os.path.join("artifacts", "v8_coverage_load_main_menu_test.json")
            with open(coverage_path, "w") as f:
                json.dump(coverage, f, indent=4)
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
        except Exception as e:
            print(f"Failed to save coverage: {e}")
    browser.close()


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
            # Stop V8 coverage and save to file (even on failure)
            coverage = cdp_session.send("Profiler.takePreciseCoverage")['result']
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_load_main_menu_test.json", "w") as f:
                json.dump(coverage, f)
