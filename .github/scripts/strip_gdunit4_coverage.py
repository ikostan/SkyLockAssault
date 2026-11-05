#!/usr/bin/env python3
"""
Strip gdUnit4-coverage references from a Godot project.godot file (CI only).

The committed project.godot keeps the gdUnit4-coverage plugin enabled for local
editor use, but CI deletes the addon. Without this cleanup gdUnit4 fails while
loading the missing session hook. Only the CI checkout is modified; nothing is
committed back.

Removes:
  1. The whole [gdunit4_coverage] section (header through the next section).
  2. Dictionary entries pointing into the addon (e.g. the session hook),
     including the dangling comma left when the removed entry was the last one.
  3. The plugin path from PackedStringArray lists (e.g. editor_plugins/enabled).

Exits with status 1 if any gdunit4_coverage reference survives, so new kinds of
references fail loudly instead of breaking the gdUnit4 run later.

Usage: python3 .github/scripts/strip_gdunit4_coverage.py [path/to/project.godot]
"""

import re
import sys
from pathlib import Path

NEEDLE = "gdunit4_coverage"
DEFAULT_PATH = "project.godot"


class UnhandledReferenceError(Exception):
    """Raised when gdunit4_coverage references remain after stripping."""

    def __init__(self, leftover: list[str]):
        self.leftover = leftover
        super().__init__(f"Unhandled {NEEDLE} references remain")


def strip_coverage(text: str) -> str:
    """Return ``text`` with every gdUnit4-coverage reference removed.

    Raises UnhandledReferenceError if a reference survives the known rules.
    """
    out = []
    in_cov_section = False
    for line in text.splitlines():
        stripped = line.strip()
        # 1. Drop the whole [gdunit4_coverage] section
        if stripped.startswith("[") and stripped.endswith("]"):
            in_cov_section = stripped == f"[{NEEDLE}]"
            if in_cov_section:
                continue
        if in_cov_section:
            continue
        # 2. Drop dictionary entries pointing into the addon (e.g. the session hook)
        if stripped.startswith(f'"res://addons/{NEEDLE}/'):
            continue
        # 3. Remove the plugin from PackedStringArray lists
        if NEEDLE in line and "PackedStringArray(" in line:
            line = re.sub(rf',\s*"res://addons/{NEEDLE}/[^"]*"', "", line)
            line = re.sub(rf'"res://addons/{NEEDLE}/[^"]*"\s*,\s*', "", line)
            line = re.sub(rf'"res://addons/{NEEDLE}/[^"]*"', "", line)
        out.append(line)

    result = "\n".join(out) + "\n"
    # Removing the last entry of a multi-line dict can leave a comma before "}"
    result = re.sub(r",(\s*\n\s*\})", r"\1", result)

    leftover = [line for line in result.splitlines() if NEEDLE in line]
    if leftover:
        raise UnhandledReferenceError(leftover)
    return result


def main(argv: list[str]) -> int:
    """Strip the file named in argv[1] (default: project.godot) in place."""
    config_path = Path(argv[1]) if len(argv) > 1 else Path(DEFAULT_PATH)
    text = config_path.read_text(encoding="utf-8")
    try:
        result = strip_coverage(text)
    except UnhandledReferenceError as err:
        print(f"::error file={config_path}::Unhandled {NEEDLE} references remain:")
        print("\n".join(err.leftover))
        return 1

    config_path.write_text(result, encoding="utf-8")
    print(f"✅ Stripped {NEEDLE} plugin, hook, and settings from {config_path}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
