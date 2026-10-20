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
