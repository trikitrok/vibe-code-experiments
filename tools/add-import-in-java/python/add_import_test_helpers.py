#!/usr/bin/env python3
"""
Shared pytest fixture helpers for add-import Python tests.

Contains utilities that were duplicated across:
- dev/python/test_add_import_py.py
- dev/python/test_add_static_import_py.py

Exports:
- is_verbose(request)
- print_block(request, capsys, title, file, content)
- create_java_file(tmp_path, pkg, cls)
- add_existing_import_to_file(path, import_line)
"""
from __future__ import annotations

from pathlib import Path

import pytest


def is_verbose(request: pytest.FixtureRequest) -> bool:
    """Return True when pytest was invoked with -v (verbosity > 0)."""
    try:
        return int(request.config.getoption("verbose") or 0) > 0
    except Exception:
        return False


def print_block(
    request: pytest.FixtureRequest,
    capsys: pytest.CaptureFixture[str],
    title: str,
    file: Path,
    content: str,
) -> None:
    """Conditionally print BEFORE/AFTER blocks only in verbose mode.

    Uses capsys.disabled() so that output appears without -s / capture disabled.
    """
    if is_verbose(request):
        with capsys.disabled():
            print(f"----- {title}: {file} -----")
            print(content, end="")
            print(f"----- end of {title}: {file} -----")


def create_java_file(tmp_path: Path, pkg: str, cls: str) -> Path:
    """Create a minimal Java source file at tmp_path/<cls>.java with optional package."""
    p = tmp_path / f"{cls}.java"
    content: list[str] = []
    if pkg:
        content.append(f"package {pkg};")
    content.append("")
    content.append("public class " + cls + " {")
    content.append("  public void foo() {}")
    content.append("}")
    p.write_text("\n".join(content) + "\n", encoding="utf-8")
    return p


def add_existing_import_to_file(path: Path, import_line: str) -> None:
    """Write a Java file that already contains the given import line.

    The class name is fixed to AlreadyHasImport to mirror existing tests.
    """
    content = "\n".join(
        [
            "package com.example;",
            "",
            import_line,
            "",
            "public class AlreadyHasImport {",
            "  public void foo() {}",
            "}",
            "",
        ]
    )
    path.write_text(content, encoding="utf-8")
