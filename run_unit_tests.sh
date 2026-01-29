#!/bin/bash
# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later

PROJECT_DIR="/project"

echo "Ensuring GDUnit4 in project addons..."
cp -r /project/addons/gdUnit4 $PROJECT_DIR/addons/ || true

echo "Importing Resources..."
godot --headless --path $PROJECT_DIR --import --quit
if [ $? -ne 0 ]; then echo "Resource import failed."; exit 1; fi

echo "Running GDUnit4 Tests..."
godot --headless --path $PROJECT_DIR -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --add res://test
if [ $? -ne 0 ]; then echo "Unit tests failed."; exit 1; fi

# Simulate artifact: Copy reports
mkdir -p $PROJECT_DIR/reports
cp -r reports/** $PROJECT_DIR/reports || true

echo "Godot Unit Tests completed!"
