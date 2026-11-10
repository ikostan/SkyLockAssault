# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_test_summary.py
"""Tests for .github/scripts/test_summary.py, the CI test result summaries (#1156).

The XML files in tests/ci/data/test_summary/ are real, unedited output of the
tools and versions each job runs, from a small sample suite with passing,
failing, skipped and erroring tests:

- gut_junit.xml: GUT 9.7.1 on Godot 4.7.1-stable, run like gut_tests.yml.
- gdunit4_results.xml: gdUnit4 6.2.0 on Godot 4.7.1-stable with -c, from
  reports/report_1/results.xml.
- gdunit4_fail_fast.xml: the same suite run like gdunit4_tests.yml (no -c):
  gdUnit4 stops at the first failing test, so the XML declares 4 tests but
  holds 1 result.
- pytest_xunit2.xml: pytest 9.1.1 --junitxml (test_ci_scripts.yml).
- pytest_legacy.xml: the same with -o junit_family=legacy (browser_test.yml).
"""

import importlib.util
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

import pytest
import yaml

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = PROJECT_ROOT / ".github/scripts/test_summary.py"
SCRIPT_REF = ".github/scripts/test_summary.py"
DATA = PROJECT_ROOT / "tests/ci/data/test_summary"
# Listed by name, not globbed: a missing sample must fail, not skip its tests.
SAMPLES = (
    "gdunit4_fail_fast.xml",
    "gdunit4_results.xml",
    "gut_junit.xml",
    "pytest_legacy.xml",
    "pytest_xunit2.xml",
)
WORKFLOWS = PROJECT_ROOT / ".github/workflows"

PASSING_XML = """<?xml version="1.0" encoding="utf-8"?>
<testsuites name="pytest tests">
  <testsuite name="pytest" errors="0" failures="0" skipped="{skipped}"
      tests="{tests}" time="0.1">
    {cases}
  </testsuite>
</testsuites>
"""


