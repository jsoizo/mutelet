#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
build_derived_data="$repository_root/.build/DerivedData/VerifyBuild"
test_derived_data="$repository_root/.build/DerivedData/VerifyTests"
project="$repository_root/Mutelet.xcodeproj"

cd "$repository_root"

"$script_dir/check-localizations.sh"
swift test

common_arguments=(
    -project "$project"
    -scheme Mutelet
    -destination "platform=macOS,arch=arm64"
)

xcodebuild -quiet "${common_arguments[@]}" \
    -derivedDataPath "$build_derived_data" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build
xcodebuild -quiet "${common_arguments[@]}" \
    -derivedDataPath "$test_derived_data" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY=- \
    build-for-testing
if [[ "${RUN_UI_TESTS:-0}" == "1" ]]; then
    if pgrep -f '/Mutelet.app/Contents/MacOS/Mutelet' >/dev/null 2>&1; then
        echo "error: quit the running Mutelet app before executing UI tests" >&2
        exit 1
    fi
    xcodebuild -quiet "${common_arguments[@]}" \
        -derivedDataPath "$test_derived_data" \
        -configuration Debug \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGNING_REQUIRED=YES \
        CODE_SIGN_IDENTITY=- \
        -only-testing:MuteletUITests \
        test-without-building
fi
xcodebuild -quiet "${common_arguments[@]}" \
    -derivedDataPath "$build_derived_data" \
    -configuration Release \
    CODE_SIGNING_ALLOWED=NO \
    build
xcodebuild -quiet "${common_arguments[@]}" \
    -derivedDataPath "$build_derived_data" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    analyze

release_app="$build_derived_data/Build/Products/Release/Mutelet.app"
executable="$release_app/Contents/MacOS/Mutelet"

if [[ ! -x "$executable" ]]; then
    echo "error: Release executable was not produced at $executable" >&2
    exit 1
fi

if [[ "$(lipo -archs "$executable")" != "arm64" ]]; then
    echo "error: Release executable must contain only arm64" >&2
    lipo -archs "$executable" >&2
    exit 1
fi

if strings "$executable" | grep -F -- '--ui-testing' >/dev/null; then
    echo "error: Release executable contains the UI-testing dependency switch" >&2
    exit 1
fi

if [[ "$(defaults read "$release_app/Contents/Info" LSUIElement)" != "1" ]]; then
    echo "error: Release app must set LSUIElement=true" >&2
    exit 1
fi

deployment_target="$(otool -l "$executable" | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build_version = 1; next }
    in_build_version && $1 == "minos" { print $2; exit }
')"
if [[ "$deployment_target" != "13.0" ]]; then
    echo "error: expected deployment target 13.0, got ${deployment_target:-unknown}" >&2
    exit 1
fi

if [[ "${RUN_UI_TESTS:-0}" == "1" ]]; then
    ui_test_result="unit and UI tests"
else
    ui_test_result="unit tests and UI test build (set RUN_UI_TESTS=1 to run UI tests)"
fi

echo "Verification passed: localization, $ui_test_result, Debug/Release builds, analyze, arm64, macOS 13, and LSUIElement."
