# tests/difficulty_integration_test.py
from playwright.sync_api import sync_playwright, expect
import pytest
from ui_elements_coords import UI_ELEMENTS  # Import the coordinates dictionary


@pytest.fixture(scope="function")
def page_fixture():
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page()
        yield page
        browser.close()


def test_difficulty_integration(page_fixture):
    page = page_fixture
    logs = []
    page.on("console", lambda msg: logs.append(msg.text))

    page.goto("http://localhost:8080/index.html")
    page.wait_for_timeout(2000)

    canvas = page.locator("canvas")
    box = canvas.bounding_box()

    # Open options
    options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
    options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
    page.mouse.click(options_x, options_y)  # Click Options button

    # Set difficulty to 2.0 (direct click to slider_2.0 position)
    slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_2.0"]["x"]
    slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_2.0"]["y"]
    page.mouse.move(slider_x, slider_y)  # Move to 2.0 position
    page.mouse.click(slider_x, slider_y)  # Click to set 2.0
    assert any("Difficulty changed to: 2.0" in log for log in logs), "Change to 2.0 failed"

    # Back to main menu
    back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
    back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
    page.mouse.click(back_x, back_y)  # Click Back button

    # Start level
    start_x = box['x'] + UI_ELEMENTS["start_game_button"]["x"]
    start_y = box['y'] + UI_ELEMENTS["start_game_button"]["y"]
    page.mouse.click(start_x, start_y)  # Click Start button

    # Wait for level load, simulate fire and idle for fuel
    page.wait_for_timeout(2000)
    page.keyboard.press("Space")
    assert any("Firing with scaled cooldown: 1.0" in log for log in logs), "Weapon scaling failed"

    page.wait_for_timeout(5000)  # ~5 fuel ticks
    fuel_logs = [log for log in logs if "Fuel left:" in log]
    assert len(fuel_logs) > 0, "No fuel logs"
    last_fuel = float(fuel_logs[-1].split("Fuel left: ")[1])
    assert last_fuel < 95.0, f"Fuel scaling failed: got {last_fuel}"
