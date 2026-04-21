#!/bin/bash
# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later

# Set variables
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

# 1. GDScript Lint and Format Check
echo "Running GDScript Format Check..."
gdformat --diff --check $PROJECT_DIR/scripts
check_exit "GDScript Format Check"

echo "Running GDScript Lint..."
gdlint $PROJECT_DIR/scripts
check_exit "GDScript Lint"

# 2. Markdown Lint
echo "Running Markdown Lint..."
# Now using the version pre-installed in the Docker image
markdownlint-cli2 "**/*.md" "!venv/**" --config .markdownlint-cli2.yaml --fix
check_exit "Markdown Lint"

# 3. YAML Lint
echo "Running YAML Lint..."
yamllint -c .yamllint.yaml .github/workflows/*.yml
check_exit "YAML Lint"

# 4. Godot Unit Tests (GDUnit4 v6)
echo "Ensuring GDUnit4 addons are present..."
cp -r /project/addons/gdUnit4 $PROJECT_DIR/addons/ || true

echo "Importing Resources..."
godot --headless --path $PROJECT_DIR --import --quit
check_exit "Resource Import"

echo "Running GDUnit4 Tests..."
godot --headless --path $PROJECT_DIR -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --verbose --ignoreHeadlessMode --add res://test/gdunit4
check_exit "GDUnit4 Tests"

# 5. GUT Unit Tests
echo "Ensuring GUT is installed in addons/..."
if [ ! -d "$PROJECT_DIR/addons/gut" ]; then
  mkdir -p "$PROJECT_DIR/addons"
  wget https://github.com/bitwes/Gut/archive/refs/tags/v9.5.0.zip
  unzip v9.5.0.zip -d "$PROJECT_DIR/addons"
  mv "$PROJECT_DIR/addons/Gut-9.5.0/addons/gut" "$PROJECT_DIR/addons/gut"
  rm -rf "$PROJECT_DIR/addons/Gut-9.5.0" v9.5.0.zip
fi

echo "Running GUT Unit Tests..."
# Let .gutconfig.json govern discovery; removed -gdir overrides
godot --headless --verbose --path $PROJECT_DIR \
  -s res://addons/gut/gut_cmdln.gd \
  -gconfig=res://.gutconfig.json \
  -gexit
check_exit "GUT Unit Tests"

mkdir -p $PROJECT_DIR/reports
cp -r reports/** $PROJECT_DIR/reports || true

# 6. Browser Functional Tests
echo "Exporting Godot Project to Web..."
mkdir -p $EXPORT_DIR
godot --headless --path $PROJECT_DIR --export-release "Web_thread_off" $EXPORT_DIR/index.html
check_exit "Godot Web Export"

python3 -m http.server $SERVER_PORT --directory $EXPORT_DIR &
SERVER_PID=$!

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

echo "Running Playwright Browser Tests..."
pytest tests/ --ignore=tests/refactor -v --junitxml=$PROJECT_DIR/report.xml
check_exit "Playwright Tests"

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