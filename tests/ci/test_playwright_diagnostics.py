# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_playwright_diagnostics.py
"""Test suite for failure-only Playwright diagnostics helpers in conftest.py.

Covers the refactored/added helpers backing PR #872:
``_is_test_failed``, ``_stop_tracing``, ``_finalize_video``,
``_cleanup_context_diagnostics``, ``_determine_final_outcome``, and
``_record_test_profiling``.
"""

from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import MagicMock

import pytest


@pytest.fixture(autouse=True)
def _isolate_conftest_state(tmp_path: Path):
    """Snapshot and restore mutable module-level state in tests.conftest.

    Prevents cross-test pollution of ``_FAILED_NODEIDS``, ``_TEST_PROFILING_DATA``,
    ``_SUMMARY_COUNTS``, and redirects ``ARTIFACTS_DIR`` to an isolated tmp_path.
    """
    from tests import conftest as conf

    original_failed_nodeids = set(conf._FAILED_NODEIDS)
    original_profiling_data = list(conf._TEST_PROFILING_DATA)
    original_summary_counts = dict(conf._SUMMARY_COUNTS)
    original_artifacts_dir = conf.ARTIFACTS_DIR

    conf._FAILED_NODEIDS.clear()
    conf._TEST_PROFILING_DATA.clear()
    conf._SUMMARY_COUNTS.clear()
    conf._SUMMARY_COUNTS.update({"passed": 0, "failed": 0, "skipped": 0})
    conf.ARTIFACTS_DIR = tmp_path

    yield conf

    conf._FAILED_NODEIDS.clear()
    conf._FAILED_NODEIDS.update(original_failed_nodeids)
    conf._TEST_PROFILING_DATA.clear()
    conf._TEST_PROFILING_DATA.extend(original_profiling_data)
    conf._SUMMARY_COUNTS.clear()
    conf._SUMMARY_COUNTS.update(original_summary_counts)
    conf.ARTIFACTS_DIR = original_artifacts_dir


def _make_request(
    nodeid: str,
    *,
    rep_setup: Any = None,
    rep_call: Any = None,
) -> SimpleNamespace:
    """Build a fake pytest.FixtureRequest with a node carrying report attrs."""
    node = SimpleNamespace(nodeid=nodeid)
    if rep_setup is not None:
        node.rep_setup = rep_setup
    if rep_call is not None:
        node.rep_call = rep_call
    return SimpleNamespace(node=node)


# ==============================================================================
# _is_test_failed
# ==============================================================================


def test_is_test_failed_returns_false_when_no_failure_signals(_isolate_conftest_state):
    conf = _isolate_conftest_state
    request = _make_request("tests/test_a.py::test_one")

    failed, target = conf._is_test_failed(request)

    assert failed is False
    assert target == "tests/test_a.py::test_one"


def test_is_test_failed_detects_rep_call_failure(_isolate_conftest_state):
    conf = _isolate_conftest_state
    request = _make_request(
        "tests/test_a.py::test_one",
        rep_call=SimpleNamespace(failed=True),
    )

    failed, target = conf._is_test_failed(request)

    assert failed is True
    assert target == "tests/test_a.py::test_one"


def test_is_test_failed_detects_rep_setup_failure(_isolate_conftest_state):
    conf = _isolate_conftest_state
    request = _make_request(
        "tests/test_a.py::test_one",
        rep_setup=SimpleNamespace(failed=True),
        rep_call=SimpleNamespace(failed=False),
    )

    failed, target = conf._is_test_failed(request)

    assert failed is True
    assert target == "tests/test_a.py::test_one"


def test_is_test_failed_detects_membership_in_failed_nodeids(_isolate_conftest_state):
    conf = _isolate_conftest_state
    conf._FAILED_NODEIDS.add("tests/test_a.py::test_one")
    request = _make_request("tests/test_a.py::test_one")

    failed, target = conf._is_test_failed(request)

    assert failed is True
    assert target == "tests/test_a.py::test_one"


def test_is_test_failed_module_failures_ignored_by_default(_isolate_conftest_state):
    """Without include_module_failures, sibling test failures must not leak in."""
    conf = _isolate_conftest_state
    conf._FAILED_NODEIDS.add("tests/test_a.py::test_other")
    request = _make_request("tests/test_a.py::test_one")

    failed, target = conf._is_test_failed(request, include_module_failures=False)

    assert failed is False
    assert target == "tests/test_a.py::test_one"


