# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_pr_path_filters.py

"""
Regression guard for the path filters in ``lint_test_on_pull.yml`` (#1018, #____).

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

The same mechanism keeps CI infrastructure tests out of the browser suite:

* ``python_tests`` excludes ``tests/ci/**`` with a ``'!tests/ci/**'`` pattern.
  Those tests only parse workflow and config files; ``ci_script_tests`` already
  runs them through the ``ci`` filter, so they must not trigger the web export.

The benchmark runs on PRs too, report-only (#1112). It needs game changes, which
``gdscript`` catches, and its own files, which ``gdscript`` excludes with the rest
of ``test/``, so a ``benchmark`` filter adds those. Nothing may wait on that job,
and it must stay read-only.
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

FILTERS_WITH_EXCLUDES = ["gdscript", "python_tests"]
"""The only filters allowed to carry ``!`` patterns (sorted)."""

BENCHMARK_PATTERNS = {
    "test/benchmark/**",
    ".github/workflows/benchmark.yml",
    "export_presets.cfg",
}
"""The benchmark's own files, which must run it even with no game change."""

BENCHMARK_CONDITION = (
    "${{ always() && ( needs.detect-changes.outputs.gdscript == 'true' || "
    "needs.detect-changes.outputs.benchmark == 'true' ) && "
    "needs.gdlint.result != 'failure' && "
    "needs.readmelint.result != 'failure' && "
    "needs.yamllint.result != 'failure' && "
    "needs.gdunit4_tests.result != 'failure' && "
    "needs.gut_tests.result != 'failure' && "
    "needs.ci_script_tests.result != 'failure' && "
    "needs.browser_tests.result != 'failure' }}"
)
"""The exact condition of the PR ``benchmark`` job, whitespace collapsed."""


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


def test_python_tests_excludes_ci_tests(filters):
    """
    ``python_tests`` must exclude ``tests/ci/**`` but keep matching other tests.

    Playwright suites (``tests/*_test.py``, ``tests/refactor/``) still need the
    browser run; only the CI infrastructure tests are routed elsewhere.
    """
    python_tests = filters["python_tests"]
    assert "!tests/ci/**" in python_tests
    assert "tests/**/*.py" in python_tests
    assert "pytest.ini" in python_tests


def test_ci_filter_still_covers_ci_tests(filters):
    """``ci`` must keep ``tests/ci/**`` so ``ci_script_tests`` runs those tests."""
    assert "tests/ci/**" in filters["ci"]


def test_only_expected_filters_use_exclude_patterns(filters):
    """
    No other filter may carry a ``!`` pattern by accident.

    ``some-with-excludes`` applies to every filter in the step. Only ``gdscript``
    and ``python_tests`` need an exclusion; a new ``!`` pattern elsewhere should
    be a deliberate change that updates ``FILTERS_WITH_EXCLUDES``.
    """
    with_excludes = sorted(
        name
        for name, patterns in filters.items()
        if any(str(p).startswith("!") for p in patterns)
    )
    assert with_excludes == FILTERS_WITH_EXCLUDES


def test_exclude_patterns_require_quantifier(filter_step, filters):
    """Any ``!`` pattern is only safe under ``some-with-excludes``."""
    has_excludes = any(
        str(p).startswith("!") for patterns in filters.values() for p in patterns
    )
    if has_excludes:
        assert filter_step.get("predicate-quantifier") == QUANTIFIER


def _glob_to_regex(pattern):
    """
    Translate a paths-filter glob to a regular expression.

    Supports only what the ``filters:`` block uses: ``**/``, ``**`` and ``*``.
    Dot files match, as they do in paths-filter.

    Args:
        pattern: The glob, without any leading ``!``.

    Returns:
        re.Pattern: A pattern to use with ``fullmatch``.
    """
    regex = re.escape(pattern)
    regex = regex.replace(r"\*\*/", "(?:.*/)?").replace(r"\*\*", ".*")
    return re.compile(regex.replace(r"\*", "[^/]*"))


