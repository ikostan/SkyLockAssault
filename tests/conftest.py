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
import warnings
from pathlib import Path
from typing import Any, Generator

import pytest
from playwright.sync_api import Browser, BrowserContext, Page, Playwright, sync_playwright

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

# Set of failed test node IDs across session execution
_FAILED_NODEIDS: set[str] = set()


# ==============================================================================
# Helper Functions
# ==============================================================================


def track_process_pid(pid: int) -> None:
    """Track sub-process PIDs spawned during test execution.

    Parameters
    ----------
    pid : int
        Process ID to register for teardown cleanup.
    """
    if pid:
        _TRACKED_PIDS.add(pid)


def _is_test_failed(
    request: pytest.FixtureRequest, include_module_failures: bool = False
) -> tuple[bool, str]:
    """Determine if the active test node or any test in its parent module failed.

    Parameters
    ----------
    request : pytest.FixtureRequest
        The requesting test fixture context.
    include_module_failures : bool, default=False
        Whether to inspect module-wide failures (used exclusively by module-scoped
        fixtures like `shared_page` so final context teardown retains diagnostics
        attributed to the primary failing test node ID).

    Returns
    -------
    tuple[bool, str]
        Tuple containing (is_failed, target_nodeid).
    """
    rep_setup = getattr(request.node, "rep_setup", None)
    rep_call = getattr(request.node, "rep_call", None)
    node_failed = (
        (rep_setup and rep_setup.failed)
        or (rep_call and rep_call.failed)
        or (request.node.nodeid in _FAILED_NODEIDS)
    )

    module_failed_tests: list[str] = []
    if include_module_failures:
        mod_prefix = str(request.node.nodeid).split("::")[0]
        module_failed_tests = [
            nid for nid in _FAILED_NODEIDS if nid.startswith(mod_prefix)
        ]

    test_failed = node_failed or bool(module_failed_tests)

    # Attribute module-level fixture diagnostics to the first failing test node ID
    # in the module, or fallback to the current node ID if the failure was isolated.
    target_nodeid = (
        module_failed_tests[0] if module_failed_tests else request.node.nodeid
    )
    return test_failed, target_nodeid


def _stop_tracing(context: BrowserContext, safe_nodeid: str, test_failed: bool) -> None:
    """Stop Playwright tracing and conditionally export trace archive.

    Parameters
    ----------
    context : BrowserContext
        The Playwright BrowserContext being closed.
    safe_nodeid : str
        Sanitized node ID for file naming.
    test_failed : bool
        Flag indicating if the test failed.
    """
    trace_path = ARTIFACTS_DIR / f"trace_{safe_nodeid}.zip" if test_failed else None
    try:
        if trace_path:
            context.tracing.stop(path=str(trace_path))
        else:
            context.tracing.stop()
    except Exception as exc:  # noqa: BLE001
        warnings.warn(
            f"Failed to stop tracing for {safe_nodeid}: {exc}",
            UserWarning,
            stacklevel=2,
        )


def _finalize_video(video_handle: Any, safe_nodeid: str, test_failed: bool) -> None:
    """Save or delete video recording based on test outcome post-context close.

    Parameters
    ----------
    video_handle : Any
        The Playwright Video handle or None.
    safe_nodeid : str
        Sanitized node ID for file naming.
    test_failed : bool
        Flag indicating if the test failed.
    """
    if not video_handle:
        return

    if test_failed:
        video_path = ARTIFACTS_DIR / f"video_{safe_nodeid}.webm"
        try:
            video_handle.save_as(str(video_path))
        except Exception as exc:  # noqa: BLE001
            warnings.warn(
                f"Failed to save video for {safe_nodeid}: {exc}",
                UserWarning,
                stacklevel=2,
            )
    else:
        try:
            video_handle.delete()
        except Exception as exc:  # noqa: BLE001
            warnings.warn(
                f"Failed to delete video for {safe_nodeid}: {exc}",
                UserWarning,
                stacklevel=2,
            )


