# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_benchmark_compare.py
"""Tests for test/benchmark/compare.py, the CI benchmark gate (#1079)."""

import csv
import importlib.util
import json
import math
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


def test_title_sets_report_heading(compare, tmp_path, capsys):
    """--title replaces the heading, so desktop and web reports differ."""
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS])
    base_path = write_baseline(tmp_path / "baseline_ci.json", BASE_METRICS)
    args = ["--results", str(results), "--baseline", str(base_path)]
    assert compare.main([*args, "--title", "Performance benchmark (web)"]) == 0
    assert "## Performance benchmark (web)" in capsys.readouterr().out


def test_profile_widens_only_its_own_tolerance(compare, tmp_path):
    """Desktop allows reload-growth noise; web keeps the tight value."""
    noisy = {**BASE_METRICS, "reload_object_growth": 15.0}
    results = write_runs(tmp_path / "runs.csv", [noisy])
    base_path = write_baseline(tmp_path / "baseline_ci.json", BASE_METRICS)
    args = ["--results", str(results), "--baseline", str(base_path)]
    assert compare.main([*args, "--profile", "desktop"]) == 0
    assert compare.main([*args, "--profile", "web"]) == 1
    assert compare.main(args) == 1


@pytest.mark.parametrize(
    ("baseline_growth", "current_growth", "expected_status"),
    [
        (2, 11, "ok"),
        (2, 12, "ok"),
        (2, 13, "fail"),
        (12, 2, "ok"),
        (12, 1, "better"),
    ],
)
def test_desktop_reload_growth_observed_spread(
    compare, baseline_growth, current_growth, expected_status
):
    """The observed 2-to-12 spread fits from either end, but no further."""
    rows = compare.compare(
        {"reload_object_growth": current_growth},
        {"reload_object_growth": baseline_growth},
        "desktop",
    )
    assert rows == [
        (
            "count",
            "Reload loop object growth",
            baseline_growth,
            current_growth,
            expected_status,
        )
    ]


def test_web_profile_allows_node_noise_desktop_does_not(compare, tmp_path):
    """Web allows nodes_avg noise; desktop keeps the tight value."""
    noisy = {**BASE_METRICS, "nodes_avg": BASE_METRICS["nodes_avg"] + 12}
    results = write_runs(tmp_path / "runs.csv", [noisy])
    base_path = write_baseline(tmp_path / "baseline_ci.json", BASE_METRICS)
    args = ["--results", str(results), "--baseline", str(base_path)]
    assert compare.main([*args, "--profile", "web"]) == 0
    assert compare.main([*args, "--profile", "desktop"]) == 1


# Web medians from two main runs with no code change between them: run
# 41155653694 (400d734, fast runner) and run 41274707348 (c480f53, slower one).
WEB_FAST_RUNNER = {"objects_avg": 2222.55, "nodes_avg": 458.95}
WEB_SLOW_RUNNER = {"objects_avg": 2309.267, "nodes_avg": 519.367}


def test_web_runner_speed_counts_only_warn(compare, tmp_path, capsys):
    """The real fast-to-slow runner swing warns on web and fails on desktop."""
    baseline = {**BASE_METRICS, **WEB_FAST_RUNNER}
    current = {**BASE_METRICS, **WEB_SLOW_RUNNER}
    results = write_runs(tmp_path / "runs.csv", [current] * 3)
    base_path = write_baseline(tmp_path / "baseline_ci.json", baseline)
    args = ["--results", str(results), "--baseline", str(base_path)]

    assert compare.main([*args, "--profile", "web"]) == 0
    report = capsys.readouterr().out
    assert "| ⚠️ | OBJECT_COUNT avg | count |" in report
    assert "| ⚠️ | OBJECT_NODE_COUNT avg | count |" in report
    assert "Regressions: 0. Warnings: 2." in report

    assert compare.main([*args, "--profile", "desktop"]) == 1
    assert "Regressions: 2." in capsys.readouterr().out


