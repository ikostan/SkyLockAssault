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

import json
import os
import time
from typing import Any, Callable

import pytest
from playwright.sync_api import Page, expect

# Configuration for stability in different environments
# Default to 5000ms, but allow CI to override via environment variable
DEFAULT_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "30000"))
TEST_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "5000"))


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

    def on_console(msg: Any) -> None:
        """
        Console message handler to capture logs.

        :param msg: The console message.
        :type msg: Any
        :rtype: None
        """
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    def wait_for_console_log(
        predicate: Callable[[str], bool], start_idx: int, timeout_ms: int = TEST_TIMEOUT
    ) -> None:
        """
        Helper to poll until a matching console log arrives or timeout expires.
        """
        start_time = time.time()
        while (time.time() - start_time) * 1000 < timeout_ms:
            if any(predicate(log["text"].lower()) for log in logs[start_idx:]):
                return
            page.wait_for_timeout(50)  # Micro-poll for event loop progression
        pytest.fail(f"Timed out waiting for expected console log matching predicate after {timeout_ms}ms")

    try:
        # Start CDP session for V8 JS coverage (workaround for Python Playwright lacking native coverage API)
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        page.goto(
            "http://localhost:8080/index.html",
            wait_until="networkidle",
            timeout=DEFAULT_TIMEOUT,
        )

        # 1. Wait deterministically for Godot engine initialization
        page.wait_for_function("() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT)

        # Verify canvas
        canvas = page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # NAV-01: Verify main menu overlays exist and are configured
        expect(page.locator("#start-button")).to_be_visible(timeout=TEST_TIMEOUT)
        expect(page.locator("#options-button")).to_be_visible(timeout=TEST_TIMEOUT)
        expect(page.locator("#quit-button")).to_be_visible(timeout=TEST_TIMEOUT)

        opacity: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('options-button')).opacity"
        )
        assert opacity == "0", f"Expected opacity 0, got {opacity}"
        pointer_events: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('options-button')).pointerEvents"
        )
        assert (
            pointer_events == "none"
        ), f"Expected pointer-events none, got {pointer_events}"

        # NAV-02: Navigate to options menu
        page.wait_for_function(
            "() => typeof window.optionsPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.optionsPressed([])")

        # Go to Advanced settings
        page.wait_for_selector(
            "#advanced-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.advancedPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.advancedPressed([])")
        page.wait_for_function(
            "() => typeof window.changeLogLevel !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => window.getComputedStyle(document.getElementById('log-level-select')).display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # NAV-03: Set log level to DEBUG
        pre_change_log_count = len(logs)
        page.evaluate("window.changeLogLevel([0])")
        wait_for_console_log(
            lambda text: "log level changed to: debug" in text,
            start_idx=pre_change_log_count,
        )
        assert page.evaluate(
            "document.getElementById('audio-button') !== null"
        ), "Audio button not found/displayed"

        # Go back to Options menu
        page.wait_for_selector(
            "#advanced-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.advancedBackPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.advancedBackPressed([])")

        # NAV-04: Navigate to audio sub-menu
        page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
        assert page.evaluate(
            "document.getElementById('audio-button') !== null"
        ), "Audio button not found/displayed"

        # Open audio
        pre_audio_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioPressed([0])")

        # Wait deterministically for master slider display and console log
        page.wait_for_function(
            "() => window.getComputedStyle(document.getElementById('master-slider')).display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        wait_for_console_log(
            lambda text: "audio button pressed." in text,
            start_idx=pre_audio_log_count,
        )

        # Assert gameplay/options UI is hidden while audio menu is open
        gameplay_button_display_in_audio: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('gameplay-button')).display"
        )
        assert (
            gameplay_button_display_in_audio == "none"
        ), "Gameplay button should be hidden while audio menu is open"

        # Navigate back from audio menu
        page.wait_for_selector(
            "#audio-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioBackPressed([])")

        # Assert audio overlay is hidden again and options overlay is restored deterministically
        page.wait_for_function(
            "() => window.getComputedStyle(document.getElementById('master-slider')).display === 'none'",
            timeout=TEST_TIMEOUT,
        )
        page.wait_for_function(
            "() => window.getComputedStyle(document.getElementById('gameplay-button')).display === 'block'",
            timeout=TEST_TIMEOUT,
        )

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(
            path=f"artifacts/test_navigation_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_navigation_failure_console_logs_{timestamp}.txt", "w"
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            # Stop V8 coverage and save to file (even on failure)
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_navigation_to_audio_test.json", "w") as f:
                json.dump(coverage, f)
