# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# test/benchmark/compare.py
"""Compare a benchmark result with the committed CI baseline (#1079).

Reads the runs.csv written by run_desktop.py, takes the median of every
metric across the runs and compares it with baseline_ci.json:

- Count metrics (settings saves, live objects, orphans, reload leak) are
  stable from run to run. Getting worse beyond a small tolerance is a
  REGRESSION and makes this script exit with 1.
- Timing metrics (frame times) are noisy on shared CI runners. Getting
  clearly worse is only a WARNING.

Usage:

    python test/benchmark/compare.py --results <out>/runs.csv
        [--baseline test/benchmark/baseline_ci.json]
        [--summary <markdown file to append the table to>]
        [--write-baseline <path for a new baseline file>]
        [--title <report heading>]

With no baseline file yet, it only reports the numbers (exit 0). Use
--write-baseline to produce a baseline file from these results; commit it as
test/benchmark/baseline_ci.json to make it the reference.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import platform
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path

DEFAULT_BASELINE = Path(__file__).resolve().parent / "baseline_ci.json"
BASELINE_VERSION = 1
DEFAULT_TITLE = "Performance benchmark"


@dataclass(frozen=True)
class CountRule:
    """A stable metric: worse by more than `tolerance` is a regression."""

    key: str
    label: str
    tolerance: float


@dataclass(frozen=True)
class TimingRule:
    """A noisy metric: worse by more than `ratio` and `min_abs` is a warning."""

    key: str
    label: str
    ratio: float
    min_abs: float


# Lower is better for every metric below.
COUNT_RULES = [
    CountRule("saves", "Settings saves in 60 s", 2),
    CountRule("objects_avg", "OBJECT_COUNT avg", 25),
    CountRule("nodes_avg", "OBJECT_NODE_COUNT avg", 5),
    CountRule("resources_avg", "OBJECT_RESOURCE_COUNT avg", 2),
    CountRule("orphans_max", "Orphan nodes, gameplay (max)", 0),
    CountRule("reload_orphans_max", "Orphan nodes, reload loop (max)", 0),
    CountRule("reload_object_growth", "Reload loop object growth", 1),
]
# Wider count tolerances for one platform only, from the spread seen between
# runs on GitHub runners (PR #1094 merge run). Desktop: the reload-loop object
# count goes up and down by about 5 per cycle, so reload growth varied from 2
# to 12. Web: nodes_avg varied by about 14. The other platform keeps the tight
# value above (desktop nodes_avg and web reload growth did not vary at all).
PROFILE_TOLERANCES: dict[str, dict[str, float]] = {
    "desktop": {"reload_object_growth": 8},
    "web": {"nodes_avg": 15},
}
TIMING_RULES = [
    TimingRule("frame_p95_ms", "Frame interval p95 (ms)", 1.25, 1.0),
    TimingRule("frames_over_33.4ms", "Dropped frames (> 33.4 ms)", 1.5, 5.0),
    TimingRule("proc_worst_avg_ms", "Process, worst/s avg (ms)", 1.5, 0.5),
    TimingRule("phys_worst_avg_ms", "Physics, worst/s avg (ms)", 1.5, 0.5),
    TimingRule("mem_static_growth", "MEMORY_STATIC growth (bytes)", 1.5, 100_000),
]

OK, BETTER, WARN, FAIL, NEW = "ok", "better", "warn", "fail", "new"
ICONS = {OK: "✅", BETTER: "🟢", WARN: "⚠️", FAIL: "❌", NEW: "🆕"}


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--results", type=Path, required=True, help="runs.csv")
    parser.add_argument(
        "--baseline",
        type=Path,
        default=DEFAULT_BASELINE,
        help="Baseline JSON (default: test/benchmark/baseline_ci.json).",
    )
    parser.add_argument(
        "--summary", type=Path, help="Append the Markdown report to this file."
    )
    parser.add_argument(
        "--write-baseline",
        type=Path,
        help="Write a new baseline JSON from these results to this path.",
    )
    parser.add_argument(
        "--profile",
        choices=sorted(PROFILE_TOLERANCES),
        help="Platform whose count tolerances to use (default: the tight ones).",
    )
    parser.add_argument(
        "--title",
        default=DEFAULT_TITLE,
        help=f"Report heading (default: {DEFAULT_TITLE}).",
    )
    return parser.parse_args(argv)


def load_medians(results: Path) -> tuple[dict[str, float], int, dict[str, str]]:
    """Return (median per numeric column, number of runs, text info)."""
    with results.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"{results} has no runs")
    medians: dict[str, float] = {}
    info: dict[str, str] = {}
    for key in rows[0]:
        values = [row[key] for row in rows]
        try:
            medians[key] = statistics.median(float(v) for v in values)
        except ValueError:
            info[key] = values[0]
    return medians, len(rows), info


def judge_count(
    rule: CountRule, base: float, now: float, tolerance: float | None = None
) -> str:
    """Status of a count metric (tolerance overrides the rule's own)."""
    if tolerance is None:
        tolerance = rule.tolerance
    if now > base + tolerance:
        return FAIL
    if now < base - tolerance:
        return BETTER
    return OK


def judge_timing(rule: TimingRule, base: float, now: float) -> str:
    """Status of a timing metric."""
    if now > base * rule.ratio and now - base > rule.min_abs:
        return WARN
    if now < base / rule.ratio and base - now > rule.min_abs:
        return BETTER
    return OK


def fmt(value: float) -> str:
    """Format a number for the report."""
    if value == int(value) or abs(value) >= 1000:
        return f"{value:,.0f}"
    return f"{value:.3f}"


def fmt_change(base: float, now: float) -> str:
    """Format the change from baseline to now."""
    delta = now - base
    sign = "+" if delta > 0 else ""
    if base:
        return f"{sign}{fmt(delta)} ({sign}{delta / base * 100:.0f}%)"
    return f"{sign}{fmt(delta)}"


def compare(
    medians: dict[str, float],
    baseline: dict[str, float] | None,
    profile: str | None = None,
) -> list[tuple[str, str, float | None, float, str]]:
    """Return report rows: (kind, label, baseline, now, status)."""
    overrides = PROFILE_TOLERANCES.get(profile or "", {})
    rows: list[tuple[str, str, float | None, float, str]] = []
    for kind, rules in (("count", COUNT_RULES), ("timing", TIMING_RULES)):
        for rule in rules:
            if rule.key not in medians:
                continue
            now = medians[rule.key]
            base = None if baseline is None else baseline.get(rule.key)
            if base is None:
                status = NEW
            elif isinstance(rule, CountRule):
                status = judge_count(rule, base, now, overrides.get(rule.key))
            else:
                status = judge_timing(rule, base, now)
            rows.append((kind, rule.label, base, now, status))
    return rows


def render(
    rows: list[tuple[str, str, float | None, float, str]],
    runs: int,
    baseline_meta: dict | None,
    title: str = DEFAULT_TITLE,
) -> str:
    """Render the comparison as Markdown."""
    lines = [f"## {title}", ""]
    if baseline_meta is None:
        lines.append("No baseline yet: these numbers are not compared.")
    else:
        lines.append(
            f"Baseline: commit `{baseline_meta.get('commit', 'unknown')}`, "
            f"created {baseline_meta.get('created', 'unknown')}."
        )
    lines += [
        f"Medians of {runs} runs. Counts fail the job if they get worse;",
        "timings only warn (shared CI runners are noisy).",
        "",
        "| | Metric | Kind | Baseline | Now | Change |",
        "|---|---|---|---:|---:|---:|",
    ]
    for kind, label, base, now, status in rows:
        base_cell = "—" if base is None else fmt(base)
        change = "—" if base is None else fmt_change(base, now)
        lines.append(
            f"| {ICONS[status]} | {label} | {kind} | {base_cell} "
            f"| {fmt(now)} | {change} |"
        )
    fails = sum(1 for row in rows if row[4] == FAIL)
    warns = sum(1 for row in rows if row[4] == WARN)
    lines += ["", f"Regressions: {fails}. Warnings: {warns}.", ""]
    return "\n".join(lines)


def build_baseline(medians: dict[str, float], runs: int, info: dict[str, str]) -> dict:
    """Build a baseline document from these results."""
    keys = [rule.key for rule in COUNT_RULES + TIMING_RULES]
    return {
        "version": BASELINE_VERSION,
        "created": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "commit": os.environ.get("GITHUB_SHA", "unknown"),
        "runner": os.environ.get("RUNNER_NAME", platform.platform()),
        "godot": info.get("godot", "unknown"),
        "runs": runs,
        "metrics": {key: medians[key] for key in keys if key in medians},
    }


def main(argv: list[str] | None = None) -> int:
    """Compare results with the baseline; exit 1 on any count regression."""
    args = parse_args(argv)
    medians, runs, info = load_medians(args.results)

    baseline_doc = None
    if args.baseline.is_file():
        baseline_doc = json.loads(args.baseline.read_text(encoding="utf-8"))
    baseline = None if baseline_doc is None else baseline_doc.get("metrics", {})

    rows = compare(medians, baseline, args.profile)
    report = render(rows, runs, baseline_doc, args.title)
    print(report)
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as handle:
            handle.write(report + "\n")
    if args.write_baseline:
        doc = build_baseline(medians, runs, info)
        args.write_baseline.write_text(json.dumps(doc, indent=2) + "\n", "utf-8")
        print(f"Wrote baseline candidate: {args.write_baseline}")

    return 1 if any(row[4] == FAIL for row in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