def test_web_warnings_do_not_hide_a_gated_failure_in_summary(compare, tmp_path, capsys):
    """A web count warning and a timing warning coexist with a failing leak gate."""
    current = {
        **BASE_METRICS,
        "objects_avg": BASE_METRICS["objects_avg"] + 26,
        "reload_orphans_max": 1,
        "frame_p95_ms": 30,
    }
    results = write_runs(tmp_path / "runs.csv", [current])
    base_path = write_baseline(tmp_path / "baseline.json", BASE_METRICS)
    summary = tmp_path / "summary.md"
    summary.write_text("existing\n", encoding="utf-8")

    assert (
        compare.main(
            [
                "--results",
                str(results),
                "--baseline",
                str(base_path),
                "--profile",
                "web",
                "--summary",
                str(summary),
            ]
        )
        == 1
    )
    report = capsys.readouterr().out
    assert "| ⚠️ | OBJECT_COUNT avg | count |" in report
    assert "| ❌ | Orphan nodes, reload loop (max) | count |" in report
    assert "| ⚠️ | Frame interval p95 (ms) | timing |" in report
    assert "Regressions: 1. Warnings: 2." in report
    assert "On web, OBJECT_COUNT avg and OBJECT_NODE_COUNT avg only warn:" in report
    assert summary.read_text(encoding="utf-8") == "existing\n" + report


@pytest.mark.parametrize("metric", ["objects_avg", "nodes_avg"])
def test_web_warn_only_counts_distinguish_missing_and_zero_baselines(compare, metric):
    """Missing counts remain new, while zero is a real baseline that can warn."""
    current = {metric: 100.0}
    assert compare.compare(current, None, "web")[0][-1] == "new"
    assert compare.compare(current, {}, "web")[0][-1] == "new"
    assert compare.compare(current, {metric: 0.0}, "web")[0][-1] == "warn"


@pytest.mark.parametrize("metric, tolerance", [("objects_avg", 25), ("nodes_avg", 15)])
@pytest.mark.parametrize("worse_runs, status", [(1, "✅"), (2, "⚠️")])
def test_web_count_warning_uses_median(
    compare, tmp_path, capsys, metric, tolerance, worse_runs, status
):
    """Only a median above the tolerance generates a web count warning."""
    baseline = {metric: 100.0}
    runs = [baseline] * (3 - worse_runs) + [{metric: 101.0 + tolerance}] * worse_runs
    results = write_runs(tmp_path / "runs.csv", runs)
    base_path = write_baseline(tmp_path / "baseline.json", baseline)

    assert (
        compare.main(
            [
                "--results",
                str(results),
                "--baseline",
                str(base_path),
                "--profile",
                "web",
            ]
        )
        == 0
    )
    report = capsys.readouterr().out
    label = "OBJECT_COUNT avg" if metric == "objects_avg" else "OBJECT_NODE_COUNT avg"
    assert f"| {status} | {label} | count |" in report
    assert f"Regressions: 0. Warnings: {int(worse_runs == 2)}." in report


@pytest.mark.parametrize("metric", ["objects_avg", "nodes_avg"])
def test_web_warn_only_counts_still_report_ok_and_better(compare, metric):
    """Warn-only changes only a failure; ok and better are reported as before."""
    baseline = {metric: WEB_SLOW_RUNNER[metric]}
    assert compare.compare(dict(baseline), baseline, "web")[0][-1] == "ok"
    faster = {metric: WEB_FAST_RUNNER[metric]}
    assert compare.compare(faster, baseline, "web")[0][-1] == "better"


@pytest.mark.parametrize(
    "metric", ["saves", "resources_avg", "orphans_max", "reload_object_growth"]
)
def test_web_keeps_gating_leak_counts(compare, metric):
    """On web, only objects and nodes are warn-only; leak counts still fail."""
    baseline = {metric: 0.0}
    rows = compare.compare({metric: 100.0}, baseline, "web")
    assert rows[0][-1] == "fail"


