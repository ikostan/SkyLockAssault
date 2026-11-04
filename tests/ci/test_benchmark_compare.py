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


# Automatic baselines (#1109): ratchet, rolling median and accept.

GOOD_SAVES = {**BASE_METRICS, "saves": 0.0}


def write_history_file(
    path: Path,
    baseline: dict | None = None,
    history: list[dict] | None = None,
    accepted: dict | None = None,
) -> Path:
    """Write a version 2 baseline file; history is a list of metric dicts."""
    doc = {
        "version": 2,
        "commit": "seed",
        "created": "x",
        "baseline": BASE_METRICS if baseline is None else baseline,
        "history": [
            {"run_id": f"old{i}", "commit": "c", "date": "d", "metrics": metrics}
            for i, metrics in enumerate(history or [])
        ],
        "accepted": accepted,
    }
    path.write_text(json.dumps(doc), encoding="utf-8")
    return path


def update_run(
    compare, tmp_path, metrics, base_path, run_id="r1", profile="desktop", accept=None
):
    """Run one --update pass in place; return (exit code, file, unchanged bytes?)."""
    results = write_runs(tmp_path / "runs.csv", [metrics])
    before = base_path.read_bytes()
    accept_args = [] if accept is None else ["--accept", accept]
    code = compare.main(
        [
            "--results",
            str(results),
            "--baseline",
            str(base_path),
            "--update",
            str(base_path),
            "--run-id",
            run_id,
            "--commit",
            f"sha-{run_id}",
            "--profile",
            profile,
            *accept_args,
        ]
    )
    return (
        code,
        json.loads(base_path.read_text(encoding="utf-8")),
        (before == base_path.read_bytes()),
    )


def test_ratchet_moves_only_after_three_runs_past_tolerance(compare, tmp_path, capsys):
    """Two good runs change nothing; the third drops the baseline to the worst."""
    path = write_history_file(tmp_path / "desktop.json")
    for run_id, saves in (("r1", 0.0), ("r2", 2.0)):
        code, doc, _ = update_run(
            compare, tmp_path, {**BASE_METRICS, "saves": saves}, path, run_id
        )
        assert code == 0
        assert doc["baseline"]["saves"] == 61.0
    capsys.readouterr()
    code, doc, _ = update_run(
        compare, tmp_path, {**BASE_METRICS, "saves": 1.0}, path, "r3"
    )
    assert code == 0
    assert doc["baseline"]["saves"] == 2.0
    assert "- saves: 61 → 2 (3 runs past tolerance)" in capsys.readouterr().out
    assert [run["run_id"] for run in doc["history"]] == ["r1", "r2", "r3"]
    assert doc["history"][-1]["commit"] == "sha-r3"


def test_noise_inside_tolerance_never_moves_ratchet(compare, tmp_path):
    """Runs better by exactly the tolerance do not count, however many there are."""
    path = write_history_file(tmp_path / "desktop.json")
    at_limit = {**BASE_METRICS, "objects_avg": BASE_METRICS["objects_avg"] - 25}
    for index in range(6):
        _, doc, _ = update_run(compare, tmp_path, at_limit, path, f"r{index}")
    assert doc["baseline"]["objects_avg"] == BASE_METRICS["objects_avg"]


def test_single_good_run_between_normal_runs_never_moves_ratchet(compare, tmp_path):
    """Only three consecutive runs past the tolerance move a baseline."""
    path = write_history_file(tmp_path / "desktop.json")
    pattern = [GOOD_SAVES, GOOD_SAVES, BASE_METRICS, GOOD_SAVES, BASE_METRICS]
    for index, metrics in enumerate(pattern):
        _, doc, _ = update_run(compare, tmp_path, metrics, path, f"r{index}")
    assert doc["baseline"]["saves"] == 61.0


def test_baseline_never_rises_without_accept(compare, tmp_path):
    """Passing runs just inside the worse limit never lift the baseline."""
    path = write_history_file(tmp_path / "desktop.json")
    creep = {**BASE_METRICS, "saves": 63.0}
    for index in range(4):
        code, doc, _ = update_run(compare, tmp_path, creep, path, f"r{index}")
        assert code == 0
    assert doc["baseline"]["saves"] == 61.0


@pytest.mark.parametrize(("baseline", "moved"), [(12.0, False), (13.0, True)])
def test_desktop_reload_growth_ratchet_uses_profile_tolerance(
    compare, tmp_path, baseline, moved
):
    """Desktop reload growth moves only past its tolerance of 10."""
    path = write_history_file(
        tmp_path / "desktop.json", {**BASE_METRICS, "reload_object_growth": baseline}
    )
    low = {**BASE_METRICS, "reload_object_growth": 2.0}
    for index in range(3):
        _, doc, _ = update_run(compare, tmp_path, low, path, f"r{index}")
    assert doc["baseline"]["reload_object_growth"] == (2.0 if moved else baseline)


