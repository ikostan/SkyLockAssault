# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_docker_compose_config.py
"""Structural tests for infra/docker-compose.yml (PR #872).

Validates the volume mount now points at the thread-off Godot web export and
that the copyright header was refreshed alongside the change.
"""

from pathlib import Path
from typing import Any

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[2]
COMPOSE_PATH = PROJECT_ROOT / "infra" / "docker-compose.yml"


@pytest.fixture(scope="module")
def compose_config() -> dict[str, Any]:
    """Parse infra/docker-compose.yml once for all tests in this module."""
    with open(COMPOSE_PATH, encoding="utf-8") as f:
        return yaml.safe_load(f)


@pytest.fixture(scope="module")
def compose_text() -> str:
    """Raw text of infra/docker-compose.yml, for comment/header assertions."""
    return COMPOSE_PATH.read_text(encoding="utf-8")


def test_web_server_service_exists(compose_config: dict[str, Any]) -> None:
    """Verify godot_web_server service definition is declared in compose config."""
    assert "godot_web_server" in compose_config["services"]


def test_volume_mounts_thread_off_export_directory(
    compose_config: dict[str, Any],
) -> None:
    """Verify the html volume now serves export/web_thread_off, not export/web."""
    volumes = compose_config["services"]["godot_web_server"]["volumes"]

    assert "../export/web_thread_off:/usr/share/nginx/html:ro" in volumes


def test_volume_no_longer_mounts_legacy_export_web_directory(
    compose_config: dict[str, Any],
) -> None:
    """Regression guard: the old export/web (non thread-off) mount must be gone."""
    volumes = compose_config["services"]["godot_web_server"]["volumes"]

    assert "../export/web:/usr/share/nginx/html:ro" not in volumes


def test_nginx_conf_directory_still_mounted(compose_config: dict[str, Any]) -> None:
    """Ensure the unrelated nginx config mount survived the edit untouched."""
    volumes = compose_config["services"]["godot_web_server"]["volumes"]

    assert "./nginx:/etc/nginx/conf.d" in volumes


def test_copyright_header_updated_to_2025_2026(compose_text: str) -> None:
    """Verify compose file top comment reflects updated 2025-2026 copyright year."""
    assert "# Copyright (C) 2025-2026 Egor Kostan" in compose_text
    assert "# Copyright (C) 2025 Egor Kostan" not in compose_text
