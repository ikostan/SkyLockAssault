# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/log_level_test.py
"""
Log Level Setting Test (Playwright, Python)
===========================================

Overview
--------
Verifies that cycling through all log levels (DEBUG, INFO, WARNING,
ERROR, NONE) correctly updates the application state in Advanced settings.
"""

import json
import os
import time
from typing import Any

from playwright.sync_api import Page

from tests.test_utils import (
    TEST_TIMEOUT,
    init_cdp_coverage,
    init_page_and_wait_ready,
    open_options_menu,
)


def test_log_level_setting(page: Page) -> None:
    """
    E2E: Verifies cycling through all log levels in Advanced settings.

    Steps:
    - Open game page and wait for Godot initialization.
    - Navigate to Options ➔ Advanced settings.
    - Sequentially test all log levels (0 to 4) and verify
      `window.currentLogLevel`.
    """
    logs: list[dict[str, str]] = []

    def on_console(msg: Any) -> None:
        """Console message handler to capture logs."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    cdp_session, coverage_started = init_cdp_coverage(page)

    try:
        # 1. Load page and wait deterministically for Godot engine readiness
        init_page_and_wait_ready(page)

        # 2. Open Options menu
        open_options_menu(page)

        # 3. Go to Advanced settings
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

        # 4. Cycle through all log levels:
        # (0: DEBUG, 1: INFO, 2: WARNING, 3: ERROR, 4: NONE)
        log_levels = [
            (0, "DEBUG"),
            (1, "INFO"),
            (2, "WARNING"),
            (3, "ERROR"),
            (4, "NONE"),
        ]

        for level_idx, level_name in log_levels:
            page.evaluate(f"window.changeLogLevel([{level_idx}])")

            # Deterministically wait until window.currentLogLevel matches target index
            page.wait_for_function(
                f"() => window.currentLogLevel === {level_idx}",
                timeout=TEST_TIMEOUT,
            )

            current_level = page.evaluate("window.currentLogLevel")
            assert current_level == level_idx, (
                f"Expected log level {level_idx} ({level_name}), "
                f"got {current_level}"
            )

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(
            path=f"artifacts/test_log_level_setting_failure_{timestamp}.png"
        )
        log_file = (
            f"artifacts/test_log_level_setting_failure_" f"console_logs_{timestamp}.txt"
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
                    "v8_coverage_log_level_setting_test.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")
