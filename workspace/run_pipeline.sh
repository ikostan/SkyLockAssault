#!/bin/bash
# Copyright (C) 2025-2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later

# Set variables
PROJECT_DIR="/project"
EXPORT_DIR="$PROJECT_DIR/export/web_thread_off"
SERVER_PORT=8080
PW_TIMEOUT=30000

# Function to check if a step failed
check_exit() {
  if [ $? -ne 0 ]; then
    echo "❌ Error in $1. Exiting pipeline."
    exit 1
  fi
}

# Ensure Git trusts the container directory
git config --global --add safe.directory "$PROJECT_DIR" 2>/dev/null || true

# 🧹 0. Reset working tree to clean slate before running any tests
echo "🧹 Resetting repository to pristine state..."
git restore export_presets.cfg scripts/core/globals.gd 2>/dev/null || true
rm -f export_presets.cfg.bak v8_coverage_*.json 2>/dev/null || true

# Create an isolated temporary directory for addon downloads
ADDON_TMP=$(mktemp -d "${TMPDIR:-/tmp}/pipeline-addons.XXXXXX")

cleanup_workspace() {
  rm -rf "$ADDON_TMP" 2>/dev/null || true
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  git restore export_presets.cfg scripts/core/globals.gd 2>/dev/null || true
  rm -f export_presets.cfg.bak 2>/dev/null || true

  # Safety trap: ensure stray coverage or report files move to artifacts/
  mkdir -p "$PROJECT_DIR/artifacts" 2>/dev/null || true
  mv "$PROJECT_DIR"/v8_coverage_*.json "$PROJECT_DIR/artifacts/" 2>/dev/null || true
}
trap cleanup_workspace EXIT INT TERM

# 1. GDScript Lint and Format Check
echo "Running GDScript Format Check..."
gdformat --diff --check $PROJECT_DIR/scripts
check_exit "GDScript Format Check"

echo "Running GDScript Lint..."
gdlint $PROJECT_DIR/scripts
check_exit "GDScript Lint"

# 2. Markdown Lint
echo "Running Markdown Lint..."
markdownlint-cli2 "**/*.md" "!.venv/**" "!venv/**" "!staticfiles/**" "!static/**" "!export/**" "!artifacts/**" "!addons/**" --config .markdownlint-cli2.yaml --fix
check_exit "Markdown Lint"

