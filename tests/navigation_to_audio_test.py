# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
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
v8_coverage_navigation_to_audio_test.json, artifacts/test_navigation_failure_*.png/txt
"""

import os
import time
import json
from playwright.sync_api import Page


def test_navigation_to_audio(page: Page) -> None:
    """
    Main test suite for navigation to audio settings using DOM overlays and coordinates.

    Implements NAV-01 to NAV-04: Verify main menu overlays, open options, set DEBUG log level, open audio, verify overlays/logs.

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
        page.wait_for_timeout(3000)
        page.wait_for_function("() => window.godotInitialized", timeout=5000)

        # Verify canvas
        canvas = page.locator("canvas")
        page.wait_for_selector("canvas", state="visible", timeout=5000)
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # NAV-01: Verify main menu overlays exist and are configured
        page.wait_for_selector('#start-button', state='visible', timeout=2500)
        assert page.evaluate("document.getElementById('start-button') !== null")
        page.wait_for_selector('#options-button', state='visible', timeout=2500)
        assert page.evaluate("document.getElementById('options-button') !== null")
        page.wait_for_selector('#quit-button', state='visible', timeout=2500)
        assert page.evaluate("document.getElementById('quit-button') !== null")
        opacity: str = page.evaluate("window.getComputedStyle(document.getElementById('options-button')).opacity")
        assert opacity == '0', f"Expected opacity 0, got {opacity}"
        pointer_events: str = page.evaluate("window.getComputedStyle(document.getElementById('options-button')).pointerEvents")
        assert pointer_events == 'none', f"Expected pointer-events none, got {pointer_events}"

        # NAV-02: Navigate to options menu
        # Open options
        page.wait_for_selector('#options-button', state='visible', timeout=2500)
        page.click("#options-button", force=True)

        # Go to Advanced settings
        page.wait_for_selector('#advanced-button', state='visible', timeout=2500)
        page.click("#advanced-button", force=True)
        page.wait_for_function('window.changeLogLevel !== undefined', timeout=2500)
        advanced_display: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('log-level-select')).display")
        assert advanced_display == 'block', "Advanced menu not loaded (selected log level not displayed)"

        # NAV-03: Set log level to DEBUG
        # Set log level DEBUG
        pre_change_log_count = len(logs)
        page.evaluate("window.changeLogLevel([0])")
        page.wait_for_timeout(1000)
        new_logs = logs[pre_change_log_count:]
        assert any("log level changed to: debug" in log["text"].lower() for log in new_logs)
        assert page.evaluate("document.getElementById('audio-button') !== null"), "Audio button not found/displayed"

        # Go back to Options menu
        page.wait_for_selector('#advanced-back-button', state='visible', timeout=2500)
        # page.click("#advanced-back-button", force=True)
        page.evaluate("window.advancedBackPressed([0])")

        # NAV-04: Navigate to audio sub-menu
        page.wait_for_selector('#audio-button', state='visible', timeout=2500)
        assert page.evaluate("document.getElementById('audio-button') !== null"), "Audio button not found/displayed"

        # Open audio
        # page.click("#audio-button", force=True, timeout=1500)
        page.wait_for_function('window.audioPressed !== undefined', timeout=2500)
        page.evaluate("window.audioPressed([0])")
        page.wait_for_timeout(5000)  # Wait for audio scene load and JS eval

        audio_display: str = page.evaluate("window.getComputedStyle(document.getElementById('master-slider')).display")
        assert audio_display == 'block', "Audio menu not loaded (master-slider not displayed)"
        assert any("audio button pressed." in log["text"].lower() for log in logs), "Audio navigation log not found"

        # Navigate back from audio menu
        page.wait_for_selector('#audio-back-button', state='visible', timeout=2500)
        # page.click("#audio-back-button", force=True, timeout=1500)
        page.wait_for_function('window.audioBackPressed !== undefined', timeout=2500)
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_timeout(2000)  # Wait for audio overlay to hide and main/options overlays to re-show

        # Assert audio overlay is hidden again
        audio_display_after_back: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('master-slider')).display"
        )
        assert audio_display_after_back == 'none', "Audio menu still visible after navigating back from audio menu"

        # Assert main/options overlays are restored
        options_overlay_display: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('difficulty-slider')).display"
        )
        assert options_overlay_display == 'block', "Options overlay not restored after exiting audio menu"

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_navigation_failure_screenshot_{timestamp}.png")
        with open(f"artifacts/test_navigation_failure_console_logs_{timestamp}.txt", "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            # Stop V8 coverage and save to file (even on failure)
            coverage = cdp_session.send("Profiler.takePreciseCoverage")['result']
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_navigation_to_audio_test.json", "w") as f:
                json.dump(coverage, f)
