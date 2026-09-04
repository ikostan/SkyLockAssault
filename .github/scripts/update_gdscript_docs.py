#!/usr/bin/env python3
"""
Deterministic GDScript Documentation Auditor and Transactional Injector.

DOCUMENTATION_CONTRACT_VERSION = "1.0"

Audits and synchronizes production GDScript files against documentation contract v1.0:
- AST parsing via gdtoolkit with explicit metadata collection.
- Top-level class scope isolation (matches contract validator).
- Operational 4-state classification (COMPLIANT, MISSING, NON_COMPLIANT, AMBIGUOUS).
- Bidirectional parameter contract enforcement for functions and signals.
- Project-approved single-pass BBCode grammar validation with case-insensitive code spans.
- Contiguous annotation/comment block resolution.
- Post-injection AST reparse and reclassification verification.
- Non-comment byte-for-byte SHA-256 integrity verification.
- Two-phase staged transaction with atomic replacement and filesystem rollback.
"""

DOCUMENTATION_CONTRACT_VERSION = "1.0"

import argparse
import difflib
import enum
import hashlib
import json
import os
import re
import shutil
import sys
import textwrap
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# -----------------------------------------------------------------------------
# Imports & Fail-Closed Environment Check
# -----------------------------------------------------------------------------
try:
    from gdtoolkit.parser import parser as gdparser
    from google import genai
    from google.genai import types
    from lark.lexer import Token
    from lark.tree import Tree
    from pydantic import BaseModel, Field, field_validator
except ImportError as err:
    print(f"[FAIL-CLOSED] Missing required dependency: {err}")
    sys.exit(1)

# -----------------------------------------------------------------------------
# Configuration & Limits
# -----------------------------------------------------------------------------
MAX_FILES_MODIFIED_PER_RUN = 1
MAX_DOC_SLOTS_MODIFIED_PER_RUN = 100
PINNED_MODEL = "gemini-3.5-flash-lite"
ALLOWED_SUBDIRS = ("core", "entities", "managers", "resources", "system", "ui")

RE_DOC_LINE = re.compile(r"^[ \t]*##(?:\s.*)?$")
RE_BANNED_FENCE = re.compile(r"```")
RE_DOXYGEN_TAG = re.compile(r"(?<![A-Za-z0-9_])@(param|return|brief)\b")

FORMATTING_TAGS = {"b", "i"}

SEMANTIC_TAG_RULES = {
    "param": re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*$"),
    "constant": re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?$"),
    "member": re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?$"),
    "method": re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?$"),
    "signal": re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?$"),
    "enum": re.compile(r"^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)?$"),
}

PROPERTY_EXPORT_ANNOTATIONS = {
    "export",
    "export_range",
    "export_enum",
    "export_file",
    "export_file_path",
    "export_dir",
    "export_global_file",
    "export_global_dir",
    "export_multiline",
    "export_placeholder",
    "export_node_path",
    "export_flags",
    "export_flags_2d_physics",
    "export_flags_2d_render",
    "export_flags_3d_physics",
    "export_flags_3d_render",
    "export_color_no_alpha",
    "export_exp_easing",
    "export_storage",
    "export_custom",
    "export_tool_button",
}

RE_TOKEN_TAG = re.compile(r"\[(/?[a-zA-Z0-9_]+)(?:\s+([^\]]*))?\]")


class DocStatus(enum.Enum):
    COMPLIANT = "COMPLIANT"
    MISSING = "MISSING"
    NON_COMPLIANT = "NON_COMPLIANT"
    AMBIGUOUS = "AMBIGUOUS"


@dataclass
class DocumentationPayload:
    errors: List[str]
    param_names: List[str]
    tags: List[str]


# -----------------------------------------------------------------------------
# Documentation Payload Normalization & BBCode Parser
# -----------------------------------------------------------------------------
def normalize_doc_payload(docs: List[str]) -> str:
    """Strips comment markers ('##') and leading whitespace, returning raw payload."""
    return "".join(re.sub(r"^[ \t]*##[ \t]?", "", line) for line in docs)


