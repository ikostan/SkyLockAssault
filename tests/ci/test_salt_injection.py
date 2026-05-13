import os
import subprocess
import sys

# Dynamically locate the master bash script relative to this Python file
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
INJECT_SCRIPT = os.path.join(PROJECT_ROOT, ".github", "scripts", "inject_salt.sh")


def run_injection(file_path, raw_secret):
    """
    Executes the single-source-of-truth bash script.
    """
    env = os.environ.copy()
    env["PRODUCTION_SALT"] = raw_secret

    if not os.path.exists(INJECT_SCRIPT):
        print(f"❌ ERROR: Master inject script not found at {INJECT_SCRIPT}")
        sys.exit(1)

    try:
        subprocess.run(["bash", INJECT_SCRIPT, file_path], env=env, check=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ ERROR: Injection script failed with exit code {e.returncode}")
        sys.exit(1)


def test_injection():
    dummy_file = "dummy_globals.gd"

    print("Running GDScript Salt Injection Tests via Master Script...")
    print("-" * 40)

    # TEST 1: Standard nasty secret with quotes and backslashes
    raw_secret_1 = 'T3st_S@lt!_2026#"\\'
    expected_salt_1 = 'T3st_S@lt!_2026#\\"\\\\'

    with open(dummy_file, "w") as f:
        f.write(
            'func _get_encryption_key() -> String:\n\tvar salt: String = "CI_INJECT_SALT_HERE"\n\treturn salt\n'
        )

    run_injection(dummy_file, raw_secret_1)

    with open(dummy_file, "r") as f:
        content = f.read()
        if f'var salt: String = "{expected_salt_1}"' in content:
            print("✅ TEST 1 PASS: Injected standard nasty secret correctly.")
        else:
            print(f"❌ TEST 1 FAIL\n{content}")
            sys.exit(1)

    # TEST 2: Secret with sed delimiter characters (| and &)
    raw_secret_2 = "My|Secret&Salt"
    expected_salt_2 = "My|Secret&Salt"

    with open(dummy_file, "w") as f:
        f.write(
            'func _get_encryption_key() -> String:\n\tvar salt: String = "CI_INJECT_SALT_HERE"\n\treturn salt\n'
        )

    run_injection(dummy_file, raw_secret_2)

    with open(dummy_file, "r") as f:
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

    if os.path.exists(dummy_file):
        os.remove(dummy_file)


if __name__ == "__main__":
    test_injection()
