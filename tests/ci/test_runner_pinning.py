# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_runner_pinning.py

"""
Regression guards for runner pinning and the Ubuntu 26.04 canary (#1008).

GitHub moves ``ubuntu-latest`` from 24.04 to 26.04 between Oct 19 and
Nov 19, 2026. Every workflow is pinned to ``ubuntu-24.04``; the reusable test
workflows take a ``runner`` input so the advisory ``ubuntu_26_canary.yml`` can
run them on ``ubuntu-26.04``. These tests keep that arrangement intact.

Delete this file together with the canary once the migration lands (or reduce
it to the ``ubuntu-latest`` guard only).
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
CANARY = "ubuntu_26_canary.yml"
PIPELINES = ("lint_test_on_pull.yml", "lint_test_deploy.yml")
RUNNER_EXPR = "${{ inputs.runner }}"


def _load(name: str) -> dict[str, Any]:
    with open(WORKFLOW_DIR / name, encoding="utf-8") as f:
        return yaml.safe_load(f)


def _triggers(workflow: dict[str, Any]) -> dict[str, Any]:
    # PyYAML parses the bare `on:` key as boolean True.
    return workflow.get("on", workflow.get(True)) or {}


def test_workflow_files_found() -> None:
    assert WORKFLOW_FILES, f"No workflow files found under {WORKFLOW_DIR}"


@pytest.mark.parametrize("path", WORKFLOW_FILES, ids=lambda p: p.name)
def test_no_job_uses_ubuntu_latest(path: pathlib.Path) -> None:
    workflow = _load(path.name)
    offenders = [
        job_id
        for job_id, job in (workflow.get("jobs") or {}).items()
        if "ubuntu-latest" in str(job.get("runs-on", ""))
    ]
    assert not offenders, f"{path.name}: jobs use ubuntu-latest: {offenders}"


@pytest.mark.parametrize("name", REUSABLE)
def test_reusable_workflow_defines_runner_input(name: str) -> None:
    inputs = _triggers(_load(name))["workflow_call"].get("inputs") or {}
    assert "runner" in inputs, f"{name}: missing workflow_call input 'runner'"
    assert inputs["runner"].get("type") == "string"
    assert inputs["runner"].get("default") == "ubuntu-24.04"


@pytest.mark.parametrize("name", REUSABLE)
def test_reusable_workflow_jobs_use_runner_input(name: str) -> None:
    jobs = _load(name)["jobs"]
    wrong = {
        jid: j.get("runs-on")
        for jid, j in jobs.items()
        if j.get("runs-on") != RUNNER_EXPR
    }
    assert not wrong, f"{name}: jobs not using {RUNNER_EXPR}: {wrong}"


def test_browser_workflow_coverage_upload_is_optional() -> None:
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


def test_canary_calls_exactly_the_reusable_workflows_on_26_04() -> None:
    jobs = _load(CANARY)["jobs"]
    called = sorted(pathlib.Path(job["uses"]).name for job in jobs.values())
    assert called == sorted(REUSABLE)
    for job_id, job in jobs.items():
        assert (job.get("with") or {}).get("runner") == "ubuntu-26.04", job_id


def test_canary_jobs_are_independent() -> None:
    jobs = _load(CANARY)["jobs"]
    dependent = [job_id for job_id, job in jobs.items() if "needs" in job]
    assert not dependent, f"Canary jobs must not use needs: {dependent}"


def test_canary_does_not_upload_coverage() -> None:
    jobs = _load(CANARY)["jobs"]
    browser = [j for j in jobs.values() if j["uses"].endswith("/browser_test.yml")]
    assert len(browser) == 1
    assert browser[0]["with"].get("upload_coverage") is False


@pytest.mark.parametrize("name", PIPELINES)
def test_pipelines_do_not_reference_canary(name: str) -> None:
    text = (WORKFLOW_DIR / name).read_text(encoding="utf-8")
    assert CANARY not in text


@pytest.mark.parametrize("name", PIPELINES)
def test_pipelines_pass_no_runner(name: str) -> None:
    for job_id, job in _load(name)["jobs"].items():
        assert "runner" not in (job.get("with") or {}), f"{name}:{job_id}"
