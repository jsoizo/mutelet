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

## Selection and reconnection

- **System Default** follows the current macOS default input.
- A selected device is persisted by UID. If disconnected, Mutelet waits for the same UID rather than silently controlling another input.
- **All Inputs** aggregates every currently visible input. If a new input appears while the all-input mute latch is active, Mutelet attempts to mute it too.

Aggregate devices, virtual inputs, USB interfaces, Bluetooth devices, and conferencing drivers may expose unusual or read-only controls. They should not crash Mutelet, but their ability to mute varies.

## Test matrix

The compatibility table will be populated as physical testing is completed.

| Device | Connection | macOS | Controls | Toggle | Push to Talk | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Mac built-in microphone | Internal | Pending | Pending | Pending | Pending | Manual verification required |
| AirPods | Bluetooth | Pending | Pending | Pending | Pending | Reconnect and latency testing required |
| USB audio input | USB | Pending | Pending | Pending | Pending | Channel-layout testing required |

When reporting results, include the exact device name shown by macOS, macOS version, connection type, and whether Mutelet displayed a volume-only warning.
