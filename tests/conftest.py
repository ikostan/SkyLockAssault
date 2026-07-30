# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/conftest.py
"""
Shared pytest fixtures and configs for SkyLockAssault E2E tests.
"""

import os
import re
import subprocess
from pathlib import Path
from typing import Generator

import pytest
from playwright.sync_api import Browser, BrowserContext, Page, Playwright

# Storage for test lifecycle memory metrics
_LIFECYCLE_METRICS = []


@pytest.fixture(autouse=True)
def capture_lifecycle_metrics(request):
    """Captures browser JS heap memory metrics after each test execution."""
    yield
    # Sample page memory if shared_page or page fixture was used
    page_fixture = None
    if "shared_page" in request.fixturenames:
        page_fixture = "shared_page"
    elif "page" in request.fixturenames:
        page_fixture = "page"

    if page_fixture:
        try:
            page = request.getfixturevalue(page_fixture)
            heap_info = page.evaluate("""() => {
                if (window.performance && window.performance.memory) {
                    return {
                        usedJSHeapMB: (performance.memory.usedJSHeapSize / (1024 * 1024)).toFixed(2),
                        totalJSHeapMB: (performance.memory.totalJSHeapSize / (1024 * 1024)).toFixed(2),
                        jsHeapLimitMB: (performance.memory.jsHeapSizeLimit / (1024 * 1024)).toFixed(2)
                    };
                }
                return null;
            }""")

            if heap_info:
                _LIFECYCLE_METRICS.append({
                    "test": request.node.name,
                    "used_heap_mb": heap_info["usedJSHeapMB"],
                    "total_heap_mb": heap_info["totalJSHeapMB"],
                    "limit_mb": heap_info["jsHeapLimitMB"],
                })
        except Exception:
            pass


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    """Outputs a browser memory & process lifecycle report at the end of the test suite."""
    if _LIFECYCLE_METRICS:
        terminalreporter.ensure_newline()
        terminalreporter.section("Browser Lifecycle & Memory Metrics (#773)", sep="=", bold=True)
        for entry in _LIFECYCLE_METRICS:
            terminalreporter.write_line(
                f"  • {entry['test']:<45} | JS Heap: {entry['used_heap_mb']:>6} MB / {entry['total_heap_mb']:>6} MB (Limit: {entry['limit_mb']} MB)"
            )
        terminalreporter.ensure_newline()


def pytest_sessionfinish(session, exitstatus):
    """Guarantees browser and HTTP server sub-processes are terminated when PyCharm finishes testing."""
    # 1. Clean up orphaned python HTTP server sub-processes
    try:
        if os.name == "nt":  # Windows
            subprocess.run(
                [
                    "taskkill",
                    "/F",
                    "/IM",
                    "python.exe",
                    "/FI",
                    "WINDOWTITLE eq http.server*",
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:  # Linux / WSL2
            subprocess.run(["pkill", "-f", "http.server"], check=False)
    except Exception:
        pass

    # 2. Force terminate lingering Playwright Chromium driver instances
    try:
        if os.name == "nt":
            subprocess.run(
                ["taskkill", "/F", "/IM", "chrome.exe", "/T"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        else:
            subprocess.run(["pkill", "-f", "chromium"], check=False)
    except Exception:
        pass


@pytest.fixture(scope="module")
def shared_page(browser: Browser) -> Page:
    """Module-scoped page fixture. Boots Godot WASM once per module."""
    context = browser.new_context(viewport={"width": 1280, "height": 720})
    page = context.new_page()

    # 1. Neutralize native JS alert/confirm dialogs so they never freeze CDP
    page.add_init_script("""
        window.alert = (msg) => console.log('[STUBBED ALERT]: ' + msg);
        window.confirm = (msg) => { console.log('[STUBBED CONFIRM]: ' + msg); return true; };
    """)
    page.on("dialog", lambda dialog: dialog.dismiss())

    # 2. Load shell using domcontentloaded
    page.goto("http://localhost:8080/index.html", wait_until="domcontentloaded")

    # 3. Wait deterministically for Godot engine boot flag
    page.wait_for_function("() => window.godotInitialized === true", timeout=30000)

    yield page

    # Teardown: Explicitly lose WebGL context to free GPU memory before closing
    try:
        page.evaluate("""() => {
            const canvas = document.getElementById('canvas');
            if (canvas) {
                const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
                if (gl) {
                    const loseContext = gl.getExtension('WEBGL_lose_context');
                    if (loseContext) loseContext.loseContext();
                }
            }
        }""")
    except Exception:
        pass

    page.close()
    context.close()


@pytest.fixture(autouse=True)
def soft_ui_reset(request):
    """Executes a lightweight UI state reset between tests using existing window hooks."""
    yield
    if "shared_page" in request.fixturenames:
        page = request.getfixturevalue("shared_page")
        try:
            page.evaluate("""() => {
                localStorage.clear();
                sessionStorage.clear();
                if (typeof window.audioBackPressed === 'function') window.audioBackPressed([]);
                if (typeof window.controlsBackPressed === 'function') window.controlsBackPressed([]);
                if (typeof window.gameplayBackPressed === 'function') window.gameplayBackPressed([]);
                if (typeof window.advancedBackPressed === 'function') window.advancedBackPressed([]);
                if (typeof window.optionsBackPressed === 'function') window.optionsBackPressed([]);
            }""")
        except Exception:
            pass


@pytest.fixture(scope="session")
def browser_instance(playwright: Playwright) -> Generator[Browser, None, None]:
    """
    Session-scoped Chromium launch fixture to minimize startup
    overhead across the test suite.
    """
    browser = playwright.chromium.launch(
        headless=True,
        args=[
            "--enable-unsafe-swiftshader",
            "--disable-gpu",
            "--use-gl=swiftshader",
        ],
    )
    yield browser
    browser.close()


@pytest.fixture(scope="function")
def page(
    browser_instance: Browser, request: pytest.FixtureRequest
) -> Generator[Page, None, None]:
    """
    Function-scoped page fixture providing clean browser context
    isolation for each test.
    """
    har_path = None
    if request.node.get_closest_marker("record_har"):
        nodeid = request.node.nodeid
        safe_nodeid = re.sub(r"[^A-Za-z0-9._-]+", "_", nodeid)
        artifacts_dir = Path("artifacts")
        artifacts_dir.mkdir(parents=True, exist_ok=True)
        har_path = artifacts_dir / f"{safe_nodeid}.har"

    context: BrowserContext = browser_instance.new_context(
        viewport={"width": 1280, "height": 720},
        record_har_path=str(har_path) if har_path else None,
    )
    page: Page = context.new_page()
    yield page
    context.close()


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line(
        "markers",
        "record_har: Mark tests that should record HAR files "
        "for network tracing in Playwright.",
    )
