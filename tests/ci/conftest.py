# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/conftest.py
"""CI-specific pytest configuration and browser launch arguments."""

import os
import tempfile
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session")
def browser_type_launch_args():
    """Configures Playwright Chromium flags to prevent memory leaks

    and container OOM errors.
    """
    return [
        "--use-gl=angle",
        "--use-angle=swiftshader",
        "--disable-dev-shm-usage",
        "--no-sandbox",
        "--js-flags=--max-old-space-size=2048",
    ]


@pytest.fixture
def repo_tmp():
    """Creates an isolated temporary directory INSIDE the project root.

    Yields a relative POSIX path (e.g. 'tmp_xyz') so WSL bash can easily
    digest it without encountering Windows absolute path translation errors.
    """
    with tempfile.TemporaryDirectory(dir=PROJECT_ROOT) as tmpdir:
        rel_path = os.path.relpath(tmpdir, PROJECT_ROOT).replace("\\", "/")
        yield rel_path
