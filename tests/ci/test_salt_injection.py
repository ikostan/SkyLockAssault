"""
Test suite for the CI/CD salt injection pipeline.

Validates that the master bash script correctly replaces placeholder strings
in GDScript files with various complex secrets, ensuring that escape sequences
and special sed characters do not break the final game code.
"""

import os
import subprocess
import pytest
import tempfile

# Dynamically locate the project root
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
INJECT_SCRIPT_REL = ".github/scripts/inject_salt.sh"


@pytest.fixture
def repo_tmp():
    """
    Creates an isolated temporary directory INSIDE the project root.
    Yields a relative POSIX path (e.g. 'tmp_xyz') so WSL bash can easily digest
    it without encountering Windows 'C:\\...' absolute path translation errors.
    """
    with tempfile.TemporaryDirectory(dir=PROJECT_ROOT) as tmpdir:
        # Get relative path and force forward slashes for bash
        rel_path = os.path.relpath(tmpdir, PROJECT_ROOT).replace("\\", "/")
        yield rel_path


def run_injection(file_path, raw_secret):
    """
    Executes the single-source-of-truth bash script using relative paths.
    Returns the CompletedProcess object for assertion checking.
    """
    env = os.environ.copy()
    env["PRODUCTION_SALT"] = raw_secret

    if "WSLENV" in env:
        env["WSLENV"] += ":PRODUCTION_SALT/u"
    else:
        env["WSLENV"] = "PRODUCTION_SALT/u"

    script_abs_path = os.path.join(PROJECT_ROOT, INJECT_SCRIPT_REL)
    assert os.path.exists(script_abs_path), f"Master inject script not found at {script_abs_path}"

    return subprocess.run(
        ["bash", INJECT_SCRIPT_REL, str(file_path)],
        env=env,
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8" # CRITICAL: Prevents Windows crash when bash prints UTF-8 emojis
    )


@pytest.mark.parametrize("scenario, raw_secret, expected_salt", [
    ("standard", 'T3st_S@lt!_2026#"\\', 'T3st_S@lt!_2026#\\"\\\\'),
    ("sed_special", "My|Secret&Salt", "My|Secret&Salt"),
    # FIX: Account for the script correctly escaping backslashes to protect sed/GDScript
    ("regex_tokens", r"\1 \2 $HOME", r"\\1 \\2 $HOME"),
    ("utf8_unicode", "пароль_日本語_🔒", "пароль_日本語_🔒")
])
def test_injection_values(repo_tmp, scenario, raw_secret, expected_salt):
    """
    Parametrized test covering standard strings, bash/sed delimiters,
    backreferences, and UTF-8 locale handling.
    """
    dummy_rel = f"{repo_tmp}/dummy_{scenario}.gd"
    dummy_abs = os.path.join(PROJECT_ROOT, dummy_rel)

    with open(dummy_abs, "w", encoding="utf-8") as f:
        f.write('func _get_encryption_key() -> String:\n\tvar salt: String = "CI_INJECT_SALT_HERE"\n\treturn salt\n')

    result = run_injection(dummy_rel, raw_secret)

    assert result.returncode == 0, f"Injection failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    with open(dummy_abs, "r", encoding="utf-8") as f:
        content = f.read()
    assert f'var salt: String = "{expected_salt}"' in content


def test_injection_multiple_placeholders(repo_tmp):
    """Ensures global replacement updates all occurrences, leaving no partial leftovers."""
    dummy_rel = f"{repo_tmp}/dummy_multi.gd"
    dummy_abs = os.path.join(PROJECT_ROOT, dummy_rel)

    with open(dummy_abs, "w", encoding="utf-8") as f:
        f.write(
            'extends Node\n'
            'var security = {"save_salt": "CI_INJECT_SALT_HERE"}\n'
            'var another = {"save_salt": "CI_INJECT_SALT_HERE"}\n'
        )

    result = run_injection(dummy_rel, "multi-placeholder-salt")

    assert result.returncode == 0
    with open(dummy_abs, "r", encoding="utf-8") as f:
        content = f.read()
    assert "CI_INJECT_SALT_HERE" not in content
    assert content.count("multi-placeholder-salt") == 2


def test_injection_missing_placeholder(repo_tmp):
    """A missing placeholder is a safe no-op. The file must remain untouched."""
    dummy_rel = f"{repo_tmp}/dummy_missing.gd"
    dummy_abs = os.path.join(PROJECT_ROOT, dummy_rel)
    original_content = 'extends Node\nvar security = {"save_salt": "unchanged"}\n'

    with open(dummy_abs, "w", encoding="utf-8") as f:
        f.write(original_content)

    result = run_injection(dummy_rel, "missing-placeholder-salt")

    assert result.returncode == 0
    with open(dummy_abs, "r", encoding="utf-8") as f:
        content = f.read()
    assert content == original_content


def test_injection_empty_secret(repo_tmp):
    """Ensures the bash script guard catches an empty environment variable and aborts."""
    dummy_rel = f"{repo_tmp}/dummy_empty.gd"
    dummy_abs = os.path.join(PROJECT_ROOT, dummy_rel)

    with open(dummy_abs, "w", encoding="utf-8") as f:
        f.write('var salt = "CI_INJECT_SALT_HERE"\n')

    result = run_injection(dummy_rel, "")

    assert result.returncode != 0
    assert "environment variable is not set" in result.stdout


def test_injection_filename_with_spaces(repo_tmp):
    """Verifies bash variable quoting robustness against argument splitting."""
    dummy_rel = f"{repo_tmp}/dummy globals spaces.gd"
    dummy_abs = os.path.join(PROJECT_ROOT, dummy_rel)

    with open(dummy_abs, "w", encoding="utf-8") as f:
        f.write('var salt = "CI_INJECT_SALT_HERE"\n')

    result = run_injection(dummy_rel, "space-test-secret")

    assert result.returncode == 0
    with open(dummy_abs, "r", encoding="utf-8") as f:
        content = f.read()
    assert "space-test-secret" in content


def test_injection_non_existent_file():
    """Ensures script fails fast with a deterministic error on bad paths."""
    result = run_injection("this_file_does_not_exist.gd", "non-existent-file-salt")
    assert result.returncode != 0
    assert "does not exist" in result.stdout


def test_injection_multiline_secret(repo_tmp):
    """Validates that multiline secrets safely fail instead of silently corrupting."""
    dummy_rel = f"{repo_tmp}/dummy_multiline.gd"
    dummy_abs = os.path.join(PROJECT_ROOT, dummy_rel)

    with open(dummy_abs, "w", encoding="utf-8") as f:
        f.write('var salt = "CI_INJECT_SALT_HERE"\n')

    result = run_injection(dummy_rel, "line1\nline2")

    # sed typically fails when unescaped newlines are passed in the replacement string
    assert result.returncode != 0
    assert "unterminated `s' command" in result.stderr


def test_idempotency(repo_tmp):
    """Running the injection twice should not cause corruption or double-escaping."""
    dummy_rel = f"{repo_tmp}/dummy_idempotent.gd"
    dummy_abs = os.path.join(PROJECT_ROOT, dummy_rel)

    with open(dummy_abs, "w", encoding="utf-8") as f:
        f.write('var salt = "CI_INJECT_SALT_HERE"\n')

    # First run
    run_injection(dummy_rel, "idempotent-secret")

    # Second run
    result = run_injection(dummy_rel, "idempotent-secret")

    assert result.returncode == 0
    with open(dummy_abs, "r", encoding="utf-8") as f:
        content = f.read()
    assert content.count("idempotent-secret") == 1
