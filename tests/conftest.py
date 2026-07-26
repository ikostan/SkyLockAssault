# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/conftest.py
"""
Shared pytest fixtures and configs for SkyLockAssault E2E tests.
"""

import re
from pathlib import Path
from typing import Generator

import pytest
from playwright.sync_api import Browser, BrowserContext, Page, Playwright


@pytest.fixture(scope="session")
def browser_instance(playwright: Playwright) -> Generator[Browser, None, None]:
    """
    Session-scoped Chromium launch fixture to minimize startup
    overhead across the test suite.
    """
    browser = playwright.chromium.launch(
        headless=True,
        args=[
            "--enable-unsafe-swiftshader",
            "--disable-gpu",
            "--use-gl=swiftshader",
        ],
    )
    yield browser
    browser.close()


@pytest.fixture(scope="function")
def page(
    browser_instance: Browser, request: pytest.FixtureRequest
) -> Generator[Page, None, None]:
    """
    Function-scoped page fixture providing clean browser context
    isolation for each test.
    """
    har_path = None
    if request.node.get_closest_marker("record_har"):
        nodeid = request.node.nodeid
        safe_nodeid = re.sub(r"[^A-Za-z0-9._-]+", "_", nodeid)
        artifacts_dir = Path("artifacts")
        artifacts_dir.mkdir(parents=True, exist_ok=True)
        har_path = artifacts_dir / f"{safe_nodeid}.har"

    context: BrowserContext = browser_instance.new_context(
        viewport={"width": 1280, "height": 720},
        record_har_path=str(har_path) if har_path else None,
    )
    page: Page = context.new_page()
    yield page
    context.close()


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line(
        "markers",
        "record_har: Mark tests that should record HAR files "
        "for network tracing in Playwright.",
    )
