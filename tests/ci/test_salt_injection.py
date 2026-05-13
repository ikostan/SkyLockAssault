import os
import subprocess
import sys

# Dynamically locate the project root
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Define paths RELATIVE to the project root for bash to digest easily
INJECT_SCRIPT_REL = ".github/scripts/inject_salt.sh"


def run_injection(file_name, raw_secret):
    """Executes the single-source-of-truth bash script using relative paths."""
    env = os.environ.copy()
    env["PRODUCTION_SALT"] = raw_secret

    # Verify the script exists using Python's absolute path
    script_abs_path = os.path.join(PROJECT_ROOT, ".github", "scripts", "inject_salt.sh")
    if not os.path.exists(script_abs_path):
        print(f"❌ ERROR: Master inject script not found at {script_abs_path}")
        sys.exit(1)

    try:
        # By setting cwd=PROJECT_ROOT, bash only deals with relative paths!
        # Example: bash .github/scripts/inject_salt.sh dummy_globals.gd
        # This completely avoids the C:/ vs /c/ Windows Git Bash pathing nightmare.
        subprocess.run(
            ["bash", INJECT_SCRIPT_REL, file_name],
            env=env,
            cwd=PROJECT_ROOT,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"❌ ERROR: Injection script failed with exit code {e.returncode}")
        sys.exit(1)


def test_injection():
    dummy_file_name = "dummy_globals.gd"
    # Create the dummy file explicitly in the project root so bash can find it relatively
    dummy_file_abs = os.path.join(PROJECT_ROOT, dummy_file_name)

    print("Running GDScript Salt Injection Tests via Master Script...")
    print("-" * 40)

    # TEST 1: Standard nasty secret with quotes and backslashes
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
            print("✅ TEST 1 PASS: Injected standard nasty secret correctly.")
        else:
            print(f"❌ TEST 1 FAIL\n{content}")
            sys.exit(1)

    # TEST 2: Secret with sed delimiter characters (| and &)
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
                "✅ TEST 2 PASS: Injected secret with sed special characters (| and &)."
            )
        else:
            print(f"❌ TEST 2 FAIL\n{content}")
            sys.exit(1)

    print("-" * 40)
    print("🎉 ALL INJECTION TESTS PASSED!")

    if os.path.exists(dummy_file_abs):
        os.remove(dummy_file_abs)


if __name__ == "__main__":
    test_injection()