def validate_and_tokenize_bbcode(text: str, location_desc: str) -> DocumentationPayload:
    """
    Validates project-approved BBCode via a single-pass token stack.
    - [code] is case-insensitive, non-nesting, rejects attributes, and terminates at [/code].
    - [b], [i] enforce balanced opening/closing with no attributes.
    - Semantic tags enforce per-tag argument grammar and cannot be closed.
    """
    errors: List[str] = []
    param_names: List[str] = []
    found_tags: List[str] = []
    idx = 0
    length = len(text)
    tag_stack: List[str] = []

    while idx < length:
        # Check for malformed [code ...] with attributes
        m_code_attr = re.match(r"^\[code\s+[^\]]+\]", text[idx:], re.IGNORECASE)
        if m_code_attr:
            errors.append(f"{location_desc}: Tag '[code]' does not accept attributes.")
            idx += m_code_attr.end()
            continue

        # Valid [code] open tag
        m_code_open = re.match(r"^\[code\]", text[idx:], re.IGNORECASE)
        if m_code_open:
            found_tags.append("code")
            m_close = re.search(r"\[/code\]", text[idx + 6 :], re.IGNORECASE)
            if not m_close:
                errors.append(f"{location_desc}: Unclosed '[code]' block.")
                break

            end_code = (idx + 6) + m_close.start()
            inner_code = text[idx + 6 : end_code]
            if re.search(r"\[code\]", inner_code, re.IGNORECASE):
                errors.append(
                    f"{location_desc}: Nested '[code]' block detected inside code span."
                )

            idx = (idx + 6) + m_close.end()
            continue

        m_code_stray = re.match(r"^\[/code\]", text[idx:], re.IGNORECASE)
        if m_code_stray:
            errors.append(
                f"{location_desc}: Stray closing '[/code]' without preceding open '[code]'."
            )
            idx += m_code_stray.end()
            continue

        match = RE_TOKEN_TAG.match(text, idx)
        if not match:
            idx += 1
            continue

        raw_tag = match.group(0)
        tag_name = match.group(1).lower()
        tag_args = (match.group(2) or "").strip()
        idx = match.end()

        if tag_name == "codeblock":
            errors.append(
                f"{location_desc}: Unsupported project BBCode tag '[codeblock]'. Only inline [code] is permitted."
            )
            continue

        if tag_name.startswith("/"):
            base_tag = tag_name[1:]
            if tag_args:
                errors.append(
                    f"{location_desc}: Closing tag '[{tag_name}]' cannot contain arguments."
                )
                continue
            if base_tag not in FORMATTING_TAGS:
                errors.append(
                    f"{location_desc}: Unsupported or non-closeable tag '[{tag_name}]'."
                )
                continue
            if not tag_stack or tag_stack[-1] != base_tag:
                expected = f"[/{tag_stack[-1]}]" if tag_stack else "no open tags"
                errors.append(
                    f"{location_desc}: Mismatched closing tag '{raw_tag}', expected '{expected}'."
                )
                continue
            tag_stack.pop()
            continue

        if tag_name in FORMATTING_TAGS:
            found_tags.append(tag_name)
            if tag_args:
                errors.append(
                    f"{location_desc}: Formatting tag '[{tag_name}]' cannot take attributes."
                )
                continue
            tag_stack.append(tag_name)
            continue

        if tag_name in SEMANTIC_TAG_RULES:
            found_tags.append(tag_name)
            rule = SEMANTIC_TAG_RULES[tag_name]
            if not tag_args:
                errors.append(
                    f"{location_desc}: Semantic tag '[{tag_name}]' requires a target identifier argument."
                )
            elif not rule.match(tag_args):
                errors.append(
                    f"{location_desc}: Argument '{tag_args}' in '[{tag_name}]' violates {tag_name} grammar."
                )
            else:
                if tag_name == "param":
                    param_names.append(tag_args)
            continue

        errors.append(
            f"{location_desc}: Unapproved or malformed BBCode tag '{raw_tag}'."
        )

    while tag_stack:
        unclosed = tag_stack.pop()
        errors.append(
            f"{location_desc}: Unclosed formatting tag '[{unclosed}]' at end of documentation."
        )

    return DocumentationPayload(errors=errors, param_names=param_names, tags=found_tags)


def validate_docstring_text(text: Optional[str], field_name: str) -> Optional[str]:
    if not text:
        return text
    if RE_BANNED_FENCE.search(text):
        raise ValueError(f"{field_name} contains banned Markdown code fences (```).")
    if RE_DOXYGEN_TAG.search(text):
        raise ValueError(
            f"{field_name} contains banned Doxygen tags (@param/@return/@brief)."
        )

    payload = validate_and_tokenize_bbcode(text, field_name)
    if payload.errors:
        raise ValueError(f"{field_name} BBCode violation: {'; '.join(payload.errors)}")

    return text.strip()


class MemberDoc(BaseModel):
    name: str = Field(description="Exact name of the target public member.")
    summary: str = Field(
        description="Single-line concise description starting with an active verb."
    )
    description: Optional[str] = Field(
        default=None, description="Optional extended details."
    )
    parameters: Optional[Dict[str, str]] = Field(
        default=None,
        description="Key-value mapping of parameter name to description. Keys MUST strictly match parameter identifiers.",
    )
    returns: Optional[str] = Field(
        default=None, description="Optional return value description."
    )

    @field_validator("name", mode="after")
    @classmethod
    def check_name(cls, v: str) -> str:
        if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", v):
            raise ValueError(f"Invalid member name identifier: '{v}'")
        return v

    @field_validator("summary", mode="after")
    @classmethod
    def check_summary(cls, v: str) -> str:
        validated = validate_docstring_text(v, "Summary")
        if not validated or "\n" in validated or "\r" in validated:
            raise ValueError(
                "Summary must be a single non-empty line without line breaks."
            )
        return validated

    @field_validator("description", mode="after")
    @classmethod
    def check_description(cls, v: Optional[str]) -> Optional[str]:
        return validate_docstring_text(v, "Description")

    @field_validator("returns", mode="after")
    @classmethod
    def check_returns(cls, v: Optional[str]) -> Optional[str]:
        validated = validate_docstring_text(v, "Returns")
        if validated and ("\n" in validated or "\r" in validated):
            raise ValueError(
                "Return description must be a single line without line breaks."
            )
        return validated

    @field_validator("parameters", mode="after")
    @classmethod
    def check_params_dict(cls, v: Optional[Dict[str, str]]) -> Optional[Dict[str, str]]:
        if not v:
            return v
        for p_name, p_desc in v.items():
            if not re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", p_name):
                raise ValueError(f"Invalid parameter identifier key: '{p_name}'")
            validated_desc = validate_docstring_text(
                p_desc, f"Parameter description for '{p_name}'"
            )
            if not validated_desc or "\n" in validated_desc or "\r" in validated_desc:
                raise ValueError(
                    f"Parameter description for '{p_name}' must be a non-empty single line without line breaks."
                )
        return v


class FileDocumentationResponse(BaseModel):
    members: List[MemberDoc] = Field(
        description="Documentation entries for all requested members."
    )


