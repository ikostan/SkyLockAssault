# PR Summary: Save Encryption Refactor & CI/CD Pipeline Hardening

---

## Overview

This PR overhauls the project's encryption key management by
transitioning from a ProjectSettings-based salt to a CI-injected
GDScript bytecode salt. This hardens the Web export process
against WebAssembly initialization crashes, establishes robust
cross-platform shell utilities, implements corrupted-save
auto-recovery, and vastly stabilizes the automated testing
pipelines.

---

### Key Technical Achievements & Fixes

- **The Sniper Rifle: Update inject_salt.sh**: Instead of replacing
  every instance of "CI_INJECT_SALT_HERE" anywhere in the file, we
  tell sed to only replace it if it's part of the explicit variable
  declaration. Then, we add a hard gate that immediately fails the
  script if the security check was accidentally wiped.
- **Cross-Platform Shell Compatibility**: Extracted inline YAML
  injection logic into dedicated bash scripts. Implemented a
  sedi wrapper in .github/scripts/ci_utils.sh to seamlessly
  handle the syntax differences between GNU sed (Linux/Windows
  Git Bash) and BSD sed (macOS), preventing file corruption for
  local developers.
- **CI Python Hardening**: Patched sys.stdout.encoding in
  inject_ci_flag.py with a safe fallback to prevent hard
  AttributeError crashes when stdout is redirected in automated
  CI runner environments.
- **Godot WebAssembly Stability**: Removed early JavaScriptBridge
  calls during encryption key generation that were silently
  crashing the Web module.
- **Production Security Guards**: Centralized the "CI_INJECT_SALT_HERE"
  placeholder replacement. Rejected abstraction to constants to
  ensure global sed substitution functions correctly. Enforced
  strict engine crashes in production if the salt is missing or weak,
  removing all plaintext fallbacks. Log spam for is_automated_test
  was dropped to DEBUG to prevent CI state leakage.
- **Behavior-Driven Infrastructure Testing**: Rewrote Pytest assertions
  in test_salt_injection.py to decouple from specific shell tool
  outputs (e.g., looking for "sed" or exact English phrases),
  focusing instead on deterministic return codes and file integrity.
  Added tests specifically verifying sed's /g flag behavior on
  single-line multiple placeholders.
- **Windows CRLF Support**: Added specific Pytest coverage
  (test_inject_ci_flag_crlf_windows_endings) to ensure multiline regex
  injections do not choke on \r\n line endings committed by Windows
  developers.
- **Plugin Scoping**: Scoped the sed command used to disable editor
  plugins before headless exports directly to the [editor_plugins]
  block to prevent accidental deletion of other valid enabled= arrays
  in project.godot.

---

### Reviewer's Guide

This PR refactors the project's save encryption architecture to use a
CI‑injected GDScript salt and SHA‑256 key, fundamentally hardening web
exports against WebAssembly crashes. It introduces robust cross-platform
CI utilities for secure secret injection and feature-flagging, implements
an auto-recovery failsafe for corrupted encrypted saves, and vastly
stabilizes both local and automated browser testing environments.

Updates the GitHub Actions workflow for deploying to itch.io so that Godot
export caching is disabled, ensuring a fresh recompile on each deployment
and preventing crashes related to a stale production salt.

Hardens the production salt injection mechanism and itch.io deployment
workflow by enforcing strict error handling, normalizing/validating the
PRODUCTION_SALT secret, tightening export/patch/re-zip steps, adding
end-to-end verification, and expanding CI coverage plus minor runtime
logging for debugging.

Tightens the CI salt injection mechanism to target only the salt variable
assignment, adds guard checks to ensure the security conditional is
preserved, and updates tests and globals.gd to align with the new behavior
and prevent accidental corruption of security logic.

---

### File-Level Changes

