import pytest
from playwright.sync_api import Page
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


def test_weapon_firing(page: Page):
    logs: list = []
    try:
        # Set up console log capture
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

        # Set log level to DEBUG
        # Open options menu
        options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
        options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
        page.mouse.click(options_x, options_y)
        page.wait_for_timeout(7000)
        # assert any("Options menu loaded." in log["text"] for log in logs), "Options menu failed to load"

        # Click log level dropdown
        log_dropdown_x = box['x'] + UI_ELEMENTS["log_level_dropdown"]["x"]
        log_dropdown_y = box['y'] + UI_ELEMENTS["log_level_dropdown"]["y"]
        page.mouse.click(log_dropdown_x, log_dropdown_y)
        page.wait_for_timeout(1000)

        # Select DEBUG
        debug_item_x = box['x'] + UI_ELEMENTS["log_level_debug"]["x"]
        debug_item_y = box['y'] + UI_ELEMENTS["log_level_debug"]["y"]
        page.mouse.click(debug_item_x, debug_item_y)
        page.wait_for_timeout(2000)
        assert any("Log level changed to: DEBUG" in log["text"] for log in logs), "Failed to set log level to DEBUG"

        # Back to main menu
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        page.mouse.click(back_x, back_y)
        page.wait_for_timeout(5000)
        assert any("Back button pressed." in log["text"] for log in logs), "Back button failed"

        # Start level (assume click Start)
        start_x = box['x'] + UI_ELEMENTS["start_game_button"]["x"]
        start_y = box['y'] + UI_ELEMENTS["start_game_button"]["y"]
        page.mouse.click(start_x, start_y)  # Click Start button
        page.wait_for_timeout(5000)  # Increased for level load
        assert any("Start Game menu button pressed." in log["text"] for log in logs), "Start Game button not found"

        # Simulate idle time for depletion (fuel_timer is 1s default; wait 5s for ~5 ticks)
        page.wait_for_timeout(10000)

        # Fire one time
        page.keyboard.press("Space")

        # Assert 1 bullet fired (via log count; add "Bullet instantiated" print in weapon.gd _fire if needed)
        bullet_logs = [log["text"] for log in logs if "Firing bullet from weapon global" in log["text"]]
        assert len(bullet_logs) == 1, f"Expected 1 bullet, got {len(bullet_logs)}"
    except Exception as e:
        # Save screenshot
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_weapon_firing_failure_{int(time.time())}.png")
        print(f"Test: Weapon firing test failed: {str(e)}")
        # Save logs to file (in case teardown fixture is skipped)
        log_file = "artifacts/test_weapon_firing_failure_console_logs.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        print(f"Console logs saved to {log_file}")
        raise
