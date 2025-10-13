from playwright.async_api import async_playwright, expect
import pytest


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

        # Wait for game load with function (checks for startup log from _ready)
        await page.wait_for_function("() => document.querySelector('canvas') && console.log.toString().includes('Log "
                                     "level set to')", timeout=10000)  # Adjust if log differs
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
        await page.wait_for_timeout(5000)
        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Reopen

        assert any("Loaded saved difficulty: 1.5" in log for log in logs), "Expected persisted 1.5"

        await browser.close()
