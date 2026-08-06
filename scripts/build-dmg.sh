#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 /path/to/Mutelet.app /path/to/Mutelet-version.dmg" >&2
    exit 64
fi

app_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
output_parent="$(dirname "$2")"
mkdir -p "$output_parent"
output_directory="$(cd "$output_parent" && pwd)"
output_dmg="$output_directory/$(basename "$2")"

if [[ ! -d "$app_path" || "$(basename "$app_path")" != "Mutelet.app" ]]; then
    echo "error: first argument must be an existing Mutelet.app" >&2
    exit 66
fi

staging_directory="$(mktemp -d "${TMPDIR:-/tmp}/mutelet-dmg.XXXXXX")"
cleanup() {
    rm -rf "$staging_directory"
}
trap cleanup EXIT

ditto "$app_path" "$staging_directory/Mutelet.app"
ln -s /Applications "$staging_directory/Applications"

hdiutil create \
    -volname Mutelet \
    -srcfolder "$staging_directory" \
    -format UDZO \
    -ov \
    "$output_dmg"

(
    cd "$output_directory"
    shasum -a 256 "$(basename "$output_dmg")" > "$(basename "$output_dmg").sha256"
)

echo "Created $output_dmg"
echo "Created $output_dmg.sha256"
