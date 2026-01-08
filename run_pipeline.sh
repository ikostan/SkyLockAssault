#!/bin/bash

# Set variables
PROJECT_DIR="/project"
EXPORT_DIR="$PROJECT_DIR/export/web_thread_off"
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
