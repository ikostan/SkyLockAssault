# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/no_error_logs_test.py
"""
Console Error Integrity Test (Playwright + UI Automation)
=========================================================

Overview
--------
Verifies that the SkyLockAssault HTML5 build loads without triggering
any 'error' level logs in the browser console.

Test Flow
---------
- Listen to all console messages.
- Navigate to the index page and wait for network idle.
- Wait for window.godotInitialized (Godot _ready() signal).
- Assert that no logs with type="error" exist.
"""

import json
import os
import time

from playwright.sync_api import Page


def test_no_error_logs_after_load(page: Page) -> None:
    """
    E2E test to ensure zero console errors on initial load.

    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg) -> None:
        """Capture all console messages for inspection."""
        logs.append({"type": msg.type, "text": msg.text})

    # Attach the listener before navigation
    page.on("console", on_console)

    try:
        # Start CDP session for coverage (consistent with your other tests)
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        # Navigate and wait for the game to initialize
        page.goto(
            "http://localhost:8080/index.html", wait_until="networkidle", timeout=5000
        )
        page.wait_for_function("() => window.godotInitialized", timeout=5000)

        # Allow a short buffer for any delayed post-load errors
        page.wait_for_timeout(1000)

        # Filter for error logs
        error_logs = [log for log in logs if log["type"] == "error"]

        # Detailed assertion message for easier debugging
        error_details = "\n".join(
            [f"[{err['type']}] {err['text']}" for err in error_logs]
        )
        assert (
            len(error_logs) == 0
        ), f"Found {len(error_logs)} error(s) in console:\n{error_details}"

    except Exception as e:
        # print(f"Test: 'test_no_error_logs_after_load' failed: {str(e)}")
        print(f"Test: 'test_no_error_logs_after_load' failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time())
        page.screenshot(path=f"artifacts/test_error_logs_failure_{timestamp}.png")

        # Save logs for inspection
        with open(
                f"artifacts/test_error_logs_console_{timestamp}.txt",
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
            with open("v8_coverage_no_error_logs_test.json", "w", encoding="utf-8") as f:
                json.dump(coverage, f)
