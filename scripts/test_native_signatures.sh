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
cp "$SOURCE" "$FIXTURES/with-integrations"
/usr/bin/codesign --force --sign - "$FIXTURES/without-integrations"
/usr/bin/codesign --force --sign - --generate-entitlement-der \
  --entitlements "$ENTITLEMENTS" "$FIXTURES/with-integrations"
xcrun swiftc -swift-version 5 -warnings-as-errors -parse-as-library \
  "$ROOT/Fitness/Core/SigningCapabilities.swift" "$ROOT/scripts/SigningSmoke.swift" \
  -o "$CHECKS/SigningSmoke"
CONTAINER="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-identifiers:0' "$ENTITLEMENTS")"
GROUP="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' "$ENTITLEMENTS")"
"$CHECKS/SigningSmoke" "$SOURCE" none "$CONTAINER" "$GROUP"
"$CHECKS/SigningSmoke" "$FIXTURES/without-integrations" none "$CONTAINER" "$GROUP"
"$CHECKS/SigningSmoke" "$FIXTURES/with-integrations" full "$CONTAINER" "$GROUP"
python3 "$ROOT/scripts/verify_ipa.py" "$PRODUCTS/Wateera-unsigned.ipa"