def test_web_warn_only_counts_are_never_ratcheted(compare, tmp_path, capsys):
    """Web objects and nodes leave the baseline; gated counts still move."""
    path = write_history_file(tmp_path / "web.json")
    fast = {**GOOD_SAVES, "objects_avg": 2000.0, "nodes_avg": 400.0}
    for index in range(3):
        code, doc, _ = update_run(compare, tmp_path, fast, path, f"r{index}", "web")
        assert code == 0
    report = capsys.readouterr().out
    assert "- objects_avg:" not in report
    assert "- nodes_avg:" not in report
    assert "objects_avg" not in doc["baseline"]
    assert "nodes_avg" not in doc["baseline"]
    assert doc["baseline"]["saves"] == 0.0


def test_desktop_objects_and_nodes_are_ratcheted(compare, tmp_path):
    """The same drop on desktop moves the count baselines."""
    path = write_history_file(tmp_path / "desktop.json")
    fast = {**BASE_METRICS, "objects_avg": 2000.0, "nodes_avg": 400.0}
    for index in range(3):
        _, doc, _ = update_run(compare, tmp_path, fast, path, f"r{index}")
    assert doc["baseline"]["objects_avg"] == 2000.0
    assert doc["baseline"]["nodes_avg"] == 400.0


def test_web_warn_only_counts_warn_against_rolling_median(compare, tmp_path, capsys):
    """Web nodes are judged by the history median, not the seed, and never fail."""
    history = [{**BASE_METRICS, "nodes_avg": value} for value in (500.0, 510.0, 900.0)]
    path = write_history_file(tmp_path / "web.json", {"saves": 61.0}, history)
    jump = {**BASE_METRICS, "nodes_avg": 526.0}
    code, _, _ = update_run(compare, tmp_path, jump, path, "r1", "web")
    assert code == 0
    assert (
        "| ⚠️ | OBJECT_NODE_COUNT avg | count | 510 | 526 |" in capsys.readouterr().out
    )


@pytest.mark.parametrize(
    ("values", "median"),
    [
        ([10.0], 10.0),
        ([10.0, 20.0], 15.0),
        ([30.0, 10.0, 20.0], 20.0),
        ([1.0, 2.0, 3.0, 4.0, 100.0], 3.0),
        ([500.0, 1.0, 2.0, 3.0, 4.0, 100.0], 3.0),
    ],
)
def test_rolling_median_with_short_and_full_history(compare, tmp_path, values, median):
    """The timing reference is the median of up to the last 5 runs."""
    history = [{"frame_p95_ms": value} for value in values]
    path = write_history_file(tmp_path / "d.json", {"frame_p95_ms": 999.0}, history)
    reference = compare.build_reference(compare.load_baseline(path), "desktop")
    assert reference["frame_p95_ms"] == median


def test_timing_uses_median_and_stays_a_warning(compare, tmp_path, capsys):
    """A jump against recent history warns and is still recorded as passing."""
    history = [{**BASE_METRICS, "frame_p95_ms": 10.0}] * 3
    path = write_history_file(tmp_path / "d.json", history=history)
    slow = {**BASE_METRICS, "frame_p95_ms": 20.0}
    code, doc, _ = update_run(compare, tmp_path, slow, path)
    report = capsys.readouterr().out
    assert code == 0
    assert "| ⚠️ | Frame interval p95 (ms) | timing | 10 | 20 |" in report
    assert "Timings: median of the last 3 passing runs." in report
    assert len(doc["history"]) == 4


def test_history_keeps_last_five_runs(compare, tmp_path):
    """Older runs fall out of the history."""
    path = write_history_file(tmp_path / "d.json")
    for index in range(7):
        _, doc, _ = update_run(compare, tmp_path, BASE_METRICS, path, f"r{index}")
    assert [run["run_id"] for run in doc["history"]] == [f"r{i}" for i in range(2, 7)]
    assert set(doc["history"][0]) == {"run_id", "commit", "date", "metrics"}
    assert set(doc["history"][0]["metrics"]) == set(BASE_METRICS)


def test_failing_run_leaves_file_and_history_unchanged(compare, tmp_path):
    """An unaccepted failure exits 1 and writes nothing, even to another path."""
    path = write_history_file(tmp_path / "d.json", history=[BASE_METRICS])
    worse = {**BASE_METRICS, "saves": 64.0}
    code, _, unchanged = update_run(compare, tmp_path, worse, path)
    assert code == 1
    assert unchanged

    other = tmp_path / "other.json"
    results = str(tmp_path / "runs.csv")
    args = ["--results", results, "--baseline", str(path), "--update", str(other)]
    assert compare.main([*args, "--run-id", "r2", "--profile", "desktop"]) == 1
    assert not other.exists()


