# Upgrade Godot to 4.7.1 and add GDUnit4 coverage CI
<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->

---

Upgrade the project to Godot 4.7.1 and add resilient GDUnit4 code coverage reporting to the CI pipeline.

New Features:

- Add GDUnit4 coverage profiling to CI, including LCOV aggregation and Codecov uploads for coverage and test results.

Enhancements:

- Upgrade project tooling and CI workflows to Godot 4.7.1 with engine version and checksum validation.
- Update GDUnit4 and GUT test dependencies to newer releases.
- Improve GDUnit4 CI reliability by isolating test suites into memory-conscious batches and supporting unauthenticated runs without Codecov secrets.
- Align Codecov configuration with GDUnit4 coverage reporting and exclude test and addon sources from coverage.
- Refresh the development container with Godot 4.7.1 and updated export templates and testing dependencies.

---



---



---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