def _matches(patterns, path):
    """
    Apply the ``some-with-excludes`` rule to one changed file.

    Args:
        patterns: The filter's patterns, including any ``!`` ones.
        path: The changed file's path.

    Returns:
        bool: True if an include pattern matches and no ``!`` pattern does.
    """
    excludes = [p[1:] for p in patterns if p.startswith("!")]
    includes = [p for p in patterns if not p.startswith("!")]
    return any(_glob_to_regex(p).fullmatch(path) for p in includes) and not any(
        _glob_to_regex(p).fullmatch(path) for p in excludes
    )


def _benchmark_runs(filters, path):
    """
    Say whether changing one file runs the PR ``benchmark`` job.

    Args:
        filters: Filter name mapped to its list of patterns.
        path: The changed file's path.

    Returns:
        bool: True if either filter the job's condition reads matches.
    """
    return _matches(filters["gdscript"], path) or _matches(filters["benchmark"], path)


@pytest.mark.parametrize(
    "path",
    [
        "scripts/player/player.gd",
        "scenes/main_menu.tscn",
        "config_resources/audio.tres",
        "default_bus_layout.tres",
        "project.godot",
        "test/benchmark/benchmark_runner.gd",
        "test/benchmark/benchmark_runner.tscn",
        "test/benchmark/compare.py",
        ".github/workflows/benchmark.yml",
        "export_presets.cfg",
    ],
)
def test_game_and_benchmark_changes_run_the_benchmark(filters, path):
    """Game code, resources and the benchmark's own files run both jobs."""
    assert _benchmark_runs(filters, path), f"{path} must run the benchmark"


@pytest.mark.parametrize(
    "path",
    [
        "README.md",
        "files/docs/Performance_Benchmark_Guide.md",
        ".github/workflows/yamllint.yml",
        ".github/workflows/lint_test_on_pull.yml",
        "tests/ci/test_pr_path_filters.py",
        "tests/refactor/menu_test.py",
        "test/gut/test_player.gd",
        "test/gdunit4/test_scene.tscn",
    ],
)
def test_docs_yaml_and_other_tests_skip_the_benchmark(filters, path):
    """Docs, other YAML and tests outside ``test/benchmark/`` skip both jobs."""
    assert not _benchmark_runs(filters, path), f"{path} must not run the benchmark"


def test_benchmark_filter_has_exactly_its_patterns(filters):
    """
    The filter must list the benchmark's own files and nothing else.

    A wider pattern here would spend about 10 runner minutes on PRs that cannot
    change the numbers.
    """
    assert set(filters.get("benchmark", [])) == BENCHMARK_PATTERNS


def test_detect_changes_exports_benchmark(workflow):
    """``detect-changes`` must expose ``benchmark`` to the job that reads it."""
    outputs = workflow["jobs"]["detect-changes"]["outputs"]
    assert outputs.get("benchmark") == "${{ steps.filter.outputs.benchmark }}"


def test_benchmark_job_calls_the_workflow_on_either_filter(workflow):
    """
    The job must call ``benchmark.yml`` when either filter matches.

    Compares the whole condition: an ``&&`` between the filters would skip game-only
    and benchmark-only PRs, and an ``always()`` outside the check on them would run
    docs-only ones. Without ``always()``, a needed job skipped by its own filter
    would skip the benchmark too. The job waits for every lint and test job.
    """
    job = workflow["jobs"]["benchmark"]
    assert job["uses"] == "./.github/workflows/benchmark.yml"
    assert set(job["needs"]) == {
        "browser_tests",
        "detect-changes",
        "gdlint",
        "readmelint",
        "yamllint",
        "gdunit4_tests",
        "gut_tests",
        "ci_script_tests",
    }
    assert _job_if(workflow, "benchmark") == BENCHMARK_CONDITION


