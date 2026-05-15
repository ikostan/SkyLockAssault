#!/bin/bash
# test_injection.sh

cleanup() {
    if [ -f "globals.gd.backup" ]; then
        echo "🧹 Cleaning up: Restoring globals.gd from backup..."
        mv -f "globals.gd.backup" scripts/core/globals.gd
    fi
    if [ -f "project.godot.backup" ]; then
        echo "🧹 Cleaning up: Restoring project.godot from backup..."
        mv -f "project.godot.backup" project.godot
    fi
    if [ -f "export_presets.cfg.backup" ]; then
        echo "🧹 Cleaning up: Restoring export_presets.cfg from backup..."
        mv -f "export_presets.cfg.backup" export_presets.cfg
    fi
    # Clean up the internal artifact created by the Python injection script
    rm -f export_presets.cfg.bak
}
trap cleanup EXIT INT TERM

GODOT_CMD="godot"
RAW_SECRET='T3st_S@lt!_2026#"\'
export PRODUCTION_SALT="$RAW_SECRET"

# Cross-platform sed for in-place editing (macOS vs Linux)
sedi() {
  if [ "$(uname)" = "Darwin" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

echo "=========================================="
echo " Starting Local CI/CD Simulation"
echo "=========================================="

if [ ! -f "scripts/core/globals.gd" ] || [ ! -f "project.godot" ] || [ ! -f "export_presets.cfg" ]; then
    echo "❌ ERROR: Required project files not found!"
    exit 1
fi

cp scripts/core/globals.gd globals.gd.backup
cp project.godot project.godot.backup
cp export_presets.cfg export_presets.cfg.backup

echo "🗑️ Wiping previous web export files..."
rm -rf export/web/*
mkdir -p export/web

echo "🔌 Disabling editor plugins (GUT) to prevent headless crashes..."
sedi '/^\[editor_plugins\]/,/^\[/ s/^enabled=PackedStringArray.*/enabled=PackedStringArray()/' project.godot
# sed -i '/^\[editor_plugins\]/,/^\[/ s/^enabled=PackedStringArray.*/enabled=PackedStringArray()/' project.godot

# Call the Single Source of Truth script
bash ./.github/scripts/inject_salt.sh "scripts/core/globals.gd" || {
    echo "❌ ERROR: Master injection script failed."
    exit 1
}

echo "⚙️ Injecting 'ci' feature flag into export_presets.cfg..."
python3 .github/scripts/inject_ci_flag.py || {
    echo "❌ ERROR: CI flag injection script failed."
    exit 1
}

echo "🎮 Exporting Godot project (Web preset)..."

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
