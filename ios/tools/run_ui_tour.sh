#!/bin/bash
# Runs the live end-to-end UI tests (AppShellUITests) and the screenshot tour (ScreenshotTourUITests) on one simulator,
# against the live backend (https://paywise-api-n0f9.onrender.com).
#
#   ios/tools/run_ui_tour.sh          # live tests, then the tour 4 times
#   ios/tools/run_ui_tour.sh live     # live tests only
#   ios/tools/run_ui_tour.sh tour     # the tour only
#
# Steps: find (or create) the simulator, warm Render, `simctl addmedia` the laptop checkout so it is the newest photo,
# build once, run. The tour runs light + default size, dark + default size, light + Dynamic Type extra-large (XL) and
# light + extra-extra-large, writing docs/overnight-shots/{light-default,dark-default,light-xl,light-xxl}/NN-<screen>.png.
# Appearance, text size and the status bar are put back (light, large, cleared) on exit.
#
# Env: PAYWISE_SIM (simulator name, default "Paywise Dev 18"), PAYWISE_DD (DerivedData), PAYWISE_RESULTS (where the
# .xcresult bundles and logs go). macOS has no `timeout`; a watchdog stops xcodebuild if it hangs after the tests end.
set -euo pipefail

mode="${1:-all}"
ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo_dir="$(cd "$ios_dir/.." && pwd)"
sim_name="${PAYWISE_SIM:-Paywise Dev 18}"
dd="${PAYWISE_DD:-${TMPDIR:-/tmp}/paywise-dd-ui}"
results="${PAYWISE_RESULTS:-${TMPDIR:-/tmp}/paywise-ui-results}/$(date +%Y%m%d-%H%M%S)"
api="https://paywise-api-n0f9.onrender.com"
mkdir -p "$results"

udid_of() {
  xcrun simctl list devices | grep -F "    $sim_name (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

udid="$(udid_of)"
if [ -z "$udid" ]; then
  echo "Creating simulator \"$sim_name\""
  xcrun simctl create "$sim_name" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0 >/dev/null
  udid="$(udid_of)"
fi
echo "Simulator: $sim_name ($udid)"
xcrun simctl bootstatus "$udid" -b >/dev/null

restore() {
  xcrun simctl ui "$udid" appearance light || true
  xcrun simctl ui "$udid" content_size large || true
  xcrun simctl status_bar "$udid" clear || true
}
trap restore EXIT

# Render's free tier sleeps; the first request can take ~30-60 s.
for attempt in 1 2 3 4 5 6; do
  code="$(curl -s -m 60 -o /dev/null -w '%{http_code}' "$api/health" || true)"
  echo "GET /health → $code (attempt $attempt)"
  [ "$code" = "200" ] && break
  sleep 5
done

# The picker shows the newest photo first and the tests pick it. addmedia dates a PNG by its file's modification time,
# so add a fresh copy (dated now): it sorts ahead of anything already in the simulator's library.
photo_dir="$(mktemp -d)"
cp "$repo_dir/fixtures/screenshots/laptop-checkout.png" "$photo_dir/laptop-checkout.png"
xcrun simctl addmedia "$udid" "$photo_dir/laptop-checkout.png"
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4

# xcodebuild <log> <args…> with a watchdog: interrupt it if it hasn't exited 60 s after the test run ended.
run_xcodebuild() {
  local log="$1"; shift
  (cd "$ios_dir" && xcodebuild "$@" </dev/null >"$log" 2>&1) &
  local pid=$! ended="" interrupted=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ -z "$ended" ] && grep -qE "Test Suite '(Selected tests|All tests)' (passed|failed)" "$log"; then ended=$(date +%s); fi
    if [ -n "$ended" ] && [ $(( $(date +%s) - ended )) -gt 60 ]; then
      interrupted=1
      kill -INT "$pid" 2>/dev/null || true; sleep 10; kill -9 "$pid" 2>/dev/null || true
      break
    fi
    sleep 2
  done
  local status=0
  wait "$pid" 2>/dev/null || status=$?
  grep -E "error:|Test Case .*(passed|failed)|Executed [0-9]+ tests?|PAYWISE_UI|TEST (BUILD )?(SUCCEEDED|FAILED)" "$log" \
    | grep -v "debugger version" | awk '!seen[$0]++' || true
  if [ "$interrupted" = 1 ]; then
    echo "WATCHDOG: xcodebuild hung for 60 s after the tests ended and was interrupted; the result comes from the log"
    if grep -qE "Test Suite '(Selected tests|All tests)' passed" "$log"; then status=0; else status=1; fi
  fi
  return "$status"
}

common=(-project Paywise.xcodeproj -scheme Paywise -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$dd")

echo "Building for testing → $results/build.log"
run_xcodebuild "$results/build.log" "${common[@]}" build-for-testing

failed=0
if [ "$mode" = "all" ] || [ "$mode" = "live" ]; then
  echo "Live UI tests → $results/live.log"
  xcrun simctl ui "$udid" appearance light
  xcrun simctl ui "$udid" content_size large
  run_xcodebuild "$results/live.log" "${common[@]}" -resultBundlePath "$results/live.xcresult" \
    -only-testing:PaywiseUITests/AppShellUITests test-without-building || failed=1
fi

if [ "$mode" = "all" ] || [ "$mode" = "tour" ]; then
  for run in "light large light-default" "dark large dark-default" "light extra-large light-xl" \
    "light extra-extra-large light-xxl"; do
    set -- $run
    echo "Tour: appearance $1, text size $2 → docs/overnight-shots/$3"
    xcrun simctl ui "$udid" appearance "$1"
    xcrun simctl ui "$udid" content_size "$2"
    TEST_RUNNER_PAYWISE_SHOTS="$3" run_xcodebuild "$results/tour-$3.log" "${common[@]}" \
      -resultBundlePath "$results/tour-$3.xcresult" \
      -only-testing:PaywiseUITests/ScreenshotTourUITests/testScreenshotTour test-without-building || failed=1
    echo "  $(ls "$repo_dir/docs/overnight-shots/$3"/*.png 2>/dev/null | wc -l | tr -d ' ') PNGs"
  done
fi

echo "Logs and result bundles: $results"
exit "$failed"
