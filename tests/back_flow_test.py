# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/back_flow_test.py
"""
Back Navigation Test Suite (Playwright + UI Automation with DOM Overlays)
========================================================================

Overview
--------
E2E tests for BACK-01 to BACK-04: Validate back button behavior from audio menu,
including return to options, no state mutation without changes, persistence of changes,
and handling mid-interaction.

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

import json
import os
import time
from typing import Any, Callable

import pytest
from playwright.sync_api import Page, expect

# Configuration for stability in different environments
DEFAULT_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "30000"))
TEST_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "10000"))


def test_back_flow(page: Page) -> None:
    """
    Main test suite for back navigation using DOM overlays.

    Implements BACK-01 to BACK-04: Back from audio, verify return, state persistence.

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
        predicate: Callable[[str], bool],
        start_idx: int,
        timeout_ms: int = TEST_TIMEOUT,
    ) -> None:
        """Helper to poll until a matching console log arrives or timeout expires."""
        start_time = time.time()
        while (time.time() - start_time) * 1000 < timeout_ms:
            if any(predicate(log["text"].lower()) for log in logs[start_idx:]):
                return
            page.wait_for_timeout(50)  # Micro-poll for event loop progression
        pytest.fail(
            "Timed out waiting for expected console log matching "
            f"predicate after {timeout_ms}ms"
        )

    try:
        # Start CDP session for V8 JS coverage
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
        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )

        # Verify canvas
        canvas = page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Navigate to options menu
        page.wait_for_selector("#options-button", state="visible", timeout=TEST_TIMEOUT)
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
            "() => window.getComputedStyle("
            "document.getElementById('log-level-select')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # Set log level DEBUG
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
            "() => typeof window.advancedBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.advancedBackPressed([])")

        # Navigate to audio sub-menu
        page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
        assert page.evaluate(
            "document.getElementById('audio-button') !== null"
        ), "Audio button not found/displayed"
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioPressed([])")

        # Wait deterministically for audio menu display
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        wait_for_console_log(
            lambda text: "audio button pressed." in text,
            start_idx=pre_change_log_count,
        )

        # BACK-01: Back returns to parent menu
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioBackPressed([])")

        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('gameplay-button')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'none'",
            timeout=TEST_TIMEOUT,
        )
        wait_for_console_log(
            lambda text: "audio settings: back button pressed" in text,
            start_idx=pre_change_log_count,
        )

        # Re-enter audio for next tests
        page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioPressed([0])")
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # BACK-02: Back without changes
        initial_master: str = page.evaluate(
            "document.getElementById('master-slider').value"
        )
        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioPressed([0])")
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        assert (
            page.evaluate("document.getElementById('master-slider').value")
            == initial_master
        ), "State mutated without changes"

        # Re-enter audio via page reload
        page.reload(wait_until="networkidle")
        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )

        # Navigate to options menu
        page.wait_for_selector("#options-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.optionsPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.optionsPressed([])")

        # Navigate to audio menu
        page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioPressed([0])")
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # BACK-03: Back after slider changes
        page.wait_for_function(
            "() => typeof window.changeMusicVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeMusicVolume([0.4])")
        page.wait_for_function(
            "() => document.getElementById('music-slider').value === '0.4'",
            timeout=TEST_TIMEOUT,
        )
        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioPressed([0])")
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        assert (
            page.evaluate("document.getElementById('music-slider').value") == "0.4"
        ), "Changes did not persist after back"

        # BACK-04: Back from mid-interaction
        pre_change_log_count = len(logs)
        page.evaluate("""
            const slider = document.getElementById('sfx-slider');
            slider.value = 0.6;
            slider.dispatchEvent(new Event('input'));  // Mid-drag
        """)
        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('gameplay-button')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        new_logs = logs[pre_change_log_count:]
        assert not any(
            "error" in log["text"].lower() for log in new_logs
        ), "JS exceptions during back mid-interaction"

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_back_failure_screenshot_{timestamp}.png")
        with open(
            f"artifacts/test_back_failure_console_logs_{timestamp}.txt", "w"
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_back_flow_test.json", "w") as f:
                json.dump(coverage, f)
