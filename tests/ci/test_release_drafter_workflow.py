# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Regression coverage for the pull request events that refresh release drafts."""

from pathlib import Path

import yaml


def test_release_drafter_refreshes_for_open_reopen_and_new_commits_only():
    """Editing pull request metadata alone must not trigger a draft update."""
    path = Path(".github/workflows/release_drafter_pr.yml")
    # BaseLoader preserves GitHub Actions' unquoted "on" as a string.
    workflow = yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    assert set(workflow["on"]["pull_request"]["types"]) == {
        "opened",
        "reopened",
        "synchronize",
    }
