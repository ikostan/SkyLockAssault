#!/bin/bash
# test_injection.sh

# Prerequisites:
# 1. Ensure 'godot' is in your system PATH (or update the GODOT_CMD variable below).
# 2. Ensure 'python3' is installed to run the local web server.

GODOT_CMD="godot"

# 1. Hardcoded Secret (Mimicking GitHub Secrets)
RAW_SECRET='T3st_S@lt!_2026#"\'
export PRODUCTION_SALT="$RAW_SECRET"

echo "=========================================="
echo " Starting Local CI/CD Simulation"
echo " Simulated Secret: $PRODUCTION_SALT"
echo "=========================================="

# Ensure project.godot exists
if [ ! -f "project.godot" ]; then
    echo "❌ ERROR: project.godot not found in the current directory!"
    exit 1
fi

# Create a backup so we don't permanently mangle your local file
cp project.godot project.godot.backup
echo "ℹ️ Backed up project.godot to project.godot.backup"

# 2. Mimic the GitHub Action Injection Step
ESCAPED_SALT=$(printf '%s' "$PRODUCTION_SALT" | sed 's/\\/\\\\/g; s/"/\\"/g')

echo "⚙️ Running sed injection script..."

GODOT_ESCAPED=$(printf '%s' "$PRODUCTION_SALT" | sed 's/\\/\\\\/g; s/"/\\"/g')
SED_ESCAPED=$(printf '%s' "$GODOT_ESCAPED" | sed 's/\\/\\\\/g; s/&/\\&/g; s/|/\\|/g')

sed -i "s|^[[:space:]]*security/save_salt=.*|security/save_salt=\"$SED_ESCAPED\"|g" project.godot


# 3. Verifying Injection (Enhanced)
echo ""
echo "=========================================="
echo " Verifying Injection Results"
echo "=========================================="

if grep -q "\[game\]" project.godot; then
  echo "✅ [game] section found."

  # Extract the value placed between the quotes
  SALT_VAL=$(sed -n '/^\[game\]/,/^\[/p' project.godot | grep "security/save_salt=" | sed 's/.*security\/save_salt="//; s/"$//')
  if [ -n "$SALT_VAL" ]; then
    echo "✅ security/save_salt is present and not empty."

    # Calculate metrics
    SALT_LENGTH=${#SALT_VAL}
    DIGITS_COUNT=$(echo -n "$SALT_VAL" | tr -cd '0-9' | wc -c)
    SPECIAL_CHARS_COUNT=$(echo -n "$SALT_VAL" | tr -cd '[:punct:]' | wc -c)

    echo "📊 Salt Validation Metrics:"
    echo "   - Injected Salt:      $SALT_VAL"
    echo "   - Total Length:       $SALT_LENGTH characters"
    echo "   - Number of Digits:   $DIGITS_COUNT"
    echo "   - Special Characters: $SPECIAL_CHARS_COUNT"

    # Match verification
    if [ "$SALT_VAL" = "$ESCAPED_SALT" ]; then
       echo "🔒 Verification Passed: Injected string perfectly matches the escaped secret."
    else
       echo "❌ Verification Failed: The extracted string does not match what was injected!"
       echo "   Expected: $ESCAPED_SALT"
       echo "   Found:    $SALT_VAL"
    fi
  else
    echo "❌ security/save_salt is MISSING or EMPTY inside [game] section."
    echo "   (This confirms the awk script failed to overwrite the blank setting.)"
  fi
else
  echo "❌ [game] section was NEVER CREATED."
fi


# 4. Mimic Export & Deployment Steps
echo ""
echo "=========================================="
echo " Executing Build & Export Pipeline"
echo "=========================================="

echo "📁 Creating Export Directories..."
mkdir -p export/web

# 4. Mimic Export & Deployment Steps
echo ""
echo "=========================================="
echo " Executing Build & Export Pipeline"
echo "=========================================="

echo "🗑️ Cleaning old ghost files..."
rm -rf export/web/*
mkdir -p export/web

echo "🎮 Exporting Godot project (Web preset)..."
$GODOT_CMD --verbose --headless --export-release "Web" export/web/index.html

if [ ! -f "export/web/index.pck" ]; then
    echo "❌ Export failed. index.pck not found."
    exit 1
fi

echo "🛡️ Patching index.js for security..."
if [ -f "./.github/scripts/patch_index_js.sh" ]; then
    bash ./.github/scripts/patch_index_js.sh "export/web"
else
    echo "⚠️ Warning: .github/scripts/patch_index_js.sh not found locally. Skipping."
fi

echo "✅ Build pipeline completed successfully."

# 5. Start Local Server
echo ""
echo "=========================================="
echo " Starting Local Game Server"
echo "=========================================="
echo "🌐 Note: Generating a Python server to provide COOP/COEP headers required by Godot Threads."

cat << 'EOF' > export/web/serve.py
import http.server
import socketserver

PORT = 8080

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Add headers required for SharedArrayBuffer (Thread support)
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"🚀 Game server running! Open http://localhost:{PORT} in your browser.")
    print("Press Ctrl+C to stop the server.")
    httpd.serve_forever()
EOF

cd export/web
python3 serve.py

# (Optional: If you cancel the server with Ctrl+C, the script ends here.
# You can restore your project.godot manually using the backup created earlier).