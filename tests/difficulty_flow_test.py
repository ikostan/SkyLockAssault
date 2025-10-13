from playwright.sync_api import sync_playwright, expect
import pytest


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

    # Open options, drag slider to 2.0 (full right drag ~200px)
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Options
    slider_x = box['x'] + box['width'] / 2
    slider_y = box['y'] + box['height'] / 2
    page.mouse.move(slider_x, slider_y)
    page.mouse.down()
    page.mouse.move(slider_x + 200, slider_y)  # To max (2.0)
    page.mouse.up()
    assert any("Difficulty changed to: 2.0" in log for log in logs), "Expected change to 2.0"

    # Back, start game
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.9)  # Back
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.7)  # Start (adjust pos)

    # Wait for level load, simulate fire (Space)
    page.wait_for_timeout(2000)
    page.keyboard.press("Space")
    assert any("Firing with scaled cooldown: 1.0" in log for log in logs), "Expected doubled cooldown (1.0)"
