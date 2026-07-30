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
- Attach console listener to fresh page context.
- Navigate to index.html and wait for engine initialization signal.
- Listen for specific error patterns: "SCRIPT ERROR", "Compile Error", "Parse Error".
- Fail if any critical engine or script errors are detected during load.
"""

import os
import time

from playwright.sync_api import Page

from tests.test_utils import DEFAULT_TIMEOUT, init_page_and_wait_ready


# DO NOT REFACTOR: Must inject function-scoped `page`, NOT `shared_page`.
def test_no_critical_errors_on_load(page: Page) -> None:
    """
    Verifies that the game loads without script compilation or engine errors.

    IMPORTANT ARCHITECTURAL CONSTRAINT:
    -----------------------------------
    This test MUST consume the function-scoped `page` fixture (NOT `shared_page`).
    The console listener (`page.on("console")`) MUST be attached BEFORE page
    navigation and engine bootup.

    Using `shared_page` initializes Godot prior to listener attachment, causing
    `init_page_and_wait_ready()` to return instantly and leaving the captured
    `logs` list empty—allowing GDScript compilation or runtime load errors to bypass detection.
    """
    logs: list[dict[str, str]] = []

    def on_console(msg) -> None:
        """Capture all console messages for inspection."""
        logs.append({"type": msg.type, "text": msg.text})

    # CRITICAL: Attach console listener BEFORE navigating and booting Godot
    page.on("console", on_console)

    try:
        # Fresh page fixture navigates and logs startup output
        init_page_and_wait_ready(page)

        # Analyze captured logs for specific patterns
        critical_errors = [
            log["text"]
            for log in logs
            if log["type"] in ["error", "warning"]
            and (
                log["type"] == "error"
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
            )
        ]

        if critical_errors:
            error_summary = "\n".join([f" - {err}" for err in critical_errors])
            assert (
                not critical_errors
            ), f"Critical errors detected during load:\n{error_summary}"

    except Exception as e:
        print(f"Load validation failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time())
        page.screenshot(
            path=f"artifacts/test_load_error_screenshot_{timestamp}.png"
        )

        with open(f"artifacts/test_load_error_logs_{timestamp}.txt", "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
