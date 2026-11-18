# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
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
from typing import Any

from playwright.sync_api import Page
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError

from tests.test_utils import (
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    init_page_and_wait_ready,
    open_audio_menu,
    open_options_menu,
    set_log_level,
    wait_for_console_log,
)

# Must match SettingsMenuBase.OPTIONS_MENU_OVERLAY_IDS (#1165).
OPTIONS_MENU_OVERLAY_IDS: tuple[str, ...] = (
    "controls-button",
    "audio-button",
    "advanced-button",
    "gameplay-button",
    "options-back-button",
)


def _overlay_display(page: Page, element_id: str) -> str:
    """Return the computed CSS display of a DOM overlay ("missing" if absent)."""
    return page.evaluate(
        "(id) => { const el = document.getElementById(id);"
        " return el ? window.getComputedStyle(el).display : 'missing'; }",
        element_id,
    )


def _wait_for_overlays(
    page: Page, shown: tuple[str, ...], hidden: tuple[str, ...], path: str
) -> None:
    """
    Wait until every id in ``shown`` has display ``block`` and every id in
    ``hidden`` has display ``none``; on timeout, fail listing every element.
    """
    try:
        page.wait_for_function(
            "([shown, hidden]) => {"
            " const d = (id) => { const el = document.getElementById(id);"
            " return el ? window.getComputedStyle(el).display : 'missing'; };"
            " return shown.every((id) => d(id) === 'block')"
            " && hidden.every((id) => d(id) === 'none'); }",
            arg=[list(shown), list(hidden)],
            timeout=TEST_TIMEOUT,
        )
    except PlaywrightTimeoutError:
        displays = {i: _overlay_display(page, i) for i in (*shown, *hidden)}
        raise AssertionError(
            f"{path}: expected shown {list(shown)} and hidden {list(hidden)},"
            f" got {displays}"
        ) from None


def _assert_options_overlays_restored(page: Page, path: str) -> None:
    """Assert all five Options buttons are shown and difficulty-slider is hidden."""
    displays = {
        element_id: _overlay_display(page, element_id)
        for element_id in (*OPTIONS_MENU_OVERLAY_IDS, "difficulty-slider")
    }
    hidden = [i for i in OPTIONS_MENU_OVERLAY_IDS if displays[i] != "block"]
    assert not hidden, f"{path}: Options buttons not shown: {hidden} ({displays})"
    assert (
        displays["difficulty-slider"] == "none"
    ), f"{path}: difficulty-slider (a Gameplay control) is shown ({displays})"


