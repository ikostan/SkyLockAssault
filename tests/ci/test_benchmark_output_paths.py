# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_benchmark_output_paths.py
"""Tests for the bench_results/<kind>/<name> output layout (#1079).

Every runner writes under <project>/bench_results/, one folder per kind of
run (desktop, docker, web_headless, web_headed), so results that are not
comparable never share a folder.
"""

import importlib.util
import re
import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[2]
BENCH_DIR = PROJECT_ROOT / "test/benchmark"
STAMP = re.compile(r"^\d{8}_\d{6}$")


def _load(name: str):
    """Load a script from test/benchmark (not a package) as a module."""
    sys.path.insert(0, str(BENCH_DIR))
    try:
        spec = importlib.util.spec_from_file_location(name, BENCH_DIR / f"{name}.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.remove(str(BENCH_DIR))


@pytest.fixture(scope="module")
def desktop():
    """run_desktop.py as a module."""
    return _load("run_desktop")


@pytest.fixture(scope="module")
def web():
    """run_web.py as a module (needs Playwright installed)."""
    pytest.importorskip("playwright")
    return _load("run_web")


def test_results_root_is_bench_results_in_project(desktop):
    """All results live under <project>/bench_results."""
    assert desktop.RESULTS_ROOT == PROJECT_ROOT / "bench_results"


@pytest.mark.parametrize(("exists", "expected"), [(True, "docker"), (False, "desktop")])
def test_detect_environment_uses_docker_marker(desktop, tmp_path, exists, expected):
    """/.dockerenv present means docker, absent means desktop."""
    marker = tmp_path / ".dockerenv"
    if exists:
        marker.touch()
    assert desktop.detect_environment(marker) == expected


@pytest.mark.parametrize("kind", ["desktop", "docker", "web_headless", "web_headed"])
def test_default_out_uses_timestamp_under_kind(desktop, kind):
    """Without a name, each kind gets a timestamp folder under its own folder."""
    out = desktop.default_out(kind)
    assert out.parent == desktop.RESULTS_ROOT / kind
    assert STAMP.match(out.name), out.name


def test_default_out_uses_name_instead_of_timestamp(desktop):
    """--name replaces the timestamp folder."""
    out = desktop.default_out("docker", "baseline_616")
    assert out == desktop.RESULTS_ROOT / "docker" / "baseline_616"


@pytest.mark.parametrize(
    ("argv", "expected_parts"),
    [
        (["--godot", "g"], None),
        (["--godot", "g", "--name", "before"], ("desktop", "before")),
    ],
)
def test_desktop_parse_args_default_out(desktop, monkeypatch, argv, expected_parts):
    """run_desktop.py defaults to bench_results/desktop/<timestamp or name>."""
    monkeypatch.setattr(desktop, "detect_environment", lambda: "desktop")
    monkeypatch.setattr(sys, "argv", ["run_desktop.py", *argv])
    out = desktop.parse_args().out
    if expected_parts is None:
        assert out.parent == desktop.RESULTS_ROOT / "desktop"
        assert STAMP.match(out.name)
    else:
        assert out == desktop.RESULTS_ROOT.joinpath(*expected_parts)


def test_desktop_parse_args_inside_docker(desktop, monkeypatch):
    """Inside Docker, run_desktop.py defaults to bench_results/docker."""
    monkeypatch.setattr(desktop, "detect_environment", lambda: "docker")
    monkeypatch.setattr(sys, "argv", ["run_desktop.py", "--godot", "g"])
    assert desktop.parse_args().out.parent == desktop.RESULTS_ROOT / "docker"


def test_desktop_parse_args_explicit_out_wins(desktop, monkeypatch, tmp_path):
    """--out overrides the default folder, even with --name."""
    argv = ["run_desktop.py", "--godot", "g", "--out", str(tmp_path), "--name", "x"]
    monkeypatch.setattr(sys, "argv", argv)
    assert desktop.parse_args().out == tmp_path


@pytest.mark.parametrize(
    ("extra", "kind"), [([], "web_headless"), (["--headed"], "web_headed")]
)
def test_web_parse_args_default_out_by_mode(web, monkeypatch, extra, kind):
    """Headless and headed web runs default to separate folders."""
    monkeypatch.setattr(sys, "argv", ["run_web.py", "--godot", "g", *extra])
    out = web.parse_args().out
    assert out.parent == web.PROJECT_ROOT / "bench_results" / kind
    assert STAMP.match(out.name)


def test_web_parse_args_name_and_explicit_out(web, monkeypatch, tmp_path):
    """--name names the web folder; --out overrides it."""
    monkeypatch.setattr(
        sys, "argv", ["run_web.py", "--godot", "g", "--headed", "--name", "after"]
    )
    assert web.parse_args().out == (
        web.PROJECT_ROOT / "bench_results" / "web_headed" / "after"
    )
    monkeypatch.setattr(
        sys, "argv", ["run_web.py", "--no-export", "--out", str(tmp_path)]
    )
    assert web.parse_args().out == tmp_path


@pytest.mark.parametrize("runner_name", ["desktop", "web"])
def test_explicit_relative_out_is_preserved_with_name(
    request, runner_name, monkeypatch
):
    """Explicit output paths take precedence without being resolved or renamed."""
    runner = request.getfixturevalue(runner_name)
    monkeypatch.setattr(
        sys, "argv", ["runner", "--godot", "g", "--name", "baseline", "--out", "relative/run"]
    )
    assert runner.parse_args().out == Path("relative/run")


def test_web_no_export_uses_named_headless_default_without_godot(web, monkeypatch):
    """Reusing a build still selects the web output layout without GODOT_BIN."""
    monkeypatch.delenv("GODOT_BIN", raising=False)
    monkeypatch.setattr(sys, "argv", ["run_web.py", "--no-export", "--name", "baseline"])
    assert web.parse_args().out == web.PROJECT_ROOT / "bench_results/web_headless/baseline"


@pytest.mark.parametrize("runner_name", ["desktop", "web"])
@pytest.mark.parametrize("runs", ["0", "-1"])
def test_invalid_run_count_is_rejected_with_output_options(
    request, runner_name, runs, monkeypatch, capsys
):
    """Choosing an output folder must not bypass run-count validation."""
    runner = request.getfixturevalue(runner_name)
    monkeypatch.setattr(
        sys, "argv", ["runner", "--godot", "g", "--runs", runs, "--name", "baseline"]
    )
    with pytest.raises(SystemExit) as exc:
        runner.parse_args()
    assert exc.value.code == 2
    assert "--runs must be at least 1" in capsys.readouterr().err


def test_empty_name_uses_timestamp(desktop):
    """An empty name does not collapse the output path to the kind directory."""
    out = desktop.default_out("desktop", "")
    assert out.parent == desktop.RESULTS_ROOT / "desktop"
    assert STAMP.fullmatch(out.name)
