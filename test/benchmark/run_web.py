# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# test/benchmark/run_web.py
"""Run the web performance benchmark N times and report medians (#1079).

One command does everything:

1. Exports the Web_benchmark preset as a debug build (skip with --no-export).
2. Serves the build on a local port.
3. Opens it N times in Chromium (Playwright), each time in a fresh browser
   context, so every run starts with no saved settings.
4. Collects the "BENCH,..." console lines, writes the same CSV files as the
   desktop runner and the same runs.csv and medians.md.

Usage (from the project folder, with the project .venv active):

    python test/benchmark/run_web.py --godot <path to Godot console exe>

The Godot path can also come from the GODOT_BIN environment variable.
First time only: python -m playwright install chromium

By default Chromium runs headless with software rendering (SwiftShader), like
the browser tests. --headed opens a visible window that uses the GPU. Only
compare results made the same way.

Exit code: 0 if every run is valid, 1 otherwise.
"""

from __future__ import annotations

import argparse
import contextlib
import functools
import http.server
import os
import shutil
import subprocess
import sys
import threading
import time
from collections.abc import Iterator
from pathlib import Path

# Error is Playwright's base error (timeouts included).
from playwright.sync_api import Browser, ConsoleMessage, Error, Page, sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_desktop import (  # noqa: E402  (sibling script, not a package)
    PROJECT_ROOT,
    RUN_CSVS,
    add_output_arguments,
    collect_metrics,
    default_out,
    has_data_rows,
    prepare_out,
    write_reports,
)

PRESET = "Web_benchmark"
DEFAULT_BUILD_DIR = PROJECT_ROOT / "export" / "web_benchmark"
EXPORT_TIMEOUT_S = 600
RUN_TIMEOUT_S = 300
VIEWPORT = {"width": 1280, "height": 720}
GPU_WARNING_BUTTON = "#gpu-warning-dismiss-btn"
GPU_WARNING_WAIT_MS = 3000
# Same software-rendering flags as the browser tests (tests/conftest.py).
HEADLESS_ARGS = ["--enable-unsafe-swiftshader", "--disable-gpu", "--use-gl=swiftshader"]

# CSV headers, identical to the files benchmark_runner.gd writes on desktop.
SECONDS_HEADER = (
    "t_s,fps,proc_worst_ms,phys_worst_ms,"
    "mem_static,mem_static_max,objects,nodes,resources,orphans,saves"
)
RELOAD_HEADER = "cycle,orphans,objects"
FRAMES_HEADER = "interval_ms"
SUMMARY_HEADER = (
    "godot,os,env,"
    "proc_worst_n,proc_worst_avg_ms,proc_worst_p95_ms,proc_worst_max_ms,"
    "phys_worst_n,phys_worst_avg_ms,phys_worst_p95_ms,phys_worst_max_ms,"
    "frame_n,frame_avg_ms,frame_p95_ms,frame_max_ms,"
    "saves,fuel_end,ammo_end,speed_end,valid"
)


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--godot",
        default=os.environ.get("GODOT_BIN"),
        help="Path to the Godot 4.7.1 console executable (or set GODOT_BIN).",
    )
    parser.add_argument(
        "--runs", type=int, default=3, help="Number of runs (default 3)."
    )
    add_output_arguments(parser, "<web_headless|web_headed>")
    parser.add_argument(
        "--build",
        type=Path,
        default=DEFAULT_BUILD_DIR,
        help="Web build folder (default: <project>/export/web_benchmark).",
    )
    parser.add_argument(
        "--no-export",
        action="store_true",
        help="Use the existing build in --build instead of exporting first.",
    )
    parser.add_argument(
        "--headed",
        action="store_true",
        help="Show the browser window and use the GPU (default: headless).",
    )
    parser.add_argument(
        "--channel",
        help="Browser channel, e.g. 'chrome' for installed Google Chrome.",
    )
    parser.add_argument(
        "--keep-going",
        action="store_true",
        help="Continue with the remaining runs after an invalid run.",
    )
    args = parser.parse_args()
    if not args.no_export and not args.godot:
        parser.error(
            "Godot executable not given: use --godot, set GODOT_BIN, "
            "or pass --no-export to reuse an existing build."
        )
    if args.runs < 1:
        parser.error("--runs must be at least 1.")
    if args.out is None:
        mode = "web_headed" if args.headed else "web_headless"
        args.out = default_out(mode, args.name)
    return args


def export_build(godot: str, build_dir: Path, out: Path) -> bool:
    """Export the Web_benchmark preset as a debug build. Returns success."""
    build_dir.mkdir(parents=True, exist_ok=True)
    pck = build_dir / "index.pck"
    started = time.time()
    cmd = [
        godot,
        "--headless",
        "--path",
        str(PROJECT_ROOT),
        "--export-debug",
        PRESET,
        str(build_dir / "index.html"),
    ]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=EXPORT_TIMEOUT_S,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"  export failed: {exc}")
        return False
    (out / "export.txt").write_text(proc.stdout + proc.stderr, encoding="utf-8")
    # Godot can return 0 even when the export failed, so check for a fresh .pck.
    if proc.returncode != 0 or not pck.is_file() or pck.stat().st_mtime < started:
        print(f"  export failed (exit {proc.returncode}); see {out / 'export.txt'}")
        return False
    return True


class _QuietHandler(http.server.SimpleHTTPRequestHandler):
    """Static file handler that does not log every request."""

    def log_message(self, *args: object) -> None:
        """Silence per-request logging."""


@contextlib.contextmanager
def serve(build_dir: Path) -> Iterator[str]:
    """Serve build_dir on a free local port; yields the index.html URL."""
    handler = functools.partial(_QuietHandler, directory=str(build_dir))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_address[1]}/index.html"
    finally:
        server.shutdown()
        server.server_close()


