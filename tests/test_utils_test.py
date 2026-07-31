# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/test_utils_test.py
"""Targeted unit and integration tests for helper utilities in test_utils.py."""

from playwright.sync_api import Page, expect

from tests.test_utils import DEFAULT_TIMEOUT, init_page_and_wait_ready


def test_init_page_short_circuits_when_already_ready(shared_page: Page) -> None:
    """Verifies init_page_and_wait_ready skips redundant reloads on an initialized page."""
    # Ensure page is initially ready
    init_page_and_wait_ready(shared_page)

    # Set a custom DOM marker to detect if page reload occurs
    shared_page.evaluate("window.__test_no_reload_marker = true")

    # Call helper again on already-initialized page
    init_page_and_wait_ready(shared_page)

    # Verify marker still exists (proves page did not re-navigate or reload)
    is_same_session = shared_page.evaluate("window.__test_no_reload_marker === true")
    assert (
        is_same_session
    ), "init_page_and_wait_ready reloaded an already initialized page"
    expect(shared_page.locator("canvas")).to_be_visible(timeout=DEFAULT_TIMEOUT)


def test_init_page_loads_fresh_page_with_custom_url(page: Page) -> None:
    """Verifies init_page_and_wait_ready loads a fresh page and respects custom URL parameters."""
    target_url = "http://localhost:8080/index.html"
    init_page_and_wait_ready(page, url=target_url)

    assert target_url in page.url
    assert page.evaluate("window.godotInitialized === true")
    expect(page.locator("canvas")).to_be_visible(timeout=DEFAULT_TIMEOUT)
