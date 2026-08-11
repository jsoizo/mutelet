# Releasing

Releases are arm64-only, signed with Developer ID, notarized by Apple, stapled, and distributed as a DMG with a SHA-256 checksum.

## Prerequisites

- A clean checkout on an Apple Silicon Mac
- Current stable Xcode selected by `xcode-select`
- A valid `Developer ID Application` certificate in the keychain
- Apple notarization credentials
- A 1Password account with access to the release items described below
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

## Test the release workflow

To exercise the complete signing, notarization, packaging, and upload path before the final release, push a prerelease tag whose numeric prefix matches `MARKETING_VERSION`:

```bash
git tag -a v0.1.0-beta.1 -m "Mutelet 0.1.0 beta 1"
git push origin v0.1.0-beta.1
```

The workflow builds an app with version `0.1.0` and publishes the tagged release as a GitHub prerelease named `0.1.0-beta.1`. After validating the release and its downloaded DMG, remove the test release and both copies of the tag:

```bash
gh release delete v0.1.0-beta.1 --cleanup-tag --yes
git tag -d v0.1.0-beta.1
```

Deleting the release does not erase the GitHub Actions run or Apple's notarization history.

## GitHub Actions credentials

1Password is the source of truth for Apple release credentials. The release workflow loads these fields:

| 1Password reference | Value |
| --- | --- |
| `op://Mutelet Dev/Developer-ID/application-certificate-b64` | Base64-encoded Developer ID Application `.p12` |
| `op://Mutelet Dev/Developer-ID/certificate-password` | Password used when exporting the `.p12` |
| `op://Mutelet Dev/Developer-ID/signing-identity` | Full `Developer ID Application: Name (TEAM_ID)` identity |
| `op://Mutelet Dev/Developer-ID/team-id` | Apple Developer Team ID |
| `op://Mutelet Dev/App-Store-Connect/auth-key-b64` | Base64-encoded App Store Connect team API `.p8` key |
| `op://Mutelet Dev/App-Store-Connect/key-id` | App Store Connect API key ID |
| `op://Mutelet Dev/App-Store-Connect/issuer-id` | App Store Connect API issuer ID |

Use Mutelet-specific Apple credentials instead of copying credentials from another project's items. Create a 1Password service account for Mutelet with read-only access to the `Mutelet Dev` vault. Store only its token as the `OP_SERVICE_ACCOUNT_TOKEN` secret in the protected GitHub `release` environment. Rotate or revoke this service account independently from other projects.

## Publish

1. Inspect and install the stapled DMG on a clean user account.
2. Verify Toggle, Push to Talk, settings, login item approval, sleep/wake, and quit safety with real hardware.
3. Commit the version and release-note changes.
4. Create and push an annotated `v<version>` tag.
5. Confirm the protected `release` environment is approved and the release workflow publishes the DMG, checksum, and notarization logs.

Before enabling the tag workflow, configure its 1Password service account and `OP_SERVICE_ACCOUNT_TOKEN` environment secret, protect `v*` tags, configure required reviewers for the `release` environment, and enable private vulnerability reporting or publish a private security contact. GitHub-hosted artifacts are not a substitute for manually checking the final stapled download.
