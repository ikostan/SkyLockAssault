# tests/difficulty_flow_test.py
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


def test_difficulty_flow(page_fixture):
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

    # Drag slider to 2.0
    slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_2.0"]["x"]
    slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_2.0"]["y"]
    page.mouse.move(slider_x, slider_y)  # Move to 2.0 position
    page.mouse.down()
    page.mouse.move(slider_x, slider_y)  # Ensure at 2.0 (no drag needed if direct)
    page.mouse.up()
    assert any("Difficulty changed to: 2.0" in log for log in logs), "Expected change to 2.0"

    # Back to main menu
    back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
    back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
    page.mouse.click(back_x, back_y)  # Click Back button

    # Start game
    start_x = box['x'] + UI_ELEMENTS["start_game_button"]["x"]
    start_y = box['y'] + UI_ELEMENTS["start_game_button"]["y"]
    page.mouse.click(start_x, start_y)  # Click Start button

    # Wait for level load, simulate fire (Space)
    page.wait_for_timeout(2000)
    page.keyboard.press("Space")
    assert any("Firing with scaled cooldown: 1.0" in log for log in logs), "Expected doubled cooldown (1.0)"