@pytest.fixture(scope="module")
def summary():
    """Load test_summary.py as a module (.github/scripts is not a package)."""
    spec = importlib.util.spec_from_file_location("ci_test_summary", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    # Dataclasses look their module up in sys.modules while being created.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    yield module
    sys.modules.pop(spec.name, None)


def run(summary, tmp_path: Path, results: str, title: str = "Tests") -> str:
    """Run main() like a workflow step and return what it appended."""
    out = tmp_path / "step_summary.md"
    code = summary.main(["--title", title, "--results", results, "--summary", str(out)])
    assert code == 0
    return out.read_text(encoding="utf-8")


def passing_xml(path: Path, passed: int, skipped: int = 0) -> Path:
    """Write a pytest-style XML with only passing and skipped tests."""
    cases = [
        f'<testcase classname="t" name="test_{i}" time="0.01"/>' for i in range(passed)
    ]
    cases += [
        f'<testcase classname="t" name="test_skip_{i}" time="0">'
        '<skipped message="later"/></testcase>'
        for i in range(skipped)
    ]
    path.write_text(
        PASSING_XML.format(
            skipped=skipped, tests=passed + skipped, cases="\n    ".join(cases)
        ),
        encoding="utf-8",
    )
    return path


# ---------------------------------------------------------------------------
# Real XML from each job
# ---------------------------------------------------------------------------


def test_every_sample_is_present():
    """The tests below read these files; without them they can't check anything."""
    missing = [name for name in SAMPLES if not (DATA / name).is_file()]

    assert not missing, f"missing from tests/ci/data/test_summary/: {missing}"


@pytest.mark.parametrize(
    "sample, passed, failed, errors, skipped",
    [
        # GUT: the pending test is skipped; the risky one has no failure, so passes.
        ("gut_junit.xml", 2, 2, 0, 1),
        ("gdunit4_results.xml", 1, 2, 0, 1),
        ("gdunit4_fail_fast.xml", 0, 1, 0, 0),
        # pytest: the xfail is skipped, the fixture failure is an error.
        ("pytest_xunit2.xml", 2, 2, 1, 2),
        ("pytest_legacy.xml", 2, 2, 1, 2),
    ],
)
def test_counts_come_from_each_jobs_real_xml(
    summary, sample, passed, failed, errors, skipped
):
    """Each job's real XML gives the right count per outcome."""
    results = summary.read_results(str(DATA / sample))

    assert results.problems == []
    assert results.count(summary.PASSED) == passed
    assert results.count(summary.FAILED) == failed
    assert results.count(summary.ERROR) == errors
    assert results.count(summary.SKIPPED) == skipped
    total = passed + failed + errors + skipped
    assert f"| {passed} | {failed} | {errors} | {skipped} | {total} |" in (
        summary.render("T", results)
    )


def test_gut_counts_tests_not_failed_asserts(summary):
    """GUT's suite failures attribute counts asserts (3); 2 tests failed."""
    root = ET.parse(DATA / "gut_junit.xml").getroot()
    assert root.find("testsuite").get("failures") == "3"

    results = summary.read_results(str(DATA / "gut_junit.xml"))
    assert results.count(summary.FAILED) == 2
    assert results.not_run == 0


@pytest.mark.parametrize(
    "sample, name, message",
    [
        # GUT writes message="failed" and the real message in the text.
        (
            "gut_junit.xml",
            "test/gut_sample/test_summary_sample.gd::test_fails_with_message",
            '["a|b"] expected to equal ["c"]:  pipe | and <angle> & quote " chars',
        ),
        (
            "gut_junit.xml",
            "test/gut_sample/test_summary_sample.gd::test_fails_twice",
            "first failure",
        ),
        # gdUnit4 writes message="FAILED: res://...:18" and the message in the text.
        (
            "gdunit4_results.xml",
            "summary_sample_test::test_fails_with_message",
            "pipe | and <angle> & chars",
        ),
        # pytest's message attribute is the message; its text is the traceback.
        (
            "pytest_xunit2.xml",
            "test_summary_sample::test_fails_with_message",
            "AssertionError: pipe | and <angle> & chars",
        ),
        (
            "pytest_legacy.xml",
            "test_summary_sample::test_errors_in_setup",
            'failed on setup with "RuntimeError: fixture setup exploded"',
        ),
        (
            "pytest_legacy.xml",
            "test_summary_sample::test_param[c]",
            "AssertionError: assert 'c' != 'c'",
        ),
    ],
)
def test_failure_shows_name_and_first_message_line(summary, sample, name, message):
    """A failing test is listed with its name and its message's first line."""
    results = summary.read_results(str(DATA / sample))
    messages = {case.name: case.message for case in results.cases}

    assert messages[name] == message
    report = summary.render("T", results)
    assert f"`{name}`" in report
    assert f"`{message}`" in report


def test_extra_failures_in_one_test_are_noted(summary):
    """gdUnit4 writes one failure element per failed assert; the test counts once."""
    results = summary.read_results(str(DATA / "gdunit4_results.xml"))
    cases = [c for c in results.cases if c.name.endswith("test_fails_twice")]

    assert len(cases) == 1, "expected one test_fails_twice result in the sample"
    case = cases[0]
    assert case.outcome == summary.FAILED
    assert case.more == 1
    assert "`Expecting: 'true' but is 'false'` (+1 more)" in summary.render(
        "T", results
    )


def test_error_is_labelled_apart_from_failures(summary):
    """An error (pytest fixture setup) is listed as an error, not a failure."""
    report = summary.render("T", summary.read_results(str(DATA / "pytest_xunit2.xml")))

    assert "`test_summary_sample::test_errors_in_setup` (error):" in report
    assert "`test_summary_sample::test_param[c]` (failed):" in report
    assert report.splitlines()[2] == "❌ 2 failed, 1 error of 7 tests."


def test_gut_test_with_no_assertions_gets_a_note(summary):
    """GUT's risky test stays counted as passed, with a note under the status."""
    results = summary.read_results(str(DATA / "gut_junit.xml"))
    risky = [case.name for case in results.cases if case.no_asserts]

    assert risky == ["test/gut_sample/test_summary_sample.gd::test_has_no_asserts"]
    report = summary.render("T", results)
    lines = report.splitlines()
    assert lines[2] == "❌ 2 failed of 5 tests."
    assert lines[4] == "- ⚠️ 1 GUT test made no assertions."
    assert "| 2 | 2 | 0 | 1 | 5 |" in report


def test_no_assertion_note_keeps_a_clean_run_ticked(summary, tmp_path):
    """The note does not change the counts or the verdict of a clean run."""
    xml = tmp_path / "gut_junit.xml"
    xml.write_text(
        '<testsuites name="GutTests" failures="0" tests="3">'
        '<testsuite name="test/gut/test_a.gd" tests="3" failures="0" skipped="0">'
        '<testcase name="test_ok" status="pass" classname="a" time="0.1"/>'
        '<testcase name="test_x" status="no asserts" classname="a" time="0.1"/>'
        '<testcase name="test_y" status="no asserts" classname="a" time="0.1"/>'
        "</testsuite></testsuites>",
        encoding="utf-8",
    )

    report = run(summary, tmp_path, str(xml))

    assert report.splitlines()[2] == "✅ All 3 tests passed."
    assert "- ⚠️ 2 GUT tests made no assertions." in report
    assert "| 3 | 0 | 0 | 0 | 3 |" in report


@pytest.mark.parametrize(
    "sample", ["gdunit4_results.xml", "pytest_xunit2.xml", "pytest_legacy.xml"]
)
def test_other_jobs_get_no_assertion_note(summary, sample):
    """Only GUT marks tests with status="no asserts"."""
    report = summary.render("T", summary.read_results(str(DATA / sample)))

    assert "made no assertions" not in report


def test_fail_fast_run_reports_tests_that_did_not_run(summary, tmp_path):
    """gdUnit4 without -c stops at the first failure; the rest must not vanish."""
    report = run(summary, tmp_path, str(DATA / "gdunit4_fail_fast.xml"))

    assert "3 tests declared in the XML have no result" in report
    assert "✅" not in report


def test_tests_that_did_not_run_block_the_tick(summary, tmp_path):
    """Declared tests with no result keep a run with no failures from showing ✅."""
    xml = tmp_path / "results.xml"
    passing_xml(xml, passed=2)
    xml.write_text(xml.read_text().replace('tests="2"', 'tests="5"'))

    report = run(summary, tmp_path, str(xml))

    assert report.splitlines()[2].startswith("⚠️")
    assert "3 tests declared in the XML have no result" in report
    assert "✅" not in report


def test_single_testsuite_root_is_read(summary, tmp_path):
    """A file whose root is one testsuite (no testsuites wrapper) is read."""
    root = ET.parse(DATA / "pytest_xunit2.xml").getroot()
    single = tmp_path / "single.xml"
    ET.ElementTree(root.find("testsuite")).write(single, encoding="utf-8")

    results = summary.read_results(str(single))

    assert results.problems == []
    assert len(results.cases) == 7
    assert results.declared == 7
    assert results.count(summary.FAILED) == 2


# ---------------------------------------------------------------------------
# No results, bad results and 0 tests never show ✅
# ---------------------------------------------------------------------------


def test_missing_xml_says_so(summary, tmp_path):
    """No file at the path: a crash before the tests started must not look clean."""
    report = run(summary, tmp_path, str(tmp_path / "gut-reports/*/gut_junit.xml"))

    assert "⚠️ No results." in report
    assert "No JUnit XML matched" in report
    assert "gut_junit.xml" in report
    assert "✅" not in report
    assert "| Passed |" not in report


@pytest.mark.parametrize(
    "content",
    [
        '<?xml version="1.0"?>\n<testsuites><testsuite name="x" tests="1">',
        "",
        "not xml at all",
    ],
    ids=["truncated", "empty", "garbage"],
)
def test_unreadable_xml_says_so(summary, tmp_path, content):
    """An unreadable file (for example cut off by a crash) is reported."""
    xml = tmp_path / "junit.xml"
    xml.write_text(content, encoding="utf-8")

    report = run(summary, tmp_path, str(xml))

    assert "is unreadable" in report
    assert "✅" not in report


def test_xml_that_is_not_junit_says_so(summary, tmp_path):
    """Well-formed XML with another root is not taken as 0 tests passing."""
    xml = tmp_path / "coverage.xml"
    xml.write_text('<?xml version="1.0"?><coverage line-rate="1"/>', encoding="utf-8")

    report = run(summary, tmp_path, str(xml))

    assert "is not JUnit XML (its root is `<coverage>`)" in report
    assert "✅" not in report


def test_unreadable_file_among_good_ones_is_still_flagged(summary, tmp_path):
    """One bad file next to a passing one keeps the run from showing ✅."""
    passing_xml(tmp_path / "a.xml", passed=3)
    (tmp_path / "b.xml").write_text("<testsuites>", encoding="utf-8")

    report = run(summary, tmp_path, str(tmp_path / "*.xml"))

    assert "| 3 | 0 | 0 | 0 | 3 |" in report
    assert "b.xml` is unreadable" in report
    assert "✅" not in report


def test_zero_tests_says_so(summary, tmp_path):
    """The browser job's empty-shard XML (0 tests) is reported, not ticked."""
    xml = tmp_path / "junit.xml"
    xml.write_text(empty_shard_xml(), encoding="utf-8")

    report = run(summary, tmp_path, str(xml))

    assert "⚠️ No tests ran: the XML holds 0 test results." in report
    assert "| 0 | 0 | 0 | 0 | 0 |" in report
    assert "✅" not in report


def test_browser_empty_shard_xml_is_valid_junit(summary, tmp_path):
    """The whole XML browser_test.yml writes for an empty shard reads as 0 tests.

    Parsing it catches a broken here-doc, such as an indented XML declaration
    or a missing root, which checking for one line would miss.
    """
    xml = tmp_path / "junit.xml"
    xml.write_text(empty_shard_xml(), encoding="utf-8")

    root = ET.parse(xml).getroot()
    results = summary.read_results(str(xml))

    assert root.tag == "testsuites"
    assert [suite.get("tests") for suite in root.iter("testsuite")] == ["0"]
    assert results.problems == []
    assert results.files == [str(xml)]
    assert results.cases == []
    assert results.declared == 0


# ---------------------------------------------------------------------------
# Clean runs
# ---------------------------------------------------------------------------


def test_clean_run_shows_tick(summary, tmp_path):
    """Only a run with tests, no failures and no problems shows ✅."""
    report = run(summary, tmp_path, str(passing_xml(tmp_path / "j.xml", passed=4)))

    assert report.splitlines()[2] == "✅ All 4 tests passed."
    assert "**Failures:**" not in report


def test_clean_run_with_skips_shows_both(summary, tmp_path):
    """Skipped tests are counted in the status line of a clean run."""
    xml = passing_xml(tmp_path / "j.xml", passed=3, skipped=2)

    report = run(summary, tmp_path, str(xml))

    assert report.splitlines()[2] == "✅ 3 passed, 2 skipped."


def test_glob_adds_up_all_matching_files(summary, tmp_path):
    """A glob such as reports/report_*/results.xml reads every match."""
    for index, passed in enumerate((2, 3), start=1):
        folder = tmp_path / "reports" / f"report_{index}"
        folder.mkdir(parents=True)
        passing_xml(folder / "results.xml", passed=passed)

    results = summary.read_results(str(tmp_path / "reports/report_*/results.xml"))

    assert len(results.files) == 2
    assert len(results.cases) == 5


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def test_report_has_title_table_and_collapsed_slowest_tests(summary, tmp_path):
    """The report follows the benchmark layout: heading, status, table, details."""
    report = run(summary, tmp_path, str(DATA / "pytest_xunit2.xml"), title="GUT")

    lines = report.splitlines()
    assert lines[0] == "## GUT"
    assert "| Passed | Failed | Errors | Skipped | Total |" in report
    assert "<details>\n<summary>The 5 slowest tests</summary>" in report
    assert report.index("<details>") > report.index("**Failures:**")
    assert "</details>" in report


def test_slowest_tests_are_the_five_longest(summary, tmp_path):
    """The collapsed section lists the 5 slowest tests, slowest first."""
    cases = "".join(
        f'<testcase classname="c" name="t{i}" time="{i}"/>' for i in range(8)
    )
    xml = tmp_path / "j.xml"
    xml.write_text(f'<testsuite tests="8">{cases}</testsuite>', encoding="utf-8")

    report = run(summary, tmp_path, str(xml))
    section = report.split("<details>")[1]
    rows = [line for line in section.splitlines() if line.startswith("| `")]

    assert [row.split("`")[1] for row in rows] == [f"c::t{i}" for i in (7, 6, 5, 4, 3)]
    assert rows[0].endswith("| 7.000 s |")


def test_slowest_section_handles_one_test_and_no_times(summary, tmp_path):
    """One timed test reads naturally; with no times the section is left out."""
    one = tmp_path / "one.xml"
    one.write_text('<testsuite tests="1"><testcase name="a" time="1"/></testsuite>')
    none = tmp_path / "none.xml"
    none.write_text('<testsuite tests="1"><testcase name="a"/></testsuite>')

    assert "<summary>The slowest test</summary>" in run(summary, tmp_path, str(one))
    assert "<details>" not in summary.render("T", summary.read_results(str(none)))


def test_pipe_in_test_name_does_not_break_the_table(summary):
    """A parametrized id with `|` is escaped inside the slowest-tests table."""
    report = summary.render("T", summary.read_results(str(DATA / "pytest_xunit2.xml")))
    rows = [line for line in report.splitlines() if line.startswith("| `")]

    assert all(line.count(" | ") == 1 for line in rows)
    passing = summary.Case("t::test_param[a|b]", summary.PASSED, 9.0)
    table = summary.render_slowest(summary.Results(cases=[passing]))
    assert "| `t::test_param[a\\|b]` | 9.000 s |" in table


def test_backtick_in_name_or_message_keeps_the_code_span(summary):
    """A backtick in the text switches to a double-backtick code span."""
    assert summary.code("plain") == "`plain`"
    assert summary.code("uses `x`") == "`` uses `x` ``"
    assert summary.code("two\nlines") == "`two lines`"


@pytest.mark.parametrize(
    "text, expected",
    [
        ("a``b", "``` a``b ```"),
        ("``", "``` `` ```"),
        (
            "x ``` [link](https://example.com) ```",
            "```` x ``` [link](https://example.com) ``` ````",
        ),
        ("`one` and ``two``", "``` `one` and ``two`` ```"),
    ],
)
def test_backtick_runs_cannot_close_the_code_span(summary, text, expected):
    """The fence is longer than any backtick run, so the text stays inside it."""
    assert summary.code(text) == expected


def test_long_message_is_cut(summary):
    """A message longer than the limit ends with an ellipsis."""
    text = "x" * 500
    cut = summary.shorten(text)

    assert len(cut) == summary.MAX_MESSAGE
    assert cut.endswith("…")
    assert summary.shorten("short") == "short"


def test_failure_list_is_capped(summary):
    """Hundreds of failures don't flood the page."""
    cases = [
        summary.Case(f"t::f{i}", summary.FAILED, None, "boom")
        for i in range(summary.MAX_FAILURES + 7)
    ]
    lines = summary.render_failures(summary.Results(cases=cases))

    assert sum(line.startswith("- `t::f") for line in lines) == summary.MAX_FAILURES
    assert lines[-1] == "- …and 7 more; see the job log."


def test_failure_without_message(summary, tmp_path):
    """A failure element with no message or text still lists the test."""
    xml = tmp_path / "j.xml"
    xml.write_text(
        '<testsuite tests="1"><testcase name="a"><failure/></testcase></testsuite>'
    )

    report = run(summary, tmp_path, str(xml))

    assert "- `a` (failed): (no message)" in report


def test_generic_message_attribute_falls_back_to_text(summary):
    """A message that only names the outcome or location defers to the text."""
    generic = ET.fromstring(
        '<failure message="FAILED: res://a.gd:3">\nreal\n</failure>'
    )
    useful = ET.fromstring('<failure message="assert 1 == 2">trace</failure>')
    bare = ET.fromstring('<failure message="failed"/>')

    assert summary.message_of(generic) == "real"
    assert summary.message_of(useful) == "assert 1 == 2"
    assert summary.message_of(bare) == "failed"


# ---------------------------------------------------------------------------
# Always exits 0, and appends
# ---------------------------------------------------------------------------


def test_summary_is_appended_not_overwritten(summary, tmp_path):
    """Two steps writing to the same summary file both keep their report."""
    out = tmp_path / "step_summary.md"
    out.write_text("## Earlier step\n", encoding="utf-8")

    for title in ("First", "Second"):
        summary.main(
            [
                "--title",
                title,
                "--results",
                str(DATA / "gut_junit.xml"),
                "--summary",
                str(out),
            ]
        )

    text = out.read_text(encoding="utf-8")
    assert text.startswith("## Earlier step\n")
    assert text.index("## First") < text.index("## Second")


def test_report_is_printed_to_the_log(summary, capsys):
    """The report also goes to stdout, so the job log shows it."""
    assert (
        summary.main(["--title", "Log", "--results", str(DATA / "gut_junit.xml")]) == 0
    )

    assert "## Log" in capsys.readouterr().out


@pytest.mark.parametrize("sample", SAMPLES)
def test_failing_results_exit_zero_as_a_script(sample, tmp_path):
    """Run as the workflows do: failures in the XML never fail the step."""
    out = tmp_path / "s.md"
    proc = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--title",
            "T",
            "--results",
            str(DATA / sample),
            "--summary",
            str(out),
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    assert proc.returncode == 0, proc.stderr
    assert out.read_text(encoding="utf-8").startswith("## T")


@pytest.mark.parametrize(
    "args",
    [[], ["--results", "x.xml"], ["--title", "T"], ["--bogus"]],
    ids=["no-args", "no-title", "no-results", "unknown-flag"],
)
def test_bad_arguments_exit_zero(args):
    """Even a broken step definition can't fail the job."""
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )

    assert proc.returncode == 0
    assert "usage:" in proc.stderr


