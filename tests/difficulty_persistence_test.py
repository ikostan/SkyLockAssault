# tests/difficulty_persistence_test.py
from playwright.async_api import async_playwright, expect
import pytest
import time
import asyncio


@pytest.mark.asyncio
async def test_difficulty_persistence():
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=True)
        page = await browser.new_page()
        logs = []

        async def handle_console(msg):
            try:
                log_text = msg.text  # Changed from msg.text() to msg.text
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
            print(f"Logs captured: {logs}")
            # Fallback: Check canvas interactivity
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

        await page.wait_for_timeout(10000)  # Increased to 10s for CI stability

        canvas = page.locator("canvas")
        box = await canvas.bounding_box()

        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)

        assert any("Loaded saved difficulty: 1.0" in log or "No saved settings found" in log for log in logs), "Expected default load log"

        slider_x = box['x'] + box['width'] / 2
        slider_y = box['y'] + box['height'] / 2
        await page.mouse.move(slider_x, slider_y)
        await page.mouse.down()
        await page.mouse.move(slider_x + 150, slider_y)
        await page.mouse.up()

        assert any("Difficulty changed to: 1.5" in log for log in logs), "Expected change to 1.5"

        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.9)

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

        await page.wait_for_timeout(10000)  # Increased to 10s
        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)

        assert any("Loaded saved difficulty: 1.5" in log for log in logs), "Expected persisted 1.5"

        await browser.close()
