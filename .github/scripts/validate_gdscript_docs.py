#!/usr/bin/env python3
"""
Strict GDScript Documentation Contract Validator.

Audits production GDScript files for:
1. Native Godot 4 '##' docstrings on ALL public members:
   - Functions
   - Exported properties (@export)
   - Public signals
   - Public constants
   - Public enums
2. Parameter tag matching: all [param x] must exist in method signatures.
3. Complete rejection of banned constructs (```, @param, @return).
4. Strict BBCode tag allowlist (handles opening and closing tags cleanly).
5. Proper annotation placement across ALL public members (docstrings must precede annotations).
"""

import re
import sys
from pathlib import Path
from typing import Any, List, Optional, Tuple

try:
    from gdtoolkit.parser import parser as gdparser
    from lark.lexer import Token
    from lark.tree import Tree
except ImportError:
    print("[ERROR] 'gdtoolkit' is required. Run: pip install gdtoolkit")
    sys.exit(1)

ALLOWED_SUBDIRS = ("core", "entities", "managers", "resources", "system", "ui")

RE_DOC_LINE = re.compile(r"^[ \t]*##(?:\s.*)?$")
RE_PARAM_TAG = re.compile(r"\[param\s+([a-zA-Z0-9_]+)\]", re.IGNORECASE)
RE_BANNED_FENCE = re.compile(r"```")
RE_DOXYGEN_TAG = re.compile(r"@(param|return|brief)")
RE_CODE_BLOCK = re.compile(r"\[code\].*?\[/code\]", re.DOTALL | re.IGNORECASE)

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