def _cleanup_context_diagnostics(
    context: BrowserContext,
    page_obj: Page,
    request: pytest.FixtureRequest,
    include_module_failures: bool = False,
) -> None:
    """Conditionally retain trace, screenshot, and video on failure, or purge on pass.

    Parameters
    ----------
    context : BrowserContext
        The Playwright BrowserContext being closed.
    page_obj : Page
        The active Playwright Page instance.
    request : pytest.FixtureRequest
        The requesting test fixture context.
    include_module_failures : bool, default=False
        Whether to include module-level failure matching.
    """
    test_failed, target_nodeid = _is_test_failed(
        request, include_module_failures=include_module_failures
    )
    safe_nodeid = re.sub(r"[^A-Za-z0-9._-]+", "_", target_nodeid)
    video_handle = page_obj.video

    try:
        if test_failed:
            screenshot_path = ARTIFACTS_DIR / f"failure_{safe_nodeid}.png"
            try:
                page_obj.screenshot(path=str(screenshot_path), full_page=True)
            except Exception as exc:  # noqa: BLE001
                warnings.warn(
                    f"Failed to capture failure screenshot for {safe_nodeid}: {exc}",
                    UserWarning,
                    stacklevel=2,
                )

        _stop_tracing(context, safe_nodeid, test_failed)
    finally:
        # Close context FIRST so Playwright finalizes video file streams on disk
        try:
            context.close()
        except Exception as exc:  # noqa: BLE001
            warnings.warn(
                f"Error closing Playwright browser context for {safe_nodeid}: {exc}",
                UserWarning,
                stacklevel=2,
            )

        _finalize_video(video_handle, safe_nodeid, test_failed)


def _determine_final_outcome(item: pytest.Item, rep_teardown: pytest.TestReport) -> str:
    """Determine overall test outcome across setup, call, and teardown phases.

    Parameters
    ----------
    item : pytest.Item
        The active pytest item being reported.
    rep_teardown : pytest.TestReport
        The teardown phase test report object.

    Returns
    -------
    str
        One of "failed", "skipped", or "passed".
    """
    rep_setup = getattr(item, "rep_setup", None)
    rep_call = getattr(item, "rep_call", None)

    for rep in (rep_setup, rep_call, rep_teardown):
        if rep and rep.failed:
            return "failed"

    for rep in (rep_setup, rep_call):
        if rep and rep.skipped:
            return "skipped"

    return "passed"


def _record_test_profiling(item: pytest.Item, rep_teardown: pytest.TestReport) -> None:
    """Record test profiling metrics at teardown phase (#776).

    Parameters
    ----------
    item : pytest.Item
        The active pytest item being reported.
    rep_teardown : pytest.TestReport
        The teardown phase test report object.
    """
    rep_setup = getattr(item, "rep_setup", None)
    rep_call = getattr(item, "rep_call", None)

    final_outcome = _determine_final_outcome(item, rep_teardown)

    if final_outcome == "failed":
        _FAILED_NODEIDS.add(item.nodeid)

    duration = sum(
        rep.duration for rep in (rep_setup, rep_call, rep_teardown) if rep is not None
    )

    wasm_boot = getattr(item, "_wasm_boot_time", None)
    wasm_boot_sec = round(wasm_boot, 4) if wasm_boot is not None else None

    _TEST_PROFILING_DATA.append(
        {
            "nodeid": item.nodeid,
            "duration_sec": round(duration, 4),
            "outcome": final_outcome,
            "wasm_boot_duration_sec": wasm_boot_sec,
        }
    )

    _SUMMARY_COUNTS[final_outcome] = _SUMMARY_COUNTS.get(final_outcome, 0) + 1


# ==============================================================================
# Pytest Hooks
# ==============================================================================


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


