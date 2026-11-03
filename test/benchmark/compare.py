# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# test/benchmark/compare.py
"""Compare a benchmark result with the CI baseline and maintain it (#1079, #1109).

Reads the runs.csv written by run_desktop.py, takes the median of every
metric across the runs and compares it with the baseline file:

- Count metrics (settings saves, live objects, orphans, reload leak) are
  stable from run to run. Getting worse beyond a small tolerance is a
  REGRESSION and makes this script exit with 1. On web, the object and node
  averages follow runner speed, so they only warn (PROFILE_WARN_ONLY).
- Timing metrics (frame times) are noisy on shared CI runners. Getting
  clearly worse is only a WARNING. They are compared with the median of the
  passing runs in the file's history, as are the warn-only counts.

Usage:

    python test/benchmark/compare.py --results <out>/runs.csv
        [--baseline test/benchmark/baseline_ci.json]
        [--summary <markdown file to append the table to>]
        [--write-baseline <path for a new version 1 baseline file>]
        [--title <report heading>]
        [--profile desktop|web]
        [--report-only]
        [--update <path> --run-id <id> [--commit <sha>] [--accept <id>]]

With no baseline file yet, it only reports the numbers (exit 0). Use
--write-baseline to produce a baseline file from these results.

--update writes the updated version 2 file, which needs a passing or accepted
run and an existing baseline. A version 2 file holds:

- baseline: the count baselines the gate compares against. A seed file also
  holds the values that later follow the rolling median; each one is the
  reference only until the first passing run and is then dropped.
- history: the last 5 passing runs (run ID, commit, date, metric medians).
- accepted: the last accept that raised a count, or null.

After a passing run, a count baseline drops to the worst of the last 3 runs
if all 3 beat it by more than its tolerance. It never rises except through
--accept, which raises only the failing counts to this run's values. A failing
run without --accept writes nothing, so it is not added to the history.

--report-only never exits 1 and cannot be combined with --update. It still
appends to --summary and writes the --write-baseline candidate, which the
results artifacts carry for the accept check.
"""

from __future__ import annotations

import argparse
import copy
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
HISTORY_VERSION = 2
HISTORY_RUNS = 5
RATCHET_RUNS = 3
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
# to 12. The tolerance covers the whole 2-to-12 spread, so a baseline anywhere
# inside it cannot fail on noise. Web: nodes_avg varied by about 14 within one
# run. The other platform keeps the tight value above (desktop nodes_avg and web
# reload growth did not vary at all).
PROFILE_TOLERANCES: dict[str, dict[str, float]] = {
    "desktop": {"reload_object_growth": 10},
    "web": {"nodes_avg": 15},
}
# Count metrics that only warn on one platform. Web runs software-rendered in
# Chromium, and its object and node averages follow how fast the runner draws
# frames: main runs gave nodes_avg 459 on a fast runner and 516 to 519 on
# slower ones, with no code change. Desktop headless measures the same game
# logic without that effect and keeps the gate; on web, saves, resources,
# orphans and reload growth stay gated.
PROFILE_WARN_ONLY: dict[str, frozenset[str]] = {
    "web": frozenset({"objects_avg", "nodes_avg"}),
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
    parser.add_argument(
        "--update",
        type=Path,
        help="Write the updated version 2 baseline file to this path.",
    )
    parser.add_argument(
        "--accept",
        type=non_empty,
        metavar="ID",
        help="PR number or run ID that raises the failing counts to this run.",
    )
    parser.add_argument(
        "--run-id",
        type=non_empty,
        help="ID of this run for the history (required with --update).",
    )
    parser.add_argument(
        "--commit",
        type=non_empty,
        help="SHA this run measured (default: the GITHUB_SHA variable).",
    )
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="Print and summarize; never exit 1 and never update the baseline.",
    )
    args = parser.parse_args(argv)
    if args.report_only and args.update:
        parser.error("--report-only cannot be combined with --update")
    if args.accept and not args.update:
        parser.error("--accept requires --update")
    if args.update and not args.run_id:
        parser.error("--update requires --run-id")
    if args.update and not args.profile:
        parser.error("--update requires --profile")
    return args


def non_empty(value: str) -> str:
    """Reject an empty ID, such as an unset workflow variable."""
    if not value.strip():
        raise argparse.ArgumentTypeError("must not be empty")
    return value


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


def load_baseline(path: Path) -> dict | None:
    """Read a version 1 or 2 baseline file as version 2 (None if missing)."""
    if not path.is_file():
        return None
    raw = json.loads(path.read_text(encoding="utf-8"))
    version = raw.get("version") if isinstance(raw, dict) else None
    if version == BASELINE_VERSION:
        metrics = raw.get("metrics", {})
    elif version == HISTORY_VERSION:
        metrics = raw.get("baseline", {})
    else:
        raise ValueError(f"{path}: unsupported baseline version {version!r}")
    doc = {key: value for key, value in raw.items() if key != "metrics"}
    doc.update(
        version=HISTORY_VERSION,
        baseline=metrics,
        history=raw.get("history", []),
        accepted=raw.get("accepted"),
    )
    return doc


