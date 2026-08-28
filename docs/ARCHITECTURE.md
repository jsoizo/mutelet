# Architecture

Mutelet separates operating-system I/O from its mute state machine so safety behavior can be tested without changing a real microphone.

```text
MenuBarExtra / Settings / HUD / persistent status / screen edge
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
- `ScreenEdgeIndicatorController` owns one click-through panel per screen and glows the display borders while Push to Talk can carry sound. Its panels are built when the mode is selected rather than when a gesture starts, and it asks the window server to keep them out of screen captures.
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
- `unavailable` / `disconnected`: no current target can be resolved, and every input Core Audio reported has a readable identity;
- `unsupported`: no writable mute strategy exists;
- `externallySilenced`: the target is silent for a reason Mutelet did not cause, typically a zero input volume, and no receipt exists to undo it;
- `partial`: an all-input state includes unsupported devices or operation/read failures;
- `error`: an operation could not produce a trustworthy state, or an input without a readable identity leaves the target unresolvable rather than absent.

Mixed state toggles toward mute. Unsupported, externally silenced, and failed targets are never folded into a confirmed muted state. A restoration without a receipt is read back, so an input that stays silent after the write is reported as a failure rather than a success.

## Push to Talk safety

Selecting Push to Talk immediately requests mute. Key down restores the prior state for speech; key up uses a safety path that resolves the current target and requests mute without trusting cached UI state. Repeated key-down events do not invert state. Changing the shortcut cancels an active gesture and remutes before replacing the registration. App termination waits for a safe mute; a workspace sleep notification queues the same request on a best-effort basis, and wake is serialized after it. A target that cannot be muted at all, because it resolves to no device or has no mute control, never blocks a target change or a shortcut change; a failure to read the inventory still does.

Core Audio device-list and default-input events trigger inventory refreshes. Bursts of control-value events are coalesced and filtered to the current target before state is read back. Push to Talk remutes promptly when that read-back finds an externally unmuted target, without rewriting controls that are already confirmed muted.

## Toggle mute maintenance

When enabled, a successful Toggle mute creates a process-local mute intent. Device-list, default-input, topology, readiness, and relevant control events are treated as invalidation signals rather than an ordered event log. A generation-scoped reconciliation worker resolves the latest semantic target to device UIDs, re-resolves each temporary AudioObjectID, reads the current controls, and only writes when the target is not already muted.

New targets are read back as muted before former targets are restored from receipts. Disconnected former targets remain pending until the same UID reconnects. Persisted receipts are restoration records rather than mute intent, so explicit unmute and target-change operations may restore a receipt from an earlier app session. If saved controls disappeared, the stale receipt is discarded with a warning so it cannot permanently block future control; newly added controls do not prevent the saved controls from being restored. Reconciliation retries after 100, 300, and 600 milliseconds, then waits for another Core Audio event. A target that resolves to no device is reported as disconnected or unavailable instead of being retried, and pending restorations still run while it stays that way. An input with no mute control is still retried, because capabilities can be momentarily unreadable, but it keeps its unsupported status instead of being reported as uncontrollable. A restoration pass is skipped rather than run against an unknown target set when the inventory cannot be read.

Sleep suspends listeners and workers while retaining the process-local intent; wake resumes from a fresh inventory. Shutdown discards the intent. Persisted receipts protect restoration after failures, but are never interpreted as a mute intent on the next launch.

The HUD reports state for every hot-key press, and in Push to Talk also on release because release changes state. When the screen edge indicator is enabled, Push to Talk gestures show the edge instead of the HUD. Those gestures report nothing themselves, because a release returns before the remute settles; the VoiceOver announcement and the record that stops an automatic remute from repeating it both follow the status the edge is showing. Warnings such as a failed restoration keep using the HUD, which the edge cannot express. Entering Push to Talk announces the shortcut once. Automatic maintenance results are matched by content against the last HUD presentation and dropped when they repeat it within two seconds, so a remute confirming what a press already showed never appears, while a result for another device or a new restoration failure does.

The persistent status can optionally invoke the same toggle command, but only in Toggle mode while the coordinator is actionable and idle. Passive status refreshes do not announce through VoiceOver. A click result is announced by either the transient HUD or the persistent status, never both.

## Testing

Core tests use fake audio and persistence implementations. UI tests launch the app with `--ui-testing`, which swaps in deterministic devices and disables system hot-key and login-item integration. The `mutelet-probe` executable remains available for explicit, manual Core Audio diagnostics.
