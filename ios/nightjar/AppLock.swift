import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security

// MARK: - AppLock
//
// The gate at the app's own door: a passcode
// the OPERATOR chooses, under a protection
// scheme the OPERATOR chooses, and the whole
// application unusable until it is given.
//
// THE SHAPE. The passcode is stretched by
// PBKDF2-HMAC-SHA256 (the operator picks the
// rounds: 100k, 300k or 600k) over a fresh
// 16-byte salt into a 32-byte key. That key
// seals one small proof — a known constant
// wearing 16 random bytes — under the chosen
// cipher, AES-256-GCM or ChaCha20-Poly1305.
// The salt, the rounds, the suite and the
// sealed box live as ONE Keychain item; the
// passcode itself is never stored anywhere.
// Opening the proof with a derived key is
// the whole test: AEAD opens, or it doesn't.
//
// THE HONESTY LINE, said here once and in
// the manual again: this seals the
// INTERFACE. It does not re-encrypt the
// app's stored files, and it was never
// going to — iOS already guards the data
// container with the device passcode. What
// this gate buys is a door of the operator's
// own on the app itself: the borrowed phone,
// the handed-over phone, opens onto the
// lock and nothing else.
//
// Brute force is priced twice: the KDF
// rounds make every guess cost real time,
// and five wrong guesses start a lockout
// that doubles — 30 seconds, a minute, two,
// four, eight — until a right guess resets
// the count to zero.

/// The two suites the gate can seal under —
/// the operator's choice, named plainly.
enum AppLockSuite: String, CaseIterable {
    case aesgcm
    case chacha

    var label: String {
        switch self {
        case .aesgcm: return "AES-256-GCM"
        case .chacha: return "ChaCha20-Poly1305"
        }
    }
}

enum AppLockStandard {

    /// The production Keychain service. The
    /// Gauntlet works on the test service, so
    /// a self-test never touches the seal the
    /// operator actually lives behind.
    static let productionService =
        "net.nosuchmachine.nightjarhack.applock"
    static let testService =
        "net.nosuchmachine.nightjarhack.applock.test"

    /// What the seal proves: this constant,
    /// then 16 random bytes so no two seals
    /// ever share a plaintext.
    static let sealConstant = "nightjar-applock-v1"
    static let keyLength = 32
    static let saltLength = 16
    static let tailLength = 16

    static let allowedRounds = [100_000, 300_000, 600_000]
    static let defaultRounds = 300_000
    static let allowedGrace = [0, 60, 300]

    enum Failure: Error {
        case noRandomness
        case sealRefused
    }

    // MARK: - Configuration
    //
    // The operator's chosen settings, in
    // UserDefaults under keys derived from
    // the service — the production house and
    // the Gauntlet's test house can never
    // read each other's settings. The SEAL
    // itself is the authority for verify():
    // the suite and rounds it was made with
    // ride inside the record, and the mirrors
    // here are for the settings room to show.

    private static func defaultsKey(
        _ service: String, _ name: String) -> String {
        service + "." + name
    }

    static func suite(
        service: String = productionService
    ) -> AppLockSuite {
        if let record = storedRecord(service: service),
           let sealed = AppLockSuite(
            rawValue: record.suite) {
            return sealed
        }
        let saved = UserDefaults.standard.string(
            forKey: defaultsKey(service, "suite"))
        return AppLockSuite(rawValue: saved ?? "")
            ?? .aesgcm
    }

    static func setSuite(
        _ suite: AppLockSuite,
        service: String = productionService) {
        UserDefaults.standard.set(
            suite.rawValue,
            forKey: defaultsKey(service, "suite"))
    }

    static func kdfRounds(
        service: String = productionService) -> Int {
        if let record = storedRecord(service: service),
           allowedRounds.contains(record.rounds) {
            return record.rounds
        }
        let saved = UserDefaults.standard.integer(
            forKey: defaultsKey(service, "rounds"))
        return allowedRounds.contains(saved)
            ? saved : defaultRounds
    }