# -----------------------------------------------------------------------------
# AST Traversal & Member Extraction
# -----------------------------------------------------------------------------
@dataclass
class MemberDeclaration:
    name: str
    kind: str
    decl_line: int
    insert_line: int
    params: List[str]
    context_snippet: str
    status: DocStatus = DocStatus.MISSING
    existing_doc_lines: List[str] = field(default_factory=list)
    detached_doc_indices: List[int] = field(default_factory=list)


def get_first_token_line(node: Any) -> Optional[int]:
    if isinstance(node, Token):
        return node.line
    if isinstance(node, Tree):
        if hasattr(node, "meta") and hasattr(node.meta, "line"):
            return node.meta.line
        for child in node.children:
            line = get_first_token_line(child)
            if line is not None:
                return line
    return None


def extract_annotation_name(anno_node: Tree) -> Optional[str]:
    for child in anno_node.children:
        if isinstance(child, Token) and child.type == "NAME":
            return str(child.value).lstrip("@")
    return None


def extract_func_name(func_node: Tree) -> Optional[str]:
    """Unwraps static_func_def -> func_def -> func_header to locate the function identifier."""
    target_def = func_node
    if target_def.data == "static_func_def":
        if not target_def.children or not isinstance(target_def.children[0], Tree):
            return None
        target_def = target_def.children[0]

    if not isinstance(target_def, Tree) or target_def.data != "func_def":
        return None

    func_header = None
    for child in target_def.children:
        if isinstance(child, Tree) and child.data == "func_header":
            func_header = child
            break

    if not func_header:
        if target_def.children and isinstance(target_def.children[0], Tree):
            func_header = target_def.children[0]
        else:
            return None

    for child in func_header.children:
        if isinstance(child, Token) and child.type == "NAME":
            return str(child.value)

    return None


def extract_var_name(var_node: Tree) -> Optional[str]:
    for child in var_node.children:
        if isinstance(child, Tree) and child.data == "class_var_name":
            for sub in child.children:
                if isinstance(sub, Token) and sub.type == "NAME":
                    return str(sub.value)
        elif isinstance(child, Token) and child.type == "NAME":
            return str(child.value)
    return None


def extract_signal_name(signal_node: Tree) -> Optional[str]:
    for child in signal_node.children:
        if isinstance(child, Token) and child.type == "NAME":
            return str(child.value)
    return None


def extract_const_name(const_node: Tree) -> Optional[str]:
    for child in const_node.children:
        if isinstance(child, Token) and child.type == "NAME":
            return str(child.value)
    return None


def extract_enum_name(enum_node: Tree) -> Optional[str]:
    for child in enum_node.children:
        if isinstance(child, Tree) and child.data == "enum_name":
            for sub in child.children:
                if isinstance(sub, Token) and sub.type == "NAME":
                    return str(sub.value)
        elif isinstance(child, Token) and child.type == "NAME":
            return str(child.value)
    return None


def extract_parameters_from_ast(func_node: Tree) -> Tuple[List[str], bool]:
    """Extracts parameter identifiers in source order across all GDScript 4 forms."""
    params = []
    param_rules: Set[str] = {
        "func_arg_regular",
        "func_arg_typed",
        "func_arg_inf",
        "func_arg_variadic",
    }

    for subtree in func_node.iter_subtrees():
        if subtree.data == "func_arg_variadic":
            vararg_name = None
            for child in subtree.children:
                if isinstance(child, Token) and child.type == "NAME":
                    vararg_name = str(child.value)
                    break
            if vararg_name:
                params.append(vararg_name)
                continue
            return [], False

        if subtree.data in param_rules:
            param_name = None
            for child in subtree.children:
                if isinstance(child, Token) and child.type == "NAME":
                    param_name = str(child.value)
                    break
            if not param_name:
                return [], False
            params.append(param_name)

    return params, True


def extract_signal_parameters_from_ast(sig_node: Tree) -> List[str]:
    params = []
    signal_arg_rules: Set[str] = {"signal_arg_regular", "signal_arg_typed"}
    for subtree in sig_node.iter_subtrees():
        if subtree.data in signal_arg_rules:
            for child in subtree.children:
                if isinstance(child, Token) and child.type == "NAME":
                    params.append(str(child.value))
                    break
    return params


def get_top_level_statements(ast: Tree) -> List[Any]:
    """Extraction of top-level class body statements with safe fallback for script layouts."""
    if ast.data == "class_body":
        return ast.children
    if ast.data == "start":
        for child in ast.children:
            if isinstance(child, Tree) and child.data == "class_body":
                return child.children
        # Safe fallback for files parsed directly under start (e.g. constant/path scripts)
        return [c for c in ast.children if isinstance(c, Tree)]
    return [c for c in ast.children if isinstance(c, Tree)]


def resolve_declaration_block(
    decl_line: int,
    source_lines: List[str],
    anno_map: Dict[int, List[str]],
) -> Tuple[int, List[str], List[int]]:
    """
    Resolves the contiguous annotation block, insertion anchor, and docstrings.
    Returns: (insert_line, existing_doc_lines, detached_doc_indices)
    """
    curr = decl_line - 1
    contiguous_lines: List[int] = []

    while curr > 0:
        line_str = source_lines[curr - 1].strip()
        if line_str == "":
            break  # Blank line strictly terminates the contiguous block
        if curr in anno_map or line_str.startswith("#"):
            contiguous_lines.append(curr)
            curr -= 1
        else:
            break

    member_annos = [l for l in contiguous_lines if l in anno_map]
    detached_indices: List[int] = []

    if member_annos:
        earliest_anno = min(member_annos)
        for mid in range(earliest_anno + 1, decl_line):
            if RE_DOC_LINE.match(source_lines[mid - 1]):
                detached_indices.append(mid - 1)

        block_top = earliest_anno
        while block_top > 1:
            line_above = source_lines[block_top - 2].strip()
            if line_above.startswith("#") and not RE_DOC_LINE.match(
                source_lines[block_top - 2]
            ):
                block_top -= 1
            else:
                break
        insert_line = block_top
    else:
        insert_line = decl_line

    doc_lines: List[str] = []
    idx = insert_line - 2
    while idx >= 0 and RE_DOC_LINE.match(source_lines[idx]):
        doc_lines.insert(0, source_lines[idx])
        idx -= 1

    return insert_line, doc_lines, detached_indices


