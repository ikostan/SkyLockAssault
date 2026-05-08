#!/bin/bash

# $1 is the filename passed from Python (e.g., "dummy.godot")
TARGET_FILE="$1"

if [ -z "$TARGET_FILE" ]; then
    echo "Error: No file path provided."
    exit 1
fi

awk '
BEGIN {
  salt = ENVIRON["SALT"]
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
' "$TARGET_FILE" > "${TARGET_FILE}.tmp" && mv "${TARGET_FILE}.tmp" "$TARGET_FILE"