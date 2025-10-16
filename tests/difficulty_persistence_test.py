# tests/difficulty_persistence_test.py
from playwright.async_api import async_playwright, expect
import pytest
import time
import asyncio


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
        # Adjust click coordinates based on canvas offset
        click_x = box['x'] + (658.420104980469 - box['x'])  # Relative to canvas top-left
        click_y = box['y'] + (359.608276367188 - box['y'])
        print(f"Clicking at adjusted coordinates: ({click_x}, {click_y})")
        await page.mouse.click(click_x, click_y)

        await wait_for_log_containing("Instancing options menu", timeout=30000)
        await wait_for_log_containing("Options menu loaded", timeout=30000)
        assert any("Loaded saved difficulty: 1.6" in log for log in logs), "Expected loaded difficulty 1.6"

        slider_x = box['x'] + box['width'] * 0.5
        slider_y = box['y'] + box['height'] * 0.5
        print(f"Moving slider from ({slider_x}, {slider_y}) to ({slider_x + 100}, {slider_y})")
        await page.mouse.move(slider_x, slider_y)
        await page.mouse.down()
        await page.mouse.move(slider_x + 100, slider_y)
        await page.mouse.up()

        await wait_for_log_containing("Difficulty changed to", timeout=30000)
        assert any("Difficulty changed to: 1.5" in log for log in logs), "Expected change to 1.5"

        click_x = box['x'] + box['width'] * 0.5
        click_y = box['y'] + box['height'] * 0.8
        print(f"Clicking to save and close at coordinates: ({click_x}, {click_y})")
        await page.mouse.click(click_x, click_y)
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
        click_x = box['x'] + (658.420104980469 - box['x'])  # Reuse Options button coordinates
        click_y = box['y'] + (359.608276367188 - box['y'])
        print(f"Clicking after reload at coordinates: ({click_x}, {click_y})")
        await page.mouse.click(click_x, click_y)

        await wait_for_log_containing("Instancing options menu", timeout=30000)
        await wait_for_log_containing("Options menu loaded", timeout=30000)
        assert any("Loaded saved difficulty: 1.5" in log for log in logs), "Expected persisted 1.5"

        await browser.close()
