import os
import subprocess
import sys


def run_sed_injection(file_path, raw_secret):
    """
    Emulates the exact bash pipeline used in test_injection.sh and deploy_to_itch.yml.
    Passes the secret securely via environment variables.
    """
    env = os.environ.copy()
    env["PRODUCTION_SALT"] = raw_secret

    # The exact sed escaping sequence from our pipeline
    bash_script = f"""
    GODOT_ESCAPED=$(printf '%s' "$PRODUCTION_SALT" | sed 's/\\/\\\\/g; s/"/\\"/g')
    SED_ESCAPED=$(printf '%s' "$GODOT_ESCAPED" | sed 's/\\/\\\\/g; s/&/\\&/g; s/|/\\|/g')
    sed -i "s|\\"CI_INJECT_SALT_HERE\\"|\\"$SED_ESCAPED\\"|g" {file_path}
    """

    try:
        # Execute the pipeline using bash
        subprocess.run(["bash", "-c", bash_script], env=env, check=True)
    except FileNotFoundError:
        print("❌ ERROR: 'bash' or 'sed' command not found.")
        print(
            "Run this Python script from your VS Code Git Bash terminal instead of PowerShell."
        )
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"❌ ERROR: sed injection failed with exit code {e.returncode}")
        sys.exit(1)


def test_injection():
    dummy_file = "dummy_globals.gd"

    print("Running GDScript Salt Injection Tests in Python...")
    print("-" * 40)

    # TEST 1: Standard nasty secret with quotes and backslashes
    raw_secret_1 = 'T3st_S@lt!_2026#"\\'
    expected_salt_1 = 'T3st_S@lt!_2026#\\"\\\\'

    with open(dummy_file, "w") as f:
        f.write(
            'func _get_encryption_key() -> String:\n\tvar salt: String = "CI_INJECT_SALT_HERE"\n\treturn salt\n'
        )

    run_sed_injection(dummy_file, raw_secret_1)

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

    run_sed_injection(dummy_file, raw_secret_2)

    with open(dummy_file, "r") as f:
        content = f.read()
        # GDScript just sees the raw characters, no extra escaping needed for | and &,
        # but our sed pipeline must survive injecting them.
        if f'var salt: String = "{expected_salt_2}"' in content:
            print(
                "✅ TEST 2 PASS: Injected secret with sed special characters (| and &)."
            )
        else:
            print(f"❌ TEST 2 FAIL\n{content}")
            sys.exit(1)

    print("-" * 40)
    print("🎉 ALL INJECTION TESTS PASSED!")

    # Cleanup
    if os.path.exists(dummy_file):
        os.remove(dummy_file)


if __name__ == "__main__":
    test_injection()
