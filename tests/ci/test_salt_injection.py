"""
Test suite for the CI/CD salt injection pipeline.

Validates that the master bash script correctly replaces placeholder strings
in GDScript files with various complex secrets, ensuring that escape sequences
and special sed characters do not break the final game code.
"""

import os
import subprocess
from pathlib import Path

import pytest

# Dynamically locate the project root
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
INJECT_SCRIPT_REL = ".github/scripts/inject_salt.sh"


def run_injection(file_path, raw_secret):
    """
    Executes the single-source-of-truth bash script using relative paths.
    Returns the CompletedProcess object for assertion checking.
    """
    env = os.environ.copy()
    env["PRODUCTION_SALT"] = raw_secret

    # NEW: If None is passed, simulate a completely missing/unset environment variable
    if raw_secret is None:
        env.pop("PRODUCTION_SALT", None)
    else:
        env["PRODUCTION_SALT"] = raw_secret

    if "WSLENV" in env:
        env["WSLENV"] += ":PRODUCTION_SALT/u"
    else:
        env["WSLENV"] = "PRODUCTION_SALT/u"

    script_abs_path = os.path.join(PROJECT_ROOT, INJECT_SCRIPT_REL)
    assert os.path.exists(
        script_abs_path
    ), f"Master inject script not found at {script_abs_path}"

    return subprocess.run(
        ["bash", INJECT_SCRIPT_REL, str(file_path)],
        env=env,
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=10,
        check=False,  # Tells the linter: "I am intentionally handling exit codes manually"
    )


@pytest.mark.parametrize(
    "scenario, raw_secret, expected_salt",
    [
        ("standard", 'T3st_S@lt!_2026#"\\', 'T3st_S@lt!_2026#\\"\\\\'),
        ("sed_special", "My|Secret&Salt", "My|Secret&Salt"),
        ("regex_tokens", r"\1 \2 $HOME", r"\\1 \\2 $HOME"),
        ("utf8_unicode", "пароль_日本語_🔒", "пароль_日本語_🔒"),
        (
            "forward_slash",
            "path/to/my/secret",
            "path/to/my/secret",
        ),  # Ensures forward slashes don't break sed
    ],
)
def test_injection_values(repo_tmp, scenario, raw_secret, expected_salt):
    """
    Parametrized test covering standard strings, bash/sed delimiters,
    backreferences, UTF-8 locale handling, and path-like slashes.
    """
    dummy_rel = f"{repo_tmp}/dummy_{scenario}.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    dummy_abs.write_text(
        'func _get_encryption_key() -> String:\n\tvar salt: String = "CI_INJECT_SALT_HERE"\n\treturn salt\n',
        encoding="utf-8",
    )

    result = run_injection(dummy_rel, raw_secret)

    assert (
        result.returncode == 0
    ), f"Injection failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    content = dummy_abs.read_text(encoding="utf-8")
    assert f'var salt: String = "{expected_salt}"' in content

    # Verifies sed did not leave behind macOS/Linux .bak or temp file artifacts
    files_in_dir = list(dummy_abs.parent.iterdir())
    unexpected = [f for f in files_in_dir if f.name != dummy_abs.name]
    assert (
        not unexpected
    ), f"Artifact pollution detected. Unexpected files found: {unexpected}"


def test_injection_multiple_placeholders(repo_tmp):
    """Ensures global replacement updates all occurrences, leaving no partial leftovers."""
    dummy_rel = f"{repo_tmp}/dummy_multi.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    dummy_abs.write_text(
        "extends Node\n"
        'var security = {"save_salt": "CI_INJECT_SALT_HERE"}\n'
        'var another = {"save_salt": "CI_INJECT_SALT_HERE"}\n',
        encoding="utf-8",
    )

    result = run_injection(dummy_rel, "multi-placeholder-salt")

    assert result.returncode == 0
    content = dummy_abs.read_text(encoding="utf-8")
    assert "CI_INJECT_SALT_HERE" not in content
    assert content.count("multi-placeholder-salt") == 2


def test_injection_multiple_placeholders_same_line(repo_tmp):
    """Ensures sed performs a truly global substitution when placeholders repeat on one line."""
    dummy_rel = f"{repo_tmp}/dummy_multi_same_line.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    dummy_abs.write_text(
        "extends Node\n"
        'var security = {"salt1": "CI_INJECT_SALT_HERE", "salt2": "CI_INJECT_SALT_HERE"}\n',
        encoding="utf-8",
    )

    result = run_injection(dummy_rel, "multi-placeholder-salt")

    assert result.returncode == 0
    content = dummy_abs.read_text(encoding="utf-8")
    assert "CI_INJECT_SALT_HERE" not in content
    # Both placeholders on the same line must be replaced
    assert content.count("multi-placeholder-salt") == 2


def test_injection_missing_placeholder(repo_tmp):
    """A missing placeholder is a safe no-op. The file must remain untouched."""
    dummy_rel = f"{repo_tmp}/dummy_missing.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel
    original_content = 'extends Node\nvar security = {"save_salt": "unchanged"}\n'

    dummy_abs.write_text(original_content, encoding="utf-8")

    result = run_injection(dummy_rel, "missing-placeholder-salt")

    assert result.returncode == 0
    assert dummy_abs.read_text(encoding="utf-8") == original_content


