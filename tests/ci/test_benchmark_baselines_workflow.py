# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_benchmark_baselines_workflow.py

"""
Tests for the benchmark gate and accept path in CI (#1111).

The first half checks the workflow files: who can write, and that the deploy chain
stays independent. The second half runs the real shell steps of
``benchmark_baselines.yml`` with the real ``compare.py`` against a local bare git
repository and a stubbed ``gh``. A workflow only runs on GitHub after it merges, so
this is what can catch a broken gate or push before then.
"""

import json
import os
import pathlib
import shutil
import stat
import subprocess
import sys

import pytest
import yaml

WORKFLOW_DIR = pathlib.Path(".github/workflows")
BASELINES_WORKFLOW = "benchmark_baselines.yml"
REPO = "ikostan/SkyLockAssault"
SHA = "a1b2c3d" + "0" * 33
RUN_ID = "1000"
MANUAL_SHA = "f" * 40  # A manual run's own SHA: the latest main, not the failed run's.
BRANCH = "benchmark-baselines"
COUNTS = {
    "saves": 0.0,
    "objects_avg": 2500.0,
    "nodes_avg": 500.0,
    "resources_avg": 206.0,
    "orphans_max": 0.0,
    "reload_orphans_max": 0.0,
    "reload_object_growth": 2.0,
}
TIMINGS = {
    "frame_p95_ms": 16.8,
    "frames_over_33.4ms": 0.0,
    "proc_worst_avg_ms": 0.1,
    "phys_worst_avg_ms": 0.15,
    "mem_static_growth": 150000.0,
}
METRICS = {**COUNTS, **TIMINGS}

needs_bash = pytest.mark.skipif(
    os.name == "nt", reason="runs the workflow's bash steps with a POSIX gh stub"
)


def load(name: str) -> dict:
    """Parse a workflow file."""
    return yaml.safe_load((WORKFLOW_DIR / name).read_text(encoding="utf-8"))


def job_steps() -> list[dict]:
    """Return the steps of the baselines job."""
    return load(BASELINES_WORKFLOW)["jobs"]["baselines"]["steps"]


def find_step(steps: list[dict], name: str) -> dict:
    """Return the step with this name, failing the test clearly if it is missing."""
    found = [s for s in steps if s.get("name") == name]
    assert found, f"no step named {name!r}"
    return found[0]


def step(name: str) -> dict:
    """Return one step of the baselines job by name."""
    return find_step(job_steps(), name)


def needs(job: dict) -> list[str]:
    """Return a job's needs as a list."""
    value = job.get("needs", [])
    return [value] if isinstance(value, str) else list(value)


# Workflow files


def test_baselines_workflow_has_one_job_and_no_workflow_permissions():
    """Write access lives in one job, not at workflow level."""
    workflow = load(BASELINES_WORKFLOW)
    assert list(workflow["jobs"]) == ["baselines"]
    assert "permissions" not in workflow


def test_only_the_baselines_job_requests_contents_write():
    """Only the baselines job can write; the benchmark jobs stay read-only."""
    assert load(BASELINES_WORKFLOW)["jobs"]["baselines"]["permissions"] == {
        "contents": "write",
        "pull-requests": "read",
        "actions": "read",
    }
    benchmark = load("benchmark.yml")
    assert "permissions" not in benchmark
    assert sorted(benchmark["jobs"]) == ["desktop", "web"]
    for job in benchmark["jobs"].values():
        assert job["permissions"] == {"contents": "read"}


def test_benchmark_jobs_never_persist_credentials():
    """Jobs that run pip, Playwright and Godot keep no token in the checkout."""
    for job_id, job in load("benchmark.yml")["jobs"].items():
        checkouts = [
            s for s in job["steps"] if "actions/checkout" in str(s.get("uses", ""))
        ]
        assert len(checkouts) == 2, job_id
        for checkout in checkouts:
            assert checkout["with"]["persist-credentials"] is False, job_id