def test_failing_run_does_not_reset_the_ratchet_window(compare, tmp_path):
    """A failed run is skipped, so it neither counts toward the 3 nor resets them."""
    path = write_history_file(tmp_path / "d.json", history=[GOOD_SAVES, GOOD_SAVES])
    regress = {**GOOD_SAVES, "reload_orphans_max": 1.0}
    assert update_run(compare, tmp_path, regress, path, "bad")[0] == 1
    _, doc, _ = update_run(compare, tmp_path, GOOD_SAVES, path, "r3")
    assert doc["baseline"]["saves"] == 0.0


def test_accept_raises_only_failing_counts(compare, tmp_path, capsys):
    """Failing counts rise to this run; passing ones stay and the accept is logged."""
    path = write_history_file(tmp_path / "d.json")
    run_values = {
        **BASE_METRICS,
        "objects_avg": 2840.0,
        "nodes_avg": 505.0,
        "saves": 0.0,
    }
    code, doc, _ = update_run(
        compare, tmp_path, run_values, path, "r1", "desktop", accept="123"
    )
    assert code == 0
    assert doc["baseline"]["objects_avg"] == 2840.0
    assert doc["baseline"]["nodes_avg"] == 503.0
    assert doc["baseline"]["saves"] == 61.0
    assert [run["run_id"] for run in doc["history"]] == ["r1"]
    assert doc["accepted"]["id"] == "123"
    assert doc["accepted"]["raised"] == {"objects_avg": {"from": 2542.0, "to": 2840.0}}
    assert (
        "- objects_avg: raised to 2,840 (accepted in #123)" in capsys.readouterr().out
    )


def test_accept_keeps_other_counts_on_the_ratchet(compare, tmp_path):
    """Another count already due to drop still drops on an accepted run."""
    path = write_history_file(tmp_path / "d.json", history=[GOOD_SAVES, GOOD_SAVES])
    run_values = {**GOOD_SAVES, "objects_avg": 2840.0}
    _, doc, _ = update_run(
        compare, tmp_path, run_values, path, "r3", "desktop", accept="123"
    )
    assert doc["baseline"]["objects_avg"] == 2840.0
    assert doc["baseline"]["saves"] == 0.0


def test_raised_baseline_is_not_ratcheted_back_by_old_history(compare, tmp_path):
    """Pre-accept runs cannot lower a raised baseline; only 3 newer runs can."""
    old = [BASE_METRICS, BASE_METRICS]
    path = write_history_file(tmp_path / "d.json", history=old)
    higher = {**BASE_METRICS, "objects_avg": 2840.0}
    update_run(compare, tmp_path, higher, path, "r3", "desktop", accept="123")

    # Each run beats 2840 by more than the tolerance of 25. The accepted run is
    # still among the last 3 for the first two, so the baseline must hold.
    for run_id, objects in (("r4", 2700.0), ("r5", 2650.0)):
        lower = {**BASE_METRICS, "objects_avg": objects}
        _, doc, _ = update_run(compare, tmp_path, lower, path, run_id)
        assert doc["baseline"]["objects_avg"] == 2840.0

    # Three post-accept runs now qualify, so it drops to the worst of them.
    lowest = {**BASE_METRICS, "objects_avg": 2600.0}
    _, doc, _ = update_run(compare, tmp_path, lowest, path, "r6")
    assert doc["baseline"]["objects_avg"] == 2700.0


def test_accept_with_nothing_failing_keeps_the_last_accept(compare, tmp_path, capsys):
    """An unneeded accept records the run but not an empty accept."""
    last = {"id": "99", "raised": {"saves": {"from": 1, "to": 2}}}
    path = write_history_file(tmp_path / "d.json", accepted=last)
    code, doc, _ = update_run(
        compare, tmp_path, BASE_METRICS, path, "r1", "desktop", accept="123"
    )
    assert code == 0
    assert doc["accepted"] == last
    assert len(doc["history"]) == 1
    assert "Accept #123 raised nothing" in capsys.readouterr().out


def test_web_warning_is_not_raised_by_accept(compare, tmp_path):
    """Only failing counts rise; a web warn-only count has no baseline to raise."""
    path = write_history_file(tmp_path / "web.json")
    run_values = {**BASE_METRICS, "objects_avg": 3000.0, "resources_avg": 300.0}
    code, doc, _ = update_run(
        compare, tmp_path, run_values, path, "r1", "web", accept="123"
    )
    assert code == 0
    assert set(doc["accepted"]["raised"]) == {"resources_avg"}
    assert "objects_avg" not in doc["baseline"]


def test_version_1_file_is_read_as_baseline_with_empty_history(compare, tmp_path):
    """A version 1 file keeps its metrics and has no history or accept."""
    path = write_baseline(tmp_path / "baseline_ci.json", BASE_METRICS)
    doc = compare.load_baseline(path)
    assert doc["version"] == 2
    assert doc["baseline"] == BASE_METRICS
    assert doc["history"] == []
    assert doc["accepted"] is None
    assert doc["commit"] == "abc1234"
    assert "metrics" not in doc


