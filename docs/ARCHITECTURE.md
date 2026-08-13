# Architecture

Mutelet separates operating-system I/O from its mute state machine so safety behavior can be tested without changing a real microphone.

```text
MenuBarExtra / Settings / HUD / persistent status
              |
              v
  MuteletApplicationModel
       |              |
       v              v
MuteCoordinator   Carbon hot key / login item / preferences
       |
       v
AudioDeviceControlling
       |
       v
 Core Audio properties and event listeners
```

## Components

- `CoreAudioDeviceController` enumerates input devices, inspects controls, reads snapshots, and performs mute or restoration writes.
- `MuteCoordinator` owns the selected mode and target, aggregates state, serializes transitions, and enforces Push to Talk safety.
- `CarbonHotKeyMonitor` registers a system hot key and publishes press/release events without an event tap.
- `MuteletApplicationModel` joins app lifecycle, persisted settings, UI commands, HUD, login item, and global hot-key handling on the main actor.
- `StatusOverlayController` owns one non-activating floating panel, resolves physical displays by Core Graphics UUID, and converts its draggable position to normalized coordinates. It subscribes to coordinator state through the application model but does not share the transient HUD's window or lifetime.
- `AudioMutationReceiptStoring` persists the exact values to restore before Core Audio is mutated. Restoration receipts are removed only after a read-back verifies every saved control.

## Identity and concurrency

Core Audio `AudioObjectID` values are process-local, temporary references. Mutelet persists device UIDs and resolves the current object again after hardware changes or wake.

The controller keeps a process-local device inventory only while Core Audio's device-list, default-input, stream-configuration, control-list, device-change, and name revisions are unchanged. Degraded enumeration results are never cached. Cached object IDs are checked against their device UID before control access and are discarded and resolved again on a mismatch. Device-control and topology listeners are synchronized by identity and address, adding replacements before removing obsolete registrations.

Core Audio operations are isolated behind an actor-conforming interface. Published UI state and mode transitions live on `@MainActor`. The coordinator uses generations and awaited transitions to prevent an older asynchronous selection from overwriting a newer one.

## Security boundary

The app target enables both App Sandbox and Hardened Runtime. It does not request audio-input or network entitlements: microphone muting reads and writes Core Audio control properties without opening an input stream, and all application data remains local. Release and verification scripts inspect the signed application to prevent these entitlement constraints from regressing.

## State model

The visible states are:

- `live`: at least one relevant control is audible and none conflict;
- `muted`: mute or zero-volume controls confirm silence;
- `mixed`: controls within one target or states across several targets disagree;
- `unavailable` / `disconnected`: no current target can be resolved;
- `unsupported`: no writable mute strategy exists;
- `partial`: an all-input state includes unsupported devices or operation/read failures;
- `error`: an operation could not produce a trustworthy state.

Mixed state toggles toward mute. Unsupported and failed targets are never folded into a confirmed muted state.

## Push to Talk safety

Selecting Push to Talk immediately requests mute. Key down restores the prior state for speech; key up uses a safety path that resolves the current target and requests mute without trusting cached UI state. Repeated key-down events do not invert state. Changing the shortcut cancels an active gesture and remutes before replacing the registration. App termination waits for a safe mute; a workspace sleep notification queues the same request on a best-effort basis, and wake is serialized after it.

Core Audio device-list and default-input events trigger inventory refreshes. Bursts of control-value events are coalesced and filtered to the current target before state is read back. Push to Talk remutes promptly when that read-back finds an externally unmuted target, without rewriting controls that are already confirmed muted.

## Toggle mute maintenance

When enabled, a successful Toggle mute creates a process-local mute intent. Device-list, default-input, topology, readiness, and relevant control events are treated as invalidation signals rather than an ordered event log. A generation-scoped reconciliation worker resolves the latest semantic target to device UIDs, re-resolves each temporary AudioObjectID, reads the current controls, and only writes when the target is not already muted.

New targets are read back as muted before former targets are restored from receipts. Disconnected former targets remain pending until the same UID reconnects. Persisted receipts are restoration records rather than mute intent, so explicit unmute and target-change operations may restore a receipt from an earlier app session. If saved controls disappeared, the stale receipt is discarded with a warning so it cannot permanently block future control; newly added controls do not prevent the saved controls from being restored. Reconciliation retries after 100, 300, and 600 milliseconds, then waits for another Core Audio event.

Sleep suspends listeners and workers while retaining the process-local intent; wake resumes from a fresh inventory. Shutdown discards the intent. Persisted receipts protect restoration after failures, but are never interpreted as a mute intent on the next launch.

The HUD intentionally appears once when entering Push to Talk, not on every press and release. Toggle mode continues to show state feedback for each action.

The persistent status can optionally invoke the same toggle command, but only in Toggle mode while the coordinator is actionable and idle. Passive status refreshes do not announce through VoiceOver. A click result is announced by either the transient HUD or the persistent status, never both.

## Testing

Core tests use fake audio and persistence implementations. UI tests launch the app with `--ui-testing`, which swaps in deterministic devices and disables system hot-key and login-item integration. The `mutelet-probe` executable remains available for explicit, manual Core Audio diagnostics.