@pytest.mark.parametrize(
    "job_id, profile, candidate",
    [
        ("desktop", "desktop", "baseline_ci.json"),
        ("web", "web", "baseline_web_ci.json"),
    ],
)
def test_benchmark_jobs_only_report(job_id, profile, candidate):
    """The jobs compare report-only with the branch and keep the accept check's file."""
    steps = load("benchmark.yml")["jobs"][job_id]["steps"]
    script = find_step(steps, "Compare With Baseline")["run"]
    assert "--report-only" in script
    assert f"--baseline baselines/{profile}.json" in script
    assert f"--profile {profile}" in script
    assert f'--write-baseline "${{OUT_DIR}}/{candidate}"' in script
    assert "--update" not in script
    assert "test/benchmark/baseline" not in script


@pytest.mark.parametrize("job_id", ["desktop", "web"])
def test_benchmark_jobs_check_out_baselines_after_measuring(job_id):
    """The baselines must not be in the project or the export being measured."""
    steps = load("benchmark.yml")["jobs"][job_id]["steps"]
    names = [s.get("name", "") for s in steps]
    measuring = [i for i, name in enumerate(names) if "Benchmark" in name]
    assert measuring, f"{job_id}: no benchmark step"
    checkout = names.index("Check Out Baselines")
    assert measuring[0] < checkout < names.index("Compare With Baseline")
    assert steps[checkout]["with"]["ref"] == BRANCH
    assert steps[checkout]["with"]["path"] == "baselines"


def test_baselines_job_runs_on_main_only_in_one_queue():
    """Runs on main queue up one at a time, and a pending run is never replaced."""
    job = load(BASELINES_WORKFLOW)["jobs"]["baselines"]
    assert job["if"] == "github.ref == 'refs/heads/main'"
    assert job["runs-on"] == "ubuntu-24.04"
    assert job["concurrency"] == {
        "group": BRANCH,
        "cancel-in-progress": False,
        "queue": "max",
    }


def test_baselines_workflow_triggers():
    """It is called by the pipeline or run by hand with a run ID and accept."""
    workflow = load(BASELINES_WORKFLOW)
    triggers = workflow.get("on", workflow.get(True))
    assert sorted(triggers) == ["workflow_call", "workflow_dispatch"]
    inputs = triggers["workflow_dispatch"]["inputs"]
    assert inputs["run_id"]["required"] is True
    assert inputs["accept"]["type"] == "boolean"
    assert inputs["accept"]["default"] is False


def test_baselines_job_installs_nothing_while_holding_write_access():
    """A job with write access runs only this repository's code."""
    for s in job_steps():
        script = s.get("run", "")
        for word in ("pip install", "npm ", "apt-get", "playwright", "godot"):
            assert word not in script, s.get("name")


def test_only_the_baselines_checkout_can_push():
    """The scripts checkout keeps no token; only the baselines checkout does."""
    assert step("Check Out Scripts")["with"]["persist-credentials"] is False
    baselines = step("Check Out Baselines")["with"]
    assert baselines["ref"] == BRANCH
    assert baselines.get("persist-credentials", True) is True


def test_downloads_use_the_selected_run():
    """Both downloads take the selected run, so a manual accept reuses its results."""
    for name, artifact in (
        ("Download Desktop Results", "benchmark-results"),
        ("Download Web Results", "benchmark-web-results"),
    ):
        settings = step(name)["with"]
        assert settings["name"] == artifact
        assert settings["run-id"] == "${{ steps.run.outputs.id }}"


def test_run_inputs_reach_shell_through_env_only():
    """Dispatch inputs are never expanded into a script, so they cannot inject code."""
    for s in job_steps():
        assert "${{" not in s.get("run", ""), s.get("name")


def test_main_pipeline_calls_baselines_after_benchmark():
    """The gate runs after both benchmark jobs, on their results."""
    job = load("lint_test_deploy.yml")["jobs"]["benchmark_baselines"]
    assert job["uses"] == f"./.github/workflows/{BASELINES_WORKFLOW}"
    assert needs(job) == ["benchmark"]