def parse_declarations_from_ast(source: str) -> Tuple[List[MemberDeclaration], bool]:
    try:
        ast = gdparser.parse(source, gather_metadata=True)
        statements = get_top_level_statements(ast)
    except Exception as e:
        print(f"[FAIL-CLOSED] GDScript AST parse error: {e}")
        return [], False

    declarations: List[MemberDeclaration] = []
    source_lines = source.splitlines(keepends=True)

    anno_map: Dict[int, List[str]] = {}
    for anno_node in ast.find_data("annotation"):
        line = get_first_token_line(anno_node)
        anno_name = extract_annotation_name(anno_node)
        if line and anno_name:
            anno_map.setdefault(line, []).append(anno_name)

    for node in statements:
        if not isinstance(node, Tree):
            continue

        # 1. Functions (regular and static)
        if node.data in ("func_def", "static_func_def"):
            func_name = extract_func_name(node)
            if not func_name or func_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                return [], False

            params, ok = extract_parameters_from_ast(node)
            insert_line, docs, detached = resolve_declaration_block(
                decl_line, source_lines, anno_map
            )

            decl = MemberDeclaration(
                name=func_name,
                kind="function",
                decl_line=decl_line,
                insert_line=insert_line,
                params=params,
                context_snippet="".join(
                    source_lines[
                        insert_line - 1 : min(len(source_lines), decl_line + 15)
                    ]
                ),
                existing_doc_lines=docs,
                detached_doc_indices=detached,
            )
            if not ok:
                decl.status = DocStatus.AMBIGUOUS
            declarations.append(decl)

        # 2. Exported Variables (@export)
        elif node.data == "class_var_stmt":
            var_name = extract_var_name(node)
            if not var_name or var_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                return [], False

            insert_line, docs, detached = resolve_declaration_block(
                decl_line, source_lines, anno_map
            )

            is_export = False
            for l in range(insert_line, decl_line):
                if l in anno_map:
                    if any(name in PROPERTY_EXPORT_ANNOTATIONS for name in anno_map[l]):
                        is_export = True
                        break

            if not is_export:
                for child in node.children:
                    if isinstance(child, Tree) and child.data == "annotation":
                        child_name = extract_annotation_name(child)
                        if child_name in PROPERTY_EXPORT_ANNOTATIONS:
                            is_export = True

            if not is_export:
                continue

            declarations.append(
                MemberDeclaration(
                    name=var_name,
                    kind="export",
                    decl_line=decl_line,
                    insert_line=insert_line,
                    params=[],
                    context_snippet="".join(source_lines[insert_line - 1 : decl_line]),
                    existing_doc_lines=docs,
                    detached_doc_indices=detached,
                )
            )

        # 3. Signals
        elif node.data == "signal_stmt":
            sig_name = extract_signal_name(node)
            if not sig_name or sig_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                return [], False

            sig_params = extract_signal_parameters_from_ast(node)
            insert_line, docs, detached = resolve_declaration_block(
                decl_line, source_lines, anno_map
            )

            declarations.append(
                MemberDeclaration(
                    name=sig_name,
                    kind="signal",
                    decl_line=decl_line,
                    insert_line=insert_line,
                    params=sig_params,
                    context_snippet=source_lines[decl_line - 1],
                    existing_doc_lines=docs,
                    detached_doc_indices=detached,
                )
            )

        # 4. Public Constants
        elif node.data == "const_stmt":
            const_name = extract_const_name(node)
            if not const_name or const_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                return [], False

            insert_line, docs, detached = resolve_declaration_block(
                decl_line, source_lines, anno_map
            )

            declarations.append(
                MemberDeclaration(
                    name=const_name,
                    kind="constant",
                    decl_line=decl_line,
                    insert_line=insert_line,
                    params=[],
                    context_snippet=source_lines[decl_line - 1],
                    existing_doc_lines=docs,
                    detached_doc_indices=detached,
                )
            )

        # 5. Public Enums
        elif node.data == "enum_stmt":
            enum_name = extract_enum_name(node)
            if not enum_name or enum_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                return [], False

            insert_line, docs, detached = resolve_declaration_block(
                decl_line, source_lines, anno_map
            )

            declarations.append(
                MemberDeclaration(
                    name=enum_name,
                    kind="enum",
                    decl_line=decl_line,
                    insert_line=insert_line,
                    params=[],
                    context_snippet=source_lines[decl_line - 1],
                    existing_doc_lines=docs,
                    detached_doc_indices=detached,
                )
            )

    return declarations, True


# -----------------------------------------------------------------------------
# Classification Engine
# -----------------------------------------------------------------------------
def classify_member(decl: MemberDeclaration) -> None:
    """Classifies a member into COMPLIANT, MISSING, NON_COMPLIANT, or AMBIGUOUS."""
    if decl.status == DocStatus.AMBIGUOUS:
        return

    if decl.detached_doc_indices:
        decl.status = DocStatus.AMBIGUOUS
        return

    if not decl.existing_doc_lines:
        decl.status = DocStatus.MISSING
        return

    raw_payload = normalize_doc_payload(decl.existing_doc_lines)
    payload = validate_and_tokenize_bbcode(raw_payload, f"Docstring for '{decl.name}'")
    if payload.errors:
        decl.status = DocStatus.NON_COMPLIANT
        return

    if len(payload.param_names) != len(set(payload.param_names)):
        decl.status = DocStatus.NON_COMPLIANT
        return

    if set(payload.param_names) != set(decl.params):
        decl.status = DocStatus.NON_COMPLIANT
        return

    decl.status = DocStatus.COMPLIANT


