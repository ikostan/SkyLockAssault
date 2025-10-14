from playwright.async_api import async_playwright, expect
import pytest
import time


@pytest.mark.asyncio
async def test_difficulty_persistence():
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(headless=True)
        page = await browser.new_page()
        logs = []  # Collect console logs

        async def handle(msg):
            try:
                logs.append(await msg.text())  # Await text async
            except Exception as exc:
                pass  # Ignore non-text msgs

        page.on("console", handle)

        await page.goto("http://localhost:8080/index.html")

        # Wait for canvas to appear
        await page.wait_for_selector("canvas", timeout=10000)

        # Wait for startup log
        async def wait_for_log_containing(text, timeout=10000):
            start = time.time()
            while time.time() - start < timeout / 1000:
                if any(text in log for log in logs):
                    return
                await asyncio.sleep(0.05)
            raise TimeoutError(f"Timeout {timeout}ms exceeded waiting for log containing '{text}'")

        await wait_for_log_containing("Log level set to")

        await page.wait_for_timeout(5000)  # Increased for CI load (fixes missed log)

        canvas = page.locator("canvas")
        box = await canvas.bounding_box()  # Get position/size for relative clicks/drags

        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Adjust coords

        # Check initial difficulty via log (fallback for no file)
        assert any("Loaded saved difficulty: 1.0" in log or "No saved settings found" in log for log in logs), "Expected default load log"

        slider_x = box['x'] + box['width'] / 2
        slider_y = box['y'] + box['height'] / 2  # Assume mid-y
        await page.mouse.move(slider_x, slider_y)
        await page.mouse.down()
        await page.mouse.move(slider_x + 150, slider_y)  # Drag for ~0.5 increase (calibrate range: 0.5-2.0 over ~300px)
        await page.mouse.up()

        assert any("Difficulty changed to: 1.5" in log for log in logs), "Expected change to 1.5"

        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.9)  # Adjust

        await page.reload()

        # Wait for canvas after reload
        await page.wait_for_selector("canvas", timeout=10000)

        # Wait for startup log after reload
        await wait_for_log_containing("Log level set to")

        await page.wait_for_timeout(5000)
        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Reopen

        assert any("Loaded saved difficulty: 1.5" in log for log in logs), "Expected persisted 1.5"

        await browser.close()
