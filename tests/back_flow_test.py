# Copyright (C) 2025-2026 Egor Kostan
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
from typing import Any

from playwright.sync_api import Page

from tests.test_utils import (
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    init_page_and_wait_ready,
    open_audio_menu,
    open_options_menu,
    set_log_level,
    wait_for_console_log,
)


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

        # BACK-01: Back returns to parent menu
        pre_change_log_count = len(logs)
        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
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
            logs,
            lambda text: "audio settings: back button pressed" in text,
            pre_change_log_count,
            page,
        )

        # Re-enter audio for next tests
        open_audio_menu(page)

        # BACK-02: Back without changes
        initial_master: str = page.evaluate(
            "document.getElementById('master-slider').value"
        )
        page.wait_for_function(
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioBackPressed([])")

        open_audio_menu(page)

        assert (
            page.evaluate("document.getElementById('master-slider').value")
            == initial_master
        ), "State mutated without changes"

        # Re-enter audio via page reload
        page.reload(wait_until="networkidle")
        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )

        open_options_menu(page)
        open_audio_menu(page)

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
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.audioBackPressed([])")

        open_audio_menu(page)

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
            "() => typeof window.audioBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
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
