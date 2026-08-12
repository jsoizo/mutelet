import CoreAudio
import Foundation

public struct AudioDeviceDescriptor: Hashable, Sendable {
    public let objectID: AudioObjectID
    public let uid: String
    public let name: String
    public let inputChannelCount: UInt32
    public let isDefaultInput: Bool
    public let capabilities: AudioDeviceCapabilities

    public init(
        objectID: AudioObjectID,
        uid: String,
        name: String,
        inputChannelCount: UInt32,
        isDefaultInput: Bool,
        capabilities: AudioDeviceCapabilities
    ) {
        self.objectID = objectID
        self.uid = uid
        self.name = name
        self.inputChannelCount = inputChannelCount
        self.isDefaultInput = isDefaultInput
        self.capabilities = capabilities
    }
}

public enum AudioControlKind: String, Codable, Hashable, Sendable {
    case mute
    case volume
}

public struct AudioControl: Codable, Hashable, Sendable {
    public let kind: AudioControlKind
    public let element: UInt32

    public init(kind: AudioControlKind, element: UInt32) {
        self.kind = kind
        self.element = element
    }

    public var isMain: Bool {
        element == kAudioObjectPropertyElementMain
    }
}

public struct AudioDeviceCapabilities: Hashable, Sendable {
    public let nativeMuteControls: [AudioControl]
    public let volumeControls: [AudioControl]
    public let coversAllInputChannels: Bool

    public init(
        nativeMuteControls: [AudioControl],
        volumeControls: [AudioControl],
        coversAllInputChannels: Bool = true
    ) {
        self.nativeMuteControls = nativeMuteControls
        self.volumeControls = volumeControls
        self.coversAllInputChannels = coversAllInputChannels
    }

    public var isSupported: Bool {
        coversAllInputChannels && (!nativeMuteControls.isEmpty || !volumeControls.isEmpty)
    }

    public var usesVolumeFallbackOnly: Bool {
        isSupported && nativeMuteControls.isEmpty && !volumeControls.isEmpty
    }
}

public struct AudioControlValue: Codable, Hashable, Sendable {
    public let control: AudioControl
    public let value: Float

    public init(control: AudioControl, value: Float) {
        self.control = control
        self.value = value
    }
}

public enum AudioDeviceMuteState: String, Sendable {
    case live
    case muted
    case mixed
    case unsupported
}

public struct AudioDeviceSnapshot: Hashable, Sendable {
    public let device: AudioDeviceDescriptor
    public let values: [AudioControlValue]

    public init(device: AudioDeviceDescriptor, values: [AudioControlValue]) {
        self.device = device
        self.values = values
    }

    public var muteState: AudioDeviceMuteState {
        guard device.capabilities.isSupported else { return .unsupported }

        let muteValues = values
            .filter { $0.control.kind == .mute }
            .map(\.value)
        let volumeValues = values
            .filter { $0.control.kind == .volume }
            .map(\.value)

        let allNativeMuted = !muteValues.isEmpty && muteValues.allSatisfy { $0 >= 0.5 }
        let mixedNativeMute = muteValues.contains { $0 >= 0.5 } && muteValues.contains { $0 < 0.5 }
        let allVolumeZero = !volumeValues.isEmpty && volumeValues.allSatisfy { $0 <= 0.0001 }
        let mixedVolume = volumeValues.contains { $0 <= 0.0001 } && volumeValues.contains { $0 > 0.0001 }

        if allNativeMuted || allVolumeZero {
            return .muted
        }
        if mixedNativeMute || mixedVolume {
            return .mixed
        }
        return .live
    }
}

public struct AudioMutationReceipt: Codable, Hashable, Sendable {
    public let deviceUID: String
    public let originalValues: [AudioControlValue]

    public init(deviceUID: String, originalValues: [AudioControlValue]) {
        self.deviceUID = deviceUID
        self.originalValues = originalValues
    }

    public func hasSameControls(as values: [AudioControlValue]) -> Bool {
        let savedControls = Set(originalValues.map(\.control))
        let currentControls = Set(values.map(\.control))
        return savedControls.count == originalValues.count
            && currentControls.count == values.count
            && savedControls == currentControls
    }
}

public enum AudioHardwareEventKind: String, Sendable {
    case deviceListChanged
    case defaultInputChanged
    case controlValueChanged
}

public struct AudioHardwareEvent: Sendable {
    public let kind: AudioHardwareEventKind
    public let objectID: AudioObjectID
    public let deviceUID: String?
    public let selector: AudioObjectPropertySelector
    public let element: AudioObjectPropertyElement

    public init(
        kind: AudioHardwareEventKind,
        objectID: AudioObjectID,
        deviceUID: String? = nil,
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) {
        self.kind = kind
        self.objectID = objectID
        self.deviceUID = deviceUID
        self.selector = selector
        self.element = element
    }
}
