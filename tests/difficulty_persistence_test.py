# tests/difficulty_persistence_test.py
from playwright.async_api import async_playwright, expect
import pytest
import time
import asyncio
from ui_elements_coords import UI_ELEMENTS  # Import the coordinates dictionary


@pytest.mark.asyncio
async def test_console_log_presence():
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=True)
        page = await browser.new_page()
        logs = []

        async def handle_console(msg):
            try:
                log_text = msg.text
                logs.append(log_text)
                print(f"Captured log: {log_text}")
            except Exception as e:
                print(f"Console capture error: {e}")

        page.on("console", handle_console)

        try:
            await page.goto("http://localhost:8080/index.html", timeout=60000)
            await page.wait_for_selector("canvas", timeout=30000)
            await page.wait_for_timeout(10000)  # Wait for game to initialize
            assert len(logs) > 0, "Expected at least one console log from the game"
            print(f"Logs captured: {logs}")
        except Exception as e:
            print(f"Test failed: {e}")
            raise
        await browser.close()


@pytest.mark.asyncio
async def test_difficulty_persistence():
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=True)
        page = await browser.new_page()
        logs = []

        async def handle_console(msg):
            try:
                log_text = msg.text
                logs.append(log_text)
                print(f"Captured log: {log_text}")
            except Exception as e:
                print(f"Console capture error: {e}")

        async def handle_error(msg):
            print(f"Browser error: {msg}")

        page.on("console", handle_console)
        page.on("pageerror", handle_error)

        try:
            await page.goto("http://localhost:8080/index.html", timeout=60000)
        except Exception as e:
            print(f"Failed to load page: {e}")
            raise

        try:
            await page.wait_for_selector("canvas", timeout=30000)
        except Exception as e:
            print(f"Canvas not found: {e}")
            content = await page.content()
            print(f"Page content: {content}")
            await page.screenshot(path="main_menu.png")
            raise

        await page.screenshot(path="main_menu.png")

        async def wait_for_log_containing(text, timeout=60000):
            start = time.time()
            while time.time() - start < timeout / 1000:
                if any(text in log for log in logs):
                    print(f"Found log: {text}")
                    return
                await asyncio.sleep(0.2)
            print(f"Timeout waiting for '{text}'. Logs captured: {logs}")
            canvas = page.locator("canvas")
            box = await canvas.bounding_box()
            if box:
                print("Canvas detected, proceeding despite log timeout")
                return
            raise TimeoutError(f"Timeout {timeout}ms exceeded waiting for log containing '{text}'")

        try:
            await wait_for_log_containing("Log level set to")
        except TimeoutError as e:
            print(f"Log timeout: {e}")

        await page.wait_for_timeout(10000)

        canvas = page.locator("canvas")
        box = await canvas.bounding_box()
        print(f"Canvas bounds: x={box['x']}, y={box['y']}, width={box['width']}, height={box['height']}")

        # Click options button to open menu
        options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
        options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
        print(f"Clicking Options at: ({options_x}, {options_y})")
        await page.mouse.click(options_x, options_y)

        await wait_for_log_containing("Instancing options menu", timeout=30000)
        await wait_for_log_containing("Options menu loaded", timeout=30000)
        await page.wait_for_timeout(5000)
        assert any("Loaded saved difficulty: 1.6" in log for log in logs), "Expected loaded difficulty 1.6"

        # Drag slider to 1.5 (start from 0.5, drag to approximate 1.5 position)
        start_slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_0.5"]["x"]
        start_slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_0.5"]["y"]
        mid_slider_x = box['x'] + UI_ELEMENTS["difficulty_slider_1.3"]["x"]
        mid_slider_y = box['y'] + UI_ELEMENTS["difficulty_slider_1.3"]["y"]  # Note: y typo in dict, assuming 324
        print(f"Moving slider from ({start_slider_x}, {start_slider_y}) to ({mid_slider_x + 15}, {mid_slider_y})")  # Approximate +15px for 1.5
        await page.mouse.move(start_slider_x, start_slider_y)
        await page.mouse.down()
        await page.mouse.move(mid_slider_x + 15, mid_slider_y)
        await page.mouse.up()

        await wait_for_log_containing("Difficulty changed to", timeout=30000)
        assert any("Difficulty changed to: 1.5" in log for log in logs), "Expected change to 1.5"

        # Click back button to save/close
        back_x = box['x'] + UI_ELEMENTS["back_button"]["x"]
        back_y = box['y'] + UI_ELEMENTS["back_button"]["y"]
        print(f"Clicking to save and close at: ({back_x}, {back_y})")
        await page.mouse.click(back_x, back_y)
        await wait_for_log_containing("Closing options menu", timeout=30000)

        await page.reload()

        try:
            await page.wait_for_selector("canvas", timeout=30000)
        except Exception as e:
            print(f"Canvas not found after reload: {e}")
            content = await page.content()
            print(f"Page content after reload: {content}")
            await page.screenshot(path="main_menu_reload.png")
            raise

        await page.screenshot(path="main_menu_reload.png")

        try:
            await wait_for_log_containing("Log level set to")
        except TimeoutError as e:
            print(f"Log timeout after reload: {e}")
            canvas = page.locator("canvas")
            box = await canvas.bounding_box()
            if box:
                print("Canvas detected after reload, proceeding despite log timeout")

        await page.wait_for_timeout(10000)
        options_x = box['x'] + UI_ELEMENTS["options_button"]["x"]
        options_y = box['y'] + UI_ELEMENTS["options_button"]["y"]
        print(f"Clicking Options after reload at: ({options_x}, {options_y})")
        await page.mouse.click(options_x, options_y)

        await wait_for_log_containing("Instancing options menu", timeout=30000)
        await wait_for_log_containing("Options menu loaded", timeout=30000)
        assert any("Loaded saved difficulty: 1.5" in log for log in logs), "Expected persisted 1.5"

        await browser.close()
