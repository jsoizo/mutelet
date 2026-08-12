# Device compatibility

Core Audio devices expose different control surfaces. Mutelet inspects each input and chooses the safest available strategy.

| Capability | Mutelet behavior | Guarantee |
| --- | --- | --- |
| Writable native mute | Set native mute and writable input volumes | Best supported software mute |
| Writable master input volume | Save its value, set it to zero, then restore it | Volume fallback; bypass may be possible |
| Writable channel volumes | Save each value, set them to zero, then restore them | Volume fallback; bypass may be possible |
| No writable mute or volume | Do not claim mute; show unsupported | No mute operation |
| Several inputs with mixed results | Show partial counts and warning | No all-input guarantee |

Mutelet never treats an unsupported or failed device as successfully muted.
Per-channel controls must cover every input channel, using native mute, writable volume, or a combination of both. Partial channel coverage is reported as unsupported instead of muted.

## Selection and reconnection

- **System Default** follows the current macOS default input.
- A selected device is persisted by UID. If disconnected, Mutelet waits for the same UID rather than silently controlling another input.
- **All Inputs** aggregates every currently visible input. If a new input appears while the all-input mute latch is active, Mutelet attempts to mute it too.
- With **Keep muted when input changes** enabled, a Toggle mute follows a new system default and reconnecting device UIDs for the rest of the running app session. Core Audio notification order is not assumed; Mutelet re-enumerates and verifies the final state.
- If the controls exposed by a reconnecting UID no longer match its saved receipt, Mutelet keeps the receipt and reports an error instead of discarding the original values.

Aggregate devices, virtual inputs, USB interfaces, Bluetooth devices, and conferencing drivers may expose unusual or read-only controls. They should not crash Mutelet, but their ability to mute varies.

## Test matrix

The compatibility table will be populated as physical testing is completed.

| Device | Connection | macOS | Controls | Toggle | Push to Talk | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Mac built-in microphone | Internal | Pending | Pending | Pending | Pending | Manual verification required |
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