def test_is_test_failed_module_failures_detected_when_enabled(_isolate_conftest_state):
    """With include_module_failures, a failure elsewhere in the module is surfaced."""
    conf = _isolate_conftest_state
    conf._FAILED_NODEIDS.add("tests/test_a.py::test_other")
    request = _make_request("tests/test_a.py::test_one")

    failed, target = conf._is_test_failed(request, include_module_failures=True)

    assert failed is True
    assert target == "tests/test_a.py::test_other"


def test_is_test_failed_module_failures_does_not_match_other_modules(
    _isolate_conftest_state,
):
    conf = _isolate_conftest_state
    conf._FAILED_NODEIDS.add("tests/test_b.py::test_other")
    request = _make_request("tests/test_a.py::test_one")

    failed, target = conf._is_test_failed(request, include_module_failures=True)

    assert failed is False
    assert target == "tests/test_a.py::test_one"


# ==============================================================================
# _stop_tracing
# ==============================================================================


def test_stop_tracing_saves_trace_archive_on_failure(_isolate_conftest_state):
    conf = _isolate_conftest_state
    context = MagicMock()

    conf._stop_tracing(context, "safe_node_id", test_failed=True)

    expected_path = str(conf.ARTIFACTS_DIR / "trace_safe_node_id.zip")
    context.tracing.stop.assert_called_once_with(path=expected_path)


def test_stop_tracing_discards_trace_on_success(_isolate_conftest_state):
    conf = _isolate_conftest_state
    context = MagicMock()

    conf._stop_tracing(context, "safe_node_id", test_failed=False)

    context.tracing.stop.assert_called_once_with()


def test_stop_tracing_emits_warning_on_exception(_isolate_conftest_state):
    conf = _isolate_conftest_state
    context = MagicMock()
    context.tracing.stop.side_effect = RuntimeError("boom")

    with pytest.warns(UserWarning, match="Failed to stop tracing"):
        conf._stop_tracing(context, "safe_node_id", test_failed=True)


# ==============================================================================
# _finalize_video
# ==============================================================================


def test_finalize_video_noop_when_no_video_handle(_isolate_conftest_state):
    conf = _isolate_conftest_state

    # Must not raise even though there is nothing to save/delete.
    conf._finalize_video(None, "safe_node_id", test_failed=True)
    conf._finalize_video(None, "safe_node_id", test_failed=False)


def test_finalize_video_saves_video_on_failure(_isolate_conftest_state):
    conf = _isolate_conftest_state
    video_handle = MagicMock()

    conf._finalize_video(video_handle, "safe_node_id", test_failed=True)

    expected_path = str(conf.ARTIFACTS_DIR / "video_safe_node_id.webm")
    video_handle.save_as.assert_called_once_with(expected_path)
    video_handle.delete.assert_not_called()


def test_finalize_video_deletes_video_on_success(_isolate_conftest_state):
    conf = _isolate_conftest_state
    video_handle = MagicMock()

    conf._finalize_video(video_handle, "safe_node_id", test_failed=False)

    video_handle.delete.assert_called_once_with()
    video_handle.save_as.assert_not_called()


def test_finalize_video_save_failure_emits_warning(_isolate_conftest_state):
    conf = _isolate_conftest_state
    video_handle = MagicMock()
    video_handle.save_as.side_effect = OSError("disk full")

    with pytest.warns(UserWarning, match="Failed to save video"):
        conf._finalize_video(video_handle, "safe_node_id", test_failed=True)


def test_finalize_video_delete_failure_emits_warning(_isolate_conftest_state):
    conf = _isolate_conftest_state
    video_handle = MagicMock()
    video_handle.delete.side_effect = OSError("locked")

    with pytest.warns(UserWarning, match="Failed to delete video"):
        conf._finalize_video(video_handle, "safe_node_id", test_failed=False)


# ==============================================================================
# _cleanup_context_diagnostics
# ==============================================================================


def _make_page(video_handle: Any = None) -> MagicMock:
    page = MagicMock()
    page.video = video_handle
    return page


def test_cleanup_context_diagnostics_failure_path_captures_all_artifacts(
    _isolate_conftest_state,
):
    conf = _isolate_conftest_state
    context = MagicMock()
    video_handle = MagicMock()
    page_obj = _make_page(video_handle)
    request = _make_request(
        "tests/test_a.py::test_one",
        rep_call=SimpleNamespace(failed=True),
    )

    conf._cleanup_context_diagnostics(context, page_obj, request)

    safe_id = "tests_test_a.py_test_one"
    page_obj.screenshot.assert_called_once_with(
        path=str(conf.ARTIFACTS_DIR / f"failure_{safe_id}.png"), full_page=True
    )
    context.tracing.stop.assert_called_once_with(
        path=str(conf.ARTIFACTS_DIR / f"trace_{safe_id}.zip")
    )
    context.close.assert_called_once_with()
    video_handle.save_as.assert_called_once_with(
        str(conf.ARTIFACTS_DIR / f"video_{safe_id}.webm")
    )


