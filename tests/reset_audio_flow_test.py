# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/reset_audio_flow_test.py
"""
Reset Functionality Test Suite (Playwright + UI Automation with DOM Overlays)
============================================================================

Overview
--------
E2E tests for RESET-01 to RESET-05 and STATE-01 to STATE-02: Validate reset button
behavior in audio menu, including defaults restoration, no-op on defaults, partial
changes, persistence after navigation/reload, rapid clicks, and isolation.

Navigates to audio menu, adjusts sliders/mutes, resets, verifies states/logs.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k reset_flow -q

Artifacts
---------
v8_coverage_reset_flow_test.json, artifacts/test_reset_failure_*.png/txt
"""

import json
import os
import time
from typing import Any, Callable

import pytest
from playwright.sync_api import Page, expect

# Configuration for stability in different environments
DEFAULT_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "30000"))
TEST_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "5000"))


def wait_for_console_log(
    logs: list[dict[str, str]],
    predicate: Callable[[str], bool],
    start_idx: int,
    page: Page,
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


def _has_log(logs: list[dict[str, str]], keyword: str) -> bool:
    """Check if any log entry contains the specified keyword."""
    return any(keyword in log["text"].lower() for log in logs)


def _get_unignored_errors(
    logs_subset: list[dict[str, str]], ignored_phrases: list[str]
) -> list[str]:
    """Extract error messages from logs excluding ignored phrases."""
    actual_errors = []
    for log in logs_subset:
        text = log["text"].lower()
        if "error" in text and not any(ignored in text for ignored in ignored_phrases):
            actual_errors.append(log["text"])
    return actual_errors


def test_reset_flow(page: Page) -> None:
    """
    Main test suite for reset functionality using DOM overlays.

    Implements RESET-01 to RESET-05 and STATE-01 to STATE-02.

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

    ignored_phrases = [
        "encryption aborted",
        "salt is empty",
        "key generation failed",
    ]

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

        # Open options
        page.wait_for_selector("#options-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.optionsPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.optionsPressed([])")

        # Go to Advanced settings
        page.wait_for_selector(
            "#advanced-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.advancedPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.advancedPressed([])")
        page.wait_for_function(
            "() => typeof window.changeLogLevel !== 'undefined'",
            timeout=TEST_TIMEOUT,
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
            logs,
            lambda text: "log level changed to: debug" in text,
            pre_change_log_count,
            page,
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
            "() => typeof window.audioPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioPressed([])")

        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        wait_for_console_log(
            logs,
            lambda text: "audio button pressed." in text,
            pre_change_log_count,
            page,
        )

        # RESET-01: Reset all buses to defaults
        page.wait_for_function(
            "() => typeof window.changeMasterVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeMasterVolume([0.5])")
        page.wait_for_function(
            "() => typeof window.changeMusicVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeMusicVolume([0.3])")
        page.wait_for_function(
            "() => typeof window.changeSfxVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeSfxVolume([0.7])")
        page.wait_for_function(
            "() => typeof window.toggleMuteMusic !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.toggleMuteMusic([0])")
        page.wait_for_function(
            "() => typeof window.toggleMuteMaster !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.toggleMuteMaster([0])")

        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioResetPressed([])")

        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            page,
        )

        assert (
            float(page.evaluate("document.getElementById('master-slider').value"))
            == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('music-slider').value")) == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('sfx-slider').value")) == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('weapon-slider').value"))
            == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('rotors-slider').value"))
            == 1.0
        )
        assert page.evaluate("document.getElementById('mute-master').checked")
        assert page.evaluate("document.getElementById('mute-music').checked")
        assert page.evaluate("document.getElementById('mute-sfx').checked")
        assert page.evaluate("document.getElementById('mute-weapon').checked")
        assert page.evaluate("document.getElementById('mute-rotors').checked")

        new_logs = logs[pre_change_log_count:]
        assert _has_log(new_logs, "audio reset pressed"), "Reset log not found"
        assert _has_log(
            new_logs, "audio volumes reset to defaults"
        ), "Reset log not found"

        # RESET-02: Reset does not duplicate sliders already default
        pre_reset_logs = len(logs)
        page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioResetPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_reset_logs,
            page,
        )

        assert (
            float(page.evaluate("document.getElementById('master-slider').value"))
            == 1.0
        ), "Value changed unexpectedly"

        actual_errors = _get_unignored_errors(logs[pre_reset_logs:], ignored_phrases)
        assert (
            not actual_errors
        ), f"Unexpected error after reset on defaults: {actual_errors}"

        # RESET-03: Reset after incomplete changes
        page.wait_for_function(
            "() => typeof window.changeMasterVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeMasterVolume([0.4])")
        page.wait_for_function(
            "() => typeof window.changeRotorsVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeRotorsVolume([0.6])")

        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioResetPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            page,
        )

        assert (
            float(page.evaluate("document.getElementById('master-slider').value"))
            == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('rotors-slider').value"))
            == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('music-slider').value")) == 1.0
        )

        new_logs = logs[pre_change_log_count:]
        assert _has_log(new_logs, "audio reset pressed"), "Reset log not found"
        assert _has_log(
            new_logs, "audio volumes reset to defaults"
        ), "Reset log not found"

        # RESET-04: Reset persists after Back navigation
        pre_sfx_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeSfxVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeSfxVolume([0.2])")
        wait_for_console_log(
            logs,
            lambda text: "applied loaded sfx volume to audioserver: 0.2" in text,
            pre_sfx_count,
            page,
        )
        page.wait_for_function(
            "() => parseFloat(document.getElementById('sfx-slider').value) === 0.2",
            timeout=TEST_TIMEOUT,
        )

        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioResetPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            page,
        )
        page.wait_for_function(
            "() => parseFloat("
            "document.getElementById('sfx-slider').value"
            ") === 1.0",
            timeout=TEST_TIMEOUT,
        )

        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioPressed([0])")

        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        assert (
            float(page.evaluate("document.getElementById('sfx-slider').value")) == 1.0
        ), "Reset not persisted after back"

        # RESET-05: Rapid Reset clicks
        page.wait_for_function(
            "() => typeof window.changeMasterVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeMasterVolume([0.5])")

        pre_change_log_count = len(logs)
        for _ in range(3):
            page.wait_for_function(
                "() => typeof window.audioResetPressed !== 'undefined'",
                timeout=TEST_TIMEOUT,
            )
            page.evaluate("window.audioResetPressed([])")

        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            page,
        )

        assert (
            float(page.evaluate("document.getElementById('master-slider').value"))
            == 1.0
        )

        actual_errors = _get_unignored_errors(
            logs[pre_change_log_count:], ignored_phrases
        )
        assert not actual_errors, f"JS errors during rapid reset: {actual_errors}"

        # STATE-01: Reset button state persists in config
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioResetPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            page,
        )
        page.wait_for_function(
            "() => parseFloat("
            "document.getElementById('sfx-slider').value"
            ") === 1.0",
            timeout=TEST_TIMEOUT,
        )

        # Reload and validate persisted defaults for all audio controls
        page.reload(wait_until="networkidle")
        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )
        page.wait_for_selector("#options-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.optionsPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.optionsPressed([])")
        page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioPressed([])")

        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # Sliders should all be at default volume
        assert (
            float(page.evaluate("document.getElementById('master-slider').value"))
            == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('music-slider').value")) == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('sfx-slider').value")) == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('weapon-slider').value"))
            == 1.0
        )
        assert (
            float(page.evaluate("document.getElementById('rotors-slider').value"))
            == 1.0
        )

        # Mutes should retain their default checked state after reload
        assert page.evaluate("document.getElementById('mute-master').checked")
        assert page.evaluate("document.getElementById('mute-music').checked")
        assert page.evaluate("document.getElementById('mute-sfx').checked")
        assert page.evaluate("document.getElementById('mute-weapon').checked")
        assert page.evaluate("document.getElementById('mute-rotors').checked")

        # STATE-02: Reset doesn't affect other menus
        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'none'",
            timeout=TEST_TIMEOUT,
        )

        initial_difficulty_value = float(
            page.evaluate("document.getElementById('difficulty-slider').value")
        )
        pre_change_log_count = len(logs)
        assert initial_difficulty_value == 1.0, "Unexpected initial difficulty default"

        page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioPressed([])")
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        page.wait_for_function(
            "() => typeof window.audioResetPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioResetPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "audio volumes reset to defaults" in text,
            pre_change_log_count,
            page,
        )

        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'none'",
            timeout=TEST_TIMEOUT,
        )

        assert (
            float(page.evaluate("document.getElementById('difficulty-slider').value"))
            == initial_difficulty_value
        ), "Difficulty reset unexpectedly"

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_reset_failure_screenshot_{timestamp}.png")
        with open(
            f"artifacts/test_reset_failure_console_logs_{timestamp}.txt", "w"
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_reset_flow_test.json", "w") as f:
                json.dump(coverage, f)
