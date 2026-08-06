import CoreAudio
import Foundation

enum CoreAudioPropertyAccess {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    static func hasProperty(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) -> Bool {
        var mutableAddress = address
        return AudioObjectHasProperty(objectID, &mutableAddress)
    }

    static func isSettable(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress
    ) -> Bool {
        var mutableAddress = address
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(objectID, &mutableAddress, &settable)
        return status == noErr && settable.boolValue
    }

    static func dataSize(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        operation: String
    ) throws -> UInt32 {
        var mutableAddress = address
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            objectID,
            &mutableAddress,
            0,
            nil,
            &size
        )
        guard status == noErr else {
            throw CoreAudioError.operationFailed(operation: operation, status: status)
        }
        return size
    }

    static func scalar<T: BitwiseCopyable>(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        operation: String,
        as type: T.Type = T.self
    ) throws -> T {
        var mutableAddress = address
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &mutableAddress,
            0,
            nil,
            &size,
            value
        )
        guard status == noErr else {
            throw CoreAudioError.operationFailed(operation: operation, status: status)
        }
        return value.pointee
    }

    static func array<T: BitwiseCopyable>(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        operation: String,
        as type: T.Type = T.self
    ) throws -> [T] {
        let byteCount = try dataSize(
            objectID: objectID,
            address: address,
            operation: "getting size for \(operation)"
        )
        let count = Int(byteCount) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }

        let values = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { values.deallocate() }
        var mutableAddress = address
        var mutableByteCount = byteCount
        let status = AudioObjectGetPropertyData(
            objectID,
            &mutableAddress,
            0,
            nil,
            &mutableByteCount,
            values
        )
        guard status == noErr else {
            throw CoreAudioError.operationFailed(operation: operation, status: status)
        }
        let actualCount = Int(mutableByteCount) / MemoryLayout<T>.stride
        return Array(UnsafeBufferPointer(start: values, count: actualCount))
    }

    static func setScalar<T: BitwiseCopyable>(
        _ value: T,
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        operation: String
    ) throws {
        var mutableAddress = address
        let mutableValue = UnsafeMutablePointer<T>.allocate(capacity: 1)
        mutableValue.initialize(to: value)
        defer {
            mutableValue.deinitialize(count: 1)
            mutableValue.deallocate()
        }
        let size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectSetPropertyData(
            objectID,
            &mutableAddress,
            0,
            nil,
            size,
            mutableValue
        )
        guard status == noErr else {
            throw CoreAudioError.operationFailed(operation: operation, status: status)
        }
    }

    static func string(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        operation: String
    ) throws -> String {
        var mutableAddress = address
        let value = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        value.initialize(to: nil)
        defer {
            value.deinitialize(count: 1)
            value.deallocate()
        }
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &mutableAddress,
            0,
            nil,
            &size,
            value
        )
        guard status == noErr else {
            throw CoreAudioError.operationFailed(operation: operation, status: status)
        }
        guard let unmanagedValue = value.pointee else {
            throw CoreAudioError.missingProperty(operation: operation)
        }
        return unmanagedValue.takeRetainedValue() as String
    }
}
