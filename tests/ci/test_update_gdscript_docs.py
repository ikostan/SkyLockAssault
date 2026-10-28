# Copyright (C) 2026 Egor Kostan
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# tests/ci/test_update_gdscript_docs.py
"""Regression tests for the GDScript docs generator schema and retry loop (#1055)."""

import importlib.util
import json
import re
import sys
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


def param_entries(names=None):
    """Parameter list in the shape Gemini returns (defaults to FOCUS_PARAMS)."""
    names = FOCUS_PARAMS if names is None else names
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
    from google.genai import Client, _transformers

    api_client = Client(api_key="test-key")._api_client
    schema = _transformers.t_schema(api_client, docs.FileDocumentationResponse)
    dumped = schema.model_dump(exclude_none=True)
    params = dumped["properties"]["members"]["items"]["properties"]["parameters"]
    assert params["type"] == "ARRAY", params
    assert set(params["items"]["properties"]) == {"name", "description"}
    assert set(params["items"]["required"]) == {"name", "description"}


def test_gemini_schema_requires_parameters(docs):
    """Gemini sees 'parameters' as required, so it cannot silently skip the field.

    google-genai builds the schema from pydantic, where a field with a default is
    optional; Gemini then often leaves it out (Sourcery review, #1057).
    """
    from google.genai import Client, _transformers

    api_client = Client(api_key="test-key")._api_client
    schema = _transformers.t_schema(api_client, docs.FileDocumentationResponse)
    member = schema.model_dump(exclude_none=True)["properties"]["members"]["items"]
    assert "parameters" in member["required"], member["required"]


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
@pytest.mark.parametrize("name", ["candidate", "_", "_control2", "Control2"])
def test_param_doc_accepts_valid_entry(docs, name):
    """A valid entry passes and its description is stripped."""
    entry = docs.ParamDoc(
        name=name, description="  Control that should receive focus.  "
    )
    assert entry.name == name
    assert entry.description == "Control that should receive focus."


@pytest.mark.parametrize("name", ["1abc", "a-b", "", "a.b", " candidate", "café"])
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
        "First line.\rSecond line.",
        "First line.\r\nSecond line.",
        "Uses ```code``` fences.",
        "@param candidate the control",
        "[b]Unclosed bold",
        "[codeblock]x[/codeblock]",
    ],
    ids=[
        "empty",
        "blank",
        "multi-line",
        "carriage-return",
        "crlf",
        "fence",
        "doxygen",
        "unclosed-b",
        "codeblock",
    ],
)
def test_param_doc_rejects_invalid_description(docs, description):
    """Descriptions follow the same contract as the rest of the docstring."""
    with pytest.raises(ValidationError):
        docs.ParamDoc(name="candidate", description=description)


@pytest.mark.parametrize(
    "payload, field",
    [
        ({"name": "candidate"}, "description"),
        ({"description": "Receives focus."}, "name"),
        ({"name": None, "description": "Receives focus."}, "name"),
        ({"name": 42, "description": "Receives focus."}, "name"),
        ({"name": "candidate", "description": None}, "description"),
        ({"name": "candidate", "description": 42}, "description"),
    ],
    ids=[
        "missing-description",
        "missing-name",
        "null-name",
        "numeric-name",
        "null-description",
        "numeric-description",
    ],
)
def test_param_doc_requires_string_name_and_description(docs, payload, field):
    """Incomplete or wrongly typed entries identify the offending field."""
    with pytest.raises(ValidationError) as exc:
        docs.ParamDoc.model_validate(payload)
    assert field in {error["loc"][0] for error in exc.value.errors()}


def test_param_doc_preserves_valid_bbcode(docs):
    """Useful inline formatting survives parameter validation unchanged."""
    description = "Accepts [code]keyboard[/code] or [b]gamepad[/b] controls."
    entry = docs.ParamDoc(name="context", description=f"  {description}  ")
    assert entry.description == description


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
    """An explicit null 'parameters' from the model becomes an empty list."""
    doc = docs.MemberDoc.model_validate(good_member(parameters=None))
    assert doc.parameters == []


def test_member_doc_rejects_missing_parameters_key(docs):
    """Leaving 'parameters' out fails validation, so the retry loop reports it."""
    without_key = good_member()
    del without_key["parameters"]
    with pytest.raises(ValidationError, match="parameters"):
        docs.MemberDoc.model_validate(without_key)


@pytest.mark.parametrize(
    "parameters",
    [{}, {"candidate": "Receives focus."}, "candidate", [None]],
    ids=["empty-map", "legacy-map", "string", "null-entry"],
)
def test_member_doc_rejects_invalid_parameter_shapes(docs, parameters):
    """Only a list of structured entries can replace the old dictionary schema."""
    with pytest.raises(ValidationError) as exc:
        docs.MemberDoc.model_validate(good_member(parameters=parameters))
    assert all(error["loc"][0] == "parameters" for error in exc.value.errors())


def test_member_doc_keeps_case_distinct_parameter_names(docs):
    """Uniqueness uses exact identifiers, since GDScript is case sensitive."""
    member = docs.MemberDoc.model_validate(
        good_member(parameters=param_entries(["control", "Control"]))
    )
    assert member.param_map == {
        "control": "Meaningful description of control.",
        "Control": "Meaningful description of Control.",
    }


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


def test_find_unexpected_flags_undeclared_parameter(docs):
    """A parameter the signature does not declare is reported."""
    doc = docs.MemberDoc.model_validate(
        good_member(parameters=param_entries(FOCUS_PARAMS + ["bogus"]))
    )
    result = docs.find_unexpected_parameters(
        [doc], {"ensure_initial_focus": make_decl(docs)}
    )
    assert result == ["ensure_initial_focus.bogus"]


@pytest.mark.parametrize("kind", ["constant", "export", "enum"])
def test_find_unexpected_flags_any_parameter_on_non_parameterized_kind(docs, kind):
    """Constants, exports and enums take no parameters at all."""
    doc = docs.MemberDoc.model_validate(
        good_member(name="MAX_SPEED", parameters=param_entries(["x"]))
    )
    target = make_decl(docs, name="MAX_SPEED", kind=kind, params=[], return_type=None)
    assert docs.find_unexpected_parameters([doc], {"MAX_SPEED": target}) == [
        "MAX_SPEED.x"
    ]


def test_find_response_problems_reports_missing_member(docs):
    """A requested member absent from the response is reported."""
    other = docs.MemberDoc.model_validate(good_member(name="other", parameters=[]))
    problems = docs.find_response_problems(
        [other], {"ensure_initial_focus"}, {"ensure_initial_focus": make_decl(docs)}
    )
    assert len(problems) == 1
    assert "ensure_initial_focus" in problems[0]


def test_find_response_problems_passes_good_response(docs):
    """A complete, correct response has no problems."""
    doc = docs.MemberDoc.model_validate(good_member())
    assert (
        docs.find_response_problems(
            [doc], {"ensure_initial_focus"}, {"ensure_initial_focus": make_decl(docs)}
        )
        == []
    )


