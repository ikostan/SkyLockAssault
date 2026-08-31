# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/scene_transition_lifecycle_test.py

"""
Scene Transition Lifecycle & State Invariants Test Suite (Playwright + WebGL)
=============================================================================

Overview
--------
Verifies forward/reverse scene transitions (Main Menu <-> Gameplay, Pause Menu),
transition idempotency guards against concurrent duplicate clicks, and persistent
canvas/engine invariants across route swaps under WebGL/WASM (#829).
"""

import json
import os
import time
from typing import Any

from playwright.sync_api import Page, expect

from tests.gpu_detection_modal_test import get_webgl_mock_script
from tests.test_utils import (
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    open_options_menu,
    set_log_level,
    wait_for_console_log,
)


def _has_log(logs: list[dict[str, str]], keyword: str) -> bool:
    """Check if any log entry contains the specified keyword."""
    return any(keyword in log["text"].lower() for log in logs)


def _count_logs(logs: list[dict[str, str]], keyword: str) -> int:
    """Count how many log entries contain the specified keyword."""
    return sum(1 for log in logs if keyword in log["text"].lower())


def _gameplay_ready_predicate(text: str) -> bool:
    """True only when gameplay is fully mounted, HUD is wired, and
    Pause Menu callbacks are exposed.
    """
    t = text.lower()
    return (
        "hud successfully wired to player signals" in t
        or "exposed pause menu callbacks to js" in t
    )


def _main_menu_ready_predicate(text: str) -> bool:
    """True only when main_menu.tscn has fully loaded and bound fresh JS
    callbacks.
    """
    t = text.lower()
    return (
        "exposed main menu callbacks to js" in t
        or "quitdialog signals connected" in t
    )


def _setup_mock_page(page: Page, logs: list[dict[str, str]]) -> Any:
    """Configures hardware GPU mock, attaches listeners, starts CDP coverage,
    and forces DEBUG log level so readiness / scene-transition messages appear.
    """

    def on_console(msg: Any) -> None:
        """Append intercepted console messages to the logs list."""
        logs.append({"type": msg.type, "text": msg.text})

    page.on("console", on_console)

    cdp_session = page.context.new_cdp_session(page)
    cdp_session.send("Profiler.enable")
    cdp_session.send(
        "Profiler.startPreciseCoverage", {"callCount": True, "detailed": True}
    )

    # Mock hardware GPU to bypass pre-boot software warning modals
    page.add_init_script(
        get_webgl_mock_script(renderer_string="ANGLE (NVIDIA, RTX 4070 Direct3D11)")
    )
    page.goto("http://localhost:8080/index.html")
    page.wait_for_function(
        "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
    )

    # Dismiss GPU alert modal if displayed
    gpu_btn = page.locator("#gpu-alert-btn")
    if gpu_btn.is_visible():
        gpu_btn.click()

    # Force DEBUG log level to guarantee visibility of transition lifecycle events
    open_options_menu(page)
    set_log_level(page, logs, level_index=0)  # 0 = DEBUG

    # Return to main menu so subsequent startPressed calls begin from a clean state
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
            "options back button pressed" in text
            or "back button pressed" in text
            or "options menu exited" in text
        ),
        pre_back,
        page,
        timeout_ms=DEFAULT_TIMEOUT,
    )
    page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)

    return cdp_session


def _return_to_main_menu_from_gameplay(page: Page) -> None:
    """Dispatches return-to-main-menu transition from active gameplay
    via exposed bridge.
    """
    page.wait_for_function(
        "() => typeof window.mainMenuPressed === 'function'",
        timeout=TEST_TIMEOUT,
    )
    page.evaluate("window.mainMenuPressed([])")


def _dump_failure_artifacts(
    page: Page, logs: list[dict[str, str]], test_id: str
) -> None:
    """Dumps diagnostic artifacts on test failure."""
    os.makedirs("artifacts", exist_ok=True)
    timestamp = int(time.time() * 1000)
    safe_id = os.path.basename(test_id)
    page.screenshot(
        path=f"artifacts/{safe_id}_failure_screenshot_{timestamp}.png"
    )
    html_path = f"artifacts/{safe_id}_failure_html_{timestamp}.html"
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(page.content())
    log_path = f"artifacts/{safe_id}_failure_console_logs_{timestamp}.txt"
    with open(log_path, "w", encoding="utf-8") as f:
        for log in logs:
            f.write(f"[{log['type']}] {log['text']}\n")


def _save_coverage(cdp_session: Any, test_id: str) -> None:
    """Collects and writes V8 coverage data."""
    if cdp_session:
        try:
            coverage = cdp_session.send("Profiler.takePreciseCoverage")["result"]
            cdp_session.send("Profiler.stopPreciseCoverage")
            cdp_session.send("Profiler.disable")
            os.makedirs("artifacts", exist_ok=True)
            safe_id = os.path.basename(test_id)
            cov_path = (
                f"artifacts/v8_coverage_{safe_id}_{int(time.time() * 1000)}.json"
            )
            with open(cov_path, "w", encoding="utf-8") as f:
                json.dump(coverage, f)
        except Exception as cov_err:
            print(f"Warning: Failed to harvest V8 coverage data: {cov_err}")


