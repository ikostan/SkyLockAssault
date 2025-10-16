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
