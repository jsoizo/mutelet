# Contributing to Mutelet

Thanks for helping improve Mutelet.

## Requirements

- Apple Silicon Mac running macOS 13 or later
- Current stable Xcode with Swift 6
- `jq` for localization validation

## Set up and verify

```bash
open Mutelet.xcodeproj
swift test
./scripts/verify.sh
```

The Xcode project is the source of truth for the app and UI tests. `Package.swift` provides fast core unit tests and the `mutelet-probe` diagnostic executable.

`verify.sh` builds UI tests by default. To execute them locally, first quit any Mutelet instance you are using and run `RUN_UI_TESTS=1 ./scripts/verify.sh`. CI always executes them.

## Project layout

```text
Sources/Mutelet/       App lifecycle, system integrations, and SwiftUI
Sources/MuteletCore/   Core Audio, state machine, hot key, and preferences
Sources/MuteletProbe/  Read-mostly Core Audio diagnostics
Tests/                 Core unit tests using fake dependencies
MuteletUITests/        UI smoke tests using launch-time fake dependencies
docs/                  Architecture, privacy, compatibility, and release docs
scripts/               Reproducible verification and release tooling
changelogs/            Release-note drafts
```

## Development guidelines

- Keep Core Audio access behind `AudioDeviceControlling` and UI-independent behavior in `MuteletCore`.
- Treat `AudioObjectID` as temporary. Persist and reconnect devices by UID.
- Never claim a confirmed mute after a partial operation or for an unsupported input.
- Keep Push to Talk fail-safe: idle, target changes, and app termination must end muted; sleep handling should make the strongest feasible best-effort mute request.
- Add or update English and Japanese entries in `Localizable.xcstrings` for user-visible text.
- Do not add microphone capture, telemetry, network access, or new permission requirements without an explicit design discussion.
- Add focused tests for state-machine and persistence changes.

## Pull requests

Keep changes focused and explain their user-visible behavior. Before opening a pull request, run `./scripts/verify.sh` and describe any hardware paths that still require manual testing.

Do not commit signing certificates, notarization keys, provisioning data, local preferences, or `.work/` notes.

## Releases

Maintainers should follow [docs/RELEASING.md](docs/RELEASING.md). Publishing requires a Developer ID Application certificate and Apple notarization credentials; normal contributors do not need either.
