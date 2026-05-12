#!/bin/bash
# test_injection.sh

BACKUP_FILE="project.godot.backup"

# Trap function to ensure the file is ALWAYS restored on exit or Ctrl+C
cleanup() {
    if [ -f "$BACKUP_FILE" ]; then
        echo "🧹 Cleaning up: Restoring project.godot from backup..."
        mv -f "$BACKUP_FILE" project.godot
    fi
}
trap cleanup EXIT INT TERM

GODOT_CMD="godot"
RAW_SECRET='T3st_S@lt!_2026#"\'
export PRODUCTION_SALT="$RAW_SECRET"

echo "=========================================="
echo " Starting Local CI/CD Simulation"
echo "=========================================="

if [ ! -f "project.godot" ]; then
    echo "❌ ERROR: project.godot not found in the current directory!"
    exit 1
fi

cp project.godot "$BACKUP_FILE"

echo "🗑️ Wiping Windows .godot cache to force a clean Linux build..."
rm -rf .godot/
rm -rf export/web/*
mkdir -p export/web

echo "⚙️ Injecting secret using production AWK script..."
ESCAPED_SALT=$(printf '%s' "$PRODUCTION_SALT" | sed 's/\\/\\\\/g; s/"/\\"/g')
awk -v salt="$ESCAPED_SALT" '
  BEGIN { in_game = 0; salt_written = 0; saw_game_section = 0 }
  {
    if ($0 ~ /^\[game\]/) { in_game = 1; saw_game_section = 1; print; next }
    else if ($0 ~ /^\[/ && $0 !~ /^\[game\]/) {
      if (in_game && !salt_written) { print "security/save_salt=\"" salt "\""; salt_written = 1 }
      in_game = 0; print; next
    }
    if (in_game && $0 ~ /^[[:space:]]*security\/save_salt[[:space:]]*=/) {
      if (!salt_written) { print "security/save_salt=\"" salt "\""; salt_written = 1 }
      next
    }
    print
  }
  END {
    if (in_game && !salt_written) { print "security/save_salt=\"" salt "\""; salt_written = 1 }
    if (!saw_game_section) { if (NR > 0) { print "" }; print "[game]"; print "security/save_salt=\"" salt "\"" }
  }
' project.godot > project.godot.tmp && mv project.godot.tmp project.godot

echo "🎮 Exporting Godot project (Web preset)..."
$GODOT_CMD --verbose --headless --export-release "Web" export/web/index.html

if [ ! -f "export/web/index.pck" ]; then
    echo "❌ Export failed. index.pck not found."
    exit 1
fi

if [ -f "./.github/scripts/patch_index_js.sh" ]; then
    bash ./.github/scripts/patch_index_js.sh "export/web"
fi

echo "✅ Build pipeline completed successfully."

echo "=========================================="
echo " Starting Local Game Server"
echo "=========================================="
cat << 'EOF' > export/web/serve.py
import http.server
PORT = 8080
class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()
if __name__ == '__main__':
    with http.server.ThreadingHTTPServer(("", PORT), Handler) as httpd:
        print(f"🚀 Game server running! Open http://localhost:{PORT} in your browser.")
        httpd.serve_forever()
EOF

cd export/web || {
    echo "❌ ERROR: Failed to change to export/web directory!"
    exit 1
}
python3 serve.py