def test_version_1_seed_is_updated_to_version_2(compare, tmp_path):
    """Seeding: timings judge against the seed once, then move to the history."""
    path = write_baseline(tmp_path / "baseline_ci.json", BASE_METRICS)
    slow = {**BASE_METRICS, "frame_p95_ms": 30.0}
    code, doc, _ = update_run(compare, tmp_path, slow, path)
    assert code == 0
    assert doc["version"] == 2
    assert doc["accepted"] is None
    assert doc["history"][0]["metrics"]["frame_p95_ms"] == 30.0
    assert set(doc["baseline"]) == {
        "saves",
        "objects_avg",
        "nodes_avg",
        "resources_avg",
        "orphans_max",
        "reload_orphans_max",
        "reload_object_growth",
    }
    assert compare.build_reference(doc, "desktop")["frame_p95_ms"] == 30.0


@pytest.mark.parametrize("name", ["baseline_ci.json", "baseline_web_ci.json"])
def test_committed_baselines_load_as_version_2(compare, name):
    """Task 3 can seed the branch from both committed files."""
    doc = compare.load_baseline(PROJECT_ROOT / "test/benchmark" / name)
    assert doc["history"] == []
    assert doc["baseline"]["saves"] == 0


@pytest.mark.parametrize(
    "content", ['{"version": 3}', '{"metrics": {}}', "[]", "{oops"]
)
def test_unreadable_baseline_exits_2(compare, tmp_path, content, capsys):
    """An unknown format is a setup error, not a regression or an empty baseline."""
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS])
    path = tmp_path / "bad.json"
    path.write_text(content, encoding="utf-8")
    assert compare.main(["--results", str(results), "--baseline", str(path)]) == 2
    assert "Cannot read the baseline" in capsys.readouterr().err


def test_update_without_a_baseline_file_exits_2(compare, tmp_path):
    """A missing file must not reseed the gate from this run."""
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS])
    out = tmp_path / "out.json"
    args = ["--results", str(results), "--baseline", str(tmp_path / "none.json")]
    args += ["--update", str(out), "--run-id", "r1", "--profile", "desktop"]
    assert compare.main(args) == 2
    assert not out.exists()


def test_new_count_is_added_at_this_runs_value(compare, tmp_path, capsys):
    """A count missing from the baseline starts being gated."""
    seed = {key: value for key, value in BASE_METRICS.items() if key != "saves"}
    path = write_history_file(tmp_path / "d.json", seed)
    code, doc, _ = update_run(compare, tmp_path, BASE_METRICS, path)
    assert code == 0
    assert doc["baseline"]["saves"] == 61.0
    assert "- saves: added at 61 (new metric)" in capsys.readouterr().out


def test_rerun_of_a_recorded_run_changes_nothing(compare, tmp_path, capsys):
    """Re-running a job must not count one run twice toward the ratchet."""
    path = write_history_file(tmp_path / "d.json")
    update_run(compare, tmp_path, GOOD_SAVES, path, "r1")
    update_run(compare, tmp_path, GOOD_SAVES, path, "r2")
    capsys.readouterr()
    code, doc, unchanged = update_run(compare, tmp_path, GOOD_SAVES, path, "r2")
    assert code == 0
    assert doc["baseline"]["saves"] == 61.0
    assert len(doc["history"]) == 2
    assert unchanged
    assert "Run r2 is already recorded" in capsys.readouterr().out


def test_report_only_never_fails_and_updates_nothing(compare, tmp_path, capsys):
    """A regression is shown, appended to the summary, and exits 0."""
    path = write_history_file(tmp_path / "d.json")
    before = path.read_bytes()
    worse = {**BASE_METRICS, "saves": 100.0}
    results = write_runs(tmp_path / "runs.csv", [worse])
    summary = tmp_path / "summary.md"
    code = compare.main(
        [
            "--results",
            str(results),
            "--baseline",
            str(path),
            "--summary",
            str(summary),
            "--report-only",
        ]
    )
    assert code == 0
    report = capsys.readouterr().out
    assert "Regressions: 1." in report
    assert "Report only:" in report
    assert "Report only:" in summary.read_text(encoding="utf-8")
    assert path.read_bytes() == before


def test_report_only_still_writes_the_candidate(compare, tmp_path):
    """The results artifact keeps the candidate that the accept check reads."""
    path = write_history_file(tmp_path / "d.json")
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS])
    candidate = tmp_path / "candidate.json"
    args = ["--results", str(results), "--baseline", str(path), "--report-only"]
    assert compare.main([*args, "--write-baseline", str(candidate)]) == 0
    doc = json.loads(candidate.read_text(encoding="utf-8"))
    assert doc["version"] == 1
    assert doc["metrics"]["saves"] == 61.0


