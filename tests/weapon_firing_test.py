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
    start_game_and_wait_ready,
    wait_for_console_log,
)


def test_weapon_firing(shared_page: Page) -> None:
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

    def on_console(msg: Any) -> None:
        """Console message handler to capture logs."""
        logs.append({"type": msg.type, "text": msg.text})

    shared_page.on("console", on_console)

    cdp_session = None
    coverage_started = False

    try:
        # 1. Initialize CDP coverage, load page, configure settings & start game
        cdp_session, coverage_started = start_game_and_wait_ready(
            page=shared_page,
            logs=logs,
            log_level="DEBUG",
        )

        # 2. Verify canvas visibility
        canvas = shared_page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)

        # 3. Focus Canvas and fire weapon
        canvas.focus()
        pre_fire_log_count = len(logs)
        shared_page.keyboard.press("Space")

        # 4. Verify weapon firing log
        wait_for_console_log(
            logs,
            lambda text: "firing with scaled cooldown:" in text.lower(),
            pre_fire_log_count,
            shared_page,
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
        shared_page.screenshot(
            path=f"artifacts/test_weapon_firing_failure_{timestamp}.png"
        )
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
