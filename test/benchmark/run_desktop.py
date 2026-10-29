# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# test/benchmark/run_desktop.py
"""Run the desktop performance benchmark several times and report medians (Issue #1079).

Each run launches Godot headless on res://test/benchmark/benchmark_runner.tscn, which writes
its CSV files into its own run folder. This script then checks every run is valid, adds a few
derived metrics (stutter counts, reload object growth, memory growth) and writes:

    <out>/run_1 .. run_N/     raw CSVs + console.txt from each run
    <out>/runs.csv            one row per run, every metric
    <out>/medians.md          Markdown table (per run + median) ready for the #1079 comment

Usage (from anywhere; standard library only):

    python test/benchmark/run_desktop.py --godot "C:/path/Godot_v4.7.1-stable_win64_console.exe"

The Godot path can also come from the GODOT_BIN environment variable.
Exit code: 0 if every run is valid, 1 otherwise.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import platform
import statistics
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
RUNNER_SCENE = "res://test/benchmark/benchmark_runner.tscn"
RUN_TIMEOUT_S = 300

# Frame-interval thresholds (ms). 33.4 ms = at least one dropped frame at 60 FPS.
STUTTER_THRESHOLDS_MS = (25.0, 33.4, 50.0)

# Metrics shown in medians.md, in order: (column in runs.csv, label in the table).
REPORT_METRICS = [
    ("frame_avg_ms", "Frame interval avg (ms)"),
    ("frame_p95_ms", "Frame interval p95 (ms)"),
    ("frame_max_ms", "Frame interval max (ms)"),
    ("frames_over_25ms", "Frames > 25 ms"),
    ("frames_over_33.4ms", "Frames > 33.4 ms (dropped)"),
    ("frames_over_50ms", "Frames > 50 ms"),
    ("proc_worst_avg_ms", "Process, worst frame per second, avg (ms)"),
    ("proc_worst_p95_ms", "Process, worst frame per second, p95 (ms)"),
    ("proc_worst_max_ms", "Process, worst frame per second, max (ms)"),
    ("phys_worst_avg_ms", "Physics, worst frame per second, avg (ms)"),
    ("phys_worst_p95_ms", "Physics, worst frame per second, p95 (ms)"),
    ("phys_worst_max_ms", "Physics, worst frame per second, max (ms)"),
    ("fps_min", "FPS, lowest second"),
    ("mem_static_start", "MEMORY_STATIC at 1 s (bytes)"),
    ("mem_static_end", "MEMORY_STATIC at 60 s (bytes)"),
    ("mem_static_growth", "MEMORY_STATIC growth (bytes)"),
    ("mem_static_max", "MEMORY_STATIC_MAX (bytes)"),
    ("objects_avg", "OBJECT_COUNT avg"),
    ("nodes_avg", "OBJECT_NODE_COUNT avg"),
    ("resources_avg", "OBJECT_RESOURCE_COUNT avg"),
    ("orphans_max", "OBJECT_ORPHAN_NODE_COUNT max (gameplay)"),
    ("saves", "Settings saves in 60 s"),
    ("reload_orphans_max", "Reload loop: orphans max"),
    ("reload_object_growth", "Reload loop: OBJECT_COUNT growth over 10 cycles"),
    ("fuel_end", "Fuel left (validity)"),
    ("ammo_end", "Ammo left (validity)"),
]


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    stamp = dt.datetime.now().astimezone().strftime("%Y%m%d_%H%M%S")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--godot",
        default=os.environ.get("GODOT_BIN"),
        help="Path to the Godot 4.7.1 console executable (or set GODOT_BIN).",
    )
    parser.add_argument("--runs", type=int, default=3, help="Number of runs (default 3).")
    parser.add_argument(
        "--out",
        type=Path,
        default=PROJECT_ROOT / "bench_results" / stamp,
        help="Output folder (default: <project>/bench_results/<timestamp>).",
    )
    parser.add_argument(
        "--keep-going",
        action="store_true",
        help="Continue with the remaining runs after an invalid run.",
    )
    args = parser.parse_args()
    if not args.godot:
        parser.error("Godot executable not given: use --godot or set GODOT_BIN.")
    if args.runs < 1:
        parser.error("--runs must be at least 1.")
    return args


def read_csv(path: Path) -> list[dict[str, str]]:
    """Read a CSV file into a list of row dicts."""
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def to_number(value: str) -> float | str:
    """Convert a CSV cell to float where possible."""
    try:
        return float(value)
    except ValueError:
        return value


def run_once(godot: str, run_dir: Path) -> tuple[bool, str]:
    """Run the benchmark once. Returns (valid, reason)."""
    run_dir.mkdir(parents=True, exist_ok=True)
    cmd = [
        godot,
        "--headless",
        "--path",
        str(PROJECT_ROOT),
        RUNNER_SCENE,
        "--",
        f"--out={run_dir.as_posix()}",
    ]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=RUN_TIMEOUT_S,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False, f"timed out after {RUN_TIMEOUT_S} s"
    except OSError as exc:
        return False, f"could not start Godot: {exc}"

    console = proc.stdout + ("\n--- stderr ---\n" + proc.stderr if proc.stderr else "")
    (run_dir / "console.txt").write_text(console, encoding="utf-8")

    if "BENCH,done,valid" not in proc.stdout:
        return False, "no BENCH,done,valid line (see console.txt)"
    if proc.returncode != 0:
        return False, f"exit code {proc.returncode}"
    if not (run_dir / "summary.csv").is_file():
        return False, "summary.csv missing"
    return True, "valid"


def collect_metrics(run_dir: Path) -> dict[str, float | str]:
    """Combine summary.csv with metrics derived from the other CSVs of one run."""
    metrics: dict[str, float | str] = {
        key: to_number(value) for key, value in read_csv(run_dir / "summary.csv")[0].items()
    }

    frames = [float(r["interval_ms"]) for r in read_csv(run_dir / "frames_interval_ms.csv")]
    for limit in STUTTER_THRESHOLDS_MS:
        label = f"frames_over_{limit:g}ms"
        metrics[label] = float(sum(1 for f in frames if f > limit))

    seconds = read_csv(run_dir / "seconds.csv")
    mem = [float(r["mem_static"]) for r in seconds]
    metrics["mem_static_start"] = mem[0]
    metrics["mem_static_end"] = mem[-1]
    metrics["mem_static_growth"] = mem[-1] - mem[0]
    metrics["mem_static_max"] = max(float(r["mem_static_max"]) for r in seconds)
    metrics["fps_min"] = min(float(r["fps"]) for r in seconds)
    metrics["objects_avg"] = statistics.fmean(float(r["objects"]) for r in seconds)
    metrics["nodes_avg"] = statistics.fmean(float(r["nodes"]) for r in seconds)
    metrics["resources_avg"] = statistics.fmean(float(r["resources"]) for r in seconds)
    metrics["orphans_max"] = max(float(r["orphans"]) for r in seconds)

    reload_rows = read_csv(run_dir / "reload.csv")
    objects = [float(r["objects"]) for r in reload_rows]
    metrics["reload_orphans_max"] = max(float(r["orphans"]) for r in reload_rows)
    metrics["reload_object_growth"] = objects[-1] - objects[0]
    return metrics


def git_info() -> str:
    """Return 'SHA' or 'SHA (dirty)' for the project, or 'unknown'."""
    try:
        sha = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        dirty = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
    return f"{sha} (dirty)" if dirty else sha


def fmt(value: float | str) -> str:
    """Format a metric for the Markdown table."""
    if isinstance(value, str):
        return value
    if abs(value) >= 1000 or value == int(value):
        return f"{value:,.0f}"
    return f"{value:.3f}"


def write_reports(out: Path, results: list[dict[str, float | str]], invalid: int) -> None:
    """Write runs.csv and medians.md."""
    columns: list[str] = []
    for row in results:
        for key in row:
            if key not in columns:
                columns.append(key)
    with (out / "runs.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(results)

    first = results[0]
    run_headers = " | ".join(f"Run {i}" for i in range(1, len(results) + 1))
    lines = [
        "## Performance baseline (desktop, headless)",
        "",
        f"- Commit: `{git_info()}`",
        f"- Godot: {first.get('godot', 'unknown')}",
        f"- OS: {platform.platform()}",
        f"- CPU: {platform.processor() or 'unknown'}",
        (
            f"- Valid runs: {len(results)}, invalid runs skipped: {invalid}; "
            "table shows each valid run and the median"
        ),
        "",
        f"| Metric | {run_headers} | Median |",
        "|---|" + "---:|" * (len(results) + 1),
    ]
    for key, label in REPORT_METRICS:
        values = [row.get(key) for row in results]
        if any(not isinstance(v, float) for v in values):
            continue
        cells = " | ".join(fmt(v) for v in values)
        lines.append(f"| {label} | {cells} | {fmt(statistics.median(values))} |")
    lines.append("")
    (out / "medians.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    """Run the benchmark N times and write the reports."""
    args = parse_args()
    out: Path = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    print(f"Project: {PROJECT_ROOT}")
    print(f"Output:  {out}")

    results: list[dict[str, float | str]] = []
    invalid = 0
    for index in range(1, args.runs + 1):
        run_dir = out / f"run_{index}"
        print(f"Run {index}/{args.runs} (about 80 s)...", flush=True)
        valid, reason = run_once(args.godot, run_dir)
        print(f"  {reason}")
        if valid:
            results.append(collect_metrics(run_dir))
        else:
            invalid += 1
            if not args.keep_going:
                break

    if not results:
        print("No valid runs; nothing to report.")
        return 1
    write_reports(out, results, invalid)
    print(f"Wrote {out / 'runs.csv'} and {out / 'medians.md'}")
    if invalid:
        print("At least one run was invalid; do not use these numbers as the baseline.")
    return 1 if invalid else 0


if __name__ == "__main__":
    sys.exit(main())
