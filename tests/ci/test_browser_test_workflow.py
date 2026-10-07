# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_browser_test_workflow.py
"""Structural tests for .github/workflows/browser_test.yml (PR #872, Issue #1004).

Validates the failure-only diagnostics upload step, the pre-test artifact
cleanup step, and the additional pytest flags added to the sharded test run.
Issue #1004 adds guards for server readiness, failure-path reporting,
SHA pinning, and the Node.js version used for coverage conversion.
"""

import re
import subprocess
from pathlib import Path
from typing import Any

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = PROJECT_ROOT / ".github" / "workflows" / "browser_test.yml"
SHA_PINNED = re.compile(r"^[\w.-]+/[\w./-]+@[0-9a-f]{40}$")


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
    # #1004: the start step only launches the server; a probe here would fail the
    # step under bash -e before the dedicated wait step could retry.
    assert "curl" not in script
    assert "sleep" not in script


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
    assert step["uses"].startswith("actions/upload-artifact@")
    assert SHA_PINNED.match(step["uses"])
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


# --- Issue #1004 regression guards ---


def test_wait_step_tracks_readiness_explicitly(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """A server that answers on the final attempt must not fail the job."""
    script = _find_step(test_shard_steps, "Wait For WEB Server Response")["run"]

    assert "ready=true" in script
    assert "$i -eq 20" not in script
    assert "curl -I http://localhost:8080/index.html" in script


def test_test_report_runs_even_when_tests_fail(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """The xmllint summary is most useful on failed runs, so it must not skip."""
    assert _find_step(test_shard_steps, "Test Report")["if"] == "always()"


def test_coverage_conversion_runs_for_failed_tests(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """LCOV exists for the always()/!cancelled() upload steps on failed runs."""
    for name in (
        "List Coverage Reports",
        "Set up Node.js for Coverage Conversion",
        "Install Conversion Tools",
        "Convert V8 to LCOV",
    ):
        assert _find_step(test_shard_steps, name)["if"] == "!cancelled()"


def test_all_actions_are_sha_pinned(workflow: dict[str, Any]) -> None:
    """Every action in every job is pinned to a full 40-character commit SHA."""
    for job_name, job in workflow["jobs"].items():
        for step in job["steps"]:
            if "uses" in step:
                assert SHA_PINNED.match(step["uses"]), f"{job_name}: {step['uses']}"


def test_coverage_node_version_is_not_end_of_life(
    test_shard_steps: list[dict[str, Any]],
) -> None:
    """Node.js 20 reached end-of-life in April 2026."""
    step = _find_step(test_shard_steps, "Set up Node.js for Coverage Conversion")

    assert str(step["with"]["node-version"]) != "20"


@pytest.mark.parametrize(
    ("ready_on", "exit_code", "attempts", "head_requests"),
    [(1, 0, 1, 1), (20, 0, 20, 1), (21, 1, 20, 0)],
    ids=["immediately-ready", "ready-on-last-attempt", "never-ready"],
)
def test_wait_step_obeys_retry_boundary(
    test_shard_steps: list[dict[str, Any]],
    ready_on: int,
    exit_code: int,
    attempts: int,
    head_requests: int,
) -> None:
    """Execute the actual wait loop with deterministic HTTP and sleep substitutes."""
    script = _find_step(test_shard_steps, "Wait For WEB Server Response")["run"]
    harness = r"""
ready_on="$1"
probes=0
headers=0
curl() {
  if [[ "$1" == "-I" ]]; then
    headers=$((headers + 1))
    return 0
  fi
  probes=$((probes + 1))
  [[ "$probes" -ge "$ready_on" ]]
}
sleep() { :; }
trap 'echo "probes=$probes headers=$headers"' EXIT
"""
    result = subprocess.run(
        [
            "bash",
            "--noprofile",
            "--norc",
            "-eo",
            "pipefail",
            "-c",
            harness + script,
            "readiness-test",
            str(ready_on),
        ],
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )

    assert result.returncode == exit_code, result.stdout + result.stderr
    assert f"probes={attempts} headers={head_requests}" in result.stdout
    if exit_code:
        assert "did not respond after 20 attempts" in result.stderr
    else:
        assert f"Server ready (attempt {attempts})" in result.stdout
