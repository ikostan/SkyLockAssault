import pytest
import os
from playwright.sync_api import Page, ConsoleMessage


@pytest.fixture(scope="function")
def error_logs(page: Page):
    logs = []

    def handle(msg: ConsoleMessage):
        if msg.type == "error":
            logs.append(msg.text)

    page.on("console", handle)
    yield logs


def test_main_menu_loads(page: Page, error_logs):
    # Configurable timeout from env (defaults to 10000ms for faster CI)
    timeout = int(os.getenv("PW_TIMEOUT", 10000))
    page.goto("http://localhost:8080/index.html")
    page.wait_for_load_state("networkidle", timeout=timeout)  # Network idle first
    # Replacement for time.sleep: Wait for canvas visibility (basic init indicator)
    # Verifies Godot canvas loads and is visible
    page.wait_for_selector("canvas", state="visible", timeout=timeout)
    # Optional full init wait:
    # Assumes main_menu.gd sets window.godotInitialized in _ready() for web exports.
    # If not set (e.g., non-web or code change),
    # test may timeout—see docs or make optional via env var.
    page.wait_for_function("() => window.godotInitialized", timeout=timeout)  # Confirms _ready() finished
    # Assert existence to catch if signal missing (prevents silent timeout)
    assert page.evaluate("typeof window.godotInitialized !== 'undefined'"), ("godotInitialized not set—check "
                                                                             "main_menu.gd")
    assert "SkyLockAssault" in page.title()  # Title check
    page.screenshot(path="main_menu.png")  # Debug screenshot
    assert not error_logs, f"Console errors: {error_logs}"  # Check no errors