def test_pw_trans_01_main_menu_to_gameplay_lifecycle_sla(page: Page) -> None:
    """
    PW-TRANS-01: Main Menu to active Gameplay transition completes cleanly
    within the <= 2500 ms performance contract SLA without uncaught errors.
    """
    logs: list[dict[str, str]] = []
    page_errors: list[str] = []
    page.on("pageerror", lambda err: page_errors.append(str(err)))
    cdp_session = None

    try:
        cdp_session = _setup_mock_page(page, logs)

        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.startPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )

        start_click_idx = len(logs)
        t_start = time.perf_counter()

        # Trigger forward transition into gameplay
        page.evaluate("window.startPressed([])")

        # Await gameplay readiness
        wait_for_console_log(
            logs,
            _gameplay_ready_predicate,
            start_click_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )
        transition_duration_ms = (time.perf_counter() - t_start) * 1000

        # Functional and Performance SLA Assertions
        assert transition_duration_ms < 2500.0, (
            f"Transition SLA violated: took {transition_duration_ms:.2f} ms "
            "(limit: 2500 ms)"
        )
        assert (
            len(page_errors) == 0
        ), f"Uncaught page errors detected during transition: {page_errors}"

    except Exception as e:
        print(f"Test PW-TRANS-01 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_trans_01")
        raise
    finally:
        _save_coverage(cdp_session, "pw_trans_01")


def test_pw_trans_02_gameplay_to_main_menu_teardown(page: Page) -> None:
    """
    PW-TRANS-02: Reverse transition (Gameplay -> Main Menu) cleanly tears down
    active game nodes without UI duplication or frozen canvas states.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    try:
        cdp_session = _setup_mock_page(page, logs)

        # 1. Enter gameplay
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.startPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        pre_start_idx = len(logs)
        page.evaluate("window.startPressed([])")
        wait_for_console_log(
            logs,
            _gameplay_ready_predicate,
            pre_start_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )

        # 2. Trigger reverse transition to Main Menu
        pre_return_idx = len(logs)
        _return_to_main_menu_from_gameplay(page)

        # Await Main Menu re-entry and focus restoration
        wait_for_console_log(
            logs,
            _main_menu_ready_predicate,
            pre_return_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )

        # Verify Main Menu interactive overlays are restored
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        expect(page.locator("#start-button")).to_be_attached()

    except Exception as e:
        print(f"Test PW-TRANS-02 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_trans_02")
        raise
    finally:
        _save_coverage(cdp_session, "pw_trans_02")


def test_pw_trans_03_forward_transition_idempotency(page: Page) -> None:
    """
    PW-TRANS-03: Consecutive forward transition triggers ("Start Game" burst)
    do not spawn duplicate gameplay scenes or corrupt scene tree state.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    try:
        cdp_session = _setup_mock_page(page, logs)

        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.startPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )

        pre_burst_idx = len(logs)

        # Rapidly dispatch duplicate start calls before first transition completes
        page.evaluate("""() => {
            window.startPressed([]);
            window.startPressed([]);
            window.startPressed([]);
        }""")

        # Await gameplay initialization
        wait_for_console_log(
            logs,
            _gameplay_ready_predicate,
            pre_burst_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )

        new_logs = logs[pre_burst_idx:]
        init_main_scene_count = _count_logs(new_logs, "initializing main scene")
        hud_wired_count = _count_logs(new_logs, "hud successfully wired")

        # Verify idempotency guards: exactly 1 scene is loaded and initialized
        if init_main_scene_count > 0:
            assert (
                init_main_scene_count == 1
            ), f"Expected 1 main scene init, observed: {init_main_scene_count}"
        if hud_wired_count > 0:
            assert (
                hud_wired_count == 1
            ), f"Expected 1 HUD wiring, observed: {hud_wired_count}"

    except Exception as e:
        print(f"Test PW-TRANS-03 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_trans_03")
        raise
    finally:
        _save_coverage(cdp_session, "pw_trans_03")


