#!/usr/bin/env sh
# add-import.sh — add an import (class by default) or a static import to one or more Java source files
#
# Usage:
#   - Add a class import (default):
#       dev/add-import.sh com.example.SomeClass path/to/File1.java [path/to/File2.java ...]
#   - Add a static import:
#       dev/add-import.sh --static com.example.Util.someMember path/to/File1.java [...]
#
# Notes:
# - For class imports, provide a fully-qualified class name, e.g. "java.util.List".
# - For static imports, provide a fully-qualified static member reference suitable for a Java import,
#   e.g. "org.assertj.core.api.Assertions.assertThat" or "java.util.Collections.emptyList".
# - The script is idempotent: if the exact import line already exists in a file, it will be skipped.
# - The import will be inserted after the last existing import; if there are no imports, after the package
#   declaration; if there is no package/import, it will be inserted at the top of the file.
#
# Examples:
#   dev/add-import.sh java.util.List src/main/java/com/example/MyClass.java
#   dev/add-import.sh --static org.assertj.core.api.Assertions.assertThat src/test/java/com/example/MyTest.java

set -eu

# --- helpers ---
print_usage() {
  cat >&2 <<EOF
Usage:
  $0 [--static] <fully.qualified.ClassOrMember> <java_file1> [java_file2 ...]

Options:
  --static        Treat the given FQN as a static member to import (import static ...)
  -h, --help      Show this help and exit
EOF
}

 die() {
  echo "[ERROR] $*" >&2
  exit 1
}

MODE="class"          # "class" or "static"
TARGET_FQN=""

# Minimal arity check (will be revalidated after parsing)
if [ $# -lt 2 ]; then
  print_usage
  exit 1
fi

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --static)
      MODE="static"
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      # first non-option can be either the FQN (if not yet set) or the first file
      if [ -z "$TARGET_FQN" ]; then
        TARGET_FQN="$1"
      else
        break
      fi
      ;;
  esac
  shift || true
done

# If FQN wasn't provided yet (e.g., using --static without -m), read it now
if [ -z "$TARGET_FQN" ]; then
  [ $# -gt 0 ] || die "Missing required fully-qualified name argument"
  TARGET_FQN="$1"
  shift || true
fi

# Remaining args must be one or more Java files
[ $# -gt 0 ] || die "Provide at least one Java file path"

if [ "$MODE" = "static" ]; then
  IMPORT_LINE="import static ${TARGET_FQN};"
else
  IMPORT_LINE="import ${TARGET_FQN};"
fi

insert_import() {
  file="$1"
  [ -f "$file" ] || { echo "[WARN] Skipping: not a file: $file" >&2; return 0; }
  case "$file" in
    *.java) : ;;
    *) echo "[WARN] Skipping non-Java file: $file" >&2; return 0 ;;
  esac

  # Skip if already present (exact match, ignoring leading/trailing whitespace)
  if awk -v imp="$IMPORT_LINE" 'BEGIN{found=0} {line=$0; sub(/^[[:space:]]+/,"",line); sub(/[[:space:]]+$/,"",line); if(line==imp){found=1}} END{exit found?0:1}' "$file"; then
    echo "[INFO] Import already present in $file — skipping"
    return 0
  fi

  # Find positions (POSIX character classes)
  last_import_line=$(awk '/^[[:space:]]*import[[:space:]]/{lnr=NR} END{if(lnr) print lnr; else print 0}' "$file")
  package_line=$(awk '/^[[:space:]]*package[[:space:]]/{pl=NR} END{if(pl) print pl; else print 0}' "$file")

  insert_after="$last_import_line"
  if [ "$insert_after" -eq 0 ] && [ "$package_line" -ne 0 ]; then
    insert_after="$package_line"
  fi

  tmp_file=$(mktemp "${file##*/}.XXXXXX")
  if [ "$insert_after" -gt 0 ]; then
    awk -v ia="$insert_after" -v imp="$IMPORT_LINE" -v pli="$package_line" -v li="$last_import_line" '
      { print $0 }
      NR==ia {
        print imp
        # If we inserted after package and there were no imports, add a blank line for readability
        if (li==0 && pli>0) { print "" }
      }
    ' "$file" > "$tmp_file"
  else
    # No package/import lines: put import at top, then blank line, then file
    {
      echo "$IMPORT_LINE"
      echo ""
      cat "$file"
    } > "$tmp_file"
  fi

  # Replace atomically
  if mv "$tmp_file" "$file"; then
    echo "[OK] Added: $IMPORT_LINE -> $file"
  else
    rm -f "$tmp_file" 2>/dev/null || true
    die "Failed to update file: $file"
  fi
}

for f in "$@"; do
  insert_import "$f"
 done
