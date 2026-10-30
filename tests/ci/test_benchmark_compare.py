# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_benchmark_compare.py
"""Tests for test/benchmark/compare.py, the CI benchmark gate (#1079)."""

import csv
import importlib.util
import json
import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = PROJECT_ROOT / "test/benchmark/compare.py"

BASE_METRICS = {
    "saves": 61.0,
    "objects_avg": 2542.0,
    "nodes_avg": 503.0,
    "resources_avg": 206.0,
    "orphans_max": 0.0,
    "reload_orphans_max": 0.0,
    "reload_object_growth": 9.0,
    "frame_p95_ms": 17.7,
    "frames_over_33.4ms": 0.0,
    "proc_worst_avg_ms": 0.5,
    "phys_worst_avg_ms": 2.0,
    "mem_static_growth": 150000.0,
}


@pytest.fixture(scope="module")
def compare():
    """Load compare.py as a module (test/benchmark is not a package)."""
    spec = importlib.util.spec_from_file_location("bench_compare", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    # Dataclasses look their module up in sys.modules while being created.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    yield module
    sys.modules.pop(spec.name, None)


def write_runs(path: Path, runs: list[dict]) -> Path:
    """Write a runs.csv like run_desktop.py does, with a text column."""
    rows = [{"godot": "4.7.1-stable (official)", **run} for run in runs]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return path


def write_baseline(path: Path, metrics: dict) -> Path:
    """Write a baseline_ci.json with the given metrics."""
    doc = {"version": 1, "commit": "abc1234", "created": "x", "metrics": metrics}
    path.write_text(json.dumps(doc), encoding="utf-8")
    return path


def run(compare, tmp_path: Path, runs: list[dict], baseline: dict | None) -> int:
    """Run compare.main on the given runs and baseline; return the exit code."""
    results = write_runs(tmp_path / "runs.csv", runs)
    base_path = tmp_path / "baseline_ci.json"
    if baseline is not None:
        write_baseline(base_path, baseline)
    return compare.main(["--results", str(results), "--baseline", str(base_path)])


def test_identical_results_pass(compare, tmp_path):
    """Results equal to the baseline pass."""
    assert run(compare, tmp_path, [BASE_METRICS] * 3, BASE_METRICS) == 0


def test_count_regression_fails(compare, tmp_path):
    """A worse reload leak beyond tolerance fails the job."""
    worse = {**BASE_METRICS, "reload_object_growth": 20.0}
    assert run(compare, tmp_path, [worse] * 3, BASE_METRICS) == 1


def test_count_within_tolerance_passes(compare, tmp_path):
    """One extra settings save is jitter, not a regression."""
    jitter = {**BASE_METRICS, "saves": 62.0}
    assert run(compare, tmp_path, [jitter] * 3, BASE_METRICS) == 0


def test_timing_regression_only_warns(compare, tmp_path, capsys):
    """Much slower frames warn but do not fail the job."""
    slow = {**BASE_METRICS, "frame_p95_ms": 30.0, "frames_over_33.4ms": 50.0}
    assert run(compare, tmp_path, [slow] * 3, BASE_METRICS) == 0
    assert "Warnings: 2." in capsys.readouterr().out


def test_improvement_is_reported(compare, tmp_path, capsys):
    """Fewer saves are shown as an improvement and pass."""
    better = {**BASE_METRICS, "saves": 0.0}
    assert run(compare, tmp_path, [better] * 3, BASE_METRICS) == 0
    assert "🟢 | Settings saves in 60 s" in capsys.readouterr().out


def test_median_ignores_one_bad_run(compare, tmp_path):
    """The median of three runs is not moved by a single outlier."""
    outlier = {**BASE_METRICS, "reload_object_growth": 50.0}
    runs = [BASE_METRICS, outlier, BASE_METRICS]
    assert run(compare, tmp_path, runs, BASE_METRICS) == 0


def test_missing_baseline_reports_and_passes(compare, tmp_path, capsys):
    """Without a baseline file the numbers are reported, not judged."""
    assert run(compare, tmp_path, [BASE_METRICS], None) == 0
    assert "No baseline yet" in capsys.readouterr().out


def test_write_baseline_round_trips(compare, tmp_path):
    """A written baseline holds the medians and passes against itself."""
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS] * 3)
    new_base = tmp_path / "new_baseline.json"
    args = ["--results", str(results), "--baseline", str(tmp_path / "none.json")]
    assert compare.main([*args, "--write-baseline", str(new_base)]) == 0
    doc = json.loads(new_base.read_text(encoding="utf-8"))
    assert doc["metrics"]["reload_object_growth"] == 9.0
    assert doc["godot"] == "4.7.1-stable (official)"
    assert compare.main(["--results", str(results), "--baseline", str(new_base)]) == 0


def test_summary_is_appended(compare, tmp_path):
    """The Markdown report is appended to the summary file."""
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS])
    base_path = write_baseline(tmp_path / "baseline_ci.json", BASE_METRICS)
    summary = tmp_path / "summary.md"
    summary.write_text("existing\n", encoding="utf-8")
    compare.main(
        [
            "--results",
            str(results),
            "--baseline",
            str(base_path),
            "--summary",
            str(summary),
        ]
    )
    text = summary.read_text(encoding="utf-8")
    assert text.startswith("existing\n")
    assert "## Performance benchmark" in text
