"""
Test suite for the CI/CD salt injection pipeline.

Validates that the master bash script correctly replaces placeholder strings
in GDScript files with various complex secrets, ensuring that escape sequences
and special sed characters do not break the final game code.
"""

import os
import stat
import subprocess
import sys

# Dynamically locate the project root
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# Define paths RELATIVE to the project root for bash to digest easily
INJECT_SCRIPT_REL = ".github/scripts/inject_salt.sh"


def run_injection(file_name, raw_secret, expect_failure=False):
    """
    Executes the single-source-of-truth bash script using relative paths.

    Sets the required environment variable and calls the master bash script
    to perform the injection on the specified file, avoiding Windows pathing issues.

    Args:
        file_name (str): The name of the dummy file to inject the secret into.
        raw_secret (str): The raw string secret to inject.
        expect_failure (bool): If True, asserts that the bash script exits with an error.
    """
    env = os.environ.copy()
    env["PRODUCTION_SALT"] = raw_secret

    # Verify the script exists using Python's absolute path
    script_abs_path = os.path.join(PROJECT_ROOT, ".github", "scripts", "inject_salt.sh")
    if not os.path.exists(script_abs_path):
        print(f"❌ ERROR: Master inject script not found at {script_abs_path}")
        sys.exit(1)

    try:
        # By setting cwd=PROJECT_ROOT, bash only deals with relative paths!
        subprocess.run(
            ["bash", INJECT_SCRIPT_REL, file_name],
            env=env,
            cwd=PROJECT_ROOT,
            check=True,
            capture_output=True,  # Suppress bash output during tests unless there's an unexpected error
        )
        if expect_failure:
            print(
                f"❌ ERROR: Injection script was expected to fail on '{file_name}' but succeeded."
            )
            sys.exit(1)
    except subprocess.CalledProcessError as e:
        if not expect_failure:
            print(f"❌ ERROR: Injection script failed with exit code {e.returncode}")
            print(e.stderr.decode("utf-8"))
            sys.exit(1)


def test_injection_standard_secret():
    """
    Tests the injection of a standard secret containing quotes and backslashes.

    Ensures that special characters are properly escaped so that the resulting
    GDScript file remains syntactically valid when parsed by Godot.
    """
    dummy_file_name = "dummy_globals_standard.gd"
    dummy_file_abs = os.path.join(PROJECT_ROOT, dummy_file_name)

    raw_secret_1 = 'T3st_S@lt!_2026#"\\'
    expected_salt_1 = 'T3st_S@lt!_2026#\\"\\\\'

    with open(dummy_file_abs, "w") as f:
        f.write(
            'func _get_encryption_key() -> String:\n\tvar salt: String = "CI_INJECT_SALT_HERE"\n\treturn salt\n'
        )

    run_injection(dummy_file_name, raw_secret_1)

    with open(dummy_file_abs, "r") as f:
        content = f.read()
        if f'var salt: String = "{expected_salt_1}"' in content:
            print("✅ TEST PASS: Injected standard nasty secret correctly.")
        else:
            print(f"❌ TEST FAIL\n{content}")
            if os.path.exists(dummy_file_abs):
                os.remove(dummy_file_abs)
            sys.exit(1)

    if os.path.exists(dummy_file_abs):
        os.remove(dummy_file_abs)


def test_injection_sed_special_characters():
    """
    Tests the injection of a secret containing bash/sed delimiter characters.

    Ensures that characters like '|' and '&' do not prematurely terminate
    or break the sed replacement command inside the master injection script.
    """
    dummy_file_name = "dummy_globals_sed.gd"
    dummy_file_abs = os.path.join(PROJECT_ROOT, dummy_file_name)

    raw_secret_2 = "My|Secret&Salt"
    expected_salt_2 = "My|Secret&Salt"

    with open(dummy_file_abs, "w") as f:
        f.write(
            'func _get_encryption_key() -> String:\n\tvar salt: String = "CI_INJECT_SALT_HERE"\n\treturn salt\n'
        )

    run_injection(dummy_file_name, raw_secret_2)

    with open(dummy_file_abs, "r") as f:
        content = f.read()
        if f'var salt: String = "{expected_salt_2}"' in content:
            print(
                "✅ TEST PASS: Injected secret with sed special characters (| and &)."
            )
        else:
            print(f"❌ TEST FAIL\n{content}")
            if os.path.exists(dummy_file_abs):
                os.remove(dummy_file_abs)
            sys.exit(1)

    if os.path.exists(dummy_file_abs):
        os.remove(dummy_file_abs)


def test_injection_multiple_placeholders():
    """
    Tests files with multiple CI_INJECT_SALT_HERE placeholders.

    Ensures that the injection script deterministically updates all occurrences
    globally, leaving no partial replacements or silent leftovers behind.
    """
    dummy_file_name = "dummy_multiple_placeholders.gd"
    dummy_file_abs = os.path.join(PROJECT_ROOT, dummy_file_name)

    with open(dummy_file_abs, "w", encoding="utf-8") as f:
        f.write(
            "extends Node\n"
            'var security = {"save_salt": "CI_INJECT_SALT_HERE"}\n'
            'var another = {"save_salt": "CI_INJECT_SALT_HERE"}\n'
        )

    run_injection(dummy_file_name, "multi-placeholder-salt")

    with open(dummy_file_abs, "r", encoding="utf-8") as f:
        content = f.read()

    if (
        "CI_INJECT_SALT_HERE" not in content
        and content.count("multi-placeholder-salt") == 2
    ):
        print("✅ TEST PASS: Multiple placeholders replaced deterministically.")
    else:
        print(
            f"❌ TEST FAIL: Incomplete replacement in multiple placeholders.\n{content}"
        )
        if os.path.exists(dummy_file_abs):
            os.remove(dummy_file_abs)
        sys.exit(1)

    if os.path.exists(dummy_file_abs):
        os.remove(dummy_file_abs)


