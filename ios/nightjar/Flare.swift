import CryptoKit
import Foundation

/// Flare: recognition without identity. A phone with flare up
/// advertises, in the FFF0 service-data slot, a short token only
/// holders of the pairing key can compute — an HMAC of the
/// current five-minute window. A paired phone listening sees
/// the token match and knows: one of ours is in radio range.
/// To everyone else on earth the token is eight random bytes
/// that change five minutes later, attached to a rotating
/// Bluetooth address — it names nobody, and yesterday's token
/// proves nothing about today.
///
/// What a flare does NOT do: locate, identify, or authenticate
/// a person. It is a lantern only key-holders can see, carried
/// by an address that itself rotates. The match is checked
/// against the neighboring windows too, so two phones whose
/// clocks disagree by a few minutes still recognize each other.
enum Flare {
    static let windowSeconds = 300

    static func window(for date: Date = Date()) -> Int {
        Int(date.timeIntervalSince1970) / windowSeconds
    }

    static func token(key: SymmetricKey, window: Int) -> Data {
        var message = Data("nightjar-flare".utf8)
        var w = UInt64(window).bigEndian
        withUnsafeBytes(of: &w) { message.append(contentsOf: $0) }
        let mac = HMAC<SHA256>.authenticationCode(
            for: message, using: key)
        return Data(mac.prefix(8))
    }

    static func tokenNow(key: SymmetricKey) -> Data {
        token(key: key, window: window())
    }

    /// Does this FFF0 service-data payload carry a live flare
    /// from a holder of the key?
    static func matches(_ data: Data, key: SymmetricKey) -> Bool {
        let w = window()
        return [-1, 0, 1].contains {
            token(key: key, window: w + $0) == data
        }
    }
}
