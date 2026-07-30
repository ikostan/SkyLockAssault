# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/test_utils.py
"""Shared utility functions and helpers for SkyLockAssault Playwright E2E tests."""

import os
import time
from typing import Any, Callable

from playwright.sync_api import Page, expect

# Shared timeout configurations across test suites
DEFAULT_TIMEOUT = int(os.getenv("DEFAULT_TIMEOUT", "30000"))
TEST_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "5000"))

LOG_LEVEL_MAP: dict[str, int] = {
    "DEBUG": 0,
    "INFO": 1,
    "WARNING": 2,
    "ERROR": 3,
    "NONE": 4,
}


def has_save_log(logs: list[dict[str, str]]) -> bool:
    """Check if any log entry indicates settings were saved."""
    return any(
        ("encrypted" in log["text"].lower() and "settings" in log["text"].lower())
        or "falling back to plaintext" in log["text"].lower()
        or "saved" in log["text"].lower()
        for log in logs
    )


def wait_for_console_log(
    logs: list[dict[str, str]],
    predicate: Callable[[str], bool],
    start_idx: int,
    page: Page,
    timeout_ms: int = TEST_TIMEOUT,
) -> None:
    """Helper to poll until a matching console log arrives or timeout expires."""
    start_time = time.monotonic()
    while (time.monotonic() - start_time) * 1000 < timeout_ms:
        if any(predicate(log["text"].lower()) for log in logs[start_idx:]):
            return
        page.wait_for_timeout(50)  # Micro-poll for event loop progression
    raise AssertionError(
        "Timed out waiting for expected console log matching "
        f"predicate after {timeout_ms}ms"
    )


def init_cdp_coverage(page: Page) -> tuple[Any, bool]:
    """Initialize V8 coverage profiling via CDP."""
    try:
        cdp = page.context.new_cdp_session(page)
        cdp.send("Profiler.enable")
        cdp.send("Profiler.startPreciseCoverage", {"callCount": True, "detailed": True})
        return cdp, True
    except Exception as e:
        print(f"Warning: Could not start CDP coverage session: {e}")
        return None, False


def init_page_and_wait_ready(page: Page) -> None:
    """Navigates to the game index and waits for Godot engine initialization and canvas readiness."""
    page.goto(
        "http://localhost:8080/index.html",
        wait_until="networkidle",
        timeout=DEFAULT_TIMEOUT,
    )
    page.wait_for_function(
        "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
    )
    canvas = page.locator("canvas")
    expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)
    box = canvas.bounding_box()
    assert box is not None, "Canvas not found on page"
    assert "SkyLockAssault" in page.title(), "Title not found"


def open_options_menu(page: Page) -> None:
    """Navigate from Main Menu to Options menu."""
    page.wait_for_selector("#options-button", state="visible", timeout=TEST_TIMEOUT)
    page.wait_for_function(
        "() => typeof window.optionsPressed !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    page.evaluate("window.optionsPressed([])")


def open_audio_menu(page: Page, logs: list[dict[str, str]] | None = None) -> None:
    """Navigate to Audio Settings sub-menu and wait for visibility."""
    page.wait_for_selector("#audio-button", state="visible", timeout=TEST_TIMEOUT)
    page.wait_for_function(
        "() => typeof window.audioPressed !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )

    pre_change_log_count = len(logs) if logs is not None else 0
    page.evaluate("window.audioPressed([0])")

    page.wait_for_function(
        "() => window.getComputedStyle("
        "document.getElementById('master-slider')"
        ").display === 'block'",
        timeout=TEST_TIMEOUT,
    )

    if logs is not None:
        wait_for_console_log(
            logs,
            lambda text: "audio button pressed" in text,
            pre_change_log_count,
            page,
        )


def set_log_level(page: Page, logs: list[dict[str, str]], level_index: int = 0) -> None:
    """Navigate to Advanced Settings, set log level, and return to Options."""
    page.wait_for_selector("#advanced-button", state="visible", timeout=TEST_TIMEOUT)
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

    pre_change_log_count = len(logs)
    page.evaluate(f"window.changeLogLevel([{level_index}])")
    wait_for_console_log(
        logs,
        lambda text: "log level changed to:" in text,
        pre_change_log_count,
        page,
        timeout_ms=DEFAULT_TIMEOUT,
    )

    page.wait_for_selector(
        "#advanced-back-button", state="visible", timeout=TEST_TIMEOUT
    )
    page.wait_for_function(
        "() => typeof window.advancedBackPressed !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    page.evaluate("window.advancedBackPressed([])")


def set_difficulty(
    page: Page, logs: list[dict[str, str]], difficulty: float = 2.0
) -> None:
    """Navigate to Gameplay Settings, set difficulty, and return to Options."""
    page.wait_for_selector("#gameplay-button", state="visible", timeout=TEST_TIMEOUT)
    page.wait_for_function(
        "() => typeof window.gameplayPressed !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    page.evaluate("window.gameplayPressed([])")

    page.wait_for_function(
        "() => typeof window.changeDifficulty !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    page.wait_for_function(
        "() => window.getComputedStyle("
        "document.getElementById('difficulty-slider')"
        ").display === 'block'",
        timeout=TEST_TIMEOUT,
    )
    pre_change_log_count = len(logs)
    page.evaluate(f"window.changeDifficulty([{difficulty}])")
    wait_for_console_log(
        logs,
        lambda text: "setting 'difficulty' updated to:" in text,
        pre_change_log_count,
        page,
        timeout_ms=DEFAULT_TIMEOUT,
    )

    page.wait_for_selector(
        "#gameplay-back-button", state="visible", timeout=TEST_TIMEOUT
    )
    page.wait_for_function(
        "() => typeof window.gameplayBackPressed !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    page.evaluate("window.gameplayBackPressed([])")


def start_game_and_wait_ready(
    page: Page,
    logs: list[dict[str, str]],
    difficulty: float | None = None,
    log_level: str | int = "DEBUG",
) -> tuple[Any, bool]:
    """
    Shared E2E setup helper that initializes V8 coverage, loads Godot,
    configures settings, and starts gameplay.
    """
    cdp_session, coverage_started = init_cdp_coverage(page)

    init_page_and_wait_ready(page)
    open_options_menu(page)

    if isinstance(log_level, str):
        key = log_level.upper()
        if key not in LOG_LEVEL_MAP:
            raise ValueError(f"Unknown log level: {log_level!r}")
        lvl_index = LOG_LEVEL_MAP[key]
    else:
        lvl_index = log_level

    set_log_level(page, logs, level_index=lvl_index)

    if difficulty is not None:
        set_difficulty(page, logs, difficulty=difficulty)

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

    return cdp_session, coverage_started
