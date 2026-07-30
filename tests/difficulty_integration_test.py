# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/refactor/difficulty_integration_test.py
"""
Difficulty Integration Test (Playwright, Python)
================================================

Overview
--------
This module contains an end-to-end integration test that verifies
difficulty selection propagates correctly from the options menu into
gameplay. The test automates the browser with Playwright (sync API),
drives the Godot HTML5 export via DOM overlays and exposed JavaScript
callbacks (`window.xxxPressed`), and asserts on console log messages
emitted by the game to validate behavior.
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


def test_difficulty_integration(page: Page) -> None:
    """
    Full flow validation that difficulty 2.0 affects gameplay systems.

    Navigates menus using DOM overlays, sets log level to DEBUG, sets difficulty
    to 2.0 in Gameplay Settings, starts the game, waits for level load, fires
    weapon, and verifies execution logs.
    """
    logs: list[dict[str, str]] = []

    def on_console(msg: Any) -> None:
        """Console message handler to capture logs."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    cdp_session, coverage_started = start_game_and_wait_ready(
        page=page,
        logs=logs,
        difficulty=2.0,
        log_level="DEBUG",
    )

    try:
        # Verify canvas is present and visible
        canvas = page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)
        box = canvas.bounding_box()
        assert box is not None, "Canvas not found on page"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Check for unexpected error logs after setup
        unexpected_errors = [
            log["text"]
            for log in logs
            if "error" in log["text"].lower()
            and not any(
                ignored in log["text"].lower()
                for ignored in [
                    "encryption aborted",
                    "salt is empty",
                    "key generation failed",
                    "empty next_scene",
                    "loading failed or invalid",
                ]
            )
        ]
        assert (
            not unexpected_errors
        ), f"Unexpected error messages found in logs: {unexpected_errors}"

        # Focus Canvas, fire weapon, and verify execution under difficulty 2.0
        canvas.focus()
        pre_change_log_count = len(logs)
        page.keyboard.press("Space")
        wait_for_console_log(
            logs,
            lambda text: "weapon.fire() delegating to" in text or "firing" in text,
            pre_change_log_count,
            page,
        )

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(
            path=(f"artifacts/test_difficulty_integration_failure_" f"{timestamp}.png")
        )
        log_file = (
            f"artifacts/test_difficulty_integration_failure_"
            f"console_logs_{timestamp}.txt"
        )
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
                    "v8_coverage_difficulty_integration_test.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")
