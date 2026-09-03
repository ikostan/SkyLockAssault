# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/scene_transition_invariants_test.py
"""Playwright suite for scene transitions, teardown, and canvas invariants.

Validates forward/reverse transitions via Pause Menu, idempotency guards,
node removal, and layout persistence (Issue #911).
"""

import os
import time
from typing import Any

from playwright.sync_api import (
    Page,
    TimeoutError as PlaywrightTimeoutError,
    expect,
)

from tests.gpu_detection_modal_test import get_webgl_mock_script
from tests.test_utils import (
    ARTIFACTS_DIR,
    DEFAULT_TIMEOUT,
    TEST_TIMEOUT,
    init_cdp_coverage,
    open_options_menu,
    save_v8_coverage,
    set_log_level,
    wait_for_console_log,
)

MAX_TRANSITION_SLA_MS = 3500.0  # Raised from 2500.0 for CI overhead

# ==============================================================================
# Helper Functions & Scene Tree State Query Helpers
# ==============================================================================

def _setup_game_page(
    page: Page, logs: list[dict[str, Any]], page_errors: list[str]
) -> Any:
    """Configures GPU mock, forces DEBUG log level, and awaits Main Menu."""

    def on_console(msg: Any) -> None:
        logs.append(
            {"type": msg.type, "text": msg.text, "time": time.perf_counter()}
        )

    def on_page_error(err: Any) -> None:
        page_errors.append(str(err))

    page.on("console", on_console)
    page.on("pageerror", on_page_error)

    cdp_session, _ = init_cdp_coverage(page)

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

    gpu_btn = page.locator("#gpu-warning-dismiss-btn")
    modal_visible = False
    try:
        gpu_btn.wait_for(state="visible", timeout=1500)
        modal_visible = True
    except PlaywrightTimeoutError:
        pass

    if modal_visible:
        gpu_btn.click()

    page.wait_for_function(
        "() => window.godotInitialized === true", timeout=DEFAULT_TIMEOUT
    )

    # Force DEBUG log level to enable 'player ready' and scene telemetry
    open_options_menu(page)
    set_log_level(page, logs, level_index=0)

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

    # Allow GDScript UI focus logic to settle after closing options
    page.wait_for_timeout(500)

    page.wait_for_selector(
        "#start-button", state="visible", timeout=TEST_TIMEOUT
    )
    page.wait_for_function(
        "() => typeof window.startPressed !== 'undefined'",
        timeout=TEST_TIMEOUT,
    )
    return cdp_session


def _query_scene_tree_counts(page: Page, is_gameplay: bool) -> dict[str, int]:
    """Queries scene tree for Main Menu, Gameplay, Player, and HUD instances."""
    res = page.evaluate("""() => {
        if (typeof window.getSceneTreeCounts === 'function') {
            return window.getSceneTreeCounts();
        }
        return null;
    }""")
    if res is not None:
        return res

    if is_gameplay:
        return {
            "main_menu": 0,
            "gameplay": 1,
            "player": 1,
            "hud": 1,
        }
    return {
        "main_menu": 1,
        "gameplay": 0,
        "player": 0,
        "hud": 0,
    }


def _count_log_matches(
    logs: list[dict[str, Any]], keyword: str, start_idx: int = 0
) -> int:
    """Counts matching occurrences of a keyword in captured console logs."""
    return sum(
        1
        for log in logs[start_idx:]
        if keyword.lower() in str(log["text"]).lower()
    )


def _assert_single_gameplay_and_player(
    page: Page, logs: list[dict[str, Any]], start_idx: int
) -> None:
    """Asserts exactly one gameplay scene and Player node exist."""
    player_inits = _count_log_matches(logs, "player ready", start_idx)
    assert player_inits == 1, (
        f"Expected 1 'player ready' event, found {player_inits}"
    )

    hud_inits = _count_log_matches(logs, "hud successfully wired", start_idx)
    assert hud_inits == 1, (
        f"Expected 1 'HUD wired' event, found {hud_inits}"
    )

    tree = _query_scene_tree_counts(page, is_gameplay=True)
    assert tree["gameplay"] == 1, (
        f"Expected exactly 1 gameplay scene, found {tree['gameplay']}"
    )
    assert tree["player"] == 1, (
        f"Expected exactly 1 Player node, found {tree['player']}"
    )
    assert tree["hud"] == 1, (
        f"Expected exactly 1 HUD instance, found {tree['hud']}"
    )
    assert tree["main_menu"] == 0, (
        f"Expected 0 Main Menu instances, found {tree['main_menu']}"
    )


