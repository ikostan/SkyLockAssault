# Performance Benchmark Guide

How to capture the performance baseline for
[#1079](https://github.com/ikostan/SkyLockAssault/issues/1079) (Part 1, before
the Milestone 27 refactor) and rerun the identical benchmark for Part 2
(after the refactor).

Status: the desktop (headless) benchmark is complete. The web benchmark
(debug export + Playwright) is not written yet.

## Contents

- [What the benchmark does](#what-the-benchmark-does)
- [Files](#files)
- [Prerequisites](#prerequisites)
- [Step 1: Single run (smoke test)](#step-1-single-run-smoke-test)
- [Step 2: Baseline run (3 runs + medians)](#step-2-baseline-run-3-runs--medians)
- [Output files](#output-files)
- [Reading the results](#reading-the-results)
- [Rerunning for Part 2](#rerunning-for-part-2)
- [Design decisions](#design-decisions)
- [Troubleshooting](#troubleshooting)

## What the benchmark does

One run of `test/benchmark/benchmark_runner.tscn` takes about 80 seconds:

1. **Setup.** Backs up the real settings file (`user://settings.cfg`), then
   sets difficulty 0.5, log level INFO and default (unmuted) volumes, and caps
   the desktop frame rate at 60 FPS.
2. **Gameplay load.** Loads `scenes/main_scene.tscn` directly (no splash or
   menus), holds `speed_up` and fires continuously. 5 s warm-up, then 60 s
   measured.
3. **Bullet drain.** Waits until all bullets have expired (they live under the
   scene root for 5 s).
4. **Reload loop.** Loads and frees `main_scene` 10 times and records orphan
   nodes and the object count after each cycle.
5. **Report.** Prints `BENCH,...` lines, writes CSV files, restores the
   settings file and quits.

It drives the game only through input actions and public state. No gameplay
code is changed.

### Metrics

Every frame:

- **Frame interval (wall clock).** What a player feels: ~16.7 ms at 60 FPS;
  spikes are stutters.

Once per second:

- **`TIME_PROCESS`** and **`TIME_PHYSICS_PROCESS`.** Godot reports the
  **worst** frame (or physics step) of the last second.
- **`TIME_FPS`.** Recorded, but meaningless headless.
- **`MEMORY_STATIC`, `MEMORY_STATIC_MAX`.** The max is debug-build only.
- **`OBJECT_COUNT`, `OBJECT_NODE_COUNT`, `OBJECT_RESOURCE_COUNT`.**
- **`OBJECT_ORPHAN_NODE_COUNT`.** Debug-build only; also recorded after each
  reload cycle.

Counted or checked once:

- **Settings saves.** One per `Globals.settings.setting_changed` emission.
- **Fuel, ammo and speed at the end.** Validity check.

### Validity

A run is **valid** only if, at the end of the measured window, fuel is above 0,
ammo is above 0 and the plane is still at max speed. Invalid runs exit with
code 2 and must not be used.

## Files

All under `test/benchmark/`:

| File                    | Purpose                                          |
|-------------------------|--------------------------------------------------|
| `benchmark_runner.gd`   | The benchmark itself (one run)                   |
| `benchmark_runner.tscn` | A plain `Node` with the script attached          |
| `run_desktop.py`        | Runs it N times, checks validity, writes medians |

GUT only scans `res://test/gut/`, so nothing in `test/benchmark/` runs as a
unit test.

## Prerequisites

- **Godot 4.7.1-stable, console build.** On Windows use
  `Godot_v4.7.1-stable_win64_console.exe`; the non-console build does not show
  the `BENCH,...` output. It does not need to be on `PATH`.
- **Python 3.10+.** Standard library only; the project `.venv` works.
- **A committed working tree.** The report records the commit SHA and marks it
  `(dirty)` if there are uncommitted changes. The baseline must name a clean
  commit.
- **A quiet machine.** Close the editor, IDE, browsers, Docker and WSL. The
  benchmark measures wall-clock frame times, so background load shows up as
  stutter.

## Step 1: Single run (smoke test)

From the project folder in PowerShell (adjust the Godot path):

```powershell
$godot = "C:\Users\super\OneDrive\Desktop\GODOT\" +
    "Godot_v4.7.1-stable_win64_console.exe"
& $godot --headless --path . `
    res://test/benchmark/benchmark_runner.tscn `
    -- --out=C:/temp/bench/smoke
```

Godot does not need to be on `PATH`; PowerShell runs it through `&`. The
backtick (`` ` ``) continues a command on the next line.

The console stays quiet for about 70 seconds (nothing is printed during the
measured window, on purpose), then prints:

- 60 `BENCH,sec,...` lines
- 10 `BENCH,reload,...` lines
- one `BENCH,summary,...` line
- `BENCH,done,valid`

The exit code is 0 for a valid run. CSV files are written to `--out`.

## Step 2: Baseline run (3 runs + medians)

1. Make sure `bench_results/` is in `.gitignore` (the default output folder is
   inside the project), or always pass `--out` outside the project.
2. Commit your work so the report shows a clean SHA.
3. Quiet the machine (see [Prerequisites](#prerequisites)).
4. Run:

    ```powershell
    python test/benchmark/run_desktop.py --godot $godot `
        --out C:/temp/bench/baseline_desktop
    ```

    `$godot` is set as in Step 1. Alternatively set `$env:GODOT_BIN = $godot`
    once and leave out `--godot`.

5. Expect about 4–5 minutes and this output:

    ```text
    Run 1/3 (about 80 s)...
      valid
    Run 2/3 (about 80 s)...
      valid
    Run 3/3 (about 80 s)...
      valid
    Wrote ...\runs.csv and ...\medians.md
    ```

Options:

| Option         | Default                               | Meaning                                           |
|----------------|---------------------------------------|---------------------------------------------------|
| `--godot`      | `GODOT_BIN` env var                   | Path to the Godot console executable              |
| `--runs`       | 3                                     | Number of runs                                    |
| `--out`        | `<project>/bench_results/<timestamp>` | Output folder                                     |
| `--keep-going` | off                                   | Continue after an invalid run instead of stopping |

The script exits with 0 only if every run was valid.

## Output files

```text
<out>/
├── medians.md          Markdown table: each run + median, ready to paste
├── runs.csv            every metric, one row per run
└── run_1 .. run_N/
    ├── console.txt             full Godot output of the run
    ├── summary.csv             one-row summary
    ├── seconds.csv             one row per measured second
    ├── frames_interval_ms.csv  one row per frame (wall-clock interval)
    └── reload.csv              one row per reload cycle
```

`medians.md` also adds derived metrics: frames over 25 / 33.4 / 50 ms, the
lowest FPS second, memory growth over the window, average object counts and the
object-count growth across the reload loop.

## Reading the results

- **Frame interval avg** should be ~16.7 ms (60 FPS cap).
- **Frames > 33.4 ms** are dropped frames at 60 FPS; this is the clearest
  stutter metric.
- **Process / physics "worst frame per second"** come from Godot's own
  monitors. They are one value per second (the worst frame in it), not an
  average frame time.
- **Settings saves** should be ~60 today (one per fuel tick). The refactor is
  expected to reduce this.
- **Reload loop object growth** above 0 means each load of `main_scene` leaves
  objects behind.

### Run-to-run variance

Stutter metrics vary a lot between runs. In the Part 1 baseline, frame-interval
p95 ranged from 18.6 to 29.5 ms and dropped frames from 19 to 59 per run. The
averages, memory, object counts and save counts were stable.

So when comparing Part 1 with Part 2, treat a stutter difference as real only
if it is large (roughly 2× or more). More runs (`--runs 5`) make the median
less sensitive to one unusually calm or noisy run; if you use 5, use 5 for both
parts.

## Rerunning for Part 2

Part 2 must change nothing except the game code under test:

- Same machine, same Godot build (4.7.1-stable console), same quiet-machine
  rules.
- Same `benchmark_runner.gd` and `run_desktop.py`. Do not edit the scenario
  constants (`DIFFICULTY`, `WARMUP_S`, `MEASURE_S`, `RELOAD_CYCLES`,
  `DESKTOP_MAX_FPS`).
- Same number of runs as Part 1.
- Post the new `medians.md` next to the Part 1 table and compare medians.

## Design decisions

These came out of building and testing the harness; keep them for Part 2.

- **Difficulty 0.5, not 2.0.** Difficulty multiplies the shot cooldown
  (`fire_rate × difficulty`), so 0.5 is the highest fire rate (~12 shots/s).
  It also keeps fuel burn at 0.5/s; at 2.0 the plane flames out about 50 s in
  and the run measures a different game.
- **Fire is injected every frame.** `player.gd` fires on
  `event.is_action_pressed("fire")`, one shot per press event, so holding the
  action fires once. The runner sends a press and release every frame from
  `_process` (not `_physics_process`, which can step twice per frame and
  triggers a "same event parsed twice" warning). The weapon cooldown decides
  which presses become shots. Ammo (1000) lasts the run; ~775 rounds are used.
- **Engine timings once per second.** Godot updates `TIME_PROCESS` and
  `TIME_PHYSICS_PROCESS` once per second with the worst frame of that second.
  Sampling them every frame only duplicates each value ~60 times and produces
  a misleading p95. Real per-frame timing comes from the wall-clock frame
  interval instead.
- **No console output while measuring.** Per-second rows are buffered and
  printed after the measured window, so console I/O is not measured.
- **Settings file backup.** Every setting change, including the per-second
  fuel mirror, saves to `user://settings.cfg`. The runner backs the file up
  before the run and restores it afterwards (desktop only).
- **Bullet drain before the reload loop.** Bullets are added to the scene root,
  not to `main_scene`, so they are waited out before counting nodes.
- **1 s pause before quitting.** Quitting right after freeing a scene with
  playing rotor sounds made Godot report the `airplane_prop.ogg` playbacks as
  leaked at exit. Waiting lets the audio server release them.
- **60 FPS cap on desktop.** Headless Godot otherwise runs uncapped, which
  does not resemble real play.

## Troubleshooting

### `The term 'Godot_v4.7.1-stable_win64_console.exe' is not recognized`

Godot is not on `PATH`. Find it:

```powershell
Get-ChildItem -Path C:\ -Recurse -ErrorAction SilentlyContinue `
    -Filter "Godot_v4.7.1-stable_win64_console.exe" |
    Select-Object -ExpandProperty FullName
```

Then call it with its full path and `&`, as in Step 1.

### `safe_load_config(): The MD5 sum of the decrypted file does not match`

The real `user://settings.cfg` was written with the GUT test encryption key,
usually by a local GUT run (see
[#1095](https://github.com/ikostan/SkyLockAssault/issues/1095)). Godot deletes
the file and loads defaults; the benchmark is not affected.

### `ObjectDB instances were leaked at exit` / `resources still in use at exit`

These appear after `BENCH,done` and do not affect the numbers. With the
current runner (1 s pause before quitting) they should not appear. If they do,
rerun once with `--verbose` and redirect the output to see the leaked classes:

```powershell
& $godot --verbose --headless --path . `
    res://test/benchmark/benchmark_runner.tscn `
    -- --out=C:/temp/bench/verbose *> C:/temp/bench/verbose.txt
Select-String -Path C:/temp/bench/verbose.txt `
    -Pattern "Leaked|still in use" -Context 0,3
```

Do not use timing numbers from a `--verbose` run.

### A run is invalid

Check the `BENCH,summary` line (or `summary.csv`): fuel, ammo and speed at the
end. Fuel at 0 means the scenario constants were changed; ammo at 0 means the
fire rate changed. Fix the cause and rerun; never report invalid runs.

### Very noisy results

Large numbers of frames over 25 ms usually mean something else was using the
machine. Close background programs and rerun. Note that some mid-run stutter
appeared in every baseline run (see
[Run-to-run variance](#run-to-run-variance)).
