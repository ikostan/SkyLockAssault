# tests/conftest.py
"""
Shared pytest fixtures and configs for SkyLockAssault E2E tests.
"""

import pytest
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
    har_path = "artifacts/har.har" if request.node.get_closest_marker("record_har") else None

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
        record_har_path=har_path  # Network trace for debugging (optional)
    )
    page = context.new_page()
    yield page
    context.close()
    browser.close()


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "record_har: Mark tests that should record HAR files for network tracing in Playwright."
    )
