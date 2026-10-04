# Privacy

Mutelet is designed to mute microphones without consuming microphone audio.

## Data access

Mutelet:

- reads input-device names, stable UIDs, channel counts, mute controls, and volume controls through Core Audio;
- writes only supported mute and input-volume control values;
- stores settings and pre-mute restoration values locally in `UserDefaults`;
- registers the active mode’s configured shortcut with the macOS Carbon hot-key API; standalone F1–F20 keys are consumed by that registration and are not delivered to the focused app.

Mutelet does not:

- open an audio input stream or record audio;
- request Microphone, Accessibility, or Input Monitoring permission;
- send network requests;
- collect analytics, telemetry, crash reports, or identifiers;
- include advertising or third-party tracking SDKs.

The app runs inside the macOS App Sandbox without audio-input or network client/server entitlements. This enforces the application boundary without granting access to microphone audio or network communication.

## Local data

Preferences include the selected mode, input UID and display name, mode-specific shortcut choices, and HUD display choices. Migration records no keystrokes; it only maps the former single shortcut into the saved mode’s slot and applies defined defaults to the other mode. Launch at login is managed separately by macOS through `SMAppService`. Restoration receipts contain only device UIDs and numeric control values. They do not contain audio.

Removing Mutelet does not automatically delete its `UserDefaults` domain. Users may remove that local preference data with:

```bash
defaults delete app.mutelet.Mutelet
```

That command also removes saved volume restoration values, so do not run it while relying on Mutelet to restore a volume-based mute.
