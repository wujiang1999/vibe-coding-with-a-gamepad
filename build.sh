#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${SIGN_IDENTITY:-ButtonKeys Local}"

swiftc -O -o button-keys main.swift \
  -framework Cocoa -framework GameController -framework ApplicationServices -framework CoreGraphics

# 稳定签名：TCC 的辅助功能授权绑定到「标识符 + 证书身份」而不是 cdhash，
# 所以换源码重编译后授权依然有效。没有这张证书时退回 ad-hoc，
# 那种情况下每次重编译都要重新授权一次。
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" --identifier button-keys button-keys
  echo "signed: $SIGN_IDENTITY"
else
  echo "warning: signing identity '$SIGN_IDENTITY' not found — falling back to ad-hoc;" >&2
  echo "         Accessibility permission must be re-granted after every rebuild." >&2
fi

echo "built: $(pwd)/button-keys"
