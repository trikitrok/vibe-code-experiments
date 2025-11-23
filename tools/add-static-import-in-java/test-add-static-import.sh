#!/usr/bin/env bash
# test-add-static-import.sh — bashunit tests for dev/add-static-import.sh
#
# This test suite validates:
# 1) Adding an import that does not already exist in the Java class
# 2) Not duplicating an import that already exists in the Java class (idempotency)
#
# It is written for https://github.com/TypedDevs/bashunit
# To run:
#   - Using vendored bashunit (recommended):
#       dev/lib/bashunit dev/test-add-static-import.sh
#   - Or simply execute:
#       dev/test-add-static-import.sh
#     which will invoke the vendored runner internally.
#
# Verbose mode:
#   Only available when executing this test file directly with -v/--verbose.
#   It will print the Java file(s) before and after running the script under test,
#   without affecting the captured assertions.
#
# Note: This suite requires the vendored bashunit at dev/lib/bashunit.

set -euo pipefail

# Resolve this script directory robustly both when executed directly and when sourced by bashunit
_THIS_FILE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$_THIS_FILE")" && pwd)
ADD_SCRIPT="$SCRIPT_DIR/add-static-import.sh"
METHOD_FQN="org.assertj.core.api.Assertions.assertThat"
IMPORT_LINE="import static ${METHOD_FQN};"

# --- bashunit bootstrap (vendored only) ---
RUN_BASHUNIT="$SCRIPT_DIR/lib/bashunit"
if [ ! -x "$RUN_BASHUNIT" ]; then
  echo "[FATAL] Vendored bashunit not found or not executable at $RUN_BASHUNIT" >&2
  echo "Please ensure dev/lib/bashunit exists and is executable." >&2
  exit 1
fi

# --- guards ---
[ -x "$ADD_SCRIPT" ] || { echo "[FATAL] add-static-import.sh not found or not executable at $ADD_SCRIPT" >&2; exit 1; }

# --- test fixtures ---
# Verbose mode: when enabled, tests print the Java file contents before and after modification
VERBOSE="${VERBOSE:-0}"
# Buffers to emit after each test via tear_down hook (bashunit prints hook output)
VERBOSE_FILE=""
VERBOSE_BEFORE=""
VERBOSE_AFTER=""

TMP_ROOT=""
set_up() {
  TMP_ROOT=$(mktemp -d "add-static-import-tests.XXXXXX")
  VERBOSE_FILE=""
  VERBOSE_BEFORE=""
  VERBOSE_AFTER=""
}

tear_down() {
  # Emit buffered verbose output (bashunit shows hook output)
  if is_verbose && [[ -n "${VERBOSE_FILE:-}" ]]; then
    print_content_with_header "BEFORE" "$VERBOSE_FILE" "$VERBOSE_BEFORE"
    print_content_with_header "AFTER" "$VERBOSE_FILE" "$VERBOSE_AFTER"
  fi
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT" 2>/dev/null || true
  fi
}

# --- helpers ---
create_java_file() {
  local pkg="$1" cls="$2" path="$3"
  mkdir -p "$(dirname "$path")"
  {
    [[ -n "$pkg" ]] && echo "package $pkg;" || true
    echo
    echo "public class $cls {"
    echo "  public void foo() {}"
    echo "}"
  } > "$path"
}

print_file_with_header() {
  local title="$1" file="$2"
  {
    echo "----- $title: $file -----"
    cat "$file"
    echo "----- end of $title: $file -----"
  } >&2
}

print_content_with_header() {
  # Prints provided content with headers; used in tear_down so output is visible under bashunit
  local title="$1" file="$2" content="$3"
  {
    echo "----- $title: $file -----"
    # Use printf to preserve newlines exactly
    printf "%s\n" "$content"
    echo "----- end of $title: $file -----"
  }
}

add_existing_import_to_file() {
  local path="$1"
  {
    echo "package com.example;"
    echo
    echo "$IMPORT_LINE"
    echo
    echo "public class AlreadyHasImport {"
    echo "  public void foo() {}"
    echo "}"
  } > "$path"
}

