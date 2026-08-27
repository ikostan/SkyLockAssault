# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/load_main_menu_test.py
"""
Main Menu Load Test (Playwright + UI Automation with DOM Overlays)
=================================================================

Overview
--------
E2E test: Verifies Godot HTML5 build loads main menu in browser. Ensures network idle,
canvas visibility, godotInitialized flag (from main_menu.gd _ready()), and title
contains "SkyLockAssault".

No coords - DOM overlays for verification.

Test Flow
---------
- Attach console listener and CDP profiler to fresh page context.
- Call init_page_and_wait_ready(page) to load Godot engine.
- Wait canvas visible and window.godotInitialized (signals _ready() complete).
- Assert title and menu overlays.
- CDP V8 coverage saved.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k load_main_menu_test -q

Artifacts
---------
v8_coverage_load_main_menu_test.json, artifacts/test_load_main_menu_failure_*.png/txt
"""

import json
import os
import time
from typing import Any

from playwright.sync_api import Page, expect

# Configuration for stability in different environments
from tests.test_utils import DEFAULT_TIMEOUT, TEST_TIMEOUT, init_page_and_wait_ready


def test_load_main_menu(page: Page) -> None:
    """
    Main test for main menu load using DOM overlays.

    Verifies canvas visibility, godotInitialized flag, and title.

    Note: Uses function-scoped `page` (not `shared_page`) so CDP profiling and console
    listeners attach BEFORE engine boot to capture startup logs and V8 coverage.

    :param page: The Playwright page object.
    :type page: Page
    :rtype: None
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """
        Console message handler.

        :param msg: The console message.
        :rtype: None
        """
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)
    try:
        # Start CDP session for V8 JS coverage before load to capture startup
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        # Fresh page fixture navigates and boots engine while listeners are active
        init_page_and_wait_ready(page)

        # Verify canvas and title to ensure game is initialized
        canvas = page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)
        box: dict[str, float] | None = canvas.bounding_box()
        assert box is not None, "Canvas not found on page"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Assert main-menu DOM overlay elements are present and visible
        expect(page.locator("#start-button")).to_be_visible(timeout=TEST_TIMEOUT)
        expect(page.locator("#options-button")).to_be_visible(timeout=TEST_TIMEOUT)
        expect(page.locator("#quit-button")).to_be_visible(timeout=TEST_TIMEOUT)

    except Exception as e:
        print(f"Test: 'test_load_main_menu' failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp = int(time.time())
        page.screenshot(
            path=f"artifacts/test_load_main_menu_failure_screenshot_{timestamp}.png"
        )

        log_file: str = (
            f"artifacts/test_load_main_menu_failure_console_logs_{timestamp}.txt"
        )
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
            print(f"Console logs saved to {log_file}")

        with open(
            f"artifacts/test_load_main_menu_failure_html_{timestamp}.html", "w"
        ) as f:
            f.write(page.content())

        print(
            f"Failure logs: artifacts/test_load_main_menu_failure_console_logs_{timestamp}.txt. Error: {e}"
        )
        raise
    finally:
        # 1. Unregister console listener
        try:
            page.remove_listener("console", on_console)
        except Exception as exc:
            print(f"Warning: Could not remove console listener: {exc}")

        # 2. Stop coverage profiling and detach CDP session safely
        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open("v8_coverage_load_main_menu_test.json", "w") as f:
                    json.dump(coverage, f)
            except Exception as exc:
                print(f"Warning: Failed to harvest V8 coverage data: {exc}")
            finally:
                try:
                    cdp_session.detach()
                except Exception as exc:
                    print(f"Warning: Could not detach CDP session: {exc}")
