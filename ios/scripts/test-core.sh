#!/bin/sh
# Testet die Logik (GnocchiCore) auf dem Mac – auch ohne volles Xcode.
set -e
# Xcode ohne „sudo xcode-select“ verwenden, wenn es am Standardort liegt
[ -d /Applications/Xcode.app ] && export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")/../Packages/GnocchiCore"
if xcodebuild -version >/dev/null 2>&1; then
  swift test
else
  # Nur Command Line Tools: Test-Framework liegt außerhalb des Standardpfads
  F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  swift test -Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L"
fi