def test_back_flow(shared_page: Page) -> None:
    """
    Main test suite for back navigation using DOM overlays.

    Implements BACK-01 to BACK-04: Back from audio, verify return, state persistence.

    :param shared_page: The Playwright page object.
    :type shared_page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Console message handler to capture logs."""
        logs.append({"type": msg.type, "text": msg.text})

    shared_page.on("console", on_console)

    try:
        # Start CDP session for V8 JS coverage
        cdp_session = shared_page.context.new_cdp_session(shared_page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        # 1-3. Load engine, open options, set log level to DEBUG (0),
        # and open audio menu
        open_options_menu(shared_page)
        set_log_level(shared_page, logs, level_index=0)
        open_audio_menu(shared_page, logs)

        # BACK-01: Back returns to parent menu
        pre_change_log_count = len(logs)
        shared_page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioBackPressed([])")

        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('gameplay-button')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('master-slider')"
            ").display === 'none'",
            timeout=TEST_TIMEOUT,
        )
        wait_for_console_log(
            logs,
            lambda text: "audio settings: back button pressed" in text,
            pre_change_log_count,
            shared_page,
        )

        # Re-enter audio for next tests
        open_audio_menu(shared_page)

        # BACK-02: Back without changes
        initial_master: str = shared_page.evaluate(
            "document.getElementById('master-slider').value"
        )
        shared_page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioBackPressed([])")

        open_audio_menu(shared_page)

        assert (
            shared_page.evaluate("document.getElementById('master-slider').value")
            == initial_master
        ), "State mutated without changes"

        # Re-enter audio via page reload
        shared_page.reload(wait_until="domcontentloaded")
        gpu_btn = shared_page.locator("#gpu-warning-dismiss-btn")
        modal_visible = False
        try:
            gpu_btn.wait_for(state="visible", timeout=1500)
            modal_visible = True
        except PlaywrightTimeoutError:
            pass

        if modal_visible:
            gpu_btn.click()

        shared_page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )
        open_options_menu(shared_page)
        open_audio_menu(shared_page)

        # BACK-03: Back after slider changes
        shared_page.wait_for_function(
            "() => typeof window.changeMusicVolume !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.changeMusicVolume([0.4])")
        shared_page.wait_for_function(
            "() => document.getElementById('music-slider').value === '0.4'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioBackPressed([])")

        open_audio_menu(shared_page)

        assert (
            shared_page.evaluate("document.getElementById('music-slider').value")
            == "0.4"
        ), "Changes did not persist after back"

        # BACK-04: Back from mid-interaction
        pre_change_log_count = len(logs)
        shared_page.evaluate("""
            const slider = document.getElementById('sfx-slider');
            slider.value = 0.6;
            slider.dispatchEvent(new Event('input'));  // Mid-drag
        """)
        shared_page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        shared_page.evaluate("window.audioBackPressed([])")
        shared_page.wait_for_function(
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
        shared_page.screenshot(
            path=f"artifacts/test_back_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_back_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_back_flow_test.json", "w", encoding="utf-8") as f:
                json.dump(coverage, f)


def test_back_restores_options_overlays(page: Page) -> None:
    """
    BACK-05 / BACK-06 (#1165): Back from Audio or Controls restores exactly the
    Options menu's five DOM buttons, and shows no Gameplay control.

    BACK-05: Options -> Audio -> Back. All five Options buttons are visible.
    BACK-06: Options -> Controls -> Back. All five Options buttons are visible
    and difficulty-slider is hidden.

    :param page: Function-scoped Playwright page (fresh engine boot).
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []
    page.on("console", lambda msg: logs.append({"type": msg.type, "text": msg.text}))

    try:
        init_page_and_wait_ready(page)
        open_options_menu(page)
        page.wait_for_selector(
            "#options-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        _assert_options_overlays_restored(page, "Options opened")

        # BACK-05: Audio -> Back. The Options buttons must be hidden while Audio
        # is open, so the check after Back sees them change from none to block.
        open_audio_menu(page)
        _wait_for_overlays(
            page, ("master-slider",), OPTIONS_MENU_OVERLAY_IDS, "Audio opened"
        )
        page.evaluate("window.audioBackPressed([])")
        _wait_for_overlays(
            page,
            OPTIONS_MENU_OVERLAY_IDS,
            ("master-slider", "difficulty-slider"),
            "Audio -> Back",
        )
        _assert_options_overlays_restored(page, "Audio -> Back")

        # BACK-06: Controls -> Back
        page.wait_for_function(
            "() => typeof window.controlsPressed === 'function'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.controlsPressed([])")
        _wait_for_overlays(
            page, ("controls-back-button",), OPTIONS_MENU_OVERLAY_IDS, "Controls opened"
        )
        page.wait_for_function(
            "() => typeof window.controlsBackPressed === 'function'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.controlsBackPressed([])")
        _wait_for_overlays(
            page,
            OPTIONS_MENU_OVERLAY_IDS,
            ("controls-back-button", "difficulty-slider"),
            "Controls -> Back",
        )
        _assert_options_overlays_restored(page, "Controls -> Back")

    except Exception as e:
        print(f"Test BACK-05/06 failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(
            path=f"artifacts/test_back_overlays_failure_screenshot_{timestamp}.png"
        )
        with open(
            f"artifacts/test_back_overlays_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