def test_crash_exits_zero_and_does_not_look_clean(summary, tmp_path, monkeypatch):
    """An unexpected exception is reported on the page, never as ✅."""

    def explode(_pattern: str) -> Any:
        """Stand in for read_results and fail the way an unexpected bug would."""
        raise RuntimeError("boom")

    monkeypatch.setattr(summary, "read_results", explode)

    report = run(summary, tmp_path, "whatever.xml", title="GUT")

    assert report.startswith(
        "## GUT\n\n⚠️ The summary script failed: RuntimeError: boom"
    )
    assert "✅" not in report


def test_unwritable_summary_exits_zero(summary, tmp_path, capsys):
    """A summary path that can't be written only warns."""
    directory = str(tmp_path)  # open() fails on a directory.
    code = summary.main(
        [
            "--title",
            "T",
            "--results",
            str(DATA / "gut_junit.xml"),
            "--summary",
            directory,
        ]
    )

    assert code == 0
    assert "::warning::Cannot write the summary" in capsys.readouterr().out


# ---------------------------------------------------------------------------
# Workflow wiring
# ---------------------------------------------------------------------------

JOBS = {
    # workflow: (job id, results argument, test step name)
    "gut_tests.yml": (
        "unit-test",
        "gut-reports/*/gut_junit.xml",
        "Run GUT Tests (Codecov Upload Step Excluded)",
    ),
    "gdunit4_tests.yml": (
        "unit-test",
        "reports/report_*/results.xml",
        "Run GDUnit4 Test Suites",
    ),
    "test_ci_scripts.yml": (
        "test-python",
        "reports/ci-scripts/junit.xml",
        "Run CI Injection Tests",
    ),
    "browser_test.yml": ("test-shard", "artifacts/junit.xml", "Run Sharded Tests"),
}


