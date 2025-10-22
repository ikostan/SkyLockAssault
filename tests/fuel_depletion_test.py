# tests/fuel_depletion_test.py
import os
import time
import pytest
from playwright.sync_api import Page
from ui_elements_coords import UI_ELEMENTS  # Import the coordinates dictionary


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


def test_fuel_depletion(page: Page):
    logs: list = []
    try:
        # Set up console log capture
        page.on("console", lambda msg: logs.append({"type": msg.type, "text": msg.text}))
        page.goto("http://localhost:8080/index.html")
        page.wait_for_timeout(2000)

        canvas = page.locator("canvas")
        box = canvas.bounding_box()

        # Set log level to DEBUG
        # Open options menu
        options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
        options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
        page.mouse.click(options_x, options_y)
        page.wait_for_timeout(7000)
        # assert any("Options menu loaded." in log["text"] for log in logs), "Options menu failed to load"

        # Click log level dropdown
        log_dropdown_x = box['x'] + UI_ELEMENTS["log_level_dropdown"]["x"]
        log_dropdown_y = box['y'] + UI_ELEMENTS["log_level_dropdown"]["y"]
        page.mouse.click(log_dropdown_x, log_dropdown_y)
        page.wait_for_timeout(1000)

        # Select DEBUG
        debug_item_x = box['x'] + UI_ELEMENTS["log_level_debug"]["x"]
        debug_item_y = box['y'] + UI_ELEMENTS["log_level_debug"]["y"]
        page.mouse.click(debug_item_x, debug_item_y)
        page.wait_for_timeout(2000)
        assert any("Log level changed to: DEBUG" in log["text"] for log in logs), "Failed to set log level to DEBUG"

        # Back to main menu
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        page.mouse.click(back_x, back_y)
        page.wait_for_timeout(5000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button failed"

        # Open options
        options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
        options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
        page.mouse.click(options_x, options_y)  # Click Options button

        # Set difficulty to 2.0 (direct click to slider_2.0 position)
        slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_2.0"]["x"]
        slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_2.0"]["y"]
        page.mouse.move(slider_x, slider_y)  # Move to 2.0 position
        page.mouse.click(slider_x, slider_y)  # Click to set 2.0
        assert any("Difficulty changed to: 2.0" in log["text"] for log in logs), "Expected change to 2.0"

        # Back to main menu
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        page.mouse.click(back_x, back_y)  # Click Back button
        page.wait_for_timeout(5000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

        # Start level
        start_x = box['x'] + UI_ELEMENTS["start_game_button"]["x"]
        start_y = box['y'] + UI_ELEMENTS["start_game_button"]["y"]
        page.mouse.click(start_x, start_y)  # Click Start button
        page.wait_for_timeout(5000)  # Increased for level load
        assert any("Start Game menu button pressed." in log["text"] for log in logs), "Start Game button not found"

        # Simulate idle time for depletion (fuel_timer is 1s default; wait 5s for ~5 ticks)
        page.wait_for_timeout(10000)

        # Assert fuel dropped faster (e.g., parse logs for "Fuel left: X" < expected base)
        fuel_logs = [log["text"] for log in logs if "Fuel left:" in log["text"]]
        assert len(fuel_logs) > 0, "No fuel logs found"
        last_fuel = float(fuel_logs[-1].split("Fuel left: ")[1])  # Parse last value
        assert last_fuel < 95.0, f"Expected faster drop (<95.0), got {last_fuel}"  # Adjusted for 5-unit drop at 2.0x
    except Exception as e:
        # Save screenshot
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_fuel_depletion_failure_{int(time.time())}.png")
        print(f"Test: Fuel depletion test failed: {str(e)}")
        # Save logs to file (in case teardown fixture is skipped)
        log_file = "artifacts/test_fuel_depletion_failure_console_logs.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        print(f"Console logs saved to {log_file}")
        raise