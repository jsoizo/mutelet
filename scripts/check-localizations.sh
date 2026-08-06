#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
catalog="$repository_root/Sources/Mutelet/Resources/Localizable.xcstrings"

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required to validate Localizable.xcstrings" >&2
    exit 1
fi

if ! jq -e '
    .sourceLanguage == "en"
    and (.strings | type == "object")
    and ([
        .strings
        | to_entries[]
        | select(
            .value.localizations.ja.stringUnit.state != "translated"
            or (.value.localizations.ja.stringUnit.value | type != "string")
            or (.value.localizations.ja.stringUnit.value | length == 0)
        )
    ] | length == 0)
' "$catalog" >/dev/null; then
    echo "error: every localization key must have a non-empty Japanese translation" >&2
    jq -r '
        .strings
        | to_entries[]
        | select(
            .value.localizations.ja.stringUnit.state != "translated"
            or (.value.localizations.ja.stringUnit.value | type != "string")
            or (.value.localizations.ja.stringUnit.value | length == 0)
        )
        | .key
    ' "$catalog" >&2
    exit 1
fi

echo "Localization catalog is valid (English source and complete Japanese translations)."