occurrences_of_import() {
  local file="$1"
  # Count exact matches of the import line, ignoring surrounding spaces
  awk -v target="$IMPORT_LINE" '{line=$0; sub(/^\s+/, "", line); sub(/\s+$/, "", line); if (line==target) {c++}} END{print c+0}' "$file"
}

line_no_of() {
  # prints first line number matching the given regex, or 0 if not found
  local regex="$1" file="$2"
  awk -v r="$regex" 'BEGIN{ln=0} $0 ~ r { if (ln==0) ln=NR } END{print ln+0}' "$file"
}

run_add() {
  "$ADD_SCRIPT" -m "$METHOD_FQN" "$1"
}

is_verbose() {
  [ "${VERBOSE:-0}" = "1" ]
}

# --- tests ---

test_adds_import_when_missing() {
  local file="$TMP_ROOT/MissingImport.java"
  create_java_file "com.example" "MissingImport" "$file"

  if is_verbose; then
    VERBOSE_FILE="$file"
    VERBOSE_BEFORE="$(cat "$file")"
  fi

  local out
  out=$(run_add "$file")

  if is_verbose; then
    VERBOSE_AFTER="$(cat "$file")"
  fi

  # Output should report addition
  [[ "$out" == *"[OK] Added: $IMPORT_LINE -> $file"* ]] || { echo "script did not report addition as expected" >&2; return 1; }

  # Import should be present exactly once
  local count
  count=$(occurrences_of_import "$file")
  [[ "$count" -eq 1 ]] || { echo "expected 1 occurrence of import, got $count" >&2; return 1; }

  # Ensure ordering: package < import < class
  local pkg_line imp_line class_line
  pkg_line=$(line_no_of '^package ' "$file")
  imp_line=$(line_no_of '^import static ' "$file")
  class_line=$(line_no_of '^public class ' "$file")

  [[ "$pkg_line" -gt 0 ]] || fail "package line not found"
  [[ "$imp_line" -gt 0 ]] || fail "import line not found"
  [[ "$class_line" -gt 0 ]] || fail "class line not found"

  [[ "$imp_line" -gt "$pkg_line" ]] || fail "import should appear after package"
  [[ "$imp_line" -lt "$class_line" ]] || fail "import should appear before class declaration"
}


test_idempotent_when_import_already_exists() {
  local file="$TMP_ROOT/AlreadyHasImport.java"
  add_existing_import_to_file "$file"

  if is_verbose; then
    VERBOSE_FILE="$file"
    VERBOSE_BEFORE="$(cat "$file")"
  fi

  local before_count
  before_count=$(occurrences_of_import "$file")
  assert_equals 1 "$before_count"

  local out
  out=$(run_add "$file")

  if is_verbose; then
    VERBOSE_AFTER="$(cat "$file")"
  fi

  assert_match "\\[INFO\\] Import already present in $file — skipping" "$out"

  local after_count
  after_count=$(occurrences_of_import "$file")
  assert_equals 1 "$after_count"
}

# --- run ---
# Only execute this block when the script is run directly, not when sourced by bashunit to discover tests
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # Extract -v/--verbose for this test file and pass the rest to bashunit
  ARGS=()
  VERBOSE="${VERBOSE:-0}"
  for arg in "$@"; do
    case "$arg" in
      -v|--verbose)
        VERBOSE=1
        ;;
      *)
        ARGS+=("$arg")
        ;;
    esac
  done
  # If our -v/--verbose was provided, enable bashunit verbose too so it prints hook output
  if [ "$VERBOSE" = "1" ]; then
    ARGS=("-vvv" "${ARGS[@]}")
  fi
  # Run via vendored bashunit CLI, carrying VERBOSE env
  VERBOSE="$VERBOSE" "$RUN_BASHUNIT" "$0" "${ARGS[@]}"
fi
