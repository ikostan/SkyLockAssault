# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/audio_flow_test.py
"""
Warning Popups & Constraints Test Suite (Playwright + UI Automation with DOM Overlays)
===================================================================================

Overview
--------
E2E tests for WARN-01 to WARN-03: Validate warning popups when adjusting volumes with mutes enabled.

Navigates to audio menu, adjusts sliders/mutes, verifies states, logs, and popups via console logs.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k audio_flow_test -q

Artifacts
---------
v8_coverage_audio_flow_test.json, artifacts/test_audio_failure_*.png/txt
"""

import json
import os
import time
from typing import Any, Callable

import pytest
from playwright.sync_api import Page, expect

DEFAULT_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "30000"))
TEST_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "5000"))


@pytest.mark.record_har
def test_audio_flow(page: Page) -> None:
    """
    Main test for warning popups and constraints using DOM overlays.
    Implements WARN-01 to WARN-03: Mute/adjust, verify unchanged values, warning logs.
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

        # Verify canvas & title
        canvas = page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Open options
        page.wait_for_function(
            "() => typeof window.optionsPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.optionsPressed([])")

        # Go to Advanced settings
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
        page.wait_for_function(
            "() => typeof window.advancedBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.advancedBackPressed([])")

        # Open audio
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.audioPressed([])")

        page.wait_for_function(
            "() => window.getComputedStyle(document.getElementById('master-slider')).display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        wait_for_console_log(
            lambda text: "audio button pressed" in text,
            start_idx=pre_change_log_count,
        )

        # Get initial values
        initial_sfx: str = page.evaluate("document.getElementById('sfx-slider').value")
        initial_weapon: str = page.evaluate(
            "document.getElementById('weapon-slider').value"
        )
        initial_music: str = page.evaluate(
            "document.getElementById('music-slider').value"
        )
        initial_rotors: str = page.evaluate(
            "document.getElementById('rotors-slider').value"
        )

        # WARN-01: Master muted → attempt sub-volume adjust (SFX)
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.toggleMuteMaster !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.toggleMuteMaster([0])")  # Mute
        wait_for_console_log(
            lambda text: "master is muted" in text,
            start_idx=pre_change_log_count,
        )

        # Change SFX Volume when Master is muted
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeSfxVolume !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.changeSfxVolume([0])")
        wait_for_console_log(
            lambda text: "master muted, cannot adjust sub-volume" in text
            or "warning dialog" in text,
            start_idx=pre_change_log_count,
        )
        assert (
            page.evaluate("document.getElementById('sfx-slider').value") == initial_sfx
        ), "SFX value changed unexpectedly"

        # Master muted → attempt sub-volume adjust (Music)
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeMusicVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeMusicVolume([0.3])")
        wait_for_console_log(
            lambda text: "master muted, cannot adjust sub-volume" in text
            or "warning dialog" in text,
            start_idx=pre_change_log_count,
        )
        assert (
            page.evaluate("document.getElementById('music-slider').value")
            == initial_music
        ), "Music value changed unexpectedly under Master mute"

        # Master muted → attempt sub-volume adjust (Rotors)
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeRotorsVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeRotorsVolume([0.4])")
        wait_for_console_log(
            lambda text: "master muted, cannot adjust sub-volume" in text
            or "warning dialog" in text,
            start_idx=pre_change_log_count,
        )
        assert (
            page.evaluate("document.getElementById('rotors-slider').value")
            == initial_rotors
        ), "Rotors value changed unexpectedly under Master mute"

        # Unmute Master for next tests
        page.wait_for_function(
            "() => typeof window.toggleMuteMaster !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.toggleMuteMaster([1])")

        # WARN-02: SFX muted → attempt weapon adjust
        page.wait_for_function(
            "() => typeof window.toggleMuteSfx !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.toggleMuteSfx([0])")  # Mute

        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeWeaponVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeWeaponVolume([0])")
        wait_for_console_log(
            lambda text: "sfx muted, cannot adjust" in text or "warning dialog" in text,
            start_idx=pre_change_log_count,
        )
        assert (
            page.evaluate("document.getElementById('weapon-slider').value")
            == initial_weapon
        ), "Weapon value changed unexpectedly"

        # SFX muted → attempt rotors adjust
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeRotorsVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeRotorsVolume([0.5])")
        wait_for_console_log(
            lambda text: "sfx muted, cannot adjust" in text or "warning dialog" in text,
            start_idx=pre_change_log_count,
        )
        assert (
            page.evaluate("document.getElementById('rotors-slider').value")
            == initial_rotors
        ), "Rotors value changed unexpectedly under SFX mute"

        # Unmute SFX
        page.wait_for_function(
            "() => typeof window.toggleMuteSfx !== 'undefined'", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.toggleMuteSfx([1])")

        # WARN-03: Master unmuted → adjust sub-volume (Music)
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeMusicVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeMusicVolume([0.6])")

        # Deterministic check for value update
        page.wait_for_function(
            "() => document.getElementById('music-slider').value === '0.6'",
            timeout=TEST_TIMEOUT,
        )

        # Ensure no unexpected warning logs were generated
        new_logs = logs[pre_change_log_count:]
        for log in new_logs:
            text = log["text"].lower()
            if "warning" in text and "encryption aborted" not in text:
                assert (
                    False
                ), f"Unexpected warning after music volume change: {log['text']}"

    except Exception as e:
        print(f"Test: 'test_audio_flow' failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_audio_failure_screenshot_{timestamp}.png")
        log_file: str = f"artifacts/test_audio_failure_console_logs_{timestamp}.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        with open(f"artifacts/test_audio_failure_html_{timestamp}.html", "w") as f:
            f.write(page.content())
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_audio_flow_test.json", "w") as f:
                json.dump(coverage, f)