# -----------------------------------------------------------------------------
# Formatting & Invariants
# -----------------------------------------------------------------------------


def format_doc_lines(doc: MemberDoc, decl: MemberDeclaration, indent: str) -> List[str]:
    max_width = 95  # Strict margin under gdlint's 100 character limit
    prefix = f"{indent}## "
    subsequent_prefix = f"{indent}## "

    lines: List[str] = []

    # 1. Summary
    wrapped_summary = textwrap.wrap(
        doc.summary.strip(),
        width=max_width,
        initial_indent=prefix,
        subsequent_indent=subsequent_prefix,
    )
    for line in wrapped_summary:
        lines.append(f"{line}\n")

    # 2. Extended Description
    if doc.description and doc.description.strip():
        lines.append(f"{indent}##\n")
        for para in doc.description.strip().splitlines():
            if not para.strip():
                lines.append(f"{indent}##\n")
                continue
            wrapped_desc = textwrap.wrap(
                para.strip(),
                width=max_width,
                initial_indent=prefix,
                subsequent_indent=subsequent_prefix,
            )
            for line in wrapped_desc:
                lines.append(f"{line}\n")

    # 3. Parameters
    if doc.parameters and decl.kind in ("function", "signal"):
        lines.append(f"{indent}##\n")
        for p_name in decl.params:
            if p_name in doc.parameters:
                p_desc = doc.parameters[p_name].strip()
                param_prefix = f"{indent}## [param {p_name}]: "
                wrapped_param = textwrap.wrap(
                    p_desc,
                    width=max_width,
                    initial_indent=param_prefix,
                    subsequent_indent=subsequent_prefix,
                )
                for line in wrapped_param:
                    lines.append(f"{line}\n")

    # 4. Returns
    if doc.returns and doc.returns.strip() and decl.kind == "function":
        ret_desc = doc.returns.strip()
        ret_prefix = f"{indent}## Returns "
        wrapped_ret = textwrap.wrap(
            ret_desc,
            width=max_width,
            initial_indent=ret_prefix,
            subsequent_indent=subsequent_prefix,
        )
        for line in wrapped_ret:
            lines.append(f"{line}\n")

    return lines


def compute_non_doc_bytes_sha256(source: str) -> str:
    """Computes exact SHA-256 over non-documentation UTF-8 byte stream."""
    raw_lines = source.splitlines(keepends=True)
    non_doc_bytes = b"".join(
        line.encode("utf-8") for line in raw_lines if not RE_DOC_LINE.match(line)
    )
    return hashlib.sha256(non_doc_bytes).hexdigest()


def verify_modification_allowlist(original: str, proposed: str) -> bool:
    """Rejects any modifications or deletions to lines that do not match RE_DOC_LINE."""
    diff = difflib.ndiff(
        original.splitlines(keepends=True), proposed.splitlines(keepends=True)
    )
    for line in diff:
        code = line[0]
        content = line[2:]
        if code in ("+", "-") and not RE_DOC_LINE.match(content):
            return False
    return True


# -----------------------------------------------------------------------------
# Gemini Query
# -----------------------------------------------------------------------------


