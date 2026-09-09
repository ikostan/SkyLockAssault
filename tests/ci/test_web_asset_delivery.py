# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_web_asset_delivery.py
"""Tests for the optimized local/CI web asset delivery logic added in PR #872.

Validates the HTTP server (``OptimizedGodotHandler``) in
``.github/scripts/serve_web_export.py`` and the pre-test artifact cleanup and
server invocation in ``workspace/run_browser_tests.sh`` and
``workspace/run_pipeline.sh``.
"""

import http.server
import importlib.util
import re
import subprocess
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[2]

SCRIPT_PATHS = [
    PROJECT_ROOT / "workspace" / "run_browser_tests.sh",
    PROJECT_ROOT / "workspace" / "run_pipeline.sh",
]

SERVE_SCRIPT_PATH = PROJECT_ROOT / ".github" / "scripts" / "serve_web_export.py"
_CLEANUP_LINE_RE = re.compile(
    r'^rm -f "\$PROJECT_DIR".*artifacts/trace_\*\.zip.*$', re.MULTILINE
)


def _can_run_bash() -> bool:
    """Check if a functioning bash shell is available in current environment."""
    try:
        res = subprocess.run(
            ["bash", "-c", "echo ok"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        return res.returncode == 0 and res.stdout.strip() == "ok"
    except Exception:  # noqa: BLE001
        return False


def _load_handler_class():
    """Load OptimizedGodotHandler and ThreadedHTTPServer from serve_web_export.py."""
    spec = importlib.util.spec_from_file_location("serve_web_export", SERVE_SCRIPT_PATH)
    assert spec and spec.loader, f"Could not load spec for {SERVE_SCRIPT_PATH}"
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return (
        mod.OptimizedGodotHandler,
        mod.mimetypes,
        mod.ThreadedHTTPServer,
    )


def _headers_for_path(handler_cls, path: str) -> list[tuple[str, str]]:
    """Instantiate a bare handler and capture headers sent by end_headers()."""
    handler = handler_cls.__new__(handler_cls)
    handler.path = path
    handler.send_header = MagicMock()

    with patch.object(
        http.server.BaseHTTPRequestHandler, "end_headers", MagicMock()
    ) as end_headers_mock:
        handler.end_headers()
        end_headers_mock.assert_called_once()

    return [call.args for call in handler.send_header.call_args_list]


@pytest.fixture(params=SCRIPT_PATHS, ids=lambda p: p.name)
def script_path(request: pytest.FixtureRequest) -> Path:
    """Parametrized fixture providing path to scripts embedding the HTTP server."""
    return request.param


# ==============================================================================
# HTTP Server Unit Tests (serve_web_export.py)
# ==============================================================================


def test_serve_script_file_exists() -> None:
    """Verify the standalone serve_web_export.py script exists on disk."""
    assert SERVE_SCRIPT_PATH.is_file()


def test_wasm_mime_type_registered() -> None:
    """Verify application/wasm MIME mapping is registered in the embedded server."""
    _, mimetypes_module, _ = _load_handler_class()

    guessed_type, _ = mimetypes_module.guess_type("game.wasm")

    assert guessed_type == "application/wasm"


@pytest.mark.parametrize(
    "path, expected_cache_control",
    [
        ("/index.js", "public, max-age=3600"),
        ("/game.wasm", "public, max-age=3600"),
        ("/game.pck", "public, max-age=3600"),
        ("/styles/main.css", "public, max-age=3600"),
        ("/index.html", "no-cache, must-revalidate"),
        ("/", "no-cache, must-revalidate"),
        ("/assets/icon.png", "public, max-age=1800"),
    ],
)
def test_handler_sets_expected_cache_control_by_asset_type(
    path: str, expected_cache_control: str
) -> None:
    """Verify appropriate Cache-Control header is attached based on asset extension."""
    handler_cls, _, _ = _load_handler_class()

    headers = _headers_for_path(handler_cls, path)

    assert ("Cache-Control", expected_cache_control) in headers


def test_handler_strips_query_string_before_cache_classification() -> None:
    """A cache-busting query string on a .wasm request must not defeat caching."""
    handler_cls, _, _ = _load_handler_class()

    headers = _headers_for_path(handler_cls, "/game.wasm?v=123&nocache=1")

    assert ("Cache-Control", "public, max-age=3600") in headers


def test_handler_sets_coop_and_coep_headers() -> None:
    """Verify COOP and COEP isolation headers are applied to HTTP responses."""
    handler_cls, _, _ = _load_handler_class()

    headers = _headers_for_path(handler_cls, "/index.html")

    assert ("Cross-Origin-Opener-Policy", "same-origin") in headers
    assert ("Cross-Origin-Embedder-Policy", "require-corp") in headers


def test_server_uses_threaded_http_server_with_daemon_threads() -> None:
    """Verify ThreadedHTTPServer enables daemon threads and address reuse."""
    _, _, threaded_server_cls = _load_handler_class()

    assert threaded_server_cls.daemon_threads is True
    assert threaded_server_cls.allow_reuse_address is True


# ==============================================================================
# Workspace Script Tests (run_browser_tests.sh & run_pipeline.sh)
# ==============================================================================


def test_script_file_exists(script_path: Path) -> None:
    """Verify the target pipeline script exists on disk."""
    assert script_path.is_file()


def test_script_invokes_serve_web_export(script_path: Path) -> None:
    """Verify the shell script executes serve_web_export.py."""
    content = script_path.read_text(encoding="utf-8")
    assert "serve_web_export.py" in content


def _extract_cleanup_line(script_path: Path) -> str:
    """Extract artifact cleanup bash command from the script."""
    text = script_path.read_text(encoding="utf-8").replace("\r\n", "\n")
    match = _CLEANUP_LINE_RE.search(text)
    assert match, f"Could not locate artifact cleanup line in {script_path}"
    return match.group(0)


def test_cleanup_line_present_before_test_execution(script_path: Path) -> None:
    """Verify cleanup command is present before test execution with true guard."""
    line = _extract_cleanup_line(script_path)

    assert "trace_*.zip" in line
    assert "failure_*.png" in line
    assert "video_*.webm" in line
    # Failures must not abort the script (guarded with `|| true`).
    assert line.rstrip().endswith("|| true")


def test_cleanup_line_removes_only_diagnostic_artifacts(
    script_path: Path, tmp_path: Path
) -> None:
    """Run the exact extracted cleanup line and verify selective deletion."""
    if not _can_run_bash():
        pytest.skip("Functional bash interpreter is not available on this platform")

    line = _extract_cleanup_line(script_path)
    artifacts_dir = tmp_path / "artifacts"
    artifacts_dir.mkdir()

    stale_files = ["trace_test.zip", "failure_test.png", "video_test.webm"]
    keep_files = ["junit.xml", "metrics_baseline.json", "v8_coverage_test.json"]
    for name in stale_files + keep_files:
        (artifacts_dir / name).write_text("placeholder")

    posix_tmp_path = tmp_path.as_posix()
    result = subprocess.run(
        ["bash", "-c", f'PROJECT_DIR="{posix_tmp_path}"\n{line}'],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )

    assert result.returncode == 0
    remaining = {p.name for p in artifacts_dir.iterdir()}
    assert remaining == set(keep_files)


def test_cleanup_line_is_a_safe_noop_when_artifacts_dir_is_empty(
    script_path: Path, tmp_path: Path
) -> None:
    """The `|| true` guard means a missing/empty artifacts dir must not fail."""
    if not _can_run_bash():
        pytest.skip("Functional bash interpreter is not available on this platform")

    line = _extract_cleanup_line(script_path)
    (tmp_path / "artifacts").mkdir()

    posix_tmp_path = tmp_path.as_posix()
    result = subprocess.run(
        ["bash", "-c", f'PROJECT_DIR="{posix_tmp_path}"\n{line}'],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )

    assert result.returncode == 0
