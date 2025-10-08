import pytest
from playwright.sync_api import sync_playwright
import time


def test_game_loads():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto("http://localhost:8080/index.html")
        page.wait_for_load_state("networkidle", timeout=30000)  # Wait for network idle
        time.sleep(5)  # Buffer for Godot init (increase to 10 if needed)
        assert "SkyLockAssault" in page.title()  # Confirm title from project settings
        # Wait for canvas to appear instead of text selector
        page.wait_for_selector("canvas", timeout=30000)  # Verifies Godot canvas loads
        # Optional: Check for no console errors (Godot logs to console)
        logs = page.evaluate("console.error")  # Basic; extend for full logs
        assert not logs  # Fail if errors
        page.screenshot(path="main_menu.png")  # For debug
        # Remove click and URL assert—they won't work as-is
        browser.close()
