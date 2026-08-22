import CoreAudio
import Foundation

public enum CoreAudioError: Error, Sendable, CustomStringConvertible {
    case operationFailed(operation: String, status: OSStatus)
    case missingProperty(operation: String)
    case deviceNotFound(uid: String)
    case unsupportedDevice(uid: String)
    case missingRestoration(uid: String)
    case invalidRestoration(expectedUID: String, actualUID: String)
    case restorationTopologyChanged(uid: String)
    case incompleteRestoration(uid: String)
    case staleSnapshot(uid: String)
    case muteNotConfirmed(uid: String)

    public var description: String {
        switch self {
        case let .operationFailed(operation, status):
            return "\(operation) failed with OSStatus \(status)"
        case let .missingProperty(operation):
            return "Required Core Audio property is unavailable while \(operation)"
        case let .deviceNotFound(uid):
            return "No connected input device has UID \(uid)"
        case let .unsupportedDevice(uid):
            return "Input device \(uid) has no writable mute or volume control"
        case let .missingRestoration(uid):
            return "Input device \(uid) is volume-only and has no saved volume to restore"
        case let .invalidRestoration(expectedUID, actualUID):
            return "Saved volume belongs to \(actualUID), not \(expectedUID)"
        case let .restorationTopologyChanged(uid):
            return "Saved input controls for \(uid) no longer match the available controls"
        case let .incompleteRestoration(uid):
            return "Not every saved input control for \(uid) could be restored and verified"
        case let .staleSnapshot(uid):
            return "Input controls for \(uid) changed before they could be muted"
        case let .muteNotConfirmed(uid):
            return "Input device \(uid) did not report a muted state after the write"
        }
    }
}
