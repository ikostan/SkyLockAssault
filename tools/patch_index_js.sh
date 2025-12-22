#!/bin/bash

# Script to apply security patch to index.js in Godot web export.
# Checks for file existence, applies flexible perl regex patch,
# and verifies application. Fails on errors.
#
# Usage: bash patch_index_js.sh <web_export_dir>
# Example: bash patch_index_js.sh "export/web"

set -e

web_dir="$1"  # Directory containing index.js (string)

index_js="${web_dir}/index.js"  # Full path to index.js (string)

# Check if file exists
if [ ! -f "${index_js}" ]; then
  echo "Error: index.js not found in ${web_dir}"
  exit 1
fi

# Apply patch using perl with flexible regex to match smaller/stable fragment with optional whitespace
perl -i -pe 's/Module\[handler\]\s*=\s*\(\.\.\.args\)\s*=>\s*\{\s*postMessage\s*\(\s*\{\s*cmd\s*:\s*"callHandler"\s*,\s*handler\s*,\s*args\s*\}\s*\)\s*\}/if (["print","printErr"].includes(handler)) { $& }/g' "${index_js}"

# Verify replacement occurred by checking for added if statement
if ! grep -q 'if (\["print","printErr"\].includes(handler))' "${index_js}"; then
  echo "Error: Patch failed to apply - expected code not found."
  exit 1
fi
