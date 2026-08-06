# Mutelet

Mutelet is an open-source, Apple Silicon-native microphone mute utility for the macOS menu bar.

> Mutelet is under active development. The first signed and notarized release is not available yet.

[日本語](README.ja.md)

## Features

- Toggle the system default input, one selected input, or all inputs.
- Hold a global shortcut to talk with Push to Talk.
- Set writable native mute and input-volume controls together; use volume-only fallback when native mute is unavailable.
- Follow default-device changes, reconnect selected devices by UID, and report partial failures.
- Configure the shortcut, HUD, target, mode, and launch-at-login behavior without editing files.
- Run natively on Apple Silicon without Rosetta.

Mutelet does not record audio, connect to a server, collect telemetry, or request Microphone, Accessibility, or Input Monitoring permission. See [Privacy](docs/PRIVACY.md) for details.

## Requirements

- Apple Silicon Mac
- macOS 14 Sonoma or later

## Download

Signed and notarized builds will be published on the repository's **Releases** page. Until the first release, build Mutelet from source.

## Build from source

Install the current stable Xcode, then run:

```bash
git clone <repository-url>
cd mutelet
open Mutelet.xcodeproj
```

Select the `Mutelet` scheme and run it on **My Mac**. The microphone icon appears in the menu bar; Mutelet has no Dock icon.

For command-line verification:

```bash
swift test
./scripts/verify.sh
```

`verify.sh` writes derived build products under `.build/` and does not apply a distribution signature. It ad-hoc signs only the UI-test host and runner so macOS can execute them.
It builds the UI tests without interrupting a Mutelet instance you may be using. Quit Mutelet and run `RUN_UI_TESTS=1 ./scripts/verify.sh` to execute them locally; CI executes them on every change.

## Usage

The default shortcut is **Control + Shift + M**.

- **Toggle:** press once to mute and once again to restore the previous state.
- **Push to Talk:** the input is muted while idle; hold the shortcut to talk and release it to mute again.

Open the menu bar item to choose a mode or input. Open **Settings…** to change the shortcut, HUD, and launch-at-login behavior.

When a device has no native mute control, Mutelet may silence it by setting writable input volumes to zero. Some hardware or software may bypass those controls, so the UI reports that limitation instead of claiming a guaranteed mute. See [Device compatibility](docs/DEVICE_COMPATIBILITY.md).

## How it works

Mutelet talks directly to Core Audio control properties. It never opens an audio stream. Before changing volume-based controls, it stores their values per device UID and channel so they can be restored safely.

## FAQ

### Why does Mutelet show a warning for my input?

The input may expose only volume controls, expose no writable controls, be disconnected, or be one of several inputs where an operation partially failed. The menu keeps those cases distinct from a confirmed mute.

### Why is Push to Talk muted immediately after I select it?

That is the safe idle state. Hold the configured shortcut while speaking. Releasing it returns the target to mute. On sleep notification Mutelet makes a best-effort mute request; quitting waits for that request to finish.

### Does it need special permissions?

No. Mutelet controls Core Audio properties and registers a Carbon global hot key. It does not install an event tap or capture microphone audio.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [Architecture](docs/ARCHITECTURE.md), and [Security policy](SECURITY.md).

## License

Mutelet is available under the [MIT License](LICENSE).