# 3. YAML Lint
echo "Running YAML Lint..."
yamllint -c .yamllint.yaml .github/workflows/*.yml
check_exit "YAML Lint"

# Ensure addons directory exists on mounted workspace
mkdir -p "$PROJECT_DIR/addons"

# 4. Godot Unit Tests (GDUnit4 v6)
GDUNIT4_SHA256="c73f5ba0638575027a4e69b0fa8bd78ee89626487e60142bc02a2eb0ceee5d23"
echo "Ensuring GDUnit4 addons are present..."
if [ ! -d "$PROJECT_DIR/addons/gdUnit4" ]; then
  if [ -d "/opt/addons/gdUnit4" ]; then
    echo "📦 Restoring GDUnit4 from container fallback storage (/opt/addons/gdUnit4)..."
    cp -r /opt/addons/gdUnit4 "$PROJECT_DIR/addons/"
  else
    echo "📥 GDUnit4 missing locally. Downloading GDUnit4 v6.1.3..."
    wget -q https://github.com/MikeSchulze/gdUnit4/archive/refs/tags/v6.1.3.zip -O "$ADDON_TMP/gdunit4.zip"
    echo "${GDUNIT4_SHA256}  $ADDON_TMP/gdunit4.zip" | sha256sum --check --status
    check_exit "GDUnit4 Checksum Verification"
    unzip -q "$ADDON_TMP/gdunit4.zip" -d "$ADDON_TMP/gdunit_extract"
    mv "$ADDON_TMP/gdunit_extract/gdUnit4-6.1.3/addons/gdUnit4" "$PROJECT_DIR/addons/gdUnit4"
    rm -rf "$ADDON_TMP/gdunit4.zip" "$ADDON_TMP/gdunit_extract"
  fi
fi

if [ ! -d "$PROJECT_DIR/addons/gdUnit4" ]; then
  echo "❌ CRITICAL: GDUnit4 addon missing at $PROJECT_DIR/addons/gdUnit4"
  exit 1
fi

echo "Importing Resources..."
godot --headless --path $PROJECT_DIR --import --quit
check_exit "Resource Import"

echo "Running GDUnit4 Tests..."
godot --headless --path $PROJECT_DIR -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --verbose --ignoreHeadlessMode --add res://test/gdunit4
check_exit "GDUnit4 Tests"

# 5. GUT Unit Tests
GUT_SHA256="577d34a413009772a5a54f8d5069f06c64609825b29094e9f73a388f63567d2c"
echo "Checking for GUT installation..."
if [ ! -d "$PROJECT_DIR/addons/gut" ]; then
  if [ -d "/opt/addons/gut" ]; then
    echo "📦 Restoring GUT from container fallback storage (/opt/addons/gut)..."
    cp -r /opt/addons/gut "$PROJECT_DIR/addons/"
  else
    echo "📥 GUT missing locally. Downloading GUT v9.5.0..."
    wget -q https://github.com/bitwes/Gut/archive/refs/tags/v9.5.0.zip -O "$ADDON_TMP/gut.zip"
    echo "${GUT_SHA256}  $ADDON_TMP/gut.zip" | sha256sum --check --status
    check_exit "GUT Checksum Verification"
    unzip -q "$ADDON_TMP/gut.zip" -d "$ADDON_TMP/gut_extract"
    mv "$ADDON_TMP/gut_extract/Gut-9.5.0/addons/gut" "$PROJECT_DIR/addons/gut"
    rm -rf "$ADDON_TMP/gut.zip" "$ADDON_TMP/gut_extract"
  fi
fi

if [ ! -d "$PROJECT_DIR/addons/gut" ]; then
  echo "❌ CRITICAL: GUT not found at '$PROJECT_DIR/addons/gut'."
  exit 1
fi

echo "Running GUT Unit Tests..."
godot --headless --verbose --path $PROJECT_DIR \
  -s res://addons/gut/gut_cmdln.gd \
  -gconfig=res://.gutconfig.json \
  -gexit
check_exit "GUT Unit Tests"

mkdir -p $PROJECT_DIR/reports
cp -r reports/** $PROJECT_DIR/reports || true

# 6. Pre-Export Setup (Salt & CI Flag Injection)
echo "⚙️ Injecting dummy salt for Playwright tests..."
PRODUCTION_SALT="playwright_dummy_salt_123" bash .github/scripts/inject_salt.sh "scripts/core/globals.gd"
check_exit "Salt Injection"

echo "⚙️ Injecting 'ci' feature flag into export_presets.cfg..."
python3 .github/scripts/inject_ci_flag.py
check_exit "CI Flag Injection"

# 7. Browser Functional Tests
echo "🎮 Exporting Godot Project to Web..."
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
godot --headless --path "$PROJECT_DIR" --export-release "Web_thread_off" "$EXPORT_DIR/index.html"
check_exit "Godot Web Export"

# Clean modified config files back to pristine git state
echo "🧹 Restoring configuration files to pristine state..."
git restore export_presets.cfg scripts/core/globals.gd 2>/dev/null || true
rm -f export_presets.cfg.bak 2>/dev/null || true

echo "🚀 Starting security-isolated web server..."
python3 -c "
import http.server, socketserver, os

class MyHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        super().end_headers()

class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

with ThreadedHTTPServer(('', $SERVER_PORT), MyHandler) as httpd:
    os.chdir('$EXPORT_DIR')
    httpd.serve_forever()
" &
SERVER_PID=$!

echo "Waiting for server to respond..."
max_retries=100
count=0
server_ready=0

while [ $count -lt $max_retries ]; do
  if curl --fail --silent --show-error --max-time 1 \
      "http://localhost:${SERVER_PORT}/index.html" > /dev/null; then
    server_ready=1
    break
  fi
  sleep 0.2
  count=$((count + 1))
done

if [ $server_ready -eq 0 ]; then
  echo "❌ Web server failed to start within timeout"
  exit 1
fi
echo "✅ Server ready"

echo "Running Playwright Browser Tests..."
mkdir -p "$PROJECT_DIR/artifacts"
source /opt/venv/bin/activate 2>/dev/null || true

# Execute pytest with outputs directed into artifacts/
pytest tests/ --ignore=tests/refactor -v \
  --timeout=$PW_TIMEOUT \
  --html="$PROJECT_DIR/artifacts/report_all.html" \
  --self-contained-html \
  --junitxml="$PROJECT_DIR/artifacts/report.xml"
PYTEST_EXIT=$?

kill $SERVER_PID 2>/dev/null || true

# Post-test sweep: Move V8 coverage outputs to artifacts/
mv "$PROJECT_DIR"/v8_coverage_*.json "$PROJECT_DIR/artifacts/" 2>/dev/null || true

# 8. Report Summary & Failure Check
REPORT_FILE="$PROJECT_DIR/artifacts/report.xml"
if [ -f "$REPORT_FILE" ]; then
  total=$(xmllint --xpath 'count(//testcase)' "$REPORT_FILE")
  failures=$(xmllint --xpath 'count(//testcase/failure)' "$REPORT_FILE")
  errors=$(xmllint --xpath 'count(//testcase/error)' "$REPORT_FILE")
  skipped=$(xmllint --xpath 'count(//testcase/skipped)' "$REPORT_FILE")
  passed=$((total - failures - errors - skipped))

  echo "Test Report Summary:"
  echo "- Total tests: $total"
  echo "- Passed: $passed"
  echo "- Failed: $failures"
  echo "- Errors: $errors"
  echo "- Skipped: $skipped"
else
  echo "CRITICAL ERROR: report.xml not found! Playwright tests failed to generate results."
  exit 1
fi

if [ $PYTEST_EXIT -ne 0 ]; then
  echo "Error in Playwright Tests. Exiting pipeline."
  exit $PYTEST_EXIT
fi

cp -r "$PROJECT_DIR/reports" "$PROJECT_DIR/artifacts/gdunit-reports" 2>/dev/null || true

echo "Pipeline completed successfully!"
