#!/bin/bash

# Script to apply security patch to index.js in Godot web export.
# Checks for file existence, applies flexible perl regex patch if the target pattern is found,
# and verifies application. Skips without error if pattern not present (e.g., non-threaded exports).
# Fails only if pattern present but patch doesn't apply.
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

# Define the original pattern regex for detection (escaped \" for bash/perl compatibility)
original_pattern='Module\[handler\]\s*=\s*\(\.\.\.args\)\s*=>\s*\{\s*postMessage\s*\(\s*\{\s*cmd\s*:\s*\"callHandler\"\s*,\s*handler\s*,\s*args\s*\}\s*\)\s*\}'

# Define the patched pattern for pre-check (fixed-string to avoid regex issues)
patched_pattern='if (["print","printErr"].includes(handler))'

# Pre-check if already patched
if grep -F -q "${patched_pattern}" "${index_js}"; then
  echo "File already patched; skipping."
  exit 0
fi

# Check if the original pattern exists (using Perl-compatible regex for consistency)
if grep -P -q "${original_pattern}" "${index_js}"; then
  # Apply patch using perl with alternate ~ delimiter for safety
  perl -i -pe "s~${original_pattern}~if ([\"print\",\"printErr\"].includes(handler)) { \$& }~g" "${index_js}"

  # Verify replacement occurred by checking for added if statement (fixed-string)
  if ! grep -F -q "${patched_pattern}" "${index_js}"; then
    echo "Error: Patch failed to apply despite pattern present."
    exit 1
  fi
  echo "Patch applied successfully."
else
  echo "No patchable pattern found; assuming non-threaded export where patch is not needed."
fi
