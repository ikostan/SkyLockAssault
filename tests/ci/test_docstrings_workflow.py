# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_docstrings_workflow.py
"""Regression tests for PR #1007's documentation automation scope guard."""

import subprocess
from pathlib import Path

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = PROJECT_ROOT / ".github/workflows/bi_weekly_gd_docstrings.yml"


@pytest.fixture(scope="module")
def workflow():
    """Parse bi_weekly_gd_docstrings.yml once for all tests in this module."""
    return yaml.safe_load(WORKFLOW_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def steps(workflow):
    """Map step names to step definitions for the sync-docstrings job."""
    return {
        step.get("name"): step for step in workflow["jobs"]["sync-docstrings"]["steps"]
    }


def git(repo, *args):
    """Run a git command in ``repo`` and fail the test on a non-zero exit."""
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    )


@pytest.fixture
def isolated_repo(tmp_path):
    """Reuse existing history without creating commits or changing the task checkout."""
    repo = tmp_path / "repo"
    git(
        PROJECT_ROOT,
        "clone",
        "--quiet",
        "--shared",
        "--no-checkout",
        str(PROJECT_ROOT),
        str(repo),
    )
    git(repo, "sparse-checkout", "set", "scripts")
    git(repo, "checkout", "--quiet", "HEAD")
    return repo


def run_scope_check(repo, steps):
    """Run the workflow's "Final Documentation Scope Check" script inside ``repo``."""
    return subprocess.run(
        [
            "bash",
            "--noprofile",
            "--norc",
            "-eo",
            "pipefail",
            "-c",
            steps["Final Documentation Scope Check"]["run"],
        ],
        cwd=repo,
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )


@pytest.mark.parametrize(
    "subtree", ["core", "entities", "managers", "resources", "system", "ui"]
)
def test_scope_guard_accepts_existing_scripts_in_each_allowed_subtree(
    isolated_repo, steps, subtree
):
    """A docs-only edit to an existing script in each allowed subtree passes."""
    script = next((isolated_repo / "scripts" / subtree).rglob("*.gd"), None)
    if script is None:
        pytest.fail(f"No .gd file found under scripts/{subtree}")
    with script.open("a", encoding="utf-8") as stream:
        stream.write("\n## Additional documentation.\n")

    result = run_scope_check(isolated_repo, steps)

    assert result.returncode == 0, result.stdout + result.stderr
    assert (
        script.relative_to(isolated_repo).as_posix()
        in git(isolated_repo, "diff", "--cached", "--name-only").stdout
    )


def test_scope_guard_accepts_no_changes(isolated_repo, steps):
    """A run where the generator changed nothing passes the scope check."""
    result = run_scope_check(isolated_repo, steps)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize("staged", [False, True], ids=["untracked", "already-staged"])
def test_scope_guard_rejects_new_scripts_even_inside_allowed_subtree(
    isolated_repo, steps, staged
):
    """New files are rejected even in an allowed subtree, staged or not."""
    script = isolated_repo / "scripts/managers/unexpected.gd"
    script.write_text("extends Node\n", encoding="utf-8")
    if staged:
        git(isolated_repo, "add", str(script))

    result = run_scope_check(isolated_repo, steps)

    assert result.returncode == 1
    assert "attempted to create files" in result.stdout
    assert "scripts/managers/unexpected.gd" in result.stdout


def test_scope_guard_rejects_deleted_production_script(isolated_repo, steps):
    """Deleting a production script fails the scope check."""
    script = isolated_repo / "scripts/managers/audio_manager.gd"
    script.unlink()

    result = run_scope_check(isolated_repo, steps)

    assert result.returncode == 1
    assert "attempted to delete files" in result.stdout
    assert "scripts/managers/audio_manager.gd" in result.stdout


def test_scope_guard_rejects_tracked_changes_outside_production_scripts(
    isolated_repo, steps
):
    """Edits to tracked files outside the six production subtrees are rejected."""
    with (isolated_repo / "README.md").open("a", encoding="utf-8") as stream:
        stream.write("\nUnexpected edit.\n")

    result = run_scope_check(isolated_repo, steps)

    assert result.returncode == 1
    assert "outside production scope" in result.stdout
    assert "README.md" in result.stdout


def test_scope_guard_checks_staged_whitespace(isolated_repo, steps):
    """`git diff --cached --check` catches trailing whitespace in staged edits."""
    script = isolated_repo / "scripts/managers/audio_manager.gd"
    with script.open("a", encoding="utf-8") as stream:
        stream.write("\n## Trailing whitespace.  \n")

    result = run_scope_check(isolated_repo, steps)

    assert result.returncode != 0
    assert "trailing whitespace" in result.stdout + result.stderr


def test_sync_serializes_runs_and_bounds_execution(workflow):
    """Runs are queued, not cancelled, and the job has a 30-minute timeout."""
    assert workflow["concurrency"] == {
        "group": "gdscript-docs-sync",
        "cancel-in-progress": False,
    }
    assert workflow["jobs"]["sync-docstrings"]["timeout-minutes"] == 30


def test_optional_app_authentication_has_fallback_and_limited_permissions(steps):
    """The App token is optional, narrowly scoped, and falls back to GITHUB_TOKEN."""
    token_step = steps["Generate GitHub App Token"]
    assert token_step["if"] == "${{ vars.DOCS_BOT_CLIENT_ID != '' }}"
    assert token_step["id"] == "app-token"
    assert token_step["with"] == {
        "client-id": "${{ vars.DOCS_BOT_CLIENT_ID }}",
        "private-key": "${{ secrets.DOCS_BOT_PRIVATE_KEY }}",
        "permission-contents": "write",
        "permission-pull-requests": "write",
    }
    assert steps["Create or Update Pull Request"]["with"]["token"] == (
        "${{ steps.app-token.outputs.token || secrets.GITHUB_TOKEN }}"
    )