def test_find_response_problems_collects_all_requested_member_errors(docs):
    """One retry can report missing members, filler, omissions and extra parameters."""
    member = docs.MemberDoc.model_validate(
        good_member(
            parameters=[
                {"name": "candidate", "description": "  THE CANDIDATE PARAMETER...  "},
                {"name": "bogus", "description": "Selects a control."},
            ]
        )
    )
    targets = {"ensure_initial_focus": make_decl(docs)}
    problems = docs.find_response_problems(
        [member], {"z_missing", "ensure_initial_focus", "a_missing"}, targets
    )

    assert len(problems) == 3
    assert "['a_missing', 'z_missing']" in problems[0]
    assert "Missing or placeholder parameter descriptions" in problems[1]
    for name in FOCUS_PARAMS:
        assert f"ensure_initial_focus.{name}" in problems[1]
    assert "Parameters not declared in the signature" in problems[2]
    assert "ensure_initial_focus.bogus" in problems[2]


def test_parameter_checks_ignore_unrequested_members(docs):
    """Extra members cannot force retries, even when their parameters are wrong."""
    requested = docs.MemberDoc.model_validate(good_member())
    extra = docs.MemberDoc.model_validate(
        good_member(name="other", parameters=param_entries(["bogus"]))
    )
    unknown = docs.MemberDoc.model_validate(good_member(name="unknown"))
    targets = {
        "ensure_initial_focus": make_decl(docs),
        "other": make_decl(docs, name="other"),
    }

    assert docs.find_incomplete_parameters([unknown], targets) == []
    assert docs.find_unexpected_parameters([unknown], targets) == []
    assert (
        docs.find_response_problems(
            [requested, extra, unknown], {"ensure_initial_focus"}, targets
        )
        == []
    )


def test_signal_parameters_are_checked_in_both_directions(docs):
    """Signals need every declared argument and cannot invent new ones."""
    member = docs.MemberDoc.model_validate(
        good_member(name="value_changed", parameters=param_entries(["old", "bogus"]))
    )
    target = make_decl(docs, name="value_changed", kind="signal", params=["old", "new"])
    targets = {"value_changed": target}
    assert docs.find_incomplete_parameters([member], targets) == ["value_changed.new"]
    assert docs.find_unexpected_parameters([member], targets) == ["value_changed.bogus"]


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
    for name in FOCUS_PARAMS:
        assert f"## [param {name}]: Meaningful description of {name}.\n" in lines


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


@pytest.mark.parametrize("kind", ["function", "signal", "constant", "export", "enum"])
def test_format_empty_parameters_adds_no_parameter_section(docs, kind):
    """Empty parameter lists do not leave stray sections or blank doc lines."""
    member = docs.MemberDoc.model_validate(good_member(parameters=[]))
    decl = make_decl(docs, kind=kind, params=[])
    assert docs.format_doc_lines(member, decl, "\t") == [f"\t## {member.summary}\n"]


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
    request = client.models.generate_content.call_args.kwargs
    assert request["model"] == docs.PINNED_MODEL
    assert request["config"].response_schema is docs.FileDocumentationResponse
    assert request["config"].response_mime_type == "application/json"
    assert request["config"].temperature == 0.0


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


def test_query_retries_unexpected_parameter_with_feedback(docs, sleeps):
    """An undeclared parameter is fed back to Gemini instead of aborting the run."""
    bad = gemini_reply(good_member(parameters=param_entries(FOCUS_PARAMS + ["bogus"])))
    client = fake_client(bad, gemini_reply(good_member()))

    result = query(docs, client)

    assert set(result["ensure_initial_focus"].param_map) == set(FOCUS_PARAMS)
    second = sent_prompts(client)[1]
    assert REJECTED_MARKER in second
    assert "ensure_initial_focus.bogus" in second
    assert sleeps == [5]


def test_query_exits_when_unexpected_parameter_persists(docs, sleeps):
    """An undeclared parameter on every attempt still fails closed."""
    bad = gemini_reply(good_member(parameters=param_entries(FOCUS_PARAMS + ["bogus"])))
    client = fake_client(bad, bad, bad)
    with pytest.raises(SystemExit) as exc:
        query(docs, client)
    assert exc.value.code == 1
    assert sleeps == [5, 5]


@pytest.mark.parametrize("kind", ["constant", "export", "enum"])
def test_query_retries_parameters_on_non_parameterized_member(docs, sleeps, kind):
    """Parameters on a constant, export or enum are retried, then fail closed."""
    decl = make_decl(docs, name="MAX_SPEED", kind=kind, params=[], return_type=None)
    bad = gemini_reply(good_member(name="MAX_SPEED", parameters=param_entries(["x"])))
    client = fake_client(bad, bad, bad)
    with pytest.raises(SystemExit) as exc:
        query(docs, client, decl)
    assert exc.value.code == 1
    assert "MAX_SPEED.x" in sent_prompts(client)[1]


def test_query_retries_missing_member_with_feedback(docs, sleeps):
    """A response without the requested member is retried with feedback."""
    other = gemini_reply(good_member(name="other", parameters=[]))
    client = fake_client(other, gemini_reply(good_member()))

    result = query(docs, client)

    assert "ensure_initial_focus" in result
    assert "Missing documentation for requested members" in sent_prompts(client)[1]


def test_query_retries_missing_parameters_key(docs, sleeps):
    """A member without a 'parameters' key is retried, not accepted as empty."""
    without_key = good_member()
    del without_key["parameters"]
    client = fake_client(gemini_reply(without_key), gemini_reply(good_member()))

    query(docs, client)

    assert "parameters" in sent_prompts(client)[1].split(REJECTED_MARKER)[1]
    assert sleeps == [5]


@pytest.mark.parametrize("text", [None, "", "not json", '{"members":', "null", "{}"])
def test_query_retries_malformed_response_text(docs, sleeps, text):
    """Empty, truncated or structurally invalid JSON gets a fast corrective retry."""
    client = fake_client(SimpleNamespace(text=text), gemini_reply(good_member()))

    result = query(docs, client)

    assert set(result) == {"ensure_initial_focus"}
    assert client.models.generate_content.call_count == 2
    assert REJECTED_MARKER in sent_prompts(client)[1]
    assert sleeps == [5]


@pytest.mark.parametrize(
    "parameters, reason",
    [
        (param_entries(["candidate", "candidate"]), "Duplicate parameter entries"),
        ([{"name": "candidate"}], "description"),
        ({"candidate": "Receives focus."}, "parameters"),
        (
            [{"name": "a-b", "description": "Receives focus."}],
            "Invalid parameter identifier",
        ),
        (
            [{"name": "candidate", "description": "The candidate parameter."}],
            "Missing or placeholder parameter descriptions",
        ),
    ],
    ids=[
        "duplicate",
        "missing-description",
        "legacy-map",
        "invalid-name",
        "placeholder",
    ],
)
def test_query_retries_bad_parameter_entries(docs, sleeps, parameters, reason):
    """Nested schema and semantic errors both reach the retry feedback."""
    client = fake_client(
        gemini_reply(good_member(parameters=parameters)), gemini_reply(good_member())
    )

    result = query(docs, client)

    assert result["ensure_initial_focus"].param_map == {
        name: f"Meaningful description of {name}." for name in FOCUS_PARAMS
    }
    assert reason in sent_prompts(client)[1].split(REJECTED_MARKER)[1]
    assert client.models.generate_content.call_count == 2
    assert sleeps == [5]