def rolling_keys(profile: str | None) -> set[str]:
    """Metrics compared with the history median instead of a fixed baseline."""
    warn_only = PROFILE_WARN_ONLY.get(profile or "", frozenset())
    return {rule.key for rule in TIMING_RULES} | set(warn_only)


def build_reference(doc: dict | None, profile: str | None) -> dict[str, float] | None:
    """Return the value each metric is judged against."""
    if doc is None:
        return None
    reference = dict(doc["baseline"])
    runs = doc["history"][-HISTORY_RUNS:]
    for key in rolling_keys(profile):
        values = [run["metrics"][key] for run in runs if key in run["metrics"]]
        if values:
            reference[key] = statistics.median(values)
    return reference


def ratchet_count(
    rule: CountRule, base: float, history: list[dict], profile: str | None
) -> float | None:
    """Return the new baseline if the last runs all beat it, else None."""
    recent = history[-RATCHET_RUNS:]
    values = [run["metrics"].get(rule.key) for run in recent]
    if len(values) < RATCHET_RUNS or None in values:
        return None
    tolerance = PROFILE_TOLERANCES.get(profile or "", {}).get(rule.key)
    if all(judge_count(rule, base, value, tolerance) == BETTER for value in values):
        return max(values)
    return None


def accept_name(accept: str, run_id: str) -> str:
    """Name an accept: a manual one uses the run's own ID, a label one the PR."""
    return f"run {accept}" if accept == run_id else f"#{accept}"


def record_run(doc: dict, stamp: dict[str, str], medians: dict[str, float]) -> None:
    """Add this run to the history, keeping only the most recent runs."""
    keys = [rule.key for rule in COUNT_RULES + TIMING_RULES]
    metrics = {key: medians[key] for key in keys if key in medians}
    doc["history"].append({**stamp, "metrics": metrics})
    doc["history"] = doc["history"][-HISTORY_RUNS:]


def apply_accept(
    doc: dict,
    failing: list[str],
    medians: dict[str, float],
    accept_id: str | None,
    stamp: dict[str, str],
) -> tuple[set[str], list[str]]:
    """Raise the failing counts to this run; return (raised keys, change lines)."""
    if not accept_id:
        return set(), []
    accept = accept_name(accept_id, stamp["run_id"])
    if not failing:
        return set(), [f"Accept {accept} raised nothing: no count failed."]
    baseline = doc["baseline"]
    raised = {key: {"from": baseline[key], "to": medians[key]} for key in failing}
    baseline.update({key: medians[key] for key in failing})
    doc["accepted"] = {"id": accept_id, **stamp, "raised": raised}
    changes = [
        f"{key}: raised to {fmt(medians[key])} (accepted in {accept})"
        for key in failing
    ]
    return set(failing), changes


def move_count(
    rule: CountRule, doc: dict, medians: dict[str, float], profile: str | None
) -> str | None:
    """Add or ratchet one count baseline; return its change line, if any."""
    baseline = doc["baseline"]
    base = baseline.get(rule.key)
    if base is None:
        baseline[rule.key] = medians[rule.key]
        return f"{rule.key}: added at {fmt(medians[rule.key])} (new metric)"
    target = ratchet_count(rule, base, doc["history"], profile)
    if target is None:
        return None
    baseline[rule.key] = target
    return (
        f"{rule.key}: {fmt(base)} → {fmt(target)} ({RATCHET_RUNS} runs past tolerance)"
    )


def ratchet_counts(
    doc: dict, medians: dict[str, float], raised: set[str], profile: str | None
) -> list[str]:
    """Apply the ratchet to every gated count that was not just raised."""
    skipped = raised | PROFILE_WARN_ONLY.get(profile or "", frozenset())
    rules = [
        rule for rule in COUNT_RULES if rule.key in medians and rule.key not in skipped
    ]
    lines = [move_count(rule, doc, medians, profile) for rule in rules]
    return [line for line in lines if line]