@pytest.mark.parametrize(
    ("profile", "has_note"), [("web", True), ("desktop", False), (None, False)]
)
def test_report_names_warn_only_counts(compare, tmp_path, capsys, profile, has_note):
    """The web report says which counts only warn, so a count warning is clear."""
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS])
    base_path = write_baseline(tmp_path / "baseline_ci.json", BASE_METRICS)
    args = ["--results", str(results), "--baseline", str(base_path)]
    if profile:
        args += ["--profile", profile]
    assert compare.main(args) == 0
    note = (
        "On web, OBJECT_COUNT avg and OBJECT_NODE_COUNT avg only warn: "
        "they follow runner speed."
    )
    assert (note in capsys.readouterr().out) is has_note


@pytest.mark.parametrize(
    ("profile", "metric", "tolerance"),
    [
        (None, "reload_object_growth", 1),
        ("desktop", "reload_object_growth", 10),
        ("web", "reload_object_growth", 1),
        (None, "nodes_avg", 5),
        ("desktop", "nodes_avg", 5),
        ("web", "nodes_avg", 15),
    ],
)
@pytest.mark.parametrize(
    ("relative_change", "expected_status"),
    [
        (-1.01, "better"),
        (-1, "ok"),
        (0, "ok"),
        (1, "ok"),
        (1.01, "fail"),
    ],
)
def test_profile_count_boundaries(
    compare, profile, metric, tolerance, relative_change, expected_status
):
    """The limit is inclusive in both directions for each profile.

    Past the limit, web nodes_avg warns instead of failing (warn-only on web).
    """
    if expected_status == "fail" and (profile, metric) == ("web", "nodes_avg"):
        expected_status = "warn"
    baseline = {metric: 100.0}
    current = {metric: 100.0 + tolerance * relative_change}
    rows = compare.compare(current, baseline, profile)
    assert len(rows) == 1
    assert rows[0][-1] == expected_status


@pytest.mark.parametrize("profile", [None, "desktop", "web"])
@pytest.mark.parametrize(
    ("metric", "tolerance"),
    [
        ("saves", 2),
        ("objects_avg", 25),
        ("resources_avg", 2),
        ("orphans_max", 0),
        ("reload_orphans_max", 0),
    ],
)
def test_profiles_preserve_other_count_limits(compare, profile, metric, tolerance):
    """Profiles do not widen limits for unrelated count metrics.

    The limit stays the same everywhere; past it, web objects_avg warns instead
    of failing (warn-only on web).
    """
    above_status = "warn" if (profile, metric) == ("web", "objects_avg") else "fail"
    baseline = {metric: 100.0}
    at_limit = {metric: 100.0 + tolerance}
    above_limit = {metric: 100.0 + tolerance + 0.1}
    assert compare.compare(at_limit, baseline, profile)[0][-1] == "ok"
    assert compare.compare(above_limit, baseline, profile)[0][-1] == above_status


def test_zero_tolerance_override_is_respected(compare):
    """An explicit zero override is distinct from the default tolerance."""
    rule = compare.CountRule("example", "Example", 5)
    assert compare.judge_count(rule, 100, 101) == "ok"
    assert compare.judge_count(rule, 100, 101, tolerance=0) == "fail"
    assert compare.judge_count(rule, 100, 99, tolerance=0) == "better"


@pytest.mark.parametrize("profile", [None, "desktop", "web"])
def test_profiles_keep_timing_warnings_and_missing_baselines(compare, profile):
    """Profiles affect count limits, not timing or missing-baseline handling."""
    baseline = {"frame_p95_ms": 10.0}
    current = {"frame_p95_ms": 20.0, "nodes_avg": 600.0}
    rows = {row[1]: row[-1] for row in compare.compare(current, baseline, profile)}
    assert rows["Frame interval p95 (ms)"] == "warn"
    assert rows["OBJECT_NODE_COUNT avg"] == "new"
    assert all(row[-1] == "new" for row in compare.compare(current, None, profile))


