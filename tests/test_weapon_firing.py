from playwright.sync_api import sync_playwright, expect
import pytest


@pytest.fixture(scope="function")
def page_fixture():
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page()
        yield page
        browser.close()


def test_weapon_firing(page_fixture):
    page = page_fixture
    logs = []
    page.on("console", lambda msg: logs.append(msg.text))

    page.goto("http://localhost:8080/index.html")
    page.wait_for_timeout(2000)

    canvas = page.locator("canvas")
    box = canvas.bounding_box()

    # Start level (assume click Start)
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.7)  # Start

    # Wait for level, simulate fire
    page.wait_for_timeout(2000)
    page.keyboard.press("Space")

    # Assert 1 bullet fired (via log count; add "Bullet instantiated" print in weapon.gd _fire if needed)
    bullet_logs = [log for log in logs if "Bullet velocity:" in log]
    assert len(bullet_logs) == 1, f"Expected 1 bullet, got {len(bullet_logs)}"

    # Assert velocity
    velocity = float(bullet_logs[0].split("Bullet velocity:")[1].strip())
    assert abs(velocity + 400.0) < 10.0, f"Expected ~ -400.0, got {velocity}"
