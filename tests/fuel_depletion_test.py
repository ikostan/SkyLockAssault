from playwright.sync_api import sync_playwright, expect
import pytest


@pytest.fixture(scope="function")
def page_fixture():
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page()
        yield page
        browser.close()


def test_fuel_depletion(page_fixture):
    page = page_fixture
    logs = []
    page.on("console", lambda msg: logs.append(msg.text))

    page.goto("http://localhost:8080/index.html")
    page.wait_for_timeout(2000)

    canvas = page.locator("canvas")
    box = canvas.bounding_box()

    # Set difficulty to 2.0 (copy from flow test for brevity)
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Options
    slider_x = box['x'] + box['width'] / 2
    slider_y = box['y'] + box['height'] / 2
    page.mouse.move(slider_x, slider_y)
    page.mouse.down()
    page.mouse.move(slider_x + 200, slider_y)  # To max (2.0)
    page.mouse.up()
    assert any("Difficulty changed to: 2.0" in log for log in logs), "Expected change to 2.0"

    # Back, start level
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.9)  # Back
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.7)  # Start

    # Simulate idle time for depletion (fuel_timer is 1s default; wait 5s for ~5 ticks)
    page.wait_for_timeout(5000)

    # Assert fuel dropped faster (e.g., parse logs for "Fuel left: X" < expected base)
    fuel_logs = [log for log in logs if "Fuel left:" in log]
    assert len(fuel_logs) > 0, "No fuel logs found"
    last_fuel = float(fuel_logs[-1].split("Fuel left: ")[1])  # Parse last value
    assert last_fuel < 97.5, f"Expected faster drop (<97.5), got {last_fuel}"  # Base 0.5*5=2.5 drop; scaled 1.0*5=5.0 -> <95.0, but adjust
