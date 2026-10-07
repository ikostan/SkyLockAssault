# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/ci/test_strip_gdunit4_coverage.py

"""
Tests for .github/scripts/strip_gdunit4_coverage.py (Issue #1003).

The strip step edits project.godot with line and regex rules so the GDUnit4 CI
job can run without the gdUnit4-coverage addon. These tests pin down each rule
directly instead of relying on the GDUnit4 job to fail when one breaks.
"""

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = PROJECT_ROOT / ".github" / "scripts" / "strip_gdunit4_coverage.py"

_spec = importlib.util.spec_from_file_location("strip_gdunit4_coverage", SCRIPT_PATH)
strip_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(strip_mod)

GDUNIT = '"res://addons/gdUnit4/plugin.cfg"'
COV = '"res://addons/gdunit4_coverage/plugin.cfg"'
GUT = '"res://addons/gut/plugin.cfg"'
HOOK = '"res://addons/gdunit4_coverage/GdUnitCoverageTestSessionHook.gd": true'
OTHER_HOOK = '"res://test/hooks/OtherHook.gd": true'

# Mirrors the coverage-related parts of the committed project.godot.
REALISTIC_PROJECT = f"""\
[editor_plugins]

enabled=PackedStringArray({GDUNIT}, {COV}, {GUT})

[game]

security/save_salt="dev_fallback_salt"

[gdunit4]

settings/test/test_discovery=true
hooks/session_hooks=Dictionary[String, bool]({{
{HOOK}
}})

[gdunit4_coverage]

runner/gdcov_path="./bin/gdcov-4.7-stable.exe"

[input]

ui_focus_next={{
"deadzone": 0.5
}}
"""


def run_cli(config: Path) -> subprocess.CompletedProcess[str]:
    """Run the script as CI does, against an explicit file path."""
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    return subprocess.run(
        [sys.executable, str(SCRIPT_PATH), str(config)],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
        encoding="utf-8",
        check=False,
    )


# --- PackedStringArray (editor_plugins/enabled) ---


@pytest.mark.parametrize(
    ("entries", "expected"),
    [
        ([COV, GDUNIT, GUT], [GDUNIT, GUT]),  # first
        ([GDUNIT, COV, GUT], [GDUNIT, GUT]),  # middle
        ([GDUNIT, GUT, COV], [GDUNIT, GUT]),  # last
        ([COV], []),  # only entry
    ],
    ids=["first", "middle", "last", "only"],
)
def test_removes_plugin_from_packed_string_array(entries, expected):
    """The plugin path is removed wherever it sits, leaving valid separators."""
    text = f"[editor_plugins]\n\nenabled=PackedStringArray({', '.join(entries)})\n"

    result = strip_mod.strip_coverage(text)

    assert f"enabled=PackedStringArray({', '.join(expected)})" in result
    assert "gdunit4_coverage" not in result


# --- Session hook dictionary entries ---


def test_removes_session_hook_when_only_entry():
    """The real-world shape: the coverage hook is the dictionary's only entry."""
    text = (
        "[gdunit4]\n\nhooks/session_hooks=Dictionary[String, bool]({\n" f"{HOOK}\n}})\n"
    )

    result = strip_mod.strip_coverage(text)

    assert "hooks/session_hooks=Dictionary[String, bool]({\n})" in result


def test_removes_session_hook_and_dangling_comma_when_last_entry():
    """Removing the last entry must not leave a trailing comma before '}'."""
    text = (
        "[gdunit4]\n\nhooks/session_hooks=Dictionary[String, bool]({\n"
        f"{OTHER_HOOK},\n{HOOK}\n}})\n"
    )

    result = strip_mod.strip_coverage(text)

    assert f"({{\n{OTHER_HOOK}\n}})" in result
    assert f"{OTHER_HOOK}," not in result


