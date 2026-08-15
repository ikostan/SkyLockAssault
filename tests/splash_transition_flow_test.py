# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/splash_transition_flow_test.py
"""
Splash Screen Transition & Telemetry Test Suite (Playwright + UI Automation)
=============================================================================

Overview
--------
Verifies the asynchronous web loading workflow, custom shell initialization pipeline,
progressive assembly telemetry, and in-game progress transition mechanics. Eliminates
race conditions by validating orderly handshakes between the DOM layout engine and the
WebAssembly runtime graphics context.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with preloader & overlays)
- pytest, playwright

Running
-------
pytest -k splash_transition_flow -q

Artifacts
---------
v8_coverage_splash_transition_flow_test.json, artifacts/test_splash_failure_*.png/txt/html
"""

import json
import os
import re
import time
from typing import Any

from playwright.sync_api import Page, expect

from tests.test_utils import DEFAULT_TIMEOUT, TEST_TIMEOUT


# DO NOT REFACTOR: Must consume function-scoped `page` to capture preloader & startup telemetry.
def test_splash_transition_flow(page: Page) -> None:
    """
    Validates assembly stream metrics, progressive telemetry monotonicity,
    WebGL frame canvas presentation, and orderly removal of preloader DOM layers.
    """
    logs: list[dict[str, str]] = []
    page_errors: list[str] = []
    cdp_session = None

    def on_console(msg: Any) -> None:
        """Capture all console logs to track runtime lifecycle telemetry."""
        logs.append({"type": msg.type, "text": msg.text})

    def on_page_error(exc: Any) -> None:
        """Capture uncaught runtime errors during engine boot."""
        page_errors.append(f"Uncaught Exception: {exc.message}\n{exc.stack}")

    # Register listeners BEFORE navigation to capture early boot telemetry & errors
    page.on("console", on_console)
    page.on("pageerror", on_page_error)

    try:
        # 1. INITIALIZE V8 PRECISE COVERAGE VIA CDP
        cdp_session = page.context.new_cdp_session(page)
        cdp_session.send("Profiler.enable")
        cdp_session.send(
            "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
        )

        # 2. MONITOR INITIAL BROWSER LOADING LAYER
        page.goto(
            "http://localhost:8080/index.html",
            wait_until="domcontentloaded",
            timeout=DEFAULT_TIMEOUT,
        )

        # Verify custom HTML layout preloader maps instantly to the viewport
        loading_overlay = page.locator("#loading")
        expect(loading_overlay).to_be_visible(timeout=TEST_TIMEOUT)

        # 3. VERIFY ENGINE INITIALIZATION & RUNTIME TELEMETRY
        page.wait_for_function(
            "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
        )

        # Parse progressive assembly transfer marks ("Telemetry - Assembly Transfer: X%")
        progress_values: list[int] = []
        for log in logs:
            match = re.search(r"Telemetry - Assembly Transfer:\s*(\d+)%", log["text"])
            if match:
                progress_values.append(int(match.group(1)))

        # Assert telemetry presence, range bounds, and monotonic forward progression
        assert (
            len(progress_values) > 0
        ), "No 'Telemetry - Assembly Transfer:' marks captured during engine boot."
        assert all(
            0 <= val <= 100 for val in progress_values
        ), f"Telemetry percentage out of bounds [0, 100]: {progress_values}"
        assert progress_values == sorted(
            progress_values
        ), f"Assembly transfer telemetry did not progress monotonically: {progress_values}"

        # 4. ASSIGN RENDERING CANVAS HANDSHAKE & STRUCTURAL GEOMETRY
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

        # 5. VERIFY DOM TEARDOWN & LIFECYCLE INVARIANTS
        expect(loading_overlay).to_be_hidden(timeout=TEST_TIMEOUT)
        assert page.evaluate(
            "() => document.getElementById('loading').getAttribute('aria-hidden') === 'true'"
        ), "Loading container missing aria-hidden='true' post-initialization"

        # Invariant: engine initialization state must remain true after overlay teardown
        assert page.evaluate(
            "() => window.godotInitialized === true"
        ), "window.godotInitialized lost its truthy state after splash transition completed"

        # 6. AUDIT FATAL PARSING & SCRIPT COMPILATION EXCEPTIONS
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
        ), f"Critical exceptions found during web handshake:\n" + "\n".join(
            critical_faults
        )

    except Exception as e:
        print(f"Test: 'test_splash_transition_flow' failed: {e!s}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())

        # Isolate diagnostic files on execution crashes
        page.screenshot(
            path=f"artifacts/test_splash_failure_screenshot_{timestamp}.png"
        )

        with open(
            f"artifacts/test_splash_failure_console_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            f.write("--- CONSOLE LOGS ---\n")
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
            f.write("\n--- PAGE ERRORS ---\n")
            for p_err in page_errors:
                f.write(f"{p_err}\n")

        with open(
            f"artifacts/test_splash_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        raise

    finally:
        try:
            page.remove_listener("console", on_console)
            page.remove_listener("pageerror", on_page_error)
        except Exception:
            pass

        if cdp_session:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                cdp_session.detach()
                with open(
                    "v8_coverage_splash_transition_flow_test.json",
                    "w",
                    encoding="utf-8",
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")
