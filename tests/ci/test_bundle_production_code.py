# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_bundle_production_code.py

"""
Test suite for the production code bundler (workspace/bundle_production_code.py).

The bundler resolves the repo root from its own location, so each test builds
an isolated fake repo (<tmp>/workspace/ + <tmp>/scripts/) with a copy of the
script and runs it there. The real repo is never written to.

Audited for deterministic execution (subprocess timeouts, no static sleeps).
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[2]
BUNDLER_SCRIPT = PROJECT_ROOT / "workspace" / "bundle_production_code.py"
OUTPUT_NAME = "production_code_bundle.txt"
START = "===== START OF FILE: {} ====="
END = "===== END OF FILE: {} ====="


def make_fake_repo(root: Path, files: dict[str, str]) -> Path:
    """Create a fake repo with the bundler copied into <root>/workspace/."""
    (root / "workspace").mkdir(parents=True)
    shutil.copy2(BUNDLER_SCRIPT, root / "workspace" / BUNDLER_SCRIPT.name)
    for rel, content in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        # newline="" writes content exactly as given (lets tests use CRLF).
        path.write_text(content, encoding="utf-8", newline="")
    return root


def git_env(root: Path) -> dict[str, str]:
    """Env that stops git from discovering any repo above the fake one."""
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    env["GIT_CEILING_DIRECTORIES"] = str(root.parent)
    return env


def run_bundler(
    root: Path, cwd: Path | None = None
) -> subprocess.CompletedProcess[str]:
    """Run the fake repo's copy of the bundler, from root unless cwd is given."""
    return subprocess.run(
        [sys.executable, str(root / "workspace" / BUNDLER_SCRIPT.name)],
        env=git_env(root),
        cwd=str(cwd or root),
        capture_output=True,
        text=True,
        timeout=10,
        encoding="utf-8",
        check=False,  # Exit codes are asserted explicitly
    )


def read_bundle(root: Path) -> str:
    """Read the bundle without newline translation, so '\\r' would be visible."""
    with open(root / OUTPUT_NAME, encoding="utf-8", newline="") as f:
        return f.read()


def bundled_paths(bundle: str) -> list[str]:
    """Return the file paths listed in START markers, in bundle order."""
    prefix, suffix = "===== START OF FILE: ", " ====="
    return [
        line[len(prefix) : -len(suffix)]
        for line in bundle.splitlines()
        if line.startswith(prefix)
    ]


def git(root: Path, *args: str) -> str:
    """Run a git command inside the fake repo and return stdout."""
    return subprocess.run(
        ["git", "-c", "user.name=test", "-c", "user.email=test@example.com", *args],
        cwd=str(root),
        env=git_env(root),
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    ).stdout.strip()


def test_bundler_script_exists():
    """The bundler lives in workspace/ next to scan_project.py."""
    assert BUNDLER_SCRIPT.is_file()
    assert (PROJECT_ROOT / "workspace" / "scan_project.py").is_file()


def test_includes_only_gd_files_under_scripts(tmp_path):
    """Only scripts/**/*.gd is bundled; sidecars, scenes, tests and addons are not."""
    root = make_fake_repo(
        tmp_path / "repo",
        {
            "scripts/core/a.gd": "extends Node\n",
            "scripts/ui/deep/nested/b.gd": "extends Control\n",
            "scripts/core/a.gd.uid": "uid://abc\n",
            "scripts/ui/menu.tscn": "[gd_scene]\n",
            "scripts/resources/data.tres": "[gd_resource]\n",
            "scripts/core/icon.png.import": "[remap]\n",
            "scripts/core/notes.gdshader": "shader_type canvas_item;\n",
            "test/gut/test_a.gd": "extends GutTest\n",
            "addons/gut/gut.gd": "extends Node\n",
        },
    )
    result = run_bundler(root)
    assert result.returncode == 0, result.stderr

    assert bundled_paths(read_bundle(root)) == [
        "scripts/core/a.gd",
        "scripts/ui/deep/nested/b.gd",
    ]


def test_excludes_test_dirs_inside_scripts(tmp_path):
    """Test code under scripts/test/ or scripts/tests/ (any depth) is not bundled."""
    root = make_fake_repo(
        tmp_path / "repo",
        {
            "scripts/core/a.gd": "extends Node\n",
            "scripts/test/test_a.gd": "extends GutTest\n",
            "scripts/tests/test_b.gd": "extends GutTest\n",
            "scripts/ui/tests/helpers/c.gd": "extends Node\n",
            "scripts/ui/latest/d.gd": "extends Node\n",
            "scripts/ui/test_utils.gd": "extends Node\n",
        },
    )
    assert run_bundler(root).returncode == 0

    # Only folders named exactly test/tests are skipped, not similar names or files.
    assert bundled_paths(read_bundle(root)) == [
        "scripts/core/a.gd",
        "scripts/ui/latest/d.gd",
        "scripts/ui/test_utils.gd",
    ]