def dismiss_gpu_warning(page: Page) -> None:
    """Click away the shell's 'hardware acceleration' modal if it appears."""
    button = page.locator(GPU_WARNING_BUTTON)
    try:
        button.wait_for(state="visible", timeout=GPU_WARNING_WAIT_MS)
    except Error:
        return
    button.click()


def write_csv(path: Path, header: str, rows: list[str]) -> None:
    """Write a CSV file from a header and pre-joined rows."""
    path.write_text("\n".join([header, *rows]) + "\n", encoding="utf-8")


def write_run_csvs(run_dir: Path, lines: list[str]) -> None:
    """Turn the BENCH console lines of one run into the desktop CSV files."""
    seconds, reloads, frames, summary = [], [], [], []
    for line in lines:
        kind, _, rest = line.removeprefix("BENCH,").partition(",")
        if kind == "sec":
            seconds.append(rest)
        elif kind == "reload":
            reloads.append(rest)
        elif kind == "frames":
            frames = [value for value in rest.split(";") if value]
        elif kind == "summary":
            summary = [rest]
    write_csv(run_dir / "seconds.csv", SECONDS_HEADER, seconds)
    write_csv(run_dir / "reload.csv", RELOAD_HEADER, reloads)
    write_csv(run_dir / "frames_interval_ms.csv", FRAMES_HEADER, frames)
    write_csv(run_dir / "summary.csv", SUMMARY_HEADER, summary)


def run_once(browser: Browser, url: str, run_dir: Path) -> tuple[bool, str]:
    """Run the benchmark once in a fresh browser context. Returns (valid, reason)."""
    run_dir.mkdir(parents=True, exist_ok=True)
    for name in (*RUN_CSVS, "console.txt"):
        (run_dir / name).unlink(missing_ok=True)

    console: list[str] = []

    def on_console(message: ConsoleMessage) -> None:
        """Keep every console line of the page, in order."""
        console.append(message.text)

    def on_page_error(error: Exception) -> None:
        """Keep uncaught page errors in the console log, marked as such."""
        console.append(f"[pageerror] {error}")

    reason = ""
    # A new context has empty storage, so the game starts with no saved settings.
    context = browser.new_context(viewport=VIEWPORT)
    try:
        page = context.new_page()
        page.on("console", on_console)
        page.on("pageerror", on_page_error)
        try:
            page.goto(url, wait_until="domcontentloaded")
        except Error as exc:
            # Timeout or failed main resource: an invalid run, not a crash, so
            # --keep-going still works and console.txt is still written.
            reason = f"page failed to load: {str(exc).splitlines()[0]}"
            console.append(f"[navigation] {exc}")
        else:
            dismiss_gpu_warning(page)
            try:
                page.wait_for_event(
                    "console",
                    predicate=lambda m: m.text.startswith("BENCH,done"),
                    timeout=RUN_TIMEOUT_S * 1000,
                )
            except Error:
                reason = f"no BENCH,done line within {RUN_TIMEOUT_S} s"
    finally:
        context.close()

    (run_dir / "console.txt").write_text("\n".join(console) + "\n", encoding="utf-8")
    if reason:
        return False, f"{reason} (see console.txt)"
    bench = [line for line in console if line.startswith("BENCH,")]
    if "BENCH,done,valid" not in bench:
        return False, "run reported invalid (see console.txt)"
    write_run_csvs(run_dir, bench)
    for name in RUN_CSVS:
        if not has_data_rows(run_dir / name):
            return False, f"{name} missing or empty"
    return True, "valid"


def main() -> int:
    """Export, serve and run the web benchmark N times, then write reports."""
    args = parse_args()
    out: Path = args.out.resolve()
    build_dir: Path = args.build.resolve()
    error = prepare_out(out, args.overwrite)
    if error is not None:
        print(error)
        return 1
    print(f"Project: {PROJECT_ROOT}")
    print(f"Build:   {build_dir}")
    print(f"Output:  {out}")

    if not args.no_export:
        godot = shutil.which(args.godot)
        if godot is None:
            print(f"Godot executable not found: {args.godot}")
            return 1
        print(f"Exporting {PRESET} (debug)...", flush=True)
        if not export_build(godot, build_dir, out):
            return 1
    if not (build_dir / "index.html").is_file():
        print(f"No web build in {build_dir}; run without --no-export first.")
        return 1

    mode = "headed, GPU" if args.headed else "headless, software rendering"
    results: list[dict[str, float | str]] = []
    invalid = 0
    with serve(build_dir) as url, sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            headless=not args.headed,
            args=[] if args.headed else HEADLESS_ARGS,
            channel=args.channel,
        )
        print(f"Browser: {browser.browser_type.name} {browser.version} ({mode})")
        try:
            for index in range(1, args.runs + 1):
                run_dir = out / f"run_{index}"
                print(f"Run {index}/{args.runs} (about 80 s)...", flush=True)
                valid, reason = run_once(browser, url, run_dir)
                print(f"  {reason}")
                if valid:
                    results.append(collect_metrics(run_dir))
                else:
                    invalid += 1
                    if not args.keep_going:
                        break
        finally:
            browser.close()

    if not results:
        print("No valid runs; nothing to report.")
        return 1
    start = "fresh browser context (no saved settings) for every run"
    write_reports(out, results, invalid, start, title=f"web, {mode}")
    print(f"Wrote {out / 'runs.csv'} and {out / 'medians.md'}")
    if invalid:
        print("At least one run was invalid; do not use these numbers as the baseline.")
    return 1 if invalid else 0


if __name__ == "__main__":
    sys.exit(main())
