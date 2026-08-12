# Changelog

All notable user-visible changes to Mutelet will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project intends to use [Semantic Versioning](https://semver.org/spec/v2.0.0.html) after its first public release.

## [Unreleased]

### Added

- Configurable HUD size, position, display target, duration, and manual preview.
- Optional session mute maintenance across default-input changes, device reconnection, external unmute attempts, and sleep/wake.

## [0.1.0] - 2026-08-11

### Added

- Apple Silicon-native macOS menu bar app targeting macOS 14 and later.
- Toggle and Push to Talk modes with a configurable global shortcut.
- System-default, individual-device, and all-input targeting.
- Native mute plus writable input-volume controls, with volume-only fallback and safe value restoration.
- Settings, HUD feedback, launch at login, and English/Japanese localization.
- Write-ahead restoration receipts, verified restoration, and fail-safe Push to Talk remuting.
- Debug-only UI test dependencies and release checks that reject test switches.
- Original application icon and complete macOS icon-size asset catalog.
- Modern settings and menu bar presentation, with macOS 14 Sonoma as the minimum supported release.