def test_files_are_sorted_by_path(tmp_path):
    """Order is by repo-relative path, independent of creation order."""
    root = make_fake_repo(
        tmp_path / "repo",
        {
            "scripts/ui/z.gd": "# z\n",
            "scripts/core/b.gd": "# b\n",
            "scripts/core/a.gd": "# a\n",
            "scripts/entities/m.gd": "# m\n",
        },
    )
    assert run_bundler(root).returncode == 0

    assert bundled_paths(read_bundle(root)) == [
        "scripts/core/a.gd",
        "scripts/core/b.gd",
        "scripts/entities/m.gd",
        "scripts/ui/z.gd",
    ]


def test_markers_wrap_exact_file_content(tmp_path):
    """Each file sits verbatim between its START and END markers."""
    content = "extends Node\n\nfunc _ready() -> void:\n\tpass\n"
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/main.gd": content})
    assert run_bundler(root).returncode == 0

    rel = "scripts/core/main.gd"
    expected = f"{START.format(rel)}\n{content}{END.format(rel)}\n"
    assert expected in read_bundle(root)


def test_missing_trailing_newline_does_not_merge_into_end_marker(tmp_path):
    """A file without a final newline still gets its END marker on its own line."""
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/a.gd": "var x = 1"})
    assert run_bundler(root).returncode == 0

    rel = "scripts/core/a.gd"
    assert f"var x = 1\n{END.format(rel)}\n" in read_bundle(root)


def test_header_reports_counts(tmp_path):
    """Header lists source glob, file count and total line count."""
    root = make_fake_repo(
        tmp_path / "repo",
        {
            "scripts/core/a.gd": "line1\nline2\nline3\n",
            "scripts/ui/b.gd": "line1\nline2\n",
        },
    )
    result = run_bundler(root)
    assert result.returncode == 0

    header = read_bundle(root).split("=" * 60, 1)[0]
    assert header.startswith("SkyLockAssault - Production Code Bundle\n")
    assert "Source: scripts/**/*.gd\n" in header
    assert "Files: 2\n" in header
    assert "Lines: 5\n" in header
    assert "Estimated tokens: ~" in header
    assert "Bundle complete! 2 files, 5 lines" in result.stdout


def test_commit_is_unknown_outside_git(tmp_path):
    """Without a git repo the bundle still builds, with 'Commit: unknown'."""
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/a.gd": "# a\n"})
    assert run_bundler(root).returncode == 0
    assert "Commit: unknown\n" in read_bundle(root)


@pytest.mark.skipif(shutil.which("git") is None, reason="git not installed")
def test_commit_sha_and_dirty_flag(tmp_path):
    """Header carries HEAD's SHA, with '-dirty' only when scripts/ has changes."""
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/a.gd": "# a\n"})
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "init")
    sha = git(root, "rev-parse", "HEAD")

    assert run_bundler(root).returncode == 0
    assert f"Commit: {sha}\n" in read_bundle(root)

    # Changes outside scripts/ (including the bundle itself) don't mark it dirty.
    (root / "README.md").write_text("changed\n", encoding="utf-8")
    assert run_bundler(root).returncode == 0
    assert f"Commit: {sha}\n" in read_bundle(root)

    (root / "scripts" / "core" / "a.gd").write_text("# changed\n", encoding="utf-8")
    assert run_bundler(root).returncode == 0
    assert f"Commit: {sha}-dirty\n" in read_bundle(root)


def test_output_is_deterministic(tmp_path):
    """Two runs over the same tree produce byte-identical bundles."""
    root = make_fake_repo(
        tmp_path / "repo",
        {"scripts/core/a.gd": "# a\n", "scripts/ui/b.gd": "# b\n"},
    )
    assert run_bundler(root).returncode == 0
    first = read_bundle(root)
    assert run_bundler(root).returncode == 0
    assert read_bundle(root) == first


def test_runs_from_any_working_directory(tmp_path):
    """Output goes to the repo root even when run from somewhere else."""
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/a.gd": "# a\n"})
    elsewhere = tmp_path / "elsewhere"
    elsewhere.mkdir()

    assert run_bundler(root, cwd=elsewhere).returncode == 0
    assert (root / OUTPUT_NAME).is_file()
    assert not (elsewhere / OUTPUT_NAME).exists()


def test_output_uses_lf_line_endings(tmp_path):
    """CRLF sources are normalized, so the bundle is LF on every OS."""
    root = make_fake_repo(
        tmp_path / "repo", {"scripts/core/a.gd": "extends Node\r\nvar x = 1\r\n"}
    )
    assert run_bundler(root).returncode == 0

    bundle = read_bundle(root)
    assert "\r" not in bundle
    assert "extends Node\nvar x = 1\n" in bundle


def test_fails_when_scripts_dir_missing(tmp_path):
    """No scripts/ directory: exit 1 with an error, and no bundle written."""
    root = make_fake_repo(tmp_path / "repo", {})
    result = run_bundler(root)

    assert result.returncode == 1
    assert "source directory not found" in result.stderr
    assert not (root / OUTPUT_NAME).exists()


def test_fails_when_no_gd_files(tmp_path):
    """scripts/ without any .gd files: exit 1 with an error, and no bundle written."""
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/a.gd.uid": "uid://x\n"})
    result = run_bundler(root)

    assert result.returncode == 1
    assert "no .gd files found" in result.stderr
    assert not (root / OUTPUT_NAME).exists()
