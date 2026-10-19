# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_update_gdscript_docs.py
"""Regression tests for the GDScript docs generator schema and retry loop (#1055)."""

import importlib.util
import json
import re
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
import yaml
from pydantic import ValidationError

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = PROJECT_ROOT / ".github/scripts/update_gdscript_docs.py"
REQUIREMENTS = PROJECT_ROOT / ".github/scripts/requirements-docs.txt"
FOCUS_PARAMS = ["candidate", "allowed_controls", "context"]
REJECTED_MARKER = "YOUR PREVIOUS RESPONSE WAS REJECTED"


# -----------------------------------------------------------------------------
# Fixtures & helpers
# -----------------------------------------------------------------------------
@pytest.fixture(scope="module")
def docs():
    """Load update_gdscript_docs.py as a module (.github is not a package)."""
    spec = importlib.util.spec_from_file_location("update_gdscript_docs", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def sleeps(monkeypatch):
    """Record time.sleep calls instead of waiting."""
    calls = []
    monkeypatch.setattr("time.sleep", calls.append)
    return calls


def make_decl(
    docs, name="ensure_initial_focus", kind="function", params=None, return_type="void"
):
    """Build a MemberDeclaration without parsing GDScript."""
    return docs.MemberDeclaration(
        name=name,
        kind=kind,
        decl_line=1,
        insert_line=1,
        params=list(FOCUS_PARAMS if params is None else params),
        context_snippet="",
        return_type=return_type,
    )


def param_entries(names=FOCUS_PARAMS):
    """Parameter list in the shape Gemini returns."""
    return [
        {"name": n, "description": f"Meaningful description of {n}."} for n in names
    ]


def good_member(**overrides):
    """A valid MemberDoc payload for ensure_initial_focus."""
    data = {
        "name": "ensure_initial_focus",
        "summary": "Moves keyboard focus to the first usable control.",
        "description": None,
        "parameters": param_entries(),
        "returns": None,
    }
    data.update(overrides)
    return data


def gemini_reply(*members):
    """Fake generate_content response."""
    return SimpleNamespace(text=json.dumps({"members": list(members)}))


def fake_client(*outcomes):
    """Client whose generate_content returns (or raises) each outcome in turn."""
    client = MagicMock()
    client.models.generate_content.side_effect = list(outcomes)
    return client


def sent_prompts(client):
    """Prompts passed to generate_content, in call order."""
    return [c.kwargs["contents"] for c in client.models.generate_content.call_args_list]


def walk(node):
    """Yield every dict nested in a JSON schema."""
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)


# -----------------------------------------------------------------------------
# 1. Schema shape
# -----------------------------------------------------------------------------
def test_parameters_schema_is_array_of_name_description_objects(docs):
    """Gemini must receive a list of {name, description} objects, not a map."""
    schema = docs.FileDocumentationResponse.model_json_schema()
    defs = schema["$defs"]
    params = defs["MemberDoc"]["properties"]["parameters"]
    assert params["type"] == "array", params
    item_def = defs[params["items"]["$ref"].split("/")[-1]]
    assert set(item_def["required"]) == {"name", "description"}


def test_gemini_schema_keeps_parameter_item_shape(docs):
    """The schema google-genai actually sends still describes each parameter entry.

    google-genai 0.8.0 drops 'items' from a nullable (Optional) array, so this
    checks the converted schema, not just the pydantic one (#1055).
    """
    from google.genai import Client
    from google.genai import _transformers

    api_client = Client(api_key="test-key")._api_client
    schema = _transformers.t_schema(api_client, docs.FileDocumentationResponse)
    dumped = schema.model_dump(exclude_none=True)
    params = dumped["properties"]["members"]["items"]["properties"]["parameters"]
    assert params["type"] == "ARRAY", params
    assert set(params["items"]["properties"]) == {"name", "description"}
    assert set(params["items"]["required"]) == {"name", "description"}


def test_response_schema_has_no_free_form_maps(docs):
    """A Dict field reaches Gemini as an object without properties (#1055)."""
    schema = docs.FileDocumentationResponse.model_json_schema()
    for node in walk(schema):
        assert not isinstance(node.get("additionalProperties"), dict), node
        if node.get("type") == "object":
            assert node.get("properties"), node


