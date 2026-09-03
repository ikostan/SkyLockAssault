# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/telemetry_and_hold_test.py
"""UX Hold Pacing & Assembly Transfer Telemetry Test Suite.

Validates the 1.0s in-engine completion hold delay on the loading screen and
verifies progress bar telemetry monotonicity, bounds, and malformed input
handling (Issue #912).
"""

import json
import math
import os
import re
import time
from datetime import datetime
from typing import Any

from playwright.sync_api import (
    Page,
    TimeoutError as PlaywrightTimeoutError,
    expect,
)

from tests.gpu_detection_modal_test import get_webgl_mock_script
from tests.test_utils import (
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    open_options_menu,
    set_log_level,
    wait_for_console_log,
)


# ==============================================================================
# Helper Functions & In-Engine Timestamp Parsing
# ==============================================================================


def _setup_mock_page(page: Page, logs: list[dict[str, Any]]) -> Any:
    """Configures hardware GPU mock, attaches listeners, starts CDP coverage,
    and forces DEBUG log level to enable in-engine timing telemetry.
    """

    def on_console(msg: Any) -> None:
        """Appends intercepted console messages to the logs list."""
        logs.append(
            {"type": msg.type, "text": msg.text, "time": time.perf_counter()}
        )

    page.on("console", on_console)

    cdp_session = page.context.new_cdp_session(page)
    cdp_session.send("Profiler.enable")
    cdp_session.send(
        "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
    )

    # Mock hardware GPU to bypass software emulation warnings
    page.add_init_script(
        get_webgl_mock_script(
            renderer_string="ANGLE (NVIDIA, RTX 4070 Direct3D11)"
        )
    )
    page.goto(
        "http://localhost:8080/index.html",
        wait_until="domcontentloaded",
        timeout=DEFAULT_TIMEOUT,
    )
    page.wait_for_function(
        "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
    )

    # Dismiss GPU warning modal if displayed
    gpu_btn = page.locator("#gpu-warning-dismiss-btn")
    modal_visible = False
    try:
        gpu_btn.wait_for(state="visible", timeout=1500)
        modal_visible = True
    except PlaywrightTimeoutError:
        pass

    if modal_visible:
        gpu_btn.click()

    open_options_menu(page)
    set_log_level(page, logs, level_index=0)  # 0 = DEBUG

    page.wait_for_selector(
        "#options-back-button", state="visible", timeout=TEST_TIMEOUT
    )
    page.wait_for_function(
        "() => typeof window.optionsBackPressed !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    pre_back = len(logs)
    page.evaluate("window.optionsBackPressed([])")
    wait_for_console_log(
        logs,
        lambda text: (
            "options back button pressed" in str(text).lower()
            or "back button pressed" in str(text).lower()
            or "options menu exited" in str(text).lower()
        ),
        pre_back,
        page,
        timeout_ms=DEFAULT_TIMEOUT,
    )

    # Allow UI thread focus to settle before returning to test logic
    page.wait_for_timeout(500)
    page.wait_for_selector(
        "#start-button", state="visible", timeout=TEST_TIMEOUT
    )

    return cdp_session


def _dump_failure_artifacts(
    page: Page, logs: list[dict[str, Any]], test_id: str
) -> None:
    """Dumps diagnostic artifacts on test failure."""
    os.makedirs("artifacts", exist_ok=True)
    timestamp = int(time.time() * 1000)
    safe_id = os.path.basename(test_id)
    page.screenshot(
        path=f"artifacts/{safe_id}_failure_screenshot_{timestamp}.png"
    )
    with open(
        f"artifacts/{safe_id}_failure_html_{timestamp}.html",
        "w",
        encoding="utf-8",
    ) as f:
        f.write(page.content())
    with open(
        f"artifacts/{safe_id}_failure_console_logs_{timestamp}.txt",
        "w",
        encoding="utf-8",
    ) as f:
        for log_entry in logs:
            f.write(f"[{log_entry['type']}] {log_entry['text']}\n")


def _save_coverage(cdp_session: Any, test_id: str) -> None:
    """Collects and writes V8 coverage data."""
    if cdp_session:
        try:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            os.makedirs("artifacts", exist_ok=True)
            safe_id = os.path.basename(test_id)
            with open(
                f"artifacts/v8_coverage_{safe_id}_{int(time.time() * 1000)}.json",
                "w",
                encoding="utf-8",
            ) as f:
                json.dump(coverage, f)
        except Exception as cov_err:
            print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


def _compute_in_engine_delta_ms(load_log: dict[str, Any], swap_log: dict[str, Any]) -> float:
    """Computes time delta in ms using in-engine ticks, hold durations, or sub-second timestamps."""
    load_text = str(load_log.get("text", ""))
    swap_text = str(swap_log.get("text", ""))

    # 1. Match explicit in-engine ticks: (ticks: 12345)
    t1_ticks = re.search(r"(?:ticks?|at)[:\s=]+(\d+(?:\.\d+)?)\b", load_text, re.IGNORECASE)
    t2_ticks = re.search(r"(?:ticks?|at)[:\s=]+(\d+(?:\.\d+)?)\b", swap_text, re.IGNORECASE)
    if t1_ticks and t2_ticks:
        return float(t2_ticks.group(1)) - float(t1_ticks.group(1))

    # 2. Match explicit hold/elapsed durations in the swap log
    elapsed_match = re.search(
        r"(?:hold|elapsed|delta|duration)[:\s=]+(\d+(?:\.\d+)?)\s*ms\b",
        swap_text,
        re.IGNORECASE,
    )
    if elapsed_match:
        return float(elapsed_match.group(1))

    # 3. Match ISO timestamps with sub-second precision
    m1_iso = re.search(r"\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)\]", load_text)
    m2_iso = re.search(r"\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)\]", swap_text)
    if m1_iso and m2_iso:
        dt1 = datetime.fromisoformat(m1_iso.group(1))
        dt2 = datetime.fromisoformat(m2_iso.group(1))
        return (dt2 - dt1).total_seconds() * 1000.0

    # 4. Fallback to browser console event performance time (seconds to ms)
    if "time" in swap_log and "time" in load_log:
        return (swap_log["time"] - load_log["time"]) * 1000.0

    raise AssertionError(
        f"Could not compute delta between logs:\n"
        f"  load: {load_text}\n"
        f"  swap: {swap_text}"
    )

# ==============================================================================
# Playwright Telemetry & UX Hold Timing Tests
# ==============================================================================

def test_pw_hold_01_ux_completion_delay(page: Page) -> None:
    """PW-HOLD-01: In-engine loading screen visibly holds at 100% for ~1.0s.

    Extracts in-engine timestamps from 'Scene loaded successfully.' and
    '[SWAP TIMING] 1. .instantiate()' to confirm the delta satisfies
    1000ms <= delta <= 1400ms without relying on host-side clock drift.
    """
    logs: list[dict[str, Any]] = []
    cdp_session = None

    try:
        cdp_session = _setup_mock_page(page, logs)

        start_btn = page.locator("#start-button")
        expect(start_btn).to_be_visible(timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.startPressed === 'function'",
            timeout=TEST_TIMEOUT,
        )

        start_click_idx = len(logs)
        start_btn.click(force=True)
        page.evaluate("""() => {
            if (typeof window.startPressed === 'function') {
                window.startPressed([]);
            }
        }""")

        # Await the in-engine swap timing log signaling hold completion
        wait_for_console_log(
            logs,
            lambda text: (
                "[swap timing] 1. .instantiate()" in str(text).lower()
                or "initializing main scene" in str(text).lower()
            ),
            start_click_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )

        # Locate exact instances of completion and instantiate timing logs
        load_log = next(
            (
                log_entry
                for log_entry in logs[start_click_idx:]
                if "scene loaded successfully" in str(log_entry["text"]).lower()
            ),
            None,
        )
        swap_log = next(
            (
                log_entry
                for log_entry in logs[start_click_idx:]
                if "[swap timing] 1. .instantiate()" in str(log_entry["text"]).lower()
            ),
            None,
        )
        if swap_log is None:
            swap_log = next(
                (
                    log_entry
                    for log_entry in logs[start_click_idx:]
                    if "initializing main scene" in str(log_entry["text"]).lower()
                ),
                None,
            )

        assert load_log is not None, "Missing 'Scene loaded successfully.' in console logs"
        assert swap_log is not None, "Missing swap timing log in console logs"

        delta_ms = _compute_in_engine_delta_ms(load_log, swap_log)
        assert 1000.0 <= delta_ms <= 1400.0, (
            f"In-engine UX hold timing {delta_ms:.2f} ms outside "
            f"1000-1400 ms contract window"
        )

    except Exception as e:
        print(f"Test PW-HOLD-01 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_hold_01")
        raise
    finally:
        _save_coverage(cdp_session, "pw_hold_01")


def test_pw_tel_01_monotonic_progress(page: Page) -> None:
    """PW-TEL-01: Progress events emit monotonic non-decreasing, finite percentages."""
    logs: list[dict[str, Any]] = []
    cdp_session = None

    try:
        cdp_session = _setup_mock_page(page, logs)

        # Extract only the telemetry logs generated during boot
        telemetry_logs = [
            str(log_entry["text"])
            for log_entry in logs
            if (
                "telemetry - assembly transfer:"
                in str(log_entry["text"]).lower()
            )
        ]
        assert len(telemetry_logs) > 0, (
            "No telemetry logs found in console history"
        )

        percentages: list[int] = []
        for text in telemetry_logs:
            percent_str = text.split(":")[-1].replace("%", "").strip()
            assert (
                percent_str.replace("-", "").isdigit()
            ), f"Malformed progress telemetry percentage: {percent_str!r}"
            val = float(percent_str)
            assert math.isfinite(val), f"Percentage is not finite: {val}"
            percentages.append(int(val))

        # Check bounds: 0 <= P <= 100
        for p in percentages:
            assert 0 <= p <= 100, f"Telemetry bounds violated: {p}%"

        # Check monotonicity: P_i <= P_{i+1}
        for i in range(len(percentages) - 1):
            assert percentages[i] <= percentages[i + 1], (
                f"Non-monotonic telemetry dip detected: "
                f"{percentages[i]}% -> {percentages[i + 1]}%"
            )

    except Exception as e:
        print(f"Test PW-TEL-01 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_tel_01")
        raise
    finally:
        _save_coverage(cdp_session, "pw_tel_01")


def test_pw_tel_02_terminal_completion(page: Page) -> None:
    """PW-TEL-02: Telemetry contains terminal 100% and does not overflow."""
    logs: list[dict[str, Any]] = []
    cdp_session = None

    try:
        cdp_session = _setup_mock_page(page, logs)

        telemetry_logs = [
            str(log_entry["text"])
            for log_entry in logs
            if (
                "telemetry - assembly transfer:"
                in str(log_entry["text"]).lower()
            )
        ]
        assert len(telemetry_logs) > 0, "No telemetry logs found"

        percentages = [
            int(float(text.split(":")[-1].replace("%", "").strip()))
            for text in telemetry_logs
        ]

        assert 100 in percentages, (
            "Terminal 100% completion step missing from sequence"
        )
        assert max(percentages) == 100, (
            f"Telemetry logic overflowed: {max(percentages)}%"
        )

    except Exception as e:
        print(f"Test PW-TEL-02 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_tel_02")
        raise
    finally:
        _save_coverage(cdp_session, "pw_tel_02")


def test_pw_tel_03_handler_robustness(page: Page) -> None:
    """PW-TEL-03: onProgress handler safely manages boundary conditions."""
    logs: list[dict[str, Any]] = []
    page_errors: list[str] = []
    page.on("pageerror", lambda err: page_errors.append(str(err)))
    cdp_session = None

    try:
        cdp_session = _setup_mock_page(page, logs)
        start_idx = len(logs)

        # Execute boundary testing directly against the production handler
        page.evaluate("""() => {
            if (
                typeof customConfig !== 'object' ||
                typeof customConfig.onProgress !== 'function'
            ) {
                throw new Error("Missing onProgress handler in HTML shell");
            }
            const handler = customConfig.onProgress;
            handler(0, 0);          // Div by zero / empty stream
            handler(-50, 100);      // Negative current state
            handler(150, 100);      // Current state exceeds total
            handler(NaN, 100);      // Non-finite current
            handler(Infinity, 100); // Infinity current
            handler(10, NaN);       // Non-finite total
        }""")

        # Allow execution and console pipeline to clear
        page.wait_for_timeout(150)
        new_logs = [
            str(log_entry["text"]).lower()
            for log_entry in logs[start_idx:]
            if "telemetry - assembly transfer:" in str(log_entry["text"]).lower()
        ]

        # Handler assertions
        assert len(page_errors) == 0, (
            f"Exceptions leaked into page context during execution: "
            f"{page_errors}"
        )
        for text in new_logs:
            assert "nan" not in text, (
                f"Calculation propagated NaN into formatting output: {text}"
            )
            assert "infinity" not in text, (
                f"Calculation propagated Infinity into formatting output: {text}"
            )

    except Exception as e:
        print(f"Test PW-TEL-03 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_tel_03")
        raise
    finally:
        _save_coverage(cdp_session, "pw_tel_03")
