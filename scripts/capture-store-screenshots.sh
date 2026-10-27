#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$repository_root/.work/store-screenshots"
if pgrep -f '/Mutelet[^/]*/Contents/MacOS/Mutelet' >/dev/null; then
    echo 'Quit Mutelet before capture. The capture uses isolated fake audio and settings.' >&2
    exit 1
fi
mkdir -p "$output/runs"
run_directory="$(mktemp -d "$output/runs/capture.XXXXXX")"
xcodebuild -quiet \
    -project "$repository_root/Mutelet.xcodeproj" \
    -scheme Mutelet \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$repository_root/.build/DerivedData/StoreScreenshots" \
    -resultBundlePath "$run_directory/Capture.xcresult" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- \
    -only-testing:MuteletUITests/MuteletUITests/testCaptureAppStoreAssets \
    test
xcrun xcresulttool export attachments \
    --path "$run_directory/Capture.xcresult" \
    --output-path "$run_directory/attachments"
node "$repository_root/tools/store-screenshots/collect.mjs" "$run_directory/attachments" "$output/assets"
echo "Captured assets: $output/assets"
echo "Result bundle: $run_directory/Capture.xcresult"
