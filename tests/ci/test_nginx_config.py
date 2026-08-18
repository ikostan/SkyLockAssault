# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_nginx_config.py
"""Structural tests for infra/nginx/default.conf (PR #872).

Nginx config files are not YAML/JSON, so these tests validate the raw text via
targeted, whitespace-tolerant assertions: WASM MIME registration, gzip
compression, and per-location Cache-Control/COOP/COEP headers.
"""

import re
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CONF_PATH = PROJECT_ROOT / "infra" / "nginx" / "default.conf"


@pytest.fixture(scope="module")
def conf_text() -> str:
    """Read and return the raw text content of default.conf."""
    return CONF_PATH.read_text(encoding="utf-8")


def test_config_braces_are_balanced(conf_text: str) -> None:
    """Basic structural sanity check: every '{' must have a matching '}'."""
    assert conf_text.count("{") == conf_text.count("}")
    assert conf_text.count("{") > 0


def test_registers_application_wasm_mime_type(conf_text: str) -> None:
    """Verify custom MIME type mapping is declared for WebAssembly binaries."""
    assert "application/wasm wasm;" in conf_text
    assert "include mime.types;" in conf_text


def test_gzip_compression_enabled_for_wasm_and_static_assets(conf_text: str) -> None:
    """Verify gzip compression directives and MIME types are configured."""
    assert re.search(r"^\s*gzip on;", conf_text, re.MULTILINE)
    assert re.search(r"^\s*gzip_static on;", conf_text, re.MULTILINE)
    assert re.search(r"^\s*gzip_vary on;", conf_text, re.MULTILINE)

    gzip_types_match = re.search(r"gzip_types\s+([^;]+);", conf_text)
    assert gzip_types_match, "gzip_types directive not found"
    gzip_types = gzip_types_match.group(1).split()
    assert "application/wasm" in gzip_types
    assert "application/javascript" in gzip_types
    assert "text/css" in gzip_types
    assert "text/html" in gzip_types


def test_server_level_coop_coep_headers_present(conf_text: str) -> None:
    """Verify top-level server block configures COOP and COEP isolation headers."""
    assert "add_header Cross-Origin-Embedder-Policy 'require-corp';" in conf_text
    assert "add_header Cross-Origin-Opener-Policy 'same-origin';" in conf_text


def test_static_binary_location_sets_long_lived_cache_control(conf_text: str) -> None:
    """Verify .wasm/.pck/.js assets get the 1-hour public cache directive."""
    match = re.search(
        r"location ~\* \\\.\(wasm\|pck\|js\)\$ \{(?P<body>[^}]*)\}",
        conf_text,
    )
    assert match, "Expected location block for .wasm|.pck|.js assets not found"
    body = match.group("body")

    assert 'add_header Cache-Control "public, max-age=3600";' in body
    assert "Cross-Origin-Embedder-Policy 'require-corp'" in body
    assert "Cross-Origin-Opener-Policy 'same-origin'" in body


def test_html_location_sets_revalidation_cache_control(conf_text: str) -> None:
    """Verify HTML entrypoints are always revalidated, never long-cached."""
    match = re.search(
        r"location ~\* \\\.html\$ \{(?P<body>[^}]*)\}",
        conf_text,
    )
    assert match, "Expected location block for .html not found"
    body = match.group("body")

    assert 'add_header Cache-Control "no-cache, must-revalidate";' in body
    assert "Cross-Origin-Embedder-Policy 'require-corp'" in body
    assert "Cross-Origin-Opener-Policy 'same-origin'" in body


def test_root_location_still_serves_index_with_try_files(conf_text: str) -> None:
    """Verify root location block serves index files with standard fallback."""
    match = re.search(r"location / \{(?P<body>[^}]*)\}", conf_text)
    assert match, "Expected root location block not found"
    body = match.group("body")

    assert "root /usr/share/nginx/html;" in body
    assert "index index.html index.htm;" in body
    assert "try_files $uri $uri/ =404;" in body


def test_listens_on_unprivileged_port_8080(conf_text: str) -> None:
    """Verify Nginx server directive binds to unprivileged port 8080."""
    assert re.search(r"^\s*listen 8080;", conf_text, re.MULTILINE)
