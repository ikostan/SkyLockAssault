#!/bin/bash
# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

echo "Running YAML Lint..."
yamllint -c .yamllint.yaml .github/workflows/*.yml
if [ $? -ne 0 ]; then echo "YAML lint failed."; exit 1; fi

echo "YAML Lint completed!"
