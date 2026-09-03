#!/usr/bin/env python3
"""
Deterministic GDScript Documentation Auditor and Transactional Injector.

Implements all issue #915 invariants:
- AST parsing via gdtoolkit.
- Operational 4-state classification (COMPLIANT, MISSING, NON_COMPLIANT, AMBIGUOUS).
- Strict BBCode tag allowlist and comprehensive text validation.
- Non-comment byte-for-byte SHA-256 integrity verification.
- Two-phase transaction with atomic rename and filesystem rollback.
"""

import argparse
import difflib
import enum
import hashlib
import json
import os
import re
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

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
MAX_FILES_MODIFIED_PER_RUN = 15
MAX_DOC_SLOTS_MODIFIED_PER_RUN = 50
PINNED_MODEL = "gemini-2.5-flash"
ALLOWED_SUBDIRS = ("core", "entities", "managers", "resources", "system", "ui")

RE_DOC_LINE = re.compile(r"^[ \t]*##(?:\s.*)?$")
RE_PARAM_TAG = re.compile(r"\[param\s+([a-zA-Z0-9_]+)\]", re.IGNORECASE)
RE_BANNED_FENCE = re.compile(r"```")
RE_DOXYGEN_TAG = re.compile(r"@(param|return|brief)")
RE_CODE_BLOCK = re.compile(r"\[code\].*?\[/code\]", re.DOTALL | re.IGNORECASE)

# Strict allowlist of Godot 4 documentation BBCode base tags
ALLOWED_BASE_TAGS = {
    "param",
    "code",
    "constant",
    "member",
    "method",
    "signal",
    "enum",
    "b",
    "i",
}
RE_BBCODE_TAG = re.compile(r"\[/?([a-zA-Z0-9_]+)(?:\s+[^\]]+)?\]")


class DocStatus(enum.Enum):
    COMPLIANT = "COMPLIANT"
    MISSING = "MISSING"
    NON_COMPLIANT = "NON_COMPLIANT"
    AMBIGUOUS = "AMBIGUOUS"


# -----------------------------------------------------------------------------
# Text Validation Helper & Pydantic Schema
# -----------------------------------------------------------------------------
def validate_docstring_text(text: Optional[str], field_name: str) -> Optional[str]:
    """Validates that text contains no code fences, Doxygen tags, or unapproved BBCode."""
    if not text:
        return text
    if RE_BANNED_FENCE.search(text):
        raise ValueError(f"{field_name} contains banned Markdown code fences (```).")
    if RE_DOXYGEN_TAG.search(text):
        raise ValueError(f"{field_name} contains banned Doxygen tags (@param/@return).")

    # Exclude [code]...[/code] content so bracketed syntax like Array[Node] isn't misidentified as tags
    text_without_code = RE_CODE_BLOCK.sub("", text)

    # Verify that all BBCode tags outside code blocks are in the allowlist
    found_tags = RE_BBCODE_TAG.findall(text_without_code)
    for tag in found_tags:
        if tag.lower() not in ALLOWED_BASE_TAGS:
            raise ValueError(f"{field_name} contains unapproved BBCode tag '[{tag}]'.")
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
            validate_docstring_text(p_name, f"Parameter key '{p_name}'")
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
    kind: str  # function, signal, export, const, enum
    decl_line: int  # 1-based start line of the declaration keyword (func, var, etc.)
    insert_line: (
        int  # 1-based line where documentation MUST be placed (above annotations)
    )
    params: List[str]
    context_snippet: str
    status: DocStatus = DocStatus.MISSING
    existing_doc_lines: List[str] = field(default_factory=list)
    detached_doc_indices: List[int] = field(default_factory=list)  # 0-based indices


def extract_parameters_from_ast(func_node: Tree) -> Tuple[List[str], bool]:
    """Robustly extracts parameter identifiers from all GDScript 4 parameter forms."""
    params = []
    # GDToolkit 4.5.0 parameter rule names
    arg_rules = (
        "func_arg_regular",
        "func_arg_typed",
        "func_arg_default",
        "func_arg_inf",
    )
    for rule in arg_rules:
        for arg_node in func_node.find_data(rule):
            param_name = None
            for child in arg_node.children:
                if isinstance(child, Token) and child.type == "NAME":
                    param_name = str(child.value)
                    break
            if not param_name:
                return [], False
            params.append(param_name)

    # Support variadic functions
    for _ in func_node.find_data("func_arg_variadic"):
        # Flag as ambiguous if vararg requires complex tagging
        return [], False

    return params, True


