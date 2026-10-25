#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swiftc -O -o button-keys main.swift \
  -framework Cocoa -framework GameController -framework ApplicationServices -framework CoreGraphics
echo "built: $(pwd)/button-keys"
