#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
catalog="$repository_root/Sources/Mutelet/Resources/Localizable.xcstrings"

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required to validate Localizable.xcstrings" >&2
    exit 1
fi

python3 - "$catalog" <<'PYTHON'
import json
import sys

class DuplicateKeyError(ValueError):
    pass

def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(key)
        result[key] = value
    return result

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as file:
        json.load(file, object_pairs_hook=reject_duplicate_keys)
except DuplicateKeyError as error:
    print(f"error: duplicate localization key: {error.args[0]}", file=sys.stderr)
    sys.exit(1)
except (OSError, json.JSONDecodeError) as error:
    print(f"error: invalid Localizable.xcstrings JSON: {error}", file=sys.stderr)
    sys.exit(1)
PYTHON

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
