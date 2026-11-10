#!/usr/bin/env python3
# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# .github/scripts/test_summary.py
"""Add a test job's JUnit XML results to the run's Summary page (#1156).

Reads every file that --results matches, counts the test cases and appends a
Markdown report to --summary (in CI, the $GITHUB_STEP_SUMMARY file):

- a status line: ✅ only when at least one test ran and none failed, errored
  or went missing; ❌ for failures and errors; ⚠️ for no XML, unreadable XML,
  0 tests, or tests the XML declares but has no result for (gdUnit4 stops
  at the first failure unless it runs with -c);
- a table of passed, failed, errors, skipped and total;
- a note for GUT tests that made no assertions (GUT calls them risky); the
  XML has no failure for them, so the table still counts them as passed;
- the failing tests, each with its name and the first line of its message;
- a collapsed list of the 5 slowest tests.

Usage:

    python3 .github/scripts/test_summary.py --title <text>
        --results <path or glob> [--summary <markdown file to append to>]

The report is also printed to stdout, so it shows in the job log.

It reads a `testsuites` root (GUT, gdUnit4, pytest) or a single `testsuite`
root, in pytest's default xunit2 or legacy junit_family. Counts come from the
`testcase` elements, not the suite attributes: GUT counts failed asserts in a
suite's failures attribute, not failed tests.

Like test/benchmark/compare.py --report-only, this script only reports. It
always exits 0, whatever it reads and even if it crashes, so it can neither
fail a job nor hide a failure: the test step's own exit code decides the job.
"""

from __future__ import annotations

import argparse
import glob
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

PASSED, FAILED, ERROR, SKIPPED = "passed", "failed", "error", "skipped"
SLOWEST = 5
MAX_FAILURES = 50
MAX_MESSAGE = 200

# A message attribute that only names the outcome or its location. GUT writes
# message="failed" and gdUnit4 message="FAILED: res://path.gd:12"; both put the
# real message in the element text, so the text is used instead.
GENERIC_MESSAGE = re.compile(
    r"^(?:failed|failure|error|skipped|pending"
    r"|(?:FAILED|ERROR|SKIPPED|WARNING): \S+:\d+)$",
    re.IGNORECASE,
)


@dataclass
class Case:
    """One test result."""

    name: str
    outcome: str
    time: float | None = None
    message: str = ""
    more: int = 0  # Further failure or error elements in the same test case.
    no_asserts: bool = False  # GUT's status="no asserts" (a risky test).


@dataclass
class Results:
    """Everything read from the matched files."""

    cases: list[Case] = field(default_factory=list)
    declared: int = 0  # Tests the suites say they hold.
    files: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)

    def count(self, outcome: str) -> int:
        """Return how many test cases had this outcome."""
        return sum(1 for case in self.cases if case.outcome == outcome)

    @property
    def no_asserts(self) -> int:
        """GUT tests that made no assertions; they are still counted as passed."""
        return sum(1 for case in self.cases if case.no_asserts)

    @property
    def not_run(self) -> int:
        """Tests the suites declare but the XML has no result for."""
        return max(0, self.declared - len(self.cases))


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--title", required=True, help="Report heading.")
    parser.add_argument(
        "--results",
        required=True,
        help="JUnit XML file, or a glob such as 'reports/report_*/results.xml'.",
    )
    parser.add_argument(
        "--summary", type=Path, help="Append the Markdown report to this file."
    )
    return parser.parse_args(argv)


def find_files(pattern: str) -> list[str]:
    """Return the files the path or glob matches, sorted."""
    matches = glob.glob(pattern, recursive=True)
    return sorted(path for path in matches if Path(path).is_file())


def to_float(value: str | None) -> float | None:
    """Return a time attribute as seconds, or None if it is absent or not a number."""
    try:
        number = float(value) if value is not None else None
    except ValueError:
        return None
    return number if number is not None and number >= 0 else None


def first_line(text: str | None) -> str:
    """Return the first non-blank line of the text, stripped."""
    for line in (text or "").splitlines():
        if line.strip():
            return line.strip()
    return ""


