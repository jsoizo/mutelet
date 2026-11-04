# Mutelet

Mutelet is an open-source, Apple Silicon-native microphone mute utility for the macOS menu bar.

[日本語](README.ja.md)

## Features

- Toggle the system default input, one selected input, or all inputs.
- Hold a global shortcut to talk with Push to Talk.
- Glow the screen edges while Push to Talk can carry sound, instead of showing the transient HUD.
- Set writable native mute and input-volume controls together; use volume-only fallback when native mute is unavailable.
- Follow default-device changes, reconnect selected devices by UID, and report partial failures.
- Configure separate Toggle and Push to Talk shortcuts, HUD, target, mode, and launch-at-login behavior without editing files.
- Run natively on Apple Silicon without Rosetta.

Mutelet does not record audio, connect to a server, collect telemetry, or request Microphone, Accessibility, or Input Monitoring permission. See [Privacy](docs/PRIVACY.md) for details.

## Requirements

- Apple Silicon Mac
- macOS 14 Sonoma or later

## Download

Mutelet 1.0.0 is free through either distribution channel:

- [Mac App Store](https://apps.apple.com/app/id6826858511): install and receive updates through the App Store.
- [GitHub Releases](https://github.com/jsoizo/mutelet/releases/latest): download the signed and notarized DMG, open it, and drag Mutelet to Applications. For updates, quit Mutelet and replace it with the newer download. Release pages include a SHA-256 checksum.

### Switching distribution channels

1. Restore any microphone muted by Mutelet, then quit all copies of the app.
2. Replace the existing installation in Applications with the same or a newer version from the other channel. Keep one installation and do not run copies from different paths at the same time.
3. Open Mutelet and check the selected input, mode, shortcuts, and display settings. Test the shortcut; if launch at login no longer works, turn it off and on in Settings and check its approval in macOS System Settings.

Settings and saved microphone-control values are stored locally. Do not delete that data when switching. Switching to an older version is unsupported: an older app may reset settings if it cannot read the stored settings format.

## Build from source

Install the current stable Xcode, then run:

```bash
git clone https://github.com/jsoizo/mutelet.git
cd mutelet
./scripts/build.sh
open .build/DerivedData/LocalBuild/Build/Products/Release/Mutelet.app
```

The microphone icon appears in the menu bar; Mutelet has no Dock icon.

`build.sh` produces a local Release build under `.build/`. It does not apply a distribution signature.

## Usage

Defaults are **Control + Shift + M** for Toggle and **F8** for Push to Talk.

- **Toggle:** press once to mute and once again to restore the previous state.
- **Push to Talk:** the input is muted while idle; hold the shortcut to talk and release it to mute again.

Open the menu bar item to choose a mode or input. Open **Settings…** to change either mode shortcut, HUD, and launch-at-login behavior.

When a device has no native mute control, Mutelet may silence it by setting writable input volumes to zero. Some hardware or software may bypass those controls, so the UI reports that limitation instead of claiming a guaranteed mute. See [Device compatibility](docs/DEVICE_COMPATIBILITY.md).

## How it works

Mutelet talks directly to Core Audio control properties. It never opens an audio stream. Before changing volume-based controls, it stores their values per device UID and channel so they can be restored safely.

## FAQ

### Why does Mutelet show a warning for my input?

The input may expose only volume controls, expose no writable controls, be disconnected, or be one of several inputs where an operation partially failed. The menu keeps those cases distinct from a confirmed mute.

### Why is Push to Talk muted immediately after I select it?

That is the safe idle state. Hold the configured shortcut while speaking. Releasing it returns the target to mute. On sleep notification Mutelet makes a best-effort mute request; quitting waits for that request to finish.

### Does it need special permissions?

No. Mutelet controls Core Audio properties and registers a Carbon global hot key. It does not install an event tap or capture microphone audio. A registered function key is consumed while Mutelet owns it, so it is not delivered to the focused app.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [Architecture](docs/ARCHITECTURE.md), and [Security policy](SECURITY.md).

For support, [open an issue](https://github.com/jsoizo/mutelet/issues) or email [jskmt-dev@proton.me](mailto:jskmt-dev@proton.me).

## License

Mutelet is available under the [MIT License](LICENSE).
