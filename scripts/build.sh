#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
derived_data="$repository_root/.build/DerivedData/LocalBuild"
app_path="$derived_data/Build/Products/Release/Mutelet.app"

xcodebuild -quiet \
    -project "$repository_root/Mutelet.xcodeproj" \
    -scheme Mutelet \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$derived_data" \
    -configuration Release \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ ! -x "$app_path/Contents/MacOS/Mutelet" ]]; then
    echo "error: Release app was not produced at $app_path" >&2
    exit 1
fi

echo "Built Mutelet at $app_path"
