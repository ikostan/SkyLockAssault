# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_v8_coverage_utils.py
"""
Test suite for V8 coverage collection utilities.

Ensures that CDP coverage sessions save artifacts correctly to the
artifacts directory, handle missing sessions gracefully, and catch
file or protocol exceptions without crashing test execution.

Audited for deterministic execution (subprocess timeouts, no static sleeps).
"""

import hashlib
import json
from pathlib import Path
from unittest.mock import MagicMock, call, patch

import pytest

from tests.test_utils import save_v8_coverage


def test_save_v8_coverage_falsy_session() -> None:
    """Verify function short-circuits gracefully when cdp_session is None or falsy."""
    # Ensure falsy CDP session handles pass without throwing errors or side effects
    save_v8_coverage(None, "sample_test_name")
    save_v8_coverage(False, "sample_test_name")


def test_save_v8_coverage_success(tmp_path: Path) -> None:
    """
    Verify artifacts directory is created, CDP commands are sent in exact order,
    and coverage JSON is saved.
    """
    mock_cdp = MagicMock()
    mock_coverage_data: dict[str, object] = {
        "result": [{"url": "http://localhost:8080/index.js", "functions": []}]
    }

    # Dynamically emulate Profiler command responses
    mock_cdp.send.side_effect = lambda cmd, *args: (
        mock_coverage_data if cmd == "Profiler.takePreciseCoverage" else None
    )

    # Mock the artifacts output directory within a temporary test path
    artifacts_dir = tmp_path / "artifacts"
    test_name = "audio_flow_test"
    name_hash = hashlib.sha256(test_name.encode()).hexdigest()[:12]

    with patch("tests.test_utils.ARTIFACTS_DIR", artifacts_dir):
        save_v8_coverage(mock_cdp, test_name)

    # 1. Verify directory creation contract
    assert artifacts_dir.is_dir()

    # 2. Verify exact CDP protocol call sequence
    assert mock_cdp.send.call_args_list == [
        call("Profiler.takePreciseCoverage"),
        call("Profiler.stopPreciseCoverage"),
    ]

    # 3. Verify correct target file path creation inside artifacts/
    expected_file = artifacts_dir / f"v8_coverage_{test_name}_{name_hash}.json"
    assert expected_file.exists()

    # 4. Verify saved payload matches expected CDP output structure
    with open(expected_file, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert data == mock_coverage_data


def test_save_v8_coverage_empty_payload(tmp_path: Path) -> None:
    """Verify that if CDP returns None or empty coverage, the function returns cleanly without writing a file."""
    mock_cdp = MagicMock()
    mock_cdp.send.return_value = None

    artifacts_dir = tmp_path / "artifacts"

    with patch("tests.test_utils.ARTIFACTS_DIR", artifacts_dir):
        save_v8_coverage(mock_cdp, "empty_payload_test")

    expected_file = artifacts_dir / "v8_coverage_empty_payload_test.json"
    assert not expected_file.exists()


def test_save_v8_coverage_handles_cdp_exception(
    capsys: pytest.CaptureFixture[str],
) -> None:
    """
    Verify CDP session errors are caught and logged as warnings without crashing the test runner.
    """
    # Simulate a CDP transport or session layer failure
    mock_cdp = MagicMock()
    mock_cdp.send.side_effect = Exception("CDP connection lost")

    # Execute helper and verify exception handling
    save_v8_coverage(mock_cdp, "failing_flow_test")

    # Verify warning message is printed cleanly to stdout
    captured = capsys.readouterr()
    assert "Warning: Failed to save V8 coverage for failing_flow_test" in captured.out
    assert "CDP connection lost" in captured.out


def test_save_v8_coverage_handles_file_write_exception(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    """Verify disk permission or write failures are caught gracefully."""
    # Prepare valid CDP response payload
    mock_cdp = MagicMock()
    mock_cdp.send.return_value = {"result": []}

    artifacts_dir = tmp_path / "artifacts"

    # Simulate filesystem write failure (e.g. read-only permissions or disk full)
    with patch("tests.test_utils.ARTIFACTS_DIR", artifacts_dir), patch(
        "builtins.open", side_effect=OSError("Disk full or permission denied")
    ):
        save_v8_coverage(mock_cdp, "write_failure_test")

    # Verify warning message captures the OS error cleanly without failing execution
    captured = capsys.readouterr()
    assert "Warning: Failed to save V8 coverage for write_failure_test" in captured.out
    assert "Disk full or permission denied" in captured.out


def test_save_v8_coverage_sanitizes_filename(tmp_path: Path) -> None:
    """Verify special characters (e.g. slashes, colons, brackets) in test_name are sanitized."""
    mock_cdp = MagicMock()
    mock_cdp.send.return_value = {"result": []}

    artifacts_dir = tmp_path / "artifacts"
    test_name = "tests/audio_test.py::test_flow[chromium]"
    name_hash = hashlib.sha256(test_name.encode()).hexdigest()[:12]

    with patch("tests.test_utils.ARTIFACTS_DIR", artifacts_dir):
        save_v8_coverage(mock_cdp, test_name)

    expected_file = (
        artifacts_dir
        / f"v8_coverage_tests_audio_test.py_test_flow_chromium__{name_hash}.json"
    )
    assert expected_file.exists()
