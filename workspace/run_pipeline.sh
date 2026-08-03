#!/bin/bash
# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later

# Set variables
PROJECT_DIR="/project"
EXPORT_DIR="$PROJECT_DIR/export/web_thread_off"
SERVER_PORT=8080
PW_TIMEOUT=10 # Value is in SECONDS for pytest-timeout compatibility

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
    wget -q https://github.com/MikeSchulze/gdUnit4/archive/refs/tags/v6.1.3.zip -O /tmp/gdunit4.zip
    echo "${GDUNIT4_SHA256}  /tmp/gdunit4.zip" | sha256sum --check --status
    check_exit "GDUnit4 Checksum Verification"
    unzip -q /tmp/gdunit4.zip -d /tmp/gdunit_extract
    mv /tmp/gdunit_extract/gdUnit4-6.1.3/addons/gdUnit4 "$PROJECT_DIR/addons/gdUnit4"
    rm -rf /tmp/gdunit4.zip /tmp/gdunit_extract
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
    wget -q https://github.com/bitwes/Gut/archive/refs/tags/v9.5.0.zip -O /tmp/gut.zip
    echo "${GUT_SHA256}  /tmp/gut.zip" | sha256sum --check --status
    check_exit "GUT Checksum Verification"
    unzip -q /tmp/gut.zip -d /tmp/gut_extract
    mv /tmp/gut_extract/Gut-9.5.0/addons/gut "$PROJECT_DIR/addons/gut"
    rm -rf /tmp/gut.zip /tmp/gut_extract
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

# 6. Browser Functional Tests
echo "Exporting Godot Project to Web..."
mkdir -p "$EXPORT_DIR"
godot --headless --path "$PROJECT_DIR" --export-release "Web_thread_off" "$EXPORT_DIR/index.html"
check_exit "Godot Web Export"

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

server_ready=false
for i in {1..20}; do
  if curl -f "http://localhost:$SERVER_PORT/index.html" >/dev/null 2>&1; then
    echo "Web server ready"
    server_ready=true
    break
  fi
  sleep 1
done

if [ "$server_ready" != true ]; then
  echo "Web server failed to start"
  kill $SERVER_PID 2>/dev/null || true
  exit 1
fi

echo "Running Playwright Browser Tests..."
pytest tests/ --ignore=tests/refactor -v --timeout=30 --junitxml="$PROJECT_DIR/report.xml"
PYTEST_EXIT=$?

kill $SERVER_PID 2>/dev/null || true
if [ $PYTEST_EXIT -ne 0 ]; then
  echo "Error in Playwright Tests. Exiting pipeline."
  exit $PYTEST_EXIT
fi

# 7. Report Summary & Failure Check
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
  echo "CRITICAL ERROR: report.xml not found! Playwright tests failed to generate results."
  kill $SERVER_PID
  exit 1
fi

kill $SERVER_PID

mkdir -p $PROJECT_DIR/artifacts
cp $PROJECT_DIR/report.xml $PROJECT_DIR/artifacts/ || true
cp main_menu.png $PROJECT_DIR/artifacts/ || true
cp -r $PROJECT_DIR/reports $PROJECT_DIR/artifacts/gdunit-reports || true

echo "Pipeline completed successfully!"