def query_gemini_for_docs(
    client: genai.Client, file_path: Path, targets: List[MemberDeclaration]
) -> Dict[str, MemberDoc]:
    import time

    target_names = [t.name for t in targets]
    if len(target_names) != len(set(target_names)):
        print(
            f"[FAIL-CLOSED] Duplicate target member names in {file_path.name}: {target_names}",
            flush=True,
        )
        sys.exit(1)

    target_by_name = {t.name: t for t in targets}
    doc_map = {}

    chunk_size = 1  # Process in safe batches to prevent JSON truncation
    total_chunks = (len(targets) + chunk_size - 1) // chunk_size

    for i in range(0, len(targets), chunk_size):
        chunk_targets = targets[i : i + chunk_size]
        current_chunk = (i // chunk_size) + 1
        chunk_names = [t.name for t in chunk_targets]

        print(
            f"[DEBUG] Generating docs for chunk {current_chunk}/{total_chunks} (Targets: {chunk_names})...",
            flush=True,
        )

        manifest = [
            {
                "name": t.name,
                "kind": t.kind,
                "required_parameters": t.params,
                "existing_developer_comments": "".join(
                    t.existing_doc_lines).strip() if t.existing_doc_lines else "None",
                "code_context": t.context_snippet.strip(),
            }
            for t in chunk_targets
        ]

        prompt = (
            f"You are an automated GDScript documentation assistant for Godot 4.\n"
            f"File: {file_path.name} (Batch {current_chunk})\n\n"
            f"Target declarations needing documentation:\n{json.dumps(manifest, indent=2)}\n\n"
            "Requirements:\n"
            "1. Supply documentation for EVERY target member in the manifest chunk.\n"
            "2. Return only requested member names. Do not invent members.\n"
            "3. If 'required_parameters' is non-empty, the 'parameters' field MUST be a dictionary mapping each exact parameter name to a detailed description.\n"
            "4. BBCode allowed: [param], [constant], [member], [method], [signal], [enum], [code], [b], [i].\n"
            "5. Strictly NO Markdown code blocks (```) or Doxygen (@param/@return/@brief) tags.\n"
            "6. CRITICAL: Do NOT use [param] inside 'summary' or 'description'. Parameter documentation belongs exclusively in the 'parameters' dictionary.\n"
            "7. CRITICAL: Do NOT wrap types or Godot classes in brackets (e.g. NEVER use [bool], [int], [String], [FileAccess], [Node]). Use [code]TypeName[/code] if mentioning a type.\n"
            "8. Keep descriptions concise and under 80 characters where possible.\n"
            "9. CRITICAL CONTEXT PRESERVATION: If 'existing_developer_comments' is provided, you MUST preserve its specific technical details, warnings, return behaviors, and explanations in your new summary, description, and parameter fields. Do not invent logic that contradicts the provided code or comments.\n"
            "10. RETURN VALUES: If the existing comments describe a return type or return behavior (e.g., ':rtype: void' or returning a specific Dictionary), you MUST extract that information and document it accurately in the 'returns' field."
        )

        max_retries = 3
        retry_delay = 35  # Increased to clear 429 quota exhaustion windows (often ~30s)
        validated = None

        for attempt in range(max_retries):
            try:
                response = client.models.generate_content(
                    model=PINNED_MODEL,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        response_schema=FileDocumentationResponse,
                        temperature=0.0,
                    ),
                )
                validated = FileDocumentationResponse.model_validate_json(response.text)
                print(
                    f"[DEBUG] API response received successfully for chunk {current_chunk}/{total_chunks}.",
                    flush=True,
                )
                break
            except Exception as e:
                if attempt == max_retries - 1:
                    print(
                        f"[FAIL-CLOSED] Gemini generation failed for {file_path} (chunk {current_chunk}) after {max_retries} attempts: {e}",
                        flush=True,
                    )
                    sys.exit(1)
                print(
                    f"[WARNING] Gemini API temporary failure (attempt {attempt + 1}/{max_retries}): {e}. Retrying in {retry_delay}s...",
                    flush=True,
                )
                time.sleep(retry_delay)
                retry_delay *= 2  # Exponential backoff

        chunk_requested_names = {t.name for t in chunk_targets}

        # Filter out any unrequested extra members returned by the model
        filtered_members = [
            m for m in validated.members if m.name in chunk_requested_names
        ]
        chunk_returned_names = {m.name for m in filtered_members}

        if chunk_requested_names != chunk_returned_names:
            print(
                f"[FAIL-CLOSED] Set mismatch in {file_path.name} chunk! Expected {chunk_requested_names}, got {chunk_returned_names}",
                flush=True,
            )
            sys.exit(1)

        validated.members = filtered_members

        for m in validated.members:
            target = target_by_name[m.name]

            if target.params:
                m.parameters = m.parameters or {}
                for p_name in target.params:
                    if p_name not in m.parameters:
                        m.parameters[p_name] = f"The {p_name} parameter."

            m_param_set = set(m.parameters.keys()) if m.parameters else set()
            target_param_set = set(target.params) if target.params else set()

            if target.kind in ("function", "signal"):
                unexpected = m_param_set - target_param_set
                if unexpected:
                    print(
                        f"[FAIL-CLOSED] Unexpected parameters returned for {m.name}: {list(unexpected)}",
                        flush=True,
                    )
                    sys.exit(1)
            elif m_param_set:
                print(
                    f"[FAIL-CLOSED] Unexpected parameters returned for non-parameterized member {m.name}: {list(m_param_set)}",
                    flush=True,
                )
                sys.exit(1)

            doc_map[m.name] = m

        # Pacing to avoid hitting the 15 RPM Free Tier Limit for Flash Lite
        if i + chunk_size < len(targets):
            time.sleep(5)

    return doc_map


# -----------------------------------------------------------------------------
# Transaction Management
# -----------------------------------------------------------------------------


@dataclass
class ProposedFileChange:
    file_path: Path
    original_source: str
    proposed_source: str
    slots_count: int


