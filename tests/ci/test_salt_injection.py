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


def get_dummy_content(var_line='var salt: String = "CI_INJECT_SALT_HERE"'):
    """
    Helper to generate standard GDScript content.
    Crucially, this satisfies the bash script's hard gate by ensuring the
    security guard logic is always present in the dummy file.
    """
    return (
        f'{var_line}\n'
        'if salt == "CI_INJECT_SALT_HERE":\n'
        '\tpush_error("Missing salt")\n'
    )


def run_injection(file_path, raw_secret):
    """
    Executes the single-source-of-truth bash script using relative paths.
    Returns the CompletedProcess object for assertion checking.
    """
    env = os.environ.copy()

    # If None is passed, simulate a completely missing/unset environment variable
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
        check=False,
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
        ),
    ],
)
def test_injection_values(repo_tmp, scenario, raw_secret, expected_salt):
    """
    Parametrized test covering standard strings, bash/sed delimiters,
    backreferences, UTF-8 locale handling, and path-like slashes.
    """
    dummy_rel = f"{repo_tmp}/dummy_{scenario}.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    dummy_abs.write_text(get_dummy_content(), encoding="utf-8")

    result = run_injection(dummy_rel, raw_secret)

    assert (
        result.returncode == 0
    ), f"Injection failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    content = dummy_abs.read_text(encoding="utf-8")
    assert f'var salt: String = "{expected_salt}"' in content

    # Ensure security guard remained intact
    assert 'if salt == "CI_INJECT_SALT_HERE":' in content

    # Verifies sed did not leave behind macOS/Linux .bak or temp file artifacts
    files_in_dir = list(dummy_abs.parent.iterdir())
    unexpected = [f for f in files_in_dir if f.name != dummy_abs.name]
    assert (
        not unexpected
    ), f"Artifact pollution detected. Unexpected files found: {unexpected}"


def test_injection_targets_only_variable(repo_tmp):
    """
    Ensures the sniper-rifle replacement ONLY targets the variable assignment,
    ignoring other occurrences of the placeholder string.
    """
    dummy_rel = f"{repo_tmp}/dummy_targeted.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    original_content = (
        'var salt: String = "CI_INJECT_SALT_HERE"\n'
        'var other_dict = {"save_salt": "CI_INJECT_SALT_HERE"}\n'
        'if salt == "CI_INJECT_SALT_HERE":\n'
        '\tpass\n'
    )
    dummy_abs.write_text(original_content, encoding="utf-8")

    result = run_injection(dummy_rel, "my-targeted-salt")

    assert result.returncode == 0
    content = dummy_abs.read_text(encoding="utf-8")

    # The variable should be updated
    assert 'var salt: String = "my-targeted-salt"' in content
    # The dictionary value should be strictly ignored
    assert 'var other_dict = {"save_salt": "CI_INJECT_SALT_HERE"}' in content
    # The guard should be strictly ignored
    assert 'if salt == "CI_INJECT_SALT_HERE":' in content


def test_injection_missing_placeholder(repo_tmp):
    """A missing placeholder is a safe no-op. The file must remain untouched."""
    dummy_rel = f"{repo_tmp}/dummy_missing.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    original_content = get_dummy_content('var salt: String = "unchanged"')
    dummy_abs.write_text(original_content, encoding="utf-8")

    result = run_injection(dummy_rel, "missing-placeholder-salt")

    assert result.returncode == 0
    assert dummy_abs.read_text(encoding="utf-8") == original_content


@pytest.mark.parametrize(
    "empty_input",
    [
        "",
        "\n",
        "\r\n\r\n",
    ],
)
def test_injection_empty_secret(repo_tmp, empty_input):
    """
    Ensures the bash script guard catches an empty environment variable
    (or one that becomes empty after stripping newlines) and aborts.
    """
    dummy_rel = f"{repo_tmp}/dummy_empty_{hash(empty_input)}.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    original_content = get_dummy_content()
    dummy_abs.write_text(original_content, encoding="utf-8")

    result = run_injection(dummy_rel, empty_input)

    assert result.returncode != 0
    assert (result.stdout + result.stderr).strip() != ""
    assert dummy_abs.read_text(encoding="utf-8") == original_content


