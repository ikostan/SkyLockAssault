#!/bin/bash
# .github/scripts/inject_salt.sh

PROJECT_FILE=$1
# We expect this to be PRE-ESCAPED by the caller
ESCAPED_SALT=$2

if [ -z "$PROJECT_FILE" ] || [ -z "$ESCAPED_SALT" ]; then
    echo "Usage: $0 <path_to_project.godot> <pre_escaped_salt>"
    exit 1
fi

awk -v salt="$ESCAPED_SALT" '
  BEGIN { in_game = 0; salt_written = 0; saw_game_section = 0 }
  {
    if ($0 ~ /^\[game\]/) { in_game = 1; saw_game_section = 1; print; next }
    else if ($0 ~ /^\[/ && $0 !~ /^\[game\]/) {
      if (in_game && !salt_written) { print "security/save_salt=\"" salt "\""; salt_written = 1 }
      in_game = 0; print; next
    }
    if (in_game && $0 ~ /^[[:space:]]*security\/save_salt[[:space:]]*=/) {
      if (!salt_written) { print "security/save_salt=\"" salt "\""; salt_written = 1 }
      next
    }
    print
  }
  END {
    if (in_game && !salt_written) { print "security/save_salt=\"" salt "\""; salt_written = 1 }
    if (!saw_game_section) { if (NR > 0) { print "" }; print "[game]"; print "security/save_salt=\"" salt "\"" }
  }
' "$PROJECT_FILE" > "$PROJECT_FILE.tmp" && mv "$PROJECT_FILE.tmp" "$PROJECT_FILE"