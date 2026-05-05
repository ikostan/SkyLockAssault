import os
import subprocess
import sys

# The exact AWK script from deploy_to_itch.yml
AWK_SCRIPT = """
BEGIN {
  salt = ENVIRON["SALT"]
  in_game = 0
  salt_written = 0
  saw_game_section = 0
}
{
  if ($0 ~ /^\\[game\\]/) {
    in_game = 1
    saw_game_section = 1
    print
    next
  } else if ($0 ~ /^\\[/ && $0 !~ /^\\[game\\]/) {
    if (in_game && !salt_written) {
      print "security/save_salt=\\"" salt "\\""
      salt_written = 1
    }
    in_game = 0
    print
    next
  }
  if (in_game && $0 ~ /^[[:space:]]*security\\/save_salt[[:space:]]*=/) {
    if (!salt_written) {
      print "security/save_salt=\\"" salt "\\""
      salt_written = 1
    }
    next
  }
  print
}
END {
  if (in_game && !salt_written) {
    print "security/save_salt=\\"" salt "\\""
    salt_written = 1
  }
  if (!saw_game_section) {
    if (NR > 0) { print "" }
    print "[game]"
    print "security/save_salt=\\"" salt "\\""
  }
}
"""


def run_awk_injection(file_path):
    # 1. Define a nasty test secret with quotes and slashes
    RAW_SECRET = 'my"nasty\\salt123'

    # Emulate the sed command: replace \ with \\, and " with \"
    escaped_salt = RAW_SECRET.replace("\\", "\\\\").replace('"', '\\"')

    # Load into environment variables for awk
    env = os.environ.copy()
    env["SALT"] = escaped_salt

    try:
        # Run the awk script via subprocess
        with open(f"{file_path}.tmp", "w") as temp_file:
            subprocess.run(
                ["awk", AWK_SCRIPT, file_path],
                env=env,
                stdout=temp_file,
                check=True,
                text=True,
            )
        # Replace original file with the modified tmp file
        os.replace(f"{file_path}.tmp", file_path)
    except FileNotFoundError:
        print("❌ ERROR: 'awk' command not found.")
        print(
            "Since the GitHub action uses Linux tools, 'awk' must be accessible to Windows."
        )
        print(
            "Run this Python script from your VS Code Git Bash terminal instead of PowerShell."
        )
        sys.exit(1)


def test_injection():
    dummy_file = "dummy.godot"
    expected_salt_line = 'security/save_salt="my\\"nasty\\\\salt123"'

    print("Running Salt Injection Tests in Python...")
    print("-" * 40)

    # TEST 1: No [game] section exists
    with open(dummy_file, "w") as f:
        f.write('[application]\nname="Test"\n')

    run_awk_injection(dummy_file)

    with open(dummy_file, "r") as f:
        content = f.read()
        if expected_salt_line in content and "[game]" in content:
            print("✅ TEST 1 PASS: Created [game] section and injected salt.")
        else:
            print(f"❌ TEST 1 FAIL\n{content}")
            sys.exit(1)

    # TEST 2: [game] section exists, followed by another section
    with open(dummy_file, "w") as f:
        f.write('[application]\nname="Test"\n[game]\nsome_setting=1\n[audio]\nbus=1\n')

    run_awk_injection(dummy_file)

    with open(dummy_file, "r") as f:
        content = f.read()
        # Check if salt is injected before [audio]
        if expected_salt_line in content and content.find(
            expected_salt_line
        ) < content.find("[audio]"):
            print("✅ TEST 2 PASS: Injected salt inside existing [game] section.")
        else:
            print(f"❌ TEST 2 FAIL\n{content}")
            sys.exit(1)

    # TEST 3: [game] section exists and already has an old salt (overwrite)
    with open(dummy_file, "w") as f:
        f.write('[game]\nsecurity/save_salt="old_salt"\nother=2\n')

    run_awk_injection(dummy_file)

    with open(dummy_file, "r") as f:
        content = f.read()
        if expected_salt_line in content and "old_salt" not in content:
            print("✅ TEST 3 PASS: Overwrote existing salt correctly.")
        else:
            print(f"❌ TEST 3 FAIL\n{content}")
            sys.exit(1)

    print("-" * 40)
    print("🎉 ALL INJECTION TESTS PASSED!")

    # Cleanup
    if os.path.exists(dummy_file):
        os.remove(dummy_file)


if __name__ == "__main__":
    test_injection()
