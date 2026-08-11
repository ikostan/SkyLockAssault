# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/test_conftest_diagnostics.py
"""Unit tests for conftest diagnostic cleanup helpers."""

from pathlib import Path
from types import SimpleNamespace
from typing import Any, Generator

import pytest

from tests import conftest
from tests.conftest import _cleanup_context_diagnostics


class DummyTracing:
    """Fake tracing object that writes a trace file when stopped with a path."""

    @staticmethod
    def stop(*, path: str | Path | None = None, **_: Any) -> None:
        """Stop tracing and write trace file if path is specified."""
        if path is not None:
            trace_path = Path(path)
            trace_path.parent.mkdir(parents=True, exist_ok=True)
            trace_path.write_text("trace", encoding="utf-8")


class DummyVideo:
    """Fake video handle that manages video file lifecycle."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text("video", encoding="utf-8")

    @staticmethod
    def save_as(path: str | Path) -> None:
        """Save video handle contents to specified destination path."""
        target = Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("saved_video", encoding="utf-8")

    def delete(self) -> None:
        """Delete temporary video file from disk if present."""
        if self.path.exists():
            self.path.unlink()


class DummyPage:
    """Fake Page that records screenshots and exposes a video handle."""

    def __init__(self, video_path: Path) -> None:
        self.video = DummyVideo(video_path)

    @staticmethod
    def screenshot(path: str | Path, **_: Any) -> None:
        """Capture screenshot and write placeholder image to path."""
        screenshot_path = Path(path)
        screenshot_path.parent.mkdir(parents=True, exist_ok=True)
        screenshot_path.write_text("screenshot", encoding="utf-8")


class DummyContext:
    """Fake BrowserContext that exposes a tracing handle and close method."""

    def __init__(self) -> None:
        self.tracing = DummyTracing()
        self.closed = False

    def close(self) -> None:
        """Mark browser context as closed."""
        self.closed = True


def _make_request(
    nodeid: str = "tests/test_demo.py::test_case",
    call_failed: bool | None = None,
    setup_failed: bool | None = None,
) -> Any:
    """Build a minimal stand-in for pytest.FixtureRequest with outcome info."""
    node = SimpleNamespace(nodeid=nodeid)
    if call_failed is not None:
        node.rep_call = SimpleNamespace(failed=call_failed, when="call")
    if setup_failed is not None:
        node.rep_setup = SimpleNamespace(failed=setup_failed, when="setup")
    return SimpleNamespace(node=node)


@pytest.fixture(autouse=True)
def isolate_conftest_state(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> Generator[Path, None, None]:
    """Isolate ARTIFACTS_DIR and reset global _FAILED_NODEIDS state."""
    test_artifacts = tmp_path / "artifacts"
    test_artifacts.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(conftest, "ARTIFACTS_DIR", test_artifacts)
    monkeypatch.setattr(conftest, "_FAILED_NODEIDS", set())
    yield test_artifacts
    conftest._FAILED_NODEIDS.clear()  # noqa: SLF001


def test_failing_test_retains_trace_screenshot_and_video(
    isolate_conftest_state: Path,
) -> None:
    """A failing test should retain trace, screenshot, and video artifacts."""
    artifacts_dir = isolate_conftest_state
    context: Any = DummyContext()
    page_obj: Any = DummyPage(artifacts_dir / "temp_video.webm")
    request = _make_request(call_failed=True)

    _cleanup_context_diagnostics(
        context, page_obj, request, include_module_failures=False
    )

    assert list(artifacts_dir.glob("trace_*.zip")), "Trace artifact missing on failure"
    assert list(artifacts_dir.glob("failure_*.png")), "Screenshot missing on failure"
    assert list(artifacts_dir.glob("video_*.webm")), "Video artifact missing on failure"
    assert context.closed, "Context should be closed"


def test_passing_test_purges_failure_artifacts(
    isolate_conftest_state: Path,
) -> None:
    """A passing test should not produce screenshots or trace archives and should delete video."""
    artifacts_dir = isolate_conftest_state
    context: Any = DummyContext()
    video_file = artifacts_dir / "temp_video.webm"
    page_obj: Any = DummyPage(video_file)
    request = _make_request(call_failed=False)

    _cleanup_context_diagnostics(
        context, page_obj, request, include_module_failures=False
    )

    assert not list(
        artifacts_dir.glob("trace_*.zip")
    ), "Trace should not be saved on pass"
    assert not list(
        artifacts_dir.glob("failure_*.png")
    ), "Screenshot should not be created on pass"
    assert not video_file.exists(), "Video should be deleted on pass"
    assert context.closed, "Context should be closed"


def test_module_level_failure_preserves_module_scoped_diagnostics(
    isolate_conftest_state: Path,
) -> None:
    """A setup or module-level failure should retain traces and videos when include_module_failures=True."""
    artifacts_dir = isolate_conftest_state
    context: Any = DummyContext()
    page_obj: Any = DummyPage(artifacts_dir / "temp_video.webm")
    request = _make_request(setup_failed=True)

    _cleanup_context_diagnostics(
        context, page_obj, request, include_module_failures=True
    )

    assert list(
        artifacts_dir.glob("trace_*.zip")
    ), "Trace should be retained for module setup failure"
    assert list(
        artifacts_dir.glob("video_*.webm")
    ), "Video should be retained for module setup failure"
    assert context.closed, "Context should be closed"
