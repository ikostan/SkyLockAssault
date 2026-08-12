# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_metrics_baseline.py
"""Test suite for metrics_baseline.json exporter and profiling helpers in conftest.py."""

import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest

from tests import conftest
from tests.conftest import _determine_final_outcome, _record_test_profiling

# ==============================================================================
# Helper Classes & Utilities
# ==============================================================================


class DummyItem:
    """Minimal stand-in for pytest.Item used in profiling unit tests."""

    def __init__(self, nodeid: str, wasm_boot_time: float | None = None) -> None:
        """Initialize dummy item with nodeid and optional WASM boot time attribute."""
        self.nodeid = nodeid
        self.rep_setup: Any = None
        self.rep_call: Any = None
        if wasm_boot_time is not None:
            self._wasm_boot_time = wasm_boot_time


def _make_report(
    failed: bool = False, skipped: bool = False, duration: float = 0.0
) -> SimpleNamespace:
    """Build a minimal stand-in for pytest.TestReport with phase status."""
    return SimpleNamespace(failed=failed, skipped=skipped, duration=duration)


def _invoke_sessionfinish(
    conftest_module: Any, artifacts_dir: Path, *, payload: dict[str, Any]
) -> None:
    """Invoke pytest_sessionfinish with controlled module state."""
    original_artifacts_dir = conftest_module.ARTIFACTS_DIR
    conftest_module.ARTIFACTS_DIR = artifacts_dir
    try:
        conftest_module._SESSION_STATE["start_time"] = payload.get("start_time", 1.0)
        conftest_module._SESSION_STATE["timestamp"] = payload.get(
            "timestamp", "2026-08-06T03:00:00Z"
        )
        conftest_module._SUMMARY_COUNTS = payload.get("summary_counts", {})
        conftest_module._TEST_PROFILING_DATA = payload.get("test_profiling_data", [])

        dummy_session = SimpleNamespace()
        conftest_module.pytest_sessionfinish(dummy_session, exitstatus=0)
    finally:
        # Restore original project artifacts directory so subsequent runs export correctly
        conftest_module.ARTIFACTS_DIR = original_artifacts_dir


def _step_hookwrapper(gen: Any, report: Any) -> None:
    """Safely step through a pytest hookwrapper generator execution."""
    try:
        next(gen)
    except StopIteration:
        return

    try:
        gen.send(SimpleNamespace(get_result=lambda: report))
    except StopIteration:
        pass


@pytest.fixture(autouse=True)
def isolate_profiling_globals(monkeypatch: pytest.MonkeyPatch) -> None:
    """Isolate global profiling datasets across test runs."""
    monkeypatch.setattr(conftest, "_FAILED_NODEIDS", set())
    monkeypatch.setattr(
        conftest, "_SUMMARY_COUNTS", {"passed": 0, "failed": 0, "skipped": 0}
    )
    monkeypatch.setattr(conftest, "_TEST_PROFILING_DATA", [])


# ==============================================================================
# Baseline JSON Exporter & Hookwrapper Tests
# ==============================================================================


def test_metrics_baseline_file_structure(tmp_path: Path) -> None:
    """Verify metrics_baseline.json schema and test count match state."""
    payload = {
        "start_time": 1.0,
        "timestamp": "2026-08-06T03:00:00Z",
        "summary_counts": {"passed": 2, "failed": 0, "skipped": 0},
        "test_profiling_data": [
            {
                "nodeid": "tests/test_a.py::test_one",
                "duration_sec": 0.1234,
                "outcome": "passed",
                "wasm_boot_duration_sec": None,
            },
            {
                "nodeid": "tests/test_b.py::test_two",
                "duration_sec": 0.5678,
                "outcome": "passed",
                "wasm_boot_duration_sec": 1.205,
            },
        ],
    }

    _invoke_sessionfinish(conftest, tmp_path, payload=payload)

    metrics_file = tmp_path / "metrics_baseline.json"
    assert metrics_file.is_file()

    data = json.loads(metrics_file.read_text(encoding="utf-8"))

    # Verify top-level schema contract
    assert set(data.keys()) == {
        "timestamp",
        "total_duration_sec",
        "summary",
        "tests",
    }

    # Content sanity checks
    assert data["timestamp"] == payload["timestamp"]
    assert isinstance(data["total_duration_sec"], float)
    assert data["summary"] == payload["summary_counts"]
    assert isinstance(data["tests"], list)
    assert len(data["tests"]) == len(payload["test_profiling_data"])
    assert data["tests"] == payload["test_profiling_data"]


