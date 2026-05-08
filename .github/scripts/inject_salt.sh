#!/bin/bash
# .github/scripts/inject_salt.sh

PROJECT_FILE=$1
RAW_SECRET=$2

if [ -z "$PROJECT_FILE" ] || [ -z "$RAW_SECRET" ]; then
    echo "Usage: $0 <path_to_project.godot> <raw_salt_secret>"
    exit 1
fi

# 1. Escape backslashes and quotes for Godot's config format
ESCAPED_SALT=$(printf '%s' "$RAW_SECRET" | sed 's/\\/\\\\/g; s/"/\\"/g')

# 2. Run the AWK script
awk -v salt="$ESCAPED_SALT" '
  BEGIN {
    in_game = 0
    salt_written = 0
    saw_game_section = 0
  }
  {
    if ($0 ~ /^\[game\]/) {
      in_game = 1
      saw_game_section = 1
      print
      next
    } else if ($0 ~ /^\[/ && $0 !~ /^\[game\]/) {
      if (in_game && !salt_written) {
        print "security/save_salt=\"" salt "\""
        salt_written = 1
      }
      in_game = 0
      print
      next
    }
    if (in_game && $0 ~ /^[[:space:]]*security\/save_salt[[:space:]]*=/) {
      if (!salt_written) {
        print "security/save_salt=\"" salt "\""
        salt_written = 1
      }
      next
    }
    print
  }
  END {
    if (in_game && !salt_written) {
      print "security/save_salt=\"" salt "\""
      salt_written = 1
    }
    if (!saw_game_section) {
      if (NR > 0) { print "" }
      print "[game]"
      print "security/save_salt=\"" salt "\""
    }
  }
' "$PROJECT_FILE" > "$PROJECT_FILE.tmp" && mv "$PROJECT_FILE.tmp" "$PROJECT_FILE"