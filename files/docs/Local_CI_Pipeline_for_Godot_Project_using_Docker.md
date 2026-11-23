# Local CI Pipeline Setup for Sky Lock Assault
<!-- markdownlint-disable line-length -->

This guide runs the project's CI checks locally on Windows with Docker
Desktop: GDScript format and lint, Markdown lint, YAML lint, gdUnit4 and GUT
unit tests, Playwright browser tests, and the `tests/ci` helper tests.

The image is built from the `Dockerfile` in the project root, so every check
runs in the same Ubuntu 24.04 environment as the GitHub Actions runners. The
scripts that run the checks are in `workspace/`.

## What the Image Contains

| Tool                         | Version                                           | Source in the `Dockerfile`           |
|------------------------------|---------------------------------------------------|--------------------------------------|
| Godot + Web export templates | 4.7.1 stable (SHA512-verified)                    | `godotengine/godot-builds` release   |
| gdUnit4                      | 6.2.0                                             | baked into `/project/addons/gdUnit4` |
| GUT                          | 9.7.1                                             | baked into `/project/addons/gut`     |
| pytest, Playwright, plugins  | pinned in `requirements.txt`                      | Chromium only                        |
| gdtoolkit (gdformat, gdlint) | 4.5.0 (CI: latest 4.*)                            | Python venv in `/opt/venv`           |
| yamllint                     | 1.38.0                                            | Python venv in `/opt/venv`           |
| markdownlint-cli2            | 0.12.1                                            | npm (CI uses v0.24.0)                |

The container runs as the non-root user `godotuser`, with `/project` as its
working directory.

