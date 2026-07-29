# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/weapon_firing_test.py
"""
Weapon Firing Test (Playwright, Python)
======================================

Overview
--------
Validates that pressing the fire action (Space key) during gameplay
triggers a weapon firing event and logs the bullet instantiation.
Drives the Godot HTML5 export via DOM overlays and window callbacks.
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


def test_weapon_firing(page: Page) -> None:
    """
    E2E: Verifies that pressing Space during gameplay fires a weapon.

    Steps:
    - Open game page and wait for Godot initialization.
    - Open Options ➔ Advanced settings and set log level to DEBUG (0).
    - Return to Main Menu and start the level.
    - Wait for player/HUD readiness.
    - Focus canvas and press Space key.
    - Verify "Firing with scaled cooldown:" appears in console logs.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None
    coverage_started = False

    def on_console(msg: Any) -> None:
        """Console message handler to capture logs."""
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

        # Return to Options menu
        page.wait_for_selector(
            "#advanced-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.wait_for_function(
            "() => typeof window.advancedBackPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        page.evaluate("window.advancedBackPressed([])")

        # Return to Main Menu
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

        # 4. Start Game
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

        # 5. Focus Canvas and fire weapon
        canvas.focus()
        pre_fire_log_count = len(logs)
        page.keyboard.press("Space")

        # 6. Verify weapon firing log
        wait_for_console_log(
            logs,
            lambda text: "firing with scaled cooldown:" in text,
            pre_fire_log_count,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        bullet_logs = [
            log["text"]
            for log in logs
            if "firing with scaled cooldown:" in log["text"].lower()
        ]
        assert (
            len(bullet_logs) >= 1
        ), f"Expected firing event log, got {len(bullet_logs)}"

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_weapon_firing_failure_{timestamp}.png")
        log_file = f"artifacts/test_weapon_firing_failure_console_logs_{timestamp}.txt"
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
                with open(
                    "v8_coverage_weapon_firing_test.json", "w", encoding="utf-8"
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")
