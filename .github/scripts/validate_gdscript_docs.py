#!/usr/bin/env python3
"""
Strict GDScript Documentation Contract Validator.

Audits production GDScript files against documentation contract v1.0:
1. Native Godot 4 '##' documentation comments on audited public class-level members:
   - Public functions (regular and static)
   - Exported properties (@export and property-level export variants)
   - Public signals
   - Public constants
   - Public named enums
2. Complete parameter contract: every signature parameter is documented
   exactly once with '[param name]', and every '[param]' references a declared parameter.
3. Complete rejection of banned constructs: Markdown code fences (```), and boundary-isolated
   Doxygen tags (@param, @return, @brief).
4. Project-approved BBCode grammar validated by a single-pass, stack-based parser:
   - Formatting tags: [b], [i]
   - Opaque code tags: [code] is non-nesting and terminates at the first literal [/code];
     nested code spans or unclosed tags are strictly invalid.
   - Semantic void tags: [param], [constant], [member], [method], [signal], [enum].
   - Unsupported Godot tags (e.g. [codeblock], [kbd], [url]) produce explicit rejection errors.
5. Placement: standalone documentation comments must immediately precede the declaration
   or its associated contiguous annotation block. Ordinary '#' comments may occur inside a
   contiguous annotation block; blank lines terminate the block.
6. Explicit exclusions: inline documentation comments ('var x ## doc'), unexported public
   variables, enum values, inner classes, and extended Godot BBCode features outside the
   project subset are deliberately outside this contract.
"""

DOCUMENTATION_CONTRACT_VERSION = "1.0"

import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, List, Optional, Set, Tuple

try:
    from gdtoolkit.parser import parser as gdparser
    from lark.lexer import Token
    from lark.tree import Tree
except ImportError:
    print("[ERROR] 'gdtoolkit' is required. Run: pip install gdtoolkit")
    sys.exit(1)

ALLOWED_SUBDIRS = ("core", "entities", "managers", "resources", "system", "ui")

RE_DOC_LINE = re.compile(r"^[ \t]*##(?:\s.*)?$")
RE_BANNED_FENCE = re.compile(r"```")
RE_DOXYGEN_TAG = re.compile(r"(?<![A-Za-z0-9_])@(param|return|brief)\b")

# Project-approved documentation BBCode grammar
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
    errors: List[str] = []
    param_names: List[str] = []
    found_tags: List[str] = []
    idx = 0
    length = len(text)
    tag_stack: List[str] = []

    while idx < length:
        if text[idx:].startswith("[code]"):
            found_tags.append("code")
            end_code = text.find("[/code]", idx + 6)
            if end_code == -1:
                errors.append(f"{location_desc}: Unclosed '[code]' block.")
                break

            inner_code = text[idx + 6 : end_code]
            if "[code]" in inner_code:
                errors.append(
                    f"{location_desc}: Nested '[code]' block detected inside code span."
                )

            idx = end_code + 7
            continue

        if text[idx:].startswith("[/code]"):
            errors.append(
                f"{location_desc}: Stray closing '[/code]' without preceding open '[code]'."
            )
            idx += 7
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


# -----------------------------------------------------------------------------
# AST Traversal & Member Extraction
# -----------------------------------------------------------------------------
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


def extract_params(func_node: Tree) -> List[str]:
    params = []
    param_rules: Set[str] = {
        "func_arg_regular",
        "func_arg_typed",
        "func_arg_inf",
        "func_arg_variadic",
    }
    for subtree in func_node.iter_subtrees():
        if subtree.data in param_rules:
            for child in subtree.children:
                if isinstance(child, Token) and child.type == "NAME":
                    params.append(str(child.value))
                    break
    return params


