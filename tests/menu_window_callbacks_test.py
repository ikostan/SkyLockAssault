# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/menu_window_callbacks_test.py
"""
Menu Window Callback Lifecycle Tests (#1166)
============================================

Menus register ``window.*`` callbacks so Playwright can drive them. When a menu
is freed, its callbacks must be set to ``null``, and a new instance of the
same menu must keep working.

- PW-CB-01: Main and Pause callbacks across two game cycles.
- PW-CB-02: Options and Controls callbacks after Back, and after reopening.
- PW-CB-03: Options and Controls reopened in the same frame as their Back.

Prerequisites
-------------
- http://localhost:8080/index.html (HTML5 export with overlays).

Running
-------
pytest tests/menu_window_callbacks_test.py -q
"""

from playwright.sync_api import Page

from tests.scene_transition_lifecycle_test import (
    _dump_failure_artifacts,
    _gameplay_ready_predicate,
    _main_menu_ready_predicate,
    _return_to_main_menu_from_gameplay,
    _save_coverage,
    _setup_mock_page,
)
from tests.test_utils import TEST_TIMEOUT, open_options_menu, wait_for_console_log

MAIN_MENU_CALLBACKS: tuple[str, ...] = ("startPressed", "optionsPressed", "quitPressed")
PAUSE_MENU_CALLBACKS: tuple[str, ...] = (
    "togglePause",
    "mainMenuPressed",
    "resumePressed",
    "pauseOptionsPressed",
)
OPTIONS_MENU_CALLBACKS: tuple[str, ...] = (
    "optionsBackPressed",
    "controlsPressed",
    "audioPressed",
    "advancedPressed",
    "gameplayPressed",
)
KEY_MAPPING_CALLBACKS: tuple[str, ...] = ("controlsBackPressed",)


def _callback_states(page: Page, names: tuple[str, ...]) -> dict[str, str]:
    """Return 'null', 'undefined' or the typeof of each window callback."""
    return page.evaluate(
        "(names) => Object.fromEntries(names.map((n) => "
        "[n, window[n] === null ? 'null' : typeof window[n]]))",
        list(names),
    )


def _assert_callbacks(page: Page, names: tuple[str, ...], state: str, when: str) -> None:
    """Assert every named window callback is in the given state."""
    states = _callback_states(page, names)
    wrong = {name: s for name, s in states.items() if s != state}
    assert not wrong, f"{when}: expected {state} for {list(names)}, got {wrong}"


def _start_game(page: Page, logs: list[dict[str, str]]) -> None:
    """Press Start on the main menu and wait until gameplay is wired."""
    page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
    page.wait_for_function(
        "() => typeof window.startPressed === 'function'", timeout=TEST_TIMEOUT
    )
    idx = len(logs)
    page.evaluate("window.startPressed([])")
    wait_for_console_log(
        logs, _gameplay_ready_predicate, idx, page, timeout_ms=TEST_TIMEOUT
    )


def _return_to_main_menu(page: Page, logs: list[dict[str, str]]) -> None:
    """Leave gameplay through the Pause menu's callback and wait for the main menu."""
    idx = len(logs)
    _return_to_main_menu_from_gameplay(page)
    wait_for_console_log(
        logs, _main_menu_ready_predicate, idx, page, timeout_ms=TEST_TIMEOUT
    )
    page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)


def _open_and_close_audio(page: Page) -> None:
    """Proves the Options callbacks work: Audio opens, and its Back returns."""
    page.evaluate("window.audioPressed([])")
    page.wait_for_selector("#master-slider", state="visible", timeout=TEST_TIMEOUT)
    page.evaluate("window.audioBackPressed([])")
    page.wait_for_selector("#master-slider", state="hidden", timeout=TEST_TIMEOUT)


def _open_controls(page: Page) -> None:
    """Open Key Mapping from Options and wait for its Back callback."""
    page.evaluate("window.controlsPressed([])")
    page.wait_for_selector(
        "#controls-back-button", state="visible", timeout=TEST_TIMEOUT
    )
    page.wait_for_function(
        "() => typeof window.controlsBackPressed === 'function'",
        timeout=TEST_TIMEOUT,
    )


