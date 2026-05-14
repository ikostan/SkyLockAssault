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


def run_ci_injection(test_work_dir):
    """
    Executes the injection script.
    Uses the absolute path to the script so it can be found regardless of cwd.
    """
    # Force the child process to use UTF-8 via environment variables
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"

    return subprocess.run(
        [sys.executable, str(INJECT_SCRIPT_ABS)],
        env=env, # Pass the forced encoding env
        cwd=str(test_work_dir),
        capture_output=True,
        text=True,
        timeout=10,
        encoding="utf-8"
    )


def test_inject_ci_flag_standard(repo_tmp):
    """Tests injection when custom_features is empty."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    config.write_text('[preset.0.options]\ncustom_features=""', encoding="utf-8")

    result = run_ci_injection(root)

    assert result.returncode == 0, f"Script failed: {result.stderr}"
    assert 'custom_features="ci"' in config.read_text()


def test_inject_ci_flag_missing_key(repo_tmp):
    """Tests injection when the custom_features key is entirely missing."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    # Preset exists but has no features defined
    config.write_text('[preset.0.options]\nother_setting=true', encoding="utf-8")

    result = run_ci_injection(root)

    assert result.returncode == 0, f"Script failed: {result.stderr}"
    content = config.read_text()
    assert 'custom_features="ci"' in content
    assert '[preset.0.options]\ncustom_features="ci"' in content


def test_inject_ci_flag_existing_values(repo_tmp):
    """Tests that existing flags are overwritten by the 'ci' flag."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    config.write_text('[preset.0.options]\ncustom_features="debug,test"', encoding="utf-8")

    result = run_ci_injection(root)

    assert result.returncode == 0, f"Script failed: {result.stderr}"
    content = config.read_text()
    assert 'custom_features="ci"' in content
    assert '"debug,test"' not in content


def test_inject_ci_flag_backup_creation(repo_tmp):
    """Verifies that a backup file is created before modification."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    config.write_text('[preset.0.options]\ncustom_features=""', encoding="utf-8")

    run_ci_injection(root)

    assert (root / "export_presets.cfg.bak").exists()


def test_inject_ci_flag_no_config_failure(repo_tmp):
    """Ensures the script fails gracefully if the config file is missing."""
    root = Path(repo_tmp)
    # config file NOT created

    result = run_ci_injection(root)

    assert result.returncode != 0
    assert "not found" in result.stdout or "not found" in result.stderr
