# tests/difficulty_flow_test.py
"""
Difficulty State Test (Playwright + UI Automation with DOM Overlays)
====================================================================

Overview
--------
Robust E2E test: Sets difficulty=2.0 via UI (click #options-button, set #difficulty-slider), starts game, simulates fire, verifies persistence (cooldown via log).
No coords - DOM overlays for IDs.

Test Flow
---------
- Navigate, wait #options-button.
- Click #options-button, set #difficulty-slider to 2.0, click #back-button.
- Click #start-button, simulate fire (Space), parse cooldown log (0.15*2.0=0.3).
- CDP V8 coverage saved.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with overlays).
- `pip install pytest playwright; playwright install chromium`

Running
-------
pytest -k difficulty_flow_test -q

Artifacts
---------
v8_coverage_difficulty_flow_test.json, artifacts/test_difficulty_failure_*.png/txt
"""

import os
import re
import time
import json
import pytest
from playwright.sync_api import Page, Playwright, TimeoutError


@pytest.fixture(scope="function")
def page(playwright: Playwright) -> Page:
    browser = playwright.chromium.launch(headless=True, args=[
        "--enable-gpu",
        "--ignore-gpu-blocklist",
        "--enable-webgl-draft-extensions",
        "--use-gl=angle",
        "--use-angle=swiftshader-webgl",
        "--use-gl=swiftshader",
        "--use-angle=swiftshader",
        "--mute-audio",
        "--disable-software-rasterizer",
        "--disable-gpu-driver-bug-workarounds",
        "--enable-gpu-rasterization",
        "--force-webgl2-context",
        "--disable-gpu-sandbox",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--enable-unsafe-swiftshader",
        "--disable-gpu-compositing",
        "--enable-3d-apis"
    ])
    context = browser.new_context(
        viewport={"width": 1280, "height": 720},
        record_har_path="artifacts/har.har"  # Optional network trace
    )
    page = context.new_page()
    # CDP for V8 coverage
    cdp_session = None  # Initialize to None outside try
    try:
        cdp_session = context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage",
                         {"callCount": False,
                          "detailed": True})
    except Exception:
        pass
    yield page
    browser.close()


def test_difficulty_flow(page: Page):
    logs = []

    def on_console(msg):
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    cdp_session = None  # Initialize to None outside try
    try:
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send("Profiler.startPreciseCoverage",
                         {"callCount": False,
                          "detailed": True})
    except:
        pass

    try:
        page.goto("http://localhost:8080/index.html", wait_until="networkidle")
        page.wait_for_timeout(5000)  # Extra buffer for HTML5 load

        # Wait main menu (ID check)
        page.wait_for_selector("#options-button", timeout=30000)

        # Click OPTIONS
        page.click("#options-button")

        # After click #options-button
        page.wait_for_selector("#log-lvl-select", timeout=10000)
        page.select_option("#log-lvl-select", value="0")  # Index 0 = DEBUG
        assert any("Log level changed to: DEBUG" in log["text"] for log in logs)

        # Set slider to 2.0 (evaluate to set value, as range in HTML)
        page.wait_for_selector("#difficulty-slider", timeout=10000)
        page.evaluate("document.getElementById('difficulty-slider').value = 2.0")

        # Click BACK
        page.click("#back-button")

        # Click START GAME
        page.click("#start-button")

        # Wait main scene (log check)
        page.wait_for_timeout(3000)
        assert any("Initializing main scene..." in log["text"] for log in logs)

        # Simulate fire (Space)
        page.keyboard.press("Space")
        page.wait_for_timeout(500)  # Log emission

        # Parse cooldown log (0.15 * 2.0 = 0.3)
        cooldown_logs = [log["text"] for log in logs if "Firing with scaled cooldown:" in log["text"]]
        assert cooldown_logs, "No fire cooldown log"
        match = re.search(r"Firing with scaled cooldown:\s*([\d.]+)", cooldown_logs[-1])
        assert match, "Parse failed on: " + cooldown_logs[-1]
        cooldown_value = float(match.group(1))
        print(f"Parsed cooldown: {cooldown_value}")
        assert abs(cooldown_value - 0.3) < 0.01, f"Expected 0.3 (0.15*2.0), got {cooldown_value}"

    except Exception as e:
        os.makedirs("artifacts", exist_ok=True)
        page.screenshot(path=f"artifacts/test_difficulty_failure_{int(time.time())}.png")
        log_file = f"artifacts/test_difficulty_failure_console_logs_{int(time.time())}.txt"
        with open(log_file, "w") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        print(f"Failure logs: {log_file}. Error: {e}")
        raise
    finally:
        if cdp_session:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            with open("v8_coverage_difficulty_flow_test.json", "w") as f:
                json.dump(coverage, f, indent=2)
