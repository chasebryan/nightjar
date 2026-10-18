import CryptoKit
import XCTest
@testable import nightjar

/// NJCF file envelopes: every protection's
/// round trip, the wrong-key failures, tamper
/// and truncation — the format's promises, kept.
final class CryptoFilesTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "njcf-" + UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func sourceFile(
        _ name: String, _ data: Data) -> URL {
        let url = dir.appendingPathComponent(name)
        try! data.write(to: url)
        return url
    }

    private func roundTrip(
        _ source: URL,
        protection: NJCFProtection,
        password: String?,
        openPassword: String?,
        recipient: P256.KeyAgreement.PublicKey? = nil
    ) throws -> URL {
        let sealed = dir.appendingPathComponent(
            "sealed.njcf")
        try CryptoFiles.encrypt(
            input: source, output: sealed,
            protection: protection, password: password,
            recipient: recipient)
        let info = try CryptoFiles.inspect(sealed)
        XCTAssertEqual(info.protection, protection)
        let outDir = dir.appendingPathComponent(
            "out", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outDir, withIntermediateDirectories: true)
        return try CryptoFiles.decrypt(
            input: sealed, password: openPassword,
            outputDirectory: outDir)
    }

    func testPasswordRoundTrip() throws {
        let data = Data("the owl flies at midnight"
            .utf8)
        let source = sourceFile("note.txt", data)
        let restored = try roundTrip(
            source, protection: .password,
            password: "correct horse",
            openPassword: "correct horse")
        XCTAssertEqual(restored.lastPathComponent,
                       "note.txt")
        XCTAssertEqual(try Data(contentsOf: restored),
                       data)
    }

    func testWrongPasswordRefused() throws {
        let source = sourceFile(
            "note.txt", Data("x".utf8))
        let sealed = dir.appendingPathComponent(
            "s.njcf")
        try CryptoFiles.encrypt(
            input: source, output: sealed,
            protection: .password,
            password: "right", recipient: nil)
        XCTAssertThrowsError(
            try CryptoFiles.decrypt(
                input: sealed, password: "wrong",
                outputDirectory: dir)) { error in
            XCTAssertEqual(error as? CryptoFileError,
                           .wrongKeyOrPassword)
        }
    }

    func testVaultKeyRoundTrip() throws {
        let data = Data("device-bound".utf8)
        let source = sourceFile("bound.bin", data)
        let restored = try roundTrip(
            source, protection: .vaultKey,
            password: nil, openPassword: nil)
        XCTAssertEqual(try Data(contentsOf: restored),
                       data)
    }

    func testEitherOpensBothWays() throws {
        let data = Data("two roads in".utf8)
        let source = sourceFile("roads.txt", data)
        let byPassword = try roundTrip(
            source, protection: .either,
            password: "pw", openPassword: "pw")
        XCTAssertEqual(try Data(contentsOf: byPassword),
                       data)
        let byVault = try roundTrip(
            source, protection: .either,
            password: "pw", openPassword: nil)
        XCTAssertEqual(try Data(contentsOf: byVault),
                       data)
    }

    func testBothRequired() throws {
        let data = Data("both halves".utf8)
        let source = sourceFile("halves.txt", data)
        let restored = try roundTrip(
            source, protection: .bothRequired,
            password: "pw", openPassword: "pw")
        XCTAssertEqual(try Data(contentsOf: restored),
                       data)
        // The wrong password leaves the halves
        // mismatched: the metadata chunk refuses.
        let sealed = dir.appendingPathComponent(
            "h.njcf")
        try CryptoFiles.encrypt(
            input: source, output: sealed,
            protection: .bothRequired,
            password: "pw", recipient: nil)
        XCTAssertThrowsError(
            try CryptoFiles.decrypt(
                input: sealed, password: "nope",
                outputDirectory: dir))
    }

    func testDeadDropToSelf() throws {
        let data = Data("for your eyes".utf8)
        let source = sourceFile("drop.txt", data)
        let restored = try roundTrip(
            source, protection: .deadDrop,
            password: nil, openPassword: nil,
            recipient: CryptoSuite.identity().publicKey)
        XCTAssertEqual(try Data(contentsOf: restored),
                       data)
    }

    func testLargeFileChunks() throws {
        var data = Data(count: 2_500_000)
        for i in 0..<data.count {
            data[i] = UInt8((i * 31) % 251)
        }
        let source = sourceFile("big.bin", data)
        let restored = try roundTrip(
            source, protection: .password,
            password: "pw", openPassword: "pw")
        XCTAssertEqual(try Data(contentsOf: restored),
                       data)
    }

    func testTamperAndTruncationRefused() throws {
        let source = sourceFile(
            "note.txt", Data("integrity".utf8))
        let sealed = dir.appendingPathComponent(
            "t.njcf")
        try CryptoFiles.encrypt(
            input: source, output: sealed,
            protection: .password,
            password: "pw", recipient: nil)
        var bytes = try Data(contentsOf: sealed)
        bytes[bytes.count - 3] ^= 0xFF
        let cut = dir.appendingPathComponent(
            "cut.njcf")
        try bytes.write(to: cut)
        XCTAssertThrowsError(
            try CryptoFiles.decrypt(
                input: cut, password: "pw",
                outputDirectory: dir))
        let short = dir.appendingPathComponent(
            "short.njcf")
        try bytes.prefix(bytes.count - 10)
            .write(to: short)
        XCTAssertThrowsError(
            try CryptoFiles.decrypt(
                input: short, password: "pw",
                outputDirectory: dir))
    }

    func testPlainFileIsNotAnEnvelope() throws {
        let source = sourceFile(
            "plain.txt", Data("hello".utf8))
        XCTAssertThrowsError(
            try CryptoFiles.inspect(source)) { error in
            XCTAssertEqual(error as? CryptoFileError,
                           .notAnEnvelope)
        }
    }
}