def extract_signal_parameters_from_ast(sig_node: Tree) -> List[str]:
    params = []
    for arg_node in sig_node.find_data("signal_arg_regular"):
        for child in arg_node.children:
            if isinstance(child, Token) and child.type == "NAME":
                params.append(str(child.value))
                break
    return params


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


def get_first_annotation_line(node: Tree) -> Optional[int]:
    """Finds line of the first annotation preceding a declaration."""
    first_line = None
    for child in node.children:
        if isinstance(child, Tree) and child.data == "annotation":
            line = get_first_token_line(child)
            if line and (first_line is None or line < first_line):
                first_line = line
    return first_line


def parse_declarations_from_ast(source: str) -> Tuple[List[MemberDeclaration], bool]:
    try:
        ast = gdparser.parse(source)
    except Exception as e:
        print(f"[FAIL-CLOSED] GDScript AST parse error: {e}")
        return [], False

    declarations: List[MemberDeclaration] = []
    source_lines = source.splitlines(keepends=True)

    # Collect all annotations with their start lines
    # gdtoolkit represents annotations as Tree nodes with data == "annotation"
    annotations: List[Tuple[int, str]] = []
    for anno_node in ast.find_data("annotation"):
        line = get_first_token_line(anno_node)
        if line:
            # Extract annotation text, e.g. "@export" or "@rpc"
            anno_text = "".join(
                str(t.value)
                for t in anno_node.scan_values(lambda v: isinstance(v, Token))
            )
            annotations.append((line, anno_text))

    def find_associated_annotation_line(target_line: int) -> Optional[int]:
        """Finds the earliest consecutive annotation preceding target_line."""
        # Search backwards from target_line
        curr = target_line - 1
        earliest_line = None
        anno_map = {l: txt for l, txt in annotations}

        while curr > 0:
            line_str = source_lines[curr - 1].strip()
            # If empty line or comment, docstrings/annotations could span, but consecutive annotations are directly adjacent
            if curr in anno_map:
                earliest_line = curr
                curr -= 1
            elif line_str.startswith("#"):
                curr -= 1
            else:
                break
        return earliest_line

    # 1. Functions
    for node in ast.find_data("func_def"):
        func_name = None
        for child in node.children:
            if isinstance(child, Token) and child.type == "NAME":
                func_name = str(child.value)
                break

        if not func_name or func_name.startswith("_"):
            continue

        params, ok = extract_parameters_from_ast(node)
        decl_line = get_first_token_line(node)
        if not decl_line:
            return [], False

        anno_line = find_associated_annotation_line(decl_line)
        insert_line = anno_line if anno_line else decl_line

        decl = MemberDeclaration(
            name=func_name,
            kind="function",
            decl_line=decl_line,
            insert_line=insert_line,
            params=params,
            context_snippet="".join(
                source_lines[insert_line - 1 : min(len(source_lines), decl_line + 15)]
            ),
        )
        if not ok:
            decl.status = DocStatus.AMBIGUOUS
        declarations.append(decl)

    # 2. Exported Variables (@export)
    for node in ast.find_data("class_var_stmt"):
        var_name = None
        for child in node.children:
            if isinstance(child, Token) and child.type == "NAME":
                var_name = str(child.value)
                break

        if not var_name or var_name.startswith("_"):
            continue

        decl_line = get_first_token_line(node)
        if not decl_line:
            return [], False

        # Look for preceding annotations (e.g. @export, @export_range)
        anno_line = find_associated_annotation_line(decl_line)

        # Verify if any associated annotation is an @export variant
        is_export = False
        if anno_line:
            for l, txt in annotations:
                if anno_line <= l < decl_line and txt.startswith("@export"):
                    is_export = True
                    break

        if not is_export:
            # Also check child annotations if gdtoolkit nested them
            for child in node.children:
                if isinstance(child, Tree) and child.data == "annotation":
                    for t in child.scan_values(lambda v: isinstance(v, Token)):
                        if t.value.startswith("@export"):
                            is_export = True

        if not is_export:
            continue

        insert_line = anno_line if anno_line else decl_line
        declarations.append(
            MemberDeclaration(
                name=var_name,
                kind="export",
                decl_line=decl_line,
                insert_line=insert_line,
                params=[],
                context_snippet="".join(source_lines[insert_line - 1 : decl_line]),
            )
        )

    # 3. Signals
    for node in ast.find_data("signal_stmt"):
        sig_name = None
        for child in node.children:
            if isinstance(child, Token) and child.type == "NAME":
                sig_name = str(child.value)
                break
        if not sig_name or sig_name.startswith("_"):
            continue

        decl_line = get_first_token_line(node)
        if not decl_line:
            return [], False

        anno_line = find_associated_annotation_line(decl_line)
        insert_line = anno_line if anno_line else decl_line
        sig_params = extract_signal_parameters_from_ast(node)
        declarations.append(
            MemberDeclaration(
                name=sig_name,
                kind="signal",
                decl_line=decl_line,
                insert_line=insert_line,
                params=sig_params,
                context_snippet=source_lines[decl_line - 1],
            )
        )

    # 4. Public Constants
    for node in ast.find_data("const_stmt"):
        const_name = None
        for child in node.children:
            if isinstance(child, Token) and child.type == "NAME":
                const_name = str(child.value)
                break
        if not const_name or const_name.startswith("_"):
            continue

        decl_line = get_first_token_line(node)
        if not decl_line:
            return [], False

        anno_line = find_associated_annotation_line(decl_line)
        insert_line = anno_line if anno_line else decl_line
        declarations.append(
            MemberDeclaration(
                name=const_name,
                kind="constant",
                decl_line=decl_line,
                insert_line=insert_line,
                params=[],
                context_snippet=source_lines[decl_line - 1],
            )
        )

    # 5. Public Enums
    for node in ast.find_data("enum_stmt"):
        enum_name = None
        for child in node.children:
            if isinstance(child, Token) and child.type == "NAME":
                enum_name = str(child.value)
                break
        if not enum_name or enum_name.startswith("_"):
            continue

        decl_line = get_first_token_line(node)
        if not decl_line:
            return [], False

        anno_line = find_associated_annotation_line(decl_line)
        insert_line = anno_line if anno_line else decl_line
        declarations.append(
            MemberDeclaration(
                name=enum_name,
                kind="enum",
                decl_line=decl_line,
                insert_line=insert_line,
                params=[],
                context_snippet=source_lines[decl_line - 1],
            )
        )

    return declarations, True