@pytest.mark.parametrize(
    ("extra", "message"),
    [
        (
            [
                "--update",
                "o.json",
                "--run-id",
                "1",
                "--profile",
                "web",
                "--report-only",
            ],
            "--report-only cannot be combined",
        ),
        (["--accept", "12"], "--accept requires --update"),
        (["--update", "o.json", "--profile", "web"], "--update requires --run-id"),
        (["--update", "o.json", "--run-id", "1"], "--update requires --profile"),
        (
            ["--update", "o.json", "--run-id", "", "--profile", "web"],
            "must not be empty",
        ),
        (
            [
                "--update",
                "o.json",
                "--run-id",
                "1",
                "--profile",
                "web",
                "--accept",
                " ",
            ],
            "must not be empty",
        ),
    ],
)
def test_invalid_update_arguments_are_rejected(compare, capsys, extra, message):
    """Unsafe or incomplete update options stop before anything is read."""
    with pytest.raises(SystemExit) as exc:
        compare.main(["--results", "runs.csv", *extra])
    assert exc.value.code == 2
    assert message in capsys.readouterr().err


def test_commit_falls_back_to_github_sha(compare, tmp_path, monkeypatch):
    """Without --commit, the history records the pipeline's own SHA."""
    monkeypatch.setenv("GITHUB_SHA", "from-env")
    path = write_history_file(tmp_path / "d.json")
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS])
    args = ["--results", str(results), "--baseline", str(path), "--update", str(path)]
    assert compare.main([*args, "--run-id", "r1", "--profile", "desktop"]) == 0
    doc = json.loads(path.read_text(encoding="utf-8"))
    assert doc["history"][0]["commit"] == "from-env"
    assert doc["commit"] == "from-env"


def test_manual_accept_is_named_as_a_run_not_a_pr(compare, tmp_path, capsys):
    """A manual accept passes the run's own ID, so the summary says run, not #."""
    path = write_history_file(tmp_path / "d.json")
    higher = {**BASE_METRICS, "objects_avg": 2840.0}
    update_run(compare, tmp_path, higher, path, "412", "desktop", accept="412")
    report = capsys.readouterr().out
    assert "- objects_avg: raised to 2,840 (accepted in run 412)" in report
    assert "#412" not in report


def test_manual_accept_with_nothing_failing_is_named_as_a_run(
    compare, tmp_path, capsys
):
    """The nothing-to-raise line names the accept the same way."""
    path = write_history_file(tmp_path / "d.json")
    update_run(compare, tmp_path, BASE_METRICS, path, "412", "desktop", accept="412")
    assert "Accept run 412 raised nothing" in capsys.readouterr().out


def test_rerun_after_leaving_the_history_does_not_count_again(compare, tmp_path):
    """A run older than the history still cannot be the third ratchet run."""
    path = write_history_file(tmp_path / "d.json")
    update_run(compare, tmp_path, GOOD_SAVES, path, "old")
    for index in range(5):
        update_run(compare, tmp_path, BASE_METRICS, path, f"f{index}")
    update_run(compare, tmp_path, GOOD_SAVES, path, "n1")
    update_run(compare, tmp_path, GOOD_SAVES, path, "n2")

    _, doc, unchanged = update_run(compare, tmp_path, GOOD_SAVES, path, "old")

    assert unchanged
    assert doc["baseline"]["saves"] == 61.0
    assert "old" not in [run["run_id"] for run in doc["history"]]


def test_runs_already_in_a_seeded_history_count_as_seen(compare, tmp_path):
    """A file without seen_runs takes the IDs from its history."""
    path = write_history_file(tmp_path / "d.json", history=[BASE_METRICS])
    assert compare.load_baseline(path)["seen_runs"] == ["old0"]
    _, doc, _ = update_run(compare, tmp_path, BASE_METRICS, path, "old0")
    assert [run["run_id"] for run in doc["history"]] == ["old0"]


def test_seen_runs_keep_only_the_most_recent_ids(compare, tmp_path, monkeypatch):
    """The list of seen runs cannot grow without limit."""
    monkeypatch.setattr(compare, "SEEN_RUNS", 6)
    path = write_history_file(tmp_path / "d.json")
    for index in range(8):
        _, doc, _ = update_run(compare, tmp_path, BASE_METRICS, path, f"r{index}")
    assert doc["seen_runs"] == [f"r{index}" for index in range(2, 8)]


def test_accepted_rerun_cannot_raise_the_gate_again(compare, tmp_path, capsys):
    """Re-running an accepted run keeps the first accept and its numbers."""
    path = write_history_file(tmp_path / "d.json")
    first = {**BASE_METRICS, "objects_avg": 2840.0}
    update_run(compare, tmp_path, first, path, "r1", "desktop", accept="123")
    capsys.readouterr()

    worse = {**BASE_METRICS, "objects_avg": 3000.0}
    code, doc, unchanged = update_run(
        compare, tmp_path, worse, path, "r1", "desktop", accept="123"
    )

    assert code == 0
    assert unchanged
    assert doc["baseline"]["objects_avg"] == 2840.0
    assert doc["accepted"]["raised"]["objects_avg"]["to"] == 2840.0
    assert doc["history"][0]["metrics"]["objects_avg"] == 2840.0
    assert "Run r1 is already recorded" in capsys.readouterr().out


