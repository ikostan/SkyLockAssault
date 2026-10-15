# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_bundle_production_code.py
"""
Test suite for the production code bundler (workspace/bundle_production_code.py).

CLI tests use an isolated fake repo (<tmp>/workspace/ + <tmp>/scripts/) with a
copy of the script. Unit tests import the module and use temporary source files
or patch its repository paths. The real repo is never written to.

Audited for deterministic execution (subprocess timeouts, no static sleeps).
"""

import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
from pathlib import Path
from unittest.mock import Mock

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


def _without_git_vars(environ: dict[str, str]) -> dict[str, str]:
    """
    Copy of environ without any GIT_* variables.

    Git hooks (e.g. pre-commit) export GIT_DIR, GIT_INDEX_FILE, GIT_WORK_TREE and
    friends. Those override repository discovery, so leaving them in place would
    point git at the real repo instead of the fake one.
    """
    return {k: v for k, v in environ.items() if not k.startswith("GIT_")}


def git_env(root: Path) -> dict[str, str]:
    """Env confining git to the fake repo: no inherited GIT_* vars, no parent repos."""
    env = _without_git_vars(dict(os.environ))
    env["PYTHONIOENCODING"] = "utf-8"
    env["GIT_CEILING_DIRECTORIES"] = str(root.parent)
    return env


@pytest.fixture(autouse=True)
def isolate_git(tmp_path, monkeypatch):
    """
    Apply the same isolation to this test process.

    Unit tests call bundler.get_commit_sha() in-process, so its git subprocesses
    inherit os.environ rather than git_env(); clean that too.
    """
    for key in list(os.environ):
        if key.startswith("GIT_"):
            monkeypatch.delenv(key)
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))


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
    r"""Read the bundle without newline translation, so '\r' would be visible."""
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


def make_symlink(link: Path, target: Path, is_dir: bool = False) -> None:
    """Create a symlink, or skip the test where the OS doesn't allow it (Windows)."""
    link.parent.mkdir(parents=True, exist_ok=True)
    try:
        link.symlink_to(target, target_is_directory=is_dir)
    except (OSError, NotImplementedError) as exc:
        pytest.skip(f"symlinks not supported here: {exc}")


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


@pytest.mark.skipif(shutil.which("git") is None, reason="git not installed")
def test_git_ignored_script_marks_dirty(tmp_path):
    """A bundled file that git ignores isn't in HEAD, so the header must say -dirty."""
    root = make_fake_repo(
        tmp_path / "repo",
        {"scripts/core/a.gd": "# a\n", ".gitignore": "scripts/core/local.gd\n"},
    )
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "init")
    sha = git(root, "rev-parse", "HEAD")
    (root / "scripts" / "core" / "local.gd").write_text("# local\n", encoding="utf-8")

    assert run_bundler(root).returncode == 0
    bundle = read_bundle(root)
    assert "scripts/core/local.gd" in bundled_paths(bundle)
    assert f"Commit: {sha}-dirty\n" in bundle


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
    """No scripts/ directory: exit 1, and a stale bundle from an earlier run is gone."""
    root = make_fake_repo(tmp_path / "repo", {OUTPUT_NAME: "stale bundle\n"})
    result = run_bundler(root)

    assert result.returncode == 1
    assert "source directory not found" in result.stderr
    assert not (root / OUTPUT_NAME).exists()


def test_fails_when_no_gd_files(tmp_path):
    """No .gd files: exit 1, and a stale bundle from an earlier run is removed."""
    root = make_fake_repo(
        tmp_path / "repo",
        {"scripts/core/a.gd.uid": "uid://x\n", OUTPUT_NAME: "stale bundle\n"},
    )
    result = run_bundler(root)

    assert result.returncode == 1
    assert "no .gd files found" in result.stderr
    assert not (root / OUTPUT_NAME).exists()