def prepare_file_change(
    client: Optional[genai.Client], file_path: Path, check_mode: bool
) -> Optional[ProposedFileChange]:
    try:
        with open(file_path, "r", encoding="utf-8", newline="") as f:
            original_source = f.read()
    except (OSError, UnicodeError) as e:
        print(f"[FAIL-CLOSED] Unable to read {file_path}: {e}")
        sys.exit(1)

    # Phase 1: Baseline AST Audit
    declarations, ok = parse_declarations_from_ast(original_source)
    if not ok:
        print(f"[FAIL-CLOSED] Baseline AST parse failed for {file_path}.")
        sys.exit(1)

    for decl in declarations:
        classify_member(decl)

    ambiguous = [d for d in declarations if d.status == DocStatus.AMBIGUOUS]
    for amb in ambiguous:
        print(
            f"[SKIPPED: AMBIGUOUS] {file_path.name}: Declaration '{amb.name}' on line {amb.decl_line} is ambiguous."
        )

    actionable = [
        d
        for d in declarations
        if d.status in (DocStatus.MISSING, DocStatus.NON_COMPLIANT)
    ]
    if not actionable:
        return None

    if check_mode:
        return ProposedFileChange(
            file_path, original_source, original_source, len(actionable)
        )

    # Phase 2: Generation & Construction
    if not client:
        print("[FAIL-CLOSED] API client required in write mode.")
        sys.exit(1)

    generated_docs = query_gemini_for_docs(client, file_path, actionable)

    raw_lines = original_source.splitlines(keepends=True)
    new_lines = list(raw_lines)
    for decl in sorted(actionable, key=lambda d: d.insert_line, reverse=True):
        if decl.detached_doc_indices:
            print(
                f"[FAIL-CLOSED] {file_path.name}: Detached docstring detected between annotation and {decl.name}. Aborting."
            )
            sys.exit(1)

        if decl.existing_doc_lines:
            start_remove = decl.insert_line - 1 - len(decl.existing_doc_lines)
            del new_lines[start_remove : decl.insert_line - 1]
            insert_at = start_remove
        else:
            insert_at = decl.insert_line - 1

        decl_line_str = raw_lines[decl.insert_line - 1]
        indent = decl_line_str[: len(decl_line_str) - len(decl_line_str.lstrip())]

        injected = format_doc_lines(generated_docs[decl.name], decl, indent)
        new_lines[insert_at:insert_at] = injected

    proposed_source = "".join(new_lines)

    # Phase 3: Post-Injection Contract Re-Verification
    post_declarations, ok = parse_declarations_from_ast(proposed_source)
    if not ok:
        print(f"[FAIL-CLOSED] Post-injection AST parse failed for {file_path.name}.")
        sys.exit(1)

    if len(post_declarations) != len(declarations):
        print(
            f"[FAIL-CLOSED] Post-injection declaration count mismatch in {file_path.name}: "
            f"expected {len(declarations)}, got {len(post_declarations)}."
        )
        sys.exit(1)

    post_by_key = {(d.kind, d.name): d for d in post_declarations}
    if len(post_by_key) != len(post_declarations):
        print(
            f"[FAIL-CLOSED] Duplicate declarations detected in post-injection AST for {file_path.name}."
        )
        sys.exit(1)

    for orig_decl in actionable:
        key = (orig_decl.kind, orig_decl.name)
        post_decl = post_by_key.get(key)
        if not post_decl:
            print(
                f"[FAIL-CLOSED] Target declaration {key} missing from post-injection AST in {file_path.name}."
            )
            sys.exit(1)

        if post_decl.params != orig_decl.params:
            print(
                f"[FAIL-CLOSED] Target declaration {orig_decl.name} signature mutated during injection in {file_path.name}!"
            )
            sys.exit(1)

        classify_member(post_decl)
        if post_decl.status != DocStatus.COMPLIANT:
            raw_payload = normalize_doc_payload(post_decl.existing_doc_lines)
            payload = validate_and_tokenize_bbcode(
                raw_payload, f"Docstring for '{post_decl.name}'"
            )
            print(
                f"[FAIL-CLOSED] Target declaration {orig_decl.name} failed post-injection compliance in {file_path.name} "
                f"(status: {post_decl.status.value}).",
                flush=True,
            )
            print(f"[DEBUG] Raw payload:\n{raw_payload}", flush=True)
            if payload.errors:
                print(f"[DEBUG] BBCode errors: {payload.errors}", flush=True)
            if len(payload.param_names) != len(set(payload.param_names)):
                print(
                    f"[DEBUG] Duplicate params found: {payload.param_names}", flush=True
                )
            if set(payload.param_names) != set(orig_decl.params):
                print(
                    f"[DEBUG] Param mismatch: Expected {set(orig_decl.params)}, got {set(payload.param_names)}",
                    flush=True,
                )
            sys.exit(1)

    # Phase 4: Byte Integrity & Modification Allowlist Guards
    orig_fp = compute_non_doc_bytes_sha256(original_source)
    prop_fp = compute_non_doc_bytes_sha256(proposed_source)
    if orig_fp != prop_fp:
        print(f"[FAIL-CLOSED] Source integrity mismatch in {file_path}!")
        sys.exit(1)

    if not verify_modification_allowlist(original_source, proposed_source):
        print(f"[FAIL-CLOSED] Non-documentation lines modified in {file_path}!")
        sys.exit(1)

    return ProposedFileChange(
        file_path, original_source, proposed_source, len(actionable)
    )


def atomic_commit_all_changes(changes: List[ProposedFileChange]) -> None:
    """Staged file replacement with rollback-protected restoration on failure."""
    backups: Dict[Path, Path] = {}
    staged_files: List[Tuple[Path, Path]] = []

    try:
        for change in changes:
            tmp_path = change.file_path.with_suffix(".tmp_doc")
            backup_path = change.file_path.with_suffix(".bak_doc")

            if tmp_path.is_symlink() or tmp_path.exists():
                print(
                    f"[FAIL-CLOSED] Collision or symlink rejected at staging path: {tmp_path}"
                )
                sys.exit(1)
            if backup_path.is_symlink() or backup_path.exists():
                print(
                    f"[FAIL-CLOSED] Collision or symlink rejected at backup path: {backup_path}"
                )
                sys.exit(1)

            with open(tmp_path, "x", encoding="utf-8", newline="") as f:
                f.write(change.proposed_source)
                f.flush()
                os.fsync(f.fileno())

            shutil.copy2(change.file_path, backup_path, follow_symlinks=False)
            backups[change.file_path] = backup_path
            staged_files.append((tmp_path, change.file_path))

        for tmp_path, dest_path in staged_files:
            tmp_path.replace(dest_path)
            print(f"[COMMITTED] Successfully updated: {dest_path}")

        for bak in backups.values():
            if bak.exists():
                bak.unlink()

    except Exception as e:
        print(f"[FAIL-CLOSED] Write failure during commit: {e}. Executing rollback...")
        for dest_path, bak in backups.items():
            if bak.exists():
                bak.replace(dest_path)
        for tmp_path, _ in staged_files:
            if tmp_path.exists():
                tmp_path.unlink()
        sys.exit(1)


