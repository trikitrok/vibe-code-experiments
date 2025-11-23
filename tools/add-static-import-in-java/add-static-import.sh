#!/usr/bin/env sh
# add-static-import.sh — add a static import to one or more Java source files
#
# Usage:
#   dev/add-static-import.sh -m com.example.Util.someMethod path/to/File1.java [path/to/File2.java ...]
#
# Notes:
# - The -m/--method argument must be a fully-qualified static member reference suitable for a Java import,
#   e.g. "org.assertj.core.api.Assertions.assertThat" or "java.util.Collections.emptyList".
# - The script is idempotent: if the exact static import already exists in a file, it will be skipped.
# - The import will be inserted after the last existing import; if there are no imports, after the package
#   declaration; if there is no package/import, it will be inserted at the top of the file.
#
# Example:
#   dev/add-static-import.sh --method org.assertj.core.api.Assertions.assertThat \
#       src/test/java/com/example/MyTest.java

set -eu

# --- helpers ---
print_usage() {
  echo "Usage: $0 -m <fully.qualified.Owner.member> <java_file1> [java_file2 ...]" >&2
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

METHOD_FQN=""

# parse args
if [ $# -lt 2 ]; then
  print_usage
  exit 1
fi

while [ $# -gt 0 ]; do
  case "$1" in
    -m|--method)
      shift || true
      [ $# -gt 0 ] || die "Missing value after -m/--method"
      METHOD_FQN="$1"
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
      # first non-option marks beginning of files list
      break
      ;;
  esac
  shift || true
done

[ -n "$METHOD_FQN" ] || die "You must provide -m/--method with a fully-qualified method or member"

if [ $# -lt 1 ]; then
  die "Provide at least one Java file path"
fi

IMPORT_LINE="import static ${METHOD_FQN};"

insert_import() {
  file="$1"
  [ -f "$file" ] || { echo "[WARN] Skipping: not a file: $file" >&2; return 0; }
  case "$file" in
    *.java) : ;; 
    *) echo "[WARN] Skipping non-Java file: $file" >&2; return 0; ;;
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
  # Ensure tmp is created in current directory; move later to original directory
  # Construct output with awk when inserting after a specific line
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

  # Preserve original file permissions and replace atomically
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