@pytest.fixture
def bundler():
    """Load a fresh bundler module without invoking its CLI entry point."""
    spec = importlib.util.spec_from_file_location(
        "bundle_production_code", BUNDLER_SCRIPT
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def unit_repo(tmp_path, monkeypatch, bundler):
    """Point main() at a temporary repository with predictable commit metadata."""
    root = tmp_path / "repo"
    (root / "scripts").mkdir(parents=True)
    monkeypatch.setattr(bundler, "REPO_ROOT", root)
    monkeypatch.setattr(bundler, "SOURCE_DIR", root / "scripts")
    monkeypatch.setattr(bundler, "OUTPUT_FILE", root / OUTPUT_NAME)
    monkeypatch.setattr(bundler, "get_commit_sha", lambda repo_root: "test-sha")
    return root


@pytest.mark.parametrize("root_name", ["test", "tests", "project with spaces"])
def test_collect_files_checks_only_directories_below_source(
    tmp_path, bundler, root_name
):
    """Ancestor names, test-like file names and .gd directories remain distinct."""
    root = make_fake_repo(
        tmp_path / root_name,
        {
            "scripts/z.gd": "# last\n",
            "scripts/test.gd": "# production\n",
            "scripts/testing/tests.gd": "# production helper\n",
            "scripts/test/hidden.gd": "# excluded\n",
            "scripts/core/tests/deep/hidden.gd": "# excluded\n",
            "scripts/core/a.gd.uid": "uid://sidecar\n",
            "scripts/directory.gd/notes.txt": "not a script\n",
            "addons/outside.gd": "# outside source\n",
        },
    )

    assert bundler.collect_files(root / "scripts") == [
        root / "scripts/test.gd",
        root / "scripts/testing/tests.gd",
        root / "scripts/z.gd",
    ]


@pytest.mark.parametrize(
    ("content", "normalized", "lines"),
    [
        pytest.param("", "\n", 0, id="empty"),
        pytest.param("\n", "\n", 1, id="blank-line"),
        pytest.param("\n\n", "\n\n", 2, id="two-blank-lines"),
        pytest.param(" \t", " \t\n", 1, id="whitespace-without-newline"),
        pytest.param("first\nlast", "first\nlast\n", 2, id="unterminated-last-line"),
        pytest.param("first\r\nlast\r\n", "first\nlast\n", 2, id="crlf"),
        pytest.param("first\rlast\r", "first\nlast\n", 2, id="bare-cr"),
        pytest.param('var café = "🚁"\n', 'var café = "🚁"\n', 1, id="unicode"),
    ],
)
def test_build_bundle_preserves_content_and_counts_source_lines(
    tmp_path, bundler, content, normalized, lines
):
    """Markers and inserted newlines must not inflate the source line count."""
    root = make_fake_repo(tmp_path / "repo", {"scripts/ui/écran.gd": content})
    rel = "scripts/ui/écran.gd"

    body, total_lines = bundler.build_bundle([root / rel], root)

    assert body == f"{START.format(rel)}\n{normalized}{END.format(rel)}\n\n"
    assert total_lines == lines


def test_build_bundle_preserves_supplied_order_and_file_boundaries(tmp_path, bundler):
    """Building honors the input sequence and keeps adjacent empty files separate."""
    root = make_fake_repo(
        tmp_path / "repo", {"scripts/z.gd": "last", "scripts/a.gd": ""}
    )

    body, lines = bundler.build_bundle(
        [root / "scripts/z.gd", root / "scripts/a.gd"], root
    )

    assert body == (
        f"{START.format('scripts/z.gd')}\nlast\n"
        f"{END.format('scripts/z.gd')}\n\n"
        f"{START.format('scripts/a.gd')}\n\n"
        f"{END.format('scripts/a.gd')}\n\n"
    )
    assert lines == 1


def test_build_bundle_with_no_files(bundler, tmp_path):
    """An empty input has neither source lines nor boundary markers."""
    assert bundler.build_bundle([], tmp_path) == ("", 0)


@pytest.mark.parametrize("failing_command", ["rev-parse", "status"])
@pytest.mark.parametrize(
    "error_type", [OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired]
)
def test_commit_metadata_falls_back_when_either_git_command_fails(
    tmp_path, monkeypatch, bundler, failing_command, error_type
):
    """Missing, failing or hung Git (either command) degrades to unknown metadata."""
    errors = {
        OSError: OSError("git unavailable"),
        subprocess.CalledProcessError: subprocess.CalledProcessError(
            128, ["git", failing_command]
        ),
        subprocess.TimeoutExpired: subprocess.TimeoutExpired(
            ["git", failing_command], timeout=10
        ),
    }
    error = errors[error_type]
    responses = [error]
    if failing_command == "status":
        responses.insert(
            0, subprocess.CompletedProcess([], 0, stdout=f"{tmp_path}\nabc123\n")
        )
    run = Mock(side_effect=responses)
    monkeypatch.setattr(bundler.subprocess, "run", run)
    # Pretend git is installed, so the test also passes on machines without it.
    monkeypatch.setattr(bundler.shutil, "which", lambda name: "/usr/bin/git")

    assert bundler.get_commit_sha(tmp_path) == "unknown"
    assert run.call_count == (1 if failing_command == "rev-parse" else 2)


@pytest.mark.skipif(shutil.which("git") is None, reason="git not installed")
@pytest.mark.parametrize(
    "change", ["untracked-script", "staged-script", "staged-deletion", "non-gd-file"]
)
def test_commit_metadata_detects_all_scripts_changes(tmp_path, bundler, change):
    """Metadata reflects untracked, staged, deleted and non-GDScript source changes."""
    root = make_fake_repo(tmp_path / "repo", {"scripts/a.gd": "# original\n"})
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "init")
    sha = git(root, "rev-parse", "HEAD")
    assert bundler.get_commit_sha(root) == sha

    if change == "staged-deletion":
        git(root, "rm", "scripts/a.gd")
    elif change == "non-gd-file":
        (root / "scripts/notes.txt").write_text("changed\n", encoding="utf-8")
    else:
        (root / "scripts/new.gd").write_text("# new\n", encoding="utf-8")
        if change == "staged-script":
            git(root, "add", "scripts/new.gd")

    assert bundler.get_commit_sha(root) == f"{sha}-dirty"


