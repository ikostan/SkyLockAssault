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
    # CDP for V8 coverage
    cdp_session = None  # Initialize to None outside try
    try:
        cdp_session = context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage", {"callCount": False, "detailed": True})
    except:
        pass
    yield page
    # Save coverage on teardown
    if cdp_session:
        try:
            coverage: dict = cdp_session.send("Profiler.takePreciseCoverage")
            # coverage_path = os.path.join("artifacts", "v8_coverage_audio_flow_test.json")
            with open("v8_coverage_audio_flow_test.json", "w") as f:
                json.dump(coverage, f, indent=4)
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
        except Exception as e:
            print(f"Failed to save coverage: {e}")
    context.close()
    browser.close()


def test_audio_flow(page: Page) -> None:
    """
    Main test for warning popups and constraints using DOM overlays.

    Implements WARN-01 to WARN-03: Mute/adjust, verify unchanged values, warning logs.

    :param page: The Playwright page object.
    :type page: Page
    :return: None
    :rtype: None
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg) -> None:
        """
        Console message handler.

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

        # Open options
        page.wait_for_selector('#options-button', state='visible', timeout=1500)
        page.click("#options-button", force=True)
        options_display: str = page.evaluate(
            "window.getComputedStyle(document.getElementById('log-level-select')).display")
        assert options_display == 'block', "Options menu not loaded (difficulty-slider not displayed)"

        # Set log level DEBUG
        page.evaluate("window.changeLogLevel([0])")
        page.wait_for_timeout(1000)
        assert any("log level changed to: debug" in log["text"].lower() for log in logs)
        assert page.evaluate("document.getElementById('audio-button') !== null"), "Audio button not found/displayed"

        # Open audio
        page.wait_for_selector('#audio-button', state='visible', timeout=1500)
        page.click("#audio-button", force=True)
        page.wait_for_timeout(1500)
        assert page.evaluate("window.getComputedStyle(document.getElementById('master-slider')).display") == 'block'
        assert any("audio button pressed" in log["text"].lower() for log in logs)

        # Get initial values
        initial_sfx: str = page.evaluate("document.getElementById('sfx-slider').value")
        initial_weapon: str = page.evaluate("document.getElementById('weapon-slider').value")
        initial_music: str = page.evaluate("document.getElementById('music-slider').value")
        initial_rotors: str = page.evaluate("document.getElementById('rotors-slider').value")

        # WARN-01: Master muted → attempt sub-volume adjust (SFX)
        page.evaluate("window.toggleMuteMaster([0])")  # Mute
        page.wait_for_timeout(1500)
        assert any("master is muted" in log["text"].lower() for log in logs)
        page.evaluate("window.changeSfxVolume([0])")
        page.wait_for_timeout(1500)
        assert page.evaluate(
            "document.getElementById('sfx-slider').value") == initial_sfx, "SFX value changed unexpectedly"
        assert any("master muted, cannot adjust sub-volume" in log["text"].lower() for log in logs) or any(
            "warning dialog" in log["text"].lower() for log in logs)

        # Additional: Master muted → attempt sub-volume adjust (Music)
        # Attempt to change music while Master is still muted
        page.evaluate("""
            const slider = document.getElementById('music-slider');
            slider.value = 0.3;
            slider.dispatchEvent(new Event('input'));
            slider.dispatchEvent(new Event('change'));
        """)
        page.wait_for_timeout(1500)
        assert page.evaluate(
            "document.getElementById('music-slider').value") == initial_music, "Music value changed unexpectedly under Master mute"
        assert any("master muted, cannot adjust sub-volume" in log["text"].lower() for log in logs) or any(
            "warning dialog" in log["text"].lower() for log in logs)

        # Additional: Master muted → attempt sub-volume adjust (Rotors)
        # Assuming Rotors is affected by Master mute (as a deeper sub-volume)
        page.evaluate("""
            const slider = document.getElementById('rotors-slider');
            slider.value = 0.4;
            slider.dispatchEvent(new Event('input'));
            slider.dispatchEvent(new Event('change'));
        """)
        page.wait_for_timeout(1500)
        assert page.evaluate(
            "document.getElementById('rotors-slider').value") == initial_rotors, "Rotors value changed unexpectedly under Master mute"
        assert any("master muted, cannot adjust sub-volume" in log["text"].lower() for log in logs) or any(
            "warning dialog" in log["text"].lower() for log in logs)

        # Unmute Master for next tests
        page.evaluate("window.toggleMuteMaster([1])")
        page.wait_for_timeout(1500)

        # WARN-02: SFX muted → attempt weapon adjust
        page.evaluate("window.toggleMuteSfx([0])")  # Mute
        page.wait_for_timeout(1500)
        page.evaluate("window.changeWeaponVolume([0])")
        page.wait_for_timeout(1500)
        assert page.evaluate(
            "document.getElementById('weapon-slider').value") == initial_weapon, "Weapon value changed unexpectedly"
        assert any("sfx muted, cannot adjust" in log["text"].lower() for log in logs) or any(
            "warning dialog" in log["text"].lower() for log in logs)

        # Additional: SFX muted → attempt rotors adjust (assuming Rotors under SFX)
        page.evaluate("""
            const slider = document.getElementById('rotors-slider');
            slider.value = 0.5;
            slider.dispatchEvent(new Event('input'));
            slider.dispatchEvent(new Event('change'));
        """)
        page.wait_for_timeout(1500)
        assert page.evaluate(
            "document.getElementById('rotors-slider').value") == initial_rotors, "Rotors value changed unexpectedly under SFX mute"
        assert any("sfx muted, cannot adjust" in log["text"].lower() for log in logs) or any(
            "warning dialog" in log["text"].lower() for log in logs)

        # Unmute SFX
        page.evaluate("window.toggleMuteSfx([1])")
        page.wait_for_timeout(1500)

        # WARN-03: Master unmuted → adjust sub-volume (Music)
        # Capture logs before the change to isolate new ones (good for debugging in Godot tests)
        pre_change_log_count = len(logs)

        page.evaluate("""
            const slider = document.getElementById('music-slider');
            slider.value = 0.6;
            slider.dispatchEvent(new Event('input'));
            slider.dispatchEvent(new Event('change'));
        """)
        page.wait_for_timeout(1500)

        # Verify the value changed (as expected, no mute constraint)
        assert page.evaluate("document.getElementById('music-slider').value") == '0.6', "Music value not changed"

        # Check only new logs for no warnings (stronger assertion, catches unrelated warnings)
        new_logs = logs[pre_change_log_count:]
        assert not any(
            "warning" in log["text"].lower() for log in new_logs), "Unexpected warning after music volume change"

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
            # Stop V8 coverage and save to file (even on failure)
            coverage = cdp_session.send("Profiler.takePreciseCoverage")['result']
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_audio_flow_test.json", "w") as f:
                json.dump(coverage, f)
