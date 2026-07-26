# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/test_utils.py
"""Shared utility functions and helpers for SkyLockAssault Playwright E2E tests."""

import os
import time
from typing import Callable

from playwright.sync_api import Page

# Shared timeout configurations across test suites
DEFAULT_TIMEOUT = int(os.getenv("DEFAULT_TIMEOUT", "30000"))
TEST_TIMEOUT = int(os.getenv("TEST_TIMEOUT", "5000"))


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