def extract_signal_params(signal_node: Tree) -> List[str]:
    params = []
    signal_arg_rules: Set[str] = {"signal_arg_regular", "signal_arg_typed"}
    for subtree in signal_node.iter_subtrees():
        if subtree.data in signal_arg_rules:
            for child in subtree.children:
                if isinstance(child, Token) and child.type == "NAME":
                    params.append(str(child.value))
                    break
    return params


def get_top_level_statements(ast: Tree) -> List[Any]:
    if ast.data == "class_body":
        return ast.children
    if ast.data == "start":
        for child in ast.children:
            if isinstance(child, Tree) and child.data == "class_body":
                return child.children
        raise ValueError("AST 'start' node contains no class_body.")
    raise ValueError(
        f"Unable to locate top-level class body. Root rule is '{ast.data}'."
    )


def check_doc_presence(lines: List[str], insert_line: int) -> List[str]:
    doc_lines = []
    idx = insert_line - 2
    while idx >= 0 and RE_DOC_LINE.match(lines[idx]):
        doc_lines.insert(0, lines[idx])
        idx -= 1
    return doc_lines


def check_detached_docs(
    lines: List[str],
    anno_line: Optional[int],
    decl_line: Optional[int],
    member_kind: str,
    member_name: str,
) -> List[str]:
    errs = []
    if anno_line and decl_line and anno_line < decl_line:
        anno_idx = anno_line - 1
        decl_idx = decl_line - 1
        for idx in range(anno_idx + 1, decl_idx):
            if RE_DOC_LINE.match(lines[idx]):
                errs.append(
                    f"Docstring placed between annotation and {member_kind} '{member_name}' (line {idx + 1})."
                )
    return errs


