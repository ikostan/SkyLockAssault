# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_reset_audio_flow_markers.py
"""Regression test ensuring reset_audio_flow_test keeps its pytest-timeout guard.

PR #872 added ``@pytest.mark.timeout(90)`` to ``test_reset_flow`` so that a hung
Godot WASM reset flow cannot stall CI indefinitely. This test statically verifies
the marker (and its argument) is present without needing a live browser/page.
"""

import tests.reset_audio_flow_test as reset_audio_flow_test


def _get_marker(func, name: str):
    """Return the first pytest Mark with the given name attached to func, if any."""
    for mark in getattr(func, "pytestmark", []):
        if mark.name == name:
            return mark
    return None


def test_test_reset_flow_has_timeout_marker():
    """Verify test_reset_flow is decorated with @pytest.mark.timeout."""
    marker = _get_marker(reset_audio_flow_test.test_reset_flow, "timeout")

    assert marker is not None, "test_reset_flow is missing the timeout marker"


def test_test_reset_flow_timeout_value_is_90_seconds():
    """Verify the configured timeout budget matches the PR's intended value."""
    marker = _get_marker(reset_audio_flow_test.test_reset_flow, "timeout")

    assert marker is not None
    assert marker.args == (90,)
    assert marker.kwargs == {}