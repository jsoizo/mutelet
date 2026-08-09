#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
site_directory="$(cd "$script_directory/.." && pwd)"
repository_root="$(cd "$site_directory/.." && pwd)"
asset_directory="$site_directory/src/assets"
capture_directory="/tmp/mutelet-website-assets"
result_bundle="$capture_directory/Capture.xcresult"
attachment_directory="$capture_directory/attachments"

cleanup() {
    rm -rf "$capture_directory"
}
trap cleanup EXIT

command -v ffmpeg >/dev/null || {
    echo "error: ffmpeg is required to generate website previews" >&2
    exit 1
}
command -v jq >/dev/null || {
    echo "error: jq is required to read the test attachment manifest" >&2
    exit 1
}

if [[ -e "$capture_directory" ]]; then
    echo "error: temporary capture directory already exists: $capture_directory" >&2
    exit 1
fi
mkdir -p "$capture_directory"

xcodebuild test \
    -project "$repository_root/Mutelet.xcodeproj" \
    -scheme Mutelet \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$repository_root/.build/DerivedDataSiteAssets" \
    -resultBundlePath "$result_bundle" \
    -only-testing:MuteletUITests/MuteletUITests/testCaptureWebsiteHUDAssets

xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$attachment_directory"

for language in en ja; do
    for frame in $(seq -w 0 27); do
        attachment_name="hud-$language-$frame"
        exported_file="$(jq -r --arg name "$attachment_name" '
            .. | objects
            | select(
                (.suggestedHumanReadableName? // "")
                | type == "string" and startswith($name + "_")
            )
            | .exportedFileName
        ' "$attachment_directory/manifest.json" | head -n 1)"
        if [[ -z "$exported_file" || "$exported_file" == "null" ]]; then
            echo "error: attachment not found: $attachment_name" >&2
            exit 1
        fi
        cp "$attachment_directory/$exported_file" \
            "$capture_directory/hud-$language-$frame.png"
    done

    video_filter="crop='min(1400,iw)':'min(788,ih)':(iw-ow)/2:(ih-oh)/2,scale=960:540:force_original_aspect_ratio=decrease,pad=960:540:(ow-iw)/2:(oh-ih)/2"
    ffmpeg -y -v error \
        -framerate 5 \
        -i "$capture_directory/hud-$language-%02d.png" \
        -vf "$video_filter" \
        -an \
        -c:v libx264 \
        -crf 23 \
        -pix_fmt yuv420p \
        -movflags +faststart \
        "$asset_directory/hud-$language.mp4"
    ffmpeg -y -v error \
        -i "$capture_directory/hud-$language-04.png" \
        -vf "$video_filter" \
        -frames:v 1 \
        "$asset_directory/hud-$language.png"
done
