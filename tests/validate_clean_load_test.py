# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/validate_clean_load_test.py
"""
Console Error Integrity Test (Playwright + UI Automation)
=========================================================

Overview
--------
Specific E2E test to catch GDScript compilation and runtime errors
identified in the browser console during Godot engine initialization.

Test Flow
---------
- Listen for specific error patterns: "SCRIPT ERROR", "Compile Error", "Parse Error".
- Monitor for 'Uncaught (in promise)' exceptions.
- Navigate to index.html and wait for engine initialization signal.
- Fail if any critical engine or script errors are detected.
"""

import json
import os
import time

from playwright.sync_api import Page


def test_no_critical_errors_on_load(page: Page) -> None:
    """
    Verifies that the game loads without script compilation or engine errors.

    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []

    def on_console(msg) -> None:
        """Capture all console messages for inspection."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        # 1. Navigate to the game
        page.goto(
            "http://localhost:8080/index.html", wait_until="networkidle", timeout=5000
        )

        # 2. Wait for the engine's ready signal
        page.wait_for_function("() => window.godotInitialized", timeout=5000)

        # 3. Analyze captured logs for the specific patterns seen in the screenshot
        critical_errors = [
            log["text"]
            for log in logs
            if log["type"] == "error"
            or any(
                pattern in log["text"]
                for pattern in [
                    "SCRIPT ERROR",
                    "Compile Error",
                    "Parse Error",
                    "Failed to load script",
                    "Uncaught (in promise)",
                ]
            )
        ]

        # 4. Detailed assertion
        if critical_errors:
            error_summary = "\n".join([f" - {err}" for err in critical_errors])
            assert (
                not critical_errors
            ), f"Critical errors detected during load:\n{error_summary}"

    except Exception as e:
        print(f"Load validation failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time())
        page.screenshot(path=f"artifacts/test_load_error_screenshot_{timestamp}.png")

        # Save logs for debugging the script failures
        with open(f"artifacts/test_load_error_logs_{timestamp}.txt", "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