def test_invalid_profile_is_rejected(compare, capsys):
    """Misspelled profiles cannot silently select the default tolerances."""
    with pytest.raises(SystemExit) as exc:
        compare.main(["--results", "runs.csv", "--profile", "mobile"])
    assert exc.value.code == 2
    assert "invalid choice" in capsys.readouterr().err


@pytest.mark.parametrize(
    ("profile", "baseline_name", "metric", "tolerance", "gated"),
    [
        ("desktop", "baseline_ci.json", "reload_object_growth", 10, True),
        ("web", "baseline_web_ci.json", "nodes_avg", 15, False),
        ("web", "baseline_web_ci.json", "reload_object_growth", 1, True),
    ],
)
def test_committed_baseline_and_profile_gate(
    compare, tmp_path, capsys, profile, baseline_name, metric, tolerance, gated
):
    """Each committed CI baseline supplies all metrics and enforces its limit.

    Past the limit a gated metric fails; web nodes_avg only warns.
    """
    baseline_path = PROJECT_ROOT / "test/benchmark" / baseline_name
    doc = json.loads(baseline_path.read_text(encoding="utf-8"))
    metrics = doc["metrics"]
    assert set(metrics) == {
        "saves",
        "objects_avg",
        "nodes_avg",
        "resources_avg",
        "orphans_max",
        "reload_orphans_max",
        "reload_object_growth",
        "frame_p95_ms",
        "frames_over_33.4ms",
        "proc_worst_avg_ms",
        "phys_worst_avg_ms",
        "mem_static_growth",
    }
    assert all(
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
        for value in metrics.values()
    )
    results = tmp_path / "runs.csv"
    args = [
        "--results",
        str(results),
        "--baseline",
        str(baseline_path),
        "--profile",
        profile,
    ]
    write_runs(results, [{**metrics, metric: metrics[metric] + tolerance}])
    assert compare.main(args) == 0
    assert "Regressions: 0." in capsys.readouterr().out
    write_runs(results, [{**metrics, metric: metrics[metric] + tolerance + 1}])
    if gated:
        assert compare.main(args) == 1
        assert "Regressions: 1." in capsys.readouterr().out
    else:
        assert compare.main(args) == 0
        assert "Regressions: 0. Warnings: 1." in capsys.readouterr().out


@pytest.mark.parametrize(
    ("profile", "baseline_name", "old_saves"),
    [
        ("desktop", "baseline_ci.json", 61),
        ("web", "baseline_web_ci.json", 60),
    ],
)
@pytest.mark.parametrize(
    ("saves", "exit_code", "icon"),
    [(0, 0, "✅"), (2, 0, "✅"), (3, 1, "❌"), ("old", 1, "❌")],
)
def test_refreshed_baselines_gate_settings_saves(
    compare, tmp_path, capsys, profile, baseline_name, old_saves, saves, exit_code, icon
):
    """Both zero-save baselines catch a return to their former save counts."""
    baseline_path = PROJECT_ROOT / "test/benchmark" / baseline_name
    metrics = json.loads(baseline_path.read_text(encoding="utf-8"))["metrics"]
    assert metrics["saves"] == 0
    saves = old_saves if saves == "old" else saves
    results = write_runs(tmp_path / "runs.csv", [{**metrics, "saves": saves}] * 3)

    assert (
        compare.main(
            [
                "--results",
                str(results),
                "--baseline",
                str(baseline_path),
                "--profile",
                profile,
            ]
        )
        == exit_code
    )
    report = capsys.readouterr().out
    assert f"| {icon} | Settings saves in 60 s | count | 0 | {saves} |" in report
    assert f"Regressions: {exit_code}." in report