<!-- markdownlint-disable line-length table-column-style -->
| Change                                                                                                                                                    | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Files                                                                                                                                                                                                                  |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Encryption Architecture & GDScript Hardening**                                                                                                          | Switched encryption key generation from `ProjectSettings` to a CI-injected GDScript placeholder (`"CI_INJECT_SALT_HERE"`).Removed `JavaScriptBridge` calls during key generation to prevent WebAssembly module crashes on web exports.Introduced a `ci` feature flag via `OS.has_feature("ci")` to bypass production security guards during tests, with logging explicitly downgraded to `DEBUG` to prevent production log spam.Tightened empty-salt handling to immediately abort and crash the engine if production security fails, removing weak plaintext fallbacks.                                                                                                                                                                                                                                                                                                                                                                                                                                                       | `scripts/core/globals.gd`                                                                                                                                                                                              |
| **Encrypted Save Auto-Recovery**                                                                                                                          | Extended `safe_load_config` to explicitly detect corrupted or invalid encrypted files (`ERR_FILE_CORRUPT`, `ERR_INVALID_DATA`).Implemented an auto-deletion mechanism for corrupted files so the game can recover with fresh defaults, preventing permanent crash loops while safely preserving non-corrupt unreadable files.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `scripts/core/globals.gd`                                                                                                                                                                                              |
| **Cross-Platform CI Utilities**                                                                                                                           | Created `.github/scripts/ci_utils.sh` to centralize a cross-platform `sedi` wrapper (handling macOS `sed -i ''` vs Linux `sed -i`) and a safely scoped `disable_editor_plugins` function.Rewrote `inject_salt.sh` to properly escape secrets for Godot/sed and execute a truly global (`/g`) in-place string replacement.Created `inject_ci_flag.py` to cleanly parse and inject `custom_features="ci"` into `export_presets.cfg`, complete with CI-safe `sys.stdout.encoding` fallbacks, backup creation, and idempotency.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | `.github/scripts/inject_salt.sh``.github/scripts/ci_utils.sh``.github/scripts/inject_ci_flag.py`                                                                                                                       |
| **CI Workflows & Local Simulation**                                                                                                                       | Updated GitHub Actions (`browser_test.yml`, `deploy_to_itch.yml`) to utilize the new shared CI scripts and correctly disable editor plugins before headless exports.Built a complete local CI simulation script (`workspace/test_injection.sh`) that verifies system dependencies (`godot`, `python3`, `sed`), backs up project files, runs the injection pipeline, executes a headless Web export, and boots a local Python HTTP server with strict `COOP/COEP` security headers.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | `.github/workflows/deploy_to_itch.yml``.github/workflows/browser_test.yml``workspace/test_injection.sh`                                                                                                                |
| **Infrastructure Test Suite (Pytest)**                                                                                                                    | Replaced old standalone scripts with comprehensive Pytest suites for CI utilities.Added behavior-driven tests in `test_salt_injection.py` to validate sed handling of multiline secrets, empty secrets, read-only files, and multiple placeholders on the same line without brittle string-matching.Added `test_ci_flag_injection.py` to validate `export_presets.cfg` modifications, ensuring it safely handles Windows CRLF (`\r\n`) line endings, malformed option blocks, and multiple presets.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `tests/ci/test_salt_injection.py``tests/ci/conftest.py``tests/ci/test_ci_flag_injection.py``.github/workflows/test_ci_scripts.yml`                                                                                     |
| **Godot Unit Tests (GUT)**                                                                                                                                | Refactored encryption tests to validate the new bytecode-based key generation and strictly assert against SHA-256 outputs and `is_file_encrypted` checks.Enforced cross-test filesystem cleanup (`user://settings.cfg`) in multiple input-binding tests to prevent state contamination during automated CI runs.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | `test/gut/test_encryption_failsafe.gd``test/gut/test_encryption_logging.gd``test/gut/test_get_pause_binding_label_for_device.gd``test/gut/test_input_remap_button.gd``test/gut/test_deduplication_on_device_switch.gd` |
| **Browser Functional Tests (Playwright)**                                                                                                                 | Stabilized Playwright test suites by increasing timeouts and replacing hardcoded wait times with standard constants.Updated workflow scripts to properly isolate `tests/ci` runs from actual browser automation test runs.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `workspace/run_browser_tests.sh``tests/*_flow_test.py``tests/*_test.py`                                                                                                                                                |
| **Chores & Dependencies**                                                                                                                                 | Bumped `urllib3` to `2.7.0`.Updated pinned SHAs for `markdownlint-cli2-action` and `release-drafter` workflows.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | `requirements.txt``.github/workflows/*.yml`                                                                                                                                                                            |
| Disable Godot export cache in the itch.io deployment workflow to force fresh recompilation on each run.                                                   | Set the Godot export action cache option from enabled to disabled so exports do not reuse previous build artifacts. Ensure web preset exports always rebuild freshly injected GDScript instead of relying on GitHub Actions cache                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | `.github/workflows/deploy_to_itch.yml`                                                                                                                                                                                 |
| Strengthened the salt injection script to be strictly fail-fast, newline-normalizing, and self-verifying while handling unset/empty secrets safely.       | Enable strict bash options (set -euo pipefail) and tolerate missing positional arg using default expansion for the target file. Guard against missing target file and unset PRODUCTION_SALT using parameter expansion, with clear error messaging instead of unbound-variable crashes. Normalize PRODUCTION_SALT by stripping all CR/LF characters into CLEAN_SALT, then escape it separately for Godot and sed. Add an explicit empty-secret guard after normalization so secrets that become empty after stripping are rejected. Use shared ci_utils.sh sed wrapper to perform the placeholder replacement and add a post-injection grep check that fails if the placeholder remains, printing success otherwise.                                                                                                                                                                                                                                                                                                            | `.github/scripts/inject_salt.sh`                                                                                                                                                                                       |
| Made the itch.io deployment workflow reliably export, patch, re-zip, verify, and deploy the patched Web build with stronger step-level error handling.    | Add set -euo pipefail to critical workflow run steps, including version injection, plugin disabling, salt injection, export staging, index.js patching, re-zipping, and butler setup/deploy. Create and clean a dedicated patched_build subdirectory under the export archive_directory before unzipping the Godot Web.zip into it. Run patch_index_js.sh on the patched_build directory instead of the previous static export/web path to keep all mutations scoped to the exported artifacts. Delete the original unpatched Web.zip, then zip the contents of patched_build back into a Web.zip located at the same archive_directory path via pushd/popd and an absolute output path. Introduce a verification step that streams the final Web.zip through unzip -p and uses grep to ensure the CI_INJECT_SALT_HERE placeholder does not appear in the shipped archive, failing otherwise. Ensure the butler push step deploys the verified Web.zip from steps.export.outputs.archive_directory with strict error handling. | `.github/workflows/deploy_to_itch.yml`                                                                                                                                                                                 |
| Expanded and refined CI tests for the injection script to cover unset, empty-after-stripping, and complex multiline/whitespace secrets.                   | Update run_injection helper to optionally simulate an entirely unset PRODUCTION_SALT by removing it from the environment when raw_secret is None, while preserving WSLENV handling. Parametrize the empty-secret test to cover empty strings and secrets that are only newlines, asserting non-zero exit and untouched target files. Replace the previous failing-multiline-secret test with a new parametrized test that ensures multiline and CRLF secrets are newline-stripped and still injected correctly, with exact expected injected values including whitespace-only cases. Add a dedicated test for an unset PRODUCTION_SALT environment variable that expects graceful failure with a custom error message, no bash 'unbound variable' errors, and no file modifications.                                                                                                                                                                                                                                           | `tests/ci/test_salt_injection.py`                                                                                                                                                                                      |
| Improved runtime observability of encryption key generation and updated documentation to reflect the hardened pipeline.                                   | In the encryption key generation function, compute the final key into a local variable and log its length at DEBUG level before returning, to aid debugging of salt injection issues. Extend milestone documentation to explicitly mention the hardened CI salt injection handling of unset/multiline PRODUCTION_SALT and the adjusted itch.io workflow behavior around patched exports.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | `scripts/core/globals.gd``files/docs/milestones/18/PART_1_Encryption_key_generation_failure_in_web_export.md`                                                                                                          |
| Make the CI salt injection script perform a targeted replacement of the salt variable and add verification of both injection success and guard integrity. | Change sed to replace only the exact `var salt: String = "CI_INJECT_SALT_HERE"` assignment instead of all placeholder literals. Add a post-injection check that fails if the salt assignment still uses the placeholder value. Add a security guard check that fails if the `if salt == "CI_INJECT_SALT_HERE":` conditional is missing or altered. Adjust success messaging to reflect both injection and guard verification.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | `.github/scripts/inject_salt.sh`                                                                                                                                                                                       |
| Update the encryption key security guard in globals.gd so the CI injector cannot accidentally match and rewrite its literal comparison.                   | Keep the runtime guard that crashes on missing salt but adjust the guard comment/string so the sed pattern no longer matches its literal line. Remove the unreachable empty-string return after a forced crash in the guard branch.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `scripts/core/globals.gd`                                                                                                                                                                                              |
| Refactor and extend CI tests to assert targeted salt injection and preservation of security guard logic across scenarios.                                 | Introduce `get_dummy_content` helper to standardize dummy GDScript content that always includes the security guard pattern. Update existing tests to use the helper and to assert the guard conditional remains intact after injection or failure cases. Replace broad multi-placeholder tests with a focused `test_injection_targets_only_variable` that ensures only the salt assignment is updated while other placeholders and guard remain unchanged. Add `test_injection_does_not_corrupt_security_guard` for regression coverage of the encryption key guard, and adjust expectations in idempotency and multiline secret tests to account for the new content shape. Tidy comments and expectations to align with the stricter behavior and return codes.                                                                                                                                                                                                                                                              | `tests/ci/test_salt_injection.py`                                                                                                                                                                                      |
---

