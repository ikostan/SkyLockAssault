from playwright.sync_api import sync_playwright, expect
import pytest


@pytest.fixture(scope="function")
def page_fixture():
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page()
        yield page
        browser.close()


def test_weapon_isolation(page_fixture):
    page = page_fixture
    logs = []
    page.on("console", lambda msg: logs.append(msg.text))

    page.goto("http://localhost:8080/index.html")
    page.wait_for_timeout(2000)

    canvas = page.locator("canvas")
    box = canvas.bounding_box()

    # Start level
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.7)  # Start

    # Wait for level, simulate single fire
    page.wait_for_timeout(2000)
    page.keyboard.press("Space")

    # Assert 1 fire (via log count)
    fire_logs = [log for log in logs if "Fire called" in log]
    assert len(fire_logs) == 1, f"Expected 1 fire, got {len(fire_logs)}"
