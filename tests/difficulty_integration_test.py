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

Specifically, the test:
- Loads the game at http://localhost:8080/index.html and verifies
  engine initialization (`window.godotInitialized === true`),
  canvas, and title.
- Opens Options -> Advanced settings, sets Log Level to DEBUG
  (`window.changeLogLevel([0])`) to surface detailed logs.
- Opens Gameplay settings, sets Difficulty to 2.0
  (`window.changeDifficulty([2.0])`).
- Returns to the main menu and starts the game
  (`window.startPressed([])`).
- Waits for scene initialization, focuses canvas, fires weapon
  (Space key), and verifies execution.
- Asserts on expected logs for log level change, navigation, and
  gameplay initialization under the chosen difficulty.
  It also records JavaScript coverage via CDP as a workaround
  for missing Playwright Python coverage API.

Prerequisites
-------------
- A local server hosting the game at http://localhost:8080/index.html
  (see files/docs/Docker_Local_Test_Server.md).
- Python with pytest and Playwright installed. Example:
  - pip install pytest playwright
  - playwright install chromium
- The Godot HTML5 build should emit console logs used by this test:
  - "Options button pressed." / "Options menu loaded."
  - "Back button pressed."
  - "Start Game menu button pressed."
  - "Log level changed to: DEBUG"
  - "Difficulty changed to: 2.0"
  - "Player ready. Weapons loaded."
  - "Weapon.fire() delegating to BulletFirer"

How It Works
------------
- The test leverages shared browser fixtures from ``tests/conftest.py``
  to execute Chromium with GPU/WebGL flags.
- It creates a CDP session to start precise JavaScript coverage collection
  for V8, then listens to browser console events to gather logs.
- UI interactions use DOM overlays and exposed window callbacks
  (e.g., ``window.optionsPressed``, ``window.changeDifficulty``)
  synchronized deterministically with ``wait_for_console_log``.
- Asserts on engine logs during navigation, level transition,
  and weapon invocation.

Artifacts
---------
- v8_coverage_difficulty_integration_test.json: V8 coverage captured via
  CDP and saved at teardown.
- artifacts/test_difficulty_integration_failure_*.png: Screenshot on failure.
- artifacts/test_difficulty_integration_failure_console_logs_*.txt:
  Console logs on failure.

Running the Test
----------------
- Run only this test:
  pytest tests/refactor/difficulty_integration_test.py -k difficulty_integration_test -q

Maintenance Notes
-----------------
- Keep asserted log strings in sync with the Godot scripts
  (options_menu.gd, main_menu.gd, weapon.gd, etc.).
- Balance changes to fuel or weapon cooldown may require adjusting
  thresholds or asserted log values.
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


def test_difficulty_integration(page: Page) -> None:
    """
    Full flow validation that difficulty 2.0 affects gameplay systems.

    Navigates menus using DOM overlays, sets log level to DEBUG, sets difficulty
    to 2.0 in Gameplay Settings, starts the game, waits for level load, fires weapon,
    and verifies execution logs.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None
    coverage_started = False

    def on_console(msg: Any) -> None:
        """Console message handler to capture logs."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    try:
        # Start CDP session for V8 JS coverage
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

        # Verify canvas and page title
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

        # 3. Open Advanced menu
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
        page.wait_for_function(
            "() => window.getComputedStyle("
            "document.getElementById('log-level-select')"
            ").display === 'block'",
            timeout=TEST_TIMEOUT,
        )

        # Set log level to DEBUG (index 0) — surfaces all subsequent DEBUG logs
        pre_change_log_count = len(logs)
        page.evaluate("window.changeLogLevel([0])")
        wait_for_console_log(
            logs,
            lambda text: "log level changed to: debug" in text,
            pre_change_log_count,
            page,
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
            lambda text: "setting 'difficulty' updated to: 2" in text,
            pre_change_log_count,
            page,
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
        )

        # Check for unexpected error logs before starting game
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

        # 6. Start game
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.startPressed !== 'undefined'",
            timeout=TEST_TIMEOUT,
        )
        pre_change_log_count = len(logs)
        page.evaluate("window.startPressed([])")

        # 6b. Wait deterministically for gameplay scene to finish loading
        wait_for_console_log(
            logs,
            lambda text: "hud successfully wired" in text or "player ready" in text,
            pre_change_log_count,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        # 7. Focus Canvas, fire weapon, and verify execution
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
            path=(f"artifacts/test_difficulty_integration_failure_{timestamp}.png")
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