@pytest.mark.parametrize("kind", ["function", "signal", "constant", "export", "enum"])
@pytest.mark.parametrize("parameters", [[], None], ids=["empty-list", "explicit-null"])
def test_query_accepts_parameterless_members(docs, sleeps, kind, parameters):
    """An explicit empty or null list is valid when the declaration has no arguments."""
    client = fake_client(gemini_reply(good_member(parameters=parameters)))
    result = query(docs, client, make_decl(docs, kind=kind, params=[]))
    assert result["ensure_initial_focus"].parameters == []
    assert client.models.generate_content.call_count == 1
    assert sleeps == []


@pytest.mark.parametrize("api_error_first", [False, True])
def test_query_mixed_failures_keep_feedback_and_backoff_separate(
    docs, sleeps, api_error_first
):
    """API failures preserve corrective feedback and use their own backoff delay."""
    bad = gemini_reply(good_member(parameters=[]))
    error = RuntimeError("503 UNAVAILABLE")
    outcomes = [error, bad] if api_error_first else [bad, error]
    client = fake_client(*outcomes, gemini_reply(good_member()))

    result = query(docs, client)

    assert set(result) == {"ensure_initial_focus"}
    first, second, third = sent_prompts(client)
    assert REJECTED_MARKER not in first
    assert sleeps == ([35, 5] if api_error_first else [5, 35])
    if api_error_first:
        assert second == first
        assert "ensure_initial_focus.context" in third.split(REJECTED_MARKER)[1]
    else:
        assert second == third
        assert "ensure_initial_focus.context" in second.split(REJECTED_MARKER)[1]


def test_query_replaces_outdated_validation_feedback(docs, sleeps):
    """Each correction describes the latest rejection without accumulating old errors."""
    client = fake_client(
        gemini_reply(good_member(parameters=[])),
        gemini_reply(good_member(parameters=param_entries(FOCUS_PARAMS + ["bogus"]))),
        gemini_reply(good_member()),
    )

    query(docs, client)

    first, second, third = sent_prompts(client)
    assert "Missing or placeholder parameter descriptions" in second
    assert "Parameters not declared in the signature" in third
    assert "Missing or placeholder parameter descriptions" not in third
    assert third.count(REJECTED_MARKER) == 1
    assert third.split("\n\n" + REJECTED_MARKER)[0] == first
    assert sleeps == [5, 5]


def test_query_bounds_validation_feedback_length(docs, sleeps):
    """Large validation errors cannot grow the corrective prompt without a bound."""
    names = [f"required_control_{index}" for index in range(150)]
    client = fake_client(
        gemini_reply(good_member(parameters=[])),
        gemini_reply(good_member(parameters=param_entries(names))),
    )

    result = query(docs, client, make_decl(docs, params=names))

    feedback = sent_prompts(client)[1].split(f"{REJECTED_MARKER} FOR THESE REASONS:\n")[
        1
    ]
    feedback = feedback.split("\nReturn a corrected response")[0]
    assert len(feedback) == 2000
    assert feedback.startswith("Missing or placeholder parameter descriptions:")
    assert "ensure_initial_focus.required_control_149" not in feedback
    assert set(result["ensure_initial_focus"].param_map) == set(names)
    assert sleeps == [5]


@pytest.mark.parametrize(
    "api_failure", [False, True], ids=["invalid-json", "api-failure"]
)
def test_query_stops_after_three_failed_attempts(docs, sleeps, capsys, api_failure):
    """Exhausted retries exit with no sleep or extra call after the final failure."""
    outcome = (
        RuntimeError("503 UNAVAILABLE") if api_failure else SimpleNamespace(text=None)
    )
    client = fake_client(outcome, outcome, outcome)

    with pytest.raises(SystemExit) as exc:
        query(docs, client)

    assert exc.value.code == 1
    assert client.models.generate_content.call_count == 3
    assert sleeps == ([35, 70] if api_failure else [5, 5])
    assert "after 3 attempts" in capsys.readouterr().out


def test_query_scopes_validation_and_feedback_to_each_chunk(docs, sleeps):
    """Extra future members are ignored and do not carry rejected docs to their chunk."""
    first = good_member()
    extra = good_member(name="other", parameters=param_entries(["bogus"]))
    corrected = good_member(
        name="other",
        parameters=param_entries(["value"]),
        summary="Stores the new value.",
    )
    client = fake_client(
        gemini_reply(good_member(parameters=[])),
        gemini_reply(first, extra),
        gemini_reply(corrected),
    )
    targets = [make_decl(docs), make_decl(docs, name="other", params=["value"])]

    result = docs.query_gemini_for_docs(client, Path("globals.gd"), targets)

    assert set(result) == {"ensure_initial_focus", "other"}
    assert result["other"].param_map == {"value": "Meaningful description of value."}
    assert result["other"].summary == "Stores the new value."
    prompts = sent_prompts(client)
    assert REJECTED_MARKER in prompts[1]
    assert REJECTED_MARKER not in prompts[2]
    manifests = [
        json.JSONDecoder().raw_decode(
            prompt.split("Target declarations needing documentation:\n")[1]
        )[0]
        for prompt in (prompts[0], prompts[2])
    ]
    assert [[entry["name"] for entry in manifest] for manifest in manifests] == [
        ["ensure_initial_focus"],
        ["other"],
    ]
    assert sleeps == [5, 5]  # One corrective retry, then pacing between chunks.


def test_query_resets_api_backoff_for_each_chunk(docs, sleeps):
    """A new chunk starts with the initial API delay after an earlier chunk recovers."""
    client = fake_client(
        RuntimeError("429 RESOURCE_EXHAUSTED"),
        gemini_reply(good_member()),
        RuntimeError("429 RESOURCE_EXHAUSTED"),
        gemini_reply(good_member(name="other", parameters=[])),
    )
    targets = [make_decl(docs), make_decl(docs, name="other", params=[])]

    result = docs.query_gemini_for_docs(client, Path("globals.gd"), targets)

    assert set(result) == {"ensure_initial_focus", "other"}
    assert client.models.generate_content.call_count == 4
    assert sleeps == [35, 5, 35]
    assert not any(REJECTED_MARKER in prompt for prompt in sent_prompts(client))


# -----------------------------------------------------------------------------
# 7. Write batches
# -----------------------------------------------------------------------------
def queue(*slot_counts):
    """Actionable-file queue entries with the given slot counts."""
    return [(Path(f"scripts/core/file_{i}.gd"), n) for i, n in enumerate(slot_counts)]


def test_batch_stops_at_file_limit(docs):
    """No more than max_files files are taken, in queue order."""
    files = queue(1, 1, 1, 1)
    assert docs.select_write_batch(files, max_files=2, max_slots=30) == files[:2]


def test_batch_stops_before_exceeding_slot_budget(docs):
    """A file that would overflow the slot budget ends the batch, keeping order."""
    files = queue(10, 15, 10, 1)
    assert docs.select_write_batch(files, max_files=5, max_slots=30) == files[:2]


