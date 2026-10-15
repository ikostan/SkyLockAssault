<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Optimize AI context window: production code bundler

---

## PR #1036 Summary

**Title:** Optimize AI context window: upgrade project scanner & bundler  
**PR:** [#1036](https://github.com/ikostan/SkyLockAssault/pull/1036)  
**Branch:** `optimize-ai-context-window-upgrade-project-scanner-bundler` → `main`  
**Author:** @ikostan  
**Closes:** [#623 – [FEATURE] Optimize AI Context Window: Upgrade Project Scanner & Bundler](https://github.com/ikostan/SkyLockAssault/issues/623)  
**Related:** [#624 – [TASK] Phase 3: Execute Global Architectural Review (Master Bundle)](https://github.com/ikostan/SkyLockAssault/issues/624) (the review itself is posted in the issues, not in this PR)  
**Milestone:** Milestone 26: Comprehensive Architectural Review & Performance Benchmarking  
**Labels:** CI/CD, enhancement, tools  

### Purpose

Add a separate script that merges all production GDScript into one deterministic text file, so the whole codebase can be handed to a high-context AI tool in a single upload. `workspace/scan_project.py` (folder/file tree) stays unchanged: the tree gives the layout, the bundle gives the code.

The production code is small (36 files, ~9.6k lines, ~85k tokens), so no complex exclusion list is needed. The original requirement to preserve `addons/ai_autonomous_agent/` was dropped because that addon no longer exists.

### Key Changes

- **Bundler** (`workspace/bundle_production_code.py`, new)
  - Collects `scripts/**/*.gd` only. `.gd.uid`, `.import`, `.tscn`, `.tres`, binaries, and anything inside a `test/` or `tests/` folder (any depth) are excluded
  - Sorted by repo-relative path; each file wrapped in `===== START OF FILE: <path> =====` / `===== END OF FILE: <path> =====`
  - LF output on every OS; CRLF and bare-CR sources are normalized; a missing final newline is added before the END marker
  - Repo root resolved from the script's own location, so it runs from any working directory
  - Writes `production_code_bundle.txt` at the repo root through a temp file plus `os.replace()` (atomic)
- **Header metadata**
  - `Commit:` HEAD SHA, with `-dirty` when `scripts/` differs from HEAD in any way (modified, untracked, staged, deleted or git-ignored files)
  - `Content SHA-256:` digest of the bundled body, so every working-tree version is exactly identifiable, even when the commit is `-dirty`
  - File count, source line count, rough token estimate (~4 characters per token)
- **Safety**
  - Symlinks are never followed: a symlinked `scripts/` is rejected; symlinked files or folders below it are skipped and reported as warnings
  - A failed run (no `scripts/`, symlinked `scripts/`, no eligible files) exits 1 and deletes any stale bundle
  - Git runs through `shutil.which("git")` with a 10 s timeout and with git's repository-override variables removed (`git rev-parse --local-env-vars`)
  - The SHA is only used when git's top-level folder *is* the project root; otherwise `Commit: unknown`
- **Tests** (`tests/ci/test_bundle_production_code.py`, new)
  - 33 test functions, 58 cases with parametrization: CLI tests against an isolated fake repo, plus unit tests of `collect_files`, `build_bundle`, `get_commit_sha` and `main`
  - Every git call in the tests is isolated from inherited `GIT_*` variables, so the suite is safe to run from a git hook
- **`.gitignore`**: adds `production_code_bundle.txt` (`project_structure.txt` was already ignored)

### Usage

```bash
python workspace/scan_project.py            # -> project_structure.txt (tree)
python workspace/bundle_production_code.py  # -> production_code_bundle.txt (code)
```

Sample header from `main` @ `5315844`:

```text
SkyLockAssault - Production Code Bundle
Commit: 5315844957ef0abb39a1d04afadf689264c84236
Content SHA-256: ef0c979fdc5b759d6706f6e2b8df93606f972e2fd1761a9c10988e1e2bd003ce
Source: scripts/**/*.gd
Files: 36
Lines: 9573
Estimated tokens: ~84,638
```

### Design Decisions

- **Separate script, `scan_project.py` untouched.** The tree and the bundle do different jobs, and neither replaces the other.
- **Report symlinks, don't follow them.** Following a linked folder would reintroduce the external-file problem the symlink checks prevent.
- **Delete the stale bundle on failure.** A previous bundle left at the canonical path could be uploaded by mistake as if it were current.
- **Content digest instead of snapshotting.** A consistent tree snapshot (`git stash`/worktree) would touch the user's working tree; the digest identifies the exact code without that risk.
- **Remove git's own list of repo-local variables** (15), not a hand-picked subset. `GIT_CEILING_DIRECTORIES` is intentionally kept, so the tests' fake repos stay isolated.

### Testing

- `tests/ci/test_bundle_production_code.py`: 58 passed
- Same suite with `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE` pointing at the real repo: 58 passed, real HEAD unchanged
- New tests fail against the earlier script versions (verified for the symlink, stale-bundle, ignored-file, timeout and env-isolation fixes)
- Real repo: 36 files, 9,573 lines, clean SHA; two runs produce byte-identical output
- `ruff check` / `ruff format`: clean on both files
- [ ] CI infrastructure tests pass on the PR (`tests/ci/` runs via `lint_test_on_pull.yml` for `workspace/**/*.py` and `tests/ci/**`)
- [ ] Windows: symlink tests skip cleanly where the account can't create symlinks

### Compatibility

- No gameplay, scene or runtime change; a local dev helper plus its CI tests
- `scan_project.py` and its output are unchanged
- Requires Python 3.10+ (`write_text(newline=...)`, `X | None` type hints)

### Follow-ups

- `scan_project.py` has its own quirks (writes to the current folder, unsorted output, lists its own output file). A small fix-up with tests can be a separate issue
- The global review (#624) produced findings now tracked in #616–#621; #622 (Region 7) closes as obsolete

---

## Reviewer's Guide

Adds a standalone, deterministic bundler that concatenates production GDScript under `scripts/` into `production_code_bundle.txt`, with commit and content-digest metadata, symlink and stale-output protection, isolated git metadata calls, and a CI test suite that is safe to run from git hooks.

### File-Level Changes

| Change                                        | Details                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Files                                                                                   |
|-----------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------|
| Add the production code bundler.              | <ul><li>Collect <code>scripts/**/*.gd</code>, excluding sidecars and <code>test/</code>/<code>tests/</code> folders, sorted by path.</li><li>Wrap each file in START/END markers; normalize to LF.</li><li>Header with commit (<code>-dirty</code> aware), content SHA-256, counts and token estimate.</li><li>Reject a symlinked <code>scripts/</code>, skip and report symlinks below it, delete stale output on failure, write atomically.</li><li>Git via <code>shutil.which</code>, 10 s timeout, repo-override variables removed, repo-root check.</li></ul> | `workspace/bundle_production_code.py`                                                   |
| Test the bundler.                             | <ul><li>CLI tests on isolated fake repos and unit tests for each function.</li><li>Cover filtering, ordering, markers, line endings, header, git metadata, symlinks, atomic and failed writes, timeouts and inherited <code>GIT_*</code> variables.</li></ul>                                                                                                                                                                                                                                                                                                      | `tests/ci/test_bundle_production_code.py`                                               |
| Ignore the generated bundle.                  | <ul><li>Add <code>production_code_bundle.txt</code>.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | `.gitignore`                                                                            |
| Record the implementation and review context. | <ul><li>Add the milestone note for this part.</li></ul>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | `files/docs/milestones/26/Part_3_Optimize_AI_context_window_production_code_bundler.md` |

### Assessment against linked issues

| Issue                                                  | Objective                                                                                                             | Addressed | Explanation                                                     |
|--------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/623> | Separate bundler for production `.gd` files under `scripts/`, excluding sidecar, non-code and test files.             | ✅        | Includes `scripts/test/` and `scripts/tests/` at any depth.     |
| <https://github.com/ikostan/SkyLockAssault/issues/623> | Deterministic, portable bundle with path markers, metadata header, LF output and repo-root output from any directory. | ✅        |                                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/623> | `scan_project.py` unchanged; generated outputs gitignored; CI tests for behavior and failure cases.                   | ✅        |                                                                 |
| <https://github.com/ikostan/SkyLockAssault/issues/624> | Global architectural review.                                                                                          | n/a       | Not part of this PR; findings are posted on #624 and #616–#622. |

---

## PR #1036 Summary

### Human contribution (@ikostan)

- **Planning and scope**
  - Revisited #623 and #624 after months of inactivity, checked whether they were still relevant, and rewrote both issues for the current codebase.
  - Set the design: keep `scan_project.py` unchanged as the layout tool and add the bundler as a separate script, so the project keeps both the tree and the code bundle.
  - Required CI tests for the bundler and kept every change local until reviewed.
- **Implementation and integration**
  - Opened the PR, integrated and committed every iteration of the bundler and its tests, and resolved the merge with the CodeRabbit commits.
- **Review leadership**
  - Ran the review loop across four bots (Sourcery, CodeRabbit, Qodo, DeepSource), brought each finding forward for triage, and decided what to fix, decline or mark as a false positive.
  - Replied to and resolved every review thread.
- **Architectural review (#624)**
  - Reviewed the global findings and filed them into the regional issues #616–#621, and closed out obsolete Region 7 (#622).
- **Documentation**
  - Defined the milestone-note format and edited this summary.

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - Drafted the bundler, its tests and the updated issue texts, and helped triage the bot findings.
  - Carried out the #624 global review and drafted the per-region findings.

- **@sourcery-ai**
  - Generated "Summary by Sourcery" and the Reviewer's Guide with the linked-issue assessment.
  - Posted 7 inline findings (symlinks, output symlink, atomic writes, stale bundle, mixed revisions, ignored files, symlinked folders) plus 2 opengrep security warnings (false positives).

- **@coderabbitai**
  - Authored `5a4cb0a` (expanded unit tests: filtering, content handling, git metadata, output validation) and `d68de18` (expanded docstrings).
  - Posted 3 findings: inherited git variables in the tests (Major), git timeouts (Minor), repo overrides in the bundler (Minor).

- **@qodo-code-review**
  - Posted a PR summary with a diagram and a file breakdown.
  - Posted 3 findings: linked source root (High), copied project reports the wrong commit (Medium), edited bundles not traceable (Medium).

- **@deepsource-io** (DeepSource / deepsource-autofix)
  - Ran static analysis and posted the report card.
  - Authored `27593e7` (`style: format code with Black and isort`).
  - Posted findings: partial executable path (×2), backslash in docstring, doc line length, missing docstring, `next()` outside try-except.

---
<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