def extract_params(func_node: Tree) -> List[str]:
    params = []
    param_rules = {
        "func_arg_regular",
        "func_arg_typed",
        "func_arg_default",
        "func_arg_inf",
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
    for arg_node in signal_node.find_data("signal_arg_regular"):
        for child in arg_node.children:
            if isinstance(child, Token) and child.type == "NAME":
                params.append(str(child.value))
                break
    return params


def check_doc_presence(lines: List[str], insert_line: int) -> List[str]:
    """Extracts consecutive '##' doc lines immediately preceding insert_line."""
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
    """Validates that no docstring comments sit detached strictly between annotations and declarations."""
    errs = []
    if anno_line and decl_line and anno_line < decl_line:
        # Check strictly between anno_line and decl_line
        for mid in range(anno_line, decl_line - 1):
            if RE_DOC_LINE.match(lines[mid]):
                errs.append(
                    f"Docstring placed between annotation and {member_kind} '{member_name}' (line {mid + 1})."
                )
    return errs


def validate_file(file_path: Path) -> List[str]:
    errors = []
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    try:
        ast = gdparser.parse(content)
    except Exception as e:
        return [f"{file_path}: GDScript AST syntax error: {e}"]

    lines = content.splitlines(keepends=True)

    # 1. Check for banned formatting across all docstring lines
    for idx, line in enumerate(lines, start=1):
        if RE_DOC_LINE.match(line):
            if RE_BANNED_FENCE.search(line):
                errors.append(
                    f"{file_path}:{idx} Banned Markdown fence (```) in docstring."
                )
            if RE_DOXYGEN_TAG.search(line):
                errors.append(
                    f"{file_path}:{idx} Banned Doxygen tag (@param/@return). Use Godot BBCode [param name]."
                )
            line_without_code = RE_CODE_BLOCK.sub("", line)
            for tag_name in RE_BBCODE_TAG.findall(line_without_code):
                if tag_name.lower() not in ALLOWED_BASE_TAGS:
                    errors.append(
                        f"{file_path}:{idx} Unapproved BBCode tag '[{tag_name}]'."
                    )

    # Collect all annotations with their start lines
    annotations: List[Tuple[int, str]] = []
    for anno_node in ast.find_data("annotation"):
        line = get_first_token_line(anno_node)
        if line:
            anno_text = "".join(
                str(t.value)
                for t in anno_node.scan_values(lambda v: isinstance(v, Token))
            )
            annotations.append((line, anno_text))

    def find_associated_annotation_line(target_line: int) -> Optional[int]:
        """Finds the earliest consecutive annotation preceding target_line."""
        curr = target_line - 1
        earliest_line = None
        anno_map = {l: txt for l, txt in annotations}

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

    # 2. Validate Functions
    for node in ast.find_data("func_def"):
        func_name = None
        for child in node.children:
            if isinstance(child, Token) and child.type == "NAME":
                func_name = str(child.value)
                break

        if not func_name or func_name.startswith("_"):
            continue

        decl_line = get_first_token_line(node)
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
            joined = "".join(docs)
            params = extract_params(node)
            for tag in RE_PARAM_TAG.findall(joined):
                if tag not in params:
                    errors.append(
                        f"{file_path}:{decl_line} Function '{func_name}' docstring references [param {tag}], "
                        f"which does not exist in signature: {params}"
                    )

    # 3. Validate Exported Variables (@export)
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
            continue

        anno_line = find_associated_annotation_line(decl_line)

        is_export = False
        if anno_line:
            for l, txt in annotations:
                if anno_line <= l < decl_line and txt.startswith("@export"):
                    is_export = True
                    break

        if not is_export:
            for child in node.children:
                if isinstance(child, Tree) and child.data == "annotation":
                    for t in child.scan_values(lambda v: isinstance(v, Token)):
                        if t.value.startswith("@export"):
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

    # 4. Validate Public Signals
    for node in ast.find_data("signal_stmt"):
        sig_name = None
        for child in node.children:
            if isinstance(child, Token) and child.type == "NAME":
                sig_name = str(child.value)
                break

        if not sig_name or sig_name.startswith("_"):
            continue

        decl_line = get_first_token_line(node)
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
            joined = "".join(docs)
            params = extract_signal_params(node)
            for tag in RE_PARAM_TAG.findall(joined):
                if tag not in params:
                    errors.append(
                        f"{file_path}:{decl_line} Signal '{sig_name}' docstring references [param {tag}], "
                        f"which does not exist in signature: {params}"
                    )

    # 5. Validate Public Constants
    for node in ast.find_data("const_stmt"):
        const_name = None
        for child in node.children:
            if isinstance(child, Token) and child.type == "NAME":
                const_name = str(child.value)
                break

        if not const_name or const_name.startswith("_"):
            continue

        decl_line = get_first_token_line(node)
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

    # 6. Validate Public Enums
    for node in ast.find_data("enum_stmt"):
        enum_name = None
        for child in node.children:
            if isinstance(child, Token) and child.type == "NAME":
                enum_name = str(child.value)
                break

        if not enum_name or enum_name.startswith("_"):
            continue

        decl_line = get_first_token_line(node)
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

    return errors


def main():
    scripts_root = Path("scripts").resolve()
    if not scripts_root.exists():
        print("[ERROR] 'scripts/' directory not found.")
        sys.exit(1)

    all_errors = []
    for subdir in ALLOWED_SUBDIRS:
        target = scripts_root / subdir
        if not target.exists():
            continue
        for fpath in sorted(target.rglob("*.gd")):
            resolved = fpath.resolve()
            if not resolved.is_relative_to(scripts_root) or fpath.is_symlink():
                all_errors.append(f"Symlink or invalid path rejected: {fpath}")
                continue
            errs = validate_file(resolved)
            all_errors.extend(errs)

    if all_errors:
        print(
            f"\n[FAIL] Documentation contract validation failed with {len(all_errors)} error(s):"
        )
        for e in all_errors:
            print(f"  - {e}")
        sys.exit(1)

    print(
        "[SUCCESS] All production GDScript documentation contracts validated successfully."
    )


if __name__ == "__main__":
    main()
