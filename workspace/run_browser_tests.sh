#!/bin/bash
# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later

PROJECT_DIR="/project"
EXPORT_DIR="$PROJECT_DIR/export/web_thread_off"
SERVER_PORT=8080
PW_TIMEOUT=30000

# 1. Parse positional CLI arguments with defaults
TEST_TARGET="${1:-tests/}"
SUITE_NAME="${2:-all}"

# Function to check if a step failed
check_exit() {
  if [ $? -ne 0 ]; then
    echo "❌ Error in $1. Exiting pipeline."
    exit 1
  fi
}

# Ensure Git trusts the container directory to avoid dubious ownership errors
git config --global --add safe.directory "$PROJECT_DIR" 2>/dev/null || true

# 2. Inject dummy salt for test runtime consistency
echo "⚙️ Injecting dummy salt for Playwright tests..."
PRODUCTION_SALT="playwright_dummy_salt_123" bash .github/scripts/inject_salt.sh "scripts/core/globals.gd"
check_exit "Salt Injection"

# 3. FORCE the "ci" feature flag into export_presets.cfg
echo "⚙️ Injecting 'ci' feature flag into export_presets.cfg..."
python3 .github/scripts/inject_ci_flag.py
check_exit "CI Flag Injection"

# 4. Check for existing export artifacts to skip redundant Godot builds
if [ ! -f "$EXPORT_DIR/index.html" ]; then
  echo "🎮 Exporting Godot Project to Web (Web_thread_off)..."
  mkdir -p "$EXPORT_DIR"
  godot --headless --path "$PROJECT_DIR" --export-release "Web_thread_off" "$EXPORT_DIR/index.html"
  check_exit "Godot Export"
else
  echo "⚡ Reusing existing web export artifacts in $EXPORT_DIR"
fi

# 5. Clean up the repository and purge temporary backups
echo "🧹 Restoring files to pristine state..."
git restore export_presets.cfg scripts/core/globals.gd 2>/dev/null || true
rm -f export_presets.cfg.bak v8_coverage_*.json 2>/dev/null || true

cleanup_server() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f export_presets.cfg.bak 2>/dev/null || true
}

trap cleanup_server EXIT INT TERM

echo "🚀 Starting security-isolated server on port $SERVER_PORT..."
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
  echo "❌ Server failed to start within timeout"
  exit 1
fi
echo "✅ Server ready"

# 6. Run Playwright browser tests using native headless mode (no xvfb-run dependency)
echo "🧪 Running Playwright Browser Tests target: $TEST_TARGET ($SUITE_NAME)..."
mkdir -p "$PROJECT_DIR/artifacts"
source /opt/venv/bin/activate

# Execute pytest directly without virtual framebuffer display server overhead
pytest "$TEST_TARGET" \
  -v \
  --timeout=$PW_TIMEOUT \
  --capture=no \
  --html="$PROJECT_DIR/artifacts/report_${SUITE_NAME}.html" \
  --self-contained-html \
  --junitxml="$PROJECT_DIR/artifacts/report_${SUITE_NAME}.xml"
check_exit "Playwright Tests"

# 7. Generate suite-scoped test report summary
REPORT_FILE="$PROJECT_DIR/artifacts/report_${SUITE_NAME}.xml"
if [ -f "$REPORT_FILE" ]; then
  total=$(xmllint --xpath 'count(//testcase)' "$REPORT_FILE")
  failures=$(xmllint --xpath 'count(//testcase/failure)' "$REPORT_FILE")
  errors=$(xmllint --xpath 'count(//testcase/error)' "$REPORT_FILE")
  skipped=$(xmllint --xpath 'count(//testcase/skipped)' "$REPORT_FILE")
  passed=$((total - failures - errors - skipped))
  echo "Test Report Summary ($SUITE_NAME):"
  echo "- Total tests: $total"
  echo "- Passed: $passed"
  echo "- Failed: $failures"
  echo "- Errors: $errors"
  echo "- Skipped: $skipped"
else
  echo "No report XML found ($REPORT_FILE)—tests may not have run."
fi
