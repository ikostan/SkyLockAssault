from playwright.sync_api import sync_playwright, expect
import pytest


@pytest.fixture(scope="function")
def page_fixture():
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page()
        yield page
        browser.close()


def test_difficulty_persistence(page_fixture):
    page = page_fixture
    logs = []  # Collect console logs
    page.on("console", lambda msg: logs.append(msg.text))  # Capture all logs

    # Navigate to local export URL (CI uses http://localhost:8080/index.html)
    page.goto("http://localhost:8080/index.html")

    # Wait for game load (e.g., title or log)
    page.wait_for_timeout(2000)  # Adjust for load time

    # Find canvas for interactions
    canvas = page.locator("canvas")
    box = canvas.bounding_box()  # Get position/size for relative clicks/drags

    # Simulate click on "Options" button (assume position; test manually first)
    # Learning: Use dev tools to find approx % positions (e.g., Options at center-bottom)
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Adjust coords

    # Check initial difficulty via log (after load)
    assert any("Loaded saved difficulty: 1.0" in log for log in logs), "Expected default 1.0 load"

    # Drag slider to 1.5 (assume horizontal slider at mid-screen; drag right 150px)
    slider_x = box['x'] + box['width'] / 2
    slider_y = box['y'] + box['height'] / 2  # Assume mid-y
    page.mouse.move(slider_x, slider_y)
    page.mouse.down()
    page.mouse.move(slider_x + 150, slider_y)  # Drag for ~0.5 increase (calibrate range: 0.5-2.0 over ~300px)
    page.mouse.up()

    # Assert change via log
    assert any("Difficulty changed to: 1.5" in log for log in logs), "Expected change to 1.5"

    # Close options (click "Back" position)
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.9)  # Adjust

    # Reload and reopen options
    page.reload()
    page.wait_for_timeout(2000)
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Reopen

    # Assert persistence via log
    assert any("Loaded saved difficulty: 1.5" in log for log in logs), "Expected persisted 1.5"
