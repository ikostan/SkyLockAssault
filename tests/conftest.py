# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/conftest.py
"""Shared pytest fixtures and configs for SkyLockAssault E2E tests."""

import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Generator

import pytest
from playwright.sync_api import Browser, BrowserContext, Page, Playwright

from tests.test_utils import init_page_and_wait_ready

# Storage for test lifecycle memory metrics
_LIFECYCLE_METRICS = []

# Storage for test-spawned PIDs if managed via pytest
_TRACKED_PIDS: set[int] = set()


def track_process_pid(pid: int) -> None:
    """Track sub-process PIDs spawned during test execution."""
    if pid:
        _TRACKED_PIDS.add(pid)


def pytest_sessionfinish(session, exitstatus):
    """Safely terminates only the sub-processes tracked during this test run."""
    _ = (session, exitstatus)
    for pid in list(_TRACKED_PIDS):
        try:
            if os.name == "nt":
                cmd = shutil.which("taskkill") or "C:\\Windows\\System32\\taskkill.exe"
                subprocess.run(
                    [cmd, "/F", "/PID", str(pid)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                )
            else:
                os.kill(pid, 9)
        except ProcessLookupError:
            pass
        except Exception:
            pass
    _TRACKED_PIDS.clear()


@pytest.fixture(autouse=True)
def capture_lifecycle_metrics(request):
    """Captures browser JS heap memory metrics after test execution."""
    page_fixture = None
    if "shared_page" in request.fixturenames:
        page_fixture = "shared_page"
    elif "page" in request.fixturenames:
        page_fixture = "page"

    # Fetch fixture during setup to guarantee teardown runs BEFORE page is closed
    page = request.getfixturevalue(page_fixture) if page_fixture else None
    yield

    if page is not None:
        try:
            heap_script = (
                "() => {\n"
                "  if (window.performance && window.performance.memory) {\n"
                "    const mem = window.performance.memory;\n"
                "    return {\n"
                "      used: (mem.usedJSHeapSize / 1048576).toFixed(2),\n"
                "      total: (mem.totalJSHeapSize / 1048576).toFixed(2),\n"
                "      limit: (mem.jsHeapSizeLimit / 1048576).toFixed(2)\n"
                "    };\n"
                "  }\n"
                "  return null;\n"
                "}"
            )
            heap_info = page.evaluate(heap_script)

            if heap_info:
                _LIFECYCLE_METRICS.append(
                    {
                        "test": request.node.name,
                        "used_heap_mb": heap_info["used"],
                        "total_heap_mb": heap_info["total"],
                        "limit_mb": heap_info["limit"],
                    }
                )
        except Exception as exc:  # noqa: BLE001 - metrics are best-effort
            print(f"Warning: heap metric capture failed: {exc}")


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    """Outputs browser memory & lifecycle report at suite end."""
    _ = (exitstatus, config)
    if _LIFECYCLE_METRICS:
        terminalreporter.ensure_newline()
        terminalreporter.section(
            "Browser Lifecycle & Memory Metrics (#773)", sep="=", bold=True
        )
        for entry in _LIFECYCLE_METRICS:
            t_name = entry["test"]
            u_heap = entry["used_heap_mb"]
            tot_heap = entry["total_heap_mb"]
            lim_heap = entry["limit_mb"]
            line = (
                f"  • {t_name:<45} | JS Heap: {u_heap:>6} MB / "
                f"{tot_heap:>6} MB (Limit: {lim_heap} MB)"
            )
            terminalreporter.write_line(line)
        terminalreporter.ensure_newline()


@pytest.fixture(scope="module")
def shared_page(browser: Browser) -> Page:
    """Module-scoped page fixture. Boots Godot WASM once per module."""
    context = browser.new_context(viewport={"width": 1280, "height": 720})
    page = context.new_page()

    # 1. Neutralize native JS alert/confirm dialogs so they never freeze CDP
    page.add_init_script("""
        window.alert = (msg) => console.log('[STUBBED ALERT]: ' + msg);
        window.confirm = (msg) => {
            console.log('[STUBBED CONFIRM]: ' + msg);
            return true;
        };
    """)
    page.on("dialog", lambda dialog: dialog.dismiss())

    # 2. Centralized page load & WASM initialization check
    init_page_and_wait_ready(page)

    yield page

    # Teardown: Explicitly lose WebGL context to free GPU memory before closing
    try:
        page.evaluate("""() => {
            const canvas = document.getElementById('canvas');
            if (canvas) {
                const gl = (
                    canvas.getContext('webgl2') || canvas.getContext('webgl')
                );
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
    """Executes a lightweight UI state reset between tests using window hooks."""
    yield
    if "shared_page" in request.fixturenames:
        page = request.getfixturevalue("shared_page")
        try:
            page.evaluate("""() => {
                localStorage.clear();
                sessionStorage.clear();
                const hooks = [
                    'audioBackPressed',
                    'controlsBackPressed',
                    'gameplayBackPressed',
                    'advancedBackPressed',
                    'optionsBackPressed'
                ];
                hooks.forEach((hook) => {
                    if (typeof window[hook] === 'function') {
                        window[hook]([]);
                    }
                });
            }""")
        except Exception:
            pass


@pytest.fixture(scope="session")
def browser_instance(
    playwright: Playwright, request: pytest.FixtureRequest
) -> Generator[Browser, None, None]:
    """Session-scoped Chromium launch fixture to minimize startup overhead."""
    launch_options = {
        "headless": True,
        "args": [
            "--enable-unsafe-swiftshader",
            "--disable-gpu",
            "--use-gl=swiftshader",
        ],
    }
    if "browser_type_launch_args" in request.fixturenames:
        override = request.getfixturevalue("browser_type_launch_args")
        if isinstance(override, dict):
            launch_options.update(override)
        elif isinstance(override, list):
            launch_options["args"] = override

    browser = playwright.chromium.launch(**launch_options)
    yield browser
    browser.close()


@pytest.fixture(scope="function")
def page(
    browser_instance: Browser, request: pytest.FixtureRequest
) -> Generator[Page, None, None]:
    """Provides clean browser context isolation for each test."""
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