@pytest.mark.parametrize(
    "empty_input",
    [
        "",  # Completely empty
        "\n",  # Single Linux newline
        "\r\n\r\n",  # Multiple Windows newlines
    ],
)
def test_injection_empty_secret(repo_tmp, empty_input):
    """
    Ensures the bash script guard catches an empty environment variable
    (or one that becomes empty after stripping newlines) and aborts.
    """
    dummy_rel = f"{repo_tmp}/dummy_empty_{hash(empty_input)}.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel
    original_content = 'var salt = "CI_INJECT_SALT_HERE"\n'
    dummy_abs.write_text(original_content, encoding="utf-8")

    result = run_injection(dummy_rel, empty_input)

    # Non-zero return code indicates the script aborted as expected
    assert result.returncode != 0

    # Some error output should be produced, but don't depend on exact wording
    assert (result.stdout + result.stderr).strip() != ""

    # Verify no partial corruption occurred
    assert dummy_abs.read_text(encoding="utf-8") == original_content


def test_injection_filename_with_spaces(repo_tmp):
    """Verifies bash variable quoting robustness against argument splitting."""
    dummy_rel = f"{repo_tmp}/dummy globals spaces.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    dummy_abs.write_text('var salt = "CI_INJECT_SALT_HERE"\n', encoding="utf-8")

    result = run_injection(dummy_rel, "space-test-secret")

    assert result.returncode == 0
    content = dummy_abs.read_text(encoding="utf-8")
    assert "space-test-secret" in content


def test_injection_non_existent_file():
    """Ensures script fails fast with a deterministic error on bad paths."""
    result = run_injection("this_file_does_not_exist.gd", "non-existent-file-salt")
    assert result.returncode != 0
    assert "does not exist" in result.stdout


@pytest.mark.skipif(os.name == "nt", reason="POSIX file permission mechanics required")
def test_injection_readonly_file(repo_tmp):
    """
    Catches CI/container filesystem edge cases.
    Secures both the file AND the parent directory to prevent
    Linux 'sed -i' from bypassing read-only file locks via directory rename.
    """
    dummy_rel = f"{repo_tmp}/dummy_readonly.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel
    original_content = 'var salt = "CI_INJECT_SALT_HERE"\n'
    dummy_abs.write_text(original_content, encoding="utf-8")

    # Lock file and directory
    dummy_abs.chmod(0o444)
    dummy_abs.parent.chmod(0o555)

    try:
        result = run_injection(dummy_rel, "readonly-secret")

        assert result.returncode != 0
        assert dummy_abs.read_text(encoding="utf-8") == original_content
    finally:
        # MUST restore write permissions, otherwise pytest temporary directory cleanup will crash
        dummy_abs.parent.chmod(0o777)
        dummy_abs.chmod(0o666)


def test_idempotency(repo_tmp):
    """Running the injection twice should not cause corruption or double-escaping."""
    dummy_rel = f"{repo_tmp}/dummy_idempotent.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    dummy_abs.write_text('var salt = "CI_INJECT_SALT_HERE"\n', encoding="utf-8")

    # First run must succeed
    first = run_injection(dummy_rel, "idempotent-secret")
    assert first.returncode == 0, "Initial injection failed"

    # Second run must also succeed and leave content uncorrupted
    second = run_injection(dummy_rel, "idempotent-secret")

    assert second.returncode == 0
    content = dummy_abs.read_text(encoding="utf-8")

    # Strict matching to guarantee NO duplicate injection or mangled formatting
    assert content == 'var salt = "idempotent-secret"\n'


@pytest.mark.parametrize(
    "secret_input, expected_injected",
    [
        ("line1\nline2", "line1line2"),  # Standard Linux/macOS LF
        ("line1\r\nline2", "line1line2"),  # Windows CRLF
        ("\n\nline1\n\nline2\n\n", "line1line2"),  # Multiple leading/trailing newlines
        ("\r\n mixed \n newlines \r\n", " mixed  newlines "),  # Mixed with spaces
        ("   ", "   "),  # All-whitespace (valid string, tests positive path)
        ("  \n\n  ", "    "),  # Whitespace split by newlines
    ],
)
def test_injection_multiline_secret_stripped(repo_tmp, secret_input, expected_injected):
    """
    Validates that multiline secrets (both LF and CRLF) are safely stripped
    of all newlines and injected, rather than failing or corrupting the file.
    """
    dummy_rel = f"{repo_tmp}/dummy_multiline_{hash(secret_input)}.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel
    original_content = 'var salt = "CI_INJECT_SALT_HERE"\n'

    dummy_abs.write_text(original_content, encoding="utf-8")

    # Pass the complex multiline secret
    result = run_injection(dummy_rel, secret_input)

    # It must SUCCEED, because `tr -d '\r\n'` sanitizes the input
    assert result.returncode == 0

    content = dummy_abs.read_text(encoding="utf-8")

    # Strict equality check: guarantees no unexpected whitespace, quotes, or newlines slipped through
    expected_content = f'var salt = "{expected_injected}"\n'
    assert content == expected_content


def test_injection_unset_secret(repo_tmp):
    """
    Ensures that a completely missing (unset) environment variable
    is caught gracefully by the bash script without triggering
    a fatal 'unbound variable' bash crash due to 'set -u'.
    """
    dummy_rel = f"{repo_tmp}/dummy_unset.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel
    original_content = 'var salt = "CI_INJECT_SALT_HERE"\n'
    dummy_abs.write_text(original_content, encoding="utf-8")

    # Pass None to completely strip the variable from the test environment
    result = run_injection(dummy_rel, None)

    # It must fail
    assert result.returncode != 0

    # It must output our custom error, NOT a standard bash "unbound variable" error
    combined_output = result.stdout + result.stderr
    assert "PRODUCTION_SALT environment variable is not set" in combined_output
    assert "unbound variable" not in combined_output

    # The file must remain completely untouched
    assert dummy_abs.read_text(encoding="utf-8") == original_content
