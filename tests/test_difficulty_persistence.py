from playwright.sync_api import sync_playwright


def run(playwright):
    browser = playwright.chromium.launch(headless=False)  # Or True for CI
    page = browser.new_page()

    # Navigate to your itch.io game URL
    page.goto("https://ikostan.itch.io/sky-lock-assault")

    # Assume game loads; wait for options button (adapt selectors to your UI)
    page.wait_for_selector("button:text('Options')")  # Use actual selector
    page.click("button:text('Options')")

    # Check initial slider value (assume label shows value)
    initial_value = page.inner_text("#difficulty-label")  # Adapt ID/class
    assert initial_value == "1.0", f"Expected default 1.0, got {initial_value}"

    # Change slider to 1.5 (drag or set value)
    slider = page.locator("#difficulty-slider")
    slider.drag_to(slider, target_position={"x": 150, "y": 0})  # Adjust based on range
    new_value = page.inner_text("#difficulty-label")
    assert new_value == "1.5", f"Expected 1.5 after change, got {new_value}"

    # Close options and reload page to test persistence (user:// in web is localStorage)
    page.click("button:text('Back')")
    page.reload()
    page.click("button:text('Options')")
    reloaded_value = page.inner_text("#difficulty-label")
    assert reloaded_value == "1.5", f"Expected persisted 1.5, got {reloaded_value}"

    browser.close()


with sync_playwright() as playwright:
    run(playwright)