def update_baseline(
    doc: dict,
    medians: dict[str, float],
    failing: list[str],
    args: argparse.Namespace,
    info: dict[str, str],
    runs: int,
) -> tuple[dict, list[str]]:
    """Apply the accept and ratchet rules; return (new file, change lines)."""
    new = copy.deepcopy(doc)
    run_id = str(args.run_id)
    recorded = any(str(run.get("run_id")) == run_id for run in new["history"])
    if recorded and not failing:
        # A re-run must not count twice toward the ratchet.
        return new, [f"Run {run_id} is already in the history: nothing changed."]

    stamp = {
        "run_id": run_id,
        "commit": args.commit or os.environ.get("GITHUB_SHA", "unknown"),
        "date": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if not recorded:
        record_run(new, stamp, medians)
    raised, changes = apply_accept(new, failing, medians, args.accept, stamp)
    changes += ratchet_counts(new, medians, raised, args.profile)

    for key in rolling_keys(args.profile) & set(medians):
        new["baseline"].pop(key, None)
    new.update(
        created=stamp["date"],
        commit=stamp["commit"],
        runner=os.environ.get("RUNNER_NAME", platform.platform()),
        godot=info.get("godot", "unknown"),
        runs=runs,
    )
    return new, changes


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
    warn_only = PROFILE_WARN_ONLY.get(profile or "", frozenset())
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
                if status == FAIL and rule.key in warn_only:
                    status = WARN
            else:
                status = judge_timing(rule, base, now)
            rows.append((kind, rule.label, base, now, status))
    return rows


def render(
    rows: list[tuple[str, str, float | None, float, str]],
    runs: int,
    baseline_meta: dict | None,
    title: str = DEFAULT_TITLE,
    profile: str | None = None,
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
        history = baseline_meta.get("history", [])[-HISTORY_RUNS:]
        if history:
            lines.append(f"Timings: median of the last {len(history)} passing runs.")
    lines += [
        f"Medians of {runs} runs. Counts fail the job if they get worse;",
        "timings only warn (shared CI runners are noisy).",
    ]
    warn_only = PROFILE_WARN_ONLY.get(profile or "", frozenset())
    if warn_only:
        labels = [rule.label for rule in COUNT_RULES if rule.key in warn_only]
        lines.append(
            f"On {profile}, {' and '.join(labels)} only warn: they follow runner speed."
        )
    lines += [
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


def read_baseline(args: argparse.Namespace) -> dict | None:
    """Load the baseline; raise ValueError if it is unusable for this run."""
    doc = load_baseline(args.baseline)
    if args.update and doc is None:
        # Seeding from this run would silently reset the gate.
        raise ValueError(f"--update needs a baseline: {args.baseline} not found")
    return doc


def failing_counts(rows: list[tuple[str, str, float | None, float, str]]) -> list[str]:
    """Return the keys of the counts that failed in these report rows."""
    labels = {row[1] for row in rows if row[4] == FAIL}
    return [rule.key for rule in COUNT_RULES if rule.label in labels]


def finish_report(report: str, changes: list[str], report_only: bool) -> str:
    """Add the baseline changes and the report-only note to the report."""
    if changes:
        items = "\n".join(f"- {line}" for line in changes)
        report += f"\nBaseline changes:\n\n{items}\n"
    if report_only:
        report += "\nReport only: this run does not fail or update the baseline.\n"
    return report


def write_outputs(
    args: argparse.Namespace,
    report: str,
    candidate: dict,
    updated: dict | None,
) -> None:
    """Write the summary, the baseline candidate and the updated baseline."""
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as handle:
            handle.write(report + "\n")
    if args.write_baseline:
        args.write_baseline.write_text(json.dumps(candidate, indent=2) + "\n", "utf-8")
        print(f"Wrote baseline candidate: {args.write_baseline}")
    if updated is not None:
        args.update.write_text(json.dumps(updated, indent=2) + "\n", "utf-8")
        print(f"Wrote updated baseline: {args.update}")


def main(argv: list[str] | None = None) -> int:
    """
    Compare results with the baseline; exit 1 on an unaccepted count regression.

    A count past its tolerance is a regression unless the profile lists it in
    PROFILE_WARN_ONLY (on web: objects_avg and nodes_avg). Those are reported
    as warnings and, like timing warnings, do not change the exit code. Neither
    does anything under --report-only. Exit 2 means the baseline file is
    unreadable, or missing when --update needs it.
    """
    args = parse_args(argv)
    medians, runs, info = load_medians(args.results)

    try:
        baseline_doc = read_baseline(args)
    except ValueError as err:
        print(f"Cannot read the baseline: {err}", file=sys.stderr)
        return 2

    rows = compare(medians, build_reference(baseline_doc, args.profile), args.profile)
    failing = failing_counts(rows)
    blocked = bool(failing) and not args.accept

    updated, changes = None, []
    if args.update and not blocked:
        updated, changes = update_baseline(
            baseline_doc, medians, failing, args, info, runs
        )

    report = render(rows, runs, baseline_doc, args.title, args.profile)
    report = finish_report(report, changes, args.report_only)
    print(report)
    write_outputs(args, report, build_baseline(medians, runs, info), updated)

    return 1 if blocked and not args.report_only else 0


if __name__ == "__main__":
    sys.exit(main())
