#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: $0 VERSION (for example, 0.1.0)" >&2
    exit 64
fi

version="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
distribution_directory="$repository_root/dist"
release_working_directory="$(mktemp -d "${TMPDIR:-/tmp}/mutelet-release.XXXXXX")"
archive_path="$release_working_directory/Mutelet.xcarchive"
app_path="$archive_path/Products/Applications/Mutelet.app"
dmg_path="$release_working_directory/Mutelet-$version.dmg"
notary_result="$release_working_directory/notary-submit.json"
notary_log="$release_working_directory/notary-log.json"

cleanup() {
    rm -rf "$release_working_directory"
}
trap cleanup EXIT

configured_version="$(xcodebuild \
    -project "$repository_root/Mutelet.xcodeproj" \
    -scheme Mutelet \
    -configuration Release \
    -showBuildSettings \
    | awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3; exit }')"
if [[ "$configured_version" != "$version" ]]; then
    echo "error: release version $version does not match MARKETING_VERSION ${configured_version:-unknown}" >&2
    exit 1
fi

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Apple Developer Team ID}"
: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the full Developer ID Application identity}"

notary_credentials=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary_credentials=(--keychain-profile "$NOTARY_PROFILE")
else
    : "${NOTARY_KEY:?Set NOTARY_PROFILE or NOTARY_KEY}"
    : "${NOTARY_KEY_ID:?Set NOTARY_KEY_ID when using NOTARY_KEY}"
    : "${NOTARY_ISSUER_ID:?Set NOTARY_ISSUER_ID when using NOTARY_KEY}"
    notary_credentials=(
        --key "$NOTARY_KEY"
        --key-id "$NOTARY_KEY_ID"
        --issuer "$NOTARY_ISSUER_ID"
    )
fi

mkdir -p "$distribution_directory"

"$script_dir/check-localizations.sh"

xcodebuild archive \
    -project "$repository_root/Mutelet.xcodeproj" \
    -scheme Mutelet \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

if [[ "$(lipo -archs "$app_path/Contents/MacOS/Mutelet")" != "arm64" ]]; then
    echo "error: archived executable must contain only arm64" >&2
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

archive_entitlements="$release_working_directory/Mutelet.entitlements.plist"
codesign -d --entitlements :- "$app_path" > "$archive_entitlements" 2>/dev/null
if [[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$archive_entitlements" 2>/dev/null || true)" != "true" ]]; then
    echo "error: archived app must be signed with App Sandbox enabled" >&2
    exit 1
fi

for forbidden_entitlement in \
    com.apple.security.device.audio-input \
    com.apple.security.network.client \
    com.apple.security.network.server; do
    if /usr/libexec/PlistBuddy -c "Print :$forbidden_entitlement" "$archive_entitlements" >/dev/null 2>&1; then
        echo "error: archived app must not include $forbidden_entitlement" >&2
        exit 1
    fi
done

archived_version="$(defaults read "$app_path/Contents/Info" CFBundleShortVersionString)"
if [[ "$archived_version" != "$version" ]]; then
    echo "error: archived app version $archived_version does not match release version $version" >&2
    exit 1
fi

"$script_dir/build-dmg.sh" "$app_path" "$dmg_path"
codesign \
    --force \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --timestamp \
    "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"

set +e
xcrun notarytool submit "$dmg_path" \
    "${notary_credentials[@]}" \
    --wait \
    --output-format json > "$notary_result"
submit_exit_code=$?
set -e

notary_status="$(plutil -extract status raw -o - "$notary_result" 2>/dev/null || true)"
submission_id="$(plutil -extract id raw -o - "$notary_result" 2>/dev/null || true)"
if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" "$notary_log" "${notary_credentials[@]}" || true
fi
cp "$notary_result" "$distribution_directory/Mutelet-$version.notary-submit.json"
if [[ -f "$notary_log" ]]; then
    cp "$notary_log" "$distribution_directory/Mutelet-$version.notary-log.json"
fi

if [[ $submit_exit_code -ne 0 || "$notary_status" != "Accepted" || -z "$submission_id" ]]; then
    echo "error: notarization was not accepted (status: ${notary_status:-unknown})" >&2
    cat "$notary_result" >&2
    if [[ -f "$notary_log" ]]; then
        cat "$notary_log" >&2
    fi
    exit 1
fi

xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

(
    cd "$release_working_directory"
    shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$dmg_path").sha256"
)

mv "$dmg_path" "$distribution_directory/"
mv "$dmg_path.sha256" "$distribution_directory/"

echo "Release artifacts are ready in $distribution_directory"
