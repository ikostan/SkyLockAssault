# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/conftest.py
"""Shared pytest fixtures, configs, and metrics for E2E tests."""

import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Generator

import pytest
from playwright.sync_api import Browser, BrowserContext, Page, Playwright

from tests.test_utils import init_page_and_wait_ready

# Project paths and artifacts configuration
PROJECT_ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS_DIR = PROJECT_ROOT / "artifacts"
ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)

# Storage for test lifecycle memory metrics (#773)
_LIFECYCLE_METRICS = []

# Storage for Task #776 profiling & metrics baseline
_SESSION_STATE: dict[str, Any] = {
    "start_time": 0.0,
    "timestamp": "",
}
_TEST_PROFILING_DATA: list[dict] = []
_SUMMARY_COUNTS = {"passed": 0, "failed": 0, "skipped": 0}

# Storage for test-spawned PIDs if managed via pytest
_TRACKED_PIDS: set[int] = set()


def track_process_pid(pid: int) -> None:
    """Track sub-process PIDs spawned during test execution.

    Parameters
    ----------
    pid : int
        Process ID to register for teardown cleanup.
    """
    if pid:
        _TRACKED_PIDS.add(pid)


def pytest_sessionstart(session) -> None:
    """Capture session start timestamp and start time for profiling (#776).

    Parameters
    ----------
    session : pytest.Session
        The pytest session object starting execution.
    """
    _ = session
    _SESSION_STATE["start_time"] = time.perf_counter()
    _SESSION_STATE["timestamp"] = time.strftime(
        "%Y-%m-%dT%H:%M:%SZ", time.gmtime()
    )


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Collect execution duration and outcome for report generation (#776).

    Parameters
    ----------
    item : pytest.Item
        The test item being reported.
    call : pytest.CallInfo
        The call phase outcome information.
    """
    outcome = yield
    if call.when == "call":
        report = outcome.get_result()
        wasm_boot = getattr(item, "_wasm_boot_time", None)
        test_detail = {
            "nodeid": item.nodeid,
            "duration_sec": round(report.duration, 4),
            "outcome": report.outcome,
            "wasm_boot_duration_sec": (
                round(wasm_boot, 4) if wasm_boot is not None else None
            ),
        }
        _TEST_PROFILING_DATA.append(test_detail)

        if report.outcome in _SUMMARY_COUNTS:
            _SUMMARY_COUNTS[report.outcome] += 1
        else:
            _SUMMARY_COUNTS[report.outcome] = 1


def pytest_sessionfinish(session, exitstatus):
    """Write Task #776 metrics baseline JSON and terminate PIDs.

    Parameters
    ----------
    session : pytest.Session
        The completed pytest session.
    exitstatus : int
        The overall session exit status code.
    """
    _ = (session, exitstatus)

    # 1. Export Task #776 Baseline Metrics JSON
    start_time = _SESSION_STATE["start_time"]
    total_duration = (
        round(time.perf_counter() - start_time, 4) if start_time else 0.0
    )
    metrics_payload = {
        "timestamp": _SESSION_STATE["timestamp"],
        "total_duration_sec": total_duration,
        "summary": _SUMMARY_COUNTS,
        "tests": _TEST_PROFILING_DATA,
    }

    metrics_file = ARTIFACTS_DIR / "metrics_baseline.json"
    try:
        with open(metrics_file, "w", encoding="utf-8") as f:
            json.dump(metrics_payload, f, indent=2)
    except Exception as exc:  # noqa: BLE001 - best effort export
        print(f"Warning: Failed to write metrics baseline: {exc}")

    # 2. Safely terminate tracked sub-processes
    for pid in list(_TRACKED_PIDS):
        try:
            if os.name == "nt":
                cmd = (
                    shutil.which("taskkill")
                    or "C:\\Windows\\System32\\taskkill.exe"
                )
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
    """Capture browser JS heap memory metrics after test execution (#773).

    Parameters
    ----------
    request : pytest.FixtureRequest
        The requesting test fixture context.
    """
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
    """Output Task #776 baseline and #773 memory metrics at suite end.

    Parameters
    ----------
    terminalreporter : _pytest.terminal.TerminalReporter
        The pytest terminal reporter instance.
    exitstatus : int
        The session exit status code.
    config : pytest.Config
        The active pytest configuration.
    """
    _ = (exitstatus, config)

    # Output Task #776 Baseline Summary
    if _TEST_PROFILING_DATA:
        terminalreporter.ensure_newline()
        terminalreporter.section("Test Profiling Baseline (#776)", sep="=", bold=True)
        start_time = _SESSION_STATE["start_time"]
        total_duration = (
            round(time.perf_counter() - start_time, 4) if start_time else 0.0
        )
        terminalreporter.write_line(f"Total Suite Duration : {total_duration}s")
        terminalreporter.write_line(
            f"Passed: {_SUMMARY_COUNTS.get('passed', 0)} | "
            f"Failed: {_SUMMARY_COUNTS.get('failed', 0)} | "
            f"Skipped: {_SUMMARY_COUNTS.get('skipped', 0)}"
        )
        metrics_file = ARTIFACTS_DIR / "metrics_baseline.json"
        terminalreporter.write_line(f"Baseline JSON Exported: {metrics_file}")
        terminalreporter.ensure_newline()

    # Output Task #773 Memory & Lifecycle Summary
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
def shared_page(browser: Browser) -> Generator[Page, None, None]:
    """Module-scoped page fixture. Boots Godot WASM once per module.

    Parameters
    ----------
    browser : Browser
        The Playwright Browser instance.

    Yields
    ------
    Page
        An initialized Playwright Page instance with Godot WASM booted.
    """
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
    """Execute a lightweight UI state reset between tests using window hooks.

    Parameters
    ----------
    request : pytest.FixtureRequest
        The requesting test fixture context.
    """
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
    """Session-scoped Chromium launch fixture to minimize startup overhead.

    Parameters
    ----------
    playwright : Playwright
        The Playwright context instance.
    request : pytest.FixtureRequest
        The requesting test fixture context.

    Yields
    ------
    Browser
        Launched session-scoped Chromium browser instance.
    """
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
    """Provide clean browser context isolation for each test function.

    Parameters
    ----------
    browser_instance : Browser
        The shared Chromium browser instance.
    request : pytest.FixtureRequest
        The requesting test fixture context.

    Yields
    ------
    Page
        An isolated Playwright Page instance.
    """
    har_path = None
    if request.node.get_closest_marker("record_har"):
        nodeid = request.node.nodeid
        safe_nodeid = re.sub(r"[^A-Za-z0-9._-]+", "_", nodeid)
        har_path = ARTIFACTS_DIR / f"{safe_nodeid}.har"

    context: BrowserContext = browser_instance.new_context(
        viewport={"width": 1280, "height": 720},
        record_har_path=str(har_path) if har_path else None,
    )
    page: Page = context.new_page()
    yield page
    context.close()


def pytest_configure(config: pytest.Config) -> None:
    """Register custom pytest markers for network tracing and profiling.

    Parameters
    ----------
    config : pytest.Config
        The global pytest configuration object.
    """
    config.addinivalue_line(
        "markers",
        "record_har: Mark tests that should record HAR files "
        "for network tracing in Playwright.",
    )
