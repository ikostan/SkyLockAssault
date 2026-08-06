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
    conftest_module._SESSION_STATE["start_time"] = payload.get(
        "start_time", 1.0
    )
    conftest_module._SESSION_STATE["timestamp"] = payload.get(
        "timestamp", "2026-08-06T03:00:00Z"
    )
    conftest_module._SUMMARY_COUNTS = payload.get("summary_counts", {})
    conftest_module._TEST_PROFILING_DATA = payload.get(
        "test_profiling_data", []
    )

    dummy_session = SimpleNamespace()
    conftest_module.pytest_sessionfinish(dummy_session, exitstatus=0)


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
        raise OSError("Simulated write failure")

    monkeypatch.setattr("builtins.open", failing_open)

    with pytest.warns(UserWarning, match="Failed to write metrics baseline"):
        _invoke_sessionfinish(conf, tmp_path, payload=payload)
