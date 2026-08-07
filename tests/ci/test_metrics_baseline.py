# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_metrics_baseline.py
"""Test suite for metrics_baseline.json exporter in conftest.py."""

import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest


def _invoke_sessionfinish(
    conftest_module: Any, artifacts_dir: Path, *, payload: dict[str, Any]
) -> None:
    """Invoke pytest_sessionfinish with controlled module state.

    Parameters
    ----------
    conftest_module : Any
        The imported conftest module.
    artifacts_dir : Path
        Temporary directory to use as ARTIFACTS_DIR.
    payload : dict[str, Any]
        Dictionary containing mock session state values.
    """
    conftest_module.ARTIFACTS_DIR = artifacts_dir
    conftest_module._SESSION_STATE["start_time"] = payload.get("start_time", 1.0)
    conftest_module._SESSION_STATE["timestamp"] = payload.get(
        "timestamp", "2026-08-06T03:00:00Z"
    )
    conftest_module._SUMMARY_COUNTS = payload.get("summary_counts", {})
    conftest_module._TEST_PROFILING_DATA = payload.get("test_profiling_data", [])

    dummy_session = SimpleNamespace()
    conftest_module.pytest_sessionfinish(dummy_session, exitstatus=0)


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


def test_metrics_baseline_file_structure(tmp_path: Path) -> None:
    """Verify metrics_baseline.json schema and test count match state."""
    from tests import conftest as conf

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

    _invoke_sessionfinish(conf, tmp_path, payload=payload)

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


def test_metrics_baseline_io_failure_is_graceful(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Verify I/O failures issue a UserWarning without crashing session."""
    from tests import conftest as conf

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
        _invoke_sessionfinish(conf, tmp_path, payload=payload)


def test_runtest_makereport_aggregates_phases() -> None:
    """Verify makereport aggregates setup, call, and teardown phase outcomes."""
    from tests import conftest as conf

    conf._TEST_PROFILING_DATA.clear()
    conf._SUMMARY_COUNTS = {"passed": 0, "failed": 0, "skipped": 0}

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
    gen_setup = conf.pytest_runtest_makereport(mock_item, SimpleNamespace(when="setup"))
    _step_hookwrapper(gen_setup, rep_setup)

    # 2. Call phase (passed)
    rep_call = SimpleNamespace(
        when="call",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.40,
    )
    gen_call = conf.pytest_runtest_makereport(mock_item, SimpleNamespace(when="call"))
    _step_hookwrapper(gen_call, rep_call)

    # 3. Teardown phase (passed)
    rep_teardown = SimpleNamespace(
        when="teardown",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.01,
    )
    gen_teardown = conf.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="teardown")
    )
    _step_hookwrapper(gen_teardown, rep_teardown)

    assert len(conf._TEST_PROFILING_DATA) == 1
    record = conf._TEST_PROFILING_DATA[0]
    assert record["nodeid"] == "tests/test_demo.py::test_demo"
    assert record["outcome"]def test_metrics_baseline_missing_start_time_defaults_to_zero_duration(
    tmp_path: Path,
) -> None:
    """Verify total_duration_sec defaults to 0.0 when start_time is missing or 0.0."""
    from tests import conftest as conf

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

    _invoke_sessionfinish(conf, tmp_path, payload=payload)

    metrics_file = tmp_path / "metrics_baseline.json"
    data = json.loads(metrics_file.read_text(encoding="utf-8"))

    assert data["total_duration_sec"] == 0.0


def test_metrics_baseline_empty_profiling_data_writes_empty_tests_list(
    tmp_path: Path,
) -> None:
    """Verify baseline JSON exporter writes an empty tests list when profiling data is empty."""
    from tests import conftest as conf

    payload = {
        "start_time": 10.0,
        "timestamp": "2026-08-06T03:00:00Z",
        "summary_counts": {"passed": 0, "failed": 0, "skipped": 0},
        "test_profiling_data": [],
    }

    _invoke_sessionfinish(conf, tmp_path, payload=payload)

    metrics_file = tmp_path / "metrics_baseline.json"
    data = json.loads(metrics_file.read_text(encoding="utf-8"))

    assert isinstance(data["tests"], list)
    assert data["tests"] == [] == "passed"
    assert record["duration_sec"] == 0.42
    assert record["wasm_boot_duration_sec"] == 0.5
    assert conf._SUMMARY_COUNTS["passed"] == 1


def test_runtest_makereport_skipped_phase_aggregates_outcome_and_duration() -> None:
    """Verify skipped setup/call phase aggregates 'skipped' outcome and sums durations."""
    from tests import conftest as conf

    conf._TEST_PROFILING_DATA.clear()
    conf._SUMMARY_COUNTS = {"passed": 0, "failed": 0, "skipped": 0}

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
    gen_setup = conf.pytest_runtest_makereport(mock_item, SimpleNamespace(when="setup"))
    _step_hookwrapper(gen_setup, rep_setup)

    # 2. Teardown phase (passed)
    rep_teardown = SimpleNamespace(
        when="teardown",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.05,
    )
    gen_teardown = conf.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="teardown")
    )
    _step_hookwrapper(gen_teardown, rep_teardown)

    assert len(conf._TEST_PROFILING_DATA) == 1
    record = conf._TEST_PROFILING_DATA[0]
    assert record["nodeid"] == "tests/test_demo.py::test_skipped"
    assert record["outcome"] == "skipped"
    assert record["duration_sec"] == 0.20
    assert conf._SUMMARY_COUNTS["skipped"] == 1


def test_runtest_makereport_setup_failure_short_circuits_and_counts_failed() -> None:
    """Verify setup failure records 'failed' outcome and counts setup duration."""
    from tests import conftest as conf

    conf._TEST_PROFILING_DATA.clear()
    conf._SUMMARY_COUNTS = {"passed": 0, "failed": 0, "skipped": 0}

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
    gen_setup = conf.pytest_runtest_makereport(mock_item, SimpleNamespace(when="setup"))
    _step_hookwrapper(gen_setup, rep_setup)

    # 2. Teardown phase (executed after failed setup)
    rep_teardown = SimpleNamespace(
        when="teardown",
        outcome="passed",
        failed=False,
        skipped=False,
        duration=0.02,
    )
    gen_teardown = conf.pytest_runtest_makereport(
        mock_item, SimpleNamespace(when="teardown")
    )
    _step_hookwrapper(gen_teardown, rep_teardown)

    assert len(conf._TEST_PROFILING_DATA) == 1
    record = conf._TEST_PROFILING_DATA[0]
    assert record["nodeid"] == "tests/test_demo.py::test_failed_setup"
    assert record["outcome"] == "failed"
    assert record["duration_sec"] == 0.27
    assert conf._SUMMARY_COUNTS["failed"] == 1
