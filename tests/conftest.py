# tests/conftest.py
"""
Shared pytest fixtures and configs for SkyLockAssault E2E tests.
"""

import pytest
import re
from pathlib import Path
from playwright.sync_api import Page, Playwright


@pytest.fixture(scope="function")
def page(playwright: Playwright, request) -> Page:
    """
    Shared fixture for browser page setup with CDP for coverage.
    Launches headless Chromium with GPU flags for Godot HTML5/WebGL compatibility.

    :param playwright: The Playwright instance.
    :param request: Pytest request object (for accessing markers/configs).
    :return: The configured page object.
    """
    # Optional: Enable HAR recording if the test is marked with @pytest.mark.record_har
    har_path = None
    if request.node.get_closest_marker("record_har"):
        # Derive a per-test HAR path from the test nodeid to avoid overwrites
        nodeid = request.node.nodeid
        # Sanitize nodeid so it's safe as a filename (e.g. replace path separators/param brackets)
        safe_nodeid = re.sub(r"[^A-Za-z0-9._-]+", "_", nodeid)
        artifacts_dir = Path("artifacts")
        artifacts_dir.mkdir(parents=True, exist_ok=True)
        har_path = artifacts_dir / f"{safe_nodeid}.har"

    browser = playwright.chromium.launch(
        headless=True,  # Change to False for headful debugging (see browser visually)
        args=[
            "--enable-unsafe-swiftshader",
            "--disable-gpu",
            "--use-gl=swiftshader",
        ]
    )
    context = browser.new_context(
        viewport={"width": 1280, "height": 720},
        record_har_path=str(har_path) if har_path else None,  # Network trace for debugging (optional)
    )
    page = context.new_page()
    yield page
    context.close()
    browser.close()


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "record_har: Mark tests that should record HAR files for network tracing in Playwright."
    )
