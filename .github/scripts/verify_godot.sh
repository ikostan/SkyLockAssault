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
CHECKSUM_URL="https://downloads.tuxfamily.org/godotengine/${TUX_VERSION}/SHA256SUMS.txt"

echo "🌐 Testing URL connectivity..."
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

# Fallback block if the maintainers drop an alternate hash algorithm target folder layout
USE_SHA512=false
if ! curl -sI -fL "$CHECKSUM_URL" > /dev/null; then
    echo "⚠️ SHA256SUMS.txt missing at primary URL. Checking for SHA512-SUMS.txt fallback..."
    CHECKSUM_URL="https://downloads.tuxfamily.org/godotengine/${TUX_VERSION}/SHA512-SUMS.txt"
    if ! curl -sI -fL "$CHECKSUM_URL" > /dev/null; then
        echo "❌ FATAL: No valid verification manifests found on the mirror infra."
        exit 1
    fi
    USE_SHA512=true
fi

echo "📥 Fetching distribution binaries..."
curl -fL --show-error -o "$EXE_FILE" "$EXE_URL"
curl -fL --show-error -o "$TEMPLATE_FILE" "$TEMPLATE_URL"

# Define a single target map for structural extraction
TARGET_MANIFEST="GODOT_TARGET_SUMS.txt"

if [ "$USE_SHA512" = true ]; then
    curl -fL --show-error -o SHA512-SUMS.txt "$CHECKSUM_URL"
    echo "🔒 Isolating cryptographic signature entries (SHA-512)..."

    grep -F "${EXE_FILE}" SHA512-SUMS.txt > "$TARGET_MANIFEST"
    grep -F "${TEMPLATE_FILE}" SHA512-SUMS.txt >> "$TARGET_MANIFEST"

    # Assert that both files were explicitly matched in the official manifest
    if [ "$(wc -l < "$TARGET_MANIFEST")" -ne 2 ]; then
        echo "❌ FATAL: Manifest is missing explicit checksum signatures for target assets."
        exit 1
    fi

    sha512sum --check "$TARGET_MANIFEST"
else
    curl -fL --show-error -o SHA256SUMS.txt "$CHECKSUM_URL"
    echo "🔒 Isolating cryptographic signature entries (SHA-256)..."

    grep -F "${EXE_FILE}" SHA256SUMS.txt > "$TARGET_MANIFEST"
    grep -F "${TEMPLATE_FILE}" SHA256SUMS.txt >> "$TARGET_MANIFEST"

    # Assert that both files were explicitly matched in the official manifest
    if [ "$(wc -l < "$TARGET_MANIFEST")" -ne 2 ]; then
        echo "❌ FATAL: Manifest is missing explicit checksum signatures for target assets."
        exit 1
    fi

    sha256sum --check "$TARGET_MANIFEST"
fi

echo "✅ SUCCESS: All targeted Godot engine components are structurally authentic and valid."
