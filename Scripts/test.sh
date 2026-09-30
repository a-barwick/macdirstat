#!/bin/bash
# Runs the test suite. With only the Command Line Tools installed (no Xcode), Swift Testing lives
# outside the default search paths, so point the compiler and linker at it.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"
if [ -d "$FW/Testing.framework" ] && [[ "$DEV" == *CommandLineTools* ]]; then
  exec swift test -Xswiftc -F -Xswiftc "$FW" -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" "$@"
fi
exec swift test "$@"
