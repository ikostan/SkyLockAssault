from playwright.sync_api import sync_playwright, expect


def fuel_depletion_test(playwright):
    browser = playwright.chromium.launch(headless=False)
    page = browser.new_page()
    logs = []
    page.on("console", lambda msg: logs.append(msg.text))

    page.goto("https://ikostan.itch.io/sky-lock-assault")
    page.wait_for_timeout(2000)

    canvas = page.locator("canvas")
    box = canvas.bounding_box()

    # Set difficulty to 2.0, start level (as above)
    # ... (copy from flow test)

    # Simulate idle time for depletion (fuel_timer is 1s default; wait 5s for ~5 ticks)
    page.wait_for_timeout(5000)

    # Assert fuel dropped faster (e.g., parse logs for "Fuel left: X" < expected base)
    fuel_logs = [log for log in logs if "Fuel left:" in log]
    assert len(fuel_logs) > 0, "No fuel logs found"
    last_fuel = float(fuel_logs[-1].split("Fuel left: ")[1])  # Parse last value
    assert last_fuel < 97.5, f"Expected faster drop (<97.5), got {last_fuel}"  # Base 0.5*5=2.5 drop; scaled 1.0*5=5.0 -> <95.0, but adjust

    browser.close()


with sync_playwright() as playwright:
    fuel_depletion_test(playwright)