def test_benchmark_job_stays_read_only(workflow):
    """
    Nothing the PR benchmark runs under may be able to write.

    The job and the pipeline's floor are both checked, because a called
    workflow can only get what its caller grants.
    """
    assert workflow["jobs"]["benchmark"]["permissions"] == {"contents": "read"}
    assert set(workflow["permissions"].values()) == {"read"}


def test_called_benchmark_workflow_cannot_push():
    """``benchmark.yml`` must not push, so a PR never reaches ``benchmark-baselines``."""
    path = WORKFLOW.parent / "benchmark.yml"
    assert "git push" not in path.read_text(encoding="utf-8")


def test_no_job_waits_on_the_benchmark(workflow):
    """
    No job may need ``benchmark``, so it stays outside the merge path.

    A job that needed it would wait on it, and would skip if the benchmark failed
    because it could not measure.
    """
    waiting = []
    for job_id, job in workflow["jobs"].items():
        needs = job.get("needs", [])
        needs = [needs] if isinstance(needs, str) else needs
        if "benchmark" in needs:
            waiting.append(job_id)
    assert not waiting, f"these jobs must not need the benchmark: {waiting}"


@pytest.mark.parametrize(
    "path, game_match, benchmark_match",
    [
        ("player.gd", True, False),
        ("scenes/nested/level.tscn", True, False),
        ("test/benchmark/nested/.fixture.json", False, True),
        ("test/benchmark/nested/scene.tscn", False, True),
        ("test/benchmarking/scene.tscn", False, False),
        ("test/benchmark.gd", False, False),
        ("export_presets.cfg.bak", False, False),
        (".github/workflows/benchmark.yml.bak", False, False),
    ],
)
def test_benchmark_filter_boundaries(filters, path, game_match, benchmark_match):
    """Each filter selects only its intended paths, including nested and dot files."""
    assert _matches(filters["gdscript"], path) is game_match
    assert _matches(filters["benchmark"], path) is benchmark_match


def test_pr_pipeline_does_not_call_the_baseline_gate(workflow):
    """A separate gate job must not run on PRs, however its workflow is referenced."""
    callers = [
        job_id
        for job_id, job in workflow["jobs"].items()
        if "benchmark_baselines.yml" in job.get("uses", "")
    ]
    assert not callers, f"PR pipeline must not call the baseline gate: {callers}"


def _find_step(steps, name):
    """
    Return the step with this name, failing the test clearly if it is missing.

    Args:
        steps: The job's list of steps.
        name: The step's ``name``.

    Returns:
        dict: The first step with that name.
    """
    found = [step for step in steps if step.get("name") == name]
    assert found, f"no step named {name!r}"
    return found[0]


@pytest.mark.parametrize(
    "job_id, artifact_name, artifact_path",
    [
        ("desktop", "benchmark-results", "bench_results/ci/desktop/**"),
        ("web", "benchmark-web-results", "bench_results/ci/web/**"),
    ],
)
def test_pr_benchmark_reports_are_uploaded_and_errors_are_not_suppressed(
    job_id, artifact_name, artifact_path
):
    """Both profiles publish results while measurement and comparison errors fail."""
    path = WORKFLOW.parent / "benchmark.yml"
    job = yaml.safe_load(path.read_text(encoding="utf-8"))["jobs"][job_id]
    steps = job["steps"]
    run_name = "Run Benchmark" if job_id == "desktop" else "Run Web Benchmark"
    for name in (run_name, "Compare With Baseline"):
        step = _find_step(steps, name)
        assert not step.get("continue-on-error", False)
        assert "|| true" not in step["run"]
    assert not job.get("continue-on-error", False)

    upload = _find_step(steps, "Upload Benchmark Results")
    assert upload["uses"].startswith("actions/upload-artifact@")
    assert upload["if"] == "always()"
    assert upload["with"]["name"] == artifact_name
    assert upload["with"]["path"] == artifact_path
