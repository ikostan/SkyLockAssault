# CI/CD Production Salt Injection & Security Guard Architecture

This document defines the architectural design, code contracts, and
verification gates governing the production encryption salt injection
pipeline. This system ensures that production builds are securely
provisioned with a cryptographic salt while explicitly preventing
silent, weak-key fallbacks or build-time code corruption.

---

## 1. Architectural Overview

The game utilizes a deterministic SHA-256 key derivation architecture
for local configuration encryption, combining unique hardware
identifiers with a project-specific salt. To preserve open-source
integrity, the true production salt is completely decoupled from the
source control repository and injected exclusively during the
automated release pipeline hosted on GitHub Actions.

To ensure the system fails safe, the codebase contains a runtime
**Security Guard**. If a production build executes without a
successfully provisioned secret, the engine triggers an immediate,
explicit crash to protect player data from weak encryption fallbacks.

---

## 2. The Shared Code Contract

The integration between the automation layer (`inject_salt.sh`) and
the engine singleton (`globals.gd`) is established via a strict
structural text contract. Two explicit code patterns serve as the
single source of truth:

<!-- markdownlint-disable line-length table-column-style -->
| Pattern Type        | Exact GDScript Code Literal                | Pipeline Role                                             |
|:--------------------|:-------------------------------------------|:----------------------------------------------------------|
| **Variable Target** | `var salt: String = "CI_INJECT_SALT_HERE"` | The token targeted for cryptographic secret substitution. |
| **Guard Target**    | `if salt == "CI_INJECT_SALT_HERE":`        | The logical gate scanned to verify structural integrity.  |
<!-- markdownlint-enable line-length table-column-style -->

Both literals must remain perfectly identical in both the application
source code and the automation scripts. Modifying or splitting these
strings in either environment will cause an intentional build-stage
failure.

---

## 3. The Injection Pipeline Workflow

The script `inject_salt.sh` processes the engine singleton using a
precise, non-greedy stream editing sequence:

1. **Environment Secret Extraction:** The pipeline retrieves the raw
   `PRODUCTION_SALT` secret from the secure GitHub environment.
2. **Newline & CR Stripping:** All carriage returns and newlines are
   stripped (`tr -d '\r\n'`) to ensure whitespace formatting
   variations do not truncate or corrupt the string literal parsing
   downstream.
3. **Godot Parser Escaping:** Special characters like backslashes
   (`\`) and double quotes (`"`) are escaped to match Godot's
   internal string syntax requirements.
4. **Sed Delimiter Escaping:** Delimiters like pipes (`|`),
   ampersands (`&`), and regex-specific tokens are escaped to
   safeguard the `sed` substitution execution.
5. **Targeted Substitution:** The `sed` operation explicitly bounds
   the pattern matching to the variable assignment statement
   (`TARGET_VAR_PATTERN`), functioning as a surgical replacement
   rather than a blind, global search-and-replace sweep.

---

## 4. Automated Verification Gates

To ensure no corrupted code is ever compiled or shipped to production,
the injection script executes three hard validation checkpoints
immediately following the substitution step. If any check fails, the
pipeline exits with a non-zero status (`exit 1`) and aborts the
deployment:

* **The Empty Input Gate:** Validates that the sanitized secret payload
  is not empty. If an environment configuration failure occurs and the
  secret evaluates to blank, the pipeline triggers a hard stop.
* **The Substitution Verification Gate:** Executes a fast `grep` check
  on the file for the original `TARGET_VAR_PATTERN`. If the literal
  pattern is still present, the pipeline declares an injection failure
  and terminates.
* **The Guard Integrity Gate:** Executes a fast `grep` check on the
  file for the original `TARGET_GUARD_PATTERN`. If this exact
  conditional block cannot be found, it indicates that the structural
  logic was accidentally corrupted or globally overwritten during the
  injection. The pipeline throws a fatal error and halts the build.

---

## 5. Automated Regression Protection

To permanently eliminate configuration regression or accidental deletion
of these safety mechanisms, the infrastructure test suite
(`test_salt_injection.py`) strictly enforces both positive and negative
validation paths via automated testing:

* **Value Rigidity Testing:** Validates that complex passwords
  containing multi-line content, special regex tokens, backreferences,
  path slashes, and Unicode characters are safely handled without
  breaking the script execution or polluting the workspace with temporary
  file artifacts.
* **Target Isolation Testing:** Mocks files containing multiple
  placeholder strings across dictionaries and conditionals to verify
  that the injection logic targets *only* the variable assignment while
  leaving downstream references unaffected.
* **Missing Guard Failure Testing (Negative Path):** Simulates an
  invalid source code file where a developer has omitted the safety
  check block. Asserts that `inject_salt.sh` successfully catches the
  omission, throws a fatal error, and flags a non-zero exit status.
* **Malformed Guard Failure Testing (Negative Path):** Simulates a file
  where the safety check contains a typo or structural deviation. Asserts
  that the script actively blocks the compilation process, enforcing code
  discipline prior to any external deployment.
