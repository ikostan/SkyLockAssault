#!/bin/bash
# .github/scripts/inject_salt.sh

# 🛑 STRICT ERROR HANDLING: Fail on errors, unset vars, and pipeline failures
set -euo pipefail

# ==============================================================================
# CI/CD SOURCE OF TRUTH CONTRACT
# If the variable declarations or security guards in globals.gd change,
# update these target patterns to match the new source structure.
# ==============================================================================
TARGET_VAR_PATTERN='var salt: String = "CI_INJECT_SALT_HERE"'
TARGET_GUARD_PATTERN='if salt == "CI_INJECT_SALT_HERE":'
# ==============================================================================

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

# 🛑 NEWLINE STRIPPING: Remove all newlines and carriage returns by design
CLEAN_SALT=$(printf '%s' "$PRODUCTION_SALT" | tr -d '\r\n')

echo "⚙️ Injecting secret into $TARGET_FILE..."

# Escape for Godot's parser
GODOT_ESCAPED=$(printf '%s' "$CLEAN_SALT" | sed 's/\\/\\\\/g; s/"/\\"/g')

# Escape for sed replacement string
SED_ESCAPED=$(printf '%s' "$GODOT_ESCAPED" | sed 's/\\/\\\\/g; s/&/\\&/g; s/|/\\|/g')

# 🛑 EMPTY SECRET GUARD: Catch secrets that become empty after stripping
if [ -z "$CLEAN_SALT" ]; then
    echo "❌ ERROR: PRODUCTION_SALT is empty or contains only newlines."
    exit 1
fi

# Source the shared utilities
source "$(dirname "$0")/ci_utils.sh"

# 1. THE FIX: Target ONLY the variable assignment line using the contract variable
sedi "s|$TARGET_VAR_PATTERN|var salt: String = \"$SED_ESCAPED\"|g" "$TARGET_FILE"

# 2. THE HARD GATE: Verify the placeholder was injected using the contract variable
if grep -qF "$TARGET_VAR_PATTERN" "$TARGET_FILE"; then
    echo "❌ FATAL: Salt injection failed! Variable assignment still has the placeholder in $TARGET_FILE."
    exit 1
fi

# 3. THE SECURITY GUARD: Verify the conditional logic was NOT overwritten using the contract variable
if ! grep -qF "$TARGET_GUARD_PATTERN" "$TARGET_FILE"; then
    echo "❌ FATAL: Salt injection corrupted the security guard logic in $TARGET_FILE!"
    exit 1
fi

echo "✅ Salt successfully injected and security guards verified in $TARGET_FILE."