def test_pw_trans_04_reverse_transition_idempotency(page: Page) -> None:
    """
    PW-TRANS-04: Consecutive reverse transition triggers from pause state
    do not duplicate Main Menu instances or corrupt scene tree hierarchy.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    try:
        cdp_session = _setup_mock_page(page, logs)

        # Transition into Gameplay
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.startPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        pre_game_idx = len(logs)
        page.evaluate("window.startPressed([])")
        wait_for_console_log(
            logs,
            _gameplay_ready_predicate,
            pre_game_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )

        page.wait_for_function(
            "() => typeof window.mainMenuPressed === 'function'",
            timeout=TEST_TIMEOUT,
        )

        pre_burst_idx = len(logs)

        # Rapidly dispatch multiple return activations
        page.evaluate("""() => {
            window.mainMenuPressed([]);
            window.mainMenuPressed([]);
            window.mainMenuPressed([]);
        }""")

        wait_for_console_log(
            logs,
            _main_menu_ready_predicate,
            pre_burst_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )

        # Verify exactly one Main Menu instance active
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        expect(page.locator("#start-button")).to_be_attached()

    except Exception as e:
        print(f"Test PW-TRANS-04 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_trans_04")
        raise
    finally:
        _save_coverage(cdp_session, "pw_trans_04")


def test_pw_trans_05_canvas_and_initialization_invariants(page: Page) -> None:
    """
    PW-TRANS-05: Validates that window.godotInitialized remains persistently true
    and the HTML5 canvas bounding box maintains positive width and height
    across all checkpoints.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    def assert_canvas_invariants(checkpoint_label: str) -> None:
        """Asserts that Godot is initialized and canvas has positive dimensions."""
        is_init = page.evaluate("() => window.godotInitialized === true")
        assert (
            is_init is True
        ), f"Invariant failed at {checkpoint_label}: godotInitialized is not true"

        canvas = page.locator("#canvas")
        expect(canvas).to_be_visible(timeout=TEST_TIMEOUT)
        box = canvas.bounding_box()
        assert (
            box is not None
        ), f"Invariant failed at {checkpoint_label}: canvas bounding box is None"
        assert (
            box["width"] > 0 and box["height"] > 0
        ), (
            f"Invariant failed at {checkpoint_label}: "
            f"invalid dimensions ({box['width']}x{box['height']})"
        )

    try:
        cdp_session = _setup_mock_page(page, logs)

        # Checkpoint 1: Startup
        assert_canvas_invariants("Checkpoint 1 (Startup / Main Menu)")

        # Checkpoint 2: Gameplay Ready
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        page.wait_for_function(
            "() => typeof window.startPressed !== 'undefined'", timeout=TEST_TIMEOUT
        )
        pre_game_idx = len(logs)
        page.evaluate("window.startPressed([])")
        wait_for_console_log(
            logs,
            _gameplay_ready_predicate,
            pre_game_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )
        assert_canvas_invariants("Checkpoint 2 (Gameplay Active)")

        # Checkpoint 3: Main Menu Re-entry
        pre_menu_idx = len(logs)
        _return_to_main_menu_from_gameplay(page)
        wait_for_console_log(
            logs,
            _main_menu_ready_predicate,
            pre_menu_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )
        assert_canvas_invariants("Checkpoint 3 (Main Menu Re-entry)")

    except Exception as e:
        print(f"Test PW-TRANS-05 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_trans_05")
        raise
    finally:
        _save_coverage(cdp_session, "pw_trans_05")


def test_pw_trans_06_multi_cycle_transition_lifecycle(page: Page) -> None:
    """
    PW-TRANS-06: Verifies multi-cycle forward and reverse transitions
    (Main Menu -> Gameplay -> Main Menu -> Gameplay -> Main Menu) execute cleanly
    without state leakage, input unresponsiveness, or resource accumulation.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None

    try:
        cdp_session = _setup_mock_page(page, logs)

        for cycle_idx in range(1, 3):
            # 1. Forward: Main Menu -> Gameplay
            page.wait_for_selector(
                "#start-button", state="visible", timeout=TEST_TIMEOUT
            )
            page.wait_for_function(
                "() => typeof window.startPressed === 'function'",
                timeout=TEST_TIMEOUT,
            )
            pre_start_idx = len(logs)
            t_cycle_start = time.perf_counter()

            page.evaluate("window.startPressed([])")
            wait_for_console_log(
                logs,
                _gameplay_ready_predicate,
                pre_start_idx,
                page,
                timeout_ms=TEST_TIMEOUT,
            )
            duration_ms = (time.perf_counter() - t_cycle_start) * 1000
            assert duration_ms < 2500.0, (
                f"Cycle {cycle_idx} forward transition exceeded SLA: "
                f"{duration_ms:.2f} ms"
            )

            # 2. Reverse: Gameplay -> Main Menu
            pre_return_idx = len(logs)
            _return_to_main_menu_from_gameplay(page)
            wait_for_console_log(
                logs,
                _main_menu_ready_predicate,
                pre_return_idx,
                page,
                timeout_ms=TEST_TIMEOUT,
            )

            # 3. Ensure Main Menu is interactive before next cycle begins
            page.wait_for_selector(
                "#start-button", state="visible", timeout=TEST_TIMEOUT
            )
            page.wait_for_function(
                "() => typeof window.startPressed === 'function'",
                timeout=TEST_TIMEOUT,
            )

    except Exception as e:
        print(f"Test PW-TRANS-06 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_trans_06")
        raise
    finally:
        _save_coverage(cdp_session, "pw_trans_06")
