#!/bin/bash
# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later

PROJECT_DIR="/project"
EXPORT_DIR="$PROJECT_DIR/export/web_thread_off"
SERVER_PORT=8080
PW_TIMEOUT=10000

# Function to check if a step failed
check_exit() {
  if [ $? -ne 0 ]; then
    echo "Error in $1. Exiting pipeline."
    exit 1
  fi
}

# Browser Functional Tests
echo "Exporting Godot Project to Web..."
mkdir -p $EXPORT_DIR

# Simulate firebelley/godot-export action: Run Godot export to HTML5
godot --headless --path $PROJECT_DIR --export-release "Web_thread_off" $EXPORT_DIR/index.html
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
mkdir -p $PROJECT_DIR/artifacts  # No chown
source /opt/venv/bin/activate
xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" pytest tests/ -v --timeout=$PW_TIMEOUT --ignore=tests/refactor --capture=no --html=$PROJECT_DIR/report.html --self-contained-html --junitxml=$PROJECT_DIR/report.xml
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
