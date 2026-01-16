# tests/back_flow_test.py
"""
Back Navigation Test Suite (Playwright + UI Automation with DOM Overlays)
========================================================================

Overview
--------
E2E tests for BACK-01 to BACK-04: Validate back button behavior from audio menu, including return to options, no state mutation without changes, persistence of changes, and handling mid-interaction.

Navigates to audio menu, performs actions, backs out, verifies states/logs.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k back_flow -q

Artifacts
---------
v8_coverage_back_flow_test.json, artifacts/test_back_failure_*.png/txt
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
    context = browser.new_context(viewport={"width": 1280, "height": 720})
    page = context.new_page()
    yield page
    context.close()
    browser.close()


def test_back_flow(page: Page) -> None:
    """
    Main test suite for back navigation using DOM overlays.

    Implements BACK-01 to BACK-04: Back from audio, verify return, state persistence, no exceptions.

    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

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
        # Start CDP session for V8 JS coverage (workaround for Python Playwright lacking native coverage API)
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage", {"callCount": True, "detailed": True})

        page.goto("http://localhost:8080/index.html", wait_until="networkidle", timeout=5000)
        page.wait_for_function("() => window.godotInitialized", timeout=5000)

        # Verify canvas
        canvas = page.locator("canvas")
        page.wait_for_selector("canvas", state="visible", timeout=5000)
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Navigate to options menu
        page.wait_for_selector('#options-button', state='visible', timeout=1500)
        page.click("#options-button", force=True, timeout=1500)

        # Set log level to DEBUG
        pre_change_log_count = len(logs)
        page.evaluate("window.changeLogLevel([0])")  # Index 0 for DEBUG
        page.wait_for_timeout(3000)
        new_logs = logs[pre_change_log_count:]
        assert any("log level changed to: debug" in log["text"].lower() for log in new_logs), "Failed to set log level to DEBUG"

        # Navigate to audio sub-menu
        page.wait_for_selector('#audio-button', state='visible', timeout=1500)
        assert page.evaluate("document.getElementById('audio-button') !== null"), "Audio button not found/displayed"
        pre_change_log_count = len(logs)
        page.click("#audio-button", force=True)
        page.wait_for_timeout(5000)  # Wait for audio scene load and JS eval
        audio_display: str = page.evaluate("window.getComputedStyle(document.getElementById('master-slider')).display")
        assert audio_display == 'block', "Audio menu not loaded (master-slider not displayed)"
        new_logs = logs[pre_change_log_count:]
        assert any("audio button pressed." in log["text"].lower() for log in new_logs), "Audio navigation log not found"

        # BACK-01: Back returns to parent menu
        # Preconditions: In Audio Settings
        # Steps: Press Back
        # Expected: Options menu visible
        pre_change_log_count = len(logs)
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_timeout(2000)
        options_display: str = page.evaluate("window.getComputedStyle(document.getElementById('difficulty-slider')).display")
        assert options_display == 'block', "Did not return to options menu"
        audio_display_after: str = page.evaluate("window.getComputedStyle(document.getElementById('master-slider')).display")
        assert audio_display_after == 'none', "Audio menu still visible after back"
        new_logs = logs[pre_change_log_count:]
        assert any("back (audio_back_button) button pressed in audio" in log["text"].lower() for log in new_logs), "Back log not found"

        # Re-enter audio for next tests
        page.wait_for_selector('#audio-button', state='visible', timeout=1500)
        page.click("#audio-button", force=True)
        page.wait_for_timeout(5000)

        # BACK-02: Back without changes
        # Preconditions: No modification
        # Steps: Press Back
        # Expected: Back to Options; no state mutation
        initial_master: str = page.evaluate("document.getElementById('master-slider').value")
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_selector('#audio-button', state='visible', timeout=1500)
        page.click("#audio-button", force=True)
        page.wait_for_timeout(5000)
        assert page.evaluate("document.getElementById('master-slider').value") == initial_master, "State mutated without changes"

        # Re-enter audio
        page.reload()
        page.wait_for_function("() => window.godotInitialized", timeout=5000)
        # Navigate to options menu
        page.wait_for_selector('#options-button', state='visible', timeout=3500)
        page.click("#options-button", force=True)
        # Navigate to audio menu
        page.wait_for_selector('#audio-button', state='visible', timeout=3500)
        page.click("#audio-button", force=True)
        page.wait_for_timeout(5000)

        # BACK-03: Back after slider changes
        # Preconditions: Sliders adjusted but not Reset
        # Steps: Press Back
        # Expected: Return; previous changes persist until Reset
        page.evaluate("window.changeMusicVolume([0.4])")
        page.wait_for_timeout(1500)
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_selector('#audio-button', state='visible', timeout=1500)
        page.click("#audio-button", force=True)
        page.wait_for_timeout(5000)
        assert page.evaluate("document.getElementById('music-slider').value") == '0.4', "Changes did not persist after back"

        # BACK-04: Back from mid-interaction
        # Preconditions: Slider being dragged
        # Steps: Trigger Back
        # Expected: Navigation ok, no JS exceptions
        # Simulate mid-drag by setting value without full change event, then back
        pre_change_log_count = len(logs)
        page.evaluate("""
            const slider = document.getElementById('sfx-slider');
            slider.value = 0.6;
            slider.dispatchEvent(new Event('input'));  // Mid-drag
        """)
        page.wait_for_timeout(500)
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_timeout(2000)
        new_logs = logs[pre_change_log_count:]
        assert not any("error" in log["text"].lower() for log in new_logs), "JS exceptions during back mid-interaction"

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_back_failure_screenshot_{timestamp}.png")
        with open(f"artifacts/test_back_failure_console_logs_{timestamp}.txt", "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")['result']
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_back_flow_test.json", "w") as f:
                json.dump(coverage, f)
