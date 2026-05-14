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
    echo "Error in $1. Exiting pipeline."
    exit 1
  fi
}

# 1. Inject a dummy salt (Pipeline consistency)
echo "⚙️ Injecting dummy salt for Playwright tests..."
PRODUCTION_SALT="playwright_dummy_salt_123" bash .github/scripts/inject_salt.sh "scripts/core/globals.gd"
check_exit "Salt Injection"

# 2. FORCE the "ci" feature flag into export_presets.cfg
# Godot 4 ignores CLI feature flags, so we must inject it into the preset directly
echo "⚙️ Injecting 'ci' feature flag into export_presets.cfg..."
cp export_presets.cfg export_presets.cfg.bak
python3 -c "
import re
with open('export_presets.cfg', 'r') as f:
    data = f.read()
# Inject into existing custom_features or add it if missing
data = re.sub(r'custom_features=\"[^\"]*\"', 'custom_features=\"ci\"', data)
if 'custom_features=\"ci\"' not in data:
    data = re.sub(r'(\[preset\.\d+\.options\])', r'\1\ncustom_features=\"ci\"', data)
with open('export_presets.cfg', 'w') as f:
    f.write(data)
"

# 3. Export the Web build for functional testing
echo "🎮 Exporting Godot Project to Web (Web_thread_off)..."
mkdir -p "$EXPORT_DIR"
godot --headless --path "$PROJECT_DIR" --export-release "Web_thread_off" "$EXPORT_DIR/index.html"
check_exit "Godot Export"

# 4. Clean up the repository
# We strictly revert globals.gd and export_presets.cfg to keep your repo pristine
echo "🧹 Restoring files to pristine state..."
git restore export_presets.cfg
git restore scripts/core/globals.gd

# 5. Start a security-isolated web server
# Provides the COOP and COEP headers absolutely required by Godot 4 Web exports
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

echo "Waiting for server to respond..."
max_retries=20
count=0
while ! curl -s http://localhost:$SERVER_PORT/index.html > /dev/null; do
  sleep 1
  count=$((count + 1))
  if [ $count -eq $max_retries ]; then
    echo "❌ Server failed to start"
    kill $SERVER_PID
    exit 1
  fi
done
echo "✅ Server ready"

# 6. Run Playwright tests
echo "🧪 Running Playwright Browser Tests..."
mkdir -p "$PROJECT_DIR/artifacts"
source /opt/venv/bin/activate
xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" pytest tests/ -v --timeout=$PW_TIMEOUT --ignore=tests/refactor --capture=no --html="$PROJECT_DIR/report.html" --self-contained-html --junitxml="$PROJECT_DIR/report.xml"
check_exit "Playwright Tests"

# Generate test report summary
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

# Cleanup
kill $SERVER_PID
