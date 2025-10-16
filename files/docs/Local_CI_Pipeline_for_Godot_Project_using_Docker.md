# Local CI Pipeline Setup for Sky Lock Assault
<!-- markdownlint-disable line-length -->

This README provides instructions to run the combined CI pipeline
(linting, unit tests, and browser functional tests) locally on your
Windows 10 64-bit machine using Docker Desktop. The pipeline
replicates the sequence from the GitHub Actions workflows:
`GDScript` lint/format check, `Markdown` lint, `YAML` lint, `Godot`
unit tests (using `GDUnit4 v6`), and browser functional tests
(using `Playwright` with `Python`).

This setup is tailored for your `Godot v4.5` game development project.
It uses a Docker container to ensure a consistent Ubuntu-based environment,
avoiding dependency issues on Windows. All test and lint commands are
centralized in `run_pipeline.sh` for easy execution and maintenance.
The Docker image handles setup of tools like `Godot`, `GDToolkit`,
`GDUnit4`, `yamllint`, `markdownlint-cli2`, and `Playwright`.

As you're learning game dev with Godot v4.5 on Windows 10 64-bit, this
pipeline helps you maintain code quality: linting ensures clean GDScript,
unit tests verify logic (e.g., player movement or enemy AI), and browser
tests check web-exported functionality like difficulty persistence.
Running these separately lets you iterate quickly on specific parts, like
testing a new script without full exports.

## Prerequisites

- **OS**: Windows 10 64-bit.
- **Docker Desktop**: Version 4.45 or compatible (ensure it's installed
    and running; enable WSL2 backend if prompted).
- **Project Setup**: Ensure your project is cloned from
    <https://github.com/ikostan/SkyLockAssault> and you're in the project
    root directory.
- **Godot Project**: Your Godot v4.5 project files (e.g., scripts in
    `./scripts`, tests in `./test`, etc.) must be present.
- No additional local installations needed—everything runs inside Docker.

## Step 1: Create Required Files

Create the following files in your project root (e.g.,
`C:\path\to\SkyLockAssault`):

### Dockerfile

This builds an Ubuntu-based image with all dependencies. Save it as
`Dockerfile` (no extension).

The previous Dockerfile failed due to conflicts with system-installed
Python packages (e.g., wheel from Debian). To resolve this, we've
switched to using a virtual environment (venv) for all Python installations.
This isolates the tools from the system Python, avoiding uninstall issues
and the need for --break-system-packages. Save this updated version as
Dockerfile (no extension).

The previous build failed because `gvfs-bin` is unavailable in `Ubuntu 24.04`.
We've replaced it with `gvfs`, which provides `gvfs-trash`. The `Dockerfile`
also includes `libglib2.0-bin` (for `gio`) and `kio` (for `kioclient5`)
to support `OS.move_to_trash` in your tests.

We've updated the Dockerfile to install Node.js and npm in the base
dependencies, then globally install markdownlint-cli2 via npm. This matches
the original GitHub Action, which uses a Node.js-based tool. Save this
updated version as Dockerfile (no extension).

```bash
# Use Ubuntu 24.04 as base (matches GitHub Actions runner)
FROM ubuntu:24.04

# Install base dependencies (added nodejs, npm, libglib2.0-bin, kio, gvfs)
RUN apt-get update && apt-get install -y \
    python3 python3-pip wget unzip curl git zip libxml2-utils netcat-openbsd python3-venv nodejs npm \
    libglib2.0-bin kio gvfs \
    && rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment for Python tools
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip, setuptools, and wheel in venv
RUN pip install --upgrade pip setuptools wheel

# Install GDToolkit for GDScript lint/format (gdtoolkit==4.* for Godot 4.x)
RUN pip install gdtoolkit==4.*

# Install yamllint
RUN pip install yamllint

# Install markdownlint-cli2 via npm (Node.js tool)
RUN npm install -g markdownlint-cli2

# Download Godot v4.5 binary and export templates
RUN wget https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_linux.x86_64.zip \
    && unzip Godot_v4.5-stable_linux.x86_64.zip \
    && mv Godot_v4.5-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm Godot_v4.5-stable_linux.x86_64.zip

RUN wget https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_export_templates.tpz \
    && mkdir -p ~/.local/share/godot/export_templates/4.5.stable/ \
    && unzip Godot_v4.5-stable_export_templates.tpz -d ~/.local/share/godot/export_templates/4.5.stable/ \
    && rm Godot_v4.5-stable_export_templates.tpz

# Install GDUnit4 v6
RUN mkdir -p /project/addons \
    && wget https://github.com/MikeSchulze/gdUnit4/archive/refs/tags/v6.0.0.zip \
    && unzip v6.0.0.zip -d /project/addons \
    && mv /project/addons/gdUnit4-6.0.0/addons/gdUnit4 /project/addons/gdUnit4 \
    && rm -rf /project/addons/gdUnit4-6.0.0 v6.0.0.zip

# Install Playwright and dependencies for browser tests (in venv)
RUN pip install playwright pytest-playwright pytest-asyncio \
    && playwright install-deps \
    && playwright install

# Set working directory
WORKDIR /project

# Default command (overridden when running the script)
CMD ["/bin/bash"]
```

