# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""
Production code bundler for SkyLockAssault.

Merges every production GDScript file under 'scripts/' into a single text
file ('production_code_bundle.txt') at the repository root, so the whole
codebase can be handed to a high-context AI tool in one upload.

Each file is wrapped in START/END markers carrying its repo-relative path.
Files are sorted by path, so the output is deterministic and diff-friendly.

Companion to 'scan_project.py', which generates the folder/file tree
('project_structure.txt'). Use the tree for layout, this bundle for code.

Usage (from any working directory):
    python workspace/bundle_production_code.py
"""

import subprocess
import sys
from pathlib import Path

# Repo root resolved from this file's location:
# <root>/workspace/bundle_production_code.py
REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO_ROOT / "scripts"
OUTPUT_FILE = REPO_ROOT / "production_code_bundle.txt"
EXTENSION = ".gd"
# Folders under scripts/ that hold test code, not production logic.
EXCLUDED_DIRS = {"test", "tests"}
# Rough heuristic for code: ~4 characters per token.
CHARS_PER_TOKEN = 4


def get_commit_sha(repo_root: Path) -> str:
    """
    Return HEAD's commit SHA for the repository at repo_root.

    A '-dirty' suffix is added when Git reports changes under 'scripts/',
    including untracked files. Return 'unknown' if either Git command fails
    or cannot run, including when no repository or HEAD commit is available.
    """
    try:
        sha = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        dirty = subprocess.run(
            ["git", "status", "--porcelain", "--", "scripts"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        return f"{sha}-dirty" if dirty else sha
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def collect_files(source_dir: Path) -> list[Path]:
    """
    Return all production .gd files under source_dir, sorted by path.

    Only the exact '.gd' suffix matches, so '.gd.uid', '.import', '.tscn',
    '.tres' and binary assets are excluded automatically. Anything inside a
    'test/' or 'tests/' folder (at any depth under source_dir) is skipped.
    """
    files = [
        p
        for p in source_dir.rglob(f"*{EXTENSION}")
        if p.is_file()
        and not EXCLUDED_DIRS.intersection(p.relative_to(source_dir).parent.parts)
    ]
    return sorted(files, key=lambda p: p.relative_to(source_dir).as_posix())


def build_bundle(files: list[Path], repo_root: Path) -> tuple[str, int]:
    """
    Concatenate UTF-8 files in the supplied order with boundary markers.

    Markers use forward-slash paths relative to repo_root. Source line endings
    are normalized to LF, and a missing final newline is added before the end
    marker. Returns the bundle body and the total number of source lines,
    excluding markers and added newlines; empty input returns ('', 0).

    Raises ValueError if a path is not relative to repo_root. File read errors
    (OSError) and invalid UTF-8 (UnicodeDecodeError) propagate to the caller.
    """
    parts: list[str] = []
    total_lines = 0
    for path in files:
        rel = path.relative_to(repo_root).as_posix()
        content = path.read_text(encoding="utf-8")
        total_lines += len(content.splitlines())
        parts.append(f"===== START OF FILE: {rel} =====\n")
        parts.append(content if content.endswith("\n") else content + "\n")
        parts.append(f"===== END OF FILE: {rel} =====\n\n")
    return "".join(parts), total_lines


def main() -> int:
    """
    Build the production bundle with metadata at OUTPUT_FILE.

    Create or overwrite the output as UTF-8 with LF line endings and return 0
    on success. Return 1 without writing the output if SOURCE_DIR is missing
    or contains no eligible files. Paths are resolved from this script's
    location, independently of the current working directory.

    File read/write errors (OSError) and decoding errors (UnicodeDecodeError)
    propagate to the caller rather than becoming a return code.
    """
    if not SOURCE_DIR.is_dir():
        print(f"ERROR: source directory not found: {SOURCE_DIR}", file=sys.stderr)
        return 1

    files = collect_files(SOURCE_DIR)
    if not files:
        print(f"ERROR: no {EXTENSION} files found under {SOURCE_DIR}", file=sys.stderr)
        return 1

    body, total_lines = build_bundle(files, REPO_ROOT)
    est_tokens = len(body) // CHARS_PER_TOKEN

    header_lines = [
        "SkyLockAssault - Production Code Bundle",
        f"Commit: {get_commit_sha(REPO_ROOT)}",
        f"Source: scripts/**/*{EXTENSION}",
        f"Files: {len(files)}",
        f"Lines: {total_lines}",
        f"Estimated tokens: ~{est_tokens:,}",
        "=" * 60,
    ]
    header = "\n".join(header_lines) + "\n\n"

    # newline="\n" keeps the output identical on Windows and Linux.
    OUTPUT_FILE.write_text(header + body, encoding="utf-8", newline="\n")

    print(
        f"Bundle complete! {len(files)} files, {total_lines} lines, "
        f"~{est_tokens:,} tokens -> {OUTPUT_FILE.name}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
