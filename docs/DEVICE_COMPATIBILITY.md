# Device compatibility

Core Audio devices expose different control surfaces. Mutelet inspects each input and chooses the safest available strategy.

| Capability | Mutelet behavior | Guarantee |
| --- | --- | --- |
| Writable native mute | Set native mute and writable input volumes | Best supported software mute |
| Writable master input volume | Save its value, set it to zero, then restore it | Volume fallback; bypass may be possible |
| Writable channel volumes | Save each value, set them to zero, then restore them | Volume fallback; bypass may be possible |
| No writable mute or volume | Do not claim mute; show unsupported | No mute operation |
| Already silent by zero volume, nothing saved | Report it as silenced outside Mutelet; leave the shortcut inactive | No restoration |
| Several inputs with mixed results | Show partial counts and warning | No all-input guarantee |

Mutelet never treats an unsupported or failed device as successfully muted.
Per-channel controls must cover every input channel, using native mute, writable volume, or a combination of both. Partial channel coverage is reported as unsupported instead of muted.

An input that is already silent because its volume is zero has no way back. Mutelet never writes a
volume the user did not choose, and clearing native mute cannot wake an input a zero volume silenced.
Such an input is reported as silenced outside Mutelet instead of muted, and the shortcut stays
inactive until the volume is raised outside Mutelet. Raising it returns the input to the normal live
state. Silence that clearing native mute only partially lifts does not count: the input becomes
audible again on the released channels and stays controllable.

A Mutelet mute is undone from the value it saved. If that record is lost, for example when a control
topology change discards it, the input becomes indistinguishable from silence Mutelet did not cause
and is reported the same way.

## Selection and reconnection

- **System Default** follows the current macOS default input.
- A selected device is persisted by UID. If disconnected, Mutelet waits for the same UID rather than silently controlling another input.
- **All Inputs** aggregates every currently visible input. If a new input appears while the all-input mute latch is active, Mutelet attempts to mute it too.
- With **Keep muted when input changes** enabled, a Toggle mute follows a new system default and reconnecting device UIDs for the rest of the running app session. Core Audio notification order is not assumed; Mutelet re-enumerates and verifies the final state.
- If saved controls disappear from a reconnecting UID, Mutelet reports the restoration failure and discards the stale receipt so future operations are not permanently blocked. Newly added controls do not prevent restoration of the saved controls.

Aggregate devices, virtual inputs, USB interfaces, Bluetooth devices, and conferencing drivers may expose unusual or read-only controls. They should not crash Mutelet, but their ability to mute varies.

## Test matrix

The initial release was accepted with the verification scope below. The pending entries are unrecorded combinations, not reported failures. They do not imply that the full matrix passed.

- Local sandbox verification on a MacBook Air (Mac14,2), macOS 26.2: input enumeration, built-in microphone native mute, input-volume write/restore, and the configured Toggle shortcut passed. See [#26](https://github.com/jsoizo/mutelet/issues/26) for the detailed Stage 1 results and log observations.
- TestFlight 1.0.0 (1) was installed and tried by the maintainer, who reported no apparent problem. A detailed list of devices, OS versions, and operations was not recorded. The maintainer accepted this scope in [#32](https://github.com/jsoizo/mutelet/issues/32).
- App Store 1.0.0 (1) and Developer ID 1.0.0 (3) use source `5c7cca1c9a1075aa1804d1502851875b2976bd7d`. Bundle ID `app.mutelet.Mutelet`, Team ID `6JQRVRW544`, arm64, macOS 14+, and App Sandbox were verified in the distribution artifacts. Neither has microphone-capture or network entitlements. See [#29](https://github.com/jsoizo/mutelet/issues/29).

The two distributions use the same app identity. Settings and restoration receipts are stored locally, but detailed channel-switching results were not recorded. Restore muted inputs before replacement and check settings, shortcuts, and launch at login afterward, as described in the [README](../README.md#switching-distribution-channels).

| Device | Connection | macOS | Controls | Toggle | Push to Talk | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| MacBook Air (Mac14,2) built-in microphone | Internal | 26.2 (25C56) | Native mute and input volume | Pass (local sandbox build) | Not recorded | Stage 1 in #26; TestFlight per-device result not recorded |
| AirPods | Bluetooth | Pending | Pending | Pending | Pending | Reconnect and latency testing required |
| USB audio input | USB | Pending | Pending | Pending | Pending | Channel-layout testing required |

When reporting results, include the exact device name shown by macOS, macOS version, connection type, and whether Mutelet displayed a volume-only warning.

## Persistent status presentation checks

Before a release, manually verify the persistent status on macOS 14 and the latest stable macOS:

- Move it within one display and across two displays, then restart Mutelet and confirm the display and position are restored.
- Disconnect the selected display, confirm fallback to the primary display at the same relative position, reconnect it, and confirm the saved display is restored.
- Change resolution, display scaling, Dock position, menu bar placement, and the primary display; the full panel must remain inside the visible frame with its 12-point margin.
- Switch normal Spaces, enter a standard full-screen Space, and use Mission Control and Stage Manager; the panel should remain visible without joining the normal window switcher or stealing keyboard focus.
- Verify both content styles and all three sizes against light and dark backgrounds.
- Enable Reduce Motion and Reduce Transparency and confirm immediate state/visibility changes and an opaque system background respectively.
- Confirm click-to-toggle works only in Toggle mode and that dragging, Push to Talk, busy operations, and non-actionable states never toggle the microphone.
