# Releasing

Releases are arm64-only, signed with Developer ID, notarized by Apple, stapled, and distributed as a DMG with a SHA-256 checksum.

## Prerequisites

- A clean checkout on an Apple Silicon Mac
- Current stable Xcode selected by `xcode-select`
- A valid `Developer ID Application` certificate in the keychain
- Apple notarization credentials
- `jq` and GitHub CLI (`gh`)

Never commit certificates, passwords, API private keys, or keychain files.

## Prepare

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Move relevant entries from `Unreleased` in `CHANGELOG.md` and finalize `changelogs/<version>.md`.
3. Quit any running Mutelet instance and run `RUN_UI_TESTS=1 ./scripts/verify.sh`.
4. Complete the device matrix and manual checks in `docs/DEVICE_COMPATIBILITY.md` on macOS 14 and the latest stable macOS.

## Local notarization credentials

Store credentials in the login keychain once:

```bash
xcrun notarytool store-credentials mutelet-notary \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Then create a release artifact:

```bash
DEVELOPMENT_TEAM="TEAM_ID" \
DEVELOPER_ID_APPLICATION="Developer ID Application: Example (TEAM_ID)" \
NOTARY_PROFILE="mutelet-notary" \
./scripts/release.sh 0.1.0
```

The script archives the app, verifies its architecture and signature, builds `dist/Mutelet-<version>.dmg`, submits it with `notarytool`, staples the ticket, validates it, and writes `dist/Mutelet-<version>.dmg.sha256`.

For API-key notarization in CI, set `NOTARY_KEY`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID` instead of `NOTARY_PROFILE`.

## Publish

1. Inspect and install the stapled DMG on a clean user account.
2. Verify Toggle, Push to Talk, settings, login item approval, sleep/wake, and quit safety with real hardware.
3. Commit the version and release-note changes.
4. Create and push an annotated `v<version>` tag.
5. Confirm the protected `release` environment is approved and the release workflow publishes the DMG, checksum, and notarization logs.

The tag workflow expects the GitHub Actions secrets documented in `.github/workflows/release.yml`. Before enabling it, protect `v*` tags, configure required reviewers for the `release` environment, and enable private vulnerability reporting or publish a private security contact. GitHub-hosted artifacts are not a substitute for manually checking the final stapled download.
