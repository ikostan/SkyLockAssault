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

# Define the original fixed string for detection (exact match from threaded minified code)
original_fixed='Module[handler]=(...args)=>{postMessage({cmd:"callHandler",handler,args})}'

# Define the patched fixed string for pre-check (exact match after patch)
patched_fixed='if (["print","printErr"].includes(handler)) { Module[handler]=(...args)=>{postMessage({cmd:"callHandler",handler,args})} }'

# Pre-check if already patched (using fixed-string grep for simplicity and reliability)
if grep -F -q "${patched_fixed}" "${index_js}"; then
  echo "File already patched; skipping."
  exit 0
fi

# Check if the original pattern exists (using fixed-string grep for consistency)
if grep -F -q "${original_fixed}" "${index_js}"; then
  # Apply patch using perl with \Q for literal quoting of the original string
  perl -i -pe "s~\Q${original_fixed}~if ([\"print\",\"printErr\"].includes(handler)) { \$& }~g" "${index_js}"

  # Verify replacement occurred by checking for added if statement (fixed-string)
  if ! grep -F -q "${patched_fixed}" "${index_js}"; then
    echo "Error: Patch failed to apply despite pattern present."
    exit 1
  fi
  echo "Patch applied successfully."
else
  echo "No patchable pattern found; assuming non-threaded export where patch is not needed."
fi
