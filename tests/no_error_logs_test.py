# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/no_error_logs_test.py
"""
Console & Page Error Integrity Test (Playwright + UI Automation)
=========================================================

Overview
--------
Verifies that the SkyLockAssault HTML5 build loads without triggering
any 'error' level logs or uncaught exceptions in the browser.

Test Flow
---------
- Listen to all console messages and uncaught page errors.
- Navigate to the index page and wait for network idle.
- Wait for window.godotInitialized (Godot _ready() signal).
- Assert that no logs with type="error" or uncaught exceptions exist.
"""

import json
import os
import time
from playwright.sync_api import Page


def test_no_error_logs_after_load(page: Page) -> None:
    """
    E2E test to ensure zero console errors and uncaught exceptions on initial load.
    """
    logs: list[dict[str, str]] = []
    page_errors: list[str] = []
    cdp_session = None

    def on_console(msg) -> None:
        """Capture all console messages for inspection."""
        logs.append({"type": msg.type, "text": msg.text})

    def on_page_error(exc) -> None:
        """Capture uncaught exceptions (pageerror)."""
        page_errors.append(f"Uncaught Exception: {exc.message}\n{exc.stack}")

    # Attach listeners before navigation
    page.on("console", on_console)
    page.on("pageerror", on_page_error)

    try:
        # Start CDP session for coverage
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

        # Combine errors for a comprehensive assertion
        all_errors = [f"[{err['type']}] {err['text']}" for err in error_logs] + page_errors
        error_details = "\n".join(all_errors)

        assert (
                len(all_errors) == 0
        ), f"Found {len(all_errors)} error(s) during load:\n{error_details}"

    except Exception as e:
        print(f"Test: 'test_no_error_logs_after_load' failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time())
        page.screenshot(path=f"artifacts/test_error_logs_failure_{timestamp}.png")

        # Save all captured logs and exceptions for inspection
        with open(
                f"artifacts/test_error_logs_console_{timestamp}.txt",
                "w",
                encoding="utf-8",
        ) as f:
            f.write("--- CONSOLE LOGS ---\n")
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")

            f.write("\n--- UNCAUGHT EXCEPTIONS ---\n")
            for p_err in page_errors:
                f.write(f"{p_err}\n")
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open(
                    "v8_coverage_no_error_logs_test.json", "w", encoding="utf-8"
            ) as f:
                json.dump(coverage, f)