# -----------------------------------------------------------------------------
# 2. ParamDoc validation
# -----------------------------------------------------------------------------
def test_param_doc_accepts_valid_entry(docs):
    """A valid entry passes and its description is stripped."""
    entry = docs.ParamDoc(
        name="candidate", description="  Control that should receive focus.  "
    )
    assert entry.description == "Control that should receive focus."


@pytest.mark.parametrize("name", ["1abc", "a-b", ""])
def test_param_doc_rejects_invalid_identifier(docs, name):
    """Parameter names must be GDScript identifiers."""
    with pytest.raises(ValidationError):
        docs.ParamDoc(name=name, description="Control that should receive focus.")


@pytest.mark.parametrize(
    "description",
    [
        "",
        "   ",
        "First line.\nSecond line.",
        "Uses ```code``` fences.",
        "@param candidate the control",
        "[b]Unclosed bold",
        "[codeblock]x[/codeblock]",
    ],
    ids=["empty", "blank", "multi-line", "fence", "doxygen", "unclosed-b", "codeblock"],
)
def test_param_doc_rejects_invalid_description(docs, description):
    """Descriptions follow the same contract as the rest of the docstring."""
    with pytest.raises(ValidationError):
        docs.ParamDoc(name="candidate", description=description)


# -----------------------------------------------------------------------------
# 3. MemberDoc
# -----------------------------------------------------------------------------
def test_member_doc_rejects_duplicate_parameters(docs):
    """Each parameter may appear only once."""
    with pytest.raises(ValidationError):
        docs.MemberDoc.model_validate(
            good_member(parameters=param_entries(["candidate", "candidate"]))
        )


def test_member_doc_param_map(docs):
    """param_map maps names to descriptions and is empty without parameters."""
    doc = docs.MemberDoc.model_validate(good_member())
    assert doc.param_map == {n: f"Meaningful description of {n}." for n in FOCUS_PARAMS}
    assert docs.MemberDoc.model_validate(good_member(parameters=[])).param_map == {}


def test_member_doc_treats_null_parameters_as_empty(docs):
    """A null 'parameters' from the model becomes an empty list, not an error."""
    doc = docs.MemberDoc.model_validate(good_member(parameters=None))
    assert doc.parameters == []
    without_key = good_member()
    del without_key["parameters"]
    assert docs.MemberDoc.model_validate(without_key).parameters == []


# -----------------------------------------------------------------------------
# 4. find_incomplete_parameters
# -----------------------------------------------------------------------------
def test_find_incomplete_flags_missing_parameter(docs):
    """A required parameter absent from the response is reported."""
    doc = docs.MemberDoc.model_validate(
        good_member(parameters=param_entries(FOCUS_PARAMS[:2]))
    )
    result = docs.find_incomplete_parameters(
        [doc], {"ensure_initial_focus": make_decl(docs)}
    )
    assert result == ["ensure_initial_focus.context"]


@pytest.mark.parametrize("placeholder", ["The context parameter.", "the context"])
def test_find_incomplete_flags_placeholders(docs, placeholder):
    """Filler descriptions are reported."""
    entries = param_entries(FOCUS_PARAMS[:2]) + [
        {"name": "context", "description": placeholder}
    ]
    doc = docs.MemberDoc.model_validate(good_member(parameters=entries))
    result = docs.find_incomplete_parameters(
        [doc], {"ensure_initial_focus": make_decl(docs)}
    )
    assert result == ["ensure_initial_focus.context"]


def test_find_incomplete_passes_complete_set(docs):
    """Nothing is reported when every parameter is described."""
    doc = docs.MemberDoc.model_validate(good_member())
    assert (
        docs.find_incomplete_parameters(
            [doc], {"ensure_initial_focus": make_decl(docs)}
        )
        == []
    )


def test_find_incomplete_skips_non_parameterized_kinds(docs):
    """Constants, exports and enums are never checked for parameters."""
    doc = docs.MemberDoc.model_validate(good_member(name="MAX_SPEED", parameters=None))
    target = make_decl(
        docs, name="MAX_SPEED", kind="constant", params=["x"], return_type=None
    )
    assert docs.find_incomplete_parameters([doc], {"MAX_SPEED": target}) == []


