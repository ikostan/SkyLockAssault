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

        await page.wait_for_timeout(2000)  # Adjust for load time

        canvas = page.locator("canvas")
        box = await canvas.bounding_box()  # Get position/size for relative clicks/drags

        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Adjust coords

        assert any("Loaded saved difficulty: 1.0" in log for log in logs), "Expected default 1.0 load"

        slider_x = box['x'] + box['width'] / 2
        slider_y = box['y'] + box['height'] / 2  # Assume mid-y
        await page.mouse.move(slider_x, slider_y)
        await page.mouse.down()
        await page.mouse.move(slider_x + 150, slider_y)  # Drag for ~0.5 increase (calibrate range: 0.5-2.0 over ~300px)
        await page.mouse.up()

        assert any("Difficulty changed to: 1.5" in log for log in logs), "Expected change to 1.5"

        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.9)  # Adjust

        await page.reload()
        await page.wait_for_timeout(2000)
        await page.mouse.click(box['x'] + box['width'] / 2, box['y'] + box['height'] * 0.8)  # Reopen

        assert any("Loaded saved difficulty: 1.5" in log for log in logs), "Expected persisted 1.5"

        await browser.close()
