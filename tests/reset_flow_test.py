# tests/reset_flow_test.py
"""
Reset Functionality Test Suite (Playwright + UI Automation with DOM Overlays)
============================================================================

Overview
--------
E2E tests for RESET-01 to RESET-05 and STATE-01 to STATE-02: Validate reset button behavior in audio menu, including defaults restoration, no-op on defaults, partial changes, persistence after navigation/reload, rapid clicks, and isolation to audio menu.

Navigates to audio menu, adjusts sliders/mutes, resets, verifies states/logs. For STATE-01, reloads page to check persistence (assumes config saves on reset; if not, adjust assertions).

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

import os
import time
import json
from playwright.sync_api import Page


def test_reset_flow(page: Page) -> None:
    """
    Main test suite for reset functionality using DOM overlays.

    Implements RESET-01 to RESET-05 and STATE-01 to STATE-02: Adjust/reset, verify defaults, persistence, stability.

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

        # Navigate to options menu
        page.wait_for_selector('#options-button', state='visible', timeout=1500)
        page.click("#options-button", force=True, timeout=1500)

        # Set log level to DEBUG
        pre_change_log_count = len(logs)
        page.wait_for_function('window.changeLogLevel !== undefined', timeout=1500)
        page.evaluate("window.changeLogLevel([0])")  # Index 0 for DEBUG
        page.wait_for_timeout(3000)
        new_logs = logs[pre_change_log_count:]
        assert any("log level changed to: debug" in log["text"].lower() for log in new_logs), "Failed to set log level to DEBUG"

        # Navigate to audio sub-menu
        page.wait_for_selector('#audio-button', state='visible', timeout=1500)
        assert page.evaluate("document.getElementById('audio-button') !== null"), "Audio button not found/displayed"
        pre_change_log_count = len(logs)
        # page.click("#audio-button", force=True)
        page.wait_for_function('window.audioPressed !== undefined', timeout=1500)
        page.evaluate("window.audioPressed([0])")
        page.wait_for_timeout(5000)  # Wait for audio scene load and JS eval
        audio_display: str = page.evaluate("window.getComputedStyle(document.getElementById('master-slider')).display")
        assert audio_display == 'block', "Audio menu not loaded (master-slider not displayed)"
        new_logs = logs[pre_change_log_count:]
        assert any("audio button pressed." in log["text"].lower() for log in new_logs), "Audio navigation log not found"

        # RESET-01: Reset all buses to defaults
        # Preconditions: Sliders moved, some mutes active
        # Steps: 1) Adjust multiple sliders 2) Toggle some mutes 3) Press Reset
        # Expected: Every slider back to 1.0, all mutes off
        page.evaluate("window.changeMasterVolume([0.5])")
        page.evaluate("window.changeMusicVolume([0.3])")
        page.evaluate("window.changeSfxVolume([0.7])")
        page.evaluate("window.toggleMuteMusic([0])")
        page.evaluate("window.toggleMuteMaster([0])")
        page.wait_for_timeout(1500)
        pre_change_log_count = len(logs)
        page.wait_for_function('window.audioResetPressed !== undefined', timeout=1500)
        page.evaluate("window.audioResetPressed([])")
        page.wait_for_timeout(1500)
        assert float(page.evaluate("document.getElementById('master-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('music-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('sfx-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('weapon-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('rotors-slider').value")) == 1.0
        assert page.evaluate("document.getElementById('mute-master').checked")
        assert page.evaluate("document.getElementById('mute-music').checked")
        assert page.evaluate("document.getElementById('mute-sfx').checked")
        assert page.evaluate("document.getElementById('mute-weapon').checked")
        assert page.evaluate("document.getElementById('mute-rotors').checked")
        new_logs = logs[pre_change_log_count:]
        assert any("audio reset pressed" in log["text"].lower() for log in new_logs), "Reset log not found"
        assert any("audio volumes reset to defaults" in log["text"].lower() for log in new_logs), "Reset log not found"

        # RESET-02: Reset does not duplicate sliders already default
        # Preconditions: All at defaults
        # Steps: Press Reset
        # Expected: No change, UI stable
        pre_reset_logs = len(logs)
        page.wait_for_function('window.audioResetPressed !== undefined', timeout=1500)
        page.evaluate("window.audioResetPressed([])")
        page.wait_for_timeout(1500)
        assert float(page.evaluate("document.getElementById('master-slider').value")) == 1.0, "Value changed unexpectedly"
        new_logs = logs[pre_reset_logs:]
        assert not any("error" in log["text"].lower() for log in new_logs), "Unexpected error after reset on defaults"

        # RESET-03: Reset after incomplete changes
        # Preconditions: Only Master & Rotors changed
        # Steps: Press Reset
        # Expected: All buses at defaults
        page.wait_for_function('window.changeMasterVolume !== undefined', timeout=1500)
        page.evaluate("window.changeMasterVolume([0.4])")
        page.wait_for_function('window.changeRotorsVolume !== undefined', timeout=1500)
        page.evaluate("window.changeRotorsVolume([0.6])")
        page.wait_for_timeout(1500)
        pre_change_log_count = len(logs)
        page.wait_for_function('window.audioResetPressed !== undefined', timeout=1500)
        page.evaluate("window.audioResetPressed([])")
        page.wait_for_timeout(1500)
        assert float(page.evaluate("document.getElementById('master-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('rotors-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('music-slider').value")) == 1.0  # Unchanged remains default
        new_logs = logs[pre_change_log_count:]
        assert any("audio reset pressed" in log["text"].lower() for log in new_logs), "Reset log not found"
        assert any("audio volumes reset to defaults" in log["text"].lower() for log in new_logs), "Reset log not found"

        # RESET-04: Reset persists after Back navigation
        # Preconditions: Modified then Reset
        # Steps: Back → Re-enter Audio
        # Expected: Defaults remain
        page.wait_for_function('window.changeSfxVolume !== undefined', timeout=1500)
        page.evaluate("window.changeSfxVolume([0.2])")
        pre_change_log_count = len(logs)
        page.wait_for_function('window.audioResetPressed !== undefined', timeout=1500)
        page.evaluate("window.audioResetPressed([])")
        page.wait_for_timeout(1500)
        new_logs = logs[pre_change_log_count:]
        assert any("audio reset pressed" in log["text"].lower() for log in new_logs), "Reset log not found"
        assert any("audio volumes reset to defaults" in log["text"].lower() for log in new_logs), "Reset log not found"
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_selector('#audio-button', state='visible', timeout=1500)
        # page.click("#audio-button", force=True)
        page.wait_for_function('window.audioPressed !== undefined', timeout=1500)
        page.evaluate("window.audioPressed([0])")
        page.wait_for_timeout(5000)
        assert float(page.evaluate("document.getElementById('sfx-slider').value")) == 1.0, "Reset not persisted after back"

        # RESET-05: Rapid Reset clicks
        # Preconditions: Controls modified
        # Steps: Click Reset quickly 3×
        # Expected: UI stays stable with defaults, no JS errors
        page.wait_for_function('window.changeMasterVolume !== undefined', timeout=1500)
        page.evaluate("window.changeMasterVolume([0.5])")
        page.wait_for_timeout(500)
        pre_change_log_count = len(logs)
        for _ in range(3):
            page.wait_for_function('window.audioResetPressed !== undefined', timeout=1500)
            page.evaluate("window.audioResetPressed([])")
            page.wait_for_timeout(300)  # Rapid
        assert float(page.evaluate("document.getElementById('master-slider').value")) == 1.0
        new_logs = logs[pre_change_log_count:]
        assert not any("error" in log["text"].lower() for log in new_logs), "JS errors during rapid reset"

        # STATE-01: Reset button state persists in config
        # Preconditions: After Reset + Save
        # Steps: Reload game/settings
        # Expected: Defaults retained for all sliders and mutes
        pre_change_log_count = len(logs)
        page.wait_for_function('window.audioResetPressed !== undefined', timeout=1500)
        page.evaluate("window.audioResetPressed([])")
        page.wait_for_timeout(1500)
        new_logs = logs[pre_change_log_count:]
        assert any("audio reset pressed" in log["text"].lower() for log in new_logs), "Reset log not found"
        assert any("audio volumes reset to defaults" in log["text"].lower() for log in new_logs), "Reset log not found"

        # Reload and validate persisted defaults for all audio controls
        page.reload()
        page.wait_for_timeout(5000)
        page.wait_for_function("() => window.godotInitialized", timeout=5000)
        page.wait_for_selector('#options-button', state='visible', timeout=5000)
        page.click("#options-button", force=True)
        page.wait_for_selector('#audio-button', state='visible', timeout=5000)
        # page.click("#audio-button", force=True)
        page.wait_for_function('window.audioPressed !== undefined', timeout=1500)
        page.evaluate("window.audioPressed([0])")
        page.wait_for_timeout(5000)

        # Sliders should all be at default volume (mirroring RESET-01 expectations)
        assert float(page.evaluate("document.getElementById('master-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('music-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('sfx-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('weapon-slider').value")) == 1.0
        assert float(page.evaluate("document.getElementById('rotors-slider').value")) == 1.0

        # Mutes should retain their default checked state after reload
        assert page.evaluate("document.getElementById('mute-master').checked")
        assert page.evaluate("document.getElementById('mute-music').checked")
        assert page.evaluate("document.getElementById('mute-sfx').checked")
        assert page.evaluate("document.getElementById('mute-weapon').checked")
        assert page.evaluate("document.getElementById('mute-rotors').checked")

        # STATE-02: Reset doesn't affect other menus
        # Preconditions: Reset in Audio
        # Steps: Navigate other menus
        # Expected: Other menus unaffected
        # Navigate back to options menu to access difficulty-slider
        page.wait_for_function('window.audioBackPressed !== undefined', timeout=1500)
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_timeout(2000)
        # Cache the initial difficulty value to avoid depending on a hardcoded default
        initial_difficulty_value = float(page.evaluate("document.getElementById('difficulty-slider').value"))
        pre_change_log_count = len(logs)
        assert initial_difficulty_value == 1.0, "Unexpected initial difficulty default"
        # Navigate back to audio menu to test reset isolation
        page.wait_for_selector('#audio-button', state='visible', timeout=1500)
        # page.click("#audio-button", force=True)
        page.wait_for_function('window.audioPressed !== undefined', timeout=1500)
        page.evaluate("window.audioPressed([0])")
        page.wait_for_timeout(5000)
        page.wait_for_function('window.audioResetPressed !== undefined', timeout=1500)
        page.evaluate("window.audioResetPressed([])")
        page.wait_for_timeout(1500)
        new_logs = logs[pre_change_log_count:]
        assert any("audio reset pressed" in log["text"].lower() for log in new_logs), "Reset log not found"
        assert any("audio volumes reset to defaults" in log["text"].lower() for log in new_logs), "Reset log not found"
        page.wait_for_function('window.audioBackPressed !== undefined', timeout=1500)
        page.evaluate("window.audioBackPressed([])")
        page.wait_for_timeout(2000)
        # Later, after audio reset and navigating back to the difficulty menu,
        # assert the difficulty slider has not changed from its initial value.
        assert float(page.evaluate(
            "document.getElementById('difficulty-slider').value")) == initial_difficulty_value, "Difficulty reset unexpectedly"
    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_reset_failure_screenshot_{timestamp}.png")
        with open(f"artifacts/test_reset_failure_console_logs_{timestamp}.txt", "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")['result']
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_reset_flow_test.json", "w") as f:
                json.dump(coverage, f)
