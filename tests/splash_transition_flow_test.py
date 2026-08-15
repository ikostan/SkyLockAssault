# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/splash_transition_flow_test.py
"""
Splash Screen Transition & Telemetry Test Suite (Playwright + UI Automation)
=============================================================================

Overview
--------
Verifies the asynchronous web loading workflow, custom shell initialization
pipeline, progressive assembly telemetry, and in-game progress transition
mechanics. Eliminates race conditions by validating orderly handshakes
between the DOM layout engine and the WebAssembly runtime graphics context.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with preloader & overlays)
- pytest, playwright

Running
-------
pytest -k splash_transition_flow -q
"""

import re
import time
from pathlib import Path
from typing import Any

from playwright.sync_api import Page, expect

from tests.test_utils import (
    ARTIFACTS_DIR,
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    init_cdp_coverage,
    save_v8_coverage,
)

_CUSTOM_SHELL_PATH = Path(__file__).resolve().parents[1] / "custom_shell.html"
_ON_PROGRESS_MARKER = "onProgress: function(current, total)"


# ==============================================================================
# Helper Functions for Isolated JS Unit Tests
# ==============================================================================


def _extract_on_progress_function_source() -> str:
    """Extracts onProgress telemetry callback verbatim from custom_shell.html."""
    html = _CUSTOM_SHELL_PATH.read_text(encoding="utf-8")
    try:
        marker_idx = html.index(_ON_PROGRESS_MARKER)
    except ValueError as exc:
        raise AssertionError(
            "onProgress telemetry handler not found in custom_shell.html"
        ) from exc

    brace_start = html.index("{", marker_idx)
    depth = 0
    idx = brace_start
    while idx < len(html):
        if html[idx] == "{":
            depth += 1
        elif html[idx] == "}":
            depth -= 1
            if depth == 0:
                break
        idx += 1
    else:
        raise AssertionError("Could not find matching closing brace for body")

    body = html[brace_start : idx + 1]
    return f"function(current, total) {body}"


def _run_on_progress(
    page: Page, fn_source: str, calls: list[tuple[int, int]]
) -> list[str]:
    """Evaluates the extracted callback in an isolated JS context."""
    return page.evaluate(
        """([fnSource, calls]) => {
            const onProgress = new Function('return (' + fnSource + ')')();
            const outputs = [];
            const originalLog = console.log;
            console.log = (msg) => { outputs.push(msg); };
            try {
                for (const [current, total] of calls) {
                    onProgress(current, total);
                }
            } finally {
                console.log = originalLog;
            }
            return outputs;
        }""",
        [fn_source, calls],
    )


# ==============================================================================
# Fast Unit Tests (Run in ~20ms, No WASM Boot Required)
# ==============================================================================


def test_on_progress_telemetry_math_is_correct(page: Page) -> None:
    """Validates percentage calculations in isolated JS context."""
    fn_source = _extract_on_progress_function_source()
    outputs = _run_on_progress(
        page, fn_source, [(0, 200), (50, 200), (100, 200), (200, 200)]
    )
    assert outputs == [
        "Telemetry - Assembly Transfer: 0%",
        "Telemetry - Assembly Transfer: 25%",
        "Telemetry - Assembly Transfer: 50%",
        "Telemetry - Assembly Transfer: 100%",
    ]


def test_on_progress_floors_fractional_percentages(page: Page) -> None:
    """Regression test: fractional percentages must be floored, not rounded."""
    fn_source = _extract_on_progress_function_source()
    outputs = _run_on_progress(
        page,
        fn_source,
        [(1, 3), (2, 3), (99, 100)],
    )
    assert outputs == [
        "Telemetry - Assembly Transfer: 33%",
        "Telemetry - Assembly Transfer: 66%",
        "Telemetry - Assembly Transfer: 99%",
    ]


def test_on_progress_skips_logging_when_total_is_zero(page: Page) -> None:
    """Guards against division-by-zero (NaN% or Infinity%) when total is 0."""
    fn_source = _extract_on_progress_function_source()
    outputs = _run_on_progress(page, fn_source, [(0, 0), (5, 0)])
    assert outputs == [], f"Expected no logs when total=0, got: {outputs}"


# ==============================================================================
# E2E Stage Validation Helpers (Cyclomatic Complexity Reduction)
# ==============================================================================


def _validate_telemetry_stream(logs: list[dict[str, str]]) -> None:
    """Validates presence, progression, and formatting of telemetry marks."""
    progress_values: list[int] = []
    for log in logs:
        match = re.search(
            r"Telemetry - Assembly Transfer:\s*(\d+)%",
            log["text"],
        )
        if match:
            progress_values.append(int(match.group(1)))

    assert (
        len(progress_values) > 0
    ), "No 'Telemetry - Assembly Transfer:' marks captured during load."
    assert all(
        0 <= val <= 100 for val in progress_values
    ), f"Telemetry percentage out of bounds [0, 100]: {progress_values}"
    assert progress_values == sorted(progress_values), (
        "Assembly transfer telemetry did not progress monotonically: "
        f"{progress_values}"
    )
    assert max(progress_values) >= 90, (
        "Assembly transfer telemetry never approached completion: "
        f"{progress_values}"
    )

    malformed = [
        log["text"]
        for log in logs
        if "Telemetry - Assembly Transfer:" in log["text"]
        and not re.search(r"Telemetry - Assembly Transfer:\s*\d+%$", log["text"])
    ]
    assert malformed == [], f"Malformed telemetry entries: {malformed}"


