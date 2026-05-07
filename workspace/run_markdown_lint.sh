#!/bin/bash
# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later

echo "Running Markdown Lint..."
markdownlint-cli2 "**/*.md" --config .markdownlint-cli2.yaml --fix
if [ $? -ne 0 ]; then echo "Markdown lint failed."; exit 1; fi

echo "Markdown Lint completed!"
