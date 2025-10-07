import pytest
from playwright.sync_api import sync_playwright
import time


def test_main_menu_loads():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto("http://localhost:8080/index.html")
        page.wait_for_load_state("networkidle", timeout=30000)  # Wait for network idle
        time.sleep(5)  # Buffer for Godot init
        assert "SkyLockAssault" in page.title()  # Title check (adjust if "SkyLockAssault")
        # Change "Start" to inspected text, e.g., "text=Play" or "button"
        page.wait_for_selector("text=Start Game", timeout=30000)
        page.screenshot(path="main_menu.png")  # Debug screenshot (view in Actions artifacts)
        page.click("text=Start Game")
        time.sleep(2)  # Scene transition
        assert "game" in page.url()  # Adjust for your game_level URL pattern
        browser.close()
