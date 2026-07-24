# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
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

import json
import os
import time
from typing import Any, Callable, Dict, List, Optional

import pytest
from playwright.sync_api import Page, expect

# Configuration for stability in different environments
DEFAULT_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "30000"))
TEST_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "5000"))


def test_difficulty_flow(page: Page) -> None:
    """
    Main test for difficulty flow using DOM overlays.

    Test that invisible HTML overlays allow passthrough clicks to Godot UI.

    Verifies overlays are present, invisible, and do not block events (via log check after click).
    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: List[Dict[str, str]] = []
    cdp_session: Optional[Any] = None

    def on_console(msg: Any) -> None:
        """
        Console message handler.
        :param msg: The console message.
        :type msg: Any
        :rtype: None
        """
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    def wait_for_console_log(
        predicate: Callable[[str], bool],
        start_idx: int,
        timeout_ms: int = DEFAULT_TIMEOUT,
    ) -> None:
        """
        Helper to poll until a matching console log arrives or timeout expires.
        """
        start_time = time.time()
        while (time.time() - start_time) * 1000 < timeout_ms:
            if any(predicate(log["text"].lower()) for log in logs[start_idx:]):
                return
            page.wait_for_timeout(50)  # Micro-poll for event loop progression
        pytest.fail(
            f"Timed out waiting for expected console log matching predicate after {timeout_ms}ms"
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

        # Verify canvas and title to ensure game is initialized
        canvas = page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)
        box: Optional[Dict[str, float]] = canvas.bounding_box()
        assert box is not None, "Canvas not found on page"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Check element present
        page.wait_for_selector("#options-button", state="visible", timeout=TEST_TIMEOUT)
        assert page.evaluate("document.getElementById('options-button') !== null")

        # Check invisible (opacity 0)
        opacity: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('options-button')).opacity"
        )
        assert opacity == "0", f"Expected opacity 0, got {opacity}"

        # Check pointer-events none
        pointer_events: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('options-button')).pointerEvents"
        )
        assert (
            pointer_events == "none"
        ), f"Expected pointer-events none, got {pointer_events}"

        # Wait main menu
        page.wait_for_function(
            "() => document.getElementById('options-button') !== null",
            timeout=TEST_TIMEOUT,
        )

        # Open options
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
            "() => window.getComputedStyle(document.getElementById('log-level-select')).display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # Set log level DEBUG
        pre_change_log_count: int = len(logs)
        page.evaluate("window.changeLogLevel([0])")
        wait_for_console_log(
            lambda text: "log level changed to: debug" in text,
            start_idx=pre_change_log_count,
        )
        new_logs: List[Dict[str, str]] = logs[pre_change_log_count:]
        assert any(
            "log level changed to: debug" in log["text"].lower() for log in new_logs
        )
        assert page.evaluate(
            "document.getElementById('audio-button') !== null"
        ), "Audio button not found/displayed"

        # Allow either standard encrypted saves (native) OR plaintext fallbacks (WebGL)
        assert any(
            ("encrypted" in log["text"].lower() and "settings" in log["text"].lower())
            or "falling back to plaintext" in log["text"].lower()
            for log in new_logs
        ), "Failed to save the settings (neither encrypted save nor plaintext fallback detected)"

        # Go back to Options menu
        page.wait_for_selector(
            "#advanced-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.advancedBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.advancedBackPressed([])")

        # Go to Gameplay Settings
        page.wait_for_selector(
            "#gameplay-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.gameplayPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.gameplayPressed([])")

        # Assert gameplay settings overlay is shown and options overlay is hidden
        page.wait_for_selector(
            "#difficulty-slider", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_selector(
            "#options-back-button", state="hidden", timeout=TEST_TIMEOUT
        )

        # Set difficulty to 2.0
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeDifficulty !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.changeDifficulty([2.0])")
        wait_for_console_log(
            lambda text: "js difficulty callback called with valid value: 2.0" in text,
            start_idx=pre_change_log_count,
        )
        new_logs = logs[pre_change_log_count:]

        assert any(
            "js difficulty callback called with valid value: 2.0" in log["text"].lower()
            for log in new_logs
        ), "Failed to extract/validate difficulty 2.0 from JS payload"

        assert any(
            "encrypted" in log["text"].lower() and "settings" in log["text"].lower()
            for log in new_logs
        ), "Failed to save the settings"

        # Reset gameplay settings back to defaults
        pre_reset_log_count: int = len(logs)
        page.wait_for_function(
            "() => typeof window.gameplayResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.gameplayResetPressed([])")
        wait_for_console_log(
            lambda text: "setting 'difficulty' updated to: 1" in text,
            start_idx=pre_reset_log_count,
        )
        reset_logs: List[Dict[str, str]] = logs[pre_reset_log_count:]

        assert any(
            "setting 'difficulty' updated to: 1" in log["text"].lower()
            for log in reset_logs
        ), "Resource did not reset difficulty to 1.0 after reset button press"

        # Set difficulty to 2.0 again
        pre_change_log_count = len(logs)
        page.evaluate("window.changeDifficulty([2.0])")
        wait_for_console_log(
            lambda text: "js difficulty callback called with valid value: 2.0" in text,
            start_idx=pre_change_log_count,
        )

        # Back to Main menu
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.gameplayBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.gameplayBackPressed([])")
        wait_for_console_log(
            lambda text: "back button pressed." in text,
            start_idx=pre_change_log_count,
        )
        new_logs = logs[pre_change_log_count:]
        assert any(
            "back button pressed." in log["text"].lower() for log in new_logs
        ), "Back button not found"

        # Options overlay visible
        page.wait_for_selector(
            "#options-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        assert page.evaluate("document.getElementById('options-back-button') !== null")
        # Gameplay UI hidden
        page.wait_for_selector(
            "#difficulty-slider", state="hidden", timeout=TEST_TIMEOUT
        )
        assert page.evaluate(
            "document.getElementById('difficulty-slider') === null || document.getElementById("
            "'difficulty-slider').offsetParent === null"
        )

        # Check element present
        page.wait_for_selector(
            "#options-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        assert page.evaluate("document.getElementById('options-back-button') !== null")
        page.evaluate("window.optionsBackPressed([])")

        # After optionsBackPressed([]), back on the main menu
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        assert page.evaluate("document.getElementById('start-button') !== null")
        page.wait_for_selector(
            "#options-back-button", state="hidden", timeout=TEST_TIMEOUT
        )
        assert page.evaluate(
            "document.getElementById('options-back-button') === null || document.getElementById("
            "'options-back-button').offsetParent === null"
        )

        # Start game
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        pre_start_log_count = len(logs)
        page.click("#start-button", force=True)

        # Wait deterministically for start button click and loading start
        wait_for_console_log(
            lambda text: "start game menu button pressed." in text,
            start_idx=pre_start_log_count,
            timeout_ms=TEST_TIMEOUT,
        )

        wait_for_console_log(
            lambda text: "loading started successfully." in text,
            start_idx=pre_start_log_count,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        # Wait deterministically for main scene initialization
        wait_for_console_log(
            lambda text: "initializing main scene..." in text,
            start_idx=pre_start_log_count,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        # Wait deterministically for scene load completion
        wait_for_console_log(
            lambda text: "scene loaded successfully." in text,
            start_idx=pre_start_log_count,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        start_logs = logs[pre_start_log_count:]
        assert any(
            "start game menu button pressed." in log["text"].lower()
            for log in start_logs
        ), "Start Game button not found"
        assert any(
            "initializing main scene..." in log["text"].lower() for log in start_logs
        ), "Game scene not found"

        # Refocus canvas to ensure input capture
        expect(canvas).to_be_visible(timeout=TEST_TIMEOUT)
        page.click("canvas")

        # Simulate fire (press Space)
        pre_fire_log_count = len(logs)
        page.keyboard.press("Space")
        wait_for_console_log(
            lambda text: "firing with scaled cooldown: 0.3" in text,
            start_idx=pre_fire_log_count,
            timeout_ms=TEST_TIMEOUT,
        )
        fire_logs = logs[pre_fire_log_count:]
        assert any(
            "firing with scaled cooldown: 0.3" in log["text"].lower()
            for log in fire_logs
        ), "Scaled cooldown not found in logs"

    except Exception as e:
        print(f"Test: 'test_difficulty_flow' failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(
            path=f"artifacts/test_difficulty_failure_screenshot_{timestamp}.png"
        )

        log_file: str = (
            f"artifacts/test_difficulty_failure_console_logs_{timestamp}.txt"
        )
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
            print(f"Console logs saved to {log_file}")

        with open(f"artifacts/test_difficulty_failure_html_{timestamp}.html", "w") as f:
            f.write(page.content())

        print(
            f"Failure logs: artifacts/test_difficulty_failure_console_logs_{timestamp}.txt. Error: {e}"
        )
        raise
    finally:
        if cdp_session:
            coverage: Dict[str, Any] = cdp_session.send("Profiler.takePreciseCoverage")[
                "result"
            ]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_difficulty_flow_test.json", "w") as f:
                json.dump(coverage, f)