def test_failing_rerun_without_accept_still_fails(compare, tmp_path):
    """A recorded run that now fails exits 1 and changes nothing."""
    path = write_history_file(tmp_path / "d.json")
    update_run(compare, tmp_path, BASE_METRICS, path, "r1")
    worse = {**BASE_METRICS, "saves": 64.0}
    code, _, unchanged = update_run(compare, tmp_path, worse, path, "r1")
    assert code == 1
    assert unchanged


@pytest.mark.parametrize(
    "content",
    [
        '{"version": 1}',
        '{"version": 1, "metrics": {}}',
        '{"version": 2}',
        '{"version": 2, "baseline": {}}',
        '{"version": 2, "baseline": []}',
        '{"version": 2, "baseline": {"saves": "61"}}',
        '{"version": 2, "baseline": {"saves": true}}',
        '{"version": 2, "baseline": {"saves": NaN}}',
        '{"version": 2, "baseline": {"saves": 1' + "0" * 400 + "}}",
        '{"version": 2, "baseline": {"saves": 1}, "history": {}}',
        '{"version": 2, "baseline": {"saves": 1}, "history": [1]}',
        '{"version": 2, "baseline": {"saves": 1}, "history": [{"run_id": "a"}]}',
        '{"version": 2, "baseline": {"a": 1}, "history": [{"metrics": {"a": "x"}}]}',
        '{"version": 2, "baseline": {"saves": 1}, "seen_runs": "a"}',
        '{"version": 2, "baseline": {"frame_p95_ms": 1.0}}',
    ],
)
def test_malformed_baseline_cannot_reset_the_gate(compare, tmp_path, content, capsys):
    """--update exits 2 and leaves a bad file alone, whatever this run measured."""
    path = tmp_path / "bad.json"
    path.write_text(content, encoding="utf-8")
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS])
    code = compare.main(
        [
            "--results",
            str(results),
            "--baseline",
            str(path),
            "--update",
            str(path),
            "--run-id",
            "r1",
            "--profile",
            "desktop",
        ]
    )
    assert code == 2
    assert path.read_text(encoding="utf-8") == content
    assert "Cannot read the baseline" in capsys.readouterr().err


@pytest.mark.parametrize("value", ["nan", "inf", "-inf"])
@pytest.mark.parametrize("metric", ["saves", "frame_p95_ms"])
@pytest.mark.parametrize("extra", [[], ["--report-only"]])
def test_non_finite_results_exit_2_and_write_nothing(
    compare, tmp_path, capsys, value, metric, extra
):
    """A bad count or timing is a setup error, even under --report-only."""
    path = write_history_file(tmp_path / "d.json")
    before = path.read_bytes()
    results = write_runs(tmp_path / "runs.csv", [{**BASE_METRICS, metric: value}])
    summary = tmp_path / "summary.md"
    candidate = tmp_path / "candidate.json"
    args = ["--results", str(results), "--baseline", str(path)]
    args += ["--summary", str(summary), "--write-baseline", str(candidate)]
    assert compare.main([*args, *extra]) == 2
    assert metric in capsys.readouterr().err
    assert path.read_bytes() == before
    assert not summary.exists()
    assert not candidate.exists()


def test_non_finite_results_do_not_update_the_baseline(compare, tmp_path):
    """--update rejects the run, so it never reaches the history."""
    path = write_history_file(tmp_path / "d.json")
    bad = {**BASE_METRICS, "frame_p95_ms": "nan"}
    code, doc, unchanged = update_run(compare, tmp_path, bad, path)
    assert code == 2
    assert unchanged
    assert doc["history"] == []


@pytest.mark.parametrize("position", [0, 1, 2])
def test_one_bad_iteration_is_rejected_in_any_position(compare, tmp_path, position):
    """The median must not hide a NaN, whichever iteration it came from."""
    path = write_history_file(tmp_path / "d.json")
    runs = [dict(BASE_METRICS) for _ in range(3)]
    runs[position]["saves"] = "nan"
    results = write_runs(tmp_path / "runs.csv", runs)
    assert compare.main(["--results", str(results), "--baseline", str(path)]) == 2


def test_non_finite_column_outside_the_rules_is_ignored(compare, tmp_path):
    """Only the metrics the gate uses can stop a run."""
    path = write_history_file(tmp_path / "d.json")
    results = write_runs(tmp_path / "runs.csv", [{**BASE_METRICS, "other": "nan"}])
    assert compare.main(["--results", str(results), "--baseline", str(path)]) == 0