def message_of(element: ET.Element) -> str:
    """Return the first line of a failure, error or skipped element's message."""
    attribute = first_line(element.get("message"))
    if attribute and not GENERIC_MESSAGE.match(attribute):
        return attribute
    return first_line(element.text) or attribute


def read_case(testcase: ET.Element) -> Case:
    """Turn a testcase element into a Case."""
    name = testcase.get("name") or "(unnamed)"
    classname = testcase.get("classname")
    full_name = f"{classname}::{name}" if classname else name
    time = to_float(testcase.get("time"))
    for outcome, tag in ((FAILED, "failure"), (ERROR, "error")):
        found = testcase.findall(tag)
        if found:
            extra = len(testcase.findall("failure") + testcase.findall("error")) - 1
            return Case(full_name, outcome, time, message_of(found[0]), extra)
    if testcase.find("skipped") is not None:
        return Case(full_name, SKIPPED, time)
    no_asserts = testcase.get("status") == "no asserts"
    return Case(full_name, PASSED, time, no_asserts=no_asserts)


def declared_tests(root: ET.Element, recorded: int) -> int:
    """Return how many tests the leaf suites declare (recorded if they don't say)."""
    # iter() includes the root itself when the root is a testsuite.
    suites = list(root.iter("testsuite"))
    leaves = [suite for suite in suites if suite.find("testsuite") is None]
    total = 0
    for suite in leaves:
        try:
            total += int(suite.get("tests", ""))
        except ValueError:
            return recorded
    return total


def read_file(path: str, results: Results) -> None:
    """Add one file's test cases to the results, or record why it can't be read."""
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as err:
        results.problems.append(f"`{path}` is unreadable ({err}).")
        return
    if root.tag not in ("testsuites", "testsuite"):
        results.problems.append(
            f"`{path}` is not JUnit XML (its root is `<{root.tag}>`)."
        )
        return
    cases = [read_case(testcase) for testcase in root.iter("testcase")]
    results.cases += cases
    results.declared += declared_tests(root, len(cases))
    results.files.append(path)


def read_results(pattern: str) -> Results:
    """Read every file the pattern matches."""
    results = Results()
    files = find_files(pattern)
    if not files:
        results.problems.append(
            f"No JUnit XML matched `{pattern}`. The tests may not have started."
        )
    for path in files:
        read_file(path, results)
    return results


def plural(count: int, word: str) -> str:
    """Return '1 test' or '2 tests'."""
    return f"{count} {word}" if count == 1 else f"{count} {word}s"


def status_line(results: Results) -> str:
    """Return the one-line verdict. ✅ needs tests, no failures and no problems."""
    failed, errors = results.count(FAILED), results.count(ERROR)
    if failed or errors:
        parts = [f"{failed} failed"] if failed else []
        parts += [plural(errors, "error")] if errors else []
        return f"❌ {', '.join(parts)} of {plural(len(results.cases), 'test')}."
    if not results.files:
        return "⚠️ No results."
    if not results.cases:
        return "⚠️ No tests ran: the XML holds 0 test results."
    if results.problems or results.not_run:
        return "⚠️ No failures in the results that could be read; see below."
    skipped = results.count(SKIPPED)
    if skipped:
        return f"✅ {results.count(PASSED)} passed, {skipped} skipped."
    return f"✅ All {plural(len(results.cases), 'test')} passed."


def code(text: str) -> str:
    """Return the text as a Markdown code span, so `|`, `<` and `*` show as typed.

    The fence is one backtick longer than the longest run of backticks in the
    text, so no backtick inside can close the span early and let the rest of a
    test name or message render as Markdown.
    """
    text = text.replace("\n", " ")
    longest = max((len(run) for run in re.findall(r"`+", text)), default=0)
    fence = "`" * (longest + 1)
    pad = " " if longest else ""
    return f"{fence}{pad}{text}{pad}{fence}"


