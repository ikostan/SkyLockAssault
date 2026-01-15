# tests/volume_sliders_mutes_test.py
"""
Volume Sliders & Mute Toggles Test Suite (Playwright + UI Automation with DOM Overlays)
=====================================================================================

Overview
--------
E2E tests for VOL-01 to VOL-10: Validate volume slider adjustments and mute toggles in audio menu.

Assumes navigation to audio menu (reuses navigation logic). Verifies DOM value/checked states and console logs (DEBUG level).

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with custom_shell.html overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k volume_sliders_mutes -q

Artifacts
---------
artifacts/test_volume_failure_*.png/txt
"""

import os
import time
import pytest
from playwright.sync_api import Page, Playwright


@pytest.fixture(scope="function")
def page(playwright: Playwright) -> Page:
    """
    Fixture for browser page setup.

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
    yield page
    context.close()
    browser.close()


def test_volume_sliders_mutes(page: Page) -> None:
    """
    Main test suite for volume sliders and mute toggles using DOM overlays.

    Implements VOL-01 to VOL-10: Adjust sliders, toggle mutes, verify states/logs.

    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []

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
        page.goto("http://localhost:8080/index.html", wait_until="networkidle", timeout=5000)
        page.wait_for_function("() => window.godotInitialized", timeout=5000)

        # Navigate to options menu
        page.wait_for_selector('#options-button', state='visible', timeout=1500)
        page.click("#options-button", force=True, timeout=1500)

        # Set log level to DEBUG
        page.evaluate("window.changeLogLevel([0])")  # Index 0 for DEBUG
        page.wait_for_selector('#audio-button', state='visible', timeout=1500)
        assert page.evaluate("document.getElementById('audio-button') !== null"), "Audio button not found/displayed"
        assert any(
            "log level changed to: debug" in log["text"].lower() for log in logs), "Failed to set log level to DEBUG"

        # Navigate to audio sub-menu (use coordinates for Godot-rendered button)
        canvas = page.locator("canvas")
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found"
        # Open audio
        page.click("#audio-button", force=True)
        page.wait_for_timeout(5000)  # Wait for audio scene load
        audio_display: str = page.evaluate("window.getComputedStyle(document.getElementById('master-slider')).display")
        assert audio_display == 'block', "Audio menu not loaded (master-slider not displayed)"

        # VOL-01: Adjust Master volume slider
        page.evaluate("window.changeMasterVolume([0.5])")
        page.wait_for_timeout(1500)
        assert any("master volume changed to: 0.5" in log["text"].lower() for log in logs), "Master volume change log not found"
        value = page.evaluate("document.getElementById('master-slider').value")
        assert value == '0.5', f"Master slider value not set to 0.5, got {value}"

        # VOL-02: Mute / unmute Master
        # MUTE
        page.evaluate("window.toggleMuteMaster([0])")
        page.wait_for_timeout(1500)
        assert any("master is muted" in log["text"].lower() for log in logs), "Master mute log not found"
        checked = page.evaluate("document.getElementById('mute-master').checked")
        assert not checked, "Master mute not toggled to muted"
        # UNMUTE
        page.evaluate("window.toggleMuteMaster([1])")
        page.wait_for_timeout(1500)
        assert any("applied loaded master volume to audioserver: 0.5" in log["text"].lower() for log in logs), "Master mute log not found"
        checked = page.evaluate("document.getElementById('mute-master').checked")
        assert checked, "Master mute not toggled to unmuted"
        assert any("master mute button toggled to: true" in log["text"].lower() for log in logs), "Master unmute log not found"

        # VOL-03: Adjust Music volume slider
        page.evaluate("window.changeMusicVolume([0.3])")
        page.wait_for_timeout(1500)
        value = page.evaluate("document.getElementById('music-slider').value")
        assert value == '0.3', f"Music slider value not set to 0.3, got {value}"
        assert any("music volume changed to: 0.3" in log["text"].lower() for log in logs), "Music volume change log not found"

        # VOL-04: Mute / unmute Music
        # MUTE
        page.evaluate("window.toggleMuteMusic([0])")
        page.wait_for_timeout(1500)
        checked = page.evaluate("document.getElementById('mute-music').checked")
        assert not checked, "Music mute not toggled to muted"
        # UNMUTE
        page.evaluate("window.toggleMuteMusic([1])")
        page.wait_for_timeout(1500)
        checked = page.evaluate("document.getElementById('mute-music').checked")
        assert checked, "Music mute not toggled to unmuted"

        # VOL-05: Adjust SFX volume slider
        page.evaluate("window.changeSfxVolume([0.8])")
        page.wait_for_timeout(1500)
        value = page.evaluate("document.getElementById('sfx-slider').value")
        assert value == '0.8', f"SFX slider value not set to 0.8, got {value}"

        # VOL-06: Mute / unmute SFX
        # MUTE
        page.evaluate("window.toggleMuteSfx([0])")
        page.wait_for_timeout(1500)
        checked = page.evaluate("document.getElementById('mute-sfx').checked")
        assert not checked, "SFX mute not toggled to muted"
        # UNMUTE
        page.evaluate("window.toggleMuteSfx([1])")
        page.wait_for_timeout(1500)
        checked = page.evaluate("document.getElementById('mute-sfx').checked")
        assert checked, "SFX mute not toggled to unmuted"

        # VOL-07: Adjust Weapon volume slider
        page.evaluate("window.changeWeaponVolume([0.2])")
        page.wait_for_timeout(1500)
        value = page.evaluate("document.getElementById('weapon-slider').value")
        assert value == '0.2', f"Weapon slider value not set to 0.2, got {value}"

        # VOL-08: Mute / unmute Weapon
        page.evaluate("window.toggleMuteWeapon([0])")
        page.wait_for_timeout(1500)
        checked = page.evaluate("document.getElementById('mute-weapon').checked")
        assert not checked, "Weapon mute not toggled to muted"

        page.evaluate("window.toggleMuteWeapon([1])")
        page.wait_for_timeout(1500)
        checked = page.evaluate("document.getElementById('mute-weapon').checked")
        assert checked, "Weapon mute not toggled to unmuted"

        # VOL-09: Adjust Rotors volume slider
        page.evaluate("""
            const slider = document.getElementById('rotors-slider');
            slider.value = 0.9;
            slider.dispatchEvent(new Event('input'));
            slider.dispatchEvent(new Event('change'));
        """)
        page.wait_for_timeout(1500)
        value = page.evaluate("document.getElementById('rotors-slider').value")
        assert value == '0.9', f"Rotors slider value not set to 0.9, got {value}"

        # VOL-10: Mute / unmute Rotors
        page.evaluate("""
            const checkbox = document.getElementById('mute-rotors');
            checkbox.checked = false;
            checkbox.dispatchEvent(new Event('change'));
        """)
        page.wait_for_timeout(1500)
        checked = page.evaluate("document.getElementById('mute-rotors').checked")
        assert not checked, "Rotors mute not toggled to muted"

        page.evaluate("""
            const checkbox = document.getElementById('mute-rotors');
            checkbox.checked = true;
            checkbox.dispatchEvent(new Event('change'));
        """)
        page.wait_for_timeout(1500)
        checked = page.evaluate("document.getElementById('mute-rotors').checked")
        assert checked, "Rotors mute not toggled to unmuted"

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_volume_failure_screenshot_{timestamp}.png")
        with open(f"artifacts/test_volume_failure_console_logs_{timestamp}.txt", "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
