# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Regression coverage for the pull request events that refresh release drafts."""

from pathlib import Path

import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = PROJECT_ROOT / ".github" / "workflows" / "release_drafter_pr.yml"


def test_release_drafter_refreshes_for_open_reopen_and_new_commits_only():
    """Editing pull request metadata alone must not trigger a draft update."""
    # BaseLoader preserves GitHub Actions' unquoted "on" as a string.
    workflow = yaml.load(WORKFLOW_PATH.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    assert set(workflow["on"]["pull_request"]["types"]) == {
        "opened",
        "reopened",
        "synchronize",
    }
