"""
Test suite for the CI flag injection utility.

Ensures that 'export_presets.cfg' is correctly modified to include the 'ci'
feature flag, which is critical for bypassing production security guards
during automated browser testing.
"""

import subprocess
import pytest
from pathlib import Path

# The script we are testing
INJECT_SCRIPT = ".github/scripts/inject_ci_flag.py"


def run_ci_injection(project_root):
    """Executes the injection script within the provided dummy project root."""
    return subprocess.run(
        ["python3", INJECT_SCRIPT],
        cwd=str(project_root),
        capture_output=True,
        text=True,
        timeout=10
    )


def test_inject_ci_flag_standard(repo_tmp):
    """Tests injection when custom_features is empty."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    config.write_text('[preset.0.options]\ncustom_features=""', encoding="utf-8")

    result = run_ci_injection(root)

    assert result.returncode == 0
    assert 'custom_features="ci"' in config.read_text()


def test_inject_ci_flag_missing_key(repo_tmp):
    """Tests injection when the custom_features key is entirely missing."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    # Preset exists but has no features defined
    config.write_text('[preset.0.options]\nother_setting=true', encoding="utf-8")

    result = run_ci_injection(root)

    assert result.returncode == 0
    content = config.read_text()
    assert 'custom_features="ci"' in content
    assert '[preset.0.options]\ncustom_features="ci"' in content


def test_inject_ci_flag_existing_values(repo_tmp):
    """Tests that existing flags are overwritten by the 'ci' flag."""
    root = Path(repo_tmp)
    config = root / "export_presets.cfg"
    config.write_text('[preset.0.options]\ncustom_features="debug,test"', encoding="utf-8")

    result = run_ci_injection(root)

    assert result.returncode == 0
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
    assert "not found" in result.stdout
