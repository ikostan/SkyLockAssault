#!/bin/bash

# To address the duplication of the "Flatten Export Directory" logic
# across workflows, I've extracted it into a shared Bash script at
# .github/tools/flatten_export.sh. This ensures consistency
# (using the hardened version with existence/emptiness checks and find
# to handle all files, including hidden ones), easier maintenance, and
# avoids code repetition. Place this script in your repository.

set -e

export_path="$1"
subdir="$2"
full_subdir="${export_path}/${subdir}"

# Explicitly fail if the directory doesn't exist
if [ ! -d "${full_subdir}" ]; then
  echo "Error: ${full_subdir} does not exist. Check the Godot export step."
  exit 1
fi

# Explicitly fail if the directory exists but is empty
if [ -z "$(ls -A "${full_subdir}")" ]; then
  echo "Error: ${full_subdir} exists but is empty. Verify Godot export generated files."
  exit 1
fi

# Now flatten (move all entries, including dotfiles, then remove the directory)
find "${full_subdir}" -mindepth 1 -maxdepth 1 -exec mv -t "${export_path}" {} +
rmdir "${full_subdir}"
