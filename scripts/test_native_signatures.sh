#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCTS="${OUTPUT_DIR:-$ROOT/build}"
CHECKS="$PRODUCTS/signature-smoke"
mkdir -p "$CHECKS"
FIXTURES="$(mktemp -d "$CHECKS/fixtures.XXXXXX")"
SOURCE="$PRODUCTS/Wateera.xcarchive/Products/Applications/Fitness.app/Fitness"
ENTITLEMENTS="$PRODUCTS/signing/Fitness.resolved.entitlements"
[[ -f "$SOURCE" && -f "$ENTITLEMENTS" ]]
# Sign only isolated executable copies. The archive and unsigned IPA remain untouched.
cp "$SOURCE" "$FIXTURES/without-integrations"
/usr/bin/codesign --force --sign - "$FIXTURES/without-integrations"
python3 -c 'import plistlib,sys; assert plistlib.load(open(sys.argv[1],"rb")) == {}, "Local entitlements must be empty"' "$ENTITLEMENTS"
xcrun swiftc -swift-version 5 -warnings-as-errors -parse-as-library \
  "$ROOT/Fitness/Core/SigningCapabilities.swift" "$ROOT/scripts/SigningSmoke.swift" \
  -o "$CHECKS/SigningSmoke"
CONTAINER="iCloud.com.personal.Wateera"
GROUP="group.com.personal.Wateera"
"$CHECKS/SigningSmoke" "$SOURCE" none "$CONTAINER" "$GROUP"
"$CHECKS/SigningSmoke" "$FIXTURES/without-integrations" none "$CONTAINER" "$GROUP"
python3 "$ROOT/scripts/verify_ipa.py" "$PRODUCTS/Wateera-unsigned.ipa"
