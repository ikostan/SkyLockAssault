from playwright.sync_api import sync_playwright, expect

def test_difficulty_integration(playwright):
    browser = playwright.chromium.launch(headless=True)
    page = browser.new_page()
    logs = []
    page.on("console", lambda msg: logs.append(msg.text))

    page.goto("http://localhost:8080/index.html")
    page.wait_for_timeout(2000)

    canvas = page.locator("canvas")
    box = canvas.bounding_box()

    # Open options, set to 2.0
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Options
    slider_x = box['x'] + box['width'] / 2
    slider_y = box['y'] + box['height'] / 2
    page.mouse.move(slider_x, slider_y)
    page.mouse.down()
    page.mouse.move(slider_x + 200, slider_y)  # To 2.0
    page.mouse.up()
    assert any("Difficulty changed to: 2.0" in log for log in logs), "Change to 2.0 failed"

    # Back, start level
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.9)  # Back
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.7)  # Start

    # Wait for level, simulate fire and idle for fuel
    page.wait_for_timeout(2000)
    page.keyboard.press("Space")
    assert any("Firing with scaled cooldown: 1.0" in log for log in logs), "Weapon scaling failed"

    page.wait_for_timeout(5000)  # ~5 fuel ticks
    fuel_logs = [log for log in logs if "Fuel left:" in log]
    assert len(fuel_logs) > 0, "No fuel logs"
    last_fuel = float(fuel_logs[-1].split("Fuel left: ")[1])
    assert last_fuel < 95.0, f"Fuel scaling failed: got {last_fuel}"

    browser.close()

with sync_playwright() as playwright:
    test_difficulty_integration(playwright)  # For local run; remove for pytest
