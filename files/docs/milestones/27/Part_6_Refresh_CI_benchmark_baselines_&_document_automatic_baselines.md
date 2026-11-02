<!-- markdownlint-disable MD001 MD036 MD013 MD033 table-column-style -->
# Refresh CI benchmark baselines & document automatic baselines

---

## PR #1114 + #1116 Summary

**Titles:** Document automatic benchmark baselines; Warn on web object-count benchmark drift  
**PRs:** [#1114](https://github.com/ikostan/SkyLockAssault/pull/1114), [#1116](https://github.com/ikostan/SkyLockAssault/pull/1116) (follow-up to the first `main` run after #1114)  
**Branches:** `bug-ci-benchmark-baselines-still-expect-61-settings-saves` → `main`; `fix-web-benchmark-counts-warn-only` → `main`  
**Author:** @ikostan  
**Resolves:**

- [#1108 – [BUG] CI benchmark baselines still expect 61 settings saves after #1098](https://github.com/ikostan/SkyLockAssault/issues/1108)

**Related:** [#1107 – [EPIC] Automatic CI benchmark baselines](https://github.com/ikostan/SkyLockAssault/issues/1107) (sub-task 1), [#1098 – Persist only schema-backed settings](https://github.com/ikostan/SkyLockAssault/pull/1098), [#1109](https://github.com/ikostan/SkyLockAssault/issues/1109), [#1110](https://github.com/ikostan/SkyLockAssault/issues/1110), [#1111](https://github.com/ikostan/SkyLockAssault/issues/1111), [#1113](https://github.com/ikostan/SkyLockAssault/issues/1113)  
**Milestone:** Milestone 27: Audio feedback fixes, architecture refactor & performance validation  
**Labels:** bug, documentation, testing, GUT, QA (#1114); web, testing, CI/CD, performance, QA (#1116)

### Purpose

PR #1098 dropped settings saves from 61 to 0 on desktop and from 60 to 0 on web, but the committed CI baselines still held the #1094 merge run's values (`ee128f9`). With a count tolerance of 2, a change that brought the per-tick save back would show 61 against 61 and pass. Every other gain from #1098 was unprotected the same way.

This PR refreshes both baselines from the first `main` run after #1098, so a return to 61 fails. It also adds the epic's design doc to the repo next to the benchmark guide. The design doc was tightened along the way through review. Finally, it widens one desktop tolerance that the refreshed baseline would otherwise have made flaky.

The first `main` run after #1114 ([run 41274707348](https://github.com/ikostan/SkyLockAssault/actions/runs/41274707348), `c480f53`) was green on desktop but failed on web: `OBJECT_COUNT` and `OBJECT_NODE_COUNT` rose by 87 and 60 with no game code change. The refreshed web baseline came from a fast runner. Those two web averages follow how fast the software-rendered runner draws frames, so no useful tolerance covers them. #1116 makes them warn-only on web, like the timings. Desktop keeps them on the gate, and web keeps saves, resources, orphans and reload growth gated.

---

## Key Changes

### 1. Refreshed CI baselines (`test/benchmark/baseline_ci.json`, `baseline_web_ci.json`)

- Copied unchanged from the `benchmark-results` and `benchmark-web-results` artifacts of [run 41155653694](https://github.com/ikostan/SkyLockAssault/actions/runs/41155653694), commit `400d734`.

| Metric                     | Desktop old → new | Web old → new |
|----------------------------|------------------:|--------------:|
| Settings saves             |        61 → **0** |    60 → **0** |
| `OBJECT_COUNT` avg         |     2,551 → 2,545 | 2,303 → 2,223 |
| `OBJECT_NODE_COUNT` avg    |     509.2 → 504.0 | 515.8 → 459.0 |
| Reload loop object growth  |             6 → 2 |         0 → 0 |
| Frame interval p95 (ms)    |       17.0 → 16.8 |   43.6 → 35.7 |
| Dropped frames (> 33.4 ms) |             0 → 0 |   1,478 → 680 |

### 2. Design doc (`files/docs/Automatic_Benchmark_Baselines.md`, new)

- **Source:** the collapsible design doc in #1107, mermaid diagram included.
- **Repo fit:**
  - one H1;
  - prose wrapped at 80 columns;
  - issue and PR references turned into links;
  - a source line linking #1107 and the benchmark guide.
- **Additions from review:**
  - The ratchet and timing windows are defined as *passing* `main` runs. A failed run neither counts nor resets the streak.
  - The manual accept run checks provenance before raising anything: the workflow path, a push to `main` in this repo, both benchmark jobs and artifacts present, and the artifact `commit` equal to the run's head SHA.
  - The trigger is fixed as `workflow_call` from `lint_test_deploy.yml`, so `$GITHUB_SHA` is the measured merge commit. The manual run uses the selected run's head SHA.
  - The `baselines` job's concurrency group adds `queue: max`, so pending `main` runs are queued instead of replaced.
  - The `baselines` job gets `actions: read` for the manual path.
- **Additions in #1116:**
  - A status line: the doc is the planned design; the ratchet, rolling medians and accept path arrive with #1109 and #1111.
  - Web objects and nodes follow the timing rule (rolling median, warnings) and are never ratcheted, because a ratchet would lock in a fast-runner dip.
  - The incorrect "web nodes\_avg swings about 14" example is replaced with desktop reload growth (2 to 12 against a tolerance of 10).

### 3. Desktop reload-growth tolerance (`test/benchmark/compare.py`, `files/docs/Performance_Benchmark_Guide.md`)

- **Change:** `PROFILE_TOLERANCES["desktop"]["reload_object_growth"]` goes from 8 to 10.
- **Why:** the new baseline of 2 sits at the bottom of the 2-to-12 spread seen on runners. With 8, the fail limit dropped from 14 to 10, so a three-run median of 11 or 12 could fail on noise alone. Now 2 + 10 = 12 covers the whole spread.
- **Docs:** the comment in `compare.py` and the guide's tolerance table and text say why.

### 4. Tests (`tests/ci/test_benchmark_compare.py`)

- **Updated:** two parametrized cases (8 → 10). No cases removed.
- **Added by CodeRabbit (13 cases):**
  - the reload-growth spread fits from either end but no further;
  - both refreshed baselines pass 0 to 2 saves and fail 3 saves or a return to 61 (desktop) or 60 (web).
- **#1116:** four cases rewritten to expect a warning for web objects or nodes past their limit (none removed), plus 11 new cases: the real 459 → 519 node swing (warns on web, fails on desktop), ok and better still reported, web leak counts still fail, and the report note on web only.

### 5. Web object and node counts warn-only (#1116: `test/benchmark/compare.py`, `files/docs/Performance_Benchmark_Guide.md`)

- **Change:** new `PROFILE_WARN_ONLY = {"web": {"objects_avg", "nodes_avg"}}`. In `compare()`, a failure on those keys becomes a warning. `render()` adds a line to the web report saying which counts only warn, and `main()`'s docstring names the exception to the exit code.
- **Why:** the same code gave web `OBJECT_NODE_COUNT` 459 on a fast runner (`400d734`) and 516 to 519 on slower ones (`ee128f9`, `c480f53`). All three iterations of a run share one runner, so the median of 3 cannot smooth this out.
- **Docs:** the guide's tolerance table marks both web cells "warn only" and explains why.

---

## Review Decisions

| Reviewer         | Finding                                                                 | Decision                                                                                                                                                                                                                                 |
|------------------|-------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Qodo             | Manual accept takes any run ID; untrusted results could raise baselines | **Fixed:** provenance checks added to the design doc. `benchmark.yml` uploads stay `always()`, because accept reuses failed runs' results. The checks belong in task 4.                                                                  |
| Qodo             | `queue: max` is not a supported concurrency option                      | **Declined:** GitHub added it on May 7, 2026 ([changelog](https://github.blog/changelog/2026-05-07-github-actions-concurrency-groups-now-allow-larger-queues)), with up to 100 queued runs, valid only with `cancel-in-progress: false`. |
| CodeRabbit       | Ratchet window conflicts with "failed runs are not recorded"            | **Fixed:** both windows are defined as passing `main` runs. A consecutive-run reset would need extra state for no gain.                                                                                                                  |
| CodeRabbit       | "Option" table fails MD013 in CI                                        | **Fixed:** the CI lint runs with `fix: true`, which pads tables to 87 columns. Both tables and the mermaid block are wrapped in scoped `MD013` disables.                                                                                 |
| CodeRabbit       | Concurrency drops pending runs                                          | **Fixed:** `queue: max`.                                                                                                                                                                                                                 |
| CodeRabbit       | Use `workflow_run.head_sha` for the PR lookup                           | **Declined with clarification:** the workflow is called with `workflow_call`, which inherits the caller's `GITHUB_SHA`. The doc now states the trigger and the manual-run SHA.                                                           |
| CodeRabbit       | Manual accept needs `actions: read`                                     | **Fixed.**                                                                                                                                                                                                                               |
| CodeRabbit       | Desktop reload-growth baseline 2 with tolerance 8 can fail on noise     | **Fixed:** tolerance is now 10, with the baselines left exactly as the run produced them.                                                                                                                                                |
| Sourcery         | Empty list marker with trailing whitespace                              | **Fixed:** a stray empty list marker on the PR branch before the "Option" table.                                                                                                                                                         |
| Sourcery (#1116) | `main()` docstring still says any count regression exits 1              | **Fixed:** the docstring names `PROFILE_WARN_ONLY` and says those counts do not change the exit code.                                                                                                                                    |
| Sourcery (#1116) | Design doc promises a rolling reference that `compare()` does not have  | **Declined with clarification:** the rolling median is #1109's work. A status line now says the doc is the planned design and describes today's fixed-baseline warnings.                                                                 |

---

## Verification

- **Baselines:** both JSON files come straight from the run 41155653694 artifacts, with `commit` `400d734…` and `saves` `0.0`.
- **Comparison:** `compare.py` on that run's own `runs.csv` against the new baselines reports 0 regressions, 0 warnings and no 🟢 rows. This only shows the files load and match; a run compared with a baseline made from itself cannot fail, so it did not predict the next run.
- **First `main` run after #1114:** [run 41274707348](https://github.com/ikostan/SkyLockAssault/actions/runs/41274707348): desktop green (saves 0, reload growth 2), web failed on objects (+87) and nodes (+60), which led to #1116. Under #1116's rules the same results give Regressions 0, Warnings 3.
- **Tests:** `pytest tests/ci/test_benchmark_compare.py` gives 88 passed (64 before CodeRabbit's tests, 77 after #1114).
- **Python style:** Black and isort clean.
- **Markdown lint:** `markdownlint-cli2` with the repo config, CI's `fix: true` included, reports 0 issues.
- **CI:** all PR checks green on both PRs.
- **Still to confirm:** #1108's third criterion (next `main` run green, no 🟢 settings-saves rows) is confirmed only by the first `main` run after #1116 merges.

---

## Known Limitations / Follow-ups

- **Epic out of sync:** #1107's design doc does not have the review additions (passing-run windows, provenance checks, trigger, `queue: max`, `actions: read`) or #1116's web warn-only rule, and still says "web nodes\_avg swings about 14". The repo file is now the newer copy.
- **Tests tied to the committed baselines:** `test_committed_baseline_and_profile_gate` and `test_refreshed_baselines_gate_settings_saves` read the files on `main`. Task 6 (#1113) must rewrite them when those files are removed.
- **#1109:** its acceptance criterion now says "desktop `reload_object_growth` tolerance 10; web `objects_avg` and `nodes_avg` warn only, use the rolling median and are never ratcheted" (was "desktop 8, web `nodes_avg` 15").
- **Web-only leaks:** a leak that shows only in web objects or nodes, and not in desktop counts or web reload growth or orphans, now warns instead of failing.
- **Lint config:** `.markdownlint-cli2.yaml` sets the `MD013` options at the top level, but markdownlint-cli2 only reads rule settings under a `config:` key. So `tables: false` and `code_blocks: false` are ignored. Not changed here.

---

## Reviewer's Guide (Sourcery)

*Based on Sourcery's guides for both PRs; rows for the later review fixes were added.*

The PRs document the automatic benchmark-baseline lifecycle (count ratchets, rolling timing warnings, explicit regression acceptance, validated artifact handling and branch-based storage), refresh the desktop and web references, widen the desktop reload-growth tolerance to match observed CI variability, and make web object and node counts warn-only because they follow runner speed.

### File-Level Changes

| Change                                              | Details                                                                                                                                                                                                                                                                                                                                                  | Files                                                                                                                                                                  |
|-----------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Add the design spec for self-maintaining baselines. | <ul><li>Count ratchet over 3 passing `main` runs, beyond tolerance.</li><li>Rolling 5-run timing median, warnings only.</li><li>`benchmark-accept` label and manual accept with provenance checks.</li><li>Orphan-branch storage, permissions, `workflow_call` trigger, queued concurrency.</li><li>Six staged sub-tasks; PR runs report only.</li></ul> | `files/docs/Automatic_Benchmark_Baselines.md`                                                                                                                          |
| Refresh CI baselines from run 41155653694.          | <ul><li>Settings saves 0 on desktop and web.</li><li>All other metrics from the same run.</li></ul>                                                                                                                                                                                                                                                      | `test/benchmark/baseline_ci.json`<br/>`test/benchmark/baseline_web_ci.json`                                                                                            |
| Widen the desktop reload-growth tolerance to 10.    | <ul><li>Covers the whole 2-to-12 runner spread.</li><li>Guide table and text updated.</li></ul>                                                                                                                                                                                                                                                          | `test/benchmark/compare.py`<br/>`files/docs/Performance_Benchmark_Guide.md`                                                                                            |
| Test the tolerance and the refreshed baselines.     | <ul><li>Two cases updated to 10.</li><li>13 new cases: reload spread, return to former save counts.</li></ul>                                                                                                                                                                                                                                            | `tests/ci/test_benchmark_compare.py`                                                                                                                                   |
| Make web object and node counts warn-only (#1116).  | <ul><li>`PROFILE_WARN_ONLY` turns a web objects or nodes failure into a warning.</li><li>Web report and `main()` docstring name the exception.</li><li>Four cases rewritten, 11 new.</li><li>Guide and design doc updated; design doc status line.</li></ul>                                                                                             | `test/benchmark/compare.py`<br/>`tests/ci/test_benchmark_compare.py`<br/>`files/docs/Performance_Benchmark_Guide.md`<br/>`files/docs/Automatic_Benchmark_Baselines.md` |

### Assessment against linked issues

| Issue                                                   | Objective                                                                     | Addressed | Explanation                                                                                                                        |
|---------------------------------------------------------|-------------------------------------------------------------------------------|-----------|------------------------------------------------------------------------------------------------------------------------------------|
| <https://github.com/ikostan/SkyLockAssault/issues/1108> | Both baselines come from run 41155653694: `commit` `400d734…`, `saves` 0.0    | ✅        | Copied unchanged from the artifacts.                                                                                               |
| <https://github.com/ikostan/SkyLockAssault/issues/1108> | Add `Automatic_Benchmark_Baselines.md`, matching #1107, passing Markdown lint | ✅        | Lint clean in CI mode. Review additions go beyond #1107's copy (see Follow-ups).                                                   |
| <https://github.com/ikostan/SkyLockAssault/issues/1108> | Next `main` run green, no 🟢 settings-saves rows                              | ⏳        | Run 41274707348 failed on web objects and nodes (runner speed); fixed by #1116, confirmed by the first `main` run after it merges. |

---

## Contributors

### Human contribution (@ikostan)

- Picked up #1108 and downloaded both benchmark artifacts from run 41155653694 when the session could not reach GitHub's artifact storage.
- Applied all changes to the PR branch, ran the CI lint that caught the table padding, and brought every Sourcery, Qodo and CodeRabbit finding back for assessment.
- Approved each design-doc review fix one at a time: the queue, the trigger wording, `actions: read`, and the reload-growth tolerance.
- Requested CodeRabbit's unit tests and the #1109 criterion update.
- Decided how to release the PR relative to #1109.
- Brought back the failed web job from run 41274707348, chose the warn-only fix over re-baselining web after a side-by-side comparison, kept it out of the automated docs PR #1115, and added the design doc status line.
- Commits by @ikostan:
  - `759c1ae` Document automatic benchmark baselines
  - `ce197c8` Update Automatic_Benchmark_Baselines.md
  - `e92a21b` Document manual baseline run checks
  - `f115d61` Update Automatic_Benchmark_Baselines.md
  - `23d1a45` Widen desktop reload growth tolerance
  - `f210f1f` Warn on web object-count benchmark drift (#1116)
  - `f5cf911` Update compare.py (#1116)
  - `cfff7dc` Update Automatic_Benchmark_Baselines.md (#1116)

### Bots / AI contributions

- **@claude (Opus 5.5)**
  - **Baselines**
    - Pulled both job logs to get the expected values, then checked the artifact JSON against them.
    - Ran `compare.py` on the run's results against the new baselines: 0 regressions, 0 warnings, no 🟢 rows.
  - **Design doc**
    - Wrote `Automatic_Benchmark_Baselines.md` from #1107's design doc.
  - **Review findings**
    - Found that the new desktop baseline made reload growth flaky. Widened the tolerance to 10 and updated the code comment, the two test cases and the guide.
  - **Tests and issues**
    - Ran the CI test suite: the benchmark tests pass. The other local failures (`gdtoolkit` missing, `test_salt_injection`) are the same on clean `main`.
  - **Web failure (#1116)**
    - Traced the failure to runner speed: no game code changed, and web objects and nodes tracked dropped frames across three `main` runs. Compared re-baselining against warn-only, with a chart.
    - Wrote `PROFILE_WARN_ONLY`, the report note, the docstring fix, the four rewritten and 11 new tests, and the guide and design doc changes; updated #1109's criterion.

- **@sourcery-ai**
  - Generated the PR summary and the Reviewer's Guide (extended above).
  - Posted the #1108 requirements check (2 of 4 met, 1 by hand), which flagged the stray empty list marker; fixed.
  - Hit its 7-day review budget on the first review request.
  - #1116: generated the Reviewer's Guide and posted 2 comments: the `main()` docstring (fixed) and the rolling reference (answered with the design doc status line).

- **@coderabbitai**
  - Posted the PR summary and 6 actionable comments: 5 fixed, 1 declined with a doc clarification.
  - Authored `daec393` Add benchmark tests for desktop reload growth tolerance and settings save regressions (on request): 2 tests, 13 cases. Reviewed by @claude (Opus 5.5): all kept unchanged.
  - #1116: posted the PR summary.

- **@qodo-code-review**
  - Posted the PR summary and 2 findings: provenance checks fixed; `queue: max` "unsupported" declined (outdated; supported since May 7, 2026).
  - #1116: posted the PR summary; code review found no bugs, rule violations or requirement gaps.

- **@deepsource-io**
  - Python and JavaScript analysis pass (grade A), on both PRs.
  - `deepsource-autofix[bot]` authored `a7b0913` style: format code with Black and isort (CodeRabbit's new tests).

<!-- markdownlint-enable MD001 MD036 MD013 MD033 table-column-style -->
