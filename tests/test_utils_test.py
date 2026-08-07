# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/test_utils_test.py
"""Targeted unit and integration tests for helper utilities in test_utils.py."""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from playwright.sync_api import Page, expect

from tests.test_utils import (
    DEFAULT_TIMEOUT,
    init_page_and_wait_ready,
    navigate_and_profile_godot_wasm,
    save_v8_coverage,
    start_game_and_wait_ready,
)


def test_init_page_already_initialized_returns_zero_and_sets_node() -> None:
    """Verify short-circuit returns 0.0 and sets request.node._wasm_boot_time.

    When window.godotInitialized is True, the function must return 0.0
    and assign 0.0 to request.node._wasm_boot_time.
    """
    mock_page = MagicMock()
    mock_page.evaluate.return_value = True

    mock_request = SimpleNamespace(node=SimpleNamespace())

    with patch("tests.test_utils.expect"):
        boot_time = init_page_and_wait_ready(mock_page, request=mock_request)

    assert boot_time == 0.0
    assert hasattr(mock_request.node, "_wasm_boot_time")
    assert mock_request.node._wasm_boot_time == 0.0


def test_init_page_fresh_load_calculates_boot_time_and_sets_node() -> None:
    """Verify fresh load returns boot time and attaches it to request.node.

    When page is not initialized, execution timing is calculated via
    time.perf_counter() and recorded on request.node._wasm_boot_time.
    """
    mock_page = MagicMock()
    mock_page.evaluate.return_value = False

    mock_request = SimpleNamespace(node=SimpleNamespace())

    # Simulate start_time = 10.0s, finish_time = 11.23456s -> duration = 1.2346s
    with (
        patch("time.perf_counter", side_effect=[10.0, 11.23456]),
        patch("tests.test_utils.expect"),
    ):
        boot_time = init_page_and_wait_ready(mock_page, request=mock_request)

    assert boot_time == 1.2346
    assert hasattr(mock_request.node, "_wasm_boot_time")
    assert mock_request.node._wasm_boot_time == 1.2346


def test_init_page_fresh_load_handles_none_request() -> None:
    """Verify fresh load calculates boot time cleanly when request is None."""
    mock_page = MagicMock()
    mock_page.evaluate.return_value = False

    with (
        patch("time.perf_counter", side_effect=[5.0, 7.5]),
        patch("tests.test_utils.expect"),
    ):
        boot_time = init_page_and_wait_ready(mock_page, request=None)

    assert boot_time == 2.5


def test_init_page_evaluate_exception_falls_back_to_navigation() -> None:
    """Verify fallback navigation and boot timing calculation when page.evaluate raises."""
    mock_page = MagicMock()
    mock_page.evaluate.side_effect = Exception("JS context not ready")

    mock_request = SimpleNamespace(node=SimpleNamespace())

    with (
        patch("time.perf_counter", side_effect=[10.0, 11.5]),
        patch("tests.test_utils.expect"),
    ):
        boot_time = init_page_and_wait_ready(mock_page, request=mock_request)

    mock_page.goto.assert_called_once()
    assert boot_time == 1.5
    assert hasattr(mock_request.node, "_wasm_boot_time")
    assert mock_request.node._wasm_boot_time == 1.5


def test_init_page_handles_request_without_valid_node() -> None:
    """Verify request objects lacking a valid node attribute do not raise AttributeError."""
    mock_page = MagicMock()
    mock_page.evaluate.return_value = False

    request_no_node = SimpleNamespace()
    request_none_node = SimpleNamespace(node=None)

    with (
        patch("time.perf_counter", side_effect=[1.0, 2.0]),
        patch("tests.test_utils.expect"),
    ):
        boot_time1 = init_page_and_wait_ready(mock_page, request=request_no_node)

    with (
        patch("time.perf_counter", side_effect=[3.0, 4.5]),
        patch("tests.test_utils.expect"),
    ):
        boot_time2 = init_page_and_wait_ready(mock_page, request=request_none_node)

    assert boot_time1 == 1.0
    assert boot_time2 == 1.5


