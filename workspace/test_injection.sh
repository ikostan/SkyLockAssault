#!/bin/bash
# test_injection.sh

BACKUP_FILE="project.godot.backup"

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

echo "⚙️ Injecting secret using safe ENVIRON AWK script..."
# 1. Escape for Godot's parser and EXPORT to environment
GODOT_ESCAPED=$(printf '%s' "$PRODUCTION_SALT" | sed 's/\\/\\\\/g; s/"/\\"/g')
export GODOT_ESCAPED

# 2. Use ENVIRON to prevent awk from stripping our escapes
awk '
  BEGIN { salt = ENVIRON["GODOT_ESCAPED"]; in_game = 0; salt_written = 0; saw_game_section = 0 }
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
' project.godot > project.godot.tmp && mv project.godot.tmp project.godot || {
    echo "❌ ERROR: Failed to inject security/save_salt into project.godot."
    exit 1
}

echo "🎮 Exporting Godot project (Web preset)..."
echo "⏳ Rebuilding cache from scratch. This may take 10+ minutes over Docker."

$GODOT_CMD --verbose --headless --export-release "Web" export/web/index.html > export_log.txt 2>&1 &
GODOT_PID=$!

SECONDS=0
SPINNER="-\|/"
i=0
while kill -0 $GODOT_PID 2>/dev/null; do
  i=$(( (i+1) % 4 ))
  printf "\r⚙️ Godot is working... %s (Elapsed Time: %d seconds)" "${SPINNER:$i:1}" "$SECONDS"
  sleep 1
done

printf "\r✅ Export process finished! (Total time: %d seconds)                  \n" "$SECONDS"

wait $GODOT_PID
if [ $? -ne 0 ]; then
    echo "❌ FATAL: Godot engine crashed during export."
    echo "📄 Printing the last 20 lines of the crash log:"
    tail -n 20 export_log.txt
    exit 1
fi

if [ ! -f "export/web/index.pck" ]; then
    echo "❌ Export failed. index.pck not found."
    exit 1
fi

if [ -f "./.github/scripts/patch_index_js.sh" ]; then
    bash ./.github/scripts/patch_index_js.sh "export/web" || {
        echo "❌ ERROR: patch_index_js.sh failed."
        exit 1
    }
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
