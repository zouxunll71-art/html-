#!/bin/zsh
set -e
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/python3 -c 'import json;print(json.load(open("bridge/config.json"))["developerDir"])')}"
mkdir -p build artifacts
STUDIO_BUILD_SOURCE="$(/usr/bin/python3 scripts/source_stamp.py --print)"
# The current client embeds Studio sources; it does not need the legacy GUI app.
build_legacy=1
if [[ "${STUDIO_HEADLESS:-0}" == "1" || -d "/Applications/HTML Native Studio.app" ]]; then
  build_legacy=0
fi
if [[ "$build_legacy" == "1" ]]; then
  python3 scripts/make_project.py . HTMLNativeStudio Studio Shared
fi
python3 scripts/make_project.py . HTMLNativeRuntime Runtime Shared
xcrun clang -fobjc-arc scripts/ios_frames.m -framework Foundation -framework IOSurface -framework CoreImage -framework ImageIO -framework CoreGraphics -o build/ios-frames
xcrun clang -fobjc-arc scripts/ios_input.m -framework AppKit -framework Foundation -framework CoreGraphics -o build/ios-input
if [[ "$build_legacy" == "1" ]]; then
  xcodebuild -project HTMLNativeStudio.xcodeproj -scheme HTMLNativeStudio -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/studio CODE_SIGNING_ALLOWED=NO build > artifacts/studio-build.log 2>&1
fi
xcodebuild -project HTMLNativeRuntime.xcodeproj -scheme HTMLNativeRuntime -configuration Debug -sdk iphonesimulator -derivedDataPath build/runtime CODE_SIGNING_ALLOWED=NO build > artifacts/runtime-build.log 2>&1

/usr/bin/python3 scripts/source_stamp.py "$STUDIO_BUILD_SOURCE"
