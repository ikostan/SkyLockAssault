import pytest
from playwright.sync_api import Page, expect, Browser
from ui_elements_coords import UI_ELEMENTS  # Import the coordinates dictionary


@pytest.fixture(scope="function")
def page(playwright: "playwright") -> Page:
    browser = playwright.chromium.launch(
        headless=True,
        args=["--enable-unsafe-swiftshader", "--disable-gpu", "--use-gl=swiftshader"]
    )
    context = browser.new_context(viewport={"width": 1280, "height": 720})
    page = context.new_page()
    yield page
    page.close()
    context.close()
    browser.close()


def test_difficulty_integration(page: Page):
    # Set up console log capture
    logs = []
    page.on("console", lambda msg: logs.append({"type": msg.type, "text": msg.text}))

    # Navigate to game and wait for load
    page.goto("http://localhost:8080/index.html")
    page.wait_for_timeout(10000)  # Increased significantly for WASM/scene init

    # Verify canvas and title
    canvas = page.locator("canvas")
    page.wait_for_selector("canvas", state="visible", timeout=7000)
    box = canvas.bounding_box()
    assert box, "Canvas not found on page"
    assert "SkyLockAssault" in page.title(), "Title not found"

    # Open options
    options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
    options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
    page.mouse.click(options_x, options_y)  # Click Options button
    page.wait_for_timeout(7000)  # Wait for options menu to load
    assert any("Options button pressed." in log["text"] for log in logs), "Options menu not found"
    assert any("Options menu loaded." in log["text"] for log in logs), "Options menu is not loaded"

    # Set difficulty to 2.0 (direct click to slider_2.0 position)
    slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_2.0"]["x"]
    slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_2.0"]["y"]
    page.mouse.click(slider_x, slider_y)  # Click to set 2.0
    page.wait_for_timeout(5000)
    assert any("Difficulty changed to: 2.0" in log["text"] for log in logs), "Change to 2.0 failed"

    # Back to main menu
    back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
    back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
    page.mouse.click(back_x, back_y)  # Click Back button
    page.wait_for_timeout(5000)
    assert any("Back button pressed." in log["text"] for log in logs), "Back button not found"

    # Start level
    start_x = box['x'] + UI_ELEMENTS["start_game_button"]["x"]
    start_y = box['y'] + UI_ELEMENTS["start_game_button"]["y"]
    page.mouse.click(start_x, start_y)  # Click Start button
    page.wait_for_timeout(10000)  # Increased for level load
    assert any("Start Game menu button pressed." in log["text"] for log in logs), "Start GAme button not found"

    # Simulate fire and idle for fuel
    page.keyboard.press("Space")
    page.wait_for_timeout(5000)
    assert any("Firing with scaled cooldown: 1.0" in log["text"] for log in logs), "Weapon scaling failed"

    page.wait_for_timeout(7000)
    fuel_logs = [log for log in logs if "Fuel left:" in log["text"]]
    assert len(fuel_logs) > 0, "No fuel logs"

    last_fuel = float(fuel_logs[-1]["text"].split("Fuel left: ")[1])
    assert last_fuel < 80.0, f"Fuel scaling failed: got {last_fuel}"
