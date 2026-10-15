# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""
Production code bundler for SkyLockAssault.

Merges every production GDScript file under 'scripts/' into a single text
file ('production_code_bundle.txt') at the repository root, so the whole
codebase can be handed to a high-context AI tool in one upload.

Each file is wrapped in START/END markers carrying its repo-relative path.
Files are sorted by path, so the output is deterministic and diff-friendly.

Symlinks under 'scripts/' are never followed: they are skipped and reported,
so the bundle only ever contains real files from this repository.

Companion to 'scan_project.py', which generates the folder/file tree
('project_structure.txt'). Use the tree for layout, this bundle for code.

Usage (from any working directory):
    python workspace/bundle_production_code.py
"""

import os
import shutil
import subprocess
import sys
import tempfile
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

    A '-dirty' suffix is added when 'scripts/' differs from HEAD in any way,
    including modified, untracked, or git-ignored files that could still be bundled.
    Return 'unknown' if either Git command fails or cannot run, including when
    no repository or HEAD commit is available.
    """
    git = shutil.which("git")
    if git is None:
        return "unknown"
    try:
        sha = subprocess.run(
            [git, "rev-parse", "HEAD"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        dirty = subprocess.run(
            [git, "status", "--porcelain", "--ignored", "--", "scripts"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
        return f"{sha}-dirty" if dirty else sha
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def _is_excluded(path: Path, source_dir: Path) -> bool:
    """True if path sits inside a test/ or tests/ folder under source_dir."""
    return bool(EXCLUDED_DIRS.intersection(path.relative_to(source_dir).parent.parts))


def find_symlinks(source_dir: Path) -> list[Path]:
    """
    Return every symlink (file or directory) under source_dir, sorted by path.

    rglob() lists directory symlinks but does not descend into them, so this
    reports each skipped link once instead of silently dropping its contents.
    """
    links = [p for p in source_dir.rglob("*") if p.is_symlink()]
    return sorted(links, key=lambda p: p.relative_to(source_dir).as_posix())


def collect_files(source_dir: Path) -> list[Path]:
    """
    Return all production .gd files under source_dir, sorted by path.

    Only the exact '.gd' suffix matches, so '.gd.uid', '.import', '.tscn',
    '.tres' and binary assets are excluded automatically. Anything inside a
    'test/' or 'tests/' folder (at any depth under source_dir) is skipped,
    and so is any symlinked file (see find_symlinks()).
    """
    files = [
        p
        for p in source_dir.rglob(f"*{EXTENSION}")
        if p.is_file() and not p.is_symlink() and not _is_excluded(p, source_dir)
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


def write_atomically(target: Path, text: str) -> None:
    """
    Write text to target via a temp file in the same folder, then swap it in.

    os.replace() replaces the directory entry itself, so an existing symlink at
    target is replaced, never followed, and a failed or interrupted write leaves
    the previous file untouched. newline="\\n" keeps output identical on every OS.
    """
    fd, tmp_name = tempfile.mkstemp(
        dir=target.parent, prefix=f".{target.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as tmp:
            tmp.write(text)
        os.replace(tmp_name, target)
    except BaseException:
        Path(tmp_name).unlink(missing_ok=True)
        raise


def _fail(message: str) -> int:
    """Print an error, remove any previous bundle so it can't be mistaken for current."""
    print(f"ERROR: {message}", file=sys.stderr)
    OUTPUT_FILE.unlink(missing_ok=True)
    return 1


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
        return _fail(f"source directory not found: {SOURCE_DIR}")

    for link in find_symlinks(SOURCE_DIR):
        print(
            f"WARNING: skipping symlink {link.relative_to(REPO_ROOT).as_posix()}",
            file=sys.stderr,
        )

    files = collect_files(SOURCE_DIR)
    if not files:
        return _fail(f"no {EXTENSION} files found under {SOURCE_DIR}")

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

    write_atomically(OUTPUT_FILE, header + body)

    print(
        f"Bundle complete! {len(files)} files, {total_lines} lines, "
        f"~{est_tokens:,} tokens -> {OUTPUT_FILE.name}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
