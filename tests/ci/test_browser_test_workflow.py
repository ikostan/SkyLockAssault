# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_browser_test_workflow.py
"""Structural tests for .github/workflows/browser_test.yml (PR #872).

Validates the failure-only diagnostics upload step, the pre-test artifact
cleanup step, and the additional pytest flags added to the sharded test run.
"""

from pathlib import Path
from typing import Any

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = PROJECT_ROOT / ".github" / "workflows" / "browser_test.yml"


@pytest.fixture(scope="module")
def workflow() -> dict[str, Any]:
    """Parse the browser_test.yml workflow file once for all tests in this module."""
    with open(WORKFLOW_PATH, encoding="utf-8") as f:
        return yaml.safe_load(f)


@pytest.fixture(scope="module")
def test_shard_steps(workflow: dict[str, Any]) -> list[dict[str, Any]]:
    """Return the ordered list of steps for the test-shard job."""
    return workflow["jobs"]["test-shard"]["steps"]


def _find_step(steps: list[dict[str, Any]], name: str) -> dict[str, Any]:
    """Find a step by its 'name' key, failing loudly if it cannot be located."""
    for step in steps:
        if step.get("name") == name:
            return step
    raise AssertionError(f"Step '{name}' not found in workflow steps")


def test_workflow_file_is_valid_yaml(workflow: dict[str, Any]) -> None:
    """Sanity check that the workflow parses to the expected top-level shape."""
    assert "jobs" in workflow
    assert "test-shard" in workflow["jobs"]
    assert "build-web" in workflow["jobs"]


def test_start_server_step_registers_wasm_mime_and_optimized_handler(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """Verify the security-isolated server starts via serve_web_export.py."""
    step = _find_step(test_shard_steps, "Start Security-Isolated HTTP Server")
    script = step["run"]

    assert "python3 .github/scripts/serve_web_export.py 8080" in script
    assert "export/web_thread_off" in script
    assert "curl -I http://localhost:8080/index.html" in script


def test_create_artifacts_directory_step_purges_stale_diagnostics(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """Verify stale trace/screenshot/video artifacts are purged before each run."""
    step = _find_step(test_shard_steps, "Create Artifacts Directory")
    script = step["run"]

    assert "mkdir -p artifacts" in script
    assert "rm -f artifacts/trace_*.zip" in script
    assert "artifacts/failure_*.png" in script
    assert "artifacts/video_*.webm" in script


def test_run_sharded_tests_step_uses_thread_based_timeout_and_live_output(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """Verify the sharded pytest invocation includes the new debugging flags."""
    step = _find_step(test_shard_steps, "Run Sharded Tests")
    script = step["run"]

    assert "-v" in script
    assert "-s" in script
    assert "--capture=no" in script
    assert "--timeout-method=thread" in script
    assert "--junitxml=artifacts/junit.xml" in script


def test_failure_diagnostic_artifacts_upload_only_on_failure(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """Verify diagnostics are uploaded only on failure, scoped and short-lived."""
    step = _find_step(test_shard_steps, "Upload Failure Diagnostic Artifacts")

    assert step["if"] == "failure()"
    assert step["uses"] == "actions/upload-artifact@v7"
    assert step["with"]["name"] == "test-failures-${{ matrix.artifact_suffix }}"
    assert step["with"]["if-no-files-found"] == "ignore"
    assert step["with"]["retention-days"] == 7

    paths = step["with"]["path"]
    assert "artifacts/trace_*.zip" in paths
    assert "artifacts/failure_*.png" in paths
    assert "artifacts/video_*.webm" in paths
    # Coverage JSON must not be swept up into the failure-only diagnostics bundle.
    assert "coverage_*.json" not in paths


def test_old_always_run_screenshot_upload_step_was_removed(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """Regression guard: the old unconditional screenshot/coverage step is gone."""
    names = {step.get("name") for step in test_shard_steps}

    assert "Upload Screenshot and Coverage Artifacts" not in names
    assert "Upload Failure Diagnostic Artifacts" in names


def test_other_always_run_upload_steps_are_unaffected(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """Ensure unrelated always() uploads (metrics/junit/lcov) were left untouched."""
    for name in (
        "Upload LCOV Artifact",
        "Upload Test Report Artifact",
        "Upload Profiling Baseline Artifact (#776)",
    ):
        step = _find_step(test_shard_steps, name)
        assert step["if"] == "always()"
