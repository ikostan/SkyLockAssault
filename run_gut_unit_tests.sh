#!/bin/bash
# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later

# This script runs GUT unit tests locally on Windows 10 using Godot 4.4/4.5.
# Assumptions:
# - Godot executable is in your PATH or specify the full path below.
# - Project is in the current directory.
# - Tests are located in res://test/ and use GUT syntax.
# - Run this script from the project root using Git Bash, WSL, or similar.
# - A .gutconfig.json file should exist in the project root (create one if missing; see Step 2).

# Path to Godot executable (update if not in PATH; on Windows, it's godot.exe)
GODOT="godot"  # Or full path, e.g., "C:/Path/To/Godot/godot.exe"

# Project directory (current working directory)
PROJECT_DIR="$(pwd)"

# Install GUT if not already in addons/
echo "Ensuring GUT is installed in addons/..."
if [ ! -d "$PROJECT_DIR/addons/gut" ]; then
  mkdir -p "$PROJECT_DIR/addons"
  wget https://github.com/bitwes/Gut/archive/refs/tags/v9.5.0.zip
  unzip v9.5.0.zip -d "$PROJECT_DIR/addons"
  mv "$PROJECT_DIR/addons/Gut-9.5.0/addons/gut" "$PROJECT_DIR/addons/gut"
  rm -rf "$PROJECT_DIR/addons/Gut-9.5.0" v9.5.0.zip
fi

# Optional: Import resources (uncomment if needed; runs Godot headless to import)
echo "Importing Resources..."
"$GODOT" --headless --path "$PROJECT_DIR" --import --quit
if [ $? -ne 0 ]; then echo "Resource import failed."; exit 1; fi

# Run GUT tests
echo "Running GUT Unit Tests..."
"$GODOT" --headless --verbose --path "$PROJECT_DIR" -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gdir=res://test -ginclude_subdirs=true -gexit
if [ $? -ne 0 ]; then echo "Unit tests failed."; exit 1; fi

# Optional: Handle reports (GUT can generate JUnit XML or other reports based on config)
echo "Tests completed! Check reports in gut-reports/ or configured directory if generated."
