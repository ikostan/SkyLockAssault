# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_gdunit4_workflow.py
"""Structural tests for .github/workflows/gdunit4_tests.yml (Issue #1003).

Locks in the post-cleanup shape: the strip step delegates to the tested script,
the job requests no unused permissions, and every action is SHA-pinned.
"""

import re
from pathlib import Path
from typing import Any

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = PROJECT_ROOT / ".github" / "workflows" / "gdunit4_tests.yml"
STRIP_SCRIPT = ".github/scripts/strip_gdunit4_coverage.py"
SHA_PINNED = re.compile(r"^[\w.-]+/[\w.-]+@[0-9a-f]{40}$")


@pytest.fixture(scope="module")
def unit_test_job() -> dict[str, Any]:
    """Parse the workflow once and return the unit-test job."""
    with open(WORKFLOW_PATH, encoding="utf-8") as f:
        return yaml.safe_load(f)["jobs"]["unit-test"]


def test_strip_step_runs_extracted_script(unit_test_job: dict[str, Any]) -> None:
    """The strip step calls the tested script instead of inline Python."""
    steps = {s.get("name"): s for s in unit_test_job["steps"]}
    step = steps["Strip gdUnit4-coverage From CI Project Config"]

    assert STRIP_SCRIPT in step["run"]
    assert (PROJECT_ROOT / STRIP_SCRIPT).is_file()


def test_job_requests_no_checks_permission(unit_test_job: dict[str, Any]) -> None:
    """No step uses the Checks API, so checks:write must not come back."""
    assert "checks" not in unit_test_job.get("permissions", {})


def test_all_actions_are_sha_pinned(unit_test_job: dict[str, Any]) -> None:
    """Every third-party action is pinned to a full 40-character commit SHA."""
    uses = [s["uses"] for s in unit_test_job["steps"] if "uses" in s]

    assert uses, "expected at least one action step"
    for ref in uses:
        assert SHA_PINNED.match(ref), f"not SHA-pinned: {ref}"