@pytest.mark.parametrize(
    "content",
    ["", "x", "xx", "xxx", "x" * 5000, "🚁" * 5],
    ids=["empty", "one-char", "two-chars", "three-chars", "large", "unicode"],
)
def test_main_reports_body_token_estimate_and_replaces_old_bundle(
    unit_repo, bundler, capsys, content
):
    """Token estimates use body characters, floor rounding and grouped numbers."""
    rel = "scripts/a.gd"
    (unit_repo / rel).write_text(content, encoding="utf-8")
    (unit_repo / OUTPUT_NAME).write_text("stale bundle", encoding="utf-8")
    body = f"{START.format(rel)}\n{content}\n{END.format(rel)}\n\n"
    tokens = len(body) // 4
    lines = 1 if content else 0
    header = (
        "SkyLockAssault - Production Code Bundle\n"
        "Commit: test-sha\n"
        f"Content SHA-256: {hashlib.sha256(body.encode('utf-8')).hexdigest()}\n"
        "Source: scripts/**/*.gd\n"
        "Files: 1\n"
        f"Lines: {lines}\n"
        f"Estimated tokens: ~{tokens:,}\n" + "=" * 60 + "\n\n"
    )

    assert bundler.main() == 0

    assert (unit_repo / OUTPUT_NAME).read_bytes() == (header + body).encode("utf-8")
    captured = capsys.readouterr()
    assert captured.err == ""
    assert captured.out == (
        f"Bundle complete! 1 files, {lines} lines, "
        f"~{tokens:,} tokens -> {OUTPUT_NAME}\n"
    )


@pytest.mark.parametrize("source_state", ["file", "empty", "test", "tests"])
def test_main_rejects_unusable_sources_and_removes_stale_bundle(
    unit_repo, bundler, capsys, source_state
):
    """Invalid sources, including an all-test tree, delete an earlier run's bundle."""
    source = unit_repo / "scripts"
    if source_state == "file":
        source.rmdir()
        source.write_text("not a directory", encoding="utf-8")
        expected_error = f"ERROR: source directory not found: {source}\n"
    else:
        if source_state != "empty":
            test_dir = source / "nested" / source_state
            test_dir.mkdir(parents=True)
            (test_dir / "only.gd").write_text("# test code\n", encoding="utf-8")
        expected_error = f"ERROR: no .gd files found under {source}\n"
    (unit_repo / OUTPUT_NAME).write_bytes(b"previous bundle\n")

    assert bundler.main() == 1

    assert not (unit_repo / OUTPUT_NAME).exists()
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err == expected_error


