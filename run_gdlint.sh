#!/bin/bash

PROJECT_DIR="/project"

echo "Running GDScript Format Check..."
gdformat --diff --check $PROJECT_DIR/scripts
if [ $? -ne 0 ]; then echo "Format check failed."; exit 1; fi

echo "Running GDScript Lint..."
gdlint $PROJECT_DIR/scripts
if [ $? -ne 0 ]; then echo "Lint failed."; exit 1; fi

echo "GDScript Lint and Format Check completed!"