def test_batch_always_takes_first_file(docs):
    """An oversized first file is still processed, alone, so it cannot block the queue."""
    files = queue(40, 1)
    assert docs.select_write_batch(files, max_files=5, max_slots=30) == files[:1]


def test_batch_defaults_follow_module_limits(docs, monkeypatch):
    """Without arguments the batch uses the module-level limits."""
    monkeypatch.setattr(docs, "MAX_FILES_MODIFIED_PER_RUN", 1)
    files = queue(1, 1)
    assert docs.select_write_batch(files) == files[:1]


def test_batch_of_empty_queue_is_empty(docs):
    """Nothing to do yields an empty batch."""
    assert docs.select_write_batch([], max_files=5, max_slots=30) == []


def test_batch_limits_stay_within_free_tier_quota(docs):
    """Pacing stays under 15 RPM, and a worst-case batch fits the 500 requests/day."""
    assert 60 / docs.REQUEST_PACING_SECONDS <= 15
    assert docs.MAX_DOC_SLOTS_MODIFIED_PER_RUN * 3 <= 500  # 3 attempts per slot


GD_TEMPLATE = "extends Node\n\n\nfunc {name}(value: int) -> void:\n\tpass\n"


@pytest.fixture
def scripts_tree(tmp_path, monkeypatch):
    """A fake repo with three undocumented production scripts; cwd set to it."""
    for sub, name in [("core", "a_one"), ("core", "b_two"), ("ui", "c_three")]:
        path = tmp_path / "scripts" / sub / f"{name}.gd"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(GD_TEMPLATE.format(name=name), encoding="utf-8")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    return tmp_path


def run_write(docs, monkeypatch, max_files):
    """Run main() --write with a fake client; return prepared and committed files."""
    prepared, committed = [], []
    monkeypatch.setattr(docs, "MAX_FILES_MODIFIED_PER_RUN", max_files)
    monkeypatch.setattr(docs.genai, "Client", lambda api_key: object())

    def fake_prepare(client, path, check_mode):
        """Record the file and return an empty change instead of calling Gemini."""
        prepared.append(path.name)
        return docs.ProposedFileChange(path, "", "", 1)

    monkeypatch.setattr(docs, "prepare_file_change", fake_prepare)
    monkeypatch.setattr(
        docs,
        "atomic_commit_all_changes",
        lambda changes: committed.extend(c.file_path.name for c in changes),
    )
    monkeypatch.setattr("sys.argv", ["update_gdscript_docs.py", "--write"])
    docs.main()
    return prepared, committed


def test_write_with_default_limits_takes_whole_small_queue(
    docs, scripts_tree, monkeypatch, sleeps
):
    """With the shipped limits, a small queue is cleared in one run."""
    prepared, committed = run_write(docs, monkeypatch, docs.MAX_FILES_MODIFIED_PER_RUN)
    assert prepared == committed == ["a_one.gd", "b_two.gd", "c_three.gd"]


def test_write_processes_a_batch_in_queue_order(
    docs, scripts_tree, monkeypatch, sleeps
):
    """--write prepares several files in order and commits them together."""
    prepared, committed = run_write(docs, monkeypatch, max_files=2)
    assert prepared == ["a_one.gd", "b_two.gd"]
    assert committed == ["a_one.gd", "b_two.gd"]
    assert sleeps == [docs.REQUEST_PACING_SECONDS]  # paced between files


def test_write_commits_nothing_when_a_file_fails(
    docs, scripts_tree, monkeypatch, sleeps
):
    """A failure in a later file fails closed before anything is written."""
    committed = []

    def fake_prepare(client, path, check_mode):
        """Fail closed on the second file, as prepare_file_change does on errors."""
        if path.name == "b_two.gd":
            sys.exit(1)
        return docs.ProposedFileChange(path, "", "", 1)

    monkeypatch.setattr(docs.genai, "Client", lambda api_key: object())
    monkeypatch.setattr(docs, "prepare_file_change", fake_prepare)
    monkeypatch.setattr(docs, "atomic_commit_all_changes", committed.extend)
    monkeypatch.setattr("sys.argv", ["update_gdscript_docs.py", "--write"])
    with pytest.raises(SystemExit):
        docs.main()
    assert committed == []


# -----------------------------------------------------------------------------
# 8. Round trip through prepare_file_change
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
# 9. Dependency pins
# -----------------------------------------------------------------------------
def test_docs_workflow_cache_tracks_shared_requirements():
    """Changing the shared pins invalidates the documentation workflow's pip cache."""
    workflow = yaml.safe_load(
        (PROJECT_ROOT / ".github/workflows/bi_weekly_gd_docstrings.yml").read_text(
            encoding="utf-8"
        )
    )
    setups = [
        step
        for step in workflow["jobs"]["sync-docstrings"]["steps"]
        if step.get("uses", "").startswith("actions/setup-python@")
    ]
    assert len(setups) == 1
    assert setups[0]["with"]["cache"] == "pip"
    assert (
        setups[0]["with"]["cache-dependency-path"]
        == REQUIREMENTS.relative_to(PROJECT_ROOT).as_posix()
    )


def test_every_workflow_running_ci_tests_installs_docs_requirements():
    """Any workflow that runs tests/ci/ must install the docs pins (#1058).

    test_update_gdscript_docs.py cannot even be collected without them, so a new
    runner of tests/ci/ that forgets the install breaks CI.
    """
    workflows = sorted((PROJECT_ROOT / ".github/workflows").glob("*.yml"))
    missing = []
    for path in workflows:
        text = path.read_text(encoding="utf-8")
        runs_ci_tests = re.search(
            r"pytest[^\n]*tests/ci|test_path:\s*\"tests/ci/", text
        )
        if runs_ci_tests and ".github/scripts/requirements-docs.txt" not in text:
            missing.append(path.name)
    assert missing == [], missing


