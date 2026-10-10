#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${TEST_OUTPUT_DIR:-$ROOT/build/tests}"
mkdir -p "$OUTPUT"
if [[ -n "${IOS_SIMULATOR_DESTINATION:-}" ]]; then
  DESTINATION="$IOS_SIMULATOR_DESTINATION"
else
  xcrun simctl list devices available --json > "$OUTPUT/devices.json"
  DEVICE_ID="$(python3 "$ROOT/scripts/select_simulator.py" "$OUTPUT/devices.json")"
  DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
fi
python3 "$ROOT/scripts/validate_project.py"
xcodebuild -project "$ROOT/Wateera.xcodeproj" -scheme Wateera -configuration Debug \
  -destination "$DESTINATION" -parallel-testing-enabled NO \
  -resultBundlePath "$OUTPUT/Tests.xcresult" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  COPY_PHASE_STRIP=NO ONLY_ACTIVE_ARCH=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  test 2>&1 | tee "$OUTPUT/test.log"