def test_metrics_baseline_missing_start_time_defaults_to_zero_duration(
    tmp_path: Path,
) -> None:
    """Verify total_duration_sec defaults to 0.0 when start_time is missing or 0.0."""
    payload = {
        "start_time": 0.0,
        "timestamp": "2026-08-06T03:00:00Z",
        "summary_counts": {"passed": 1, "failed": 0, "skipped": 0},
        "test_profiling_data": [
            {
                "nodeid": "tests/test_a.py::test_one",
                "duration_sec": 0.1,
                "outcome": "passed",
                "wasm_boot_duration_sec": None,
            }
        ],
    }

    _invoke_sessionfinish(conftest, tmp_path, payload=payload)

    metrics_file = tmp_path / "metrics_baseline.json"
    data = json.loads(metrics_file.read_text(encoding="utf-8"))

    assert data["total_duration_sec"] == 0.0


def test_metrics_baseline_empty_profiling_data_writes_empty_tests_list(
    tmp_path: Path,
) -> None:
    """Verify baseline JSON exporter writes an empty tests list when profiling data is empty."""
    payload = {
        "start_time": 10.0,
        "timestamp": "2026-08-06T03:00:00Z",
        "summary_counts": {"passed": 0, "failed": 0, "skipped": 0},
        "test_profiling_data": [],
    }

    _invoke_sessionfinish(conftest, tmp_path, payload=payload)

    metrics_file = tmp_path / "metrics_baseline.json"
    data = json.loads(metrics_file.read_text(encoding="utf-8"))

    assert isinstance(data["tests"], list)
    assert data["tests"] == []


