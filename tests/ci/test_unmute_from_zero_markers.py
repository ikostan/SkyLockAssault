# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep the reload timeout regression covered without booting Godot or a browser."""

import tests.unmute_from_zero_test as unmute_from_zero_test


def test_reload_unmute_has_one_90_second_timeout() -> None:
    """Two engine boots and the filesystem flush need the extended timeout."""
    marks = [
        mark
        for mark in getattr(
            unmute_from_zero_test.test_unmute_from_zero_after_reload_uses_fallback,
            "pytestmark",
            [],
        )
        if mark.name == "timeout"
    ]

    assert len(marks) == 1, "The reload test must have exactly one timeout guard"
    assert marks[0].args == (90,)
    assert marks[0].kwargs == {}


def test_single_boot_unmute_keeps_default_timeout() -> None:
    """The extended budget must stay local to the test that reloads the engine."""
    marks = getattr(
        unmute_from_zero_test.test_unmute_from_zero_restores_last_audible_volume,
        "pytestmark",
        [],
    )

    assert not any(mark.name == "timeout" for mark in marks)
    assert not any(
        mark.name == "timeout"
        for mark in getattr(unmute_from_zero_test, "pytestmark", [])
    ), "A module timeout would also extend the single-boot test"
