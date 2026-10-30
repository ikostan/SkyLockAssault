# Performance Benchmark Guide

How to capture the performance baseline for
[#1079](https://github.com/ikostan/SkyLockAssault/issues/1079) (Part 1, before
the Milestone 27 refactor) and rerun the identical benchmark for Part 2
(after the refactor).

Status: the desktop (headless) benchmark runs natively on Windows or inside
the project's Docker image. The web benchmark runs the same scenario in
Chromium through Playwright (Step 4).

## Contents

- [What the benchmark does](#what-the-benchmark-does)
- [Files](#files)
- [Prerequisites](#prerequisites)
- [Step 1: Single run (smoke test)](#step-1-single-run-smoke-test)
- [Step 2: Baseline run (3 runs + medians)](#step-2-baseline-run-3-runs--medians)
- [Step 3: Baseline run in Docker](#step-3-baseline-run-in-docker)
- [Step 4: Web benchmark](#step-4-web-benchmark)
- [Native vs Docker](#native-vs-docker)
- [Where results go](#where-results-go)
- [Output files](#output-files)
- [Reading the results](#reading-the-results)
- [Rerunning for Part 2](#rerunning-for-part-2)
- [CI benchmark](#ci-benchmark)
- [Design decisions](#design-decisions)
- [Troubleshooting](#troubleshooting)

## What the benchmark does

One run of `test/benchmark/benchmark_runner.tscn` takes about 80 seconds:

1. **Setup.** Backs up the real settings file (`user://settings.cfg`), then
   sets difficulty 0.5, log level INFO and default (unmuted) volumes, pins the
   other saved settings to their defaults (`max_fuel` 100, debug logging and
   the FPS counter off), and caps the desktop frame rate at 60 FPS.
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
ammo is above 0 and the plane is still at max speed. Exit codes of
`benchmark_runner.gd`:

- `0`: valid run.
- `1`: setup failed. The settings file could not be backed up, or a backup
  from an interrupted run already exists; nothing was changed.
- `2`: invalid run (fuel, ammo or speed check failed).
- `3`: the settings file could not be put back; the original is kept as
  `settings.cfg.bench_backup`.

Only use runs that exit with 0.

## Files

All under `test/benchmark/`:

| File                    | Purpose                                          |
|-------------------------|--------------------------------------------------|
| `benchmark_runner.gd`   | The benchmark itself (one run)                   |
| `benchmark_runner.tscn` | A plain `Node` with the script attached          |
| `run_desktop.py`        | Runs it N times, checks validity, writes medians |
| `run_web.py`            | Same, in Chromium (`Web_benchmark` export)       |
| `compare.py`            | Compares medians with the CI baseline            |
| `baseline_ci.json`      | Desktop CI baseline (committed from a CI run)    |
| `baseline_web_ci.json`  | Web CI baseline (committed from a CI run)        |

GUT only scans `res://test/gut/`, so nothing in `test/benchmark/` runs as a
unit test.

## Prerequisites

- **Godot 4.7.1-stable, console build.** On Windows use
  `Godot_v4.7.1-stable_win64_console.exe`; the non-console build does not show
  the `BENCH,...` output. It does not need to be on `PATH`.
- **Python 3.10+.** `run_desktop.py` and `compare.py` need only the standard
  library; `run_web.py` also needs Playwright (see Step 4). The project
  `.venv` works.
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
    -- --out=bench_results/desktop/smoke
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

1. Commit your work so the report shows a clean SHA.
2. Quiet the machine (see [Prerequisites](#prerequisites)).
3. Run:

    ```powershell
    python test/benchmark/run_desktop.py --godot $godot --name baseline
    ```

    Results go to `bench_results/desktop/baseline/` (see
    [Where results go](#where-results-go)). Leave out `--name` to use a
    timestamp instead.

    `$godot` is set as in Step 1. Alternatively set `$env:GODOT_BIN = $godot`
    once and leave out `--godot`.

4. Expect about 4–5 minutes and this output:

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

- `--godot`: path to the Godot console executable. Defaults to the
  `GODOT_BIN` environment variable.
- `--runs`: number of runs. Default 3.
- `--name`: results folder name instead of the timestamp.
- `--out`: exact output folder; overrides the default
  `bench_results/<desktop|docker>/<name or timestamp>`.
- `--fresh`: start every run without a settings file (first-launch player)
  instead of the default returning-player state.
- `--keep-going`: continue after an invalid run instead of stopping.

The script exits with 0 only if every run was valid, and with 1 straight
away if the Godot path does not exist.

Every run starts from the same **returning-player** state:

1. The script moves your real `settings.cfg` aside.
2. It launches the game headless twice for a moment (`--quit-after 60`). The
   first launch has no settings file, so the game writes a fresh one; the
   second launch loads it and re-saves anything it fixes, as a real second
   launch would.
3. That file is saved as `settings_fixture.cfg` and copied in before every
   run.
4. At the end your own `settings.cfg` is put back, even if a run fails.

Why not start without a settings file? Because some behaviour only happens
when saved settings exist. Starting fresh hid the reload-loop object leak
(0 instead of about +1 per reload) and about 30 live objects. Why not use
your own file? Because it differs between machines and changes over time,
and the settings are encrypted with a per-device key, so a committed fixture
would not load elsewhere. Use `--fresh` only to compare the two states.

## Step 3: Baseline run in Docker

The project `Dockerfile` (image `sky-lock-assault-pipeline`) already contains
Godot 4.7.1 (`/usr/local/bin/godot`), its export templates, Python 3 and git.
The project folder is mounted into the container, so it runs exactly the same
runner and wrapper as the native run. Nothing is copied into the image, so
script changes do not need a rebuild.

1. Build the image once (skip if it exists):

    ```powershell
    docker build -t sky-lock-assault-pipeline:latest .
    ```

2. Record the image ID for the results comment. The image is rebuilt often,
   so Part 2 does not rely on it staying the same (see
   [Rerunning for Part 2](#rerunning-for-part-2)):

    ```powershell
    docker image inspect sky-lock-assault-pipeline:latest --format "{{.Id}}"
    ```

3. Quiet the host (the WSL2 VM shares its CPU) and run, from the project
   folder:

    ```powershell
    docker run --rm --cpus=4 --memory=8g `
        -v "${PWD}:/project" -w /project `
        -e GODOT_BIN=/usr/local/bin/godot `
        sky-lock-assault-pipeline:latest `
        bash -c "git config --global --add safe.directory /project &&
            godot --headless --path . --import &&
            python3 test/benchmark/run_desktop.py --name baseline"
    ```

    Each line inside the `bash -c "..."` string ends with `&&`, so bash reads
    it as one chain of three commands. Do not split a command in the middle.

4. Results land in `bench_results/docker/baseline/` in the project folder on
   Windows: the runner detects the container and picks the `docker` folder,
   and the project folder is mounted, so no extra mount is needed.

What each part does:

- `--cpus=4 --memory=8g` fixes the container's resources. Use the same values
  for Part 2.
- `GODOT_BIN` tells the wrapper where Godot is inside the image.
- `safe.directory` lets git read the mounted folder (it belongs to a different
  user inside the container); without it the report shows the commit as
  `unknown`.
- `--import` builds the project's import cache for the Linux build. It is
  quick when nothing changed.
- `--rm` throws the container away afterwards, including its `user://`
  folder, so the host settings file is never touched.

The commit may show `(dirty)` inside the container even when it is clean on
Windows, because git on Linux can see Windows line endings as changes.

## Step 4: Web benchmark

`run_web.py` does everything in one command:

1. Exports the `Web_benchmark` preset as a **debug** build to
   `export/web_benchmark/`.
2. Serves that folder on a free local port.
3. Opens it in Chromium N times, each time in a fresh browser context, so
   every run starts with no saved settings.
4. Collects the `BENCH,...` console lines and writes the same `run_N/` CSV
   files, `runs.csv` and `medians.md` as the desktop runner.

The `Web_benchmark` preset is a copy of `Web_thread_off` that keeps
`test/benchmark/` in the build and sets the `benchmark` feature tag.
`project.godot` has `run/main_scene.benchmark`, so only that build opens the
benchmark instead of the menus. The `Web` and `Web_thread_off` builds are
unchanged.

First time only, in the project `.venv`:

```powershell
pip install -r requirements.txt
python -m playwright install chromium
```

Run it from the project folder:

```powershell
$godot = "<full path to Godot_v4.7.1-stable_win64_console.exe>"
python test/benchmark/run_web.py --godot $godot
```

Options:

- `--runs N`: number of runs (default 3).
- `--name <name>`: results folder name instead of the timestamp.
- `--out <dir>`: exact output folder; overrides the default
  `bench_results/<web_headless|web_headed>/<name or timestamp>`.
- `--headed`: show the browser window and use the GPU. Default is headless
  with software rendering (SwiftShader), like the browser tests.
- `--channel chrome`: use the installed Google Chrome instead of Playwright's
  Chromium.
- `--no-export`: reuse the existing build in `export/web_benchmark/`.
- `--keep-going`: continue after an invalid run.

Notes:

- Headless software rendering is slow (about 15 to 20 FPS), so web frame
  times are far above desktop. Compare web results only with web results
  made the same way (same machine, same mode, same browser).
- On the web the game cannot write CSV files, so the runner prints the
  per-frame intervals as one `BENCH,frames` line and `run_web.py` saves them.
- Web runs start without saved settings (first-launch player); desktop runs
  start as a returning player. Do not compare reload counts between the two.

## Native vs Docker

The same 3-run benchmark on the same machine (Windows 11, Intel Core Ultra 200
series CPU), medians:

| Median                       | Native Windows | Docker (WSL2, 4 CPUs) |
|------------------------------|---------------:|----------------------:|
| Frame interval avg           |       16.86 ms |              16.67 ms |
| Frame interval p95           |       29.29 ms |              17.44 ms |
| Worst frame                  |      173.64 ms |              20.28 ms |
| Frames > 33.4 ms (dropped)   |             56 |                     0 |
| Process, worst/s, avg        |        3.61 ms |               0.38 ms |
| Physics, worst/s, avg        |        9.44 ms |               1.69 ms |
| Settings saves in 60 s       |             61 |                    61 |
| Reload loop object growth    |             +9 |                    +9 |

- **Docker is stutter-free and repeatable.** All three Docker runs had zero
  dropped frames and a p95 between 17.4 and 17.7 ms.
- **The stutter comes from the Windows host, not the game's own cost.** Docker
  does the same 61 settings saves per minute without stuttering. Likely causes
  (not proven): Windows Defender scanning `settings.cfg` in `%APPDATA%` on
  every write, and Windows moving Godot between performance and efficiency
  cores.
- **Game-level numbers agree.** Saves, memory, object counts and the reload
  leak match in both environments.

Recommendation: use **Docker as the primary baseline** for the Part 1 vs
Part 2 comparison, because its low noise lets Part 2 detect smaller real
changes. Keep **native Windows as a secondary, real-world data point**: it
shows the stutter Windows players may get, and whether the refactor reduces
it.

The comparison is not purely "Docker overhead": the container runs Linux,
inside the WSL2 VM, limited to 4 CPUs.

## Where results go

Every runner writes under `bench_results/` in the project folder (ignored by
git), one subfolder per kind of run. Results from different kinds are not
comparable, so they never share a folder.

```text
bench_results/
├── desktop/        run_desktop.py, native
├── docker/         run_desktop.py inside the Docker image (detected)
├── web_headless/   run_web.py (default: software rendering)
├── web_headed/     run_web.py --headed (GPU)
└── ci/             CI only: ci/desktop and ci/web (job artifacts)
```

Inside each kind, a run gets a timestamp folder (`20261030_161409`) or the
name given with `--name` (`baseline`, `before_616`, `after_616`). `--out`
still writes to any exact folder.

## Output files

```text
<out>/
├── medians.md            Markdown table: each run + median, ready to paste
├── runs.csv              every metric, one row per run
├── settings_fixture.cfg  the returning-player settings every run started from
├── prime_1.txt           output of the two fixture launches
├── prime_2.txt
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
  objects behind. It only shows with a saved settings file present, which is
  why runs start from the returning-player state.

### Run-to-run variance

Stutter metrics vary between runs, much more on native Windows than in
Docker. Natively, frame-interval p95 ranged from 18.6 to 29.5 ms and dropped
frames from 19 to 59 per run; in Docker, p95 stayed between 17.4 and 17.7 ms
with 0 dropped frames. The averages, memory, object counts and save counts
were stable in both. On GitHub runners the reload-loop object growth also
varies (2 to 12 on desktop), because the object count goes up and down by
about 5 between reloads.

So when comparing Part 1 with Part 2 natively, treat a stutter difference as
real only if it is large (roughly 2× or more). More runs (`--runs 5`) make the median
less sensitive to one unusually calm or noisy run; if you use 5, use 5 for both
parts.

## Rerunning for Part 2

Part 2 ([#625](https://github.com/ikostan/SkyLockAssault/issues/625)) must
change nothing except the game code under test. Because the Docker image is
rebuilt often (and a different image, WSL or browser version can move the
timings by itself), Part 2 runs **both commits back to back** in the same
session instead of relying on the Part 1 numbers:

- **Before:** the last `main` commit before the first Region 1–6 PR merged.
  **After:** `main` with all Region 1–6 PRs merged. Check out "before" in a
  separate worktree (`git worktree add ../sla_before <sha>`) and run the same
  commands in both folders, with `--name before` and `--name after`. The
  worktree has its own `bench_results/`; to keep both in this project's
  folder, pass the "before" run
  `--out ../SkyLockAssault/bench_results/docker/before` (or `desktop`, ...).
- Same machine, same Godot build (4.7.1-stable console), same quiet-machine
  rules, same Docker `--cpus` / `--memory` limits, same screen for web.
- Same harness. Do not edit the scenario constants (`DIFFICULTY`,
  `WARMUP_S`, `MEASURE_S`, `RELOAD_CYCLES`, `DESKTOP_MAX_FPS`, and the pinned
  settings).
- Same number of runs for both commits.
- Compare with `compare.py`:

    ```powershell
    python test/benchmark/compare.py `
        --results bench_results/docker/before/runs.csv `
        --write-baseline bench_results/docker/before.json
    python test/benchmark/compare.py `
        --results bench_results/docker/after/runs.csv `
        --baseline bench_results/docker/before.json
    ```

- Post the `compare.py` table and both `medians.md` files on #625. The
  [Part 1 numbers](https://github.com/ikostan/SkyLockAssault/issues/1079#issuecomment-6513724567)
  are a sanity check for the "before" run.

## CI benchmark

The workflow `.github/workflows/benchmark.yml` runs two jobs in parallel on
GitHub runners (`ubuntu-24.04`):

- **Desktop:** `run_desktop.py` (headless Godot). Baseline
  `baseline_ci.json`, artifact `benchmark-results`.
- **Web:** `run_web.py` (`Web_benchmark` in headless Chromium). Baseline
  `baseline_web_ci.json`, artifact `benchmark-web-results`.

It is a reusable workflow, called only from the main pipeline
(`lint_test_deploy.yml`, on every push to `main`) after the Ubuntu 24.04
tests pass. Each job runs the benchmark 3 times. Neither job blocks the
release or deploy jobs.

The web job installs only the web export templates (checked against the
release's SHA-512) and Playwright's Chromium. Runners have no GPU, so the
web job uses software rendering: its timings are far slower and noisier than
a real browser and only warn. Its counts are as reliable as on desktop.

What it checks (medians of the runs):

- **Counts** (settings saves, live objects, orphans, reload leak). Worse than
  the baseline beyond a small tolerance **fails** the job. Fewer is shown as
  🟢 better and passes.
- **Timings** (frame p95, dropped frames, process and physics time, memory
  growth). Shared runners are noisy, so these only **warn**.

Count tolerances (how much worse is allowed):

| Metric                      | Default | Desktop job | Web job |
|-----------------------------|--------:|------------:|--------:|
| Settings saves in 60 s      |       2 |           2 |       2 |
| `OBJECT_COUNT` avg          |      25 |          25 |      25 |
| `OBJECT_NODE_COUNT` avg     |       5 |           5 |  **15** |
| `OBJECT_RESOURCE_COUNT` avg |       2 |           2 |       2 |
| Orphans (gameplay, reload)  |       0 |           0 |       0 |
| Reload loop object growth   |       1 |       **8** |       1 |

Each job passes `--profile desktop` or `--profile web` to `compare.py`. The two
wider values come from the spread seen between runs on GitHub runners
(desktop reload growth 2 to 12, web node count 506 to 520); each applies only
to the platform that needs it.

Each job adds its table to the run's **Summary** page. All files are in the
job's artifact.

### Creating or updating the baseline

CI numbers differ from your PC and Docker, so the baseline must come from CI:

1. Open the **Main CI/CD Pipeline** run on `main` for the commit you want as
   the reference.
2. Download its `benchmark-results` and `benchmark-web-results` artifacts.
3. Copy `baseline_ci.json` and `baseline_web_ci.json` from them to
   `test/benchmark/` and commit both.

Downloading artifacts needs a GitHub sign-in. `main` is protected, so commit
the files on a branch and merge them through a pull request.

The first baselines come from the PR #1094 merge run (commit `ee128f9`) and
were added in [#1097](https://github.com/ikostan/SkyLockAssault/pull/1097).
Without a baseline file a job only reports the numbers and passes. Update the
baselines the same way after an intended change (for example, after a fix
that lowers settings saves), so later runs are compared with the new numbers.

### Running the comparison locally

```bash
python test/benchmark/compare.py \
    --results bench_results/desktop/<run>/runs.csv --profile desktop
python test/benchmark/compare.py \
    --results bench_results/web_headless/<run>/runs.csv \
    --baseline test/benchmark/baseline_web_ci.json --profile web
```

Other options: `--write-baseline <file>` writes a baseline from the results,
`--summary <file>` appends the table to a Markdown file, `--title <text>`
changes its heading.

Only compare results from the same kind of machine: local runs against
`baseline_ci.json` are not meaningful for timings.

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
- **Returning-player start state.** Each run used to start from whatever
  `settings.cfg` the previous run (or the user) left, so runs differed. A
  fixed "no settings file" start fixed that but hid the reload leak. The
  wrapper now generates one fresh settings file per baseline and starts every
  run from it.

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
    -- --out=bench_results/desktop/verbose *> bench_results/verbose.txt
Select-String -Path bench_results/verbose.txt `
    -Pattern "Leaked|still in use" -Context 0,3
```

Do not use timing numbers from a `--verbose` run.

### `Backup already exists: ...settings.cfg.bench_user_backup` (or `.bench_backup`)

An earlier run was interrupted before it put your settings back. The backup
may be the only copy of your settings, so the scripts stop instead of
touching it. In the folder shown, delete `settings.cfg` if it exists, rename
the backup to `settings.cfg`, and run again. If you do not need your old
settings, delete the backup instead.

### A run is invalid

Check the `BENCH,summary` line (or `summary.csv`): fuel, ammo and speed at the
end. Fuel at 0 means the scenario constants were changed; ammo at 0 means the
fire rate changed. Fix the cause and rerun; never report invalid runs.

### Very noisy results

Large numbers of frames over 25 ms usually mean something else was using the
machine. Close background programs and rerun. Note that some mid-run stutter
appeared in every baseline run (see
[Run-to-run variance](#run-to-run-variance)).
