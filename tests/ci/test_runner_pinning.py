# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_runner_pinning.py

"""
Regression guards for runner pinning and the Ubuntu 26.04 test run (#1008).

GitHub moves ``ubuntu-latest`` from 24.04 to 26.04 between Oct 19 and
Nov 19, 2026. Every workflow is pinned to ``ubuntu-24.04``. The reusable test
workflows take a ``runner`` input, ``test_suite.yml`` runs all of them for one
runner, and the main pipeline calls the suite twice: on 24.04 (gating the scans
and the deploy) and on 26.04 (advisory, nothing depends on it). These tests
keep that arrangement intact.

After the migration to 26.04, drop the 26.04 call and reduce this file to the
``ubuntu-latest`` guard.
"""

import pathlib
from typing import Any

import pytest
import yaml

WORKFLOW_DIR = pathlib.Path(".github/workflows")
WORKFLOW_FILES = sorted(WORKFLOW_DIR.glob("*.yml"))
REUSABLE = (
    "gdunit4_tests.yml",
    "gut_tests.yml",
    "test_ci_scripts.yml",
    "browser_test.yml",
)
WITH_ARTIFACTS = ("gdunit4_tests.yml", "gut_tests.yml", "browser_test.yml")
SUITE = "test_suite.yml"
MAIN = "lint_test_deploy.yml"
PR = "lint_test_on_pull.yml"
RUNNER_EXPR = "${{ inputs.runner }}"
GATED_BY_TESTS = ("codeql", "snyk", "trivy")


def _load(name: str) -> dict[str, Any]:
    """Parse a workflow file from .github/workflows/ and return it as a dict."""
    with open(WORKFLOW_DIR / name, encoding="utf-8") as f:
        return yaml.safe_load(f)


def _triggers(workflow: dict[str, Any]) -> dict[str, Any]:
    """Return the workflow's `on:` block, which PyYAML may store under key True."""
    # PyYAML parses the bare `on:` key as boolean True.
    return workflow.get("on", workflow.get(True)) or {}


def _needs(job: dict[str, Any]) -> list[str]:
    """Return a job's `needs:` as a list, whether written as a string or a list."""
    needs = job.get("needs", [])
    return [needs] if isinstance(needs, str) else list(needs)


def _calls(name: str, target: str) -> dict[str, dict[str, Any]]:
    """Return the jobs in workflow `name` that call the reusable workflow `target`."""
    return {
        job_id: job
        for job_id, job in _load(name)["jobs"].items()
        if pathlib.Path(job.get("uses", "")).name == target
    }


def test_workflow_files_found() -> None:
    """Verify the glob finds workflow files, so the parametrized tests are not empty."""
    assert WORKFLOW_FILES, f"No workflow files found under {WORKFLOW_DIR}"


@pytest.mark.parametrize("path", WORKFLOW_FILES, ids=lambda p: p.name)
def test_no_job_uses_ubuntu_latest(path: pathlib.Path) -> None:
    """Verify no job runs on ubuntu-latest, which GitHub is moving to 26.04."""
    workflow = _load(path.name)
    offenders = [
        job_id
        for job_id, job in (workflow.get("jobs") or {}).items()
        if "ubuntu-latest" in str(job.get("runs-on", ""))
    ]
    assert not offenders, f"{path.name}: jobs use ubuntu-latest: {offenders}"


@pytest.mark.parametrize("name", REUSABLE + (SUITE,))
def test_workflow_defines_runner_input(name: str) -> None:
    """Verify the workflow has a string `runner` input that defaults to ubuntu-24.04."""
    inputs = _triggers(_load(name))["workflow_call"].get("inputs") or {}
    assert "runner" in inputs, f"{name}: missing workflow_call input 'runner'"
    assert inputs["runner"].get("type") == "string"
    assert inputs["runner"].get("default") == "ubuntu-24.04"


@pytest.mark.parametrize("name", REUSABLE)
def test_reusable_workflow_jobs_use_runner_input(name: str) -> None:
    """Verify every job in a reusable test workflow runs on `inputs.runner`."""
    jobs = _load(name)["jobs"]
    wrong = {
        jid: j.get("runs-on")
        for jid, j in jobs.items()
        if j.get("runs-on") != RUNNER_EXPR
    }
    assert not wrong, f"{name}: jobs not using {RUNNER_EXPR}: {wrong}"


