"""Utility functions"""

import importlib.resources
import logging
import re
from pathlib import Path

from langchain_core.exceptions import OutputParserException
from langchain_core.messages import AIMessage, BaseMessage

from buttercup.seed_gen import __module_name__

logger = logging.getLogger(__name__)


def resolve_module_subpath(subpath: str) -> Path:
    """Returns absolute path for file at subpath in module"""
    traversable = importlib.resources.files(f"buttercup.{__module_name__}").joinpath(subpath)
    return Path(str(traversable)).resolve()


def _validate_python_syntax(code: str) -> bool:
    """Check if the code is syntactically valid Python."""
    try:
        compile(code, "<string>", "exec")
        return True
    except SyntaxError as e:
        logger.debug("Syntax error in extracted code: %s", e)
        return False


def _extract_python_functions(content: str) -> list[str]:
    """Extract complete Python function definitions from text content.

    Uses indentation-based parsing to capture complete function bodies,
    including multi-line strings and nested structures.
    """
    functions = []
    lines = content.split("\n")
    i = 0

    while i < len(lines):
        line = lines[i]
        # Look for function definitions that match our expected naming
        func_match = re.match(r"^def\s+(gen_|generate_)[A-Za-z0-9_]*\s*\([^)]*\)", line)
        if func_match:
            # Found a function definition, extract the complete function
            func_lines = [line]
            i += 1

            # Get the base indentation (should be 0 for top-level functions)
            base_indent = len(line) - len(line.lstrip())

            # Track triple-quoted string state
            in_triple_single = False
            in_triple_double = False

            # Continue collecting lines that are part of this function
            while i < len(lines):
                next_line = lines[i]

                # Track triple-quoted strings
                # Count occurrences of ''' and """ (handling escaped quotes is complex, keep simple)
                triple_double_count = next_line.count('"""')
                triple_single_count = next_line.count("'''")

                # Toggle state based on odd number of triple quotes
                if triple_double_count % 2 == 1:
                    in_triple_double = not in_triple_double
                if triple_single_count % 2 == 1:
                    in_triple_single = not in_triple_single

                in_multiline_string = in_triple_single or in_triple_double

                # If we're inside a multi-line string, just add the line
                if in_multiline_string:
                    func_lines.append(next_line)
                    i += 1
                    continue

                # Empty lines are part of the function
                if not next_line.strip():
                    func_lines.append(next_line)
                    i += 1
                    continue

                # Calculate indentation of this line
                next_indent = len(next_line) - len(next_line.lstrip())

                # If we hit a line at or below base indentation that's not empty,
                # it's either a new top-level definition or not part of the function
                if next_indent <= base_indent and next_line.strip():
                    # Check if it's a new function definition
                    if re.match(r"^def\s+", next_line):
                        break
                    # Check if it looks like prose/explanation (starts with capital, no colon at end)
                    stripped = next_line.strip()
                    if (
                        stripped[0].isupper()
                        and not stripped.endswith(":")
                        and not stripped.startswith(("return", "raise", "assert", "pass", "break", "continue"))
                    ):
                        break

                func_lines.append(next_line)
                i += 1

            # Remove trailing empty lines
            while func_lines and not func_lines[-1].strip():
                func_lines.pop()

            # Only add if we have more than just the definition line
            if len(func_lines) > 1:
                functions.append("\n".join(func_lines))
        else:
            i += 1

    return functions


def extract_code(msg: BaseMessage) -> str:
    """Extract last markdown block or partial block from the AIMessage"""
    if not isinstance(msg, AIMessage):
        raise OutputParserException(f"Did not receive an AIMessage. Received: {type(msg)}")
    content = msg.content

    # Handle list content (some models return list of content blocks)
    if isinstance(content, list):
        # Extract text from content blocks
        text_parts = []
        for block in content:
            if isinstance(block, str):
                text_parts.append(block)
            elif isinstance(block, dict) and "text" in block:
                text_parts.append(block["text"])
        content = "\n".join(text_parts)
        logger.debug("Converted list content to string (%d parts)", len(text_parts))

    if not isinstance(content, str):
        raise OutputParserException(f"Content is not a string. Content is {type(content)}")

    # Try to get last complete markdown block
    find_iter = re.finditer(r"```([A-Za-z]*)\n(.*?)```", content, re.DOTALL)
    match = None
    for m in find_iter:
        match = m

    if match is not None:
        code = match.group(2)
        if _validate_python_syntax(code):
            return code
        logger.warning("Markdown code block has syntax errors, trying fallback extraction")

    # Try alternate pattern: code block without newline after language
    find_iter = re.finditer(r"```([A-Za-z]*)(.*?)```", content, re.DOTALL)
    match = None
    for m in find_iter:
        match = m

    if match is not None:
        code = match.group(2)
        # Strip leading newline if present
        if code.startswith("\n"):
            code = code[1:]
        if _validate_python_syntax(code):
            logger.debug("Found code block with alternate pattern")
            return code
        logger.warning("Alternate code block has syntax errors, trying fallback extraction")

    # If no complete block found, try to get partial block
    # Captures everything except the last function definition (likely incomplete)
    partial_match = re.search(
        r"```([A-Za-z]*)\n(.*)(?=\n\s*def\s+[A-Za-z0-9_]+\s*\([^)]*\))",
        content,
        re.DOTALL,
    )
    if partial_match is not None:
        code = partial_match.group(2)
        if _validate_python_syntax(code):
            logger.info("Found partial code block")
            return code
        logger.warning("Partial code block has syntax errors, trying fallback extraction")

    # Fallback: try to extract functions without markdown blocks
    # Use a smarter approach: find all function definitions and extract complete functions
    functions = _extract_python_functions(content)
    if functions:
        # Filter out syntactically invalid functions
        valid_functions = [f for f in functions if _validate_python_syntax(f)]
        if valid_functions:
            logger.warning(
                "No valid markdown block found, extracted %d/%d valid functions directly",
                len(valid_functions),
                len(functions),
            )
            return "\n\n".join(valid_functions)
        logger.warning(
            "Extracted %d functions but none are syntactically valid",
            len(functions),
        )

    # Log the content when we fail to extract code for debugging
    has_def = "def " in content
    has_triple_backtick = "```" in content
    content_preview = content[:1000] if len(content) > 1000 else content
    logger.error(
        "Failed to extract code from message. has_def=%s, has_backticks=%s, length=%d. Content preview:\n%s%s",
        has_def,
        has_triple_backtick,
        len(content),
        content_preview,
        "\n..." if len(content) > 1000 else "",
    )

    raise OutputParserException("Failed to extract code from message")


def get_diff_content(diffs: list[Path]) -> str | None:
    """Process diff files from ChallengeTask.get_diffs()

    Note: currently returns the first diff's content
    """
    # TODO: add support for multiple diffs if necessary
    if len(diffs) == 0:
        logger.info("No diffs found")
        return None
    if len(diffs) > 1:
        logger.warning("Multiple diffs found, using the first one")
    diff_content = diffs[0].read_text()
    return diff_content