def test_injection_missing_placeholder():
    """
    Tests the behavior when a file is missing the placeholder string entirely.

    Because the bash script uses sed, a missing placeholder is a safe no-op.
    This test ensures the file is left entirely untouched without crashing.
    """
    dummy_file_name = "dummy_missing_placeholder.gd"
    dummy_file_abs = os.path.join(PROJECT_ROOT, dummy_file_name)
    original_content = 'extends Node\nvar security = {"save_salt": "unchanged"}\n'

    with open(dummy_file_abs, "w", encoding="utf-8") as f:
        f.write(original_content)

    run_injection(dummy_file_name, "missing-placeholder-salt")

    with open(dummy_file_abs, "r", encoding="utf-8") as f:
        content = f.read()

    if content == original_content:
        print("✅ TEST PASS: Missing placeholder resulted in safe no-op.")
    else:
        print(
            f"❌ TEST FAIL: Missing placeholder test unexpectedly mutated the file.\n{content}"
        )
        if os.path.exists(dummy_file_abs):
            os.remove(dummy_file_abs)
        sys.exit(1)

    if os.path.exists(dummy_file_abs):
        os.remove(dummy_file_abs)


def test_injection_empty_secret():
    """
    Tests the behavior when the PRODUCTION_SALT environment variable is empty.

    Ensures the script's safety guard catches the missing secret and fails
    deterministically rather than injecting an empty string into the game.
    """
    dummy_file_name = "dummy_empty_secret.gd"
    dummy_file_abs = os.path.join(PROJECT_ROOT, dummy_file_name)

    with open(dummy_file_abs, "w") as f:
        f.write('var salt = "CI_INJECT_SALT_HERE"\n')

    # Pass an empty string. The python wrapper sets env["PRODUCTION_SALT"] = ""
    run_injection(dummy_file_name, "", expect_failure=True)

    print("✅ TEST PASS: Empty secret triggered deterministic error guard.")

    if os.path.exists(dummy_file_abs):
        os.remove(dummy_file_abs)


def test_injection_read_only_file():
    """
    Tests the script's resilience against read-only file permissions.

    Ensures that if the CI/CD runner locks the file, the sed replacement
    fails cleanly with an error code instead of failing silently.
    """
    dummy_file_name = "dummy_readonly.gd"
    dummy_file_abs = os.path.join(PROJECT_ROOT, dummy_file_name)

    with open(dummy_file_abs, "w") as f:
        f.write('var salt = "CI_INJECT_SALT_HERE"\n')

    # Make the file read-only
    os.chmod(dummy_file_abs, stat.S_IREAD)

    try:
        run_injection(dummy_file_name, "valid-secret", expect_failure=True)
        print("✅ TEST PASS: Read-only file triggered deterministic OS error.")
    finally:
        # Restore write permissions so the test runner can clean it up
        os.chmod(dummy_file_abs, stat.S_IWRITE)
        if os.path.exists(dummy_file_abs):
            os.remove(dummy_file_abs)


def test_injection_filename_with_spaces():
    """
    Tests bash variable quoting robustness.

    Ensures the script correctly parses target file names that contain spaces,
    preventing argument splitting errors in bash.
    """
    dummy_file_name = "dummy globals spaces.gd"
    dummy_file_abs = os.path.join(PROJECT_ROOT, dummy_file_name)

    with open(dummy_file_abs, "w") as f:
        f.write('var salt = "CI_INJECT_SALT_HERE"\n')

    run_injection(dummy_file_name, "space-test-secret")

    with open(dummy_file_abs, "r") as f:
        content = f.read()

    if "space-test-secret" in content:
        print("✅ TEST PASS: Filename with spaces handled correctly.")
    else:
        print(f"❌ TEST FAIL: Space in filename broke injection.\n{content}")
        if os.path.exists(dummy_file_abs):
            os.remove(dummy_file_abs)
        sys.exit(1)

    if os.path.exists(dummy_file_abs):
        os.remove(dummy_file_abs)


def test_injection_non_existent_file():
    """
    Tests invoking the injection script with a non-existent file.

    Ensures the script fails fast with a clear, deterministic error code
    rather than causing silent or downstream pipeline failures.
    """
    run_injection(
        "this_file_does_not_exist.gd", "non-existent-file-salt", expect_failure=True
    )
    print("✅ TEST PASS: Non-existent file triggered deterministic error.")


if __name__ == "__main__":
    print("Running GDScript Salt Injection Tests via Master Script...")
    print("-" * 40)
    test_injection_standard_secret()
    test_injection_sed_special_characters()
    test_injection_multiple_placeholders()
    test_injection_missing_placeholder()
    test_injection_non_existent_file()

    # New Edge Cases
    test_injection_empty_secret()
    test_injection_read_only_file()
    test_injection_filename_with_spaces()

    print("-" * 40)
    print("🎉 ALL INJECTION TESTS PASSED!")
