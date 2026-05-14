#!/usr/bin/env python3
"""
Infrastructure utility for Godot 4 Web exports.

This script modifies 'export_presets.cfg' to inject a custom 'ci' feature flag.
"""

import re
import shutil
import sys
from pathlib import Path

# Force UTF-8 encoding for stdout to prevent crashes on Windows legacy terminals
if sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8")


def inject_ci_flag():
    """
    Parses export_presets.cfg and injects the 'ci' flag into custom_features.
    Uses a 'Strip and Append' strategy to safely handle multiple presets.
    """
    config_path = Path("export_presets.cfg")
    backup_path = Path("export_presets.cfg.bak")

    try:
        if config_path.exists():
            shutil.copy2(config_path, backup_path)
        else:
            print(
                f"❌ ERROR: {config_path} not found. Ensure you are in the project root."
            )
            sys.exit(1)

        data = config_path.read_text(encoding="utf-8")

        # 1. Strip out ANY existing custom_features lines to ensure a clean slate.
        # (?m) enables multiline mode. ^ matches the start of a line. \r?\n? handles line breaks.
        updated_data = re.sub(r"(?m)^custom_features=.*\r?\n?", "", data)

        # 2. Inject the 'ci' flag directly under EVERY preset options header.
        updated_data = re.sub(
            r"(\[preset\.\d+\.options\])", r'\1\ncustom_features="ci"', updated_data
        )

        config_path.write_text(updated_data, encoding="utf-8")

        print("✅ Successfully injected 'ci' feature flag into export_presets.cfg")

    except Exception as e:
        try:
            print(f"❌ Failed to inject 'ci' flag: {e}")
        except UnicodeEncodeError:
            print(f"Failed to inject 'ci' flag (encoding error in logs): {e}")
        sys.exit(1)


if __name__ == "__main__":
    inject_ci_flag()