# -----------------------------------------------------------------------------
# File Validation
# -----------------------------------------------------------------------------
def validate_file(file_path: Path) -> List[str]:
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
    except (OSError, UnicodeError) as e:
        return [f"{file_path}: unable to read file: {e}"]

    errors: List[str] = []

    try:
        ast = gdparser.parse(content, gather_metadata=True)
        statements = get_top_level_statements(ast)
    except Exception as e:
        return [f"{file_path}: GDScript AST syntax error: {e}"]

    lines = content.splitlines(keepends=True)

    # 1. Banned formatting checks
    for idx, line in enumerate(lines, start=1):
        if RE_DOC_LINE.match(line):
            if RE_BANNED_FENCE.search(line):
                errors.append(
                    f"{file_path}:{idx} Banned Markdown code fence (```) in docstring."
                )
            if RE_DOXYGEN_TAG.search(line):
                errors.append(
                    f"{file_path}:{idx} Banned Doxygen tag (@param/@return/@brief). Use Native Godot BBCode."
                )

    # 2. Collect class-level annotations
    annotations: List[Tuple[int, str]] = []
    for anno_node in ast.find_data("annotation"):
        line = get_first_token_line(anno_node)
        anno_name = extract_annotation_name(anno_node)
        if line and anno_name:
            annotations.append((line, anno_name))

    def find_associated_annotation_line(target_line: int) -> Optional[int]:
        curr = target_line - 1
        earliest_line = None
        anno_map = {l: name for l, name in annotations}
        while curr > 0:
            line_str = lines[curr - 1].strip()
            if curr in anno_map:
                earliest_line = curr
                curr -= 1
            elif line_str.startswith("#"):
                curr -= 1
            else:
                break
        return earliest_line

    # 3. Validate Top-Level Declarations
    for node in statements:
        if not isinstance(node, Tree):
            continue

        # Functions (regular and static)
        if node.data in ("func_def", "static_func_def"):
            func_name = extract_func_name(node)
            if not func_name or func_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                continue
            anno_line = find_associated_annotation_line(decl_line)
            insert_line = anno_line if anno_line else decl_line

            for detached_err in check_detached_docs(
                lines, anno_line, decl_line, "function", func_name
            ):
                errors.append(f"{file_path}: {detached_err}")

            docs = check_doc_presence(lines, insert_line)
            if not docs:
                errors.append(
                    f"{file_path}:{decl_line} Public function '{func_name}' is missing docstrings."
                )
            else:
                raw_payload = normalize_doc_payload(docs)
                payload = validate_and_tokenize_bbcode(
                    raw_payload, f"{file_path}:{decl_line} ({func_name})"
                )
                errors.extend(payload.errors)

                sig_params = extract_params(node)
                doc_params = payload.param_names
                if len(doc_params) != len(set(doc_params)):
                    errors.append(
                        f"{file_path}:{decl_line} Function '{func_name}' has duplicate [param] tags."
                    )

                missing = [p for p in sig_params if p not in doc_params]
                unexpected = [p for p in doc_params if p not in sig_params]

                for p in missing:
                    errors.append(
                        f"{file_path}:{decl_line} Function '{func_name}' is missing docstring tag for [param {p}]."
                    )
                for p in unexpected:
                    errors.append(
                        f"{file_path}:{decl_line} Function '{func_name}' docstring references undeclared [param {p}]."
                    )

        # Exported Properties
        elif node.data == "class_var_stmt":
            var_name = extract_var_name(node)
            if not var_name or var_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                continue
            anno_line = find_associated_annotation_line(decl_line)

            is_export = False
            if anno_line:
                for l, name in annotations:
                    if (
                        anno_line <= l < decl_line
                        and name in PROPERTY_EXPORT_ANNOTATIONS
                    ):
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

            insert_line = anno_line if anno_line else decl_line
            for detached_err in check_detached_docs(
                lines, anno_line, decl_line, "exported property", var_name
            ):
                errors.append(f"{file_path}: {detached_err}")

            docs = check_doc_presence(lines, insert_line)
            if not docs:
                errors.append(
                    f"{file_path}:{decl_line} Exported property '{var_name}' is missing docstrings."
                )
            else:
                raw_payload = normalize_doc_payload(docs)
                payload = validate_and_tokenize_bbcode(
                    raw_payload, f"{file_path}:{decl_line} (@export {var_name})"
                )
                errors.extend(payload.errors)

        # Public Signals
        elif node.data == "signal_stmt":
            sig_name = extract_signal_name(node)
            if not sig_name or sig_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                continue
            anno_line = find_associated_annotation_line(decl_line)
            insert_line = anno_line if anno_line else decl_line

            for detached_err in check_detached_docs(
                lines, anno_line, decl_line, "signal", sig_name
            ):
                errors.append(f"{file_path}: {detached_err}")

            docs = check_doc_presence(lines, insert_line)
            if not docs:
                errors.append(
                    f"{file_path}:{decl_line} Public signal '{sig_name}' is missing docstrings."
                )
            else:
                raw_payload = normalize_doc_payload(docs)
                payload = validate_and_tokenize_bbcode(
                    raw_payload, f"{file_path}:{decl_line} (signal {sig_name})"
                )
                errors.extend(payload.errors)

                sig_params = extract_signal_params(node)
                doc_params = payload.param_names
                if len(doc_params) != len(set(doc_params)):
                    errors.append(
                        f"{file_path}:{decl_line} Signal '{sig_name}' has duplicate [param] tags."
                    )

                missing = [p for p in sig_params if p not in doc_params]
                unexpected = [p for p in doc_params if p not in sig_params]

                for p in missing:
                    errors.append(
                        f"{file_path}:{decl_line} Signal '{sig_name}' is missing docstring tag for [param {p}]."
                    )
                for p in unexpected:
                    errors.append(
                        f"{file_path}:{decl_line} Signal '{sig_name}' references undeclared [param {p}]."
                    )

        # Public Constants
        elif node.data == "const_stmt":
            const_name = extract_const_name(node)
            if not const_name or const_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                continue
            anno_line = find_associated_annotation_line(decl_line)
            insert_line = anno_line if anno_line else decl_line

            for detached_err in check_detached_docs(
                lines, anno_line, decl_line, "constant", const_name
            ):
                errors.append(f"{file_path}: {detached_err}")

            docs = check_doc_presence(lines, insert_line)
            if not docs:
                errors.append(
                    f"{file_path}:{decl_line} Public constant '{const_name}' is missing docstrings."
                )
            else:
                raw_payload = normalize_doc_payload(docs)
                payload = validate_and_tokenize_bbcode(
                    raw_payload, f"{file_path}:{decl_line} (const {const_name})"
                )
                errors.extend(payload.errors)

        # Public Enums
        elif node.data == "enum_stmt":
            enum_name = extract_enum_name(node)
            if not enum_name or enum_name.startswith("_"):
                continue

            decl_line = get_first_token_line(node)
            if not decl_line:
                continue
            anno_line = find_associated_annotation_line(decl_line)
            insert_line = anno_line if anno_line else decl_line

            for detached_err in check_detached_docs(
                lines, anno_line, decl_line, "enum", enum_name
            ):
                errors.append(f"{file_path}: {detached_err}")

            docs = check_doc_presence(lines, insert_line)
            if not docs:
                errors.append(
                    f"{file_path}:{decl_line} Public enum '{enum_name}' is missing docstrings."
                )
            else:
                raw_payload = normalize_doc_payload(docs)
                payload = validate_and_tokenize_bbcode(
                    raw_payload, f"{file_path}:{decl_line} (enum {enum_name})"
                )
                errors.extend(payload.errors)

    return errors


# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="GDScript Documentation Contract Validator"
    )
    parser.add_argument(
        "files",
        nargs="*",
        help="Optional specific files to validate. If omitted, scans all approved subtrees.",
    )
    args = parser.parse_args()

    raw_scripts_root = Path("scripts")
    if raw_scripts_root.is_symlink():
        print("[ERROR] 'scripts/' must not be a symlink.")
        sys.exit(1)

    scripts_root = raw_scripts_root.resolve()
    if not scripts_root.exists():
        print("[ERROR] 'scripts/' directory not found.")
        sys.exit(1)

    all_errors: List[str] = []

    # If specific files are passed (e.g. from git diff), validate only those
    if args.files:
        for file_str in args.files:
            fpath = Path(file_str)
            if fpath.is_symlink():
                all_errors.append(f"Symlink file rejected: {fpath}")
                continue
            resolved = fpath.resolve()
            if not resolved.is_relative_to(scripts_root):
                all_errors.append(f"Path escaping root rejected: {fpath}")
                continue
            all_errors.extend(validate_file(resolved))
    else:
        # Full-tree scan
        for subdir in ALLOWED_SUBDIRS:
            raw_target = scripts_root / subdir
            if not raw_target.exists():
                continue
            if raw_target.is_symlink():
                all_errors.append(f"Symlink directory rejected: {raw_target}")
                continue
            target = raw_target.resolve()
            if not target.is_relative_to(scripts_root):
                all_errors.append(f"Directory escaping root rejected: {raw_target}")
                continue
            for fpath in sorted(target.rglob("*.gd")):
                if fpath.is_symlink():
                    all_errors.append(f"Symlink file rejected: {fpath}")
                    continue
                resolved = fpath.resolve()
                if not resolved.is_relative_to(scripts_root):
                    all_errors.append(f"Path escaping root rejected: {fpath}")
                    continue
                all_errors.extend(validate_file(resolved))

    if all_errors:
        print(
            f"\n[FAIL] Documentation contract validation v{DOCUMENTATION_CONTRACT_VERSION} failed with {len(all_errors)} error(s):"
        )
        for e in all_errors:
            print(f"  - {e}")
        sys.exit(1)

    print(
        f"[SUCCESS] All targeted GDScript documentation contracts (v{DOCUMENTATION_CONTRACT_VERSION}) validated successfully."
    )


if __name__ == "__main__":
    main()
