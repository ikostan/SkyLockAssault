#!/usr/bin/env bash
set -euo pipefail

# Accept a version argument, default to 4.6.3-stable if none provided
GODOT_VERSION="${1:-4.6.3-stable}"
echo "🔍 Initiating target asset verification for Godot ${GODOT_VERSION}..."

# Setup a clean, local workspace folder for binaries
STAGING_DIR="godot_binaries"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cd "$STAGING_DIR"

# Define asset targets mapping to GitHub Release assets
EXE_FILE="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
TEMPLATE_FILE="Godot_v${GODOT_VERSION}_export_templates.tpz"

EXE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${EXE_FILE}"
TEMPLATE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${TEMPLATE_FILE}"

# Parse standard version component for the TuxFamily path (e.g., extracts 4.6.3)
TUX_VERSION=$(echo "${GODOT_VERSION}" | sed 's/-stable//')

echo "🌐 Testing target binary availability..."
if ! curl -sI -fL "$EXE_URL" > /dev/null; then
    echo "❌ FATAL: Godot Executable URL is invalid or throwing a 404 error:"
    echo "   $EXE_URL"
    exit 1
fi

if ! curl -sI -fL "$TEMPLATE_URL" > /dev/null; then
    echo "❌ FATAL: Godot Export Templates URL is invalid or throwing a 404 error:"
    echo "   $TEMPLATE_URL"
    exit 1
fi

echo "📥 Fetching distribution binaries from GitHub..."
curl -fL --show-error -o "$EXE_FILE" "$EXE_URL"
curl -fL --show-error -o "$TEMPLATE_FILE" "$TEMPLATE_URL"

echo "📥 Locating official cryptographic verification manifest..."
TARGET_MANIFEST="GODOT_TARGET_SUMS.txt"
MANIFEST_DOWNLOADED=false
USE_SHA512=false

# Sequence through official download mirrors using standard GET requests to bypass server restrictions
if curl -fL --silent --show-error -o SHA256SUMS.txt "https://downloads.tuxfamily.org/godotengine/${TUX_VERSION}/SHA256SUMS.txt" 2>/dev/null; then
    echo "🔒 Isolating cryptographic signature entries (SHA-256) from TuxFamily..."
    grep -F "${EXE_FILE}" SHA256SUMS.txt > "$TARGET_MANIFEST"
    grep -F "${TEMPLATE_FILE}" SHA256SUMS.txt >> "$TARGET_MANIFEST"
    MANIFEST_DOWNLOADED=true
elif curl -fL --silent --show-error -o SHA512-SUMS.txt "https://downloads.tuxfamily.org/godotengine/${TUX_VERSION}/SHA512-SUMS.txt" 2>/dev/null; then
    echo "🔒 Isolating cryptographic signature entries (SHA-512) from TuxFamily..."
    grep -F "${EXE_FILE}" SHA512-SUMS.txt > "$TARGET_MANIFEST"
    grep -F "${TEMPLATE_FILE}" SHA512-SUMS.txt >> "$TARGET_MANIFEST"
    USE_SHA512=true
    MANIFEST_DOWNLOADED=true
elif curl -fL --silent --show-error -o SHA512-SUMS.txt "https://sourceforge.net/projects/godot-engine.mirror/files/${GODOT_VERSION}/SHA512-SUMS.txt/download" 2>/dev/null; then
    echo "🔒 Isolating cryptographic signature entries (SHA-512) from SourceForge mirror..."
    grep -F "${EXE_FILE}" SHA512-SUMS.txt > "$TARGET_MANIFEST"
    grep -F "${TEMPLATE_FILE}" SHA512-SUMS.txt >> "$TARGET_MANIFEST"
    USE_SHA512=true
    MANIFEST_DOWNLOADED=true
fi

if [ "$MANIFEST_DOWNLOADED" = false ]; then
    echo "❌ FATAL: Could not retrieve a valid SHA256SUMS.txt or SHA512-SUMS.txt manifest from official mirrors."
    exit 1
fi

# CodeRabbit Validation: Assert that both files were explicitly matched in the isolated manifest
if [ "$(wc -l < "$TARGET_MANIFEST")" -ne 2 ]; then
    echo "❌ FATAL: Downloaded manifest is incomplete or missing checksum signatures for target assets."
    exit 1
fi

# Execute the strict cryptographic test
if [ "$USE_SHA512" = true ]; then
    sha512sum --check "$TARGET_MANIFEST"
else
    sha256sum --check "$TARGET_MANIFEST"
fi

echo "✅ SUCCESS: All targeted Godot engine components are structurally authentic and valid."