# -----------------------------------------------------------------------------
# 5. format_doc_lines
# -----------------------------------------------------------------------------
def param_line_names(lines):
    """Names from the '## [param name]:' lines, in output order."""
    names = []
    for line in lines:
        match = re.match(r"\s*## \[param (\w+)\]:", line)
        if match:
            names.append(match.group(1))
    return names


def test_format_orders_params_by_declaration(docs):
    """Param lines follow the signature order, not the response order."""
    doc = docs.MemberDoc.model_validate(
        good_member(parameters=list(reversed(param_entries())))
    )
    lines = docs.format_doc_lines(doc, make_decl(docs), "")
    assert param_line_names(lines) == FOCUS_PARAMS


def test_format_wraps_long_descriptions(docs):
    """Every generated line stays within the 95-column margin."""
    long_text = " ".join(["Describes the accepted control values in detail."] * 8)
    entries = [{"name": n, "description": long_text} for n in FOCUS_PARAMS]
    doc = docs.MemberDoc.model_validate(good_member(parameters=entries))
    lines = docs.format_doc_lines(doc, make_decl(docs), "\t")
    assert all(len(line.rstrip("\n")) <= 95 for line in lines)
    assert all(line.startswith("\t##") for line in lines)


def test_format_signal_gets_param_lines(docs):
    """Signals document their arguments too."""
    names = ["old_value", "new_value"]
    doc = docs.MemberDoc.model_validate(
        good_member(name="value_changed", parameters=param_entries(names))
    )
    decl = make_decl(
        docs, name="value_changed", kind="signal", params=names, return_type=None
    )
    assert param_line_names(docs.format_doc_lines(doc, decl, "")) == names


def test_format_void_function_has_no_returns_line(docs):
    """A void function never gets a Returns line, even if the model sent one."""
    doc = docs.MemberDoc.model_validate(good_member(returns="nothing useful"))
    lines = docs.format_doc_lines(doc, make_decl(docs, return_type="void"), "")
    assert not any(line.startswith("## Returns") for line in lines)


def test_format_strips_duplicated_returns_prefix(docs):
    """A model-supplied leading 'Returns' is not doubled."""
    doc = docs.MemberDoc.model_validate(
        good_member(returns="Returns true if focus moved.")
    )
    lines = docs.format_doc_lines(doc, make_decl(docs, return_type="bool"), "")
    assert "## Returns true if focus moved.\n" in lines


# -----------------------------------------------------------------------------
# 6. query_gemini_for_docs (mocked client)
# -----------------------------------------------------------------------------
def query(docs, client, decl=None):
    """Run query_gemini_for_docs for a single target."""
    return docs.query_gemini_for_docs(
        client, Path("globals.gd"), [decl or make_decl(docs)]
    )


def test_query_returns_docs_on_first_good_response(docs, sleeps):
    """A valid first response is accepted without retries or sleeps."""
    client = fake_client(gemini_reply(good_member()))
    result = query(docs, client)
    assert set(result["ensure_initial_focus"].param_map) == set(FOCUS_PARAMS)
    assert client.models.generate_content.call_count == 1
    assert sleeps == []


def test_query_recovers_from_oct18_failure_shape_with_feedback(docs, sleeps):
    """Parameters emitted as empty-summary members trigger a fast retry with feedback."""
    bad = gemini_reply(
        good_member(parameters=None),
        *({"name": n, "summary": ""} for n in FOCUS_PARAMS),
    )
    client = fake_client(bad, gemini_reply(good_member()))

    result = query(docs, client)

    assert "ensure_initial_focus" in result
    first, second = sent_prompts(client)
    assert REJECTED_MARKER not in first
    assert REJECTED_MARKER in second
    assert "Summary must be a single non-empty line" in second
    assert sleeps == [5]


def test_query_backs_off_on_api_errors_without_feedback(docs, sleeps):
    """API errors use exponential backoff and add no rejection text."""
    client = fake_client(
        RuntimeError("429 RESOURCE_EXHAUSTED"),
        RuntimeError("503 UNAVAILABLE"),
        gemini_reply(good_member()),
    )
    query(docs, client)
    assert sleeps == [35, 70]
    assert not any(REJECTED_MARKER in p for p in sent_prompts(client))


