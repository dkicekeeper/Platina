#!/bin/bash
#
# capture_screenshots.sh — the App Store's screenshots on simulators, no Mac at hand needed
# (Actions → Screenshots runs it; docs/app-store.md).
#
# For each device (an iPhone 6.9" and an iPad 13") and language (ru, en) it runs
# PlatinaUITests/ScreenshotCaptureTests: the app in its demo (-ScreenshotDemo: a made-up library
# in memory, art drawn on the device, Plati from a script) opens each screen itself; the test
# keeps a picture of it. The pictures are exported from the result bundles into
# screenshots/raw/<device>/<language>/NN-screen.png.
#
# Usage:
#   scripts/capture_screenshots.sh
#   DEVICES=iphone LANGUAGES=ru scripts/capture_screenshots.sh
#   SCREENS=game,plati scripts/capture_screenshots.sh
#
set -uo pipefail
cd "$(dirname "$0")/.."

DEVICES="${DEVICES:-iphone ipad}"
LANGUAGES="${LANGUAGES:-ru en}"
SCREENS="${SCREENS:-}"
OUT_ROOT="screenshots/raw"
RESULTS_ROOT="ios/build/screenshot-results"
mkdir -p "$OUT_ROOT" "$RESULTS_ROOT"

# The newest runtime's device of the store's size: an iPhone Pro Max (6.9"), an iPad Pro 13".
pick_device() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
kind = sys.argv[1]
pattern = re.compile(r"^iPhone \d+ Pro Max$" if kind == "iphone" else r"^iPad Pro 13-inch")
found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    for device in devices:
        if pattern.match(device["name"]):
            found.append(((int(m.group(1)), int(m.group(2))), device["name"], device["udid"]))
if found:
    found.sort(reverse=True)
    print(found[0][2] + "|" + found[0][1] + " (iOS " + ".".join(map(str, found[0][0])) + ")")
' "$1"
}

failures=()
for device in $DEVICES; do
  picked=$(pick_device "$device")
  if [[ -z "$picked" ]]; then
    echo "✗ No $device simulator of the store's size on this machine"
    failures+=("$device")
    continue
  fi
  udid="${picked%%|*}"
  echo ""
  echo "━━━ $device: ${picked#*|} ━━━"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # The store's status bar: 9:41, full battery and signal.
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 2>/dev/null || true

  for language in $LANGUAGES; do
    case "$language" in
      en) locale="en_US" ;;
      *) locale="ru_RU" ;;
    esac
    result="$RESULTS_ROOT/$device-$language.xcresult"
    rm -rf "$result"
    echo "▶ $language"
    TEST_RUNNER_SCREENSHOT_LANGUAGE="$language" \
    TEST_RUNNER_SCREENSHOT_LOCALE="$locale" \
    TEST_RUNNER_SCREENSHOT_SCREENS="$SCREENS" \
    xcodebuild test \
      -project ios/Platina.xcodeproj \
      -scheme Platina \
      -destination "platform=iOS Simulator,id=$udid" \
      -only-testing:PlatinaUITests/ScreenshotCaptureTests \
      -parallel-testing-enabled NO \
      -derivedDataPath ios/build/screenshots \
      -resultBundlePath "$result" \
      CODE_SIGNING_ALLOWED=NO \
      2>&1 | grep -aE "Test [Cc]ase .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)|error:" | head -40

    dest="$OUT_ROOT/$device/$language"
    rm -rf "$dest"
    mkdir -p "$dest"
    export_dir="$(mktemp -d)"
    if xcrun xcresulttool export attachments --path "$result" --output-path "$export_dir" >/dev/null 2>&1; then
      python3 - "$export_dir" "$dest" <<'PY'
import json, os, re, shutil, sys
export_dir, dest = sys.argv[1], sys.argv[2]
count = 0
manifest = os.path.join(export_dir, "manifest.json")
def walk(node):
    global count
    if isinstance(node, dict):
        for attachment in node.get("attachments", []) if isinstance(node.get("attachments"), list) else []:
            exported = attachment.get("exportedFileName")
            human = attachment.get("suggestedHumanReadableName") or exported or ""
            match = re.match(r"^([0-9]{2}-[a-z]+)", human)
            if exported and match and os.path.exists(os.path.join(export_dir, exported)):
                shutil.copy(os.path.join(export_dir, exported), os.path.join(dest, match.group(1) + ".png"))
                count += 1
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
if os.path.exists(manifest):
    walk(json.load(open(manifest)))
print(f"  exported {count} screenshots -> {dest}")
PY
    else
      echo "  ⚠️ could not export the attachments"
      failures+=("$device-$language")
    fi
    rm -rf "$export_dir"
    if [[ -z "$(ls "$dest")" ]]; then
      failures+=("$device-$language")
    fi
  done
  xcrun simctl shutdown "$udid" 2>/dev/null || true
done

echo ""
if (( ${#failures[@]} > 0 )); then
  echo "⚠️ With problems: ${failures[*]}"
  exit 1
fi
echo "✅ Screenshots in $OUT_ROOT/"
