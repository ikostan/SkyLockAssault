# tests/difficulty_integration_test.py
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


def test_difficulty_integration(page: Page):
    logs: list = []
    try:
        # Set up console log capture
        page.on("console", lambda msg: logs.append({"type": msg.type, "text": msg.text}))

        # Navigate to game and wait for load
        page.goto("http://localhost:8080/index.html")
        page.wait_for_timeout(10000)  # Increased significantly for WASM/scene init

        # Verify canvas and title
        canvas = page.locator("canvas")
        page.wait_for_selector("canvas", state="visible", timeout=7000)
        box = canvas.bounding_box()
        assert box, "Canvas not found on page"
        assert "SkyLockAssault" in page.title(), "Title not found"

        # Set log level to DEBUG
        # Open options menu
        options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
        options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
        page.mouse.click(options_x, options_y)
        page.wait_for_timeout(2000)
        # assert any("Options menu loaded." in log["text"] for log in logs), "Options menu failed to load"

        # Click log level dropdown
        log_dropdown_x = box['x'] + UI_ELEMENTS["log_level_dropdown"]["x"]
        log_dropdown_y = box['y'] + UI_ELEMENTS["log_level_dropdown"]["y"]
        page.mouse.click(log_dropdown_x, log_dropdown_y)
        page.wait_for_timeout(2000)

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
        page.wait_for_timeout(2000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button failed"

        # Open options
        options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
        options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
        page.mouse.click(options_x, options_y)  # Click Options button
        page.wait_for_timeout(2000)  # Wait for options menu to load
        assert any("Options button pressed." in log["text"] for log in logs), "Options menu not found"
        assert any("Options menu loaded." in log["text"] for log in logs), "Options menu is not loaded"

        # Set difficulty to 2.0 (direct click to slider_2.0 position)
        slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_2.0"]["x"]
        slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_2.0"]["y"]
        page.mouse.click(slider_x, slider_y)  # Click to set 2.0
        page.wait_for_timeout(2000)
        assert any("Difficulty changed to: 2.0" in log["text"] for log in logs), "Change to 2.0 failed"

        # Back to main menu
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        page.mouse.click(back_x, back_y)  # Click Back button
        page.wait_for_timeout(2000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

        # Start level
        start_x = box['x'] + UI_ELEMENTS["start_game_button"]["x"]
        start_y = box['y'] + UI_ELEMENTS["start_game_button"]["y"]
        page.mouse.click(start_x, start_y)  # Click Start button
        page.wait_for_timeout(2000)  # Increased for level load
        assert any("Start Game menu button pressed." in log["text"] for log in logs), "Start Game button not found"

        # Simulate fire and idle for fuel
        page.keyboard.press("Space")
        page.wait_for_timeout(5000)
        assert any("Firing with scaled cooldown: 1.0" in log["text"] for log in logs), "Weapon scaling failed"

        page.wait_for_timeout(10000)
        fuel_logs = [log for log in logs if "Fuel left:" in log["text"]]
        assert len(fuel_logs) > 0, "No fuel logs"

        last_fuel = float(fuel_logs[-1]["text"].split("Fuel left: ")[1])
        assert last_fuel < 85.0, f"Fuel scaling failed: got {last_fuel}"
    except Exception as e:
        # Save screenshot
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_difficulty_integration_failure_{int(time.time())}.png")
        print(f"Test: Difficulty integration test failed: {str(e)}")
        # Save logs to file (in case teardown fixture is skipped)
        log_file = "artifacts/test_difficulty_integration_failure_console_logs.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        print(f"Console logs saved to {log_file}")
        raise