# -----------------------------------------------------------------------------
# Classification Engine
# -----------------------------------------------------------------------------
def classify_member(decl: MemberDeclaration, raw_lines: List[str]) -> None:
    """Classifies a member into COMPLIANT, MISSING, NON_COMPLIANT, or AMBIGUOUS."""
    if decl.status == DocStatus.AMBIGUOUS:
        return

    doc_lines = []
    idx = decl.insert_line - 2  # Line immediately preceding annotations/declaration

    while idx >= 0:
        curr = raw_lines[idx]
        if RE_DOC_LINE.match(curr):
            doc_lines.insert(0, curr)
            idx -= 1
        else:
            break

    decl.existing_doc_lines = doc_lines

    # Detached Docstring Guard: Check if ## appears between annotations and decl
    if decl.insert_line != decl.decl_line:
        for mid_idx in range(decl.insert_line - 1, decl.decl_line - 1):
            if RE_DOC_LINE.match(raw_lines[mid_idx]):
                decl.detached_doc_indices.append(mid_idx)
                decl.status = DocStatus.NON_COMPLIANT

        if decl.detached_doc_indices:
            return

    if not doc_lines:
        decl.status = DocStatus.MISSING
        return

    combined_docs = "".join(doc_lines)

    # Check banned tags or fences
    if RE_BANNED_FENCE.search(combined_docs) or RE_DOXYGEN_TAG.search(combined_docs):
        decl.status = DocStatus.NON_COMPLIANT
        return

    # Check unapproved BBCode tags (excluding contents within [code]...[/code])
    docs_without_code = RE_CODE_BLOCK.sub("", combined_docs)
    found_tags = RE_BBCODE_TAG.findall(docs_without_code)
    for tag in found_tags:
        if tag.lower() not in ALLOWED_BASE_TAGS:
            decl.status = DocStatus.NON_COMPLIANT
            return

    # Check parameter referencing
    if decl.kind in ("function", "signal"):
        tags = RE_PARAM_TAG.findall(combined_docs)
        for t in tags:
            if t not in decl.params:
                decl.status = DocStatus.NON_COMPLIANT
                return

    decl.status = DocStatus.COMPLIANT