def shorten(text: str, limit: int = MAX_MESSAGE) -> str:
    """Cut a long message to the limit, marking the cut."""
    return text if len(text) <= limit else text[: limit - 1] + "…"


def render_failures(results: Results) -> list[str]:
    """Return the list of failing tests with their messages."""
    bad = [case for case in results.cases if case.outcome in (FAILED, ERROR)]
    if not bad:
        return []
    lines = ["", "**Failures:**", ""]
    for case in bad[:MAX_FAILURES]:
        label = "error" if case.outcome == ERROR else "failed"
        message = code(shorten(case.message)) if case.message else "(no message)"
        more = f" (+{case.more} more)" if case.more else ""
        lines.append(f"- {code(case.name)} ({label}): {message}{more}")
    if len(bad) > MAX_FAILURES:
        lines.append(f"- …and {len(bad) - MAX_FAILURES} more; see the job log.")
    return lines


def slowest_label(count: int) -> str:
    """Return 'The slowest test' or 'The 5 slowest tests'."""
    return "The slowest test" if count == 1 else f"The {count} slowest tests"


def render_slowest(results: Results) -> list[str]:
    """Return a collapsed table of the slowest tests, if the XML has times."""
    timed = [case for case in results.cases if case.time is not None]
    if not timed:
        return []
    slowest = sorted(timed, key=lambda case: case.time, reverse=True)[:SLOWEST]
    lines = [
        "",
        "<details>",
        f"<summary>{slowest_label(len(slowest))}</summary>",
        "",
        "| Test | Time |",
        "|---|---:|",
    ]
    # Inside a table, GitHub ends the cell at a `|` even in a code span.
    lines += [
        f"| {code(case.name).replace('|', chr(92) + '|')} | {case.time:.3f} s |"
        for case in slowest
    ]
    lines += ["", "</details>"]
    return lines


def render(title: str, results: Results) -> str:
    """Render the report as Markdown."""
    lines = [f"## {title}", "", status_line(results)]
    notes = [f"- ⚠️ {problem}" for problem in results.problems]
    if results.not_run:
        verb = "has" if results.not_run == 1 else "have"
        notes.append(
            f"- ⚠️ {plural(results.not_run, 'test')} declared in the XML "
            f"{verb} no result: the runner stopped before running them."
        )
    if results.no_asserts:
        notes.append(
            f"- ⚠️ {plural(results.no_asserts, 'GUT test')} made no assertions."
        )
    if notes:
        lines += ["", *notes]
    if results.files:
        passed, failed = results.count(PASSED), results.count(FAILED)
        errors, skipped = results.count(ERROR), results.count(SKIPPED)
        lines += [
            "",
            "| Passed | Failed | Errors | Skipped | Total |",
            "|---:|---:|---:|---:|---:|",
            f"| {passed} | {failed} | {errors} | {skipped} | {len(results.cases)} |",
        ]
    lines += render_failures(results)
    lines += render_slowest(results)
    lines.append("")
    return "\n".join(lines)


def crash_report(title: str, err: BaseException) -> str:
    """Render the report for a crash in this script, which must not look clean."""
    return (
        f"## {title}\n\n⚠️ The summary script failed: "
        f"{type(err).__name__}: {err}. Check the job log.\n"
    )


def write_summary(path: Path | None, report: str) -> None:
    """Append the report to the summary file; a failed write only warns."""
    if path is None:
        return
    try:
        with path.open("a", encoding="utf-8") as handle:
            handle.write(report + "\n")
    except OSError as err:
        print(f"::warning::Cannot write the summary to {path}: {err}")


def main(argv: list[str] | None = None) -> int:
    """Print and append the report. Always returns 0 (see the module docstring)."""
    try:
        args = parse_args(argv)
    except SystemExit:  # argparse has printed the problem, or the help.
        return 0
    try:
        report = render(args.title, read_results(args.results))
    except Exception as err:  # pylint: disable=broad-exception-caught
        report = crash_report(args.title, err)
    print(report)
    write_summary(args.summary, report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
