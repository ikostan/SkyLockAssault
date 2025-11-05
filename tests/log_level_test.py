"""Test selecting DEBUG in Options."""

from playwright.sync_api import Page
from ui_elements_coords import UI_ELEMENTS  # Import the coordinates dictionary


def test_log_level_setting(page: Page):
    """E2E: Verifies that selecting DEBUG in Options updates the app's log level.

    Steps:
    - Listen to browser console messages to capture app logs.
    - Open the game page and wait for Godot initialization and canvas visibility.
    - Use pre-mapped UI coordinates to open Options, expand the log-level dropdown,
      and choose the DEBUG option.
    - Assert a console message confirms the level change.

    Args:
        page (Page): Playwright page fixture used to automate the browser.
    """
    logs: list = []
    page.on("console", lambda msg: logs.append({"type": msg.type, "text": msg.text}))
    page.goto("http://localhost:8080/index.html")
    page.wait_for_timeout(10000)
    page.wait_for_function("() => window.godotInitialized", timeout=10000)
    canvas = page.locator("canvas")
    page.wait_for_selector("canvas", state="visible", timeout=7000)
    box = canvas.bounding_box()
    # Click Options
    options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
    options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
    page.mouse.click(options_x, options_y)
    page.wait_for_timeout(7000)
    # Click dropdown
    log_dropdown_x = box['x'] + UI_ELEMENTS["log_level_dropdown"]["x"]
    log_dropdown_y = box['y'] + UI_ELEMENTS["log_level_dropdown"]["y"]
    page.mouse.click(log_dropdown_x, log_dropdown_y)
    page.wait_for_timeout(3000)  # Slightly increased for dropdown open
    # Select DEBUG
    debug_item_x = box['x'] + UI_ELEMENTS["log_level_debug"]["x"]
    debug_item_y = box['y'] + UI_ELEMENTS["log_level_debug"]["y"]
    page.mouse.click(debug_item_x, debug_item_y)
    page.wait_for_timeout(3000)
    assert any("Log level changed to: DEBUG" in log["text"] for log in logs), "Failed to set log level to DEBUG"