### Assessment against linked issues

| Issue    | Objective                                                                                                                                                                                                                                                                | Addressed | Explanation                                                                                                                                                                          |
|----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **#597** | Create a shared, executable shell script (`.github/scripts/inject_salt.sh`) that encapsulates the salt injection logic previously implemented inline (awk/sed) in `deploy_to_itch.yml`.                                                                                  | ✅         | Replaced inline YAML logic with a dedicated, testable Bash script utilizing cross-platform utilities.                                                                                |
| **#597** | Update the deployment workflow to remove the inline salt injection logic and instead call the shared script with the appropriate arguments and environment.                                                                                                              | ✅         | `deploy_to_itch.yml` and `browser_test.yml` now directly invoke the centralized `inject_salt.sh` as the single source of truth.                                                      |
| **#597** | Refactor the Python salt injection test to remove the embedded AWK script and instead validate behavior by invoking the shared script via subprocess.                                                                                                                    | ✅         | `test_salt_injection.py` was completely overhauled to run `subprocess.run` directly against the Bash script, securing absolute CI parity.                                            |
| **#600** | Harden the web CI/deploy pipeline by moving the save encryption salt into CI-injected GDScript bytecode, while disabling editor plugins before headless exports to avoid crashes.                                                                                        | ✅         | Salt is now successfully injected into `globals.gd`. Plugins are cleanly stripped from `project.godot` before export using the new `disable_editor_plugins` utility.                 |
| **#600** | Fix web encryption key generation so it no longer triggers WebAssembly crashes, produces a non-empty SHA-256 key, and supports a CI-only feature flag.                                                                                                                   | ✅         | `JavaScriptBridge` logic was bypassed, AES/SHA-256 generation was locked in, and the `.github/scripts/inject_ci_flag.py` utility safely provisions the environment for test runners. |
| **#600** | Implement automatic recovery from corrupted or key-mismatched encrypted config/save files by detecting decryption errors and allowing the game to regenerate clean defaults.                                                                                             | ✅         | Handled cleanly in `safe_load_config()`. Explicit `ERR_FILE_CORRUPT` files are deleted automatically, while non-corrupt unreadable files are preserved to prevent data loss.         |
| **#608** | Modify the GitHub Actions workflow `.github/workflows/deploy_to_itch.yml` so that the `firebelley/godot-export` step runs with export caching disabled, ensuring Godot recompiles the GDScript with the injected production salt instead of using stale cached bytecode. | ✅         | `deploy_to_itch.yml` updated to explicitly disable the export cache so Godot is forced to recompile the freshly injected GDScript                                                    |
<!-- markdownlint-enable line-length table-column-style -->

