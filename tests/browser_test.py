import pytest
from playwright.sync_api import sync_playwright
import time


def test_main_menu_loads():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto("http://localhost:8080/index.html")
        time.sleep(5)  # Wait for Godot HTML5 to fully load (canvas init can be slow)
        assert "SkyLockAssault" in page.title()  # Adjust if title differs
        page.wait_for_selector("text=Start", timeout=30000)  # Increased timeout; check button visible
        page.click("text=Start")
        time.sleep(2)  # Give time for scene transition
        assert "game" in page.url()  # Check for game_level load; adjust if URL changes
        browser.close()
