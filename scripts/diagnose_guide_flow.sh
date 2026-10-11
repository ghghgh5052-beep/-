#!/bin/bash
# Capture a blocked simulator UI without changing the app's timers or test assertions.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT/build/tests-guide"
mkdir -p "$OUTPUT"
(
  for ATTEMPT in {1..300}; do
    WORKOUT_PID="$(pgrep -x Fitness | head -n 1 || true)"
    if [[ -n "$WORKOUT_PID" ]]; then
      sleep 180
      if kill -0 "$WORKOUT_PID" 2>/dev/null; then
        sample "$WORKOUT_PID" 5 -file "$OUTPUT/workout-ui.sample.txt" >/dev/null 2>&1 || true
      fi
      exit 0
    fi
    sleep 2
  done
) &
SAMPLER_PID=$!
trap 'kill "$SAMPLER_PID" 2>/dev/null || true' EXIT
TEST_OUTPUT_DIR="$OUTPUT" TEST_ONLY_IDENTIFIER="FitnessUITests/EnhancementFlowTests/testTimedExerciseLogsSecondsAndShowsNativeStartEndPreview" bash "$ROOT/scripts/test_ios.sh"