### run_pipeline.sh

This script runs all steps in sequence. Save it as `run_pipeline.sh`
in the project root. Make it executable if needed (on Windows, Docker
will handle it).

```bash
#!/bin/bash

# Set variables
PROJECT_DIR="/project"
EXPORT_DIR="$PROJECT_DIR/export/web"
SERVER_PORT=8080
PW_TIMEOUT=10000  # Default timeout in ms; adjustable

# Function to check if a step failed
check_exit() {
  if [ $? -ne 0 ]; then
    echo "Error in $1. Exiting pipeline."
    exit 1
  fi
}

# 1. GDScript Lint and Format Check
echo "Running GDScript Format Check..."
gdformat --diff --check $PROJECT_DIR/scripts
check_exit "GDScript Format Check"

echo "Running GDScript Lint..."
gdlint $PROJECT_DIR/scripts
check_exit "GDScript Lint"

# 2. Markdown Lint
echo "Running Markdown Lint..."
markdownlint-cli2 "**/*.md" --config .markdownlint-cli2.yaml --fix
check_exit "Markdown Lint"

# 3. YAML Lint
echo "Running YAML Lint..."
yamllint -c .yamllint.yaml .github/workflows/*.yml
check_exit "YAML Lint"

# 4. Godot Unit Tests (GDUnit4 v6)
echo "Downloading GDUnit4 if needed (already in image, but ensure project addons)..."
cp -r /project/addons/gdUnit4 $PROJECT_DIR/addons/ || true  # Copy if not present

echo "Importing Resources..."
godot --headless --path $PROJECT_DIR --import --quit
check_exit "Resource Import"

echo "Running GDUnit4 Tests..."
godot --headless --path $PROJECT_DIR -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --verbose --ignoreHeadlessMode --add res://test
check_exit "GDUnit4 Tests"

# Upload reports (simulate artifact upload by copying to a reports dir)
mkdir -p $PROJECT_DIR/reports
cp -r reports/** $PROJECT_DIR/reports || true

# 5. Browser Functional Tests
echo "Exporting Godot Project to Web..."
mkdir -p $EXPORT_DIR

# Simulate firebelley/godot-export action: Run Godot export to HTML5
godot --headless --path $PROJECT_DIR --export-release "Web" $EXPORT_DIR/index.html
check_exit "Godot Web Export"

# Start web server in background
python3 -m http.server $SERVER_PORT --directory $EXPORT_DIR &
SERVER_PID=$!

# Wait for server to be ready
for i in {1..20}; do
  if curl -f http://localhost:$SERVER_PORT/index.html >/dev/null 2>&1; then
    echo "Web server ready"
    break
  fi
  sleep 1
done
if [ $i -eq 20 ]; then
  echo "Web server failed to start"
  kill $SERVER_PID
  exit 1
fi

# Run Playwright tests
echo "Running Playwright Browser Tests..."
pytest tests/difficulty_persistence_test.py -v --junitxml=$PROJECT_DIR/report.xml
check_exit "Playwright Tests"

# Generate test report summary
if [ -f $PROJECT_DIR/report.xml ]; then
  total=$(xmllint --xpath 'count(//testcase)' $PROJECT_DIR/report.xml)
  failures=$(xmllint --xpath 'count(//testcase/failure)' $PROJECT_DIR/report.xml)
  errors=$(xmllint --xpath 'count(//testcase/error)' $PROJECT_DIR/report.xml)
  skipped=$(xmllint --xpath 'count(//testcase/skipped)' $PROJECT_DIR/report.xml)
  passed=$((total - failures - errors - skipped))
  echo "Test Report Summary:"
  echo "- Total tests: $total"
  echo "- Passed: $passed"
  echo "- Failed: $failures"
  echo "- Errors: $errors"
  echo "- Skipped: $skipped"
else
  echo "No report.xml found—tests may not have run."
fi

# Cleanup: Stop server
kill $SERVER_PID

# Simulate artifact uploads (copy to host via mounted volume)
mkdir -p $PROJECT_DIR/artifacts
cp $PROJECT_DIR/report.xml $PROJECT_DIR/artifacts/ || true
cp main_menu.png $PROJECT_DIR/artifacts/ || true  # If screenshot exists
cp -r $PROJECT_DIR/reports $PROJECT_DIR/artifacts/gdunit-reports || true

echo "Pipeline completed successfully!"
```