    static func setKdfRounds(
        _ rounds: Int,
        service: String = productionService) {
        UserDefaults.standard.set(
            allowedRounds.contains(rounds)
                ? rounds : defaultRounds,
            forKey: defaultsKey(service, "rounds"))
    }

    static func graceSeconds(
        service: String = productionService) -> Int {
        let saved = UserDefaults.standard.integer(
            forKey: defaultsKey(service, "grace"))
        return allowedGrace.contains(saved) ? saved : 0
    }

    static func setGraceSeconds(
        _ seconds: Int,
        service: String = productionService) {
        UserDefaults.standard.set(
            allowedGrace.contains(seconds)
                ? seconds : 0,
            forKey: defaultsKey(service, "grace"))
    }

    static func biometricsEnabled(
        service: String = productionService) -> Bool {
        UserDefaults.standard.bool(
            forKey: defaultsKey(service, "biometrics"))
    }

    static func setBiometricsEnabled(
        _ on: Bool,
        service: String = productionService) {
        UserDefaults.standard.set(
            on,
            forKey: defaultsKey(service, "biometrics"))
    }

    /// Whether this device can offer biometry
    /// at all — the settings room and the gate
    /// both ask before they offer the button.
    static func biometricsAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error)
    }

    static func biometryKind() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error)
        return context.biometryType
    }

    // MARK: - Derivation
    //
    // PBKDF2-HMAC-SHA256 by CommonCrypto's
    // own hand — the published vectors are
    // the contract, and the Gauntlet pins
    // one of them byte for byte.

    static func derive(passcode: String, salt: Data,
                       rounds: Int) -> Data {
        var derived = Data(count: keyLength)
        let status: Int32 = passcode.withCString {
            password in
            derived.withUnsafeMutableBytes { out in
                salt.withUnsafeBytes { rawSalt in
                    guard let outAddress =
                            out.baseAddress,
                          let saltAddress =
                            rawSalt.baseAddress
                    else { return -1 }
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        password, passcode.utf8.count,
                        saltAddress.assumingMemoryBound(
                            to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(
                            kCCPRFHmacAlgSHA256),
                        UInt32(max(rounds, 1)),
                        outAddress.assumingMemoryBound(
                            to: UInt8.self),
                        keyLength)
                }
            }
        }
        guard status == kCCSuccess else { return Data() }
        return derived
    }

    private static func randomBytes(
        _ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes {
            raw in
            SecRandomCopyBytes(kSecRandomDefault,
                               count, raw.baseAddress!)
        }
        guard status == errSecSuccess else {
            return Data()
        }
        return data
    }

    // MARK: - The seal record
    //
    // One Keychain item, account "seal": a
    // small JSON envelope naming its own
    // version, suite and rounds, with the
    // salt and the sealed box in base64. The
    // read/write/delete shapes mirror the
    // house mirror's own (Setup.swift) — the
    // same discipline, a different door.

    private struct SealRecord: Codable {
        var v: Int
        var suite: String
        var rounds: Int
        var salt: String
        var box: String
    }

    private static func baseQuery(
        service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "seal"]
    }

    private static func keychainRead(
        service: String) -> Data? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] =
            kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(
                query as CFDictionary, &item)
                == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return data
    }

    private static func keychainWrite(
        _ data: Data, service: String) {
        let status = SecItemUpdate(
            baseQuery(service: service)
                as CFDictionary,
            [kSecValueData as String: data]
                as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(service: service)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private static func keychainDelete(
        service: String) {
        SecItemDelete(baseQuery(service: service)
            as CFDictionary)
    }

    private static func storedRecord(
        service: String) -> SealRecord? {
        guard let data = keychainRead(service: service)
        else { return nil }
        return try? JSONDecoder().decode(
            SealRecord.self, from: data)
    }

    private static func sealBox(
        suite: AppLockSuite, key: Data,
        plaintext: Data) -> Data? {
        let key = SymmetricKey(data: key)
        switch suite {
        case .aesgcm:
            return try? AES.GCM.seal(
                plaintext, using: key).combined
        case .chacha:
            return try? ChaChaPoly.seal(
                plaintext, using: key).combined
        }
    }

    private static func openBox(
        suite: AppLockSuite, key: Data,
        combined: Data) -> Data? {
        let key = SymmetricKey(data: key)
        switch suite {
        case .aesgcm:
            guard let box = try? AES.GCM.SealedBox(
                combined: combined)
            else { return nil }
            return try? AES.GCM.open(box, using: key)
        case .chacha:
            guard let box = try? ChaChaPoly.SealedBox(
                combined: combined)
            else { return nil }
            return try? ChaChaPoly.open(
                box, using: key)
        }
    }

    // MARK: - The API

    static func isArmed(
        service: String = productionService) -> Bool {
        keychainRead(service: service) != nil
    }

    /// Arm the gate: a fresh salt, a fresh
    /// seal, the settings mirrored beside it,
    /// and any old lockout forgotten.
    static func configure(
        passcode: String, suite: AppLockSuite,
        rounds: Int,
        service: String = productionService) throws {
        let salt = randomBytes(saltLength)
        let tail = randomBytes(tailLength)
        guard salt.count == saltLength,
              tail.count == tailLength
        else { throw Failure.noRandomness }
        let rounds = allowedRounds.contains(rounds)
            ? rounds : defaultRounds
        let key = derive(passcode: passcode,
                         salt: salt, rounds: rounds)
        var plaintext = Data(sealConstant.utf8)
        plaintext.append(tail)
        guard let box = sealBox(suite: suite, key: key,
                                plaintext: plaintext)
        else { throw Failure.sealRefused }
        let record = SealRecord(
            v: 1, suite: suite.rawValue,
            rounds: rounds,
            salt: salt.base64EncodedString(),
            box: box.base64EncodedString())
        let data = try JSONEncoder().encode(record)
        keychainWrite(data, service: service)
        setSuite(suite, service: service)
        setKdfRounds(rounds, service: service)
        resetLockout(service: service)
    }

    /// The whole test: derive from the STORED
    /// salt and rounds, open with the STORED
    /// suite, and read the constant back. A
    /// failed open is a wrong passcode — there
    /// is no other answer to give.
    static func verify(
        _ passcode: String,
        service: String = productionService) -> Bool {
        guard let record = storedRecord(service: service),
              let salt = Data(
                base64Encoded: record.salt),
              let box = Data(
                base64Encoded: record.box),
              let suite = AppLockSuite(
                rawValue: record.suite)
        else { return false }
        let key = derive(passcode: passcode,
                         salt: salt,
                         rounds: record.rounds)
        guard let opened = openBox(
                suite: suite, key: key, combined: box)
        else { return false }
        let prefix = opened.prefix(
            sealConstant.utf8.count)
        return String(decoding: prefix, as: UTF8.self)
            == sealConstant
    }

    /// Remove the lock — and only ever behind
    /// the passcode itself.
    static func disarm(
        passcode: String,
        service: String = productionService) -> Bool {
        guard verify(passcode, service: service)
        else { return false }
        keychainDelete(service: service)
        resetLockout(service: service)
        return true
    }

    /// A new passcode over the same chosen
    /// scheme: verify the old, re-seal the new
    /// under the record's own suite and rounds
    /// with a fresh salt.
    static func changePasscode(
        old: String, new: String,
        service: String = productionService) -> Bool {
        guard verify(old, service: service),
              let record = storedRecord(service: service),
              let suite = AppLockSuite(
                rawValue: record.suite)
        else { return false }
        do {
            try configure(passcode: new, suite: suite,
                          rounds: record.rounds,
                          service: service)
            return true
        } catch {
            return false
        }
    }

    /// A new scheme under the same passcode:
    /// the suite or the rounds change, the
    /// seal is remade, the passcode never
    /// changes hands.
    static func reconfigure(
        passcode: String, suite: AppLockSuite,
        rounds: Int,
        service: String = productionService) -> Bool {
        guard verify(passcode, service: service)
        else { return false }
        do {
            try configure(passcode: passcode,
                          suite: suite, rounds: rounds,
                          service: service)
            return true
        } catch {
            return false
        }
    }

    /// The unverified wipe. The operator's own
    /// road is disarm; this exists for the
    /// Gauntlet's cleanup, so a self-test can
    /// guarantee the test house is left empty
    /// whatever a step did.
    static func wipe(
        service: String = productionService) {
        keychainDelete(service: service)
        resetLockout(service: service)
    }

    // MARK: - The lockout
    //
    // Failed guesses counted in the open (the
    // count is not a secret; the seal is).
    // Five failures buy a 30-second wait, and
    // every further failure doubles it, capped
    // at the fourth doubling — eight minutes.
    // A success clears the slate entirely.

    static func lockoutRemaining(
        service: String = productionService
    ) -> TimeInterval {
        let until = UserDefaults.standard.double(
            forKey: defaultsKey(service, "lockoutUntil"))
        let remaining = until
            - Date().timeIntervalSince1970
        return remaining > 0 ? remaining : 0
    }

    static func recordFailure(
        service: String = productionService) {
        let defaults = UserDefaults.standard
        let fails = defaults.integer(
            forKey: defaultsKey(service, "fails")) + 1
        defaults.set(
            fails,
            forKey: defaultsKey(service, "fails"))
        if fails >= 5 {
            let step = min(fails - 5, 4)
            let delay = 30.0 * pow(2.0, Double(step))
            defaults.set(
                Date().timeIntervalSince1970 + delay,
                forKey: defaultsKey(
                    service, "lockoutUntil"))
        }
    }

    static func recordSuccess(
        service: String = productionService) {
        resetLockout(service: service)
    }

    private static func resetLockout(
        service: String) {
        let defaults = UserDefaults.standard
        defaults.set(
            0, forKey: defaultsKey(service, "fails"))
        defaults.removeObject(
            forKey: defaultsKey(service, "lockoutUntil"))
    }
}

/// The gate's keeper: one published truth —
/// is the app behind the lock right now —
/// and the scene's comings and goings read
/// against the operator's grace. Locked at
/// launch whenever a seal stands; locked
/// again the moment the app leaves the
/// screen, or once the grace has run out.
final class AppLockCenter: ObservableObject {
    static let shared = AppLockCenter()

    @Published private(set) var locked: Bool

    /// When the app last left the screen, kept
    /// in memory only — a relaunch starts
    /// locked anyway, so nothing is lost.
    private var backgroundedAt: Date?

    init() {
        locked = AppLockStandard.isArmed()
    }

    func noteBackgrounded() {
        backgroundedAt = Date()
    }

    func noteForegrounded() {
        guard AppLockStandard.isArmed() else {
            locked = false
            return
        }
        guard let since = backgroundedAt else {
            // Never left the screen this launch:
            // the launch state already carries
            // the lock, and nothing has lifted it.
            return
        }
        backgroundedAt = nil
        let grace = AppLockStandard.graceSeconds()
        if grace <= 0
            || Date().timeIntervalSince(since)
                >= TimeInterval(grace) {
            locked = true
        }
    }

    /// Called only after a passcode or a
    /// biometric success at the gate itself.
    func unlock() {
        locked = false
    }

    func lockNow() {
        if AppLockStandard.isArmed() {
            locked = true
        }
    }

    /// After the settings room arms or removes
    /// the lock, the keeper re-reads the seal:
    /// a house with no lock is never held shut.
    func syncWithStandard() {
        if !AppLockStandard.isArmed() {
            locked = false
        }
    }
}