def test_cleanup_context_diagnostics_success_path_purges_artifacts(
    _isolate_conftest_state,
):
    conf = _isolate_conftest_state
    context = MagicMock()
    video_handle = MagicMock()
    page_obj = _make_page(video_handle)
    request = _make_request(
        "tests/test_a.py::test_one",
        rep_call=SimpleNamespace(failed=False),
    )

    conf._cleanup_context_diagnostics(context, page_obj, request)

    page_obj.screenshot.assert_not_called()
    context.tracing.stop.assert_called_once_with()
    context.close.assert_called_once_with()
    video_handle.delete.assert_called_once_with()
    video_handle.save_as.assert_not_called()


def test_cleanup_context_diagnostics_screenshot_failure_still_closes_context(
    _isolate_conftest_state,
):
    conf = _isolate_conftest_state
    context = MagicMock()
    video_handle = MagicMock()
    page_obj = _make_page(video_handle)
    page_obj.screenshot.side_effect = RuntimeError("screenshot boom")
    request = _make_request(
        "tests/test_a.py::test_one",
        rep_call=SimpleNamespace(failed=True),
    )

    with pytest.warns(UserWarning, match="Failed to capture failure screenshot"):
        conf._cleanup_context_diagnostics(context, page_obj, request)

    context.tracing.stop.assert_called_once()
    context.close.assert_called_once_with()
    video_handle.save_as.assert_called_once()


def test_cleanup_context_diagnostics_context_close_failure_still_finalizes_video(
    _isolate_conftest_state,
):
    conf = _isolate_conftest_state
    context = MagicMock()
    context.close.side_effect = RuntimeError("close boom")
    video_handle = MagicMock()
    page_obj = _make_page(video_handle)
    request = _make_request(
        "tests/test_a.py::test_one",
        rep_call=SimpleNamespace(failed=False),
    )

    with pytest.warns(UserWarning, match="Error closing Playwright browser context"):
        conf._cleanup_context_diagnostics(context, page_obj, request)

    video_handle.delete.assert_called_once_with()


def test_cleanup_context_diagnostics_module_scope_uses_failed_sibling_nodeid(
    _isolate_conftest_state,
):
    """Module-scoped shared_page fixture should name artifacts after the failed test."""
    conf = _isolate_conftest_state
    conf._FAILED_NODEIDS.add("tests/test_a.py::test_failed_sibling")
    context = MagicMock()
    video_handle = MagicMock()
    page_obj = _make_page(video_handle)
    request = _make_request("tests/test_a.py::test_passing_teardown")

    conf._cleanup_context_diagnostics(
        context, page_obj, request, include_module_failures=True
    )

    safe_id = "tests_test_a.py_test_failed_sibling"
    page_obj.screenshot.assert_called_once_with(
        path=str(conf.ARTIFACTS_DIR / f"failure_{safe_id}.png"), full_page=True
    )
    video_handle.save_as.assert_called_once_with(
        str(conf.ARTIFACTS_DIR / f"video_{safe_id}.webm")
    )


# ==============================================================================
# _determine_final_outcome
# ==============================================================================


def _rep(when: str, *, failed: bool = False, skipped: bool = False) -> SimpleNamespace:
    return SimpleNamespace(when=when, failed=failed, skipped=skipped)


def test_determine_final_outcome_all_passed(_isolate_conftest_state):
    conf = _isolate_conftest_state
    item = SimpleNamespace(rep_setup=_rep("setup"), rep_call=_rep("call"))

    outcome = conf._determine_final_outcome(item, _rep("teardown"))

    assert outcome == "passed"


def test_determine_final_outcome_setup_failure(_isolate_conftest_state):
    conf = _isolate_conftest_state
    item = SimpleNamespace(rep_setup=_rep("setup", failed=True), rep_call=None)

    outcome = conf._determine_final_outcome(item, _rep("teardown"))

    assert outcome == "failed"


def test_determine_final_outcome_call_failure(_isolate_conftest_state):
    conf = _isolate_conftest_state
    item = SimpleNamespace(rep_setup=_rep("setup"), rep_call=_rep("call", failed=True))

    outcome = conf._determine_final_outcome(item, _rep("teardown"))

    assert outcome == "failed"