def test_metrics_baseline_io_failure_is_graceful(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Verify I/O failures issue a UserWarning without crashing session."""
    payload = {
        "start_time": 0.0,
        "timestamp": "2026-08-06T03:00:00Z",
        "summary_counts": {},
        "test_profiling_data": [],
    }

    def failing_open(*args, **kwargs):
        """Simulate an open() file I/O error."""
        _ = (args, kwargs)
        raise OSError("Simulated write failure")

    monkeypatch.setattr("builtins.open", failing_open)

    with pytest.warns(UserWarning, match="Failed to write metrics baseline"):
        _invoke_sessionfinish(conftest, tmp_path, payload=payload)


def test_runtest_makereport_aggregates_phases() -> None:
    """Verify makereport aggregates setup, call, and teardown phase outcomes."""
    mock_item = SimpleNamespace(
        nodeid="tests/test_demo.py::test_demo", _wasm_boot_time=0.5
    )

    # 1. Setup phase (passed)
    rep_setup = SimpleNamespace(
        when="setup",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.01,
    )
    gen_setup = conftest.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="setup")
    )
    _step_hookwrapper(gen_setup, rep_setup)

    # 2. Call phase (passed)
    rep_call = SimpleNamespace(
        when="call",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.40,
    )
    gen_call = conftest.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="call")
    )
    _step_hookwrapper(gen_call, rep_call)

    # 3. Teardown phase (passed)
    rep_teardown = SimpleNamespace(
        when="teardown",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.01,
    )
    gen_teardown = conftest.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="teardown")
    )
    _step_hookwrapper(gen_teardown, rep_teardown)

    assert len(conftest._TEST_PROFILING_DATA) == 1
    record = conftest._TEST_PROFILING_DATA[0]
    assert record["nodeid"] == "tests/test_demo.py::test_demo"
    assert record["outcome"] == "passed"
    assert record["duration_sec"] == 0.42
    assert record["wasm_boot_duration_sec"] == 0.5
    assert conftest._SUMMARY_COUNTS["passed"] == 1


def test_runtest_makereport_skipped_phase_aggregates_outcome_and_duration() -> None:
    """Verify skipped setup/call phase aggregates 'skipped' outcome and sums durations."""
    mock_item = SimpleNamespace(
        nodeid="tests/test_demo.py::test_skipped", _wasm_boot_time=None
    )

    # 1. Setup phase (skipped)
    rep_setup = SimpleNamespace(
        when="setup",
        outcome="skipped",
        failed=False,
        skipped=True,
        duration=0.15,
    )
    gen_setup = conftest.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="setup")
    )
    _step_hookwrapper(gen_setup, rep_setup)

    # 2. Teardown phase (passed)
    rep_teardown = SimpleNamespace(
        when="teardown",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.05,
    )
    gen_teardown = conftest.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="teardown")
    )
    _step_hookwrapper(gen_teardown, rep_teardown)

    assert len(conftest._TEST_PROFILING_DATA) == 1
    record = conftest._TEST_PROFILING_DATA[0]
    assert record["nodeid"] == "tests/test_demo.py::test_skipped"
    assert record["outcome"] == "skipped"
    assert record["duration_sec"] == 0.20
    assert conftest._SUMMARY_COUNTS["skipped"] == 1


def test_runtest_makereport_setup_failure_short_circuits_and_counts_failed() -> None:
    """Verify setup failure records 'failed' outcome and counts setup duration."""
    mock_item = SimpleNamespace(
        nodeid="tests/test_demo.py::test_failed_setup", _wasm_boot_time=None
    )

    # 1. Setup phase (failing setup)
    rep_setup = SimpleNamespace(
        when="setup",
        outcome="failed",
        failed=True,
        skipped=False,
        duration=0.25,
    )
    gen_setup = conftest.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="setup")
    )
    _step_hookwrapper(gen_setup, rep_setup)

    # 2. Teardown phase (executed after failed setup)
    rep_teardown = SimpleNamespace(
        when="teardown",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.02,
    )
    gen_teardown = conftest.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="teardown")
    )
    _step_hookwrapper(gen_teardown, rep_teardown)

    assert len(conftest._TEST_PROFILING_DATA) == 1
    record = conftest._TEST_PROFILING_DATA[0]
    assert record["nodeid"] == "tests/test_demo.py::test_failed_setup"
    assert record["outcome"] == "failed"
    assert record["duration_sec"] == 0.27
    assert conftest._SUMMARY_COUNTS["failed"] == 1


# ==============================================================================
# Unit Tests for _determine_final_outcome
# ==============================================================================


def test_determine_final_outcome_failed_setup() -> None:
    """Failing setup phase should classify outcome as failed."""
    item: Any = DummyItem("test_demo.py::test_setup_fail")
    item.rep_setup = _make_report(failed=True)
    rep_teardown = _make_report()

    assert _determine_final_outcome(item, rep_teardown) == "failed"


def test_determine_final_outcome_failed_call() -> None:
    """Failing call phase should classify outcome as failed."""
    item: Any = DummyItem("test_demo.py::test_call_fail")
    item.rep_call = _make_report(failed=True)
    rep_teardown = _make_report()

    assert _determine_final_outcome(item, rep_teardown) == "failed"


def test_determine_final_outcome_failed_teardown() -> None:
    """Failing teardown phase should classify outcome as failed."""
    item: Any = DummyItem("test_demo.py::test_teardown_fail")
    rep_teardown = _make_report(failed=True)

    assert _determine_final_outcome(item, rep_teardown) == "failed"


def test_determine_final_outcome_skipped_setup_or_call() -> None:
    """Skipped setup or call phase should classify outcome as skipped."""
    item_setup_skip: Any = DummyItem("test_demo.py::test_setup_skip")
    item_setup_skip.rep_setup = _make_report(skipped=True)
    rep_teardown = _make_report()

    assert _determine_final_outcome(item_setup_skip, rep_teardown) == "skipped"

    item_call_skip: Any = DummyItem("test_demo.py::test_call_skip")
    item_call_skip.rep_call = _make_report(skipped=True)

    assert _determine_final_outcome(item_call_skip, rep_teardown) == "skipped"


def test_determine_final_outcome_all_passed() -> None:
    """Passing all phases should classify outcome as passed."""
    item: Any = DummyItem("test_demo.py::test_pass")
    item.rep_setup = _make_report()
    item.rep_call = _make_report()
    rep_teardown = _make_report()

    assert _determine_final_outcome(item, rep_teardown) == "passed"


# ==============================================================================
# Unit Tests for _record_test_profiling
# ==============================================================================


def test_record_test_profiling_failure_tracking_and_summary_counts() -> None:
    """Failing tests should register in _FAILED_NODEIDS and increment summary counts."""
    item: Any = DummyItem("test_demo.py::test_failing")
    item.rep_setup = _make_report(duration=0.1)
    item.rep_call = _make_report(failed=True, duration=0.5)
    rep_teardown = _make_report(duration=0.25)

    _record_test_profiling(item, rep_teardown)

    assert "test_demo.py::test_failing" in conftest._FAILED_NODEIDS
    assert conftest._SUMMARY_COUNTS["failed"] == 1
    assert conftest._TEST_PROFILING_DATA[0]["outcome"] == "failed"


def test_record_test_profiling_pass_and_skip_do_not_mark_failed() -> None:
    """Passing or skipped tests should update counts without populating _FAILED_NODEIDS."""
    item: Any = DummyItem("test_demo.py::test_skipped")
    item.rep_setup = _make_report(skipped=True, duration=0.1)
    rep_teardown = _make_report(duration=0.2)

    _record_test_profiling(item, rep_teardown)

    assert "test_demo.py::test_skipped" not in conftest._FAILED_NODEIDS
    assert conftest._SUMMARY_COUNTS["skipped"] == 1
    assert conftest._TEST_PROFILING_DATA[0]["outcome"] == "skipped"


def test_record_test_profiling_duration_aggregation_and_wasm_boot() -> None:
    """Durations should aggregate across phases, round to 4 decimals, and capture WASM boot time."""
    item: Any = DummyItem("test_demo.py::test_wasm_profiling", wasm_boot_time=1.234567)
    item.rep_setup = _make_report(duration=0.12344)
    item.rep_call = _make_report(duration=0.23456)
    rep_teardown = _make_report(duration=0.34567)

    _record_test_profiling(item, rep_teardown)

    entry = conftest._TEST_PROFILING_DATA[0]
    expected_duration = round(0.12344 + 0.23456 + 0.34567, 4)

    assert entry["duration_sec"] == expected_duration
    assert entry["wasm_boot_duration_sec"] == 1.2346


def test_runtest_makereport_setup_failure_short_circuits_and_counts_failed() -> None:
    """Verify setup failure records 'failed' outcome, updates _FAILED_NODEIDS, and counts setup duration."""
    mock_item = SimpleNamespace(
        nodeid="tests/test_demo.py::test_failed_setup", _wasm_boot_time=None
    )

    # 1. Setup phase (failing setup)
    rep_setup = SimpleNamespace(
        when="setup",
        outcome="failed",
        failed=True,
        skipped=False,
        duration=0.25,
    )
    gen_setup = conftest.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="setup")
    )
    _step_hookwrapper(gen_setup, rep_setup)

    # Verify failing nodeid is recorded immediately during setup report handling
    assert "tests/test_demo.py::test_failed_setup" in conftest._FAILED_NODEIDS

    # 2. Teardown phase (executed after failed setup)
    rep_teardown = SimpleNamespace(
        when="teardown",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.02,
    )
    gen_teardown = conftest.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="teardown")
    )
    _step_hookwrapper(gen_teardown, rep_teardown)

    assert len(conftest._TEST_PROFILING_DATA) == 1
    record = conftest._TEST_PROFILING_DATA[0]
    assert record["nodeid"] == "tests/test_demo.py::test_failed_setup"
    assert record["outcome"] == "failed"
    assert record["duration_sec"] == 0.27
    assert conftest._SUMMARY_COUNTS["failed"] == 1
    assert "tests/test_demo.py::test_failed_setup" in conftest._FAILED_NODEIDS
