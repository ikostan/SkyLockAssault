from playwright.sync_api import sync_playwright


def run(playwright):
    browser = playwright.chromium.launch(headless=False)
    page = browser.new_page()
    page.goto("https://ikostan.itch.io/sky-lock-assault")  # Or local export URL

    # Open options from main menu, set difficulty to 2.0
    page.wait_for_selector("button:text('Options')")
    page.click("button:text('Options')")
    slider = page.locator("#difficulty-slider")  # Add id in scene if needed
    slider.drag_to(slider, target_position={"x": 200, "y": 0})  # To max (2.0)
    page.click("button:text('Back')")

    # Start game, enter level
    page.click("button:text('Start')")
    page.wait_for_selector("#player")  # Assume player element in level

    # Simulate firing (if input mappable) and check cooldown via logs or timing
    # For simplicity: Wait and check if firing feels slower (manual inspect or add debug)
    page.keyboard.press("Space")  # Assume 'fire' action
    print("Inspect browser console for scaled cooldown log >0.5")

    browser.close()


with sync_playwright() as playwright:
    run(playwright)