def test_symlinked_file_is_skipped_and_reported(tmp_path):
    """A .gd symlink (e.g. to a file outside the repo) is never read into the bundle."""
    outside = tmp_path / "outside.gd"
    outside.write_text("# SECRET outside repo\n", encoding="utf-8")
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/a.gd": "# a\n"})
    make_symlink(root / "scripts" / "core" / "link.gd", outside)

    result = run_bundler(root)
    assert result.returncode == 0

    bundle = read_bundle(root)
    assert bundled_paths(bundle) == ["scripts/core/a.gd"]
    assert "SECRET" not in bundle
    assert "skipping symlink scripts/core/link.gd" in result.stderr


def test_symlinked_directory_is_reported(tmp_path):
    """Files behind a directory symlink are skipped with a warning, not silently."""
    outside_dir = tmp_path / "outside_dir"
    outside_dir.mkdir()
    (outside_dir / "b.gd").write_text("# b\n", encoding="utf-8")
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/a.gd": "# a\n"})
    make_symlink(root / "scripts" / "linked", outside_dir, is_dir=True)

    result = run_bundler(root)
    assert result.returncode == 0
    assert bundled_paths(read_bundle(root)) == ["scripts/core/a.gd"]
    assert "skipping symlink scripts/linked" in result.stderr


def test_output_symlink_is_replaced_not_followed(tmp_path):
    """A symlink at the output path is replaced; the file it pointed to is untouched."""
    victim = tmp_path / "victim.txt"
    victim.write_text("do not overwrite\n", encoding="utf-8")
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/a.gd": "# a\n"})
    make_symlink(root / OUTPUT_NAME, victim)

    assert run_bundler(root).returncode == 0
    assert victim.read_text(encoding="utf-8") == "do not overwrite\n"
    assert not (root / OUTPUT_NAME).is_symlink()
    assert bundled_paths(read_bundle(root)) == ["scripts/core/a.gd"]


def test_no_temp_files_left_behind(tmp_path):
    """The atomic write leaves only the final bundle in the repo root."""
    root = make_fake_repo(tmp_path / "repo", {"scripts/core/a.gd": "# a\n"})
    assert run_bundler(root).returncode == 0
    assert not list(root.glob(f".{OUTPUT_NAME}.*.tmp"))


