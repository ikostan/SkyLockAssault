#!/bin/bash
# .github/scripts/ci_utils.sh
#
# Utility functions for local CI simulation and GitHub Actions.
# This script is designed to be sourced by other bash scripts to provide
# shared, cross-platform functionality.

# -----------------------------------------------------------------------------
# Function: sedi
# Description: A cross-platform wrapper for 'sed' in-place file editing.
#
# Why this is needed:
# GNU 'sed' (Linux, WSL, Git Bash on Windows) uses: sed -i '...'
# BSD 'sed' (macOS/Darwin) requires an empty string extension: sed -i '' '...'
# This function checks the OS and automatically applies the correct syntax
# so the script doesn't crash or corrupt files for developers on Macs.
# -----------------------------------------------------------------------------
sedi() {
  if [ "$(uname)" = "Darwin" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# -----------------------------------------------------------------------------
# Function: disable_editor_plugins
# Description: Safely strips editor plugins from the project configuration.
#
# Why this is needed:
# Running Godot headless exports on CI runners (like Ubuntu) can sometimes cause
# Signal 11 crashes if UI-dependent plugins (like GUT) attempt to initialize.
# This function isolates the [editor_plugins] block in the project config
# and clears the 'enabled' array to ensure a safe, headless build.
#
# Arguments:
#   $1 - (Optional) Path to the Godot project file.
#        Defaults to "project.godot" in the current working directory.
# -----------------------------------------------------------------------------
disable_editor_plugins() {
    local target_file="${1:-project.godot}"
    echo "🔌 Disabling editor plugins in $target_file to prevent headless crashes..."
    sedi '/^\[editor_plugins\]/,/^\[/ s/^enabled=PackedStringArray.*/enabled=PackedStringArray()/' "$target_file"
}
