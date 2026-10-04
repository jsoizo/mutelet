# Changelog

All notable user-visible changes to Mutelet will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project intends to use [Semantic Versioning](https://semver.org/spec/v2.0.0.html) after its first public release.

## [Unreleased]

### Added

- Standalone F1–F20 shortcut support, with mode-specific shortcut settings: **Control + Shift + M** for Toggle and **F8** for Push to Talk so typing can continue while the key is held.
- Configurable HUD size, position, display target, duration, and manual preview.
- Optional session mute maintenance across default-input changes, device reconnection, external unmute attempts, and sleep/wake.
- Optional screen edge indicator that glows the display borders while Push to Talk can carry sound, replacing the transient HUD for those gestures.

### Changed

- The former single-shortcut preference migrates into the saved mode’s shortcut slot; the other mode receives its recommended default. Untouched schema 5-or-earlier Push to Talk **Control + Shift + M** defaults migrate to **F8**; schema 6 values are preserved as user selections.
- Push to Talk shows HUD feedback on every press and release instead of only when the mode is selected.
- Automatic mute maintenance reports its result immediately instead of delaying the HUD, and repeats of what the HUD already shows are dropped.

### Fixed

- An input that is already silent because its volume is zero is no longer reported as muted when Mutelet has no saved value for it. Mutelet reports that the input is silenced outside its control and leaves the shortcut inactive instead of claiming a mute it cannot undo.
- A restoration without a saved value is read back, so an input that stays silent after the write is reported as a failure instead of appearing to succeed.
- In Push to Talk, a different input can now be selected while the current one is disconnected. A target that resolves to no device cannot carry sound, so it no longer blocks the change, and the input it replaces is restored instead of being left muted.
- A disconnected input is reported as disconnected instead of as a microphone that could not be controlled.
- Changing the shortcut while the key is held no longer fails when the selected input is disconnected.
- In Push to Talk, a different input can now be selected while the current one has no mute control, and that input keeps being reported as unsupported instead of as a microphone that could not be controlled.
- An input Core Audio reports without a readable identity no longer makes the selected input look disconnected. Mutelet reports that the input could not be read, so the state stays distinguishable from an input that was unplugged.

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