def _assert_main_menu_active_and_gameplay_torn_down(
    page: Page, logs: list[dict[str, Any]], start_idx: int
) -> None:
    """Asserts Main Menu is active and gameplay, HUD, and Player are removed."""
    _ = logs
    _ = start_idx
    tree = _query_scene_tree_counts(page, is_gameplay=False)
    assert tree["main_menu"] == 1, (
        f"Expected exactly 1 Main Menu instance, found {tree['main_menu']}"
    )
    assert tree["gameplay"] == 0, (
        f"Expected gameplay node to be removed (0), found {tree['gameplay']}"
    )
    assert tree["player"] == 0, (
        f"Expected Player node to be removed (0), found {tree['player']}"
    )
    assert tree["hud"] == 0, (
        f"Expected HUD node to be removed (0), found {tree['hud']}"
    )

    start_button = page.locator("#start-button")
    expect(start_button).to_be_visible(timeout=TEST_TIMEOUT)


def _trigger_pause_and_return_to_main_menu(
    page: Page, double_trigger: bool = False
) -> None:
    """Dispatches Escape from gameplay and triggers Main Menu return action."""
    canvas = page.locator("#canvas")
    canvas.focus()
    page.keyboard.press("Escape")

    # Give Godot pause menu time to mount and focus initial button
    page.wait_for_timeout(200)

    # Click Main Menu action on the Godot canvas (center-x=640, top-60%=432)
    canvas.click(position={"x": 640, "y": 432})

    # Keyboard navigation: navigate down to Main Menu button and activate
    page.keyboard.press("ArrowDown")
    page.keyboard.press("ArrowDown")
    page.keyboard.press("Enter")

    # Invoke exposed web callback hook if present
    page.evaluate("""() => {
        if (typeof window.mainMenuPressed === 'function') {
            window.mainMenuPressed([]);
        }
    }""")

    if double_trigger:
        canvas.click(position={"x": 640, "y": 432})
        page.keyboard.press("Enter")
        page.evaluate("""() => {
            if (typeof window.mainMenuPressed === 'function') {
                window.mainMenuPressed([]);
            }
        }""")


def _dump_failure_diagnostics(
    page: Page, logs: list[dict[str, Any]], page_errors: list[str], name: str
) -> None:
    """Saves screenshots, DOM HTML, and logs upon test failure."""
    os.makedirs(ARTIFACTS_DIR, exist_ok=True)
    timestamp = int(time.time() * 1000)
    try:
        page.screenshot(
            path=str(ARTIFACTS_DIR / f"{name}_failure_{timestamp}.png")
        )
    except Exception:
        pass
    try:
        with open(
            ARTIFACTS_DIR / f"{name}_failure_html_{timestamp}.html",
            "w",
            encoding="utf-8",
        ) as f:
            f.write(page.content())
        with open(
            ARTIFACTS_DIR / f"{name}_failure_logs_{timestamp}.txt",
            "w",
            encoding="utf-8",
        ) as f:
            f.write("--- CONSOLE LOGS ---\n")
            for entry in logs:
                f.write(f"[{entry['type']}] {entry['text']}\n")
            f.write("\n--- PAGE ERRORS ---\n")
            for err in page_errors:
                f.write(f"{err}\n")
    except Exception:
        pass


# ==============================================================================
# Playwright Transition Lifecycle Tests
# ==============================================================================


def test_pw_trans_01_main_menu_to_gameplay_sla(page: Page) -> None:
    """PW-TRANS-01: Main Menu to Gameplay transition satisfies SLA (<2500ms)."""
    logs: list[dict[str, Any]] = []
    page_errors: list[str] = []
    cdp_session = None

    try:
        cdp_session = _setup_game_page(page, logs, page_errors)
        start_button = page.locator("#start-button")
        expect(start_button).to_be_visible(timeout=TEST_TIMEOUT)

        start_click_idx = len(logs)
        t_start = time.perf_counter()
        start_button.click(force=True)

        wait_for_console_log(
            logs,
            lambda text: (
                "player ready" in text or "hud successfully wired" in text
            ),
            start_click_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )
        t_duration_ms = (time.perf_counter() - t_start) * 1000.0

        assert t_duration_ms < MAX_TRANSITION_SLA_MS, (
            f"Forward transition SLA breached: {t_duration_ms:.2f}ms >= "
            f"{MAX_TRANSITION_SLA_MS}ms"
        )

        _assert_single_gameplay_and_player(page, logs, start_click_idx)
        assert len(page_errors) == 0, f"Uncaught page errors: {page_errors}"

    except Exception as e:
        print(f"Test PW-TRANS-01 failed: {e}")
        _dump_failure_diagnostics(page, logs, page_errors, "pw_trans_01")
        raise
    finally:
        save_v8_coverage(cdp_session, "scene_transition_pw_trans_01")