def test_first_update_binds_the_file_to_its_profile(compare, tmp_path):
    """A seed file takes the profile of its first update and keeps it."""
    path = write_baseline(tmp_path / "web.json", BASE_METRICS)
    _, doc, _ = update_run(compare, tmp_path, BASE_METRICS, path, "r1", "web")
    assert doc["profile"] == "web"
    code, doc, _ = update_run(compare, tmp_path, BASE_METRICS, path, "r2", "web")
    assert code == 0
    assert [run["run_id"] for run in doc["history"]] == ["r1", "r2"]


def test_other_profile_cannot_update_the_file(compare, tmp_path, capsys):
    """Web runs must not ratchet desktop counts, or the reverse."""
    path = write_history_file(tmp_path / "shared.json")
    fast = {**BASE_METRICS, "objects_avg": 2000.0}
    for index in range(3):
        update_run(compare, tmp_path, fast, path, f"w{index}", "web")
    capsys.readouterr()

    code, doc, unchanged = update_run(compare, tmp_path, fast, path, "d0", "desktop")

    assert code == 2
    assert unchanged
    assert [run["run_id"] for run in doc["history"]] == ["w0", "w1", "w2"]
    assert "is for web, not desktop" in capsys.readouterr().err


@pytest.mark.parametrize(("profile", "code"), [("desktop", 2), ("web", 0), (None, 0)])
def test_report_only_checks_the_profile_when_given(compare, tmp_path, profile, code):
    """A comparison against another platform's history is also refused."""
    path = write_history_file(tmp_path / "web.json")
    update_run(compare, tmp_path, BASE_METRICS, path, "r1", "web")
    args = ["--results", str(tmp_path / "runs.csv"), "--baseline", str(path)]
    args += ["--report-only"]
    if profile:
        args += ["--profile", profile]
    assert compare.main(args) == code


def test_missing_metric_in_recent_history_breaks_ratchet_window(compare, tmp_path):
    """A run without a count cannot be used as evidence to lower its gate."""
    missing_saves = {key: value for key, value in GOOD_SAVES.items() if key != "saves"}
    path = write_history_file(tmp_path / "d.json", history=[GOOD_SAVES, missing_saves])

    # The first two new runs still have the gap in their last 3 runs.
    for run_id in ("r1", "r2"):
        code, doc, _ = update_run(compare, tmp_path, GOOD_SAVES, path, run_id)
        assert code == 0
        assert doc["baseline"]["saves"] == 61.0

    code, doc, _ = update_run(compare, tmp_path, GOOD_SAVES, path, "r3")
    assert code == 0
    assert doc["baseline"]["saves"] == 0.0


def test_rolling_reference_uses_only_recent_values_and_seed_fallback(compare, tmp_path):
    """Missing metrics are skipped within the five-run window, not across it."""
    history = [
        {"frame_p95_ms": 100.0, "proc_worst_avg_ms": 99.0},
        {"frame_p95_ms": 10.0},
        {},
        {"frame_p95_ms": 30.0},
        {},
        {},
    ]
    path = write_history_file(
        tmp_path / "d.json",
        {"saves": 61.0, "frame_p95_ms": 50.0, "proc_worst_avg_ms": 0.5},
        history,
    )

    reference = compare.build_reference(compare.load_baseline(path), "desktop")
    assert reference["frame_p95_ms"] == 20.0
    assert reference["proc_worst_avg_ms"] == 0.5
    assert reference["saves"] == 61.0


def test_accept_multiple_failures_to_separate_output(compare, tmp_path, monkeypatch):
    """All failed counts are recorded, while the source and passing counts stay put."""
    monkeypatch.setenv("GITHUB_SHA", "workflow-sha")
    source = write_history_file(tmp_path / "source.json")
    before = source.read_bytes()
    values = {**BASE_METRICS, "saves": 64.0, "resources_avg": 210.0}
    results = write_runs(tmp_path / "runs.csv", [values])
    output = tmp_path / "updated.json"

    code = compare.main(
        [
            "--results",
            str(results),
            "--baseline",
            str(source),
            "--update",
            str(output),
            "--run-id",
            "r1",
            "--profile",
            "desktop",
            "--commit",
            "measured-sha",
            "--accept",
            "123",
        ]
    )

    assert code == 0
    assert source.read_bytes() == before
    doc = json.loads(output.read_text(encoding="utf-8"))
    assert doc["accepted"]["raised"] == {
        "saves": {"from": 61.0, "to": 64.0},
        "resources_avg": {"from": 206.0, "to": 210.0},
    }
    assert doc["baseline"]["saves"] == 64.0
    assert doc["baseline"]["resources_avg"] == 210.0
    assert doc["baseline"]["nodes_avg"] == BASE_METRICS["nodes_avg"]
    assert doc["commit"] == doc["history"][0]["commit"] == "measured-sha"
    assert doc["accepted"]["commit"] == "measured-sha"


