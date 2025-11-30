#!/usr/bin/env python3
"""
add-import.py — add an import (class by default) or a static import to one or more Java source files

Usage:
  - Add a class import (default):
      dev/python/add-import.py com.example.SomeClass path/to/File1.java [path/to/File2.java ...]
  - Add a static import:
      dev/python/add-import.py --static com.example.Util.someMember path/to/File1.java [...]

Notes:
- For class imports, provide a fully-qualified class name, e.g. "java.util.List".
- For static imports, provide a fully-qualified static member reference suitable for a Java import,
  e.g. "org.assertj.core.api.Assertions.assertThat" or "java.util.Collections.emptyList".
- The script is idempotent: if the exact import line already exists in a file, it will be skipped.
- The import will be inserted after the last existing import; if there are no imports, after the package
  declaration; if there is no package/import, it will be inserted at the top of the file.

This Python implementation mirrors the behavior and output of dev/add-import.sh.
"""
from __future__ import annotations

import io
import os
import sys
import tempfile
from pathlib import Path

import click

DASH_INFO = "[INFO]"
DASH_OK = "[OK]"
EM_DASH = "—"  # U+2014, to exactly match the shell script output


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write_text_atomic(path: Path, text: str) -> None:
    # Write to a temp file in the same directory then replace
    directory = path.parent
    with tempfile.NamedTemporaryFile("w", dir=str(directory), delete=False, encoding="utf-8") as tf:
        tf.write(text)
        tmp_name = tf.name
    os.replace(tmp_name, path)


def _import_line(static: bool, fqn: str) -> str:
    return f"import {'static ' if static else ''}{fqn};"


def _already_has_import(content: str, import_line: str) -> bool:
    target = import_line.strip()
    for raw in content.splitlines():
        line = raw.strip()
        if line == target:
            return True
    return False


def _find_positions(content: str) -> tuple[int, int]:
    """Return (last_import_line_no, package_line_no), both 1-based or 0 if not found."""
    last_import = 0
    package_line = 0
    for idx, raw in enumerate(content.splitlines(), start=1):
        s = raw.lstrip()
        if s.startswith("import "):
            last_import = idx
        if s.startswith("package ") and package_line == 0:
            package_line = idx
    return last_import, package_line


def _insert_import(content: str, import_line: str) -> str:
    lines = content.splitlines()
    last_import, package_line = _find_positions(content)

    if last_import > 0:
        insert_after = last_import
    elif package_line > 0:
        insert_after = package_line
    else:
        insert_after = 0

    if insert_after == 0:
        # No package/import lines: put import at top, then blank line, then file
        out = io.StringIO()
        out.write(import_line + "\n\n")
        out.write(content)
        return out.getvalue()

    # Insert after the insert_after line number
    out_lines: list[str] = []
    for idx, line in enumerate(lines, start=1):
        out_lines.append(line)
        if idx == insert_after:
            out_lines.append(import_line)
            # If inserted after package and there were no imports, add blank line for readability
            if last_import == 0 and package_line > 0:
                out_lines.append("")
    return "\n".join(out_lines) + ("\n" if content.endswith("\n") else "")


@click.command(context_settings=dict(help_option_names=["-h", "--help"]))
@click.option("static", "--static", is_flag=True, default=False,
              help="Treat the given FQN as a static member to import (import static ...)")
@click.argument("fqn", nargs=1)
@click.argument("java_files", nargs=-1, type=click.Path(path_type=Path))
def main(static: bool, fqn: str, java_files: tuple[Path, ...]) -> None:
    """Add class or static imports to one or more Java files.

    This mirrors the behavior of the shell script version.
    """
    if not java_files:
        click.echo("[ERROR] Provide at least one Java file path", err=True)
        raise SystemExit(1)

    import_line = _import_line(static, fqn)

    for f in java_files:
        # Existence and extension checks
        if not f.exists():
            click.echo(f"[WARN] Skipping: not a file: {f}", err=True)
            continue
        if not f.is_file():
            click.echo(f"[WARN] Skipping: not a file: {f}", err=True)
            continue
        if f.suffix.lower() != ".java":
            click.echo(f"[WARN] Skipping non-Java file: {f}", err=True)
            continue

        content = _read_text(f)
        if _already_has_import(content, import_line):
            click.echo(f"{DASH_INFO} Import already present in {f} {EM_DASH} skipping")
            continue

        new_content = _insert_import(content, import_line)
        _write_text_atomic(f, new_content)
        click.echo(f"{DASH_OK} Added: {import_line} -> {f}")


if __name__ == "__main__":
    main()
