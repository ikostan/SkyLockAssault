#!/bin/bash
# .github/scripts/inject_salt.sh

TARGET_FILE="$1"

if [ -z "$TARGET_FILE" ]; then
    echo "❌ ERROR: No target file provided."
    exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "❌ ERROR: Target file '$TARGET_FILE' does not exist."
    exit 1
fi

if [ -z "$PRODUCTION_SALT" ]; then
    echo "❌ ERROR: PRODUCTION_SALT environment variable is not set."
    exit 1
fi

echo "⚙️ Injecting secret into $TARGET_FILE..."

# 1. Escape for Godot's parser
GODOT_ESCAPED=$(printf '%s' "$PRODUCTION_SALT" | sed 's/\\/\\\\/g; s/"/\\"/g')

# 2. Escape for sed replacement string
SED_ESCAPED=$(printf '%s' "$GODOT_ESCAPED" | sed 's/\\/\\\\/g; s/&/\\&/g; s/|/\\|/g')

# 3. Replace the safe placeholder with the real secret
sed -i "s|\"CI_INJECT_SALT_HERE\"|\"$SED_ESCAPED\"|g" "$TARGET_FILE"