def test_update_records_iteration_medians_and_only_known_metrics(compare, tmp_path):
    """History stores the run median rather than an iteration or extra CSV data."""
    path = write_history_file(tmp_path / "d.json")
    runs = [
        {**BASE_METRICS, "saves": saves, "frame_p95_ms": timing, "extra": 10}
        for saves, timing in [(61.0, 20.0), (60.0, 10.0), (59.0, 30.0)]
    ]
    results = write_runs(tmp_path / "runs.csv", runs)
    args = ["--results", str(results), "--baseline", str(path), "--update", str(path)]

    assert compare.main([*args, "--run-id", "r1", "--profile", "desktop"]) == 0
    doc = json.loads(path.read_text(encoding="utf-8"))
    assert doc["runs"] == 3
    assert doc["history"][0]["metrics"]["saves"] == 60.0
    assert doc["history"][0]["metrics"]["frame_p95_ms"] == 20.0
    assert "extra" not in doc["history"][0]["metrics"]


@pytest.mark.parametrize("value", [float("nan"), float("inf"), True, "10"])
def test_invalid_history_metric_rejects_update_before_writing(
    compare, tmp_path, capsys, value
):
    """Bad historical values cannot poison references or produce output files."""
    path = write_history_file(tmp_path / "d.json", history=[{"frame_p95_ms": value}])
    before = path.read_bytes()
    results = write_runs(tmp_path / "runs.csv", [BASE_METRICS])
    output = tmp_path / "updated.json"
    summary = tmp_path / "summary.md"
    candidate = tmp_path / "candidate.json"

    code = compare.main(
        [
            "--results",
            str(results),
            "--baseline",
            str(path),
            "--update",
            str(output),
            "--run-id",
            "r1",
            "--profile",
            "desktop",
            "--summary",
            str(summary),
            "--write-baseline",
            str(candidate),
        ]
    )
    assert code == 2
    assert "history holds an invalid run" in capsys.readouterr().err
    assert path.read_bytes() == before
    assert not output.exists()
    assert not summary.exists()
    assert not candidate.exists()


@pytest.mark.parametrize("value", ["n/a", ""])
@pytest.mark.parametrize("metric", ["saves", "frame_p95_ms"])
@pytest.mark.parametrize("extra", [[], ["--report-only"]])
def test_non_numeric_results_exit_2_and_write_nothing(
    compare, tmp_path, capsys, value, metric, extra
):
    """A text or blank metric cell cannot silently drop the metric from the gate."""
    path = write_history_file(tmp_path / "d.json")
    before = path.read_bytes()
    results = write_runs(tmp_path / "runs.csv", [{**BASE_METRICS, metric: value}])
    summary = tmp_path / "summary.md"
    candidate = tmp_path / "candidate.json"
    args = ["--results", str(results), "--baseline", str(path)]
    args += ["--summary", str(summary), "--write-baseline", str(candidate)]
    assert compare.main([*args, *extra]) == 2
    assert metric in capsys.readouterr().err
    assert path.read_bytes() == before
    assert not summary.exists()
    assert not candidate.exists()


@pytest.mark.parametrize("position", [0, 1, 2])
def test_one_text_cell_cannot_hide_a_regression(compare, tmp_path, position):
    """A regression in the other iterations must not pass because one cell is text."""
    path = write_history_file(tmp_path / "d.json")
    runs = [{**BASE_METRICS, "saves": 500.0} for _ in range(3)]
    runs[position]["saves"] = "n/a"
    code, doc, unchanged = update_run_rows(compare, tmp_path, runs, path)
    assert code == 2
    assert unchanged
    assert doc["history"] == []


def update_run_rows(compare, tmp_path, runs, path):
    """Run one --update pass from several iterations; return like update_run."""
    results = write_runs(tmp_path / "runs.csv", runs)
    before = path.read_bytes()
    args = ["--results", str(results), "--baseline", str(path), "--update", str(path)]
    code = compare.main([*args, "--run-id", "r1", "--profile", "desktop"])
    doc = json.loads(path.read_text(encoding="utf-8"))
    return code, doc, before == path.read_bytes()


def test_short_results_row_exits_2_instead_of_crashing(compare, tmp_path, capsys):
    """A truncated runs.csv row is invalid results, not a traceback."""
    path = write_history_file(tmp_path / "d.json")
    results = tmp_path / "runs.csv"
    results.write_text("godot,saves,orphans_max\n4.7,0,0\n4.7,0\n", encoding="utf-8")
    assert compare.main(["--results", str(results), "--baseline", str(path)]) == 2
    assert "orphans_max" in capsys.readouterr().err


def test_absent_metric_column_is_still_skipped(compare, tmp_path):
    """A column the results do not have is not invalid; it is just not compared."""
    path = write_history_file(tmp_path / "d.json")
    without = {key: value for key, value in BASE_METRICS.items() if key != "saves"}
    results = write_runs(tmp_path / "runs.csv", [without])
    assert compare.main(["--results", str(results), "--baseline", str(path)]) == 0
