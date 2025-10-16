from playwright.async_api import async_playwright, expect
import pytest
import time
import asyncio


@pytest.mark.asyncio
async def test_difficulty_persistence():
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=True)
        page = await browser.new_page()
        logs = []  # Collect console logs

        async def handle(msg):
            try:
                log_text = await msg.text()
                logs.append(log_text)
                print(f"Console log: {log_text}")  # Debug: Print all logs
            except Exception:
                pass  # Ignore non-text messages

        page.on("console", handle)

        # Navigate to game
        try:
            await page.goto("http://localhost:8080/index.html", timeout=30000)
        except Exception as e:
            print(f"Failed to load page: {e}")
            raise

        # Wait for canvas to appear
        try:
            await page.wait_for_selector("canvas", timeout=15000)
        except Exception as e:
            print(f"Canvas not found: {e}")
            raise

        # Wait for startup log with increased timeout
        async def wait_for_log_containing(text, timeout=20000):
            start = time.time()
            while time.time() - start < timeout / 1000:
                if any(text in log for log in logs):
                    print(f"Found log: {text}")
                    return
                await asyncio.sleep(0.1)  # Slightly longer sleep for CI
            print(f"Logs captured: {logs}")  # Debug: Show all logs on timeout
            raise TimeoutError(f"Timeout {timeout}ms exceeded waiting for log containing '{text}'")

        await wait_for_log_containing("Log level set to")

        await page.wait_for_timeout(5000)  # Wait for UI stabilization

        canvas = page.locator("canvas")
        box = await canvas.bounding_box()  # Get position/size

        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)

        # Check initial difficulty
        assert any("Loaded saved difficulty: 1.0" in log or "No saved settings found" in log for log in logs), "Expected default load log"

        slider_x = box['x'] + box['width'] / 2
        slider_y = box['y'] + box['height'] / 2
        await page.mouse.move(slider_x, slider_y)
        await page.mouse.down()
        await page.mouse.move(slider_x + 150, slider_y)  # Drag for ~0.5 increase
        await page.mouse.up()

        assert any("Difficulty changed to: 1.5" in log for log in logs), "Expected change to 1.5"

        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.9)

        await page.reload()

        # Wait for canvas after reload
        await page.wait_for_selector("canvas", timeout=15000)

        # Wait for startup log after reload
        await wait_for_log_containing("Log level set to")

        await page.wait_for_timeout(5000)
        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)

        assert any("Loaded saved difficulty: 1.5" in log for log in logs), "Expected persisted 1.5"

        await browser.close()
