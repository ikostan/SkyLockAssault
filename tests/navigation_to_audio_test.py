# tests/navigation_to_audio_test.py
"""
Navigation to Audio Settings Test Suite (Playwright + UI Automation with DOM Overlays)
===================================================================================

Overview
--------
E2E tests for NAV-01 to NAV-04: Validate main menu overlays, navigate to options, set log level to DEBUG, navigate to audio sub-menu, verify audio overlays.

Uses DOM overlays for main/options, coordinates for audio button (no overlay). Verifies display styles and console logs (DEBUG level).

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with custom_shell.html overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k navigation_to_audio -q

Artifacts
---------
artifacts/test_navigation_failure_*.png/txt
"""

import os
import time
import pytest
from playwright.sync_api import Page, Playwright


@pytest.fixture(scope="function")
def page(playwright: Playwright) -> Page:
    """
    Fixture for browser page setup.

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
    context = browser.new_context(viewport={"width": 1280, "height": 720})
    page = context.new_page()
    yield page
    context.close()
    browser.close()


def test_navigation_to_audio(page: Page) -> None:
    """
    Main test suite for navigation to audio settings using DOM overlays and coordinates.

    Implements NAV-01 to NAV-04: Verify main menu overlays, open options, set DEBUG log level, open audio, verify overlays/logs.

    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []

    def on_console(msg) -> None:
        """
        Console message handler to capture logs.

        :param msg: The console message.
        :type msg: Any
        :rtype: None
        """
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)
    try:
        page.goto("http://localhost:8080/index.html", wait_until="networkidle", timeout=5000)
        page.wait_for_function("() => window.godotInitialized", timeout=5000)

        # NAV-01: Verify main menu overlays exist and are configured
        page.wait_for_selector('#start-button', state='visible', timeout=1000)
        assert page.evaluate("document.getElementById('start-button') !== null")
        page.wait_for_selector('#options-button', state='visible', timeout=1000)
        assert page.evaluate("document.getElementById('options-button') !== null")
        page.wait_for_selector('#quit-button', state='visible', timeout=1000)
        assert page.evaluate("document.getElementById('quit-button') !== null")
        opacity: str = page.evaluate("window.getComputedStyle(document.getElementById('options-button')).opacity")
        assert opacity == '0', f"Expected opacity 0, got {opacity}"
        pointer_events: str = page.evaluate("window.getComputedStyle(document.getElementById('options-button')).pointerEvents")
        assert pointer_events == 'none', f"Expected pointer-events none, got {pointer_events}"

        # NAV-02: Navigate to options menu
        page.click("#options-button", force=True)
        page.wait_for_timeout(3000)
        options_display: str = page.evaluate("window.getComputedStyle(document.getElementById('difficulty-slider')).display")
        assert options_display == 'block', "Options menu not loaded (difficulty-slider not displayed)"

        # NAV-03: Set log level to DEBUG
        page.evaluate("window.changeLogLevel([0])")  # Index 0 for DEBUG
        page.wait_for_timeout(3000)
        assert any("log level changed to: debug" in log["text"].lower() for log in logs), "Failed to set log level to DEBUG"

        # NAV-04: Navigate to audio sub-menu
        page.wait_for_selector('#audio-button', state='visible', timeout=1000)
        assert page.evaluate("document.getElementById('audio-button') !== null"), "Audio button not found/displayed"
        canvas = page.locator("canvas")
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found"
        # Open audio
        page.click("#audio-button", force=True)
        page.wait_for_timeout(5000)  # Wait for audio scene load and JS eval
        audio_display: str = page.evaluate("window.getComputedStyle(document.getElementById('master-slider')).display")
        assert audio_display == 'block', "Audio menu not loaded (master-slider not displayed)"
        assert any("audio button pressed." in log["text"].lower() for log in logs), "Audio navigation log not found"

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_navigation_failure_screenshot_{timestamp}.png")
        with open(f"artifacts/test_navigation_failure_console_logs_{timestamp}.txt", "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
