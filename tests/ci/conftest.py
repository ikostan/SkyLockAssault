# tests/ci/conftest.py
import os
import tempfile

import pytest

# Dynamically locate the project root relative to this file
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


@pytest.fixture
def repo_tmp():
    """
    Creates an isolated temporary directory INSIDE the project root.
    Yields a relative POSIX path (e.g. 'tmp_xyz') so WSL bash can easily digest
    it without encountering Windows 'C:\\...' absolute path translation errors.
    """
    with tempfile.TemporaryDirectory(dir=PROJECT_ROOT) as tmpdir:
        rel_path = os.path.relpath(tmpdir, PROJECT_ROOT).replace("\\", "/")
        yield rel_path
