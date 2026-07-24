#!/bin/bash
# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later

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

# Ensure Git trusts the container directory to avoid dubious ownership errors
git config --global --add safe.directory "$PROJECT_DIR" 2>/dev/null || true

# 1. Inject a dummy salt (Pipeline consistency)
echo "⚙️ Injecting dummy salt for Playwright tests..."
PRODUCTION_SALT="playwright_dummy_salt_123" bash .github/scripts/inject_salt.sh "scripts/core/globals.gd"
check_exit "Salt Injection"

# 2. FORCE the "ci" feature flag into export_presets.cfg
echo "⚙️ Injecting 'ci' feature flag into export_presets.cfg..."
python3 .github/scripts/inject_ci_flag.py
check_exit "CI Flag Injection"

# 3. Export the Web build for functional testing
echo "🎮 Exporting Godot Project to Web (Web_thread_off)..."
mkdir -p "$EXPORT_DIR"
godot --headless --path "$PROJECT_DIR" --export-release "Web_thread_off" "$EXPORT_DIR/index.html"
check_exit "Godot Export"

# 4. Clean up the repository
echo "🧹 Restoring files to pristine state..."
git restore export_presets.cfg scripts/core/globals.gd
check_exit "Repository Restore"

# 5. Start a security-isolated web server with reliable cleanup trap
echo "🚀 Starting security-isolated server on port $SERVER_PORT..."
python3 -c "
import http.server, socketserver, os
class MyHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        super().end_headers()
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('', $SERVER_PORT), MyHandler) as httpd:
    os.chdir('$EXPORT_DIR')
    httpd.serve_forever()
" &
SERVER_PID=$!

# Trap process termination signals to ensure background server cleanup
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT INT TERM

echo "Waiting for server to respond..."
max_retries=100
count=0
server_ready=0

while [ $count -lt $max_retries ]; do
  if curl -s http://localhost:$SERVER_PORT/index.html > /dev/null; then
    server_ready=1
    break
  fi
  sleep 0.2
  count=$((count + 1))
done

if [ $server_ready -eq 0 ]; then
  echo "❌ Server failed to start within timeout"
  exit 1
fi
echo "✅ Server ready"

# 6. Run Playwright tests
echo "🧪 Running Playwright Browser Tests..."
mkdir -p "$PROJECT_DIR/artifacts"
source /opt/venv/bin/activate
xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" pytest tests/ \
  -v \
  --timeout=$PW_TIMEOUT \
  --ignore=tests/refactor \
  --ignore=tests/ci \
  --capture=no \
  --html="$PROJECT_DIR/report.html" \
  --self-contained-html \
  --junitxml="$PROJECT_DIR/report.xml"
check_exit "Playwright Tests"

# 7. Generate test report summary
if [ -f "$PROJECT_DIR/report.xml" ]; then
  total=$(xmllint --xpath 'count(//testcase)' "$PROJECT_DIR/report.xml")
  failures=$(xmllint --xpath 'count(//testcase/failure)' "$PROJECT_DIR/report.xml")
  errors=$(xmllint --xpath 'count(//testcase/error)' "$PROJECT_DIR/report.xml")
  skipped=$(xmllint --xpath 'count(//testcase/skipped)' "$PROJECT_DIR/report.xml")
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