### Additional Files

- Ensure `.markdownlint-cli2.yaml` and `.yamllint.yaml` exist in the
  project root (from your existing setup).
- For browser tests, ensure `tests/difficulty_persistence_test.py` and
  `requirements.txt` (if any) are in place.
- The `docker-compose.yml` and `default.conf` are not integrated here,
  as they are for deployment. Use them separately for serving the game
  (e.g., `docker compose up` after exporting to `./export/web`).

## Step 2: Build the Docker Image

Open PowerShell or Command Prompt in the project root and run:

```bash
docker build -t sky-lock-assault-pipeline:latest .
```

This builds the image named `sky-lock-assault-pipeline`. Run it once or
when dependencies change.

## Step 3: Run the Full Pipeline

Mount your project directory into the container and execute `run_pipeline.sh`:

```bash
docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline:latest /bin/bash /project/run_pipeline.sh
```

- `-v %CD%:/project`: Mounts your current directory (project root) to
  `/project` in the container.
- Outputs (reports, artifacts) will appear in `./reports`, `./artifacts`, etc.,
  on your host machine.
- If errors occur (e.g., missing files), the script exits early.

## Step 4: Running Individual Workflows

To run workflows separately (e.g., for quick checks while developing a new
Godot script or test), use the same Docker image. Below are sample scripts
for each major workflow. Create these as separate `.sh` files in your project
root, then run them with similar `docker run` commands.

These are extracted from the full pipeline for isolation—great for learning:
e.g., run GDScript lint after editing a script to catch errors early.

### run_gdlint.sh (GDScript Lint and Format Check)

```bash
#!/bin/bash

PROJECT_DIR="/project"

echo "Running GDScript Format Check..."
gdformat --diff --check $PROJECT_DIR/scripts
if [ $? -ne 0 ]; then echo "Format check failed."; exit 1; fi

echo "Running GDScript Lint..."
gdlint $PROJECT_DIR/scripts
if [ $? -ne 0 ]; then echo "Lint failed."; exit 1; fi

echo "GDScript Lint and Format Check completed!"
```

Run it:

```bash
docker run -it --rm -v %CD%:/project sky-lock-assault-pipeline /bin/bash /project/run_gdlint.sh
```

### run_markdown_lint.sh (Markdown Lint)

```bash
#!/bin/bash

echo "Running Markdown Lint..."
markdownlint-cli2 "**/*.md" --config .markdownlint-cli2.yaml --fix
if [ $? -ne 0 ]; then echo "Markdown lint failed."; exit 1; fi

echo "Markdown Lint completed!"
```

Run it:

```bash
docker run -it --rm -v %CD%:/project sky-lock-assault-pipeline /bin/bash /project/run_markdown_lint.sh
```

### run_yaml_lint.sh (YAML Lint)

```bash
#!/bin/bash

echo "Running YAML Lint..."
yamllint -c .yamllint.yaml .github/workflows/*.yml
if [ $? -ne 0 ]; then echo "YAML lint failed."; exit 1; fi

echo "YAML Lint completed!"
```

Run it:

```bash
docker run -it --rm -v %CD%:/project sky-lock-assault-pipeline /bin/bash /project/run_yaml_lint.sh
```

### run_unit_tests.sh (Godot Unit Tests with GDUnit4)

```bash
#!/bin/bash

PROJECT_DIR="/project"

echo "Ensuring GDUnit4 in project addons..."
cp -r /project/addons/gdUnit4 $PROJECT_DIR/addons/ || true

echo "Importing Resources..."
godot --headless --path $PROJECT_DIR --import --quit
if [ $? -ne 0 ]; then echo "Resource import failed."; exit 1; fi

echo "Running GDUnit4 Tests..."
godot --headless --path $PROJECT_DIR -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --verbose --ignoreHeadlessMode --add res://test
if [ $? -ne 0 ]; then echo "Unit tests failed."; exit 1; fi

# Simulate artifact: Copy reports
mkdir -p $PROJECT_DIR/reports
cp -r reports/** $PROJECT_DIR/reports || true

echo "Godot Unit Tests completed!"
```

Run it:

```bash
docker run -it --rm -v %CD%:/project sky-lock-assault-pipeline /bin/bash /project/run_unit_tests.sh
```

### run_browser_tests.sh (Browser Functional Tests with Playwright)

