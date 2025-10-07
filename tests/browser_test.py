import pytest
from playwright.sync_api import sync_playwright
import subprocess
import time
import os


@pytest.fixture(scope="module")
def browser_server():
    # Export Godot to HTML5 (run once manually or automate)
    os.system('godot --headless --export-release "HTML5" build/index.html')  # Use your project.godot path if needed

    # Start simple Python server
    server = subprocess.Popen(["python", "-m", "http.server", "8080", "--directory", "build"])
    time.sleep(2)  # Wait for server start
    yield
    server.kill()  # Cleanup


def test_main_menu_loads(browser_server):
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto("http://localhost:8080/index.html")
        assert page.title() == "SkyLockAssault"  # Adjust for your game's title
        page.wait_for_selector("text=Start Game", timeout=10000)  # Check button visible
        page.click("text=Start Game")
        assert "game_level" in page.url()  # Check navigation; tweak for your scenes
        browser.close()