@pytest.mark.skipif(shutil.which("git") is None, reason="git not installed")
def test_inherited_git_dir_does_not_leak_into_fake_repo(tmp_path, monkeypatch, bundler):
    """A GIT_DIR exported by a git hook must not redirect the helpers or the bundler."""
    other = tmp_path / "other"
    other.mkdir()
    git(other, "init", "-q")  # stands in for the developer's real repo
    root = make_fake_repo(tmp_path / "repo", {"scripts/a.gd": "# a\n"})
    git(root, "init", "-q")

    # Simulate running inside a hook of the "other" repo, then re-apply isolation.
    monkeypatch.setenv("GIT_DIR", str(other / ".git"))
    monkeypatch.setenv("GIT_WORK_TREE", str(other))
    assert "GIT_DIR" not in git_env(root)
    monkeypatch.delenv("GIT_DIR")
    monkeypatch.delenv("GIT_WORK_TREE")

    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "init")
    assert bundler.get_commit_sha(root) == git(root, "rev-parse", "HEAD")
    # The other repo never received a commit.
    log = subprocess.run(
        ["git", "log", "--oneline"],
        cwd=str(other),
        env=git_env(other),
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    assert log.returncode != 0 or log.stdout.strip() == ""


def test_git_calls_have_a_timeout_and_clean_env(tmp_path, monkeypatch, bundler):
    """Both git calls pass a finite timeout and drop repository-override variables."""
    monkeypatch.setenv("GIT_DIR", "/somewhere/else/.git")
    monkeypatch.setenv("GIT_INDEX_FILE", "/somewhere/else/.git/index")
    run = Mock(
        return_value=subprocess.CompletedProcess([], 0, stdout=f"{tmp_path}\nabc123\n")
    )
    monkeypatch.setattr(bundler.subprocess, "run", run)
    monkeypatch.setattr(bundler.shutil, "which", lambda name: "/usr/bin/git")

    bundler.get_commit_sha(tmp_path)

    assert run.call_count == 2
    for call in run.call_args_list:
        assert call.kwargs["timeout"] == bundler.GIT_TIMEOUT_SECONDS
        assert "GIT_DIR" not in call.kwargs["env"]
        assert "GIT_INDEX_FILE" not in call.kwargs["env"]


@pytest.mark.skipif(shutil.which("git") is None, reason="git not installed")
def test_bundler_ignores_inherited_git_dir(tmp_path):
    """With GIT_DIR pointing at another repo, the header still names the fake repo."""
    other = tmp_path / "other"
    other.mkdir()
    git(other, "init", "-q")
    (other / "x.txt").write_text("x\n", encoding="utf-8")
    git(other, "add", "-A")
    git(other, "commit", "-q", "-m", "other")
    root = make_fake_repo(tmp_path / "repo", {"scripts/a.gd": "# a\n"})
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "init")
    sha = git(root, "rev-parse", "HEAD")

    env = git_env(root)
    env["GIT_DIR"] = str(other / ".git")
    env["GIT_WORK_TREE"] = str(other)
    result = subprocess.run(
        [sys.executable, str(root / "workspace" / BUNDLER_SCRIPT.name)],
        env=env,
        cwd=str(root),
        capture_output=True,
        text=True,
        timeout=10,
        encoding="utf-8",
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert f"Commit: {sha}\n" in read_bundle(root)


def test_symlinked_scripts_root_is_rejected(tmp_path):
    """scripts/ itself linking outside the repo is refused, not bundled."""
    outside_dir = tmp_path / "outside_src"
    outside_dir.mkdir()
    (outside_dir / "secret.gd").write_text("# SECRET\n", encoding="utf-8")
    root = make_fake_repo(tmp_path / "repo", {OUTPUT_NAME: "stale bundle\n"})
    make_symlink(root / "scripts", outside_dir, is_dir=True)

    result = run_bundler(root)

    assert result.returncode == 1
    assert "source directory is a symlink" in result.stderr
    assert not (root / OUTPUT_NAME).exists()


@pytest.mark.skipif(shutil.which("git") is None, reason="git not installed")
def test_copy_inside_another_repo_reports_unknown_commit(tmp_path):
    """A project copy without its own .git must not borrow the enclosing repo's SHA."""
    outer = tmp_path / "outer"
    outer.mkdir()
    git(outer, "init", "-q")
    (outer / "x.txt").write_text("x\n", encoding="utf-8")
    git(outer, "add", "-A")
    git(outer, "commit", "-q", "-m", "outer")
    root = make_fake_repo(outer / "copy", {"scripts/a.gd": "# a\n"})

    # Ceiling above 'outer', so git can discover the enclosing repository.
    result = subprocess.run(
        [sys.executable, str(root / "workspace" / BUNDLER_SCRIPT.name)],
        env=git_env(outer),
        cwd=str(root),
        capture_output=True,
        text=True,
        timeout=10,
        encoding="utf-8",
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert "Commit: unknown\n" in read_bundle(root)


def test_content_digest_identifies_exact_code(tmp_path):
    """Different edits give different digests; identical code gives the same one."""

    prefix = "Content SHA-256: "

    def digest_for(content: str, name: str) -> str:
        """Bundle a one-file fake repo and return the digest from its header."""
        root = make_fake_repo(tmp_path / name, {"scripts/a.gd": content})
        assert run_bundler(root).returncode == 0
        header = read_bundle(root).split("=" * 60, 1)[0]
        matches = [x for x in header.splitlines() if x.startswith(prefix)]
        assert len(matches) == 1, f"expected one '{prefix}' line in:\n{header}"
        return matches[0].removeprefix(prefix)

    first = digest_for("var x = 1\n", "one")
    assert digest_for("var x = 1\n", "same") == first
    assert digest_for("var x = 2\n", "edited") != first
    assert len(first) == 64
