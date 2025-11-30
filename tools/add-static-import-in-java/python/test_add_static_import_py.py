#!/usr/bin/env python3
# pytest tests for dev/python/add-import.py (static imports)
#
# Validates:
# 1) Adding a static import when missing
# 2) Idempotency when the static import is already present
#
# Usage (from project root):
#   pytest -q dev/python/test_add_static_import_py.py

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import pytest

# Allow importing helper module from the same dev/python directory
import sys as _sys
_dev_dir = Path(__file__).parent
if str(_dev_dir) not in _sys.path:
    _sys.path.insert(0, str(_dev_dir))
from add_import_test_helpers import (
    create_java_file,
    add_existing_import_to_file as _add_existing_import_to_file,
    print_block,
)

SCRIPT = Path(__file__).with_name("add-import.py")
METHOD_FQN = "org.assertj.core.api.Assertions.assertThat"
IMPORT_LINE = f"import static {METHOD_FQN};"







@pytest.mark.parametrize("pkg,cls", [("com.example", "MissingImport")])
def test_adds_import_when_missing(tmp_path: Path, pkg: str, cls: str, request: pytest.FixtureRequest, capsys: pytest.CaptureFixture[str]) -> None:
    java_file = create_java_file(tmp_path, pkg, cls)

    # Verbose-like output only when -v
    before_text = java_file.read_text(encoding="utf-8")
    print_block(request, capsys, "BEFORE", java_file, before_text)

    # Run the Python script to add the static import
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--static", METHOD_FQN, str(java_file)],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr

    expected_snippet = f"[OK] Added: {IMPORT_LINE} -> {java_file}"
    assert expected_snippet in result.stdout

    # Verify the import exists exactly once
    text = java_file.read_text(encoding="utf-8")
    assert text.count(IMPORT_LINE) == 1

    # Verbose-like output only when -v
    print_block(request, capsys, "AFTER", java_file, text)

    # Ensure ordering: package < import < class
    def line_no_of(pattern: str) -> int:
        m = re.search(pattern, text, flags=re.MULTILINE)
        if not m:
            return 0
        return text[: m.start()].count("\n") + 1

    pkg_line = line_no_of(r"^package ")
    imp_line = line_no_of(r"^import static ")
    class_line = line_no_of(r"^public class ")

    assert pkg_line > 0, "package line not found"
    assert imp_line > 0, "import line not found"
    assert class_line > 0, "class line not found"
    assert imp_line > pkg_line, "import should be after package"
    assert imp_line < class_line, "import should be before class declaration"


@pytest.mark.parametrize("cls", ["AlreadyHasImport"])
def test_idempotent_when_import_already_exists(tmp_path: Path, cls: str, request: pytest.FixtureRequest, capsys: pytest.CaptureFixture[str]) -> None:
    java_file = tmp_path / f"{cls}.java"
    _add_existing_import_to_file(java_file, IMPORT_LINE)

    before = java_file.read_text(encoding="utf-8")
    assert before.count(IMPORT_LINE) == 1

    # Verbose-like output only when -v
    print_block(request, capsys, "BEFORE", java_file, before)

    # Run the script again
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--static", METHOD_FQN, str(java_file)],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr

    # Expect the exact idempotency message with an em-dash
    em_dash = "—"
    expected_msg = f"[INFO] Import already present in {java_file} {em_dash} skipping"
    assert expected_msg in result.stdout

    after = java_file.read_text(encoding="utf-8")
    assert after.count(IMPORT_LINE) == 1

    # Verbose-like output only when -v
    print_block(request, capsys, "AFTER", java_file, after)
