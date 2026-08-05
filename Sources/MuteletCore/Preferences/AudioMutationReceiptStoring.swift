import Foundation

public protocol AudioMutationReceiptStoring: Sendable {
    func receipt(deviceUID: String) async -> AudioMutationReceipt?
    func save(_ receipt: AudioMutationReceipt) async throws
    func removeReceipt(deviceUID: String) async throws
}

public actor UserDefaultsAudioMutationReceiptStore: AudioMutationReceiptStoring {
    private static let storageKey = "audioMutationReceipts.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(suiteName: String? = nil) {
        if let suiteName, let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
        } else {
            self.defaults = .standard
        }
    }

    public func receipt(deviceUID: String) -> AudioMutationReceipt? {
        load()[deviceUID]
    }

    public func save(_ receipt: AudioMutationReceipt) throws {
        var receipts = load()
        receipts[receipt.deviceUID] = receipt
        try persist(receipts)
    }

    public func removeReceipt(deviceUID: String) throws {
        var receipts = load()
        receipts.removeValue(forKey: deviceUID)
        try persist(receipts)
    }

    private func load() -> [String: AudioMutationReceipt] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let receipts = try? decoder.decode([String: AudioMutationReceipt].self, from: data) else {
            return [:]
        }
        return receipts
    }

    private func persist(_ receipts: [String: AudioMutationReceipt]) throws {
        defaults.set(try encoder.encode(receipts), forKey: Self.storageKey)
    }
}
