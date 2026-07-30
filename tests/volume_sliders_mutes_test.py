# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/volume_sliders_mutes_test.py
"""
Volume Sliders & Mute Toggles Test Suite (Playwright + UI Automation Overlay)
=============================================================================

Overview
--------
E2E tests for VOL-01 to VOL-12: Validate volume slider adjustments, side-effect
logging (AudioManager + persistence), and mute toggles in the audio menu.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with custom_shell.html overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k volume_sliders_mutes -q

Artifacts
---------
v8_coverage_volume_sliders_mutes_test.json, artifacts/test_volume_failure_*.png/txt
"""

import json
import os
import time
from typing import Any, Callable

from playwright.sync_api import Page, expect

# Import shared utilities at the top of the file
from tests.test_utils import (
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    has_save_log,
    wait_for_console_log,
)


def test_volume_sliders_mutes(shared_page: Page) -> None:
    """
    Main test suite for volume sliders and mute toggles using DOM overlays.

    Implements VOL-01 to VOL-12: Adjust sliders, toggle mutes, verify states/logs.

    :param shared_page: The Playwright page object.
    :type shared_page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []
    cdp_session = None
    coverage_started = False

    def on_console(msg: Any) -> None:
        """
        Console message handler to capture logs.

        :param msg: The console message.
        :type msg: Any
        :rtype: None
        """
        logs.append({"type": msg.type, "text": msg.text})

    shared_page.on("console", on_console)

    try:
        # Start CDP session for V8 JS coverage
        cdp_session = shared_page.context.new_cdp_session(shared_page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )
        coverage_started = True

        # Verify canvas
        canvas = shared_page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found"
        assert "SkyLockAssault" in shared_page.title(), "Title not found"

        # Open options
        shared_page.wait_for_selector(
            "#options-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.optionsPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.optionsPressed([])")

        # Go to Advanced settings
        shared_page.wait_for_selector(
            "#advanced-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.advancedPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.advancedPressed([])")
        shared_page.wait_for_function(
            "() => typeof window.changeLogLevel !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('log-level-select')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # Set log level DEBUG
        pre_change_log_count = len(logs)
        shared_page.evaluate("window.changeLogLevel([0])")
        wait_for_console_log(
            logs,
            lambda text: "log level changed to: debug" in text,
            pre_change_log_count,
            shared_page,
        )
        assert shared_page.evaluate(
            "document.getElementById('audio-button') !== null"
        ), "Audio button not found/displayed"

        # Go back to Options menu
        shared_page.wait_for_selector(
            "#advanced-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        shared_page.wait_for_function(
            "() => typeof window.advancedBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.advancedBackPressed([])")

        # Open audio
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.audioPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioPressed([])")

        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        wait_for_console_log(
            logs,
            lambda text: "audio button pressed" in text,
            pre_change_log_count,
            shared_page,
        )

        # VOL-01: Adjust Master volume slider
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.changeMasterVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeMasterVolume([0.5])")
        wait_for_console_log(
            logs,
            lambda text: "applied loaded master volume to audioserver: 0.5" in text,
            pre_change_log_count,
            shared_page,
        )
        wait_for_console_log(
            logs,
            lambda text: "master volume level in audiomanager: 0.5" in text
            or "saved" in text
            or "encrypted" in text,
            pre_change_log_count,
            shared_page,
        )
        value = shared_page.evaluate("document.getElementById('master-slider').value")
        assert value == "0.5", f"Master slider value not set to 0.5, got {value}"

        # VOL-02: Mute / unmute Master
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteMaster !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteMaster([0])")
        wait_for_console_log(
            logs,
            lambda text: "master is muted" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-master').checked")
        assert not checked, "Master mute not toggled to muted"

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteMaster !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteMaster([1])")
        wait_for_console_log(
            logs,
            lambda text: "master mute button toggled to: true" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-master').checked")
        assert checked, "Master mute not toggled to unmuted"

        # VOL-03: Adjust Music volume slider
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.changeMusicVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeMusicVolume([0.3])")
        wait_for_console_log(
            logs,
            lambda text: "applied loaded music volume to audioserver: 0.3" in text,
            pre_change_log_count,
            shared_page,
        )
        wait_for_console_log(
            logs,
            lambda text: "music volume level in audiomanager: 0.3" in text
            or "saved" in text
            or "encrypted" in text,
            pre_change_log_count,
            shared_page,
        )
        value = shared_page.evaluate("document.getElementById('music-slider').value")
        assert value == "0.3", f"Music slider value not set to 0.3, got {value}"

        # VOL-04: Mute / unmute Music
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteMusic !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteMusic([0])")
        wait_for_console_log(
            logs,
            lambda text: "music is muted" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-music').checked")
        assert not checked, "Music mute not toggled to muted"

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteMusic !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteMusic([1])")
        wait_for_console_log(
            logs,
            lambda text: "music mute button toggled to: true" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-music').checked")
        assert checked, "Music mute not toggled to unmuted"

        # VOL-05: Adjust SFX volume slider
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.changeSfxVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeSfxVolume([0.8])")
        wait_for_console_log(
            logs,
            lambda text: "applied loaded sfx volume to audioserver: 0.8" in text,
            pre_change_log_count,
            shared_page,
        )
        wait_for_console_log(
            logs,
            lambda text: "sfx volume level in audiomanager: 0.8" in text
            or "saved" in text
            or "encrypted" in text,
            pre_change_log_count,
            shared_page,
        )
        sfx_logs = logs[pre_change_log_count:]
        assert any(
            "sfx volume level in audiomanager: 0.8" in log["text"].lower()
            for log in sfx_logs
        ) or has_save_log(sfx_logs), "SFX volume side effect log missing"
        value = shared_page.evaluate("document.getElementById('sfx-slider').value")
        assert value == "0.8", f"SFX slider value not set to 0.8, got {value}"

        # VOL-06: Mute / unmute SFX
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteSfx !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteSfx([0])")
        wait_for_console_log(
            logs,
            lambda text: "sfx is muted" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-sfx').checked")
        assert not checked, "SFX mute not toggled to muted"

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteSfx !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteSfx([1])")
        wait_for_console_log(
            logs,
            lambda text: "sfx mute button toggled to: true" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-sfx').checked")
        assert checked, "SFX mute not toggled to unmuted"

        # VOL-07: Adjust Weapon volume slider
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.changeWeaponVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeWeaponVolume([0.2])")
        wait_for_console_log(
            logs,
            lambda text: "applied loaded sfx_weapon volume to audioserver: 0.2" in text,
            pre_change_log_count,
            shared_page,
        )
        value = shared_page.evaluate("document.getElementById('weapon-slider').value")
        assert value == "0.2", f"Weapon slider value not set to 0.2, got {value}"

        # VOL-08: Mute / unmute Weapon
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteWeapon !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteWeapon([0])")
        wait_for_console_log(
            logs,
            lambda text: "weapon is muted" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-weapon').checked")
        assert not checked, "Weapon mute not toggled to muted"

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteWeapon !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteWeapon([1])")
        wait_for_console_log(
            logs,
            lambda text: "weapon mute button toggled to: true" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-weapon').checked")
        assert checked, "Weapon mute not toggled to unmuted"

        # VOL-09: Adjust Rotors volume slider
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.changeRotorsVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeRotorsVolume([0.9])")
        wait_for_console_log(
            logs,
            lambda text: "applied loaded sfx_rotors volume to audioserver: 0.9" in text,
            pre_change_log_count,
            shared_page,
        )
        value = shared_page.evaluate("document.getElementById('rotors-slider').value")
        assert value == "0.9", f"Rotors slider value not set to 0.9, got {value}"

        # VOL-10: Mute / unmute Rotors
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteRotors !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteRotors([0])")
        wait_for_console_log(
            logs,
            lambda text: "rotors is muted" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-rotors').checked")
        assert not checked, "Rotors mute not toggled to muted"

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteRotors !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteRotors([1])")
        wait_for_console_log(
            logs,
            lambda text: "rotors mute button toggled to: true" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-rotors').checked")
        assert checked, "Rotors mute not toggled to unmuted"

        # VOL-11: Adjust Menu volume slider
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.changeMenuVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeMenuVolume([0.9])")
        wait_for_console_log(
            logs,
            lambda text: "applied loaded sfx_menu volume to audioserver: 0.9" in text,
            pre_change_log_count,
            shared_page,
        )
        value = shared_page.evaluate("document.getElementById('menu-slider').value")
        assert value == "0.9", f"Menu slider value not set to 0.9, got {value}"

        # VOL-12: Mute / unmute Menu
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteMenu !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteMenu([0])")
        wait_for_console_log(
            logs,
            lambda text: "menu is muted" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-menu').checked")
        assert not checked, "Menu mute not toggled to muted"

        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.toggleMuteMenu !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.toggleMuteMenu([1])")
        wait_for_console_log(
            logs,
            lambda text: "menu mute button toggled to: true" in text,
            pre_change_log_count,
            shared_page,
        )
        checked = shared_page.evaluate("document.getElementById('mute-menu').checked")
        assert checked, "Menu mute not toggled to unmuted"

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        shared_page.screenshot(
            path=f"artifacts/test_volume_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_volume_failure_console_logs_{timestamp}.txt", "w"
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session and coverage_started:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open("v8_coverage_volume_sliders_mutes_test.json", "w") as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")
