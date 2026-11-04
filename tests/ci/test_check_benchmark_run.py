# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_check_benchmark_run.py

"""Tests for .github/scripts/check_benchmark_run.py, the manual accept checks (#1111)."""

import importlib.util
import json
import pathlib

import pytest

SCRIPT = pathlib.Path(".github/scripts/check_benchmark_run.py")
SPEC = importlib.util.spec_from_file_location("check_benchmark_run", SCRIPT)
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)

REPO = "ikostan/SkyLockAssault"
SHA = "a" * 40


def good_run() -> dict:
    """Return the API response for a run that may be accepted."""
    return {
        "path": ".github/workflows/lint_test_deploy.yml",
        "event": "push",
        "head_branch": "main",
        "head_repository": {"full_name": REPO},
        "status": "completed",
        "conclusion": "failure",
        "head_sha": SHA,
    }


def good_jobs() -> dict:
    """Return the jobs of a run that may be accepted; its gate job failed."""
    return {
        "jobs": [
            {"name": "Performance Benchmark / Desktop", "conclusion": "success"},
            {"name": "Performance Benchmark / Web", "conclusion": "success"},
            {"name": "Benchmark Baselines / Baselines", "conclusion": "failure"},
        ]
    }


def good_artifacts() -> dict:
    """Return the artifacts of a run that may be accepted."""
    return {
        "artifacts": [
            {"name": "benchmark-results", "expired": False},
            {"name": "benchmark-web-results", "expired": False},
        ]
    }


def run_check(tmp_path, capsys, run=None, jobs=None, artifacts=None):
    """Run the 'run' subcommand on these responses; return (exit code, stdout)."""
    files = {
        "run": good_run() if run is None else run,
        "jobs": good_jobs() if jobs is None else jobs,
        "artifacts": good_artifacts() if artifacts is None else artifacts,
    }
    argv = ["run", "--repo", REPO]
    for name, content in files.items():
        path = tmp_path / f"{name}.json"
        path.write_text(json.dumps(content), encoding="utf-8")
        argv += [f"--{name}", str(path)]
    code = check.main(argv)
    return code, capsys.readouterr().out.strip()


def test_trusted_run_passes_and_prints_its_sha(tmp_path, capsys):
    """A finished push to main with both results prints the SHA to accept."""
    assert run_check(tmp_path, capsys) == (0, SHA)


@pytest.mark.parametrize(
    "field, value, reason",
    [
        ("path", ".github/workflows/lint_test_on_pull.yml", "lint_test_on_pull"),
        ("path", None, "None"),
        ("event", "pull_request", "pull_request"),
        ("event", "workflow_dispatch", "workflow_dispatch"),
        ("head_branch", "feature", "feature"),
        ("head_repository", {"full_name": "someone/fork"}, "someone/fork"),
        ("head_repository", None, "unknown repository"),
        ("status", "in_progress", "in_progress"),
        ("head_sha", "", "no head SHA"),
    ],
)
def test_untrusted_run_is_refused(tmp_path, capsys, field, value, reason):
    """Each run check refuses on its own and names the reason for the summary."""
    run = {**good_run(), field: value}
    code, out = run_check(tmp_path, capsys, run=run)
    assert code == 1
    assert reason in out


def test_repository_match_ignores_case(tmp_path, capsys):
    """GitHub treats owner and repository names as case-insensitive."""
    run = {**good_run(), "head_repository": {"full_name": REPO.lower()}}
    assert run_check(tmp_path, capsys, run=run) == (0, SHA)


def test_display_name_is_not_trusted(tmp_path, capsys):
    """A run is matched by workflow path, so copying the name does not help."""
    run = {
        **good_run(),
        "name": "Main CI/CD Pipeline",
        "path": ".github/workflows/x.yml",
    }
    assert run_check(tmp_path, capsys, run=run)[0] == 1


@pytest.mark.parametrize("job", ["Desktop", "Web"])
@pytest.mark.parametrize("conclusion", ["failure", "skipped", "cancelled", None])
def test_benchmark_job_that_did_not_pass_is_refused(tmp_path, capsys, job, conclusion):
    """A benchmark job only reports, so one that did not pass measured nothing usable."""
    jobs = good_jobs()
    name = f"Performance Benchmark / {job}"
    for entry in jobs["jobs"]:
        if entry["name"] == name:
            entry["conclusion"] = conclusion
    code, out = run_check(tmp_path, capsys, jobs=jobs)
    assert code == 1
    assert name in out


@pytest.mark.parametrize("job", ["Desktop", "Web"])
def test_missing_benchmark_job_is_refused(tmp_path, capsys, job):
    """A run without one of the benchmark jobs cannot be accepted."""
    name = f"Performance Benchmark / {job}"
    jobs = {"jobs": [j for j in good_jobs()["jobs"] if j["name"] != name]}
    code, out = run_check(tmp_path, capsys, jobs=jobs)
    assert code == 1
    assert name in out


@pytest.mark.parametrize("conclusion", ["success", "skipped", "cancelled", None])
def test_run_whose_gate_did_not_fail_is_refused(tmp_path, capsys, conclusion):
    """Only a failed gate has something to accept."""
    jobs = good_jobs()
    jobs["jobs"][-1]["conclusion"] = conclusion
    code, out = run_check(tmp_path, capsys, jobs=jobs)
    assert code == 1
    assert "Benchmark Baselines / Baselines" in out


def test_run_from_before_the_gate_existed_is_refused(tmp_path, capsys):
    """An old green run with worse numbers must not raise today's baselines."""
    jobs = {"jobs": good_jobs()["jobs"][:2]}
    code, out = run_check(tmp_path, capsys, jobs=jobs)
    assert code == 1
    assert "Benchmark Baselines / Baselines" in out


