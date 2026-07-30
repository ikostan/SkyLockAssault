# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/fuel_depletion_test.py
"""
Fuel Depletion Test (Playwright, Python)
=======================================

Overview
--------
Validates that fuel depletes strictly and monotonically under difficulty 2.0.
Drives the Godot HTML5 export via DOM overlays and directly samples `window.currentFuel`
exposed via the JavaScript bridge.
"""

import json
import os
import time
from typing import Any

from playwright.sync_api import Page, expect

from tests.test_utils import (
    DEFAULT_TIMEOUT,
    start_game_and_wait_ready,
)


def test_fuel_depletion(shared_page: Page) -> None:
    """
    Validate fuel depletes monotonically under difficulty 2.0 after starting the level.

    Navigates menus via DOM overlays/callbacks, sets difficulty to 2.0, starts
    the game, and samples `window.currentFuel` over time to verify depletion rate
    and monotonicity.
    """
    page = shared_page
    logs: list[dict[str, str]] = []

    def on_console(msg: Any) -> None:
        """Console message handler to capture logs."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    cdp_session = None
    coverage_started = False

    try:
        # 1. Initialize CDP coverage, load page, configure settings & start game
        cdp_session, coverage_started = start_game_and_wait_ready(
            page=page,
            logs=logs,
            difficulty=2.0,
            log_level="DEBUG",
        )

        # 2. Verify canvas visibility
        canvas = page.locator("canvas")
        expect(canvas).to_be_visible(timeout=DEFAULT_TIMEOUT)

        # 3. Focus Canvas and sample window.currentFuel deterministically as it ticks
        canvas.focus()

        # Wait deterministically until window.currentFuel is initialized
        page.wait_for_function(
            "() => typeof window.currentFuel === 'number'",
            timeout=DEFAULT_TIMEOUT,
        )

        fuel_samples: list[float] = []
        sample_count = 5

        # Record initial reading
        last_val = float(page.evaluate("() => window.currentFuel"))
        fuel_samples.append(last_val)

        # Collect subsequent samples by waiting for value updates (ticks)
        for _ in range(sample_count - 1):
            page.wait_for_function(
                f"() => typeof window.currentFuel === 'number' "
                f"&& window.currentFuel !== {last_val}",
                timeout=DEFAULT_TIMEOUT,
            )
            last_val = float(page.evaluate("() => window.currentFuel"))
            fuel_samples.append(last_val)

        # Sanity check: fuel values must be numeric and within [0, 100]
        for fuel in fuel_samples:
            assert 0.0 <= fuel <= 100.0, f"Fuel out of expected range [0, 100]: {fuel}"

        # Monotonic decrease check: fuel must strictly decrease over time
        for earlier, later in zip(fuel_samples, fuel_samples[1:]):
            assert (
                later < earlier
            ), f"Fuel did not strictly decrease: {earlier} -> {later}"

        # Depletion rate check: total drop across 4 ticks at cruise speed (~2.8 units)
        total_drop = fuel_samples[0] - fuel_samples[-1]
        assert total_drop >= 2.5, (
            f"Fuel did not deplete enough for difficulty 2.0: "
            f"drop={total_drop}, samples={fuel_samples}"
        )

    except Exception as e:
        print(f"Test suite failed: {str(e)}")
        os.makedirs("artifacts", exist_ok=True)
        timestamp: int = int(time.time())
        page.screenshot(path=f"artifacts/test_fuel_depletion_failure_{timestamp}.png")
        log_file = f"artifacts/test_fuel_depletion_failure_console_logs_{timestamp}.txt"
        with open(log_file, "w", encoding="utf-8") as f:
            for log in logs:
                f.write(f"[{log['type']}] {log['text']}\n")
        raise
    finally:
        if cdp_session and coverage_started:
            try:
                coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
                cdp_session.send("Profiler.stopPreciseCoverage")
                cdp_session.send("Profiler.disable")
                with open(
                    "v8_coverage_fuel_depletion_test.json", "w", encoding="utf-8"
                ) as f:
                    json.dump(coverage, f)
            except Exception as cov_err:
                print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")
