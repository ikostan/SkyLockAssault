import os
import subprocess
import sys

# Path to the shared script
SCRIPT_PATH = "./.github/scripts/inject_salt.sh"


def run_script_injection(file_path):
    # The nasty test secret
    RAW_SECRET = 'my"nasty\\salt123'

    try:
        # We call the EXACT script used by the YML
        subprocess.run(
            ["bash", SCRIPT_PATH, file_path, RAW_SECRET],
            check=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        print(f"❌ ERROR: Script execution failed: {e}")
        sys.exit(1)


def test_injection():
    dummy_file = "dummy.godot"
    # Note: The expected output should match what the bash script produces
    expected_salt_line = 'security/save_salt="my\\"nasty\\\\salt123"'

    print("Running Shared Script Injection Tests...")
    print("-" * 40)

    # TEST 1: No [game] section exists
    with open(dummy_file, "w") as f:
        f.write('[application]\nname="Test"\n')

    run_script_injection(dummy_file)

    with open(dummy_file, "r") as f:
        content = f.read()
        if expected_salt_line in content and "[game]" in content:
            print("✅ TEST 1 PASS: Created [game] section and injected salt.")
        else:
            print(f"❌ TEST 1 FAIL\n{content}")
            sys.exit(1)

    print("-" * 40)
    print("🎉 ALL INTEGRATION TESTS PASSED!")
    if os.path.exists(dummy_file):
        os.remove(dummy_file)


if __name__ == "__main__":
    test_injection()
