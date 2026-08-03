# Copyright (C) 2025 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/conftest.py
"""CI-specific pytest configuration and browser launch arguments."""

import os
import tempfile
from pathlib import Path

import pytest

from tests.test_utils import ARTIFACTS_DIR, PROJECT_ROOT


@pytest.fixture(scope="session")
def browser_type_launch_args():
    """Configures Playwright Chromium flags to prevent memory leaks

    and container OOM errors.
    """
    return {
        "args": [
            "--use-gl=angle",
            "--use-angle=swiftshader",
            "--disable-dev-shm-usage",
            "--no-sandbox",
            "--js-flags=--max-old-space-size=2048",
        ]
    }


@pytest.fixture
def repo_tmp():
    """Creates an isolated temporary directory INSIDE artifacts/.

    Yields a relative POSIX path (e.g. 'artifacts/tmp_xyz') so WSL bash can easily
    digest it without encountering Windows absolute path translation errors while
    keeping the project root pristine.
    """
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=ARTIFACTS_DIR) as tmpdir:
        rel_path = os.path.relpath(tmpdir, PROJECT_ROOT).replace("\\", "/")
        yield rel_path