def test_browser_workflow_coverage_upload_is_optional() -> None:
    """Verify `upload_coverage` can turn off the Codecov upload (default on)."""
    workflow = _load("browser_test.yml")
    inputs = _triggers(workflow)["workflow_call"]["inputs"]
    assert inputs["upload_coverage"].get("type") == "boolean"
    assert inputs["upload_coverage"].get("default") is True
    steps = [
        step
        for job in workflow["jobs"].values()
        for step in job.get("steps", [])
        if step.get("name") == "Upload Coverage to Codecov"
    ]
    assert steps, "browser_test.yml: Codecov upload step not found"
    for step in steps:
        assert "inputs.upload_coverage" in str(step.get("if", ""))


@pytest.mark.parametrize("name", WITH_ARTIFACTS)
def test_artifact_names_are_unique_per_runner(name: str) -> None:
    """Verify artifact names include RUNNER_SUFFIX, so 24.04 and 26.04 don't clash."""
    workflow = _load(name)
    suffix = (workflow.get("env") or {}).get("RUNNER_SUFFIX", "")
    assert "inputs.runner" in suffix, f"{name}: RUNNER_SUFFIX must use the runner"
    names = [
        step["with"]["name"]
        for job in workflow["jobs"].values()
        for step in job.get("steps", [])
        if "-artifact@" in str(step.get("uses", ""))
    ]
    assert names, f"{name}: no artifact steps found"
    missing = [n for n in names if "env.RUNNER_SUFFIX" not in n]
    assert not missing, f"{name}: artifact names without suffix: {missing}"


def test_playwright_cache_is_per_runner() -> None:
    """Verify the Playwright cache key includes RUNNER_SUFFIX."""
    # A shared key would let 26.04 restore the 24.04 cache and skip
    # `playwright install --with-deps`, the step the 26.04 run must exercise.
    keys = [
        step["with"]["key"]
        for job in _load("browser_test.yml")["jobs"].values()
        for step in job.get("steps", [])
        if step.get("id") == "playwright-cache"
    ]
    assert keys, "browser_test.yml: Playwright cache step not found"
    assert all("env.RUNNER_SUFFIX" in key for key in keys)


def test_suite_calls_every_reusable_workflow_with_its_runner() -> None:
    """Verify test_suite.yml calls all four test workflows and passes its runner."""
    jobs = _load(SUITE)["jobs"]
    called = sorted(pathlib.Path(job["uses"]).name for job in jobs.values())
    assert called == sorted(REUSABLE)
    for job_id, job in jobs.items():
        assert (job.get("with") or {}).get("runner") == RUNNER_EXPR, job_id


def test_suite_forwards_upload_coverage() -> None:
    """Verify test_suite.yml passes `upload_coverage` through to the browser tests."""
    browser = _calls(SUITE, "browser_test.yml")
    assert len(browser) == 1
    (job,) = browser.values()
    assert job["with"].get("upload_coverage") == "${{ inputs.upload_coverage }}"


def test_main_pipeline_runs_suite_on_24_and_26() -> None:
    """Verify the main pipeline calls test_suite.yml once on 24.04 and once on 26.04."""
    calls = _calls(MAIN, SUITE)
    runners = sorted(
        (job.get("with") or {}).get("runner", "ubuntu-24.04") for job in calls.values()
    )
    assert runners == ["ubuntu-24.04", "ubuntu-26.04"], runners


def test_main_pipeline_26_04_run_is_advisory() -> None:
    """Verify the 26.04 run uploads no coverage and no job depends on it."""
    jobs = _load(MAIN)["jobs"]
    canary = [
        job_id
        for job_id, job in _calls(MAIN, SUITE).items()
        if (job.get("with") or {}).get("runner") == "ubuntu-26.04"
    ]
    assert len(canary) == 1
    (canary_id,) = canary
    assert jobs[canary_id]["with"].get("upload_coverage") is False
    blocked = [job_id for job_id, job in jobs.items() if canary_id in _needs(job)]
    assert not blocked, f"Jobs must not need the 26.04 run: {blocked}"


def test_main_pipeline_scans_wait_for_24_04_tests() -> None:
    """Verify CodeQL, Snyk and Trivy wait for the 24.04 test run."""
    jobs = _load(MAIN)["jobs"]
    gate = [
        job_id
        for job_id, job in _calls(MAIN, SUITE).items()
        if "runner" not in (job.get("with") or {})
    ]
    assert len(gate) == 1
    for job_id in GATED_BY_TESTS:
        assert gate[0] in _needs(jobs[job_id]), f"{job_id} must need {gate[0]}"


def test_pr_pipeline_stays_on_24_04() -> None:
    """Verify the PR pipeline passes no `runner`, so PRs stay on ubuntu-24.04."""
    for job_id, job in _load(PR)["jobs"].items():
        assert "runner" not in (job.get("with") or {}), f"{PR}:{job_id}"