def test_query_exits_when_parameters_stay_missing(docs, sleeps):
    """Three responses without parameters fail closed."""
    reply = gemini_reply(good_member(parameters=None))
    client = fake_client(reply, reply, reply)
    with pytest.raises(SystemExit) as exc:
        query(docs, client)
    assert exc.value.code == 1
    assert sleeps == [5, 5]


def test_query_exits_on_unexpected_parameter(docs, sleeps):
    """A parameter not in the signature fails closed."""
    client = fake_client(
        gemini_reply(good_member(parameters=param_entries(FOCUS_PARAMS + ["bogus"])))
    )
    with pytest.raises(SystemExit) as exc:
        query(docs, client)
    assert exc.value.code == 1


@pytest.mark.parametrize("kind", ["constant", "export", "enum"])
def test_query_exits_on_parameters_for_non_parameterized_member(docs, sleeps, kind):
    """Parameters returned for a constant, export or enum fail closed."""
    decl = make_decl(docs, name="MAX_SPEED", kind=kind, params=[], return_type=None)
    client = fake_client(
        gemini_reply(good_member(name="MAX_SPEED", parameters=param_entries(["x"])))
    )
    with pytest.raises(SystemExit) as exc:
        query(docs, client, decl)
    assert exc.value.code == 1


# -----------------------------------------------------------------------------
# 7. Round trip through prepare_file_change
# -----------------------------------------------------------------------------
FIXTURE_GD = (
    "extends Node\n"
    "\n"
    "\n"
    "func ensure_initial_focus(candidate: Control, allowed_controls: Array, context: String) -> void:\n"
    "\tpass\n"
)


def test_round_trip_injection_is_compliant_and_preserves_code(docs, tmp_path, sleeps):
    """Injected docs re-parse as COMPLIANT and non-doc bytes are unchanged."""
    gd_file = tmp_path / "focus.gd"
    gd_file.write_text(FIXTURE_GD, encoding="utf-8")
    client = fake_client(gemini_reply(good_member()))

    change = docs.prepare_file_change(client, gd_file, check_mode=False)

    assert change is not None
    for name in FOCUS_PARAMS:
        assert f"## [param {name}]: " in change.proposed_source
    decls, ok = docs.parse_declarations_from_ast(change.proposed_source)
    assert ok
    (decl,) = decls
    docs.classify_member(decl)
    assert decl.status == docs.DocStatus.COMPLIANT
    assert docs.compute_non_doc_bytes_sha256(
        FIXTURE_GD
    ) == docs.compute_non_doc_bytes_sha256(change.proposed_source)


# -----------------------------------------------------------------------------
# 8. Dependency pins
# -----------------------------------------------------------------------------
def test_docs_requirements_are_exact_pins():
    """requirements-docs.txt pins exactly the three docs dependencies."""
    entries = [
        line.strip()
        for line in REQUIREMENTS.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    names = set()
    for entry in entries:
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([A-Za-z0-9_.+-]+)", entry)
        assert match, f"Not an exact pin: {entry!r}"
        names.add(match.group(1).lower())
    assert names == {"google-genai", "pydantic", "gdtoolkit"}


@pytest.mark.parametrize(
    "workflow_path, job",
    [
        (".github/workflows/bi_weekly_gd_docstrings.yml", "sync-docstrings"),
        (".github/workflows/test_ci_scripts.yml", "test-python"),
    ],
)
def test_workflows_install_docs_requirements_file(workflow_path, job):
    """Both workflows install the shared pins file and never pin inline."""
    workflow = yaml.safe_load(
        (PROJECT_ROOT / workflow_path).read_text(encoding="utf-8")
    )
    runs = [step.get("run", "") for step in workflow["jobs"][job]["steps"]]
    assert any(
        "pip install -r .github/scripts/requirements-docs.txt" in run for run in runs
    )
    assert not any(
        re.search(r"\b(google-genai|gdtoolkit|pydantic)==", run) for run in runs
    )