def test_navigate_and_profile_godot_wasm_delegates_to_init_page() -> None:
    """Verify wrapper helper delegates arguments to init_page_and_wait_ready."""
    mock_page = MagicMock()
    mock_request = SimpleNamespace(node=SimpleNamespace())

    with patch(
        "tests.test_utils.init_page_and_wait_ready", return_value=1.5
    ) as mock_init:
        result = navigate_and_profile_godot_wasm(
            mock_page, url="http://localhost:8080/test.html", request=mock_request
        )

    assert result == 1.5
    mock_init.assert_called_once_with(
        mock_page, url="http://localhost:8080/test.html", request=mock_request
    )


def test_start_game_and_wait_ready_propagates_request_and_sets_wasm_boot_time() -> None:
    """Ensure start_game_and_wait_ready forwards pytest request and sets _wasm_boot_time."""
    mock_page = MagicMock()
    mock_page.evaluate.return_value = False
    mock_logs: list[dict[str, str]] = []
    request = SimpleNamespace(node=SimpleNamespace())

    import tests.test_utils as utils

    real_init_page = utils.init_page_and_wait_ready

    with (
        patch("tests.test_utils.init_cdp_coverage", return_value=(MagicMock(), True)),
        patch("tests.test_utils.open_options_menu"),
        patch("tests.test_utils.set_log_level"),
        patch("tests.test_utils.set_difficulty"),
        patch("tests.test_utils.wait_for_console_log"),
        patch(
            "tests.test_utils.init_page_and_wait_ready",
            wraps=real_init_page,
        ) as mock_init,
        patch("time.perf_counter", side_effect=[5.0, 7.5]),
        patch("tests.test_utils.expect"),
    ):
        start_game_and_wait_ready(
            mock_page,
            logs=mock_logs,
            request=request,
        )

    _, kwargs = mock_init.call_args
    assert kwargs["request"] is request
    assert hasattr(request.node, "_wasm_boot_time")
    assert request.node._wasm_boot_time == 2.5


def test_save_v8_coverage_collision_prevention(tmp_path, monkeypatch):
    """Verify that similar test names do not produce duplicate coverage filenames."""
    monkeypatch.setattr("tests.test_utils.ARTIFACTS_DIR", tmp_path)

    mock_cdp = MagicMock()
    mock_cdp.send.side_effect = lambda cmd, *args: (
        {"result": []} if cmd == "Profiler.takePreciseCoverage" else None
    )

    test_a = "tests/a/b::test"
    test_b = "tests/a_b::test"

    save_v8_coverage(mock_cdp, test_a)
    save_v8_coverage(mock_cdp, test_b)

    files = list(tmp_path.glob("v8_coverage_*.json"))
    assert len(files) == 2
    assert files[0].name != files[1].name


def test_init_page_short_circuits_when_already_ready(shared_page: Page) -> None:
    """Verifies init_page_and_wait_ready skips redundant reloads on an initialized page."""
    # Ensure page is initially ready
    init_page_and_wait_ready(shared_page)

    # Set a custom DOM marker to detect if page reload occurs
    shared_page.evaluate("window.__test_no_reload_marker = true")

    # Call helper again on already-initialized page
    init_page_and_wait_ready(shared_page)

    # Verify marker still exists (proves page did not re-navigate or reload)
    is_same_session = shared_page.evaluate("window.__test_no_reload_marker === true")
    assert (
        is_same_session
    ), "init_page_and_wait_ready reloaded an already initialized page"
    expect(shared_page.locator("canvas")).to_be_visible(timeout=DEFAULT_TIMEOUT)


def test_init_page_loads_fresh_page_with_custom_url(page: Page) -> None:
    """Verifies init_page_and_wait_ready loads a fresh page and respects custom URL parameters."""
    target_url = "http://localhost:8080/index.html"
    init_page_and_wait_ready(page, url=target_url)

    assert target_url in page.url
    assert page.evaluate("window.godotInitialized === true")
    expect(page.locator("canvas")).to_be_visible(timeout=DEFAULT_TIMEOUT)
