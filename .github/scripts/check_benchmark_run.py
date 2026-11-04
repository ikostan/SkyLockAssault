#!/usr/bin/env python3
# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# .github/scripts/check_benchmark_run.py
"""
Check that a run may be accepted into the benchmark baselines by hand (#1111).

A manual accept raises count baselines from another run's results, so that run
must be a trusted benchmark run on main. See "Which runs it accepts" in
files/docs/Automatic_Benchmark_Baselines.md.

Subcommands:

    run         Check the run, its jobs and its artifacts from saved GitHub API
                responses. Prints the run's head SHA.
    candidates  Check that the commit in each downloaded baseline candidate
                equals the run's head SHA.

Exit 0 means the check passed. Exit 1 means it failed, with the reason on stdout
so the workflow can put it in the job summary.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PIPELINE = ".github/workflows/lint_test_deploy.yml"
BENCHMARK_JOBS = ("Performance Benchmark / Desktop", "Performance Benchmark / Web")
ARTIFACTS = ("benchmark-results", "benchmark-web-results")


def job_problems(jobs: dict) -> list[str]:
    """Return why the run's benchmark jobs cannot be trusted.

    The benchmark jobs only report, so one that did not pass failed to measure.
    """
    conclusions = {job.get("name"): job.get("conclusion") for job in jobs["jobs"]}
    return [
        f"job '{name}' did not pass (conclusion: {conclusions.get(name)})."
        for name in BENCHMARK_JOBS
        if conclusions.get(name) != "success"
    ]


def artifact_problems(artifacts: dict) -> list[str]:
    """Return which results artifacts are missing or expired."""
    usable = {
        artifact.get("name")
        for artifact in artifacts["artifacts"]
        if not artifact.get("expired", True)
    }
    return [
        f"artifact '{name}' is missing or expired."
        for name in ARTIFACTS
        if name not in usable
    ]


def run_problems(run: dict, repo: str) -> list[str]:
    """Return why this run did not come from a push to this repository's main."""
    head_repo = (run.get("head_repository") or {}).get("full_name", "")
    checks = (
        (
            run.get("path") == PIPELINE,
            f"the run is from {run.get('path')}, not {PIPELINE}.",
        ),
        (
            run.get("event") == "push",
            f"the run's event is {run.get('event')}, not push.",
        ),
        (
            run.get("head_branch") == "main",
            f"the run is on branch {run.get('head_branch')}, not main.",
        ),
        (
            head_repo.casefold() == repo.casefold(),
            f"the run's code is from {head_repo or 'an unknown repository'}, not {repo}.",
        ),
        (
            run.get("status") == "completed",
            f"the run has not finished (status: {run.get('status')}).",
        ),
        (bool(run.get("head_sha")), "the run has no head SHA."),
    )
    return [reason for passed, reason in checks if not passed]


def candidate_problems(paths: list[Path], sha: str) -> list[str]:
    """Return which baseline candidates did not come from this commit."""
    problems = []
    for path in paths:
        try:
            commit = json.loads(path.read_text(encoding="utf-8")).get("commit")
        except (OSError, ValueError, AttributeError) as err:
            problems.append(f"cannot read {path.name}: {err}.")
            continue
        if commit != sha:
            problems.append(f"{path.name} is from commit {commit}, not {sha}.")
    return problems


def load(path: Path) -> dict:
    """Read one saved API response."""
    return json.loads(path.read_text(encoding="utf-8"))


def check_run(args: argparse.Namespace) -> tuple[list[str], str]:
    """Run the 'run' subcommand; return (problems, text to print on success)."""
    run = load(args.run)
    problems = run_problems(run, args.repo)
    problems += job_problems(load(args.jobs))
    problems += artifact_problems(load(args.artifacts))
    return problems, str(run.get("head_sha"))


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    run = commands.add_parser("run", help="Check a run from saved API responses.")
    for name in ("run", "jobs", "artifacts"):
        run.add_argument(f"--{name}", type=Path, required=True)
    run.add_argument("--repo", required=True, help="This repository, owner/name.")
    candidates = commands.add_parser("candidates", help="Check candidate commits.")
    candidates.add_argument("--sha", required=True, help="The run's head SHA.")
    candidates.add_argument("paths", type=Path, nargs="+")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Print the outcome; return 0 if the check passed, otherwise 1."""
    args = parse_args(argv)
    if args.command == "run":
        try:
            problems, success = check_run(args)
        except (OSError, ValueError, KeyError, TypeError) as err:
            problems, success = [f"cannot read the run's details: {err}."], ""
    else:
        problems, success = candidate_problems(args.paths, args.sha), args.sha
    print(" ".join(problems) if problems else success)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