# -----------------------------------------------------------------------------
# Formatting & Invariants
# -----------------------------------------------------------------------------
def format_doc_lines(doc: MemberDoc, decl: MemberDeclaration, indent: str) -> List[str]:
    lines = [f"{indent}## {doc.summary}\n"]

    if doc.description and doc.description.strip():
        lines.append(f"{indent}##\n")
        for line in doc.description.strip().splitlines():
            lines.append(f"{indent}## {line.strip()}\n")

    if doc.parameters and decl.kind in ("function", "signal"):
        lines.append(f"{indent}##\n")
        for p_name, p_desc in doc.parameters.items():
            desc_lines = p_desc.strip().splitlines()
            lines.append(f"{indent}## [param {p_name}]: {desc_lines[0].strip()}\n")
            for cont in desc_lines[1:]:
                lines.append(f"{indent}##     {cont.strip()}\n")

    if doc.returns and doc.returns.strip() and decl.kind == "function":
        ret_lines = doc.returns.strip().splitlines()
        lines.append(f"{indent}## Returns {ret_lines[0].strip()}\n")
        for cont in ret_lines[1:]:
            lines.append(f"{indent}##     {cont.strip()}\n")

    return lines


def compute_non_doc_bytes_sha256(source: str) -> str:
    """Computes exact SHA-256 over all bytes excluding recognized '##' lines."""
    raw_lines = source.splitlines(keepends=True)
    non_doc = "".join([line for line in raw_lines if not RE_DOC_LINE.match(line)])
    return hashlib.sha256(non_doc.encode("utf-8")).hexdigest()


def verify_modification_allowlist(original: str, proposed: str) -> bool:
    diff = difflib.ndiff(
        original.splitlines(keepends=True), proposed.splitlines(keepends=True)
    )
    for line in diff:
        code = line[0]
        content = line[2:]
        if code in ("+", "-"):
            if not RE_DOC_LINE.match(content) and content.strip():
                return False
    return True


