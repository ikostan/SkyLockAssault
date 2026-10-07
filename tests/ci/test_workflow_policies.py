# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# \tests\ci\test_workflow_policies.py

"""
Policy checks for GitHub Actions workflow files.

These tests parse every workflow under ``.github/workflows/`` and enforce rules
that keep CI failures cheap and obvious, rather than letting a job hang until
its runner timeout kills it.

Background: the ``azure.archive.ubuntu.com`` mirror stopped responding, so
``apt-get`` stalled for 15-20 minutes in both the gdUnit4 and the browser test
workflows. Nothing in the repository caused that, and no test can prevent it.
These tests instead guarantee that every job and every network-bound step has
an explicit time limit, so a future outage fails within minutes at a clearly
named step.
"""

import pathlib
import re

import pytest
import yaml

WORKFLOWS = sorted(pathlib.Path(".github/workflows").glob("*.yml"))
"""All workflow files under test, sorted for stable test ordering."""

NETWORK_CMD = re.compile(
    r"""
    \b(
        apt-get                               # any apt-get call, even with $OPTS before the verb
      | apt \s+ (?:update|install|upgrade)
      | pip3? \s+ install                     # also matches `python -m pip install`
      | npm \s+ (?:ci|i|install)
      | playwright \s+ install
      | wget
    )\b
    """,
    re.VERBOSE,
)
"""Commands that download from external hosts and can hang on a slow mirror.

Covers apt/apt-get, pip/pip3 (including ``python -m pip``), npm install/ci,
``playwright install`` and ``wget``. ``curl`` is deliberately excluded: its
only use is the localhost readiness loop in ``browser_test.yml``, which
already bounds itself to 20 attempts.
"""


def _jobs():
    """
    Yield one pytest parameter per job across all workflow files.

    Yields:
        pytest.param: A ``(workflow_name, job_id, job)`` triple, where ``job``
        is the parsed job mapping. Each param gets a readable test id in the
        form ``<workflow>.yml:<job_id>``.
    """
    for wf in WORKFLOWS:
        data = yaml.safe_load(wf.read_text()) or {}
        for job_id, job in (data.get("jobs") or {}).items():
            yield pytest.param(wf.name, job_id, job, id=f"{wf.name}:{job_id}")


@pytest.mark.parametrize(
    "cmd",
    [
        "sudo apt-get update",
        "sudo apt-get $APT_OPTS install -y xvfb",
        "sudo apt install -y xvfb",
        "pip install -r requirements.txt",
        "pip3 install pyyaml",
        "python -m pip install --upgrade pip",
        "python3 -m pip install -r requirements.txt",
        "npm ci",
        "npm install v8-to-istanbul nyc",
        "playwright install --with-deps chromium",
        'wget -q "$URL" -O gdunit4.zip',
    ],
)
def test_network_cmd_matches_install_commands(cmd):
    """The matcher must flag every network-bound command the policy claims to cover."""
    assert NETWORK_CMD.search(cmd), f"not detected as network-bound: {cmd!r}"


@pytest.mark.parametrize(
    "cmd",
    [
        "curl -f http://localhost:8080/index.html",
        "pip freeze",
        "npm run build",
        "cat /etc/apt/apt-mirrors.txt",
    ],
)
def test_network_cmd_ignores_local_commands(cmd):
    """The matcher must not flag local-only commands or paths that merely contain 'apt'."""
    assert not NETWORK_CMD.search(cmd), f"falsely detected as network-bound: {cmd!r}"


@pytest.mark.parametrize("wf, job_id, job", list(_jobs()))
def test_job_has_timeout(wf, job_id, job):
    """
    Every job must declare a job-level ``timeout-minutes``.

    Without one, GitHub's default of 360 minutes applies, so a hung step can
    hold a runner for six hours. Jobs that call a reusable workflow
    (``uses:``) are skipped, because GitHub doesn't allow ``timeout-minutes``
    on them; the called workflow's own jobs carry the timeout and are checked
    when that file is parsed.
    """
    if "uses" in job:
        pytest.skip("reusable workflow caller")
    assert "timeout-minutes" in job, f"{wf}:{job_id} has no job-level timeout"


@pytest.mark.parametrize("wf, job_id, job", list(_jobs()))
def test_network_steps_have_step_timeout(wf, job_id, job):
    """
    Every step that downloads from the network needs its own timeout.

    A job-level timeout alone isn't enough. When an install step hangs, it
    burns the whole job budget, and the failure surfaces as a generic
    "job exceeded maximum execution time" error instead of pointing at the
    step that stalled. A short step-level ``timeout-minutes`` makes the
    failing step obvious and leaves room for ``always()`` cleanup and
    report steps to run.
    """
    for step in job.get("steps", []):
        if NETWORK_CMD.search(step.get("run", "")):
            name = step.get("name", "<unnamed>")
            assert "timeout-minutes" in step, (
                f"{wf}:{job_id} step '{name}' touches the network "
                "but has no step-level timeout-minutes"
            )
