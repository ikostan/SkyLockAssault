# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# test/benchmark/run_desktop.py
"""Run the desktop performance benchmark N times and report medians (#1079).

Each run launches Godot headless on res://test/benchmark/benchmark_runner.tscn,
which writes its CSV files into its own run folder. This script then checks
that every run is valid, adds a few derived metrics (stutter counts, reload
object growth, memory growth) and writes:

    <out>/run_1 .. run_N/  raw CSVs + console.txt from each run
    <out>/runs.csv         one row per run, every metric
    <out>/medians.md       Markdown table (per run + median) for #1079

Usage (from anywhere; standard library only):

    python test/benchmark/run_desktop.py --godot <path to Godot console exe>

The Godot path can also come from the GODOT_BIN environment variable.

Every run starts from the same "returning player" state. The user's
settings.cfg is moved aside, two short headless game launches create a fresh
settings file (first launch) and load and re-save it (second launch), and
that file is copied back before every run. The user's file is restored at
the end. Use --fresh to start every run without any settings file instead.

Exit code: 0 if every run is valid, 1 otherwise.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import platform
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
RUNNER_SCENE = "res://test/benchmark/benchmark_runner.tscn"
RUN_TIMEOUT_S = 300
SETTINGS_FILE = "settings.cfg"
FIXTURE_FILE = "settings_fixture.cfg"
PRIME_LAUNCHES = 2
PRIME_QUIT_AFTER_FRAMES = "60"
PRIME_TIMEOUT_S = 120
GIT_TIMEOUT_S = 10

# CSV files benchmark_runner.gd writes into each run folder. All must be
# written by the current run, with at least one data row.
RUN_CSVS = ("summary.csv", "seconds.csv", "reload.csv", "frames_interval_ms.csv")

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
    parser.add_argument(
        "--runs", type=int, default=3, help="Number of runs (default 3)."
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=PROJECT_ROOT / "bench_results" / stamp,
        help="Output folder (default: <project>/bench_results/<timestamp>).",
    )
    parser.add_argument(
        "--fresh",
        action="store_true",
        help="Start every run without a settings file (first-launch player).",
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


def project_name() -> str:
    """Read config/name from project.godot (used for the user data folder)."""
    for line in (
        (PROJECT_ROOT / "project.godot").read_text(encoding="utf-8").splitlines()
    ):
        if line.startswith("config/name="):
            return line.split("=", 1)[1].strip().strip('"')
    return "SkyLockAssault"


def user_data_dir() -> Path:
    """Godot's user:// folder for this project on the current OS."""
    name = project_name()
    if sys.platform == "win32":
        base = Path(os.environ["APPDATA"]) / "Godot"
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot"
    else:
        base = (
            Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
            / "godot"
        )
    return base / "app_userdata" / name


def reset_settings(settings: Path) -> None:
    """Delete settings.cfg so the next run starts from defaults."""
    if settings.exists():
        settings.unlink()


def prime_settings(godot: str, settings: Path, out: Path) -> Path | None:
    """Create the returning-player settings fixture. Returns its path.

    Launch 1 starts without settings.cfg, so the game writes a fresh one.
    Launch 2 loads that file and re-saves anything it fixes, as a second
    launch by a real player would. The resulting file becomes the fixture.
    """
    reset_settings(settings)
    cmd = [
        godot,
        "--headless",
        "--path",
        str(PROJECT_ROOT),
        "--quit-after",
        PRIME_QUIT_AFTER_FRAMES,
    ]
    for launch in range(1, PRIME_LAUNCHES + 1):
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=PRIME_TIMEOUT_S,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            print(f"  prime launch {launch} failed: {exc}")
            return None
        (out / f"prime_{launch}.txt").write_text(
            proc.stdout + proc.stderr, encoding="utf-8"
        )
    if not settings.is_file():
        print("  the game did not create settings.cfg (see prime_*.txt)")
        return None
    fixture = out / FIXTURE_FILE
    shutil.copy2(settings, fixture)
    return fixture


def has_data_rows(path: Path) -> bool:
    """True if the CSV file exists and has at least one row after the header."""
    if not path.is_file():
        return False
    try:
        return bool(read_csv(path))
    except (OSError, UnicodeDecodeError, csv.Error):
        return False


