import pytest
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
    page.goto("http://localhost:8080/index.html")
    page.wait_for_load_state("networkidle", timeout=30000)  # Network idle first
    # Replacement for time.sleep(5): Wait for canvas visibility (basic init indicator)
    page.wait_for_selector("canvas", state="visible", timeout=30000)  # Verifies Godot canvas loads and is visible
    # Optional: If adding JS signal in GDScript (see below), add this for full init wait
    # After page.wait_for_selector("canvas", state="visible", timeout=30000)
    # Confirms _ready() finished
    page.wait_for_function("() => window.godotInitialized", timeout=30000)
    assert "SkyLockAssault" in page.title()  # Title check
    page.screenshot(path="main_menu.png")  # Debug screenshot
    assert not error_logs, f"Console errors: {error_logs}"  # Check no errors