def _validate_canvas_and_dom_invariants(
    page: Page, loading_overlay: Any
) -> None:
    """Validates canvas layout, overlay teardown, and initialized state."""
    canvas_element = page.locator("#canvas")
    expect(canvas_element).to_be_visible(timeout=TEST_TIMEOUT)

    canvas_box = canvas_element.bounding_box()
    assert canvas_box is not None, "Canvas element has no rendered bounding box"
    assert (
        canvas_box["width"] > 0
    ), "Canvas rendered width is zero (viewport layout failure)"
    assert (
        canvas_box["height"] > 0
    ), "Canvas rendered height is zero (viewport layout failure)"

    assert (
        "SkyLockAssault" in page.title()
    ), f"Target application title mismatch: '{page.title()}'"

    expect(loading_overlay).to_be_hidden(timeout=TEST_TIMEOUT)
    assert page.evaluate(
        "() => document.getElementById('loading')"
        ".getAttribute('aria-hidden') === 'true'"
    ), "Loading container missing aria-hidden='true' post-initialization"

    assert page.evaluate(
        "() => window.godotInitialized === true"
    ), "window.godotInitialized lost state after splash transition"


def _assert_no_critical_faults(
    logs: list[dict[str, str]], page_errors: list[str]
) -> None:
    """Asserts that no fatal exceptions occurred during load."""
    critical_faults = [
        log["text"]
        for log in logs
        if log["type"] == "error"
        and not any(
            phrase in log["text"].lower()
            for phrase in ["encryption aborted", "salt is empty"]
        )
    ] + page_errors

    assert (
        len(critical_faults) == 0
    ), "Critical exceptions found during web handshake:\n" + "\n".join(
        critical_faults
    )


def _save_failure_artifacts(
    page: Page, logs: list[dict[str, str]], page_errors: list[str]
) -> None:
    """Captures diagnostic log and DOM snapshot to ARTIFACTS_DIR on error."""
    timestamp = int(time.time())
    logs_path = ARTIFACTS_DIR / f"test_splash_failure_logs_{timestamp}.txt"
    with open(logs_path, "w", encoding="utf-8") as f:
        f.write("--- CONSOLE LOGS ---\n")
        for log in logs:
            f.write(f"[{log['type']}] {log['text']}\n")
        f.write("\n--- PAGE ERRORS ---\n")
        for p_err in page_errors:
            f.write(f"{p_err}\n")

    html_path = ARTIFACTS_DIR / f"test_splash_failure_html_{timestamp}.html"
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(page.content())


# ==============================================================================
# Comprehensive E2E Test (Single WASM Boot)
# ==============================================================================


# DO NOT REFACTOR: Must consume function-scoped `page` to capture preloader
# and early startup telemetry.
def test_splash_transition_flow(page: Page) -> None:
    """
    Validates assembly stream metrics, progressive telemetry monotonicity,
    WebGL frame canvas presentation, and orderly removal of preloader DOM.
    """
    logs: list[dict[str, str]] = []
    page_errors: list[str] = []

    def on_console(msg: Any) -> None:
        """Capture all console logs to track runtime lifecycle telemetry."""
        logs.append({"type": msg.type, "text": msg.text})

    def on_page_error(exc: Any) -> None:
        """Capture uncaught runtime errors during engine boot."""
        page_errors.append(f"Uncaught Exception: {exc.message}\n{exc.stack}")

    page.on("console", on_console)
    page.on("pageerror", on_page_error)

    # 1. Initialize V8 coverage
    cdp_session, _ = init_cdp_coverage(page)

    try:
        # 2. Navigate and verify initial preloader visibility
        page.goto(
            "http://localhost:8080/index.html",
            wait_until="domcontentloaded",
            timeout=DEFAULT_TIMEOUT,
        )

        loading_overlay = page.locator("#loading")
        expect(loading_overlay).to_be_visible(timeout=TEST_TIMEOUT)

        # 3. Wait for WASM initialization
        page.wait_for_function(
            "() => window.godotInitialized === true",
            timeout=DEFAULT_TIMEOUT,
        )

        # 4. Run extracted assertions
        _validate_telemetry_stream(logs)
        _validate_canvas_and_dom_invariants(page, loading_overlay)
        _assert_no_critical_faults(logs, page_errors)

    except Exception as e:
        print(f"Test: 'test_splash_transition_flow' failed: {e!s}")
        _save_failure_artifacts(page, logs, page_errors)
        raise

    finally:
        try:
            page.remove_listener("console", on_console)
            page.remove_listener("pageerror", on_page_error)
        except Exception:
            pass

        # 5. Harvest & save coverage
        save_v8_coverage(cdp_session, "splash_transition_flow_test")