# -----------------------------------------------------------------------------
# Gemini Query
# -----------------------------------------------------------------------------
def query_gemini_for_docs(
    client: genai.Client, file_path: Path, targets: List[MemberDeclaration]
) -> Dict[str, MemberDoc]:
    manifest = [
        {
            "name": t.name,
            "kind": t.kind,
            "parameters": t.params,
            "context": t.context_snippet.strip(),
        }
        for t in targets
    ]

    prompt = (
        f"You are an automated GDScript documentation assistant for Godot 4.\n"
        f"File: {file_path.name}\n\n"
        f"Target declarations needing documentation:\n{json.dumps(manifest, indent=2)}\n\n"
        "Requirements:\n"
        "1. Supply documentation for EVERY target member in the manifest.\n"
        "2. Return only requested member names. Do not invent members.\n"
        "3. In 'parameters', use ONLY parameter names present in the declaration.\n"
        "4. BBCode allowed: [param], [code], [constant], [member], [method], [signal], [b], [i].\n"
        "5. Strictly NO Markdown code blocks (```) or Doxygen (@param/@return) tags."
    )

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
    except Exception as e:
        print(f"[FAIL-CLOSED] Gemini generation failed for {file_path}: {e}")
        sys.exit(1)

    requested_names = {t.name for t in targets}
    returned_names = {m.name for m in validated.members}
    if requested_names != returned_names:
        print(
            f"[FAIL-CLOSED] Set mismatch in {file_path}! Expected {requested_names}, got {returned_names}"
        )
        sys.exit(1)

    doc_map = {}
    target_by_name = {t.name: t for t in targets}
    for m in validated.members:
        target = target_by_name[m.name]
        if m.parameters:
            for p in m.parameters:
                if p not in target.params:
                    print(
                        f"[FAIL-CLOSED] Invalid parameter '{p}' returned for {m.name}. Valid: {target.params}"
                    )
                    sys.exit(1)
        doc_map[m.name] = m

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
    with open(file_path, "r", encoding="utf-8", newline="") as f:
        original_source = f.read()

    declarations, ok = parse_declarations_from_ast(original_source)
    if not ok:
        print(f"[FAIL-CLOSED] AST parse failed for {file_path}.")
        sys.exit(1)

    raw_lines = original_source.splitlines(keepends=True)
    for decl in declarations:
        classify_member(decl, raw_lines)

    # Report ambiguous declarations
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

    print(
        f"[{'CHECK' if check_mode else 'PROPOSE'}] {file_path.name}: {len(actionable)} target slot(s)."
    )
    if check_mode:
        return ProposedFileChange(
            file_path, original_source, original_source, len(actionable)
        )

    if not client:
        print("[FAIL-CLOSED] API client required in write mode.")
        sys.exit(1)

    generated_docs = query_gemini_for_docs(client, file_path, actionable)

    # Reverse order insertion to maintain line indices
    new_lines = list(raw_lines)
    for decl in sorted(actionable, key=lambda d: d.insert_line, reverse=True):
        # 1. Clean up any detached comments placed between annotation and declaration
        for stray_idx in sorted(decl.detached_doc_indices, reverse=True):
            del new_lines[stray_idx]

        # 2. Remove compliant/non-compliant comments directly above insert_line
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

    # Invariants
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
    """Atomic filesystem commit with rollback support on failure."""
    backups: Dict[Path, Path] = {}
    staged_files: List[Tuple[Path, Path]] = []

    try:
        for change in changes:
            tmp_path = change.file_path.with_suffix(".tmp_doc")
            backup_path = change.file_path.with_suffix(".bak_doc")

            # CWE-59: Reject pre-existing symlinks or collision paths
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

            # Exclusive creation prevents following newly created symlinks
            with open(tmp_path, "x", encoding="utf-8", newline="") as f:
                f.write(change.proposed_source)
                f.flush()
                os.fsync(f.fileno())

            # Copy to backup ensuring it does not follow a pre-existing link
            shutil.copy2(change.file_path, backup_path, follow_symlinks=False)
            backups[change.file_path] = backup_path
            staged_files.append((tmp_path, change.file_path))

        # Perform atomic renames
        for tmp_path, dest_path in staged_files:
            tmp_path.replace(dest_path)
            print(f"[COMMITTED] Successfully updated: {dest_path}")

        # Cleanup backups upon successful commit
        for bak in backups.values():
            if bak.exists():
                bak.unlink()

    except Exception as e:
        print(f"[FAIL-CLOSED] Write failure during commit: {e}. Executing rollback...")
        for dest_path, bak in backups.items():
            if bak.exists():
                bak.replace(dest_path)
        # Cleanup temporary files
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
    parser.add_argument(
        "--check", action="store_true", help="Dry-run audit without writing changes."
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Generate and inject missing/non-compliant docstrings.",
    )
    args = parser.parse_args()

    if not (args.check ^ args.write):
        print("Error: Specify exactly one mode: --check or --write.")
        sys.exit(1)

    client = None
    if args.write:
        api_key = os.environ.get("GEMINI_API_KEY")
        if not api_key:
            print("[FAIL-CLOSED] Missing GEMINI_API_KEY environment variable.")
            sys.exit(1)
        client = genai.Client(api_key=api_key)

    scripts_root = Path("scripts").resolve()
    if not scripts_root.exists():
        print("[FAIL-CLOSED] 'scripts/' directory not found.")
        sys.exit(1)

    proposed_changes: List[ProposedFileChange] = []
    total_slots = 0

    for subdir_name in ALLOWED_SUBDIRS:
        target_dir = scripts_root / subdir_name
        if not target_dir.exists():
            continue

        for file_path in sorted(target_dir.rglob("*.gd")):
            resolved = file_path.resolve()
            if not resolved.is_relative_to(scripts_root) or file_path.is_symlink():
                print(
                    f"[FAIL-CLOSED] Invalid file path or symlink rejected: {file_path}"
                )
                sys.exit(1)

            change = prepare_file_change(client, resolved, check_mode=args.check)
            if change:
                proposed_changes.append(change)
                total_slots += change.slots_count

    total_files = len(proposed_changes)
    print(
        f"\nPhase 1 Complete: {total_files} file(s) and {total_slots} slot(s) identified."
    )

    if args.write:
        if total_files > MAX_FILES_MODIFIED_PER_RUN:
            print(
                f"[FAIL-CLOSED] Modified files ({total_files}) exceeded threshold ({MAX_FILES_MODIFIED_PER_RUN}). Aborting."
            )
            sys.exit(1)
        if total_slots > MAX_DOC_SLOTS_MODIFIED_PER_RUN:
            print(
                f"[FAIL-CLOSED] Modified slots ({total_slots}) exceeded threshold ({MAX_DOC_SLOTS_MODIFIED_PER_RUN}). Aborting."
            )
            sys.exit(1)

        atomic_commit_all_changes(proposed_changes)

    if args.check and total_files > 0:
        sys.exit(2)


if __name__ == "__main__":
    main()
