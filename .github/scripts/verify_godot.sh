#!/usr/bin/env bash
set -euo pipefail

# Accept a version argument, default to 4.6.3-stable if none provided
GODOT_VERSION="${1:-4.6.3-stable}"
echo "🔍 Initiating target asset verification for Godot ${GODOT_VERSION}..."

# Setup a clean, local workspace folder for binaries
STAGING_DIR="godot_binaries"
mkdir -p "$STAGING_DIR"
cd "$STAGING_DIR"

# Define asset targets mapping to GitHub Release assets
EXE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
TEMPLATE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"

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
curl -fL --show-error -o "Godot_v${GODOT_VERSION}_linux.x86_64.zip" "$EXE_URL"
curl -fL --show-error -o "Godot_v${GODOT_VERSION}_export_templates.tpz" "$TEMPLATE_URL"

if [ "$USE_SHA512" = true ]; then
    curl -fL --show-error -o SHA512-SUMS.txt "$CHECKSUM_URL"
    echo "🔒 Executing cryptographic signature test (SHA-512)..."
    sha512sum --check --ignore-missing SHA512-SUMS.txt
else
    curl -fL --show-error -o SHA256SUMS.txt "$CHECKSUM_URL"
    echo "🔒 Executing cryptographic signature test (SHA-256)..."
    sha256sum --check --ignore-missing SHA256SUMS.txt
fi

echo "✅ SUCCESS: All targeted Godot engine components are structurally authentic and valid."