---

### Contributions

**@ikostan (PR author):**

Drove entire PR #607 (10+ commits) fixing web export encryption
key crash (linked to #600).  

**Core changes:**  

- **globals.gd**: Replaced ProjectSettings salt with CI-injected
  placeholder `"CI_INJECT_SALT_HERE"`, switched to
  `OS.has_feature("web")` check, implemented SHA-256 key generation, added
  corrupted save auto-deletion with backup/recovery + guarded error
  handling to prevent data loss.  
- Added `.github/scripts/ci_utils.sh` (cross-platform `sedi()`,
  `disable_editor_plugins()` with scoped sed for [editor_plugins] block).  
- Added `.github/scripts/inject_salt.sh` (uses PRODUCTION_SALT env,
  proper escaping, sources ci_utils).  
- Added `.github/scripts/inject_ci_flag.py` (parses export_presets.cfg,
  backups, injects 'ci' feature flag safely via regex).  
- Created `workspace/test_injection.sh` (local CI simulation: backup/restore
  project.godot, Godot web export, Python server with COOP/COEP headers,
  verification).  
- Updated workflows: browser_test.yml, deploy_to_itch.yml (now call
  shared scripts, disable plugins pre-export, inject salt/flag),
  test_ci_scripts.yml, etc.  
- Updated project.godot (removed ai_autonomous_agent plugin).  
- Enhanced GUT tests (test_encryption_failsafe.gd,
  test_encryption_logging.gd, others: cleanup shared settings, new binary
  checks, no plaintext fallbacks).  
- Enhanced Playwright pytest tests (increased timeouts, cleanup,
  CI flag handling).  
- Merged dependabot bumps (markdownlint, release-drafter, urllib3),
  addressed style/lint (Black/isort), bug_risk/security suggestions
  iteratively.  

**Impact:** Reliable web exports, hardened CI/testing, centralized
utils, better recovery.  

**@sourcery-ai:**

Generated two detailed, accurate summaries of the PR: covered new
features (CI salt injection, local test script, ci flag), bug fixes
(web crash, corrupted saves, headless plugins, test flakiness),
enhancements (refactored key gen, shared scripts), CI updates,
and test improvements.  

**@deepsource-io / deepsource-autofix[bot]:**

Multiple auto-fix commits applying Black + isort to Python files
(inject_ci_flag.py, test_*.py). Addressed issues: unused imports,
docstring formatting, subprocess.check, line lengths. No manual comments.  

**@coderabbitai:**

Provided concise summary highlighting chores (dependency bumps),
tests (local CI script), bug fixes (web key selection, AI plugin
disable, salt handling).

**@dependabot:**

Automated project dependency maintenance by opening PRs to keep GitHub
Actions and Python libraries secure and up to date. Specific version
bumps merged during this cycle:

- Bumped `DavidAnson/markdownlint-cli2-action` from `23.0.0` to `23.2.0`.
- Bumped `release-drafter/release-drafter` from `7.2.0` to `7.3.0`.
- Bumped `urllib3` from `2.6.3` to `2.7.0`.

---
