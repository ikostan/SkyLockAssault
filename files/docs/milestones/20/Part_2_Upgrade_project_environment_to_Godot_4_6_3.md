# PR #754: Upgrade project environment to Godot 4.6.3
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

**Author:** [@ikostan](https://github.com/ikostan)  
**Status:** Merged (as of latest activity)  
**Linked Epic/Issue:** [#747](https://github.com/ikostan/SkyLockAssault/issues/747)  
**Milestone:** Milestone 20: Resource-Based Settings & UI Acoustic Integration

#### Overview

This comprehensive PR upgrades the **SkyLockAssault** project from Godot 4.5.stable to **Godot 4.6.3.stable**. The update modernizes the development, testing, and deployment environment while introducing robustness improvements, security enhancements, and better test isolation. It addresses compatibility constraints with newer add-ons and resolves various engine behavior changes.

Add a reusable script and workflow wiring to validate Godot engine assets and checksums during CI/CD and deployment.

#### Key Changes

**Major Upgrade**

- Core project updated to Godot 4.6.3 across `project.godot`, scenes, Docker, CI/CD workflows, and documentation.
- Added legacy `obsolete/godot_4.5_stable/Dockerfile` for archival and fallback purposes.

**Security & Reliability Enhancements**

- Added SHA-256 checksum verification for all downloaded Godot binaries and export templates in CI workflows and Dockerfile.
- Improved `AudioManager` with safer audio bus handling (`apply_volume_to_bus` guards against invalid `AudioServer` access or missing buses) and a new `cleanup_for_test()` helper for deterministic test cleanup.
- Fixed encrypted `ConfigFile` crashes by seeding dummy data before encryption in test fixtures.

**Testing Improvements**

- Hardened GUT and GDUnit4 test suites for compatibility with Godot 4.6.3.
- Enhanced `workspace/run_gut_unit_tests.sh` with temporary gdUnit4 disable/restore logic and better cache handling.
- Increased verbosity and reliability in CI test jobs (GDUnit4, GUT, browser tests).
- Updated test scenes and configurations (`audio_settings.tscn`, `default_bus_layout.tres`, etc.).

**CI/CD Updates**

- Updated workflows: `gdunit4_tests.yml`, `gut_tests.yml`, `browser_test.yml`, `deploy_to_itch.yml`.
- Bumped GDUnit4 to v6.1.3 where applicable.
- Refined Docker setup (Playwright dependencies, quiet downloads, etc.).

**New Features**

- Introduce a verify_godot.sh script to download Godot binaries, fetch checksum manifests from official mirrors, and validate asset integrity.

**Bug Fixes**

- Fix deployment workflow failures by validating Godot download URLs and checksum sources before starting exports.

**Enhancements**

- Refactor the deployment workflow to delegate Godot download and verification to a shared script and parameterize the Godot version via workflow inputs.
- Extend the CI infrastructure test workflow to exercise the Godot asset verification script with a configurable version.
- Wire lint/test workflows to pass a specific Godot version into shared CI/CD infrastructure tests.

**Documentation**

- Updated README.md with new Godot version, supported tools, and Windows compatibility notes.

---

## Reviewer's Guide

Upgrades the project toolchain and CI from Godot 4.5 to 4.6.3, introduces a legacy 4.5 Docker image, hardens automated test workflows (GDUnit4/GUT), and improves audio-related robustness and test isolation around config encryption and audio buses.

Centralizes Godot binary download and checksum verification into a reusable script, wires it into deploy and CI workflows, and propagates a configurable Godot version parameter across pipelines to prevent 404s and ensure cryptographic verification of engine assets.

### File-Level Changes

| Change                                                                                                                              | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Files                                                                                                                                                                                            |
|-------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Upgrade primary Docker image and CI workflows to Godot 4.6.3 and refresh test tooling versions.                                     | <ul><li>Bump GODOT_VERSION env in the main Dockerfile and switch Godot binary/export template downloads to the 4.6.3-stable release with SHA-256 verification.</li><li>Update GDUnit4 installation in Docker and gdunit4_tests workflow from v6.0.0 to v6.1.3, and ensure wget is quiet where appropriate.</li><li>Adjust Playwright installation in the Dockerfile to avoid redundant install-deps invocation while still installing Chromium with dependencies.</li><li>Update README project overview to reference Godot 4.6.3, newer Docker Desktop and GitHub Desktop versions, and expanded Windows support.</li></ul>                            | `Dockerfile`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`<br/>`.github/workflows/browser_test.yml`<br/>`.github/workflows/deploy_to_itch.yml`<br/>`README.md` |
| Introduce a legacy Godot 4.5 environment for backward compatibility.                                                                | <ul><li>Add an obsolete Dockerfile under obsolete/godot_4.5_stable that preserves the previous Ubuntu-based Godot 4.5 toolchain with GDUnit4, GUT, and Playwright configured similarly to the prior main Docker image.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                        | `obsolete/godot_4.5_stable/Dockerfile`                                                                                                                                                           |
| Improve audio manager safety and test isolation to avoid crashes and resource leaks.                                                | <ul><li>Guard AudioManager.apply_volume_to_bus against invalid AudioServer access and missing audio buses before performing operations.</li><li>Add cleanup_for_test helper on AudioManager to clear caches, stop and free SFX players, and recreate the pool for deterministic test cleanup.</li><li>Hook AudioManager.cleanup_for_test and file deletion into GUT tests’ after_each to ensure test artifacts and audio resources are reset between runs.</li><li>Likely adjust audio-related scene and bus layout files to align with upgraded audio settings and IDs (default_bus_layout.tres, project.godot, scenes/audio_settings.tscn).</li></ul> | `scripts/managers/audio_manager.gd`<br/>`test/gut/test_basic_save_load_without_other_settings.gd`<br/>`default_bus_layout.tres`<br/>`project.godot`<br/>`scenes/audio_settings.tscn`             |
| Work around Godot’s encrypted ConfigFile 0-byte buffer crash in tests by seeding dummy data before encryption.                      | <ul><li>Update various tests that save encrypted ConfigFile fixtures to set a trivial value under a meta section before calling save_encrypted_pass, preventing engine crashes when encrypting empty files.</li><li>Ensure test fixtures for audio persistence, settings loading, and input device persistence all follow this pattern.</li></ul>                                                                                                                                                                                                                                                                                                       | `test/gut/test_basic_save_load_without_other_settings.gd`<br/>`test/gut/test_settings_ec.gd`<br/>`test/gut/test_ui_audio_persistence.gd`<br/>`test/gdunit4/test_settings.gd`                     |
| Harden local and CI GUT/GDUnit4 test execution scripts for reliability and clearer diagnostics.                                     | <ul><li>Enhance workspace/run_gut_unit_tests.sh to temporarily disable the GDUnit4 addon while running GUT tests, restoring it via a trap-based cleanup function, and narrow the test directory to res://test/gut/.</li><li>Update gdunit4_tests and gut_tests workflows to download Godot 4.6.3 with checksum verification, clean .godot cache before GUT runs, and enable verbose output for easier debugging of CI failures.</li></ul>                                                                                                                                                                                                               | `workspace/run_gut_unit_tests.sh`<br/>`.github/workflows/gdunit4_tests.yml`<br/>`.github/workflows/gut_tests.yml`                                                                                |
| Update documentation and milestone notes for the new Godot 4.6.3 environment and tooling.                                           | <ul><li>Refresh README to note Godot 4.6.3 stable, add Windows 11 support, and bump listed Docker Desktop and GitHub Desktop versions.</li><li>Add a milestone documentation file describing PR #754’s scope, key changes, review guide, and contributor roles for the Godot 4.6.3 upgrade.</li></ul>                                                                                                                                                                                                                                                                                                                                                   | `README.md`<br/>`files/docs/milestones/20/Part_2_Upgrade_project_environment_to_Godot_4_6_3.md`                                                                                                  |
| Introduce reusable Godot binary verification script with robust checksum manifest lookup and integrity checks.                      | <ul><li>Create verify_godot.sh to download Godot executable and export templates for a given version into a fresh staging directory.</li><li>Validate target asset URLs upfront with HEAD requests to fail fast on 404 or invalid URLs.</li><li>Download binaries from GitHub and locate official checksum manifests from TuxFamily or SourceForge mirrors, preferring SHA-256 but falling back to SHA-512 as needed.</li><li>Extract only the checksums for the targeted assets into a local manifest, assert both entries are present, and verify with sha256sum or sha512sum accordingly.</li></ul>                                                  | `.github/scripts/verify_godot.sh`                                                                                                                                                                |
| Refactor deploy_to_itch workflow to delegate Godot asset handling to the shared verification script and parameterize Godot version. | <ul><li>Add a godot_version input with a default value to the deploy_to_itch workflow.</li><li>Replace inline Godot binary download and SHA256 verification logic with a call to verify_godot.sh passing the configured Godot version.</li><li>Assume the script creates a godot_binaries directory, cd into it, and serve assets via a local HTTP server for the export step.</li><li>Switch export action URLs to reference the versioned filenames served from the local HTTP server using the workflow input godot_version.</li></ul>                                                                                                               | `.github/workflows/deploy_to_itch.yml`                                                                                                                                                           |
| Extend CI infrastructure tests to cover Godot asset verification and propagate version input from calling workflows.                | <ul><li>Add a required godot_version input to the test_ci_scripts reusable workflow.</li><li>Append a job step that chmods and executes verify_godot.sh with the provided godot_version to validate asset retrieval and verification as part of CI tests.</li><li>Update lint_test_deploy and lint_test_on_pull workflows to pass a concrete Godot version into the CI scripts workflow for consistent behavior.</li></ul>                                                                                                                                                                                                                              | `.github/workflows/test_ci_scripts.yml`<br/>`.github/workflows/lint_test_deploy.yml`<br/>`.github/workflows/lint_test_on_pull.yml`                                                               |

### Assessment against linked issues

| Issue                                                | Objective                                                                                                                                                                                           | Addressed | Explanation |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------|-------------|
| <https://github.com/ikostan/SkyLockAssault/issues/747> | Update the project configuration and documentation to target Godot 4.6.3 instead of 4.5.                                                                                                            | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/747> | Update the Docker-based development environment and related tooling to install and use Godot 4.6.3, while keeping any needed legacy 4.5 support isolated.                                           | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/747> | Update CI/CD workflows (exports and test suites) and test code so that automated tests and exports run successfully under Godot 4.6.3, including compatibility with GUT and GDUnit4.                | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/749> | Update `godot_executable_download_url` in `.github/workflows/browser_test.yml` to use the Godot 4.6.3-stable Linux binary URL.                                                                      | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/749> | Update `godot_export_templates_download_url` in `.github/workflows/browser_test.yml` to use the Godot 4.6.3-stable export templates URL.                                                            | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/751> | Update the `gdunit4_tests.yml` workflow to download and use the Godot 4.6.3-stable Linux binary instead of 4.5-stable.                                                                              | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/751> | Ensure the GDUnit4 version used in the `gdunit4_tests.yml` workflow is compatible and stable with Godot 4.6.3 (including adjusting the installed GDUnit4 version if needed).                        | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/751> | Keep GDUnit4 automated test execution and report generation in the `gdunit4_tests.yml` workflow functional after upgrading to Godot 4.6.3.                                                          | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/752> | Update the gut_tests.yml GitHub Actions workflow to download and use the Godot 4.6.3-stable Linux binary for running GUT tests.                                                                     | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/752> | Ensure GUT v9.5.0 works correctly with Godot 4.6.3 for project initialization and test execution (including any necessary compatibility fixes or setup).                                            | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/752> | Maintain correct generation and handling of GUT test artifacts (e.g., JUnit XML) and preserve existing CI reporting integrations such as Codecov when moving to Godot 4.6.3.                        | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/753> | Update the Dockerfile ENV GODOT_VERSION value to use Godot 4.6.3-stable.                                                                                                                            | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/753> | Update the Dockerfile Godot engine binary and export template download URLs to use the 4.6.3-stable artifacts.                                                                                      | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/755> | Fix the CI/CD `Deploy to itch.io` workflow so that the Godot checksum manifest is fetched from a valid URL (no 404) and the downloaded binaries are cryptographically verified before export.       | ✅         |             |
| <https://github.com/ikostan/SkyLockAssault/issues/755> | Make the Godot version used in CI/CD workflows configurable while ensuring the deploy workflow and related CI tests correctly pass and use this version for downloading and verifying Godot assets. | ✅         |             |

### Possibly linked issues

- **#N/A**: PR upgrades engine version, Dockerfile, and all CI workflows to Godot 4.6.3 as requested in the feature issue.
- **#**: PR fulfills the issue by switching Dockerfile to Godot 4.6.3 and updating binary/template download URLs.
- **#[BUG] CI/CD deployment workflow fails with 404 on Godot checksum download**: PR replaces the broken checksum URL with a robust verification script, fixing the 404 failure in deploy workflow.
- **#**: They both update deploy_to_itch.yml to use Godot 4.6.3-stable binaries/templates; PR also adds verification and CI tests.

---

#### Contributors

### AI/Bot-Assisted Contributions (@sourcery-ai, @coderabbitai, etc.)

- **@sourcery-ai**: Generated a detailed PR summary highlighting new features (e.g., AudioManager cleanup helper), bug fixes (e.g., encrypted ConfigFile crash prevention, audio bus guards), enhancements (Godot/Docker/CI updates, checksum verification), and testing improvements. Also contributed a Reviewer's Guide with sequence diagrams, file-level change breakdowns, and issue linkage assessment. This aided in structuring the PR description and review process.
- **@coderabbitai**: Provided a concise summary categorizing changes into Chores (toolchain upgrades, project settings), Bug Fixes (config reliability, audio handling), Tests (CI hardening), and Refactor (stable IDs in scenes). One commit explicitly lists co-authorship with @ikostan (e.g., updates to browser_test.yml or related files), indicating direct code suggestions or automated edits integrated by the maintainer.
- **Other potential bots**: No direct commits or mentions of @dependabot in this PR. Standard GitHub bots (e.g., for actions or workflows) may have run in the background but are not prominently featured in conversation or commits.

**DeepSource Review**: No explicit mentions, comments, or contributions from DeepSource (e.g., @deepsource-io or similar) were visible in the PR conversation, commits, or summaries. If DeepSource was configured for static analysis/linting, its review may have occurred implicitly via CI without a named bot comment.

These tools enhanced code quality, documentation, and maintainability without replacing core human-driven changes.

### Human Contributions (@ikostan)

**@ikostan** (primary maintainer and author): Drove the entire PR as the main contributor. Key efforts include:

- Planning and executing the Godot 4.6.3 upgrade across core files, workflows (browser_test.yml, gdunit4_tests.yml, gut_tests.yml, deploy_to_itch.yml), Dockerfile (with legacy 4.5 archival), project.godot, scenes, and test scripts.
- Implementing bug fixes and robustness improvements (e.g., AudioManager guards/cleanup, empty ConfigFile handling to prevent crashes, GUT/GDUnit4 compatibility).
- Adding security enhancements (SHA-256 checksum verification for downloads).
- Refining tests, runner scripts, README, and CI for stability/verbosity.
- Multiple iterative commits for polishing (e.g., GDUnit4 bumps, audio settings updates, cache handling).

#### Impact

- Ensures long-term maintainability and compatibility with the Godot ecosystem.
- Strengthens supply-chain security via checksum verification.
- Improves developer experience through more stable and verbose testing.
- Maintains backward compatibility via the archived 4.5 Docker image.

This PR exemplifies a well-structured toolchain upgrade with proactive fixes for edge cases in testing and audio systems.
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
