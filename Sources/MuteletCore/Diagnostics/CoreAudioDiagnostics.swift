import CoreAudio
import Foundation
import OSLog

enum CoreAudioDiagnostics {
    struct Measurement {
        let operation: String
        let startedAt: ContinuousClock.Instant

        func finish() {
            let duration = startedAt.duration(to: ContinuousClock.now)
            let components = duration.components
            let milliseconds = Double(components.seconds) * 1_000
                + Double(components.attoseconds) / 1_000_000_000_000_000
            logger.debug(
                "\(operation, privacy: .public) finished in \(milliseconds, privacy: .public) ms"
            )
        }
    }

    private static let logger = Logger(
        subsystem: "app.mutelet.Mutelet",
        category: "CoreAudioPerformance"
    )

    static func measure(_ operation: String) -> Measurement {
        logger.debug("\(operation, privacy: .public) started")
        return Measurement(operation: operation, startedAt: ContinuousClock.now)
    }

    static func mark(_ event: String) {
        logger.debug("\(event, privacy: .public)")
    }

    static func listenerRegistrationFailed(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        error: any Error
    ) {
        logger.error(
            "Listener registration failed for object \(objectID), selector \(address.mSelector), element \(address.mElement): \(String(describing: error), privacy: .public)"
        )
    }

    static func listenerRemovalFailed(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        status: OSStatus
    ) {
        logger.error(
            "Listener removal failed for object \(objectID), selector \(address.mSelector), element \(address.mElement), status \(status)"
        )
    }
}
