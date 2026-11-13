#!/bin/sh
# Erzeugt ios/Gnocchi.xcodeproj aus ios/project.yml. Nach jeder Änderung an project.yml ausführen.
set -e
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "XcodeGen fehlt: brew install xcodegen"; exit 1; }
xcodegen generate --quiet
echo "Gnocchi.xcodeproj erzeugt."