# -----------------------------------------------------------------------------
# Main CLI
# -----------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="GDScript Documentation Auditor & Transactional Injector"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--audit",
        action="store_true",
        help="Non-mutating full-inventory scan. Always exits 0 if scanner succeeds.",
    )
    group.add_argument(
        "--check",
        action="store_true",
        help="Non-mutating strict compliance check. Exits 0 if fully documented, 1 if gaps exist.",
    )
    group.add_argument(
        "--write",
        action="store_true",
        help="Generate and inject missing/non-compliant docstrings.",
    )
    args = parser.parse_args()

    client = None
    if args.write:
        api_key = os.environ.get("GEMINI_API_KEY")
        if not api_key:
            print("[FAIL-CLOSED] Missing GEMINI_API_KEY environment variable.")
            sys.exit(1)
        client = genai.Client(api_key=api_key)

    raw_scripts_root = Path("scripts")
    if raw_scripts_root.is_symlink():
        print("[FAIL-CLOSED] 'scripts/' must not be a symlink.")
        sys.exit(1)

    scripts_root = raw_scripts_root.resolve()
    if not scripts_root.exists():
        print("[FAIL-CLOSED] 'scripts/' directory not found.")
        sys.exit(1)

    total_files_scanned = 0
    total_declarations = 0
    status_counts = {
        DocStatus.COMPLIANT: 0,
        DocStatus.MISSING: 0,
        DocStatus.NON_COMPLIANT: 0,
        DocStatus.AMBIGUOUS: 0,
    }
    actionable_files: List[Tuple[Path, int]] = []

    for subdir_name in ALLOWED_SUBDIRS:
        raw_target = scripts_root / subdir_name
        if not raw_target.exists():
            continue

        if raw_target.is_symlink():
            print(f"[FAIL-CLOSED] Symlink directory rejected: {raw_target}")
            sys.exit(1)

        target_dir = raw_target.resolve()
        if not target_dir.is_relative_to(scripts_root):
            print(f"[FAIL-CLOSED] Approved directory {raw_target} escapes root.")
            sys.exit(1)

        for file_path in sorted(target_dir.rglob("*.gd")):
            if file_path.is_symlink():
                print(f"[FAIL-CLOSED] Symlink file rejected: {file_path}")
                sys.exit(1)

            resolved = file_path.resolve()
            if not resolved.is_relative_to(scripts_root):
                print(f"[FAIL-CLOSED] Invalid file path rejected: {file_path}")
                sys.exit(1)

            try:
                with open(resolved, "r", encoding="utf-8", newline="") as f:
                    content = f.read()
            except (OSError, UnicodeError) as e:
                print(f"[FAIL-CLOSED] Unable to read {resolved}: {e}")
                sys.exit(1)

            decls, ok = parse_declarations_from_ast(content)
            if not ok:
                print(f"[FAIL-CLOSED] AST parse failed for {resolved.name}.")
                sys.exit(1)

            total_files_scanned += 1
            file_actionable_slots = 0

            for decl in decls:
                total_declarations += 1
                classify_member(decl)
                status_counts[decl.status] += 1
                if decl.status in (DocStatus.MISSING, DocStatus.NON_COMPLIANT):
                    file_actionable_slots += 1

            if file_actionable_slots > 0:
                actionable_files.append((resolved, file_actionable_slots))

    total_actionable_slots = (
        status_counts[DocStatus.MISSING] + status_counts[DocStatus.NON_COMPLIANT]
    )

    if args.audit:
        print(
            f"\n[AUDIT COMPLETE] GDScript Documentation Contract v{DOCUMENTATION_CONTRACT_VERSION}"
        )
        print(f"  Production files scanned: {total_files_scanned}")
        print(f"  Public members audited:   {total_declarations}")
        print(f"  - COMPLIANT:              {status_counts[DocStatus.COMPLIANT]}")
        print(f"  - MISSING:                {status_counts[DocStatus.MISSING]}")
        print(f"  - NON_COMPLIANT:          {status_counts[DocStatus.NON_COMPLIANT]}")
        print(f"  - AMBIGUOUS:              {status_counts[DocStatus.AMBIGUOUS]}")
        print(f"  Actionable files:         {len(actionable_files)}")
        print(f"  Actionable slots:         {total_actionable_slots}")
        sys.exit(0)

    if args.check:
        if total_actionable_slots > 0 or status_counts[DocStatus.AMBIGUOUS] > 0:
            print(
                f"[CHECK FAILED] Documentation violations exist: {total_actionable_slots} actionable slot(s), "
                f"{status_counts[DocStatus.AMBIGUOUS]} ambiguous declaration(s) across {len(actionable_files)} file(s)."
            )
            sys.exit(1)
        print(
            f"[CHECK PASSED] All {total_declarations} public members in {total_files_scanned} files "
            f"are compliant with contract v{DOCUMENTATION_CONTRACT_VERSION}."
        )
        sys.exit(0)

    if args.write:
        if len(actionable_files) == 0:
            print(
                "[INFO] No actionable docstring slots found. Repository is up-to-date."
            )
            sys.exit(0)

        if total_actionable_slots > MAX_DOC_SLOTS_MODIFIED_PER_RUN:
            print(
                f"[FAIL-CLOSED] Actionable slots ({total_actionable_slots}) exceeded limit "
                f"({MAX_DOC_SLOTS_MODIFIED_PER_RUN}). Aborting."
            )
            sys.exit(1)

        target_file, slots = actionable_files[0]
        print(
            f"[WRITE BATCH] Processing 1 file out of {len(actionable_files)} actionable: {target_file.name} ({slots} slot(s))"
        )

        change = prepare_file_change(client, target_file, check_mode=False)
        if change:
            atomic_commit_all_changes([change])


if __name__ == "__main__":
    main()
