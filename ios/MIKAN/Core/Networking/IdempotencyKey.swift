import Foundation

/// One `Idempotency-Key` per user action (see «Idempotency» in docs/API.md).
///
/// `key(for:)` keeps returning the same UUID while the request body stays the same, so «Повторить» after a timeout
/// or a dropped connection makes the server replay the original result instead of applying the write twice.
/// A changed body is a new action and gets a new key; call `reset()` once the action has succeeded.
nonisolated struct IdempotencyKey: Sendable {
    private var fingerprint: Data?
    private var value = UUID()

    mutating func key(for body: some Encodable) -> UUID {
        let encoder = JSONCoding.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try? encoder.encode(body)
        if encoded == nil || encoded != fingerprint {
            value = UUID()
            fingerprint = encoded
        }
        return value
    }

    mutating func reset() {
        fingerprint = nil
    }
}
