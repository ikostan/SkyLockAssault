from playwright.sync_api import sync_playwright, expect


def difficulty_persistence_test(playwright):
    browser = playwright.chromium.launch(headless=True)  # True for CI
    page = browser.new_page()
    logs = []  # New: Collect console logs
    page.on("console", lambda msg: logs.append(msg.text))  # Capture all logs

    # Navigate to itch.io game URL (or local: "http://localhost:8000/index.html")
    page.goto("http://localhost:8080/index.html")

    # Wait for game load (e.g., title or log)
    page.wait_for_timeout(2000)  # Adjust for load time

    # Find canvas for interactions
    canvas = page.locator("canvas")
    box = canvas.bounding_box()  # Get position/size for relative clicks/drags

    # Simulate click on "Options" button (assume position; test manually first)
    # Learning: Use dev tools to find approx % positions (e.g., Options at center-bottom)
    page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)

    # Check initial difficulty via log (after load)
    assert any("Loaded saved difficulty: 1.0" in log for log in logs), "Expected default 1.0 load"

    # Drag slider to 1.5 (assume horizontal slider at mid-screen; drag right 150px)
    slider_x = box['x'] + box['width'] / 2
    slider_y = box['y'] + box['height'] / 2  # Assume mid-y
    page.mouse.move(slider_x, slider_y)
    page.mouse.down()
    # Drag for ~0.5 increase (calibrate range: 0.5-2.0 over ~300px)
    page.mouse.move(slider_x + 150, slider_y)
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

    browser.close()


with sync_playwright() as playwright:
    difficulty_persistence_test(playwright)
