#!/bin/bash
# .github/scripts/inject_salt.sh

# 🛑 1. STRICT ERROR HANDLING: Fail on errors, unset vars, and pipeline failures
set -euo pipefail

# Use :- to prevent 'unbound variable' crashes on our custom checks
TARGET_FILE="${1:-}"

if [ -z "$TARGET_FILE" ]; then
    echo "❌ ERROR: No target file provided."
    exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "❌ ERROR: Target file '$TARGET_FILE' does not exist."
    exit 1
fi

if [ -z "${PRODUCTION_SALT:-}" ]; then
    echo "❌ ERROR: PRODUCTION_SALT environment variable is not set."
    exit 1
fi

# 🛑 2. NEWLINE STRIPPING: Remove all newlines and carriage returns by design
CLEAN_SALT=$(printf '%s' "$PRODUCTION_SALT" | tr -d '\r\n')

echo "⚙️ Injecting secret into $TARGET_FILE..."

# 1. Escape for Godot's parser
GODOT_ESCAPED=$(printf '%s' "$CLEAN_SALT" | sed 's/\\/\\\\/g; s/"/\\"/g')

# 2. Escape for sed replacement string
SED_ESCAPED=$(printf '%s' "$GODOT_ESCAPED" | sed 's/\\/\\\\/g; s/&/\\&/g; s/|/\\|/g')

# 🛑 2.5. EMPTY SECRET GUARD: Catch secrets that become empty after stripping
if [ -z "$CLEAN_SALT" ]; then
    echo "❌ ERROR: PRODUCTION_SALT is empty or contains only newlines."
    exit 1
fi

# Source the shared utilities
source "$(dirname "$0")/ci_utils.sh"

# 3. Replace the safe placeholder with the real secret
sedi "s|\"CI_INJECT_SALT_HERE\"|\"$SED_ESCAPED\"|g" "$TARGET_FILE"

# 🛑 4. EXPLICIT VERIFICATION: Ensure the placeholder was actually removed
if grep -qF -- '"CI_INJECT_SALT_HERE"' "$TARGET_FILE"; then
    echo "❌ FATAL: Salt injection failed! Placeholder still exists in $TARGET_FILE."
    exit 1
else
    echo "✅ Salt successfully injected into $TARGET_FILE."
fi
