# tests/load_main_menu_test.py
"""
Main Menu Load Test (Playwright, Python)
=======================================

Overview
--------
This test verifies that the Godot HTML5 build loads the main menu correctly in the
browser. It ensures the page reaches a stable network state, the canvas becomes visible,
_main_menu.gd_ finishes initialization (via a window flag), and the document title
contains "SkyLockAssault".

Key Behaviors Validated
-----------------------
- Page reaches network idle after navigating to http://localhost:8080/index.html.
- Godot canvas element becomes visible within a configurable timeout.
- A global window flag (window.godotInitialized) is set by main_menu.gd in _ready(),
  signaling scene initialization has completed.
- The page title includes the expected game name.

Prerequisites
-------------
- Local server hosting the game at http://localhost:8080/index.html.
- Python with pytest and Playwright installed:
  - pip install pytest playwright
  - playwright install chromium
- The HTML5 export should set window.godotInitialized in main_menu.gd during _ready().

Environment and Timeouts
------------------------
- The timeout used by wait_for_load_state, wait_for_selector, and wait_for_function can be
  overridden via the PW_TIMEOUT environment variable (milliseconds). Default is 10000ms.
- Headless Chromium is launched with flags suitable for software rendering on CI:
  "--enable-unsafe-swiftshader", "--disable-gpu", "--use-gl=swiftshader".

Artifacts
---------
- v8_coverage_load_main_menu_test.json: Precise V8 coverage saved via CDP at teardown.
- artifacts/test_load_main_menu_failure_*.png: Screenshot on failure.
- artifacts/test_load_main_menu_failure_console_logs.txt: Console logs on failure.

Running
-------
- Execute only this test: pytest -k load_main_menu_test -q

Maintenance Notes
-----------------
- If initialization signaling changes (e.g., renaming/removing window.godotInitialized),
  update the wait_for_function and assertion accordingly.
- If the title changes, update the title assertion string.
"""

import time
import os
import pytest
import json  # Added for saving coverage data
from playwright.sync_api import Page


@pytest.fixture(scope="function")
def page(playwright: "playwright") -> Page:
    """
    Provision a Chromium Page with CI-friendly settings for each test.

    Launches headless Chromium with SwiftShader-compatible flags and uses a
    fixed 1280x720 viewport to keep UI coordinates predictable.

    Returns
    -------
    Page
        A Playwright Page instance tied to a new browser context.
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


def test_main_menu_loads(page: Page):
    """
    Verify the main menu loads and initializes correctly in the browser.

    Ensures network-idle state, canvas visibility, and that main_menu.gd has set
    ``window.godotInitialized``. Uses CDP to capture V8 coverage for analysis.
    """
    logs: list = []
    cdp_session = None
    try:
        # Start CDP session for V8 JS coverage (workaround for Python Playwright lacking native coverage API)
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage", {"callCount": True, "detailed": True})

        # Configurable timeout from env (defaults to 10000ms for faster CI)
        timeout = int(os.getenv("PW_TIMEOUT", 10000))
        page.goto("http://localhost:8080/index.html")
        page.wait_for_load_state("networkidle", timeout=timeout)  # Network idle first
        # Replacement for time.sleep: Wait for canvas visibility (basic init indicator)
        # Verifies Godot canvas loads and is visible
        page.wait_for_selector("canvas", state="visible", timeout=timeout)
        # Canvas visibility is a lightweight readiness signal before full init
        # Optional full init wait:
        # Assumes main_menu.gd sets window.godotInitialized in _ready() for web exports.
        # If not set (e.g., non-web or code change),
        # test may timeout—see docs or make optional via env var.
        page.wait_for_function("() => window.godotInitialized", timeout=timeout)  # Confirms _ready() finished
        # Assert existence to catch if signal missing (prevents silent timeout)
        assert page.evaluate("typeof window.godotInitialized !== 'undefined'"), ("godotInitialized not set—check main_menu.gd")
        assert "SkyLockAssault" in page.title()  # Title check
    except Exception as e:
        # Save screenshot
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_load_main_menu_failure_{int(time.time())}.png")
        print(f"Test: Load main menu test failed: {str(e)}")
        # Save logs to file (in case teardown fixture is skipped)
        log_file = "artifacts/test_load_main_menu_failure_console_logs.txt"
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
            with open("v8_coverage_load_main_menu_test.json", "w") as f:
                json.dump(coverage, f)