def test_deploys_do_not_depend_on_the_benchmark():
    """No job in the main pipeline waits on the benchmark except the gate."""
    jobs = load("lint_test_deploy.yml")["jobs"]
    waiting = {
        job_id
        for job_id, job in jobs.items()
        if {"benchmark", "benchmark_baselines"} & set(needs(job))
    }
    assert waiting == {"benchmark_baselines"}


def test_pr_pipeline_cannot_reach_the_baselines_job():
    """The PR pipeline's read-only token never runs the job that writes."""
    assert BASELINES_WORKFLOW not in (WORKFLOW_DIR / "lint_test_on_pull.yml").read_text(
        encoding="utf-8"
    )


# Real steps against a local remote


@pytest.fixture(name="ci")
def fixture_ci(tmp_path):
    """Lay out a runner workspace: scripts, results, a remote and a stub gh."""
    return Runner(tmp_path)


class Runner:
    """A fake runner workspace whose steps run for real."""

    def __init__(self, root: pathlib.Path) -> None:
        """Create the workspace, seed the remote and check out the baselines."""
        self.root = root
        self.work = root / "work"
        self.bin = root / "bin"
        self.remote = root / "remote.git"
        self.summary = root / "summary.md"
        self.output = root / "output.txt"
        self.gh_log = root / "gh.log"
        for folder in (self.work, self.bin):
            folder.mkdir()
        repo_root = pathlib.Path.cwd()
        for rel in (
            "test/benchmark/compare.py",
            ".github/scripts/check_benchmark_run.py",
        ):
            target = self.work / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(repo_root / rel, target)
        self.write_results()
        self.seed_remote()
        self.set_gh(pulls=[])

    def git(self, *args: str, cwd: pathlib.Path | None = None) -> str:
        """Run git and return its output."""
        return subprocess.run(
            ["git", *args],
            cwd=cwd or self.root,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def seed_remote(self) -> None:
        """Create the remote branch with two seed files, then clone it."""
        seed = self.root / "seed"
        self.git("init", "-q", "--bare", str(self.remote))
        self.git("init", "-q", "-b", BRANCH, str(seed))
        for profile in ("desktop", "web"):
            doc = {
                "version": 2,
                "commit": "seed",
                "created": "2026-10-31T00:00:00Z",
                "baseline": METRICS,
                "history": [],
                "accepted": None,
                "seen_runs": [],
                "profile": profile,
            }
            (seed / f"{profile}.json").write_text(json.dumps(doc), encoding="utf-8")
        self.git("add", ".", cwd=seed)
        self.git(
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@t",
            "commit",
            "-qm",
            "seed",
            cwd=seed,
        )
        self.git("push", "-q", str(self.remote), BRANCH, cwd=seed)
        self.git(
            "clone", "-q", "-b", BRANCH, str(self.remote), str(self.work / "baselines")
        )

    def write_results(
        self, desktop: dict | None = None, web: dict | None = None
    ) -> None:
        """Write both runs.csv files, with these metrics changed from the seed."""
        for profile, changes in (("desktop", desktop), ("web", web)):
            folder = self.work / "results" / profile
            folder.mkdir(parents=True, exist_ok=True)
            row = {"godot": "4.7.1", **METRICS, **(changes or {})}
            header, values = ",".join(row), ",".join(str(v) for v in row.values())
            (folder / "runs.csv").write_text(f"{header}\n{values}\n", encoding="utf-8")

    def write_candidates(self, commit: str = SHA) -> None:
        """Write the candidate files the manual path checks."""
        for profile, name in (("desktop", "baseline_ci"), ("web", "baseline_web_ci")):
            path = self.work / "results" / profile / f"{name}.json"
            path.write_text(json.dumps({"commit": commit}), encoding="utf-8")

    def set_gh(
        self, pulls=None, run=None, jobs=None, artifacts=None, fail=False
    ) -> None:
        """Install a gh stub that answers from these responses and logs each call."""
        responses = {"pulls": pulls, "run": run, "jobs": jobs, "artifacts": artifacts}
        (self.root / "gh.json").write_text(json.dumps(responses), encoding="utf-8")
        code = f"""#!{sys.executable}
import json, sys
args = sys.argv[1:]
with open({str(self.gh_log)!r}, "a", encoding="utf-8") as log:
    log.write(" ".join(args) + "\\n")
if {fail!r}:
    sys.stderr.write("HTTP 500\\n")
    sys.exit(1)
data = json.load(open({str(self.root / "gh.json")!r}, encoding="utf-8"))
url = args[1]
if "/pulls" in url:
    key = "pulls"
elif "/jobs" in url:
    key = "jobs"
elif "/artifacts" in url:
    key = "artifacts"
else:
    key = "run"
if data[key] is None:
    sys.stderr.write("HTTP 404\\n")
    sys.exit(1)
print(json.dumps(data[key]))
"""
        stub = self.bin / "gh"
        stub.write_text(code, encoding="utf-8")
        stub.chmod(stub.stat().st_mode | stat.S_IEXEC)

    def run_step(self, name: str, **env: str) -> subprocess.CompletedProcess:
        """Run one workflow step's script the way GitHub runs `shell: bash`."""
        self.output.write_text("", encoding="utf-8")
        full_env = {
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "HOME": str(self.root),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GITHUB_STEP_SUMMARY": str(self.summary),
            "GITHUB_OUTPUT": str(self.output),
            "GITHUB_REPOSITORY": REPO,
            "GITHUB_EVENT_NAME": "push",
            "GITHUB_RUN_ID": RUN_ID,
            "GITHUB_SHA": SHA,
            "GH_TOKEN": "token",
            **env,
        }
        return subprocess.run(
            [
                "bash",
                "--noprofile",
                "--norc",
                "-eo",
                "pipefail",
                "-c",
                step(name)["run"],
            ],
            cwd=self.work,
            env=full_env,
            capture_output=True,
            text=True,
            check=False,
        )

    def outputs(self) -> dict[str, str]:
        """Return what the last step wrote to GITHUB_OUTPUT."""
        lines = self.output.read_text(encoding="utf-8").splitlines()
        return dict(line.split("=", 1) for line in lines)

    def gate(self, accept: str = "") -> subprocess.CompletedProcess:
        """Run the gate step for this run."""
        return self.run_step(
            "Gate and Update Baselines", RUN_ID=RUN_ID, RUN_SHA=SHA, ACCEPT_ID=accept
        )

    def push(self, run_id: str = RUN_ID) -> subprocess.CompletedProcess:
        """Run the push step for this run."""
        return self.run_step("Push Baselines", RUN_ID=run_id, RUN_SHA=SHA)

    def remote_log(self) -> list[str]:
        """Return the remote branch's commit subjects, newest first."""
        return self.git(
            "--git-dir", str(self.remote), "log", "--format=%s", BRANCH
        ).splitlines()

    def remote_file(self, profile: str) -> dict:
        """Return one baseline file as the remote branch holds it."""
        return json.loads(
            self.git("--git-dir", str(self.remote), "show", f"{BRANCH}:{profile}.json")
        )


@needs_bash
def test_gate_records_the_selected_commit_not_the_runners(ci):
    """A manual accept records the failed run's commit, not the latest main."""
    result = ci.run_step(
        "Gate and Update Baselines",
        GITHUB_SHA=MANUAL_SHA,
        RUN_ID=RUN_ID,
        RUN_SHA=SHA,
        ACCEPT_ID="",
    )
    assert result.returncode == 0, result.stderr
    assert ci.push().returncode == 0
    assert ci.remote_file("web")["history"][0]["commit"] == SHA
    assert ci.remote_file("web")["commit"] == SHA


@needs_bash
def test_passing_run_commits_once_naming_run_and_sha(ci):
    """A passing run adds one commit, updating both files and naming the run."""
    assert ci.gate().returncode == 0
    assert ci.push().returncode == 0
    assert ci.remote_log() == [f"Baselines from run {RUN_ID} ({SHA[:7]})", "seed"]
    for profile in ("desktop", "web"):
        doc = ci.remote_file(profile)
        assert doc["seen_runs"] == [RUN_ID]
        assert doc["history"][0]["commit"] == SHA
        assert doc["profile"] == profile
    summary = ci.summary.read_text(encoding="utf-8")
    assert "Benchmark baseline gate (desktop)" in summary
    assert "Benchmark baseline gate (web)" in summary


@needs_bash
@pytest.mark.parametrize("failing", ["desktop", "web"])
def test_regression_fails_and_leaves_the_branch_unchanged(ci, failing):
    """One platform's regression fails the job, and the other shows its table too."""
    ci.write_results(**{failing: {"saves": 61}})
    result = ci.gate()
    assert result.returncode == 1
    assert "Count regression" in result.stdout
    assert ci.remote_log() == ["seed"]
    summary = ci.summary.read_text(encoding="utf-8")
    assert "Benchmark baseline gate (desktop)" in summary
    assert "Benchmark baseline gate (web)" in summary


@needs_bash
def test_malformed_baseline_is_a_setup_failure(ci):
    """A broken file exits 2, reported as setup, not a regression, and pushes nothing."""
    (ci.work / "baselines" / "web.json").write_text("{}", encoding="utf-8")
    result = ci.gate()
    assert result.returncode == 2
    assert "Setup failure" in result.stdout
    assert ci.remote_log() == ["seed"]


@needs_bash
def test_setup_failure_outranks_a_regression(ci):
    """Exit 2 wins, so a broken file is not mistaken for a regression to accept."""
    ci.write_results(desktop={"saves": 61})
    (ci.work / "baselines" / "web.json").write_text("{}", encoding="utf-8")
    assert ci.gate().returncode == 2


@needs_bash
def test_wrong_profile_in_a_file_is_a_setup_failure(ci):
    """The two files cannot be swapped: each one refuses the other's profile."""
    baselines = ci.work / "baselines"
    desktop = (baselines / "desktop.json").read_text(encoding="utf-8")
    (baselines / "desktop.json").write_text(
        (baselines / "web.json").read_text(encoding="utf-8"), encoding="utf-8"
    )
    (baselines / "web.json").write_text(desktop, encoding="utf-8")
    assert ci.gate().returncode == 2


@needs_bash
def test_accept_raises_only_failing_counts_and_records_the_pr(ci):
    """A labelled merge raises what failed, on that platform, and names the PR."""
    ci.write_results(desktop={"objects_avg": 2900.0, "saves": 1.0})
    assert ci.gate(accept="123").returncode == 0
    assert ci.push().returncode == 0
    desktop = ci.remote_file("desktop")
    assert desktop["baseline"]["objects_avg"] == 2900.0
    assert desktop["baseline"]["saves"] == 0.0
    assert desktop["accepted"]["id"] == "123"
    assert sorted(desktop["accepted"]["raised"]) == ["objects_avg"]
    web = ci.remote_file("web")
    assert web["baseline"]["saves"] == 0.0
    assert web["accepted"] is None
    assert "accepted in #123" in ci.summary.read_text(encoding="utf-8")


@needs_bash
def test_manual_accept_is_named_by_run(ci):
    """A manual accept passes the failed run's ID to both options."""
    ci.write_results(desktop={"objects_avg": 2900.0})
    assert ci.gate(accept=RUN_ID).returncode == 0
    assert "accepted in run 1000" in ci.summary.read_text(encoding="utf-8")


@needs_bash
def test_rerun_of_a_recorded_run_pushes_nothing(ci):
    """Re-running a recorded run changes no file, so there is nothing to commit."""
    assert ci.gate().returncode == 0
    assert ci.push().returncode == 0
    assert ci.gate().returncode == 0
    result = ci.push()
    assert result.returncode == 0
    assert "nothing to push" in result.stdout
    assert len(ci.remote_log()) == 2


@needs_bash
def test_second_run_builds_on_the_first(ci):
    """Consecutive runs fast-forward the branch, and history keeps growing."""
    assert ci.gate().returncode == 0
    assert ci.push().returncode == 0
    result = ci.run_step(
        "Gate and Update Baselines", RUN_ID="1001", RUN_SHA=SHA, ACCEPT_ID=""
    )
    assert result.returncode == 0
    assert ci.push(run_id="1001").returncode == 0
    assert ci.remote_file("desktop")["seen_runs"] == [RUN_ID, "1001"]
    assert len(ci.remote_log()) == 3


@needs_bash
def test_failed_push_fails_the_job(ci):
    """A rejected push must fail the job rather than silently drop the update."""
    ci.git(
        "-C", str(ci.work / "baselines"), "remote", "set-url", "origin", "/no/such/repo"
    )
    assert ci.gate().returncode == 0
    assert ci.push().returncode != 0


def pull(number=7, sha=SHA, labels=("benchmark-accept",)):
    """Return a pull request as the commits API lists it."""
    return {
        "number": number,
        "merge_commit_sha": sha,
        "labels": [{"name": name} for name in labels],
    }


@needs_bash
@pytest.mark.parametrize(
    "pulls, expected",
    [
        pytest.param([pull()], "7", id="labelled-merge"),
        pytest.param([pull(labels=("bug",))], "", id="unlabelled-merge"),
        pytest.param([pull(labels=())], "", id="no-labels"),
        pytest.param([], "", id="direct-push"),
        pytest.param([pull(number=9, sha="f" * 40)], "", id="other-pr-holds-the-label"),
        pytest.param(
            [pull(number=9, sha="f" * 40), pull(number=7)],
            "7",
            id="picks-the-merged-pr",
        ),
    ],
)
def test_accept_lookup_on_a_push(ci, pulls, expected):
    """Only the label on the PR that merged this commit accepts it."""
    ci.set_gh(pulls=pulls)
    result = ci.run_step("Decide the Accept", RUN_ID=RUN_ID, RUN_SHA=SHA)
    assert result.returncode == 0, result.stderr
    assert ci.outputs() == {"id": expected}
    assert f"commits/{SHA}/pulls" in ci.gh_log.read_text(encoding="utf-8")


@needs_bash
def test_accept_lookup_failure_stops_the_job(ci):
    """A failed lookup must not silently count as no label."""
    ci.set_gh(fail=True)
    assert ci.run_step("Decide the Accept", RUN_ID=RUN_ID, RUN_SHA=SHA).returncode != 0


@needs_bash
def test_push_selects_this_run_without_any_api_call(ci):
    """On a push the job uses its own run ID and SHA."""
    result = ci.run_step("Select the Run", INPUT_RUN_ID="", INPUT_ACCEPT="")
    assert result.returncode == 0, result.stderr
    assert ci.outputs() == {"id": RUN_ID, "sha": SHA}
    assert not ci.gh_log.exists()


def good_api() -> dict:
    """Return gh responses for a run that may be accepted."""
    return {
        "run": {
            "path": ".github/workflows/lint_test_deploy.yml",
            "event": "push",
            "head_branch": "main",
            "head_repository": {"full_name": REPO},
            "status": "completed",
            "head_sha": SHA,
        },
        "jobs": {
            "jobs": [
                {"name": "Performance Benchmark / Desktop", "conclusion": "success"},
                {"name": "Performance Benchmark / Web", "conclusion": "success"},
                {"name": "Benchmark Baselines / Baselines", "conclusion": "failure"},
            ]
        },
        "artifacts": {
            "artifacts": [
                {"name": "benchmark-results", "expired": False},
                {"name": "benchmark-web-results", "expired": False},
            ]
        },
    }


def manual(ci, run_id="555", accept="true"):
    """Run the select step as a manual run."""
    return ci.run_step(
        "Select the Run",
        GITHUB_EVENT_NAME="workflow_dispatch",
        GITHUB_SHA=MANUAL_SHA,
        INPUT_RUN_ID=run_id,
        INPUT_ACCEPT=accept,
    )


@needs_bash
def test_manual_run_selects_the_failed_run_and_its_sha(ci):
    """A trusted run gives its own ID and head SHA, not this manual run's."""
    ci.set_gh(**good_api())
    result = manual(ci)
    assert result.returncode == 0, result.stderr
    assert ci.outputs() == {"id": "555", "sha": SHA}


@needs_bash
@pytest.mark.parametrize("accept", ["false", ""])
def test_manual_run_without_accept_does_nothing(ci, accept):
    """Without accept: true it stops before any API call, with the reason."""
    assert manual(ci, accept=accept).returncode == 1
    assert not ci.gh_log.exists()
    assert "needs accept: true" in ci.summary.read_text(encoding="utf-8")


@needs_bash
@pytest.mark.parametrize("run_id", ["", "abc", "12; rm -rf /", "../../secrets"])
def test_manual_run_id_must_be_a_number(ci, run_id):
    """A bad ID never reaches an API path."""
    assert manual(ci, run_id=run_id).returncode == 1
    assert not ci.gh_log.exists()
    assert "must be a run's number" in ci.summary.read_text(encoding="utf-8")


@needs_bash
def test_manual_run_that_cannot_be_read_is_refused(ci):
    """A run ID that does not exist stops with the reason in the summary."""
    ci.set_gh()
    assert manual(ci).returncode == 1
    assert "cannot read run 555" in ci.summary.read_text(encoding="utf-8")


@needs_bash
def test_untrusted_manual_run_is_refused_with_the_reason(ci):
    """A check that fails stops the job and puts its reason in the summary."""
    api = good_api()
    api["run"]["event"] = "pull_request"
    ci.set_gh(**api)
    assert manual(ci).returncode == 1
    assert "pull_request" in ci.summary.read_text(encoding="utf-8")
    assert ci.outputs() == {}


@needs_bash
def test_manual_accept_uses_the_run_id_and_checks_candidates(ci):
    """Matching candidates accept under the failed run's own ID."""
    ci.write_candidates()
    result = ci.run_step(
        "Decide the Accept",
        GITHUB_EVENT_NAME="workflow_dispatch",
        RUN_ID="555",
        RUN_SHA=SHA,
    )
    assert result.returncode == 0, result.stderr
    assert ci.outputs() == {"id": "555"}
    assert not ci.gh_log.exists()


@needs_bash
def test_manual_accept_refuses_mismatched_candidates(ci):
    """Results from another commit raise nothing."""
    ci.write_candidates(commit="f" * 40)
    result = ci.run_step(
        "Decide the Accept",
        GITHUB_EVENT_NAME="workflow_dispatch",
        RUN_ID="555",
        RUN_SHA=SHA,
    )
    assert result.returncode == 1
    assert "Accept refused" in ci.summary.read_text(encoding="utf-8")
    assert ci.outputs() == {}


@needs_bash
def test_manual_path_end_to_end_raises_only_the_failing_count(ci):
    """Select, decide, gate and push together, as a manual accept runs them."""
    ci.set_gh(**good_api())
    assert manual(ci).returncode == 0
    ci.write_candidates()
    ci.write_results(desktop={"nodes_avg": 600.0})
    env = {
        "GITHUB_EVENT_NAME": "workflow_dispatch",
        "GITHUB_SHA": MANUAL_SHA,
        "RUN_ID": "555",
        "RUN_SHA": SHA,
    }
    assert ci.run_step("Decide the Accept", **env).returncode == 0
    accept = ci.outputs()["id"]
    assert (
        ci.run_step("Gate and Update Baselines", ACCEPT_ID=accept, **env).returncode
        == 0
    )
    assert ci.run_step("Push Baselines", **env).returncode == 0
    assert ci.remote_log()[0] == f"Baselines from run 555 ({SHA[:7]})"
    desktop = ci.remote_file("desktop")
    assert desktop["baseline"]["nodes_avg"] == 600.0
    assert sorted(desktop["accepted"]["raised"]) == ["nodes_avg"]
    assert desktop["history"][-1]["commit"] == SHA
