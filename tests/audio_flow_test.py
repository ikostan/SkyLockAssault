# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/audio_flow_test.py
"""
Warning Popups & Constraints Test Suite (Playwright + UI Automation Overlay)
=============================================================================

Overview
--------
E2E tests for WARN-01 to WARN-03: Validate warning popups when adjusting
volumes with mutes enabled.

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
from typing import Any

import pytest
from playwright.sync_api import Page

from tests.test_utils import (
    TEST_TIMEOUT,
    init_page_and_wait_ready,
    open_audio_menu,
    open_options_menu,
    set_log_level,
    wait_for_console_log,
)


@pytest.mark.record_har
def test_audio_flow(page: Page) -> None:
    """
    Main test for warning popups and constraints using DOM overlays.

    Implements WARN-01 to WARN-03: Mute/adjust, verify unchanged values, warnings.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Console message handler to capture logs."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        # Start CDP session for V8 JS coverage
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        # 1-3. Load engine, open options, set log level to DEBUG (0),
        # and open audio menu
        init_page_and_wait_ready(page)
        open_options_menu(page)
        set_log_level(page, logs, level_index=0)
        open_audio_menu(page, logs)

        # Get initial slider values
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

        # WARN-01: Master muted ➔ attempt sub-volume adjust (SFX)
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.toggleMuteMaster !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.toggleMuteMaster([0])")  # Mute
        wait_for_console_log(
            logs,
            lambda text: "master is muted" in text,
            pre_change_log_count,
            page,
        )

        # Change SFX Volume when Master is muted
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeSfxVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeSfxVolume([0])")
        wait_for_console_log(
            logs,
            lambda text: "master muted, cannot adjust sub-volume" in text
            or "warning dialog" in text,
            pre_change_log_count,
            page,
        )
        assert (
            page.evaluate("document.getElementById('sfx-slider').value") == initial_sfx
        ), "SFX value changed unexpectedly"

        # Master muted ➔ attempt sub-volume adjust (Music)
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeMusicVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeMusicVolume([0.3])")
        wait_for_console_log(
            logs,
            lambda text: "master muted, cannot adjust sub-volume" in text
            or "warning dialog" in text,
            pre_change_log_count,
            page,
        )
        assert (
            page.evaluate("document.getElementById('music-slider').value")
            == initial_music
        ), "Music value changed unexpectedly under Master mute"

        # Master muted ➔ attempt sub-volume adjust (Rotors)
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeRotorsVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeRotorsVolume([0.4])")
        wait_for_console_log(
            logs,
            lambda text: "master muted, cannot adjust sub-volume" in text
            or "warning dialog" in text,
            pre_change_log_count,
            page,
        )
        assert (
            page.evaluate("document.getElementById('rotors-slider').value")
            == initial_rotors
        ), "Rotors value changed unexpectedly under Master mute"

        # Unmute Master for next tests
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.toggleMuteMaster !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.toggleMuteMaster([1])")
        wait_for_console_log(
            logs,
            lambda text: "master mute button toggled to: true" in text,
            pre_change_log_count,
            page,
        )

        # WARN-02: SFX muted ➔ attempt weapon adjust
        page.wait_for_function(
            "() => typeof window.toggleMuteSfx !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.toggleMuteSfx([0])")  # Mute

        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeWeaponVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeWeaponVolume([0])")
        wait_for_console_log(
            logs,
            lambda text: "sfx muted, cannot adjust" in text or "warning dialog" in text,
            pre_change_log_count,
            page,
        )
        assert (
            page.evaluate("document.getElementById('weapon-slider').value")
            == initial_weapon
        ), "Weapon value changed unexpectedly"

        # SFX muted ➔ attempt rotors adjust
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.changeRotorsVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.changeRotorsVolume([0.5])")
        wait_for_console_log(
            logs,
            lambda text: "sfx muted, cannot adjust" in text or "warning dialog" in text,
            pre_change_log_count,
            page,
        )
        assert (
            page.evaluate("document.getElementById('rotors-slider').value")
            == initial_rotors
        ), "Rotors value changed unexpectedly under SFX mute"

        # Unmute SFX
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.toggleMuteSfx !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.toggleMuteSfx([1])")
        wait_for_console_log(
            logs,
            lambda text: "sfx mute button toggled to: true" in text,
            pre_change_log_count,
            page,
        )

        # WARN-03: Master unmuted ➔ adjust sub-volume (Music)
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
                raise AssertionError(
                    f"Unexpected warning after music volume change: {log['text']}"
                )

    except Exception as e:
        print(f"Test: 'test_audio_flow' failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_audio_failure_screenshot_{timestamp}.png")
        log_file: str = f"artifacts/test_audio_failure_console_logs_{timestamp}.txt"
        with open(log_file, "w", encoding="utf-8") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        with open(
            f"artifacts/test_audio_failure_html_{timestamp}.html", "w", encoding="utf-8"
        ) as f:
            f.write(page.content())
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_audio_flow_test.json", "w", encoding="utf-8") as f:
                json.dump(coverage, f)
