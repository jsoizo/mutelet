import Foundation
import XCTest
@testable import MuteletCore

final class UserDefaultsAudioMutationReceiptStoreTests: XCTestCase {
    func testReceiptRoundTrip() async throws {
        let suiteName = "app.mutelet.tests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAudioMutationReceiptStore(suiteName: suiteName)
        let receipt = AudioMutationReceipt(
            deviceUID: "device-1",
            originalValues: [
                AudioControlValue(
                    control: AudioControl(kind: .volume, element: 1),
                    value: 0.42
                ),
            ]
        )

        try await store.save(receipt)
        let savedReceipt = await store.receipt(deviceUID: "device-1")
        XCTAssertEqual(savedReceipt, receipt)

        try await store.removeReceipt(deviceUID: "device-1")
        let removedReceipt = await store.receipt(deviceUID: "device-1")
        XCTAssertNil(removedReceipt)
    }
}