```bash
#!/bin/bash

PROJECT_DIR="/project"
EXPORT_DIR="$PROJECT_DIR/export/web"
SERVER_PORT=8080
PW_TIMEOUT=10000

echo "Exporting Godot Project to Web..."
mkdir -p $EXPORT_DIR
godot --headless --path $PROJECT_DIR --export-release "Web" $EXPORT_DIR/index.html
if [ $? -ne 0 ]; then echo "Web export failed."; exit 1; fi

# Start web server
python3 -m http.server $SERVER_PORT --directory $EXPORT_DIR &
SERVER_PID=$!

# Wait for server
for i in {1..20}; do
  if curl -f http://localhost:$SERVER_PORT/index.html >/dev/null 2>&1; then
    echo "Web server ready"
    break
  fi
  sleep 1
done
if [ $i -eq 20 ]; then
  echo "Web server failed to start"
  kill $SERVER_PID
  exit 1
fi

# Run tests
echo "Running Playwright Browser Tests..."
pytest tests/difficulty_persistence_test.py -v --junitxml=$PROJECT_DIR/report.xml
if [ $? -ne 0 ]; then echo "Browser tests failed."; kill $SERVER_PID; exit 1; fi

# Report summary
if [ -f $PROJECT_DIR/report.xml ]; then
  total=$(xmllint --xpath 'count(//testcase)' $PROJECT_DIR/report.xml)
  failures=$(xmllint --xpath 'count(//testcase/failure)' $PROJECT_DIR/report.xml)
  errors=$(xmllint --xpath 'count(//testcase/error)' $PROJECT_DIR/report.xml)
  skipped=$(xmllint --xpath 'count(//testcase/skipped)' $PROJECT_DIR/report.xml)
  passed=$((total - failures - errors - skipped))
  echo "Test Report Summary:"
  echo "- Total tests: $total"
  echo "- Passed: $passed"
  echo "- Failed: $failures"
  echo "- Errors: $errors"
  echo "- Skipped: $skipped"
else
  echo "No report.xml found."
fi

# Cleanup
kill $SERVER_PID

# Simulate artifacts
mkdir -p $PROJECT_DIR/artifacts
cp $PROJECT_DIR/report.xml $PROJECT_DIR/artifacts/ || true
cp main_menu.png $PROJECT_DIR/artifacts/ || true

echo "Browser Functional Tests completed!"
```

Run it:

```bash
docker run -it --rm -v %CD%:/project sky-lock-assault-pipeline /bin/bash /project/run_browser_tests.sh
```

## Troubleshooting

- **Docker Desktop Issues**: Ensure Docker is running and has enough
    resources (e.g., 4GB RAM allocated).
- **Permissions**: If file access issues arise, run Docker Desktop as
    administrator.
- **Timeouts**: Adjust `PW_TIMEOUT` in scripts if browser tests are slow.
- **Godot Export Failures**: Verify your project has a valid export
    preset for "Web" in Godot Editor (Project > Export > Add "Web" preset).
- **Missing Dependencies**: If a tool fails, check the Dockerfile and
    rebuild the image.
- **Windows Path Issues**: Use forward slashes in paths if editing
    scripts manually (e.g., C:/Users/...).
- **Docker Build Errors**: If the build fails, try rebuilding with
    no cache: `docker build -t sky-lock-assault-pipeline . --no-cache`.
    Ensure your internet connection is stable for downloading packages.
- **Test Failures**: If test_settings.gd or test_settings_persistence.gd
    still fail, verify that DirAccess.remove_absolute is used correctly.
    You can test interactively:
    ```bash
    docker run -it --rm -v "$($PWD.Path):/project" sky-lock-assault-pipeline /bin/bash, then check gio --version, kioclient5 --version, and gvfs-trash --version to confirm installations. If issues persist, the DirAccess approach should bypass these dependencies.
    ```
- **Slow Test Scanning**: The warnings about test suite scanning
    taking >300ms (e.g., test_settings.gd took 962ms) are normal for
    complex scenes but indicate potential optimization (e.g., simplify
    test setup or reduce resource loading).

## Testing Requirement Example

As per guidelines, here's an example GDUnit4 test for a new feature
(e.g., fuel management script in `./scripts/fuel_manager.gd`):

```gdscript
# test_fuel_manager.gd in ./test/
extends GdUnitTestSuite

func test_fuel_depletion():
    var fuel_manager = load("res://scripts/fuel_manager.gd").new()
    fuel_manager.max_fuel = 100
    fuel_manager.current_fuel = 100
    fuel_manager.deplete(10)
    assert_int(fuel_manager.current_fuel).is_equal(90)
```

For Playwright (browser automation):

```python
# example_test.py
import pytest
from playwright.async_api import async_playwright

@pytest.mark.asyncio
async def test_game_loads():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        await page.goto("http://localhost:8080/index.html")
        assert await page.title() == "Sky Lock Assault"  # Adjust to actual title
        await browser.close()
```

Run these via the pipeline or manually in the container for coverage.

This setup ensures the pipeline runs sequentially and locally, aligning
with your Godot v4.5 development workflow. If project changes
(e.g., new tools), update the Dockerfile/script accordingly.
<!-- markdownlint-enable line-length -->