def test_pw_cb_01_main_and_pause_callbacks_across_game_cycles(page: Page) -> None:
    """
    PW-CB-01: Starting a game clears the Main menu's callbacks; returning to the
    Main menu clears the Pause menu's and registers working Main menu callbacks;
    a second game registers working Pause callbacks.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None
    try:
        cdp_session = _setup_mock_page(page, logs)

        # Game 1
        _start_game(page, logs)
        _assert_callbacks(page, MAIN_MENU_CALLBACKS, "null", "After Start")
        _assert_callbacks(page, PAUSE_MENU_CALLBACKS, "function", "In game 1")

        _return_to_main_menu(page, logs)
        _assert_callbacks(page, PAUSE_MENU_CALLBACKS, "null", "After return to Main")
        _assert_callbacks(page, MAIN_MENU_CALLBACKS, "function", "Main menu reloaded")

        # The reloaded Main menu's callbacks work.
        open_options_menu(page)
        page.wait_for_selector(
            "#options-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        page.evaluate("window.optionsBackPressed([])")
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)

        # Game 2: the new Pause menu's callbacks work.
        _start_game(page, logs)
        _assert_callbacks(page, PAUSE_MENU_CALLBACKS, "function", "In game 2")
        idx = len(logs)
        page.evaluate("window.resumePressed([])")  # shows the Pause menu
        page.evaluate("window.resumePressed([])")  # hides it again
        wait_for_console_log(
            logs,
            lambda text: "resume button pressed" in text,
            idx,
            page,
            timeout_ms=TEST_TIMEOUT,
        )
        _return_to_main_menu(page, logs)
        _assert_callbacks(page, PAUSE_MENU_CALLBACKS, "null", "After game 2")
    except Exception as e:
        print(f"Test PW-CB-01 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_cb_01")
        raise
    finally:
        _save_coverage(cdp_session, "pw_cb_01")


def test_pw_cb_02_options_and_controls_callbacks_after_back(page: Page) -> None:
    """
    PW-CB-02: Closing Options or Controls clears their callbacks, and the
    reopened menus register working ones.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None
    try:
        # Setup opens Options and closes it with Back.
        cdp_session = _setup_mock_page(page, logs)
        _assert_callbacks(page, OPTIONS_MENU_CALLBACKS, "null", "After Options -> Back")

        open_options_menu(page)
        page.wait_for_selector(
            "#options-back-button", state="visible", timeout=TEST_TIMEOUT
        )
        _assert_callbacks(page, OPTIONS_MENU_CALLBACKS, "function", "Options reopened")

        # Controls -> Back, then reopen Controls.
        _open_controls(page)
        page.evaluate("window.controlsBackPressed([])")
        page.wait_for_selector(
            "#controls-back-button", state="hidden", timeout=TEST_TIMEOUT
        )
        _assert_callbacks(page, KEY_MAPPING_CALLBACKS, "null", "After Controls -> Back")
        _open_controls(page)
        page.evaluate("window.controlsBackPressed([])")
        page.wait_for_selector(
            "#controls-back-button", state="hidden", timeout=TEST_TIMEOUT
        )

        # The reopened Options menu's callbacks still work.
        _open_and_close_audio(page)
        page.evaluate("window.optionsBackPressed([])")
        page.wait_for_selector("#start-button", state="visible", timeout=TEST_TIMEOUT)
        _assert_callbacks(page, OPTIONS_MENU_CALLBACKS, "null", "After second Back")
    except Exception as e:
        print(f"Test PW-CB-02 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_cb_02")
        raise
    finally:
        _save_coverage(cdp_session, "pw_cb_02")


def test_pw_cb_03_reopen_in_same_frame_keeps_new_callbacks(page: Page) -> None:
    """
    PW-CB-03: Back and reopen in one JS call, so the new instance registers its
    callbacks before the old one is freed. The new callbacks must survive.
    """
    logs: list[dict[str, str]] = []
    cdp_session = None
    try:
        cdp_session = _setup_mock_page(page, logs)
        open_options_menu(page)
        page.wait_for_selector(
            "#options-back-button", state="visible", timeout=TEST_TIMEOUT
        )

        # Controls: Back and reopen in the same frame.
        _open_controls(page)
        page.evaluate("window.controlsBackPressed([]); window.controlsPressed([]);")
        page.wait_for_timeout(500)  # let the old instance's deferred free run
        _assert_callbacks(
            page, KEY_MAPPING_CALLBACKS, "function", "Controls reopened in same frame"
        )
        page.evaluate("window.controlsBackPressed([])")
        page.wait_for_selector(
            "#controls-back-button", state="hidden", timeout=TEST_TIMEOUT
        )

        # Options: Back and reopen in the same frame.
        page.evaluate("window.optionsBackPressed([]); window.optionsPressed([]);")
        page.wait_for_timeout(500)
        _assert_callbacks(
            page, OPTIONS_MENU_CALLBACKS, "function", "Options reopened in same frame"
        )
        _open_and_close_audio(page)
    except Exception as e:
        print(f"Test PW-CB-03 failed: {e}")
        _dump_failure_artifacts(page, logs, "pw_cb_03")
        raise
    finally:
        _save_coverage(cdp_session, "pw_cb_03")
