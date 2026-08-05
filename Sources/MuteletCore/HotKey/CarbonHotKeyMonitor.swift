import Carbon
import Foundation

public enum GlobalHotKeyEvent: String, Sendable {
    case pressed
    case released
}

public struct GlobalHotKeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = GlobalHotKeyModifiers(rawValue: 1 << 0)
    public static let control = GlobalHotKeyModifiers(rawValue: 1 << 1)
    public static let option = GlobalHotKeyModifiers(rawValue: 1 << 2)
    public static let shift = GlobalHotKeyModifiers(rawValue: 1 << 3)

    var carbonValue: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}

public enum CarbonHotKeyError: Error, Sendable, CustomStringConvertible {
    case eventHandlerRegistrationFailed(OSStatus)
    case hotKeyRegistrationFailed(OSStatus)

    public var description: String {
        switch self {
        case let .eventHandlerRegistrationFailed(status):
            return "Registering the Carbon hot-key event handler failed with OSStatus \(status)"
        case let .hotKeyRegistrationFailed(status):
            return "Registering the global hot key failed with OSStatus \(status)"
        }
    }
}

@MainActor
public final class CarbonHotKeyMonitor {
    private static let hotKeySignature: OSType = 0x4D_55_54_45 // MUTE
    private static let hotKeyIdentifier: UInt32 = 1

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var continuation: AsyncStream<GlobalHotKeyEvent>.Continuation?

    public init() {}

    public func register(
        keyCode: UInt32,
        modifiers: GlobalHotKeyModifiers,
        exclusive: Bool = true
    ) throws -> AsyncStream<GlobalHotKeyEvent> {
        stop()
        try installEventHandler()

        let identifier = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )
        var reference: EventHotKeyRef?
        let options = exclusive ? OptionBits(kEventHotKeyExclusive) : OptionBits(kEventHotKeyNoOptions)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers.carbonValue,
            identifier,
            GetApplicationEventTarget(),
            options,
            &reference
        )
        guard status == noErr, let reference else {
            removeEventHandler()
            throw CarbonHotKeyError.hotKeyRegistrationFailed(status)
        }
        hotKey = reference

        return AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.stop()
                }
            }
        }
    }

    public func stop() {
        continuation?.finish()
        continuation = nil
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        removeEventHandler()
    }

    fileprivate func receive(
        eventKind: UInt32,
        signature: OSType,
        identifier: UInt32
    ) -> OSStatus {
        guard signature == Self.hotKeySignature,
              identifier == Self.hotKeyIdentifier else {
            return OSStatus(eventNotHandledErr)
        }

        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            continuation?.yield(.pressed)
            return noErr
        case UInt32(kEventHotKeyReleased):
            continuation?.yield(.released)
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func installEventHandler() throws {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            muteletCarbonHotKeyHandler,
            eventTypes.count,
            &eventTypes,
            context,
            &handler
        )
        guard status == noErr, let handler else {
            throw CarbonHotKeyError.eventHandlerRegistrationFailed(status)
        }
        eventHandler = handler
    }

    private func removeEventHandler() {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

private func muteletCarbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    var actualSize = 0
    let parameterStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        &actualSize,
        &identifier
    )
    guard parameterStatus == noErr else { return parameterStatus }

    let eventKind = GetEventKind(event)
    let signature = identifier.signature
    let hotKeyIdentifier = identifier.id
    let monitor = Unmanaged<CarbonHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated {
        monitor.receive(
            eventKind: eventKind,
            signature: signature,
            identifier: hotKeyIdentifier
        )
    }
}