Mounting your clone on `/project` hides the addons baked into the image. The
tests use the addons in your own `addons/` folder, which Git ignores, so keep
gdUnit4 and GUT installed there (see [Prerequisites](#prerequisites)).

## Prerequisites

- **OS**: Windows 10 or 11, 64-bit.
- **Docker Desktop**: installed and running, with the WSL2 backend.
- **Project**: a clone of <https://github.com/ikostan/SkyLockAssault>, with
  PowerShell open in the project root.
- **Addons in your clone**: `addons/gdUnit4` (6.2.0) and `addons/gut`
  (9.7.1), the versions CI uses. `run_gut_unit_tests.sh` downloads GUT 9.5.0
  if `addons/gut` is missing; `run_gdunit4_unit_tests.sh` doesn't download
  gdUnit4.

## Step 1: Build the Image

```powershell
docker build -t sky-lock-assault-pipeline:latest .
```

Rebuild after a change to the `Dockerfile`, `requirements.txt` or
`.github/scripts/requirements-docs.txt`. To check the image's `HEALTHCHECK`,
see [Local CI/CD Container Health Validation](Local_CI_CD_Container_Health_Validation.md).

## Step 2: Run a Script

Every script runs the same way. Replace `<script>` with a name from the
table below:

```powershell
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/<script>
```

| Script                      | What it runs                                                     | Output                                     |
|-----------------------------|------------------------------------------------------------------|--------------------------------------------|
| `run_pipeline.sh`           | Every check below, in order; stops at the first failure          | `artifacts/`                               |
| `run_gdlint.sh`             | `gdformat --diff --check` and `gdlint` on `scripts/`             | console                                    |
| `run_markdown_lint.sh`      | `markdownlint-cli2` on all Markdown files, **with `--fix`**      | fixes files in place                       |
| `run_yaml_lint.sh`          | `yamllint` on `.github/workflows/*.yml`                          | console                                    |
| `run_gdunit4_unit_tests.sh` | gdUnit4 suites in `test/gdunit4`                                 | `reports/`                                 |
| `run_gut_unit_tests.sh`     | GUT suites in `test/gut`, using `.gutconfig.json`                | console                                    |
| `run_browser_tests.sh`      | Web export, local server, Playwright tests                       | `artifacts/report_<suite>.html` and `.xml` |
| `test_injection.sh`         | Production-style Web export with a test salt, served for playing | `export/web/`                              |

The scripts are in `workspace/`, not the project root. Running
`/project/run_unit_tests.sh` fails with `No such file or directory`.

### Full Pipeline

> [!WARNING]
> This script runs `git restore export_presets.cfg scripts/core/globals.gd`,
> which discards uncommitted edits to those two files. Commit or stash them
> before you run it.

```powershell
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/run_pipeline.sh
```

The steps run in this order:

1. GDScript format check and lint.
2. Markdown lint (with `--fix`).
3. YAML lint.
4. gdUnit4 tests.
5. GUT tests.
6. Salt and `ci` feature-flag injection, then the `Web_thread_off` export.
7. Playwright tests in `tests/` (except `tests/refactor`), against a local
   server on port 8080 inside the container.

Results go to `artifacts/`: `report_all.html`, `report.xml` and
`gdunit-reports/`.

### Unit Tests

GUT (`test/gut`):

```powershell
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/run_gut_unit_tests.sh
```

The GUT script keeps the gdUnit4 plugin out of the run: it renames
`addons/gdUnit4` to `addons/gdUnit4_disabled` first and renames it back when
the script exits.

gdUnit4 (`test/gdunit4`):

```powershell
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/run_gdunit4_unit_tests.sh
```

### Browser Tests

> [!WARNING]
> This script runs `git restore export_presets.cfg scripts/core/globals.gd`,
> which discards uncommitted edits to those two files. Commit or stash them
> before you run it.

All Playwright tests in `tests/`:

```powershell
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/run_browser_tests.sh
```

The script takes two optional arguments: the test target (default
`tests/`) and a suite name for the report files (default `all`). For one
test file:

```powershell
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/run_browser_tests.sh tests/weapon_firing_test.py weapon_firing
```

This writes `artifacts/report_weapon_firing.html` and `.xml`.

The script exports the `Web_thread_off` preset after injecting a dummy salt
into `scripts/core/globals.gd` and the `ci` feature into
`export_presets.cfg`. It restores both files with `git restore` after the
export.

### Lint Only

```powershell
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/run_gdlint.sh
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/run_markdown_lint.sh
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/run_yaml_lint.sh
```

`run_markdown_lint.sh` passes `--fix`, so it can change Markdown files in
your clone. Check `git diff` afterwards.

### Play a Local Web Build

`test_injection.sh` exports the threaded `Web` preset (the one used on
itch.io) with a test salt and serves it with the COOP/COEP headers that
threads need. Publish port 8080 so the browser on Windows can reach it:

```powershell
docker run -it --rm -p 8080:8080 -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash /project/workspace/test_injection.sh
```

Open <http://localhost:8080>, and press `Ctrl+C` to stop the server. The
script restores `scripts/core/globals.gd`, `project.godot` and
`export_presets.cfg` from backups when it exits.

## Running the CI Helper Tests (`tests/ci`)

Run the full `tests/ci` suite in the container on Windows. Many of these tests
need Linux `bash` and LF line endings, so they fail or are skipped when run
directly on Windows, even when the code is correct. Use plain `pytest` on Windows
only for individual test files that don't depend on these.

Start Docker Desktop, then run this from the project root in PowerShell:

```powershell
docker run --rm -v "${PWD}:/project" sky-lock-assault-pipeline:latest bash -c "git config --global --add safe.directory /project; git config --global --add safe.directory /project/.git; python -m pytest tests/ci/ -q --tb=short -rfE"
```

Both `safe.directory` entries are required. Without `/project/.git`, the tests
that make a local clone of the repository fail during setup with
`CalledProcessError` and exit status 128.

## Test Result Summaries on the Run Page

Each test job adds a results table to its GitHub Actions run's **Summary**
page, like the benchmark jobs do: GUT, GDUnit4, `tests/ci/` and one table per
browser shard. Each table shows passed, failed, errors, skipped and total,
then every failing test with its name and the first line of its message, and
a collapsed list of the 5 slowest tests.

`.github/scripts/test_summary.py` builds the table from the job's JUnit XML,
using only the Python standard library:

| Job            | Workflow              | XML it reads                   |
|----------------|-----------------------|--------------------------------|
| GUT            | `gut_tests.yml`       | `gut-reports/*/gut_junit.xml`  |
| GDUnit4        | `gdunit4_tests.yml`   | `reports/report_*/results.xml` |
| `tests/ci/`    | `test_ci_scripts.yml` | `reports/ci-scripts/junit.xml` |
| Browser shards | `browser_test.yml`    | `artifacts/junit.xml`          |

The step runs with `if: "always()"`, so the table also appears when the tests
fail. It only reports: the script always exits 0, so the test step alone
decides whether the job passes. A run never shows ✅ when the XML is missing
(for example, Godot crashed before the tests started), unreadable, holds 0
tests, or declares tests that have no result.

To see the report for a local run, point the script at the XML. Leave out
`--summary` to print it only, or pass a file to append it to:

```bash
python3 .github/scripts/test_summary.py --title "GUT unit tests" \
  --results "gut-reports/*/gut_junit.xml" --summary summary.md
```

Quote a glob so the script expands it, not the shell. Its tests are in
`tests/ci/test_test_summary.py`, with a real XML sample from each job in
`tests/ci/data/test_summary/`.

## Where the Tests Live

| Folder            | Framework              | Run with                                                       |
|-------------------|------------------------|----------------------------------------------------------------|
| `test/gut/`       | GUT                    | `run_gut_unit_tests.sh`                                        |
| `test/gdunit4/`   | gdUnit4                | `run_gdunit4_unit_tests.sh`                                    |
| `tests/`          | pytest + Playwright    | `run_browser_tests.sh`                                         |
| `tests/ci/`       | pytest                 | [the `tests/ci` command](#running-the-ci-helper-tests-testsci) |
| `test/benchmark/` | Godot benchmark runner | CI only (`benchmark.yml`)                                      |

## Troubleshooting

- **`/bin/bash: /project/<name>.sh: No such file or directory`**: the
  scripts are in `workspace/`. Use `/project/workspace/<name>.sh`.
- **`$'\r': command not found`**: a script was saved with Windows (CRLF)
  line endings. `.gitattributes` checks files out with LF; if an editor
  converted one, save it with LF again.
- **gdUnit4 can't find `GdUnitCmdTool.gd`**: `addons/gdUnit4` is missing
  from your clone. The copy in the image is hidden by the mount, so install
  gdUnit4 6.2.0 into `addons/gdUnit4`.
- **`addons/gdUnit4_disabled` left behind**: a GUT run was killed before
  its cleanup ran. Rename the folder back to `addons/gdUnit4`.
- **`globals.gd` or `export_presets.cfg` still modified**: a browser run
  was stopped during the export, before the files were restored. Run
  `git restore export_presets.cfg scripts/core/globals.gd`. This also
  discards your own uncommitted edits to those files, so check
  `git diff` first and keep anything you need.
- **Git reports `dubious ownership`**: the scripts add `/project` and
  `/project/.git` as safe directories themselves. For your own commands, add
  the two `git config` lines from the `tests/ci` command.
- **Port 8080 already in use**: stop whatever uses it on Windows, or
  publish another host port, for example `-p 8081:8080`, and open
  <http://localhost:8081>.
- **Markdown lint differs from CI**: the image has markdownlint-cli2 0.12.1,
  while CI uses v0.24.0, so a few rules can differ.
- **Docker build fails**: check your connection, then rebuild without the
  cache: `docker build --no-cache -t sky-lock-assault-pipeline:latest .`
- **Docker runs out of memory**: give Docker Desktop at least 4 GB of RAM.
<!-- markdownlint-enable line-length -->
