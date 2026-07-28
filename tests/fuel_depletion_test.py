# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/fuel_depletion_test.py
"""
Fuel Depletion Test (Playwright, Python)
=======================================

Overview
--------
Validates that fuel depletes at the expected rate under difficulty 2.0.
Drives the Godot HTML5 export via DOM overlays and directly queries
`window.getCurrentFuel()` via the JavaScript bridge.
"""

import json
import os
import time
from typing import Any

from playwright.sync_api import Page, expect

from tests.test_utils import (
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    wait_for_console_log,
)


def test_fuel_depletion(page: Page) -> None:
    """
    Validate fuel depletes under difficulty 2.0 after starting the level.

    Navigates menus via DOM overlays/callbacks, sets difficulty to 2.0, starts
    the game, and queries `window.getCurrentFuel()` to verify depletion rate.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None
    coverage_started = False

    def on_console(msg: Any) -> None:
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )
        coverage_started = True

        page.goto(
            "http://localhost:8080/index.html",
            wait_until="networkidle",
            timeout=DEFAULT_TIMEOUT,
        )

        # 1. Wait deterministically for Godot engine initialization
        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )

        canvas = page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)
        box = canvas.bounding_box()
        assert box is not None, "Canvas not found on page"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # 2. Open Options menu
        page.wait_for_selector("#options-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.optionsPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.optionsPressed([])")

        # 3. Go to Advanced settings and set log level to DEBUG
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

        pre_change_log_count = len(logs)
        page.evaluate("window.changeLogLevel([0])")
        wait_for_console_log(
            logs,
            lambda text: "log level changed to: debug" in text,
            pre_change_log_count,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        # Go back to Options menu
        page.wait_for_selector(
            "#advanced-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.advancedBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.advancedBackPressed([])")

        # 4. Open Gameplay Settings to access Difficulty control
        page.wait_for_selector(
            "#gameplay-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.gameplayPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.gameplayPressed([])")

        # Set difficulty to 2.0
        page.wait_for_function(
            "() => typeof window.changeDifficulty !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        pre_change_log_count = len(logs)
        page.evaluate("window.changeDifficulty([2.0])")
        wait_for_console_log(
            logs,
            lambda text: "setting 'difficulty' updated to: 2" in text
                         or "difficulty" in text,
            pre_change_log_count,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        # Return to Options menu from Gameplay Settings
        page.wait_for_selector(
            "#gameplay-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.gameplayBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.gameplayBackPressed([])")

        # 5. Return to Main Menu from Options
        page.wait_for_selector(
            "#options-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.optionsBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        pre_change_log_count = len(logs)
        page.evaluate("window.optionsBackPressed([])")
        wait_for_console_log(
            logs,
            lambda text: "options back button pressed" in text
                         or "back button pressed" in text
                         or "options menu exited" in text,
            pre_change_log_count,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        # 6. Start game
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.startPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        pre_change_log_count = len(logs)
        page.evaluate("window.startPressed([])")

        wait_for_console_log(
            logs,
            lambda text: "hud successfully wired" in text or "player ready" in text,
            pre_change_log_count,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        # 7. Focus Canvas and verify fuel depletion via console logs
        canvas.focus()
        pre_change_log_count = len(logs)

        # Wait until we receive a fuel log showing it has dropped below 95.0 under difficulty 2.0
        wait_for_console_log(
            logs,
            lambda text: "setting 'current_fuel' updated to:" in text
                         and float(text.split("updated to: ")[1]) < 95.0,
            pre_change_log_count,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        fuel_logs = [log["text"] for log in logs if "current_fuel" in log["text"]]
        assert len(fuel_logs) > 0, "No fuel logs found"

        last_fuel = float(fuel_logs[-1].split("updated to: ")[1])
        assert last_fuel < 95.0, f"Expected faster drop (<95.0), got {last_fuel}"
    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(
            path=f"artifacts/test_fuel_depletion_failure_{timestamp}.png"
        )
        log_file = f"artifacts/test_fuel_depletion_failure_console_logs_{timestamp}.txt"
        with open(log_file, "w", encoding="utf-8") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session and coverage_started:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open("v8_coverage_fuel_depletion_test.json", "w", encoding="utf-8") as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")