def test_docs_requirements_are_exact_pins():
    """requirements-docs.txt pins exactly the three docs dependencies."""
    entries = [
        line.strip()
        for line in REQUIREMENTS.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    names = []
    for entry in entries:
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([A-Za-z0-9_.+-]+)", entry)
        assert match, f"Not an exact pin: {entry!r}"
        # PEP 503 normalisation: google_genai, Google.GenAI and google-genai match
        names.append(re.sub(r"[-_.]+", "-", match.group(1)).lower())
    assert len(names) == len(set(names)), f"Package pinned more than once: {names}"
    assert set(names) == {"google-genai", "pydantic", "gdtoolkit"}


@pytest.mark.parametrize(
    "workflow_path, job",
    [
        (".github/workflows/bi_weekly_gd_docstrings.yml", "sync-docstrings"),
        (".github/workflows/test_ci_scripts.yml", "test-python"),
        # The "CI & Security" browser shard also runs tests/ci/*.py (#1058)
        (".github/workflows/browser_test.yml", "test-shard"),
    ],
)
def test_workflows_install_docs_requirements_file(workflow_path, job):
    """Every workflow that runs these tests installs the shared pins, never inline."""
    workflow = yaml.safe_load(
        (PROJECT_ROOT / workflow_path).read_text(encoding="utf-8")
    )
    # Only active shell lines count: a commented-out install must not pass
    active_lines = [
        line.strip()
        for step in workflow["jobs"][job]["steps"]
        for line in step.get("run", "").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    assert any(
        re.fullmatch(r"pip install -r \.github/scripts/requirements-docs\.txt", line)
        for line in active_lines
    ), active_lines
    assert not any(
        re.search(r"\b(google-genai|gdtoolkit|pydantic)==", line)
        for line in active_lines
    )


# -----------------------------------------------------------------------------
# 10. Legacy Doxygen migration (run 40159019327: player.gd private members)
# -----------------------------------------------------------------------------
VALIDATOR = PROJECT_ROOT / ".github/scripts/validate_gdscript_docs.py"


@pytest.fixture(scope="module")
def validator():
    """Load validate_gdscript_docs.py as a module (.github is not a package)."""
    spec = importlib.util.spec_from_file_location("validate_gdscript_docs", VALIDATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.mark.parametrize(
    "line, expected",
    [
        (
            "## @param event: The input event.\n",
            ["## [param event]: The input event.\n"],
        ),
        (
            "## @param event The input event.\n",
            ["## [param event]: The input event.\n"],
        ),
        (
            "\t## @param event: The input event.\n",
            ["\t## [param event]: The input event.\n"],
        ),
        ("## @return: void\n", []),
        ("## @return void.\n", []),
        ("## @return\n", []),
        ("## @return: The current speed.\n", ["## Returns The current speed.\n"]),
        (
            "## @return: Returns the current speed.\n",
            ["## Returns the current speed.\n"],
        ),
        ("## @brief Moves the plane.\n", ["## Moves the plane.\n"]),
        ("## @brief\n", []),
        (
            "## @param event: The input event.\r\n",
            ["## [param event]: The input event.\r\n"],
        ),
        (
            "  ##\t@param\t_control2 \t: \tThe café control.\t\n",
            ["  ## [param _control2]: The café control.\n"],
        ),
        ("## @param _: Ignored value.", ["## [param _]: Ignored value."]),
        ("## @return: VOID. \t\r\n", []),
        ("## @return:\t\n", []),
        ("## @return: Returns: return: void.\n", []),
        (
            "## @return: RETURN: Returns: the result.\n",
            ["## Returns the result.\n"],
        ),
        (
            "## @return: void when no control exists.\n",
            ["## Returns void when no control exists.\n"],
        ),
        ("  ## @brief: Résumé.\r\n", ["  ## Résumé.\r\n"]),
        ("## @brief: \t\r\n", []),
    ],
)
def test_migrate_rewrites_legacy_line(docs, line, expected):
    """Each legacy tag shape becomes Native BBCode (or is dropped) with its EOL kept."""
    migrated, unmigrated = docs.migrate_legacy_doxygen(line)
    assert unmigrated == []
    assert migrated == "".join(expected)
    assert not docs.RE_DOXYGEN_TAG.search(migrated)


@pytest.mark.parametrize(
    "line",
    [
        "## Mirrors @param handling in the parser.\n",
        "## @param event:\n",
        "## @param event: See @return of fire().\n",
        "## @param\n",
        "## @param 9event: The event.\n",
        "## @param event: \t\n",
        "## @return: See @param event.\n",
        "## @brief: See @return below.\n",
        "## @brief: See @brief below.\n",
        "## Describes @return values.\n",
        "## Describes @brief summaries.\n",
    ],
)
def test_migrate_reports_lines_it_cannot_rewrite(docs, line):
    """Mid-sentence tags and empty @param descriptions are left alone and reported."""
    migrated, unmigrated = docs.migrate_legacy_doxygen(line)
    assert migrated == line
    assert unmigrated == [(1, line.strip())]


def test_migrate_ignores_code_and_plain_comments(docs):
    """Only `##` doc lines are touched; code and `#` comments keep their @ text."""
    source = (
        "# @param kept in a plain comment\n"
        'var tag := "@return"\n'
        "## @return: void\n"
        "func _ready() -> void:\n"
        "\tpass\n"
    )
    migrated, unmigrated = docs.migrate_legacy_doxygen(source)
    assert unmigrated == []
    assert migrated == source.replace("## @return: void\n", "")
    assert docs.compute_non_doc_bytes_sha256(
        source
    ) == docs.compute_non_doc_bytes_sha256(migrated)
    assert docs.verify_modification_allowlist(source, migrated)


def test_migrate_wraps_long_param_lines_under_gdlint_limit(docs):
    """`[param x]:` is longer than `@param x:`, so long lines are re-wrapped."""
    desc = " ".join(["word"] * 30)
    migrated, unmigrated = docs.migrate_legacy_doxygen(f"\t## @param value: {desc}\n")
    assert unmigrated == []
    lines = migrated.splitlines()
    assert len(lines) > 1
    assert lines[0].startswith("\t## [param value]: ")
    assert all(line.startswith("\t## ") for line in lines)
    assert all(len(line) <= docs.LEGACY_DOC_MAX_WIDTH for line in lines)
    assert unwrap_param(lines, "value") == desc


@pytest.mark.parametrize(
    "source",
    [
        "",
        "\n\t\n",
        "##\r\n## Already native [param value]: [b]café[/b].\r\n",
        "## @parameter value, @returns and @briefly are different words.\n",
        "## Contact user@param or refer to key@return and key@brief.\n",
        'var tag := "@brief" # @param stays inline\r\n',
        "# @return: void\n### @brief stays an ordinary comment\n",
        "var value := 1 ## @param stays inline\n",
        "##@param value: No whitespace after the comment marker.\n",
        "## " + "Unchanged native documentation. " * 5,
    ],
    ids=[
        "empty",
        "whitespace",
        "native-bbcode",
        "tag-suffixes",
        "embedded-at",
        "code",
        "plain-comments",
        "inline-comment",
        "non-doc-marker",
        "long-native",
    ],
)
def test_migrate_preserves_source_without_legacy_doc_tags(docs, source):
    """Unrelated text and already native docs must remain byte-for-byte identical."""
    assert docs.migrate_legacy_doxygen(source) == (source, [])


@pytest.mark.parametrize(
    "legacy_lead, native_lead",
    [
        ("@param value: ", "[param value]: "),
        ("@return: ", "Returns "),
        ("@brief: ", ""),
    ],
    ids=["param", "return", "brief"],
)
@pytest.mark.parametrize("extra_columns", [0, 1], ids=["at-margin", "past-margin"])
@pytest.mark.parametrize("eol", ["\n", "\r\n"], ids=["lf", "crlf"])
def test_migrate_wraps_at_margin_without_losing_description(
    docs, legacy_lead, native_lead, extra_columns, eol
):
    """All tag types wrap at 95 columns, preserving prose, indentation and EOLs."""
    prefix = "  ## "
    description_width = 95 - len(prefix + native_lead) + extra_columns
    description = "x " * ((description_width - 1) // 2)
    description += "x" * (description_width - len(description))

    migrated, unmigrated = docs.migrate_legacy_doxygen(
        f"{prefix}{legacy_lead}{description}{eol}"
    )

    assert unmigrated == []
    lines = migrated.splitlines(keepends=True)
    assert len(lines) == 1 + extra_columns
    assert all(line.startswith(prefix) and line.endswith(eol) for line in lines)
    assert all(len(line.removesuffix(eol)) <= 95 for line in lines)
    payload = " ".join(line.removesuffix(eol).removeprefix(prefix) for line in lines)
    assert payload == native_lead + description
    assert docs.migrate_legacy_doxygen(migrated) == (migrated, [])


def test_migrate_reports_original_line_numbers_after_removal_and_wrapping(docs):
    """Diagnostics refer to input lines even when earlier migrations change length."""
    long_description = "word " * 30
    source = (
        "## @return: void\n"
        f"## @brief {long_description}\n"
        "  ## @param event: \t\n"
        "func _ready() -> void:\n"
        "\tpass\n"
        "\t## See @return below."
    )

    migrated, unmigrated = docs.migrate_legacy_doxygen(source)

    assert unmigrated == [(3, "## @param event:"), (6, "## See @return below.")]
    assert migrated.startswith("## word ")
    assert "@brief" not in migrated
    assert migrated.endswith("\t## See @return below.")
    assert "  ## @param event: \t\n" in migrated


def test_migrate_preserves_mixed_eols_and_non_doc_bytes(docs):
    """Removing and wrapping docs preserves code, Unicode and a missing final EOL."""
    description = "word " * 30
    code = 'extends Node\r\n# @param café stays\nvar label := "café @return"'
    source = (
        "## @brief: Résumé.\r\n"
        "extends Node\r\n"
        "## @return: void\n"
        "# @param café stays\n"
        f"## @param value: {description}\r\n"
        'var label := "café @return"'
    )

    migrated, unmigrated = docs.migrate_legacy_doxygen(source)

    assert unmigrated == []
    assert migrated.startswith("## Résumé.\r\nextends Node\r\n")
    assert "## @return: void" not in migrated
    assert (
        "".join(
            line
            for line in migrated.splitlines(keepends=True)
            if not line.lstrip(" \t").startswith("##")
        )
        == code
    )
    wrapped = [line for line in migrated.splitlines(keepends=True) if "word" in line]
    assert len(wrapped) > 1
    assert all(line.endswith("\r\n") for line in wrapped)
    assert docs.compute_non_doc_bytes_sha256(
        source
    ) == docs.compute_non_doc_bytes_sha256(migrated)
    assert docs.verify_modification_allowlist(source, migrated)
    assert docs.migrate_legacy_doxygen(migrated) == (migrated, [])


def unwrap_param(lines, name):
    """Rejoin a wrapped `[param name]:` description into one string."""
    first, *rest = (line.strip() for line in lines)
    prefix = f"## [param {name}]: "
    assert first.startswith(prefix), first
    return " ".join([first[len(prefix) :]] + [line[len("## ") :] for line in rest])


@pytest.mark.parametrize("newline", ["\n", "\r\n"], ids=["lf", "crlf"])
def test_migrate_wraps_final_line_without_eol(docs, newline):
    """Sourcery: a long last line with no EOL must still wrap into separate lines.

    Wrapped lines are separated by the file's own newline style, and the last
    one keeps the missing EOL, so the file ending does not change.
    """
    desc = " ".join(["word"] * 30)
    source = f"extends Node{newline}{newline}## @param value: {desc}"
    migrated, unmigrated = docs.migrate_legacy_doxygen(source)
    assert unmigrated == []
    assert not migrated.endswith(("\n", "\r"))
    doc_lines = migrated.split(newline)[2:]
    assert len(doc_lines) > 1
    assert all(len(line) <= docs.LEGACY_DOC_MAX_WIDTH for line in doc_lines)
    assert all("\n" not in line and "\r" not in line for line in doc_lines)
    assert unwrap_param(doc_lines, "value") == desc


def test_migrate_drops_legacy_param_already_documented_natively(docs):
    """Sourcery: a block with `[param x]` and `@param x` keeps one `[param x]` only."""
    source = (
        "## Moves.\n"
        "## [param x]: The native description.\n"
        "## @param x: The legacy description.\n"
        "## @param y: The second value.\n"
        "## @param y: A repeated legacy entry.\n"
        "func _move(x: int, y: int) -> void:\n"
        "\tpass\n"
    )
    migrated, unmigrated = docs.migrate_legacy_doxygen(source)
    assert unmigrated == []
    assert migrated == (
        "## Moves.\n"
        "## [param x]: The native description.\n"
        "## [param y]: The second value.\n"
        "func _move(x: int, y: int) -> void:\n"
        "\tpass\n"
    )


@pytest.mark.parametrize(
    "declaration, kept",
    [
        ("func _speed() -> void:", False),
        ("static func _speed() -> void:", False),
        ("func _speed() -> float:", True),
        ("func _speed():", True),
    ],
    ids=["void", "static-void", "float", "untyped"],
)
def test_migrate_return_text_follows_declared_return_type(docs, declaration, kept):
    """Sourcery: `@return: text` on a `-> void` function is dropped, not migrated
    into a `Returns` line the validator rejects for void functions.
    """
    source = (
        "## Reads the speed.\n"
        "## @return: The current speed.\n"
        '@warning_ignore("unused_parameter")\n'
        f"{declaration}\n"
        "\tpass\n"
    )
    migrated, unmigrated = docs.migrate_legacy_doxygen(source)
    assert unmigrated == []
    assert ("## Returns The current speed.\n" in migrated) is kept
    assert not docs.RE_DOXYGEN_TAG.search(migrated)


@pytest.mark.parametrize(
    "signature, kept",
    [
        ("func _move(\n\tx: int,\n\ty: int\n) -> void:\n", False),
        ("static func _move(\n\tx: int, y: int\n) -> void:\n", False),
        ("func _move(\n\tx: int,\n\ty: int\n) -> float:\n", True),
        ("func _move(\n\tx: int,\n\ty: int\n):\n", True),
        ("var speed: float = 0.0\n", True),
    ],
    ids=[
        "wrapped-void",
        "wrapped-static-void",
        "wrapped-float",
        "wrapped-untyped",
        "var",
    ],
)
def test_migrate_return_text_follows_wrapped_signature(docs, signature, kept):
    """CodeRabbit: a signature whose `-> void:` is on a later line is still void.

    Only a `func` declaration can be void; a `var` after the block keeps its text.
    """
    source = (
        "## Moves the plane.\n"
        "## @return: The new position.\n"
        '@warning_ignore("unused_parameter")\n'
        f"{signature}"
        "\tpass\n"
    )
    migrated, unmigrated = docs.migrate_legacy_doxygen(source)
    assert unmigrated == []
    assert ("## Returns The new position.\n" in migrated) is kept
    assert not docs.RE_DOXYGEN_TAG.search(migrated)
    assert migrated.endswith(f"{signature}\tpass\n")


def test_migrate_return_text_kept_when_block_ends_file(docs):
    """A doc block with no declaration after it keeps its migrated Returns line."""
    migrated, unmigrated = docs.migrate_legacy_doxygen("## @return: The value.\n")
    assert unmigrated == []
    assert migrated == "## Returns The value.\n"


@pytest.mark.parametrize(
    "legacy_line",
    [
        "## @return: The value.\n",
        "## @brief Moves the plane.\n",
        "## Mirrors @param handling.\n",
    ],
    ids=["return", "brief", "mid-sentence"],
)
def test_public_member_with_legacy_tag_is_non_compliant(docs, legacy_line):
    """Sourcery: public docs with legacy tags are regenerated, never migrated.

    The tokenizer accepts these lines, so before the fix such members counted
    as COMPLIANT and the migration rewrote them into validator failures.
    """
    source = f"extends Node\n\n\n## Moves.\n{legacy_line}func stop() -> void:\n\tpass\n"
    decls, ok = docs.parse_declarations_from_ast(source)
    assert ok
    (decl,) = decls
    docs.classify_member(decl)
    assert decl.status == docs.DocStatus.NON_COMPLIANT


LEGACY_FIXTURE_GD = (
    "extends Node\n"
    "\n"
    "\n"
    "## Called when the node enters the scene tree.\n"
    "## @return: void\n"
    "func _ready() -> void:\n"
    "\tpass\n"
    "\n"
    "\n"
    "## Captures input events.\n"
    "## @param event: The input event detected by the engine.\n"
    "## @return: void\n"
    "func _input(event: InputEvent) -> void:\n"
    "\tpass\n"
    "\n"
    "\n"
    "## Moves focus.\n"
    "## @param candidate: Control to focus.\n"
    "## @return: void\n"
    "func ensure_initial_focus(candidate: Control, allowed_controls: Array, context: String) -> void:\n"
    "\tpass\n"
)


def test_generator_output_passes_validator_with_private_legacy_tags(
    docs, validator, tmp_path, sleeps
):
    """Regression for run 40159019327: the generator regenerated the public member,
    left private `_ready`/`_input` Doxygen tags in place, and the contract validator
    (which scans every `##` line of a modified file) failed the job.
    """
    gd_file = tmp_path / "player.gd"
    gd_file.write_text(LEGACY_FIXTURE_GD, encoding="utf-8")
    client = fake_client(gemini_reply(good_member()))

    change = docs.prepare_file_change(client, gd_file, check_mode=False)

    assert change is not None
    assert not docs.RE_DOXYGEN_TAG.search(change.proposed_source)
    assert "## [param event]: The input event detected by the engine.\n" in (
        change.proposed_source
    )
    assert docs.compute_non_doc_bytes_sha256(
        LEGACY_FIXTURE_GD
    ) == docs.compute_non_doc_bytes_sha256(change.proposed_source)

    gd_file.write_text(change.proposed_source, encoding="utf-8")
    assert validator.validate_file(gd_file) == []


def test_generator_skips_file_with_unmigratable_legacy_tag(
    docs, tmp_path, sleeps, capsys
):
    """A tag the migration cannot rewrite skips that file (with a ::warning) before
    any Gemini call, instead of producing a change the validator would reject later.
    """
    source = LEGACY_FIXTURE_GD.replace(
        "## Captures input events.\n", "## Captures input events, see @param below.\n"
    )
    gd_file = tmp_path / "player.gd"
    gd_file.write_text(source, encoding="utf-8")
    client = fake_client(gemini_reply(good_member()))

    change = docs.prepare_file_change(client, gd_file, check_mode=False)

    assert change is None
    client.models.generate_content.assert_not_called()
    out = capsys.readouterr().out
    # Sourcery: the warning points at the line in the unchanged file on disk
    assert f"::warning file={gd_file},line=10::" in out
    assert "[SKIPPED: LEGACY DOXYGEN] player.gd" in out
    assert gd_file.read_text(encoding="utf-8") == source


def test_unmigratable_tag_in_regenerated_member_does_not_skip(
    docs, validator, tmp_path, sleeps
):
    """A tag the migration cannot rewrite is fine inside a member Gemini regenerates."""
    source = LEGACY_FIXTURE_GD.replace(
        "## Moves focus.\n", "## Moves focus, see @param below.\n"
    )
    gd_file = tmp_path / "player.gd"
    gd_file.write_text(source, encoding="utf-8")
    client = fake_client(gemini_reply(good_member()))

    change = docs.prepare_file_change(client, gd_file, check_mode=False)

    assert change is not None
    assert not docs.RE_DOXYGEN_TAG.search(change.proposed_source)
    gd_file.write_text(change.proposed_source, encoding="utf-8")
    assert validator.validate_file(gd_file) == []


PUBLIC_LEGACY_FIXTURE_GD = LEGACY_FIXTURE_GD + (
    "\n"
    "\n"
    "## Stops the rotors.\n"
    "## @return: Nothing useful.\n"
    "func stop() -> void:\n"
    "\tpass\n"
)


def test_public_member_with_legacy_return_is_regenerated(
    docs, validator, tmp_path, sleeps
):
    """Sourcery: a public void function with `@return: text` is regenerated by
    Gemini, so no `Returns` line reaches the validator.
    """
    gd_file = tmp_path / "player.gd"
    gd_file.write_text(PUBLIC_LEGACY_FIXTURE_GD, encoding="utf-8")
    stop = good_member(name="stop", summary="Stops both rotors.", parameters=[])
    client = fake_client(gemini_reply(good_member()), gemini_reply(stop))

    change = docs.prepare_file_change(client, gd_file, check_mode=False)

    assert change is not None
    assert change.slots_count == 2
    assert "## Stops both rotors.\nfunc stop() -> void:\n" in change.proposed_source
    assert "Returns" not in change.proposed_source
    gd_file.write_text(change.proposed_source, encoding="utf-8")
    assert validator.validate_file(gd_file) == []


def test_generator_fails_closed_when_migration_breaks_compliant_member(
    docs, tmp_path, sleeps, monkeypatch, capsys
):
    """Members that were COMPLIANT are re-verified after the whole-file migration."""
    source = (
        LEGACY_FIXTURE_GD + "\n\n## Stops the rotors.\nfunc stop() -> void:\n\tpass\n"
    )
    gd_file = tmp_path / "player.gd"
    gd_file.write_text(source, encoding="utf-8")
    real_migrate = docs.migrate_legacy_doxygen

    def corrupting_migrate(text):
        """Real migration, then an unclosed [b] in the compliant member's docs."""
        migrated, unmigrated = real_migrate(text)
        return migrated.replace("## Stops the rotors.\n", "## [b]Stops.\n"), unmigrated

    monkeypatch.setattr(docs, "migrate_legacy_doxygen", corrupting_migrate)
    client = fake_client(gemini_reply(good_member()))

    with pytest.raises(SystemExit) as exc:
        docs.prepare_file_change(client, gd_file, check_mode=False)

    assert exc.value.code == 1
    assert "Compliant declaration stop became" in capsys.readouterr().out
    assert gd_file.read_text(encoding="utf-8") == source


def test_generator_fails_closed_when_tags_survive_migration(
    docs, tmp_path, sleeps, monkeypatch, capsys
):
    """Tags left after injection (pre-check bypassed) fail closed, never ship."""
    gd_file = tmp_path / "player.gd"
    gd_file.write_text(LEGACY_FIXTURE_GD, encoding="utf-8")
    real_migrate = docs.migrate_legacy_doxygen
    calls = []

    def leaky_migrate(text):
        """Pass the pre-check, then report a leftover tag after injection."""
        calls.append(text)
        migrated, _ = real_migrate(text)
        return migrated, ([] if len(calls) == 1 else [(5, "## @return: void")])

    monkeypatch.setattr(docs, "migrate_legacy_doxygen", leaky_migrate)
    client = fake_client(gemini_reply(good_member()))

    with pytest.raises(SystemExit) as exc:
        docs.prepare_file_change(client, gd_file, check_mode=False)

    assert exc.value.code == 1
    assert len(calls) == 2
    assert "Legacy Doxygen left after migration" in capsys.readouterr().out


def test_generator_check_mode_leaves_legacy_docs_untouched(docs, tmp_path):
    """Checking actionable members neither migrates private docs nor calls Gemini."""
    gd_file = tmp_path / "player.gd"
    gd_file.write_text(LEGACY_FIXTURE_GD, encoding="utf-8")
    client = fake_client()

    change = docs.prepare_file_change(client, gd_file, check_mode=True)

    assert change is not None
    assert change.slots_count == 1
    assert change.original_source == change.proposed_source == LEGACY_FIXTURE_GD
    client.models.generate_content.assert_not_called()
    assert gd_file.read_text(encoding="utf-8") == LEGACY_FIXTURE_GD


def test_generator_does_not_migrate_files_without_actionable_members(docs, tmp_path):
    """Legacy private docs alone must not cause an otherwise untouched file to change."""
    source = LEGACY_FIXTURE_GD.split("## Moves focus.\n")[0]
    gd_file = tmp_path / "player.gd"
    gd_file.write_text(source, encoding="utf-8")
    client = fake_client()

    assert docs.prepare_file_change(client, gd_file, check_mode=False) is None

    client.models.generate_content.assert_not_called()
    assert gd_file.read_text(encoding="utf-8") == source


def test_generator_reports_every_unsafe_legacy_line(docs, tmp_path, sleeps, capsys):
    """A skipped file reports all unsafe lines with their path and input line number."""
    source = LEGACY_FIXTURE_GD.replace(
        "## Called when the node enters the scene tree.", "## See @brief below."
    ).replace("## Captures input events.", "## See @param below.")
    gd_file = tmp_path / "player.gd"
    gd_file.write_text(source, encoding="utf-8")
    client = fake_client(gemini_reply(good_member()))

    assert docs.prepare_file_change(client, gd_file, check_mode=False) is None

    warnings = [
        line
        for line in capsys.readouterr().out.splitlines()
        if line.startswith("::warning ")
    ]
    assert warnings == [
        f"::warning file={gd_file},line={line_number}::Legacy Doxygen tag cannot be "
        f"migrated automatically: {line}"
        for line_number, line in enumerate(source.splitlines(), start=1)
        if line in ("## See @brief below.", "## See @param below.")
    ]
    assert len(warnings) == 2
    assert gd_file.read_text(encoding="utf-8") == source


def test_write_continues_after_unsafe_legacy_file(
    docs, validator, scripts_tree, monkeypatch, sleeps, capsys
):
    """Skip an unsafe file while writing valid files before and after it."""
    paths = [
        scripts_tree / "scripts/core/a_one.gd",
        scripts_tree / "scripts/core/b_two.gd",
        scripts_tree / "scripts/ui/c_three.gd",
    ]
    unsafe_source = LEGACY_FIXTURE_GD.replace(
        "## Captures input events.", "## See @param below."
    )
    for path in paths:
        source = unsafe_source if path == paths[1] else LEGACY_FIXTURE_GD
        path.write_text(source, encoding="utf-8")
    client = fake_client(*(gemini_reply(good_member()) for _ in paths))
    monkeypatch.setattr(docs.genai, "Client", lambda api_key: client)
    monkeypatch.setattr("sys.argv", ["update_gdscript_docs.py", "--write"])

    docs.main()

    assert paths[1].read_text(encoding="utf-8") == unsafe_source
    for path in (paths[0], paths[2]):
        proposed = path.read_text(encoding="utf-8")
        assert proposed != LEGACY_FIXTURE_GD
        assert "## [param event]: The input event detected by the engine." in proposed
        assert not docs.RE_DOXYGEN_TAG.search(proposed)
        assert validator.validate_file(path) == []
        assert docs.compute_non_doc_bytes_sha256(
            proposed
        ) == docs.compute_non_doc_bytes_sha256(LEGACY_FIXTURE_GD)
    # The unsafe file is skipped before its Gemini call (Phase 1b), so only the two
    # written files use quota; pacing between files is unchanged.
    assert client.models.generate_content.call_count == 2
    assert sleeps == [docs.REQUEST_PACING_SECONDS] * 2
    assert "[SKIPPED: LEGACY DOXYGEN] b_two.gd" in capsys.readouterr().out
    assert sorted((scripts_tree / "scripts").rglob("*.*")) == sorted(paths)


# -----------------------------------------------------------------------------
# 11. Production scripts stay migratable
# -----------------------------------------------------------------------------
PRODUCTION_SCRIPTS = sorted(
    path
    for subdir in ("core", "entities", "managers", "resources", "system", "ui")
    for path in (PROJECT_ROOT / "scripts" / subdir).rglob("*.gd")
)


@pytest.mark.parametrize(
    "script",
    PRODUCTION_SCRIPTS,
    ids=[p.relative_to(PROJECT_ROOT).as_posix() for p in PRODUCTION_SCRIPTS],
)
def test_production_script_legacy_docs_migrate_cleanly(docs, script):
    """Every legacy Doxygen line in a real production script can be migrated.

    A line the migration cannot rewrite (a tag mid-sentence, an empty @param)
    makes the docs sync skip that whole file, so it would never be documented.
    This catches such a line in the PR that adds it, not weeks later in the
    scheduled run. The migration must also keep code bytes identical and be
    idempotent, so a second docs sync run changes nothing.
    """
    source = script.read_text(encoding="utf-8")

    migrated, unmigrated = docs.migrate_legacy_doxygen(source)

    assert (
        unmigrated == []
    ), f"{script.name}: rewrite these doc lines by hand (Native BBCode): {unmigrated}"
    assert not docs.RE_DOXYGEN_TAG.search(
        "".join(
            line
            for line in migrated.splitlines(keepends=True)
            if docs.RE_DOC_LINE.match(line.rstrip("\r\n"))
        )
    )
    assert docs.compute_non_doc_bytes_sha256(
        source
    ) == docs.compute_non_doc_bytes_sha256(migrated)
    assert docs.verify_modification_allowlist(source, migrated)
    assert docs.migrate_legacy_doxygen(migrated) == (migrated, [])
    assert all(
        len(line.rstrip("\r\n")) <= 100
        for line in migrated.splitlines()
        if docs.RE_DOC_LINE.match(line)
    )


def test_production_scripts_are_found():
    """Guards the parametrized test above against silently collecting nothing."""
    assert len(PRODUCTION_SCRIPTS) >= 30
    assert PROJECT_ROOT / "scripts/entities/player.gd" in PRODUCTION_SCRIPTS