def test_injection_filename_with_spaces(repo_tmp):
    """Verifies bash variable quoting robustness against argument splitting."""
    dummy_rel = f"{repo_tmp}/dummy globals spaces.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    dummy_abs.write_text(get_dummy_content(), encoding="utf-8")

    result = run_injection(dummy_rel, "space-test-secret")

    assert result.returncode == 0
    content = dummy_abs.read_text(encoding="utf-8")
    assert 'var salt: String = "space-test-secret"' in content


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

    original_content = get_dummy_content()
    dummy_abs.write_text(original_content, encoding="utf-8")

    # Lock file and directory
    dummy_abs.chmod(0o444)
    dummy_abs.parent.chmod(0o555)

    try:
        result = run_injection(dummy_rel, "readonly-secret")

        assert result.returncode != 0
        assert dummy_abs.read_text(encoding="utf-8") == original_content
    finally:
        dummy_abs.parent.chmod(0o777)
        dummy_abs.chmod(0o666)


def test_idempotency(repo_tmp):
    """Running the injection twice should not cause corruption or double-escaping."""
    dummy_rel = f"{repo_tmp}/dummy_idempotent.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    dummy_abs.write_text(get_dummy_content(), encoding="utf-8")

    # First run must succeed
    first = run_injection(dummy_rel, "idempotent-secret")
    assert first.returncode == 0, "Initial injection failed"

    # Second run must also succeed and leave content uncorrupted
    second = run_injection(dummy_rel, "idempotent-secret")

    assert second.returncode == 0
    content = dummy_abs.read_text(encoding="utf-8")

    # Strict matching to guarantee NO duplicate injection or mangled formatting
    expected_content = get_dummy_content('var salt: String = "idempotent-secret"')
    assert content == expected_content


@pytest.mark.parametrize(
    "secret_input, expected_injected",
    [
        ("line1\nline2", "line1line2"),
        ("line1\r\nline2", "line1line2"),
        ("\n\nline1\n\nline2\n\n", "line1line2"),
        ("\r\n mixed \n newlines \r\n", " mixed  newlines "),
        ("   ", "   "),
        ("  \n\n  ", "    "),
    ],
)
def test_injection_multiline_secret_stripped(repo_tmp, secret_input, expected_injected):
    """
    Validates that multiline secrets (both LF and CRLF) are safely stripped
    of all newlines and injected, rather than failing or corrupting the file.
    """
    dummy_rel = f"{repo_tmp}/dummy_multiline_{hash(secret_input)}.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    dummy_abs.write_text(get_dummy_content(), encoding="utf-8")

    result = run_injection(dummy_rel, secret_input)

    assert result.returncode == 0

    content = dummy_abs.read_text(encoding="utf-8")
    expected_content = get_dummy_content(f'var salt: String = "{expected_injected}"')

    assert content == expected_content


def test_injection_unset_secret(repo_tmp):
    """
    Ensures that a completely missing (unset) environment variable
    is caught gracefully by the bash script without triggering
    a fatal 'unbound variable' bash crash due to 'set -u'.
    """
    dummy_rel = f"{repo_tmp}/dummy_unset.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    original_content = get_dummy_content()
    dummy_abs.write_text(original_content, encoding="utf-8")

    result = run_injection(dummy_rel, None)

    assert result.returncode != 0

    combined_output = result.stdout + result.stderr
    assert "PRODUCTION_SALT environment variable is not set" in combined_output
    assert "unbound variable" not in combined_output
    assert dummy_abs.read_text(encoding="utf-8") == original_content


def test_injection_does_not_corrupt_security_guard(repo_tmp):
    """
    Ensures the injection script uses targeted replacement to update
    the variable declaration without overwriting the literal string
    used in the security guard conditional logic.
    """
    dummy_rel = f"{repo_tmp}/dummy_guard.gd"
    dummy_abs = Path(PROJECT_ROOT) / dummy_rel

    original_content = (
        "func _get_encryption_key() -> String:\n"
        '\tvar salt: String = "CI_INJECT_SALT_HERE"\n\n'
        "\t# The security check that must NOT be overwritten\n"
        '\tif salt == "CI_INJECT_SALT_HERE":\n'
        '\t\tpush_error("Missing salt")\n'
        "\treturn salt\n"
    )
    dummy_abs.write_text(original_content, encoding="utf-8")

    result = run_injection(dummy_rel, "my-production-secret")

    assert (
        result.returncode == 0
    ), f"Injection failed:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    content = dummy_abs.read_text(encoding="utf-8")

    assert (
        'var salt: String = "my-production-secret"' in content
    ), "Variable assignment was not updated!"

    assert (
        'if salt == "CI_INJECT_SALT_HERE":' in content
    ), "FATAL: The security guard logic was overwritten by sed!"