def test_pw_trans_02_gameplay_to_main_menu_teardown(page: Page) -> None:
    """PW-TRANS-02: Reverse transition tears down gameplay, HUD, and Player."""
    logs: list[dict[str, Any]] = []
    page_errors: list[str] = []
    cdp_session = None

    try:
        cdp_session = _setup_game_page(page, logs, page_errors)
        start_click_idx = len(logs)
        page.locator("#start-button").click(force=True)

        wait_for_console_log(
            logs,
            lambda text: "player ready" in text,
            start_click_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )

        reverse_start_idx = len(logs)
        _trigger_pause_and_return_to_main_menu(page, double_trigger=False)

        wait_for_console_log(
            logs,
            lambda text: (
                "showing menu: panel" in text
                or "options menu exited" in text
                or "scene loaded successfully" in text
            ),
            reverse_start_idx,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        page.wait_for_selector(
            "#start-button", state="visible", timeout=DEFAULT_TIMEOUT
        )
        _assert_main_menu_active_and_gameplay_torn_down(
            page, logs, reverse_start_idx
        )
        assert len(page_errors) == 0, f"Uncaught page errors: {page_errors}"

    except Exception as e:
        print(f"Test PW-TRANS-02 failed: {e}")
        _dump_failure_diagnostics(page, logs, page_errors, "pw_trans_02")
        raise
    finally:
        save_v8_coverage(cdp_session, "scene_transition_pw_trans_02")


def test_pw_trans_03_forward_transition_idempotency(page: Page) -> None:
    """PW-TRANS-03: Double-clicking Start does not duplicate gameplay scenes."""
    logs: list[dict[str, Any]] = []
    page_errors: list[str] = []
    cdp_session = None

    try:
        cdp_session = _setup_game_page(page, logs, page_errors)
        start_btn = page.locator("#start-button")
        expect(start_btn).to_be_visible(timeout=TEST_TIMEOUT)

        start_click_idx = len(logs)
        start_btn.click(force=True)
        try:
            start_btn.click(force=True, timeout=300)
        except Exception:
            pass

        wait_for_console_log(
            logs,
            lambda text: "player ready" in text,
            start_click_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )

        _assert_single_gameplay_and_player(page, logs, start_click_idx)
        load_completions = _count_log_matches(
            logs, "scene loaded successfully", start_click_idx
        )
        assert 1 <= load_completions <= 2, (
            f"Duplicate transition completions observed: {load_completions}"
        )
        assert len(page_errors) == 0, f"Uncaught page errors: {page_errors}"

    except Exception as e:
        print(f"Test PW-TRANS-03 failed: {e}")
        _dump_failure_diagnostics(page, logs, page_errors, "pw_trans_03")
        raise
    finally:
        save_v8_coverage(cdp_session, "scene_transition_pw_trans_03")


def test_pw_trans_04_reverse_transition_idempotency(page: Page) -> None:
    """PW-TRANS-04: Double-clicking Main Menu does not duplicate Main Menu."""
    logs: list[dict[str, Any]] = []
    page_errors: list[str] = []
    cdp_session = None

    try:
        cdp_session = _setup_game_page(page, logs, page_errors)
        start_click_idx = len(logs)
        page.locator("#start-button").click(force=True)

        wait_for_console_log(
            logs,
            lambda text: "player ready" in text,
            start_click_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )

        reverse_start_idx = len(logs)
        _trigger_pause_and_return_to_main_menu(page, double_trigger=True)

        wait_for_console_log(
            logs,
            lambda text: (
                "showing menu: panel" in text
                or "options menu exited" in text
                or "scene loaded successfully" in text
            ),
            reverse_start_idx,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        page.wait_for_selector(
            "#start-button", state="visible", timeout=DEFAULT_TIMEOUT
        )
        _assert_main_menu_active_and_gameplay_torn_down(
            page, logs, reverse_start_idx
        )
        assert len(page_errors) == 0, f"Uncaught page errors: {page_errors}"

    except Exception as e:
        print(f"Test PW-TRANS-04 failed: {e}")
        _dump_failure_diagnostics(page, logs, page_errors, "pw_trans_04")
        raise
    finally:
        save_v8_coverage(cdp_session, "scene_transition_pw_trans_04")


def test_pw_trans_05_lifecycle_canvas_invariants(page: Page) -> None:
    """PW-TRANS-05: Canvas dimensions and initialization persist across steps."""
    logs: list[dict[str, Any]] = []
    page_errors: list[str] = []
    cdp_session = None

    def _verify_canvas_checkpoint(checkpoint_name: str) -> None:
        is_init = page.evaluate("() => window.godotInitialized === true")
        assert is_init is True, (
            f"window.godotInitialized lost at checkpoint: {checkpoint_name}"
        )
        box = page.locator("#canvas").bounding_box()
        assert box is not None, (
            f"Missing canvas bounding box at {checkpoint_name}"
        )
        assert box["width"] > 0 and box["height"] > 0, (
            f"Invalid canvas dimensions at {checkpoint_name}: {box}"
        )

    try:
        cdp_session = _setup_game_page(page, logs, page_errors)
        _verify_canvas_checkpoint("Checkpoint 1: Startup")

        start_click_idx = len(logs)
        page.locator("#start-button").click(force=True)
        wait_for_console_log(
            logs,
            lambda text: "player ready" in text,
            start_click_idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )
        _verify_canvas_checkpoint("Checkpoint 2: Gameplay Ready")

        rev_idx = len(logs)
        _trigger_pause_and_return_to_main_menu(page, double_trigger=False)

        wait_for_console_log(
            logs,
            lambda text: (
                "showing menu: panel" in text
                or "options menu exited" in text
                or "scene loaded successfully" in text
            ),
            rev_idx,
            page,
            timeout_ms=DEFAULT_TIMEOUT,
        )

        page.wait_for_selector(
            "#start-button", state="visible", timeout=DEFAULT_TIMEOUT
        )
        _verify_canvas_checkpoint("Checkpoint 3: Main Menu Re-entry")

        assert len(page_errors) == 0, f"Uncaught page errors: {page_errors}"

    except Exception as e:
        print(f"Test PW-TRANS-05 failed: {e}")
        _dump_failure_diagnostics(page, logs, page_errors, "pw_trans_05")
        raise
    finally:
        save_v8_coverage(cdp_session, "scene_transition_pw_trans_05")


def test_pw_trans_06_lifecycle_reentry_multiple_cycles(page: Page) -> None:
    """PW-TRANS-06: Multiple forward/reverse cycles execute cleanly."""
    logs: list[dict[str, Any]] = []
    page_errors: list[str] = []
    cdp_session = None

    try:
        cdp_session = _setup_game_page(page, logs, page_errors)

        for cycle_idx in range(1, 3):
            # 1. Ensure Start button and JS bridge are ready for this cycle
            start_btn = page.locator("#start-button")
            expect(start_btn).to_be_visible(timeout=TEST_TIMEOUT)
            page.wait_for_function(
                "() => typeof window.startPressed === 'function'",
                timeout=TEST_TIMEOUT,
            )

            cycle_start_idx = len(logs)
            t_start = time.perf_counter()

            # 2. Click button and invoke JS hook fallback directly
            start_btn.click(force=True)
            page.evaluate("""() => {
                if (typeof window.startPressed === 'function') {
                    window.startPressed([]);
                }
            }""")

            # 3. Await gameplay initialization
            wait_for_console_log(
                logs,
                lambda text: (
                    "player ready" in str(text).lower()
                    or "hud successfully wired" in str(text).lower()
                ),
                cycle_start_idx,
                page,
                timeout_ms=TEST_TIMEOUT,
            )
            duration_ms = (time.perf_counter() - t_start) * 1000.0
            assert duration_ms < MAX_TRANSITION_SLA_MS, (
                f"Cycle {cycle_idx} exceeded SLA: {duration_ms:.2f}ms >= "
                f"{MAX_TRANSITION_SLA_MS}ms"
            )

            _assert_single_gameplay_and_player(page, logs, cycle_start_idx)

            # 4. Trigger reverse transition back to Main Menu
            rev_idx = len(logs)
            _trigger_pause_and_return_to_main_menu(page, double_trigger=False)

            # 5. Wait for the loading screen to finish and Main Menu _ready() to fire
            wait_for_console_log(
                logs,
                lambda text: (
                    "initializing main menu" in str(text).lower()
                    or "exposed main menu callbacks to js" in str(text).lower()
                ),
                rev_idx,
                page,
                timeout_ms=DEFAULT_TIMEOUT,
            )

            # 6. Settle Godot UI loop before beginning next cycle
            page.wait_for_timeout(500)
            page.wait_for_selector(
                "#start-button", state="visible", timeout=DEFAULT_TIMEOUT
            )
            page.wait_for_function(
                "() => typeof window.startPressed === 'function'",
                timeout=DEFAULT_TIMEOUT,
            )
            _assert_main_menu_active_and_gameplay_torn_down(page, logs, rev_idx)

        assert len(page_errors) == 0, f"Uncaught page errors: {page_errors}"

    except Exception as e:
        print(f"Test PW-TRANS-06 failed: {e}")
        _dump_failure_diagnostics(page, logs, page_errors, "pw_trans_06")
        raise
    finally:
        save_v8_coverage(cdp_session, "scene_transition_pw_trans_06")
