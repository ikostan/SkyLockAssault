#!/bin/bash

echo "Running YAML Lint..."
yamllint -c .yamllint.yaml .github/workflows/*.yml
if [ $? -ne 0 ]; then echo "YAML lint failed."; exit 1; fi

echo "YAML Lint completed!"
