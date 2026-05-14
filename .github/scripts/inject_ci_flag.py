#!/usr/bin/env python3
"""
Infrastructure utility for Godot 4 Web exports.

This script modifies 'export_presets.cfg' to inject a custom 'ci' feature flag.
Godot 4 ignores command-line feature flags during headless exports, so the
flag must be persisted directly into the configuration file to allow
conditional logic (like security guards or test fallbacks) to trigger
correctly in automated environments.
"""

import re
import sys
import shutil
from pathlib import Path


def inject_ci_flag():
    """
    Parses export_presets.cfg and injects the 'ci' flag into custom_features.

    The function performs the following steps:
    1. Creates a 'export_presets.cfg.bak' backup for safety.
    2. Uses regex to locate 'custom_features' within the configuration presets.
    3. If 'custom_features' exists, it overwrites the value with 'ci'.
    4. If 'custom_features' is missing, it appends it to the options section.

    Raises:
        SystemExit: If the configuration file is missing or unwriteable.
    """
    config_path = Path("export_presets.cfg")
    backup_path = Path("export_presets.cfg.bak")

    try:
        # 1. Create a backup for safety before modification
        if config_path.exists():
            shutil.copy2(config_path, backup_path)
        else:
            print(f"❌ ERROR: {config_path} not found. Ensure you are in the project root.")
            sys.exit(1)

        # 2. Read the configuration data
        data = config_path.read_text(encoding="utf-8")

        # 3. Inject into existing custom_features or add it if missing
        # This regex targets the value assigned to custom_features
        updated_data = re.sub(r'custom_features=\"[^\"]*\"', 'custom_features=\"ci\"', data)

        if 'custom_features="ci"' not in updated_data:
            # If the key didn't exist, append it to the first options section found
            updated_data = re.sub(r'(\[preset\.\d+\.options\])', r'\1\ncustom_features="ci"', updated_data)

        # 4. Save the modified configuration
        config_path.write_text(updated_data, encoding="utf-8")

        print("✅ Successfully injected 'ci' feature flag into export_presets.cfg")

    except Exception as e:
        print(f"❌ Failed to inject 'ci' flag: {e}")
        sys.exit(1)


if __name__ == "__main__":
    inject_ci_flag()