def run_once(godot: str, run_dir: Path) -> tuple[bool, str]:
    """Run the benchmark once. Returns (valid, reason)."""
    run_dir.mkdir(parents=True, exist_ok=True)
    # Remove output from an earlier run in this folder (reused --out), so
    # only files written by this run can pass the checks below.
    for name in (*RUN_CSVS, "console.txt"):
        (run_dir / name).unlink(missing_ok=True)
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
    for name in RUN_CSVS:
        if not has_data_rows(run_dir / name):
            return False, f"{name} missing or empty"
    return True, "valid"


def collect_metrics(run_dir: Path) -> dict[str, float | str]:
    """Combine summary.csv with metrics derived from the other CSVs of one run."""
    metrics: dict[str, float | str] = {
        key: to_number(value)
        for key, value in read_csv(run_dir / "summary.csv")[0].items()
    }

    frames = [
        float(r["interval_ms"]) for r in read_csv(run_dir / "frames_interval_ms.csv")
    ]
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
    git = shutil.which("git")
    if git is None:
        return "unknown"
    try:
        sha = subprocess.run(
            [git, "rev-parse", "HEAD"],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT_S,
            check=True,
        ).stdout.strip()
        dirty = subprocess.run(
            [git, "status", "--porcelain"],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            timeout=GIT_TIMEOUT_S,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return "unknown"
    return f"{sha} (dirty)" if dirty else sha


def fmt(value: float | str) -> str:
    """Format a metric for the Markdown table."""
    if isinstance(value, str):
        return value
    if abs(value) >= 1000 or value == int(value):
        return f"{value:,.0f}"
    return f"{value:.3f}"


def write_reports(
    out: Path, results: list[dict[str, float | str]], invalid: int, start: str
) -> None:
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
        f"- Start state: {start}",
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
    godot = shutil.which(args.godot)
    if godot is None:
        print(f"Godot executable not found: {args.godot}")
        return 1
    out: Path = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    print(f"Project: {PROJECT_ROOT}")
    print(f"Output:  {out}")

    settings = user_data_dir() / SETTINGS_FILE
    user_backup = settings.with_name(SETTINGS_FILE + ".bench_user_backup")
    print(f"Settings: {settings} (moved aside during the runs)")
    if user_backup.exists():
        # Left over from an interrupted run. Stop instead of guessing which
        # file is the player's: never delete or overwrite either of them.
        print(f"Backup already exists: {user_backup}")
        print(
            "An earlier run was interrupted. Restore it (rename it back to "
            f"{SETTINGS_FILE}) or delete it, then run again."
        )
        return 1
    if settings.exists():
        shutil.move(settings, user_backup)

    results: list[dict[str, float | str]] = []
    invalid = 0
    fixture: Path | None = None
    if args.fresh:
        start = "fresh (no settings.cfg) for every run"
    else:
        start = (
            "returning player (settings.cfg from two short game launches, "
            "copied in before every run)"
        )
    try:
        if not args.fresh:
            print("Creating the returning-player settings fixture...", flush=True)
            fixture = prime_settings(godot, settings, out)
            if fixture is None:
                return 1
        for index in range(1, args.runs + 1):
            run_dir = out / f"run_{index}"
            print(f"Run {index}/{args.runs} (about 80 s)...", flush=True)
            reset_settings(settings)
            if fixture is not None:
                shutil.copy2(fixture, settings)
            valid, reason = run_once(godot, run_dir)
            print(f"  {reason}")
            if valid:
                results.append(collect_metrics(run_dir))
            else:
                invalid += 1
                if not args.keep_going:
                    break
    finally:
        reset_settings(settings)
        if user_backup.exists():
            shutil.move(user_backup, settings)

    if not results:
        print("No valid runs; nothing to report.")
        return 1
    write_reports(out, results, invalid, start)
    print(f"Wrote {out / 'runs.csv'} and {out / 'medians.md'}")
    if invalid:
        print("At least one run was invalid; do not use these numbers as the baseline.")
    return 1 if invalid else 0


if __name__ == "__main__":
    sys.exit(main())
