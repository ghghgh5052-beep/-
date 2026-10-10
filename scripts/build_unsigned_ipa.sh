#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${OUTPUT_DIR:-$ROOT/build}"

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null; then
  echo "A Mac with Xcode 16 or newer is required." >&2
  exit 1
fi
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
ARCHIVE="$OUTPUT/Wateera.xcarchive"
STAGING="$OUTPUT/ipa-staging"
# Never remove an arbitrary caller-provided directory. Only replace these exact build products.
if [[ -e "$ARCHIVE" || -e "$STAGING" ]]; then
  echo "Existing archive/staging detected. Use a fresh OUTPUT_DIR for a reproducible build." >&2
  exit 1
fi
python3 "$ROOT/scripts/validate_project.py"
xcodebuild -version | tee "$OUTPUT/xcode-version.txt"
xcodebuild -project "$ROOT/Wateera.xcodeproj" -scheme Wateera \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  archive 2>&1 | tee "$OUTPUT/archive.log"

APP="$ARCHIVE/Products/Applications/Fitness.app"
EXTENSION="$APP/PlugIns/FitnessWidgets.appex"
[[ -d "$APP" && -d "$EXTENSION" ]] || { echo "App or embedded widget/Live Activity extension is missing." >&2; exit 1; }
if /usr/bin/codesign -dv "$APP" >/dev/null 2>&1; then
  echo "The archive is signed; this pipeline requires an unsigned app." >&2
  exit 1
fi
mkdir -p "$STAGING/Payload"
/usr/bin/ditto "$APP" "$STAGING/Payload/Fitness.app"
(
  cd "$STAGING"
  /usr/bin/zip -qry "$OUTPUT/Wateera-unsigned.ipa" Payload
)
python3 "$ROOT/scripts/verify_ipa.py" "$OUTPUT/Wateera-unsigned.ipa"
mkdir -p "$OUTPUT/signing"
xcodebuild -project "$ROOT/Wateera.xcodeproj" -scheme Wateera -configuration Release \
  -showBuildSettings -json CODE_SIGNING_ALLOWED=NO > "$OUTPUT/signing/build-settings.json"
# Scheme settings report the app only; read the embedded target explicitly.
xcodebuild -project "$ROOT/Wateera.xcodeproj" -target FitnessWidgets -configuration Release -sdk iphoneos \
  -showBuildSettings -json CODE_SIGNING_ALLOWED=NO > "$OUTPUT/signing/widget-build-settings.json"
python3 "$ROOT/scripts/resolve_entitlements.py" "$OUTPUT/signing/build-settings.json" "$OUTPUT/signing" "$OUTPUT/signing/widget-build-settings.json"
cp "$ROOT/docs/CAPABILITIES.md" "$OUTPUT/signing/"
cp "$ROOT/Config/Identifiers.xcconfig" "$OUTPUT/signing/"
(cd "$ROOT" && git rev-parse HEAD) > "$OUTPUT/source-commit.txt"
(cd "$OUTPUT" && /usr/bin/shasum -a 256 Wateera-unsigned.ipa > Wateera-unsigned.ipa.sha256)
echo "Unsigned IPA: $OUTPUT/Wateera-unsigned.ipa"