@pytest.mark.parametrize("name", ["benchmark-results", "benchmark-web-results"])
def test_missing_artifact_is_refused(tmp_path, capsys, name):
    """Both results artifacts must exist."""
    artifacts = {
        "artifacts": [a for a in good_artifacts()["artifacts"] if a["name"] != name]
    }
    code, out = run_check(tmp_path, capsys, artifacts=artifacts)
    assert code == 1
    assert name in out


@pytest.mark.parametrize("name", ["benchmark-results", "benchmark-web-results"])
def test_expired_artifact_is_refused(tmp_path, capsys, name):
    """An expired artifact cannot be downloaded, so it counts as missing."""
    artifacts = good_artifacts()
    for artifact in artifacts["artifacts"]:
        if artifact["name"] == name:
            artifact["expired"] = True
    code, out = run_check(tmp_path, capsys, artifacts=artifacts)
    assert code == 1
    assert name in out


@pytest.mark.parametrize("name", ["benchmark-results", "benchmark-web-results"])
def test_artifact_without_expiry_metadata_is_refused(tmp_path, capsys, name):
    """An artifact is usable only when the API says it has not expired."""
    artifacts = good_artifacts()
    for artifact in artifacts["artifacts"]:
        if artifact["name"] == name:
            del artifact["expired"]
    code, out = run_check(tmp_path, capsys, artifacts=artifacts)
    assert code == 1
    assert name in out


def test_unexpired_duplicate_artifact_is_usable(tmp_path, capsys):
    """An expired artifact with the same name does not hide a usable one."""
    artifacts = good_artifacts()
    artifacts["artifacts"].insert(
        0, {"name": "benchmark-results", "expired": True}
    )
    assert run_check(tmp_path, capsys, artifacts=artifacts) == (0, SHA)


def test_all_problems_are_reported_together(tmp_path, capsys):
    """One summary line names every problem, so one attempt shows them all."""
    run = {**good_run(), "event": "pull_request"}
    code, out = run_check(tmp_path, capsys, run=run, artifacts={"artifacts": []})
    assert code == 1
    assert "pull_request" in out
    assert "benchmark-results" in out
    assert "benchmark-web-results" in out


def test_malformed_api_response_is_refused(tmp_path, capsys):
    """A response of the wrong shape refuses the run instead of crashing."""
    code, out = run_check(tmp_path, capsys, jobs={"message": "Not Found"})
    assert code == 1
    assert "cannot read" in out


@pytest.mark.parametrize("bad_file", ["run", "jobs", "artifacts"])
@pytest.mark.parametrize("content", [None, "{broken"])
def test_unreadable_api_file_is_refused(tmp_path, capsys, bad_file, content):
    """Missing or invalid saved API responses cannot authorize an acceptance."""
    responses = {"run": good_run(), "jobs": good_jobs(), "artifacts": good_artifacts()}
    argv = ["run", "--repo", REPO]
    for name, response in responses.items():
        path = tmp_path / f"{name}.json"
        if name != bad_file:
            path.write_text(json.dumps(response), encoding="utf-8")
        elif content is not None:
            path.write_text(content, encoding="utf-8")
        argv += [f"--{name}", str(path)]
    assert check.main(argv) == 1
    assert "cannot read the run's details" in capsys.readouterr().out


def write_candidate(tmp_path, name, commit):
    """Write one baseline candidate holding this commit; return its path."""
    path = tmp_path / name
    path.write_text(json.dumps({"version": 1, "commit": commit}), encoding="utf-8")
    return str(path)


def test_candidates_from_the_run_pass(tmp_path, capsys):
    """Candidates whose commit is the run's head SHA pass."""
    desktop = write_candidate(tmp_path, "baseline_ci.json", SHA)
    web = write_candidate(tmp_path, "baseline_web_ci.json", SHA)
    assert check.main(["candidates", "--sha", SHA, desktop, web]) == 0
    assert capsys.readouterr().out.strip() == SHA


@pytest.mark.parametrize("wrong", ["desktop", "web"])
@pytest.mark.parametrize("commit", ["b" * 40, "unknown", None])
def test_candidate_from_another_commit_is_refused(tmp_path, capsys, wrong, commit):
    """Results from any other commit raise nothing, whichever file it is."""
    desktop = write_candidate(
        tmp_path, "baseline_ci.json", commit if wrong == "desktop" else SHA
    )
    web = write_candidate(
        tmp_path, "baseline_web_ci.json", commit if wrong == "web" else SHA
    )
    assert check.main(["candidates", "--sha", SHA, desktop, web]) == 1
    assert "not " + SHA in capsys.readouterr().out


@pytest.mark.parametrize("content", [None, "{broken", "[1, 2]"])
def test_unreadable_candidate_is_refused(tmp_path, capsys, content):
    """A missing or malformed candidate refuses the run instead of crashing."""
    path = tmp_path / "baseline_ci.json"
    if content is not None:
        path.write_text(content, encoding="utf-8")
    assert check.main(["candidates", "--sha", SHA, str(path)]) == 1
    assert "cannot read" in capsys.readouterr().out


def test_candidate_errors_are_reported_for_both_files(tmp_path, capsys):
    """A missing candidate does not prevent reporting a mismatched one too."""
    desktop = tmp_path / "baseline_ci.json"
    web = write_candidate(tmp_path, "baseline_web_ci.json", "b" * 40)
    assert check.main(["candidates", "--sha", SHA, str(desktop), web]) == 1
    out = capsys.readouterr().out
    assert "cannot read baseline_ci.json" in out
    assert "baseline_web_ci.json is from commit" in out