def pytest_sessionstart(session) -> None:
    """Capture session start timestamp and start time for profiling (#776).

    Parameters
    ----------
    session : pytest.Session
        The pytest session object starting execution.
    """
    _ = session
    _SESSION_STATE["start_time"] = time.perf_counter()
    _SESSION_STATE["timestamp"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Collect execution duration and outcome across all phases (#776).

    Parameters
    ----------
    item : pytest.Item
        The test item being reported.
    call : pytest.CallInfo
        The phase outcome information.
    """
    _ = call
    outcome = yield
    report = outcome.get_result()
    setattr(item, f"rep_{report.when}", report)

    # Record setup and call failures immediately before fixture teardowns run
    if report.when in {"setup", "call"} and report.failed:
        _FAILED_NODEIDS.add(item.nodeid)

    # Finalize reporting only once teardown completes
    if report.when == "teardown":
        _record_test_profiling(item, report)


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
    total_duration = round(time.perf_counter() - start_time, 4) if start_time else 0.0
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
        warnings.warn(
            f"Failed to write metrics baseline: {exc}",
            UserWarning,
            stacklevel=2,
        )

    # 2. Safely terminate tracked sub-processes
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


# ==============================================================================
# Pytest Fixtures
# ==============================================================================


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
    page_obj = request.getfixturevalue(page_fixture) if page_fixture else None
    yield

    if page_obj is not None:
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
            heap_info = page_obj.evaluate(heap_script)

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
            warnings.warn(
                f"Heap metric capture failed: {exc}",
                UserWarning,
                stacklevel=2,
            )


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
        page_obj = request.getfixturevalue("shared_page")
        try:
            page_obj.evaluate("""() => {
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
def playwright_instance() -> Generator[Playwright, None, None]:
    """Session-scoped Playwright context generator independent of pytest plugins."""
    with sync_playwright() as pw:
        yield pw


@pytest.fixture(scope="session")
def browser_instance(
    playwright_instance: Playwright, request: pytest.FixtureRequest
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

    browser = playwright_instance.chromium.launch(**launch_options)
    yield browser
    browser.close()


@pytest.fixture(scope="module")
def shared_page(
    browser_instance: Browser, request: pytest.FixtureRequest
) -> Generator[Page, None, None]:
    """Module-scoped page fixture. Boots Godot WASM once per module."""
    context = browser_instance.new_context(
        viewport={"width": 1280, "height": 720},
        record_video_dir=str(ARTIFACTS_DIR),
        record_video_size={"width": 1280, "height": 720},
    )
    context.tracing.start(screenshots=True, snapshots=True, sources=True)
    page_obj = context.new_page()

    page_obj.add_init_script("""
        window.alert = (msg) => console.log('[STUBBED ALERT]: ' + msg);
        window.confirm = (msg) => {
            console.log('[STUBBED CONFIRM]: ' + msg);
            return true;
        };
    """)
    page_obj.on("dialog", lambda dialog: dialog.dismiss())

    init_page_and_wait_ready(page_obj)

    try:
        yield page_obj
    finally:
        try:
            page_obj.evaluate("""() => {
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

        _cleanup_context_diagnostics(
            context, page_obj, request, include_module_failures=True
        )


@pytest.fixture(scope="function")
def page(
    browser_instance: Browser, request: pytest.FixtureRequest
) -> Generator[Page, None, None]:
    """Provide clean browser context isolation for each test function."""
    har_path = None
    if request.node.get_closest_marker("record_har"):
        nodeid = request.node.nodeid
        safe_nodeid = re.sub(r"[^A-Za-z0-9._-]+", "_", nodeid)
        har_path = ARTIFACTS_DIR / f"{safe_nodeid}.har"

    context: BrowserContext = browser_instance.new_context(
        viewport={"width": 1280, "height": 720},
        record_har_path=str(har_path) if har_path else None,
        record_video_dir=str(ARTIFACTS_DIR),
        record_video_size={"width": 1280, "height": 720},
    )

    context.tracing.start(screenshots=True, snapshots=True, sources=True)
    page_obj: Page = context.new_page()

    try:
        yield page_obj
    finally:
        _cleanup_context_diagnostics(
            context, page_obj, request, include_module_failures=False
        )