def test_determine_final_outcome_teardown_failure(_isolate_conftest_state):
    conf = _isolate_conftest_state
    item = SimpleNamespace(rep_setup=_rep("setup"), rep_call=_rep("call"))

    outcome = conf._determine_final_outcome(item, _rep("teardown", failed=True))

    assert outcome == "failed"


def test_determine_final_outcome_setup_skipped(_isolate_conftest_state):
    conf = _isolate_conftest_state
    item = SimpleNamespace(rep_setup=_rep("setup", skipped=True), rep_call=None)

    outcome = conf._determine_final_outcome(item, _rep("teardown"))

    assert outcome == "skipped"


def test_determine_final_outcome_failure_takes_priority_over_skip(
    _isolate_conftest_state,
):
    conf = _isolate_conftest_state
    item = SimpleNamespace(
        rep_setup=_rep("setup", skipped=True),
        rep_call=_rep("call", failed=True),
    )

    outcome = conf._determine_final_outcome(item, _rep("teardown"))

    assert outcome == "failed"


# ==============================================================================
# _record_test_profiling
# ==============================================================================


def test_record_test_profiling_appends_passed_entry(_isolate_conftest_state):
    conf = _isolate_conftest_state
    item = SimpleNamespace(
        nodeid="tests/test_a.py::test_one",
        rep_setup=_rep("setup", failed=False),
        rep_call=_rep("call", failed=False),
    )
    rep_teardown = SimpleNamespace(
        when="teardown", failed=False, skipped=False, duration=0.01
    )
    item.rep_setup.duration = 0.02
    item.rep_call.duration = 0.30

    conf._record_test_profiling(item, rep_teardown)

    assert len(conf._TEST_PROFILING_DATA) == 1
    record = conf._TEST_PROFILING_DATA[0]
    assert record["nodeid"] == "tests/test_a.py::test_one"
    assert record["outcome"] == "passed"
    assert record["duration_sec"] == pytest.approx(0.33)
    assert record["wasm_boot_duration_sec"] is None
    assert conf._SUMMARY_COUNTS["passed"] == 1
    assert "tests/test_a.py::test_one" not in conf._FAILED_NODEIDS


def test_record_test_profiling_failed_entry_updates_failed_nodeids(
    _isolate_conftest_state,
):
    conf = _isolate_conftest_state
    item = SimpleNamespace(
        nodeid="tests/test_a.py::test_two",
        rep_setup=_rep("setup", failed=False),
        rep_call=_rep("call", failed=True),
    )
    item.rep_setup.duration = 0.01
    item.rep_call.duration = 0.05
    rep_teardown = SimpleNamespace(
        when="teardown", failed=False, skipped=False, duration=0.01
    )

    conf._record_test_profiling(item, rep_teardown)

    assert "tests/test_a.py::test_two" in conf._FAILED_NODEIDS
    assert conf._SUMMARY_COUNTS["failed"] == 1
    assert conf._TEST_PROFILING_DATA[0]["outcome"] == "failed"


def test_record_test_profiling_includes_rounded_wasm_boot_time(
    _isolate_conftest_state,
):
    conf = _isolate_conftest_state
    item = SimpleNamespace(
        nodeid="tests/test_a.py::test_three",
        rep_setup=None,
        rep_call=None,
        _wasm_boot_time=1.23456789,
    )
    rep_teardown = SimpleNamespace(
        when="teardown", failed=False, skipped=False, duration=0.1
    )

    conf._record_test_profiling(item, rep_teardown)

    assert conf._TEST_PROFILING_DATA[0]["wasm_boot_duration_sec"] == 1.2346


def test_record_test_profiling_accumulates_summary_counts_across_calls(
    _isolate_conftest_state,
):
    conf = _isolate_conftest_state
    rep_teardown = SimpleNamespace(
        when="teardown", failed=False, skipped=False, duration=0.0
    )

    passed_item = SimpleNamespace(
        nodeid="tests/test_a.py::test_pass", rep_setup=None, rep_call=None
    )
    failed_item = SimpleNamespace(
        nodeid="tests/test_a.py::test_fail",
        rep_setup=None,
        rep_call=_rep("call", failed=True),
    )
    failed_item.rep_call.duration = 0.0

    conf._record_test_profiling(passed_item, rep_teardown)
    conf._record_test_profiling(failed_item, rep_teardown)

    assert conf._SUMMARY_COUNTS == {"passed": 1, "failed": 1, "skipped": 0}
    assert len(conf._TEST_PROFILING_DATA) == 2