def test_removes_session_hook_when_first_entry():
    """Removing the first entry keeps the following entry intact."""
    text = (
        "[gdunit4]\n\nhooks/session_hooks=Dictionary[String, bool]({\n"
        f"{HOOK},\n{OTHER_HOOK}\n}})\n"
    )

    result = strip_mod.strip_coverage(text)

    assert f"({{\n{OTHER_HOOK}\n}})" in result


# --- [gdunit4_coverage] section ---


def test_removes_whole_coverage_section_and_keeps_next_section():
    """Every line from [gdunit4_coverage] up to the next header is dropped."""
    text = (
        "[gdunit4_coverage]\n\n"
        'runner/gdcov_path="./bin/gdcov.exe"\n'
        "runner/extra=true\n\n"
        "[input]\n\nkeep_me=1\n"
    )

    result = strip_mod.strip_coverage(text)

    assert "[gdunit4_coverage]" not in result
    assert "gdcov_path" not in result
    assert "runner/extra" not in result
    assert "[input]\n\nkeep_me=1" in result


def test_removes_coverage_section_at_end_of_file():
    """A trailing [gdunit4_coverage] section with no following header is removed."""
    text = '[game]\n\nkeep_me=1\n\n[gdunit4_coverage]\n\nrunner/x="y"\n'

    result = strip_mod.strip_coverage(text)

    assert "[gdunit4_coverage]" not in result
    assert "runner/x" not in result
    assert "keep_me=1" in result


def test_keeps_similarly_named_gdunit4_section():
    """[gdunit4] must not be mistaken for [gdunit4_coverage]."""
    text = "[gdunit4]\n\nsettings/test/test_discovery=true\n"

    assert strip_mod.strip_coverage(text) == text


# --- Full file ---


def test_realistic_project_file_is_fully_cleaned():
    """All three reference kinds are removed and unrelated config survives."""
    result = strip_mod.strip_coverage(REALISTIC_PROJECT)

    assert "gdunit4_coverage" not in result
    assert f"enabled=PackedStringArray({GDUNIT}, {GUT})" in result
    assert 'security/save_salt="dev_fallback_salt"' in result
    assert "settings/test/test_discovery=true" in result
    assert 'ui_focus_next={\n"deadzone": 0.5\n}' in result


def test_strip_is_idempotent():
    """Running the strip twice gives the same result as running it once."""
    once = strip_mod.strip_coverage(REALISTIC_PROJECT)

    assert strip_mod.strip_coverage(once) == once


# --- Failure path ---


def test_unhandled_reference_raises_with_leftover_lines():
    """A reference no rule covers is reported rather than silently kept."""
    text = '[gdunit4]\n\nsome/setting="res://addons/gdunit4_coverage/x.gd"\n'

    with pytest.raises(strip_mod.UnhandledReferenceError) as exc_info:
        strip_mod.strip_coverage(text)

    assert exc_info.value.leftover == [
        'some/setting="res://addons/gdunit4_coverage/x.gd"'
    ]


# --- CLI behaviour (as invoked by gdunit4_tests.yml) ---


def test_cli_rewrites_file_and_exits_zero(tmp_path):
    """The CLI cleans the file in place and reports success."""
    config = tmp_path / "project.godot"
    config.write_text(REALISTIC_PROJECT, encoding="utf-8")

    result = run_cli(config)

    assert result.returncode == 0, result.stdout + result.stderr
    assert "gdunit4_coverage" not in config.read_text(encoding="utf-8")


def test_cli_fails_on_unhandled_reference_and_leaves_file_untouched(tmp_path):
    """The CLI exits 1 with a GitHub error annotation and does not write."""
    original = '[gdunit4]\n\nsome/setting="res://addons/gdunit4_coverage/x.gd"\n'
    config = tmp_path / "project.godot"
    config.write_text(original, encoding="utf-8")

    result = run_cli(config)

    assert result.returncode == 1
    assert "::error file=" in result.stdout
    assert "some/setting=" in result.stdout
    assert config.read_text(encoding="utf-8") == original
