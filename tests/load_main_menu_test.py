import time
import os
import pytest
from playwright.sync_api import Page


@pytest.fixture(scope="function")
def page(playwright: "playwright") -> Page:
    browser = playwright.chromium.launch(
        headless=True,
        args=["--enable-unsafe-swiftshader", "--disable-gpu", "--use-gl=swiftshader"]
    )
    context = browser.new_context(viewport={"width": 1280, "height": 720})
    page = context.new_page()
    yield page
    page.close()
    context.close()
    browser.close()


def test_main_menu_loads(page: Page):
    logs: list = []
    try:
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
    except Exception as e:
        # Save screenshot
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_load_main_menu_failure_{int(time.time())}.png")
        print(f"Test: Load main menu test failed: {str(e)}")
        # Save logs to file (in case teardown fixture is skipped)
        log_file = "artifacts/test_load_main_menu_failure_console_logs.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        print(f"Console logs saved to {log_file}")
        raise
