"""
Test suite for the CI flag injection utility.

Ensures that 'export_presets.cfg' is correctly modified to include the 'ci'
feature flag, which is critical for bypassing production security guards
during automated browser testing.
"""

import os
import subprocess
import sys
from pathlib import Path

# Dynamically locate the project root to find the infrastructure script
# We need this to build an absolute path so Python can find the script
# while the test is running inside a temporary directory.
PROJECT_ROOT = Path(__file__).resolve().parents[2]
INJECT_SCRIPT_ABS = PROJECT_ROOT / ".github" / "scripts" / "inject_ci_flag.py"


def run_ci_injection(test_work_dir: Path) -> subprocess.CompletedProcess:
    """
    Executes the injection script.
    Uses the absolute path to the script so it can be found regardless of cwd.
    """
    # Force the child process to use UTF-8 via environment variables
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"

    return subprocess.run(
        [sys.executable, str(INJECT_SCRIPT_ABS)],
        env=env,  # Pass the forced encoding env
        cwd=str(test_work_dir),
        capture_output=True,
        text=True,
        timeout=10,
        encoding="utf-8",
    )


def test_inject_ci_flag_standard(repo_tmp):
    """Tests injection when custom_features is empty."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    config.write_text('[preset.0.options]\ncustom_features=""', encoding="utf-8")

    result = run_ci_injection(root)

    assert result.returncode == 0, f"Script failed: {result.stderr}"
    assert 'custom_features="ci"' in config.read_text(encoding="utf-8")


def test_inject_ci_flag_missing_key(repo_tmp):
    """Tests injection when the custom_features key is entirely missing."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    # Preset exists but has no features defined
    config.write_text("[preset.0.options]\nother_setting=true", encoding="utf-8")

    result = run_ci_injection(root)

    assert result.returncode == 0, f"Script failed: {result.stderr}"
    content = config.read_text(encoding="utf-8")

    # Separated semantic assertions to avoid brittle newline (\r\n) failures
    assert 'custom_features="ci"' in content
    assert "[preset.0.options]" in content


def test_inject_ci_flag_existing_values(repo_tmp):
    """
    Ensures existing feature flags are intentionally replaced with CI-only mode.
    Note: Destructive overwrite is the intended behavior here to ensure
    the CI environment is perfectly isolated from local developer flags.
    """
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    config.write_text(
        '[preset.0.options]\ncustom_features="debug,test"', encoding="utf-8"
    )

    result = run_ci_injection(root)

    assert result.returncode == 0, f"Script failed: {result.stderr}"
    content = config.read_text(encoding="utf-8")
    assert 'custom_features="ci"' in content
    assert '"debug,test"' not in content


def test_inject_ci_flag_backup_creation(repo_tmp):
    """Verifies that a backup file is created and contents are perfectly preserved."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    original_content = '[preset.0.options]\ncustom_features=""'
    config.write_text(original_content, encoding="utf-8")

    run_ci_injection(root)

    backup = root / "export_presets.cfg.bak"
    assert backup.exists(), "Backup file was not created."
    assert (
        backup.read_text(encoding="utf-8") == original_content
    ), "Backup contents corrupted."


def test_inject_ci_flag_no_config_failure(repo_tmp):
    """Ensures the script fails gracefully if the config file is missing."""
    root = Path(repo_tmp)
    # config file NOT created

    result = run_ci_injection(root)

    assert result.returncode != 0
    combined_output = (result.stdout + result.stderr).lower()
    assert "not found" in combined_output


# --- NEW TESTS ADDED BELOW ---


def test_inject_ci_flag_idempotent(repo_tmp):
    """Critical CI test: Running the script twice should not corrupt or duplicate the flag."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    config.write_text("[preset.0.options]\nother_setting=true", encoding="utf-8")

    # First run
    first_result = run_ci_injection(root)
    assert first_result.returncode == 0

    # Second run
    second_result = run_ci_injection(root)
    assert second_result.returncode == 0

    content = config.read_text(encoding="utf-8")
    assert content.count('custom_features="ci"') == 1, "Flag was duplicated!"


def test_inject_ci_flag_already_exists(repo_tmp):
    """Ensures the script safely handles files where 'ci' is already present."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    config.write_text('[preset.0.options]\ncustom_features="ci"', encoding="utf-8")

    result = run_ci_injection(root)
    assert result.returncode == 0

    content = config.read_text(encoding="utf-8")
    assert content.count('custom_features="ci"') == 1


def test_inject_ci_flag_multiple_presets(repo_tmp):
    """Verifies that the script updates all available presets in the file."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"

    multi_preset_content = (
        "[preset.0.options]\n"
        "other_setting=true\n\n"
        "[preset.1.options]\n"
        'custom_features=""\n'
    )
    config.write_text(multi_preset_content, encoding="utf-8")

    result = run_ci_injection(root)
    assert result.returncode == 0

    content = config.read_text(encoding="utf-8")
    # Because of the regex replacement logic, it should inject/overwrite for BOTH presets
    assert content.count('custom_features="ci"') == 2
