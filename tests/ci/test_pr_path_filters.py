# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_pr_path_filters.py

"""
Regression guard for the path filters in ``lint_test_on_pull.yml`` (#1018).

Godot test files under ``test/`` are excluded from the web export
(``exclude_filter`` in ``export_presets.cfg``), so a PR that only changes them
must run the GUT and GDUnit4 jobs but skip gdlint, the web export and the
browser shards. That relies on three things staying in place:

* ``gdscript`` excludes ``test/**`` with a ``'!test/**'`` pattern.
* The ``Filter Paths`` step sets ``predicate-quantifier: some-with-excludes``.
  Under the default ``some`` quantifier a ``!`` pattern is just another match,
  so ``'!test/**'`` would match every file outside ``test/`` and turn
  ``gdscript`` on for every PR, docs-only ones included.
* A separate ``godot_tests`` filter feeds only the unit-test jobs.
"""

import pathlib
import re

import pytest
import yaml

WORKFLOW = pathlib.Path(".github/workflows/lint_test_on_pull.yml")
"""The pull-request orchestrator whose path filters are under test."""

QUANTIFIER = "some-with-excludes"
"""The only paths-filter quantifier under which ``!`` patterns exclude files."""

GAME_PATTERNS = {"**/*.gd", "**/*.tscn", "**/*.tres", "project.godot"}
"""Positive ``gdscript`` patterns: changes to these must still trigger every job."""

GODOT_TESTS_TRIGGER = "needs.detect-changes.outputs.godot_tests == 'true'"
"""The exact clause that must enable the unit-test jobs for test-only PRs."""


@pytest.fixture(scope="module")
def workflow():
    """
    Parse the pull-request workflow.

    Returns:
        dict: The parsed workflow mapping.
    """
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def filter_step(workflow):
    """
    Find the ``Filter Paths`` step of the ``detect-changes`` job.

    Args:
        workflow: The parsed workflow mapping.

    Returns:
        dict: The step's ``with:`` mapping.
    """
    steps = workflow["jobs"]["detect-changes"]["steps"]
    matches = [step for step in steps if step.get("id") == "filter"]
    assert len(matches) == 1, "expected exactly one step with id 'filter'"
    return matches[0]["with"]


@pytest.fixture(scope="module")
def filters(filter_step):
    """
    Parse the ``filters:`` block, which is a YAML string inside the step.

    Args:
        filter_step: The ``Filter Paths`` step's ``with:`` mapping.

    Returns:
        dict: Filter name mapped to its list of patterns.
    """
    return yaml.safe_load(filter_step["filters"])


def _job_if(workflow, job_id):
    """
    Return a job's ``if:`` expression as a string.

    Args:
        workflow: The parsed workflow mapping.
        job_id: The job key under ``jobs:``.

    Returns:
        str: The ``if:`` expression with whitespace collapsed to single spaces,
        or an empty string if the job has none.
    """
    return " ".join(str(workflow["jobs"][job_id].get("if", "")).split())


def test_filter_step_uses_some_with_excludes(filter_step):
    """The quantifier must allow ``!`` patterns to exclude files."""
    assert filter_step.get("predicate-quantifier") == QUANTIFIER


def test_gdscript_excludes_godot_tests(filters):
    """
    ``gdscript`` must exclude ``test/**`` and must not include it.

    ``gdscript`` is a list, so ``in`` compares whole patterns: ``"test/**"``
    does not match the ``"!test/**"`` entry.
    """
    gdscript = filters["gdscript"]
    assert "!test/**" in gdscript
    assert "test/**" not in gdscript


def test_gdscript_keeps_game_patterns(filters):
    """
    ``gdscript`` must still match game code, scenes, resources and the project.

    Without this, dropping a positive pattern would leave the exclusion tests
    passing while real game changes stop triggering lint, tests and export.
    """
    missing = GAME_PATTERNS - set(filters["gdscript"])
    assert not missing, f"gdscript lost game patterns: {sorted(missing)}"


def test_godot_tests_filter_exists(filters):
    """A dedicated ``godot_tests`` filter must capture ``test/**``."""
    assert "test/**" in filters.get("godot_tests", [])


def test_detect_changes_exports_godot_tests(workflow):
    """``detect-changes`` must expose ``godot_tests`` to downstream jobs."""
    outputs = workflow["jobs"]["detect-changes"]["outputs"]
    assert outputs.get("godot_tests") == "${{ steps.filter.outputs.godot_tests }}"


@pytest.mark.parametrize("job_id", ["gdunit4_tests", "gut_tests"])
def test_unit_test_jobs_run_on_godot_tests(workflow, job_id):
    """
    The unit-test jobs must run when only Godot test files change.

    Checks the exact ``== 'true'`` clause, bounded by ``(``/``||`` before and
    ``||``/``)`` after, so a ``!= 'true'`` or an ``&&``-joined clause cannot
    pass by name alone.
    """
    condition = _job_if(workflow, job_id)
    trigger = re.escape(GODOT_TESTS_TRIGGER)
    operand = rf"(?:\(|\|\|)\s*{trigger}\s*(?:\|\||\))"
    assert re.search(operand, condition), f"{job_id} must OR in: {GODOT_TESTS_TRIGGER}"


@pytest.mark.parametrize("job_id", ["gdlint", "browser_tests"])
def test_export_and_lint_jobs_ignore_godot_tests(workflow, job_id):
    """gdlint and the browser suite must not run for test-only changes."""
    assert "godot_tests" not in _job_if(workflow, job_id)


def test_only_gdscript_uses_exclude_patterns(filters):
    """
    No other filter may carry a ``!`` pattern by accident.

    ``some-with-excludes`` applies to every filter in the step. Today only
    ``gdscript`` needs an exclusion; a new ``!`` pattern elsewhere should be a
    deliberate change that updates this test.
    """
    with_excludes = sorted(
        name
        for name, patterns in filters.items()
        if any(str(p).startswith("!") for p in patterns)
    )
    assert with_excludes == ["gdscript"]


def test_exclude_patterns_require_quantifier(filter_step, filters):
    """Any ``!`` pattern is only safe under ``some-with-excludes``."""
    has_excludes = any(
        str(p).startswith("!") for patterns in filters.values() for p in patterns
    )
    if has_excludes:
        assert filter_step.get("predicate-quantifier") == QUANTIFIER
