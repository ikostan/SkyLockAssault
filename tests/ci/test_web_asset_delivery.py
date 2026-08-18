# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_web_asset_delivery.py
"""Tests for the optimized local/CI web asset delivery logic added in PR #872.

``workspace/run_browser_tests.sh`` and ``workspace/run_pipeline.sh`` both embed
an identical inline Python HTTP server (``OptimizedGodotHandler``) that adds
WASM MIME registration and tiered ``Cache-Control`` headers, plus a
pre-test cleanup line that purges stale Playwright failure diagnostics.

Rather than re-implementing that logic (which would test a copy, not the
shipped code), these tests extract the exact snippets from the shell scripts
and exercise them directly:

- The HTTP handler class is ``exec``'d (minus the socket-binding bootstrap) so
  ``end_headers()`` can be unit tested against a bare instance without opening
  any network sockets.
- The artifact-cleanup ``rm -f`` line is executed via ``bash`` in an isolated
  temporary directory to confirm it purges only diagnostic artifacts.
"""

import http.server
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

_SERVER_SNIPPET_RE = re.compile(r'python3 -c "\n(.*?)\n"\s*&', re.DOTALL)
_CLEANUP_LINE_RE = re.compile(
    r'^rm -f "\$PROJECT_DIR".*artifacts/trace_\*\.zip.*$', re.MULTILINE
)


def _extract_handler_class_source(script_path: Path) -> str:
    """Extract just the class definitions from the embedded python3 -c snippet.

    The socket-binding bootstrap (``with ThreadedHTTPServer(...) as httpd:``)
    is intentionally excluded so the snippet can be exec'd without opening a
    listening socket.
    """
    text = script_path.read_text(encoding="utf-8")
    match = _SERVER_SNIPPET_RE.search(text)
    assert match, f"Could not locate embedded python server snippet in {script_path}"
    code = match.group(1)
    boundary = code.index("with ThreadedHTTPServer")
    return code[:boundary]


def _load_handler_class(script_path: Path):
    """Exec the extracted server snippet and return classes and modules."""
    namespace: dict = {}
    exec(
        _extract_handler_class_source(script_path), namespace
    )  # skipcq: PTC-W0034, PYL-W0122
    return (
        namespace["OptimizedGodotHandler"],
        namespace["mimetypes"],
        namespace["ThreadedHTTPServer"],
    )


def _headers_for_path(handler_cls, path: str) -> list[tuple[str, str]]:
    """Instantiate a bare handler and capture headers sent by end_headers()."""
    handler = handler_cls.__new__(handler_cls)
    handler.path = path
    handler.send_header = MagicMock()

    with patch.object(http.server.BaseHTTPRequestHandler, "end_headers", MagicMock()):
        handler.end_headers()

    return [call.args for call in handler.send_header.call_args_list]


@pytest.fixture(params=SCRIPT_PATHS, ids=lambda p: p.name)
def script_path(request: pytest.FixtureRequest) -> Path:
    """Parametrized fixture providing path to scripts embedding the HTTP server."""
    return request.param


def test_script_file_exists(script_path: Path) -> None:
    """Verify the target pipeline script exists on disk."""
    assert script_path.is_file()


def test_wasm_mime_type_registered(script_path: Path) -> None:
    """Verify application/wasm MIME mapping is registered in the embedded server."""
    _, mimetypes_module, _ = _load_handler_class(script_path)

    guessed_type, _ = mimetypes_module.guess_type("game.wasm")

    assert guessed_type == "application/wasm"


@pytest.mark.parametrize(
    "path, expected_cache_control",
    [
        ("/index.js", "public, max-age=3600"),
        ("/game.wasm", "public, max-age=3600"),
        ("/game.pck", "public, max-age=3600"),
        ("/index.html", "no-cache, must-revalidate"),
        ("/", "no-cache, must-revalidate"),
        ("/assets/icon.png", "public, max-age=1800"),
        ("/styles/main.css", "public, max-age=1800"),
    ],
)
def test_handler_sets_expected_cache_control_by_asset_type(
    script_path: Path, path: str, expected_cache_control: str
) -> None:
    """Verify appropriate Cache-Control header is attached based on asset extension."""
    handler_cls, _, _ = _load_handler_class(script_path)

    headers = _headers_for_path(handler_cls, path)

    assert ("Cache-Control", expected_cache_control) in headers


def test_handler_strips_query_string_before_cache_classification(
    script_path: Path,
) -> None:
    """A cache-busting query string on a .wasm request must not defeat caching."""
    handler_cls, _ = _load_handler_class(script_path)

    headers = _headers_for_path(handler_cls, "/game.wasm?v=123&nocache=1")

    assert ("Cache-Control", "public, max-age=3600") in headers


def test_handler_sets_coop_and_coep_headers(script_path: Path) -> None:
    """Verify COOP and COEP isolation headers are applied to HTTP responses."""
    handler_cls, _, _ = _load_handler_class(script_path)

    headers = _headers_for_path(handler_cls, "/index.html")

    assert ("Cross-Origin-Opener-Policy", "same-origin") in headers
    assert ("Cross-Origin-Embedder-Policy", "require-corp") in headers


def test_server_uses_threaded_http_server_with_daemon_threads(
    script_path: Path,
) -> None:
    """Verify ThreadedHTTPServer enables daemon threads and address reuse."""
    _, _, threaded_server_cls = _load_handler_class(script_path)

    assert threaded_server_cls.daemon_threads is True
    assert threaded_server_cls.allow_reuse_address is True


def _extract_cleanup_line(script_path: Path) -> str:
    """Extract artifact cleanup bash command from the script."""
    text = script_path.read_text(encoding="utf-8")
    match = _CLEANUP_LINE_RE.search(text)
    assert match, f"Could not locate artifact cleanup line in {script_path}"
    return match.group(0)


def test_cleanup_line_present_before_test_execution(script_path: Path) -> None:
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
    line = _extract_cleanup_line(script_path)
    artifacts_dir = tmp_path / "artifacts"
    artifacts_dir.mkdir()

    stale_files = ["trace_test.zip", "failure_test.png", "video_test.webm"]
    keep_files = ["junit.xml", "metrics_baseline.json", "v8_coverage_test.json"]
    for name in stale_files + keep_files:
        (artifacts_dir / name).write_text("placeholder")

    result = subprocess.run(
        ["bash", "-c", f'PROJECT_DIR="{tmp_path}"\n{line}'],
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
    line = _extract_cleanup_line(script_path)
    (tmp_path / "artifacts").mkdir()

    result = subprocess.run(
        ["bash", "-c", f'PROJECT_DIR="{tmp_path}"\n{line}'],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )

    assert result.returncode == 0