def load_job(workflow: str) -> dict[str, Any]:
    """Return a job from a workflow file."""
    data = yaml.safe_load((WORKFLOWS / workflow).read_text(encoding="utf-8"))
    return data["jobs"][JOBS[workflow][0]]


def find_step(job: dict[str, Any], name: str) -> dict[str, Any]:
    """Return the job's step with this name, failing clearly if there is none."""
    for step in job["steps"]:
        if step.get("name") == name:
            return step
    raise AssertionError(f"Step '{name}' not found in the job")


def empty_shard_xml() -> str:
    """Return the XML the browser shards write when no test files match."""
    script = find_step(load_job("browser_test.yml"), "Run Sharded Tests")["run"]
    found = re.search(r"cat <<EOF > artifacts/junit\.xml\n(.*?)\nEOF\n", script, re.S)

    assert found, "empty-shard here-doc not found in 'Run Sharded Tests'"
    return found.group(1) + "\n"


def upload_matches(pattern: str, path: str) -> bool:
    """Match a path against an upload-artifact glob (* stays within one folder)."""
    regex = re.escape(pattern).replace(r"\*\*", ".*").replace(r"\*", "[^/]*")
    return re.fullmatch(regex, path) is not None


def summary_step(job: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    """Return the index and step that runs test_summary.py."""
    found = [
        (i, step)
        for i, step in enumerate(job["steps"])
        if SCRIPT_REF in step.get("run", "")
    ]
    assert len(found) == 1, "expected exactly one test summary step"
    return found[0]


@pytest.mark.parametrize("workflow", sorted(JOBS))
def test_summary_step_runs_always_after_the_tests(workflow):
    """The table must appear even when the test step fails."""
    job = load_job(workflow)
    index, step = summary_step(job)
    names = [s.get("name") for s in job["steps"]]

    assert step["if"] == "always()"
    assert index > names.index(JOBS[workflow][2])
    assert "continue-on-error" not in step
    assert "uses" not in step, "the summary needs no third-party action"


@pytest.mark.parametrize("workflow", sorted(JOBS))
def test_summary_step_reads_the_jobs_xml(workflow):
    """Each step passes its job's XML and appends to the run's Summary page."""
    _, step = summary_step(load_job(workflow))
    script = step["run"]

    assert f'--results "{JOBS[workflow][1]}"' in script
    assert '--summary "${GITHUB_STEP_SUMMARY}"' in script
    assert "--title" in script


def test_browser_summary_title_names_the_shard():
    """Each browser shard gets its own table, named after the shard."""
    _, step = summary_step(load_job("browser_test.yml"))

    # Passed through env, not pasted into the script (no expression injection).
    assert step["env"]["SUITE"] == "${{ matrix.suite }}"
    assert '--title "Browser tests: ${SUITE}${RUNNER_SUFFIX}"' in step["run"]
    assert "${{" not in step["run"]


@pytest.mark.parametrize("workflow", sorted(JOBS))
def test_summary_step_uses_the_runner_python(workflow):
    """python3 is on every runner image, even if a step before setup-python failed."""
    _, step = summary_step(load_job(workflow))

    assert step["run"].lstrip().startswith(f"python3 {SCRIPT_REF}")


def test_ci_scripts_pytest_writes_junit_xml():
    """pytest tests/ci/ must write the XML the summary step reads."""
    job = load_job("test_ci_scripts.yml")
    step = find_step(job, "Run CI Injection Tests")

    assert "pytest tests/ci/" in step["run"]
    assert "--junitxml=reports/ci-scripts/junit.xml" in step["run"]


def test_gdunit4_report_path_matches_where_gdunit4_writes():
    """gdUnit4 writes reports/report_<n>/results.xml, which the upload step keeps."""
    job = load_job("gdunit4_tests.yml")
    upload = find_step(job, "Upload Test Reports Artifacts")
    written = "reports/report_1/results.xml"
    patterns = [line.strip() for line in upload["with"]["path"].splitlines()]

    assert ET.parse(DATA / "gdunit4_results.xml").getroot().get("name") == "report_1"
    assert any(upload_matches(p, written) for p in patterns if p), patterns


@pytest.mark.parametrize(
    "pattern, matches",
    [
        ("reports/**", True),
        ("reports/**/results.xml", True),
        ("reports/*/results.xml", True),
        ("reports/**/results.html", False),
        ("reports/*.xml", False),
        ("artifacts/gdunit-reports/**", False),
    ],
)
def test_upload_matches_follows_upload_glob_rules(pattern, matches):
    """** crosses folders and * does not, as in actions/upload-artifact."""
    assert upload_matches(pattern, "reports/report_1/results.xml") is matches


@pytest.mark.parametrize(
    "workflow, permissions",
    [
        ("gut_tests.yml", {"contents": "read"}),
        ("gdunit4_tests.yml", {"contents": "read"}),
        ("test_ci_scripts.yml", None),
        ("browser_test.yml", None),
    ],
)
def test_job_permissions_are_unchanged(workflow, permissions):
    """Writing the step summary needs no extra permission."""
    assert load_job(workflow).get("permissions") == permissions


# ---------------------------------------------------------------------------
# Additional parser and reporting regressions
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("root_tag", ["testsuite", "testsuites"])
def test_nested_suite_counts_only_leaf_declarations(summary, tmp_path, root_tag):
    """Parent totals must not double-count missing tests in nested reports."""
    xml = tmp_path / "nested.xml"
    xml.write_text(
        f'<{root_tag} tests="3"><testsuite tests="3">'
        '<testsuite tests="1"><testcase name="done"/></testsuite>'
        '<testsuite tests="2"/>'
        f"</testsuite></{root_tag}>",
        encoding="utf-8",
    )

    results = summary.read_results(str(xml))
    report = summary.render("Nested", results)

    assert results.declared == 3
    assert results.not_run == 2
    assert "2 tests declared in the XML have no result" in report
    assert "| 1 | 0 | 0 | 0 | 1 |" in report
    assert "✅" not in report


@pytest.mark.parametrize("declaration", ["", 'tests="unknown"', 'tests="1.5"'])
def test_invalid_leaf_count_falls_back_to_recorded_cases(
    summary, tmp_path, declaration
):
    """Missing or non-integer metadata must not invent unexecuted tests."""
    xml = tmp_path / "metadata.xml"
    xml.write_text(
        '<testsuites><testsuite tests="100"><testcase name="a"/></testsuite>'
        f'<testsuite {declaration}><testcase name="b"/></testsuite></testsuites>',
        encoding="utf-8",
    )

    results = summary.read_results(str(xml))

    assert results.declared == 2
    assert results.not_run == 0
    assert summary.status_line(results) == "✅ All 2 tests passed."


@pytest.mark.parametrize(
    "children, outcome, message, more",
    [
        ('<skipped/><error message="setup"/>', "error", "setup", 0),
        (
            '<error message="cleanup"/><failure message="assertion"/><skipped/>',
            "failed",
            "assertion",
            1,
        ),
        ('<error message="first"/><error message="second"/>', "error", "first", 1),
    ],
)
def test_mixed_outcomes_count_one_case_and_preserve_diagnostics(
    summary, children, outcome, message, more
):
    """Failure/error diagnostics take precedence over skips regardless of order."""
    case = summary.read_case(
        ET.fromstring(f'<testcase name="mixed">{children}</testcase>')
    )

    assert case.name == "mixed"
    assert case.outcome == outcome
    assert case.message == message
    assert case.more == more
    results = summary.Results(cases=[case], files=["junit.xml"], declared=1)
    assert summary.status_line(results).startswith("❌")
    assert (
        sum(results.count(kind) for kind in ("passed", "failed", "error", "skipped"))
        == 1
    )


@pytest.mark.parametrize("attributes", ["", 'name=""', 'classname=""'])
def test_case_without_a_name_has_a_visible_fallback(summary, attributes):
    """Incomplete testcase metadata still gives failures an identifiable label."""
    case = summary.read_case(
        ET.fromstring(f"<testcase {attributes}><failure/></testcase>")
    )

    assert case.name == "(unnamed)"
    assert "- `(unnamed)` (failed): (no message)" in summary.render_failures(
        summary.Results(cases=[case])
    )


@pytest.mark.parametrize("duration", ["", "n/a", "-0.001", "NaN"])
def test_invalid_duration_preserves_case_but_omits_timing(summary, tmp_path, duration):
    """Bad timing metadata must neither lose a result nor pollute the slowest list."""
    xml = tmp_path / "timing.xml"
    xml.write_text(
        f'<testsuite tests="1"><testcase name="a" time="{duration}"/></testsuite>',
        encoding="utf-8",
    )

    results = summary.read_results(str(xml))
    report = summary.render("Timing", results)

    assert len(results.cases) == 1
    assert results.cases[0].time is None
    assert "✅ All 1 test passed." in report
    assert "<details>" not in report


def test_zero_duration_is_a_valid_timed_result(summary):
    """A fast test rounded to zero still belongs in the timing section."""
    case = summary.read_case(ET.fromstring('<testcase name="fast" time="0"/>'))

    assert case.time == 0.0
    assert "| `fast` | 0.000 s |" in summary.render_slowest(
        summary.Results(cases=[case])
    )


def test_recursive_glob_ignores_directories_and_sorts_files(summary, tmp_path):
    """A directory with an XML suffix is not treated as an unreadable report."""
    (tmp_path / "directory.xml").mkdir()
    nested = tmp_path / "nested"
    nested.mkdir()
    second = passing_xml(nested / "z.xml", passed=1)
    first = passing_xml(tmp_path / "a.xml", passed=1)

    results = summary.read_results(str(tmp_path / "**/*.xml"))

    assert results.files == sorted([str(first), str(second)])
    assert results.problems == []
    assert results.count(summary.PASSED) == 2


def test_read_error_keeps_other_files_results(summary, tmp_path, monkeypatch):
    """An OS read failure warns while preserving the reports that remain readable."""
    good = passing_xml(tmp_path / "a.xml", passed=1)
    bad = passing_xml(tmp_path / "b.xml", passed=1)
    original_parse = summary.ET.parse

    def deny_one(path):
        """Simulate permissions without depending on the test runner's user ID."""
        if path == str(bad):
            raise PermissionError("access denied")
        return original_parse(path)

    monkeypatch.setattr(summary.ET, "parse", deny_one)
    results = summary.read_results(str(tmp_path / "*.xml"))

    assert results.files == [str(good)]
    assert results.count(summary.PASSED) == 1
    assert len(results.problems) == 1
    assert "access denied" in results.problems[0]
    assert "✅" not in summary.render("Read failure", results)


@pytest.mark.parametrize("size", [199, 200, 201])
def test_failure_message_truncation_boundary(summary, size):
    """Messages at the display limit stay intact; overflow gets one ellipsis."""
    message = "é" * size
    case = summary.Case("boundary", summary.FAILED, message=message)
    lines = summary.render_failures(summary.Results(cases=[case]))
    expected = message if size <= 200 else "é" * 199 + "…"

    assert lines[-1] == f"- `boundary` (failed): `{expected}`"


def test_exact_failure_limit_has_no_overflow_note(summary):
    """The truncation note appears only when there are undisplayed failures."""
    cases = [summary.Case(f"f{i}", summary.ERROR) for i in range(50)]
    lines = summary.render_failures(summary.Results(cases=cases))

    assert len([line for line in lines if line.startswith("- ")]) == 50
    assert "more; see the job log" not in "\n".join(lines)
    assert lines[-1] == "- `f49` (error): (no message)"


def test_render_exception_is_reported_and_appended(
    summary, tmp_path, monkeypatch, capsys
):
    """Rendering failures keep the report-only exit contract and a visible warning."""

    def broken_render(_title, _results):
        """Raise after parsing succeeded to exercise the rendering crash path."""
        raise ValueError("cannot render")

    monkeypatch.setattr(summary, "render", broken_render)
    report = run(summary, tmp_path, str(DATA / "gut_junit.xml"), title="Résumé")

    assert report.startswith(
        "## Résumé\n\n⚠️ The summary script failed: ValueError: cannot render"
    )
    assert "✅" not in report
    assert report.strip() in capsys.readouterr().out
