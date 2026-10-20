import XCTest
import CryptoKit
@testable import nightjar

/// The SSH client's pins. Every vector here was recorded
/// from a live session between the Python prototype of
/// this exact design and an independent implementation
/// (paramiko 5.1): the exchange hash, the derived keys,
/// the host signatures, the fingerprints, and one whole
/// AES-GCM wire packet must reproduce byte for byte.
final class SSHTests: XCTestCase {

    private func data(_ hex: String) -> Data {
        var out = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(
                hex[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    private let edV_C = "5353482d322e302d6e696768746a61725f312e30"
    private let edV_S = "5353482d322e302d706172616d696b6f5f352e312e30"
    private let edI_C = "14488dd8b46bd247dfbf2e5add3811d6c20000004b637572766532353531392d7368613235362c637572766532353531392d736861323536406c69627373682e6f72672c6b65782d7374726963742d632d763030406f70656e7373682e636f6d0000001f7373682d656432353531392c65636473612d736861322d6e697374703235360000002d6165733235362d67636d406f70656e7373682e636f6d2c6165733132382d67636d406f70656e7373682e636f6d0000002d6165733235362d67636d406f70656e7373682e636f6d2c6165733132382d67636d406f70656e7373682e636f6d0000000d686d61632d736861322d3235360000000d686d61632d736861322d323536000000046e6f6e65000000046e6f6e6500000000000000000000000000"
    private let edI_S = "14643f330b03c13cca259667df1f2c5eab000000e96d6c6b656d3736387832353531392d7368613235362c637572766532353531392d736861323536406c69627373682e6f72672c656364682d736861322d6e697374703235362c656364682d736861322d6e697374703338342c656364682d736861322d6e697374703532312c6469666669652d68656c6c6d616e2d67726f757031362d7368613531322c6469666669652d68656c6c6d616e2d67726f75702d65786368616e67652d7368613235362c6469666669652d68656c6c6d616e2d67726f757031342d7368613235362c6b65782d7374726963742d732d763030406f70656e7373682e636f6d0000000b7373682d65643235353139000000786165733132382d6374722c6165733139322d6374722c6165733235362d6374722c6165733132382d6362632c6165733139322d6362632c6165733235362d6362632c336465732d6362632c6165733132382d67636d406f70656e7373682e636f6d2c6165733235362d67636d406f70656e7373682e636f6d000000786165733132382d6374722c6165733139322d6374722c6165733235362d6374722c6165733132382d6362632c6165733139322d6362632c6165733235362d6362632c336465732d6362632c6165733132382d67636d406f70656e7373682e636f6d2c6165733235362d67636d406f70656e7373682e636f6d00000083686d61632d736861322d3235362c686d61632d736861322d3531322c686d61632d736861322d3235362d65746d406f70656e7373682e636f6d2c686d61632d736861322d3531322d65746d406f70656e7373682e636f6d2c686d61632d736861312c686d61632d6d64352c686d61632d736861312d39362c686d61632d6d64352d393600000083686d61632d736861322d3235362c686d61632d736861322d3531322c686d61632d736861322d3235362d65746d406f70656e7373682e636f6d2c686d61632d736861322d3531322d65746d406f70656e7373682e636f6d2c686d61632d736861312c686d61632d6d64352c686d61632d736861312d39362c686d61632d6d64352d3936000000046e6f6e65000000046e6f6e6500000000000000000000000000"
    private let edK_S = "0000000b7373682d6564323535313900000020deed52e7832090f78e77ddf62983aaf76321f8c0a8efad0518711133e57542fa"
    private let edQ_S = "5c9f8b5327952d0bad10031ee10dce36a0460e40a716cd45f98f4a56e9c10f76"
    private let edK = "9b0733ea376d8b30f71db655a59974f7efee420e5fb4dffd182cd89c2de7e323"
    private let edH = "4a840f1f15e596d178269c8431fe885a8718c3b45192d08a4caf450a49a17f75"
    private let edsig_blob = "0000000b7373682d6564323535313900000040d4b4b5cb0e83d639e3d78c7a69d55230e97ffeee16ae95a20af268d1ff7c177f778dd2b1cd2900b9cc8842223df39399d5c7e62f70f733f2448fefc37dce4904"
    private let edephemeral_private = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
    private let edkey_c2s = "624fa01f13676c7b3e63202fe83a067ba1cd3d619f723eb45198e5fd6dec8bc3"
    private let ediv_c2s = "900fce286c781c20e4835b3c"
    private let edFingerprint = "SHA256:8s0DFxC/olAgPlubgKbJPq+JLKuvxguUUTt958aY9B4"
    private let ecV_C = "5353482d322e302d6e696768746a61725f312e30"
    private let ecV_S = "5353482d322e302d706172616d696b6f5f352e312e30"
    private let ecI_C = "14d1756a12077821021d7e168923936c6b0000004b637572766532353531392d7368613235362c637572766532353531392d736861323536406c69627373682e6f72672c6b65782d7374726963742d632d763030406f70656e7373682e636f6d0000001f7373682d656432353531392c65636473612d736861322d6e697374703235360000002d6165733235362d67636d406f70656e7373682e636f6d2c6165733132382d67636d406f70656e7373682e636f6d0000002d6165733235362d67636d406f70656e7373682e636f6d2c6165733132382d67636d406f70656e7373682e636f6d0000000d686d61632d736861322d3235360000000d686d61632d736861322d323536000000046e6f6e65000000046e6f6e6500000000000000000000000000"
    private let ecI_S = "1440de4790ced09fc95f2390e6ce47bd7d000000e96d6c6b656d3736387832353531392d7368613235362c637572766532353531392d736861323536406c69627373682e6f72672c656364682d736861322d6e697374703235362c656364682d736861322d6e697374703338342c656364682d736861322d6e697374703532312c6469666669652d68656c6c6d616e2d67726f757031362d7368613531322c6469666669652d68656c6c6d616e2d67726f75702d65786368616e67652d7368613235362c6469666669652d68656c6c6d616e2d67726f757031342d7368613235362c6b65782d7374726963742d732d763030406f70656e7373682e636f6d0000001365636473612d736861322d6e69737470323536000000786165733132382d6374722c6165733139322d6374722c6165733235362d6374722c6165733132382d6362632c6165733139322d6362632c6165733235362d6362632c336465732d6362632c6165733132382d67636d406f70656e7373682e636f6d2c6165733235362d67636d406f70656e7373682e636f6d000000786165733132382d6374722c6165733139322d6374722c6165733235362d6374722c6165733132382d6362632c6165733139322d6362632c6165733235362d6362632c336465732d6362632c6165733132382d67636d406f70656e7373682e636f6d2c6165733235362d67636d406f70656e7373682e636f6d00000083686d61632d736861322d3235362c686d61632d736861322d3531322c686d61632d736861322d3235362d65746d406f70656e7373682e636f6d2c686d61632d736861322d3531322d65746d406f70656e7373682e636f6d2c686d61632d736861312c686d61632d6d64352c686d61632d736861312d39362c686d61632d6d64352d393600000083686d61632d736861322d3235362c686d61632d736861322d3531322c686d61632d736861322d3235362d65746d406f70656e7373682e636f6d2c686d61632d736861322d3531322d65746d406f70656e7373682e636f6d2c686d61632d736861312c686d61632d6d64352c686d61632d736861312d39362c686d61632d6d64352d3936000000046e6f6e65000000046e6f6e6500000000000000000000000000"
    private let ecK_S = "0000001365636473612d736861322d6e69737470323536000000086e69737470323536000000410470525733cdde52a4b44c81490183e7fe22ce576e18dcf6a27a64e56a9d5d65fedb638c1505c86808008d0314012328d12974fe609a42b2f74478ee50d031dfeb"
    private let ecQ_S = "9a42eb7d552b054dbf7a6b2fbcdd5458005c461dcfe1ea0c3006a3721104f932"
    private let ecK = "0da603fc74035b9cead1e34fd577d2eabf869ab1dc83d44e7951bebbd5af6950"
    private let ecH = "31cd1720088adae2e02404a3cbfcd4ae2bc75658eafbdc96dfade65591d6ef3b"
    private let ecsig_blob = "0000001365636473612d736861322d6e6973747032353600000048000000206964c0ec54a654cc48a46d19c20e9574cfaa39a8103e1a776e30e4d16e8706e80000002046799e9aa3f3c5ef9006c76ea3445f4330f48db910ce883b1052c94bf32ccf73"
    private let ecephemeral_private = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"
    private let eckey_c2s = "86819c7321f4306cd68f18cc86e732a2e26fabf4a364f148ed637fcd6a475c32"
    private let eciv_c2s = "e8daf534e17456c191c24fa1"
    private let ecFingerprint = "SHA256:kfZ+mSD7PKJJiM/9baYp26IUt59fUtCMOtM00qV+18g"
    private let gcmWire = "0000001c820b320a7ece4f01028a778a421f7e1ff8c81dc4a6c7005dc6bf16ce6f6e30a99fd7edf7d8c474337d7f3088"

    private func transcript(
        vC: String, vS: String, iC: String, iS: String,
        kS: String, qS: String, shared: Data
    ) -> Data {
        var input = Data()
        input.append(SSHWire.string(data(vC)))
        input.append(SSHWire.string(data(vS)))
        input.append(SSHWire.string(data(iC)))
        input.append(SSHWire.string(data(iS)))
        input.append(SSHWire.string(data(kS)))
        let eph = try! Curve25519.KeyAgreement
            .PrivateKey(rawRepresentation:
                data(edephemeral_private))
        input.append(SSHWire.string(
            eph.publicKey.rawRepresentation))
        input.append(SSHWire.string(data(qS)))
        input.append(SSHWire.mpint(shared))
        return Data(SHA256.hash(data: input))
    }

    private func sharedSecret(qS: String) -> Data {
        let eph = try! Curve25519.KeyAgreement
            .PrivateKey(rawRepresentation:
                data(edephemeral_private))
        let peer = try! Curve25519.KeyAgreement
            .PublicKey(rawRepresentation: data(qS))
        let shared = try! eph
            .sharedSecretFromKeyAgreement(with: peer)
        return shared.withUnsafeBytes { Data($0) }
    }

    func testEd25519Transcript() throws {
        let shared = sharedSecret(qS: edQ_S)
        XCTAssertEqual(shared, data(edK))
        let hash = transcript(vC: edV_C, vS: edV_S,
                              iC: edI_C, iS: edI_S,
                              kS: edK_S, qS: edQ_S,
                              shared: shared)
        XCTAssertEqual(hash, data(edH))
        let client = SSHClient(host: "127.0.0.1",
                               port: 2222,
                               user: "operator")
        client.sessionID = hash
        XCTAssertEqual(
            client.derive(letter: 67, count: 32,
                          shared: shared, hash: hash),
            data(edkey_c2s))
        XCTAssertEqual(
            client.derive(letter: 65, count: 12,
                          shared: shared, hash: hash),
            data(ediv_c2s))
        XCTAssertEqual(
            SSHClient.fingerprint(of: data(edK_S)),
            edFingerprint)
        XCTAssertNoThrow(
            try client.verifyHostSignature(
                algorithm: "ssh-ed25519",
                keyBlob: data(edK_S),
                sigBlob: data(edsig_blob),
                hash: hash))
        XCTAssertThrowsError(
            try client.verifyHostSignature(
                algorithm: "ssh-ed25519",
                keyBlob: data(edK_S),
                sigBlob: data(edsig_blob),
                hash: Data([1, 2, 3])))
    }

    func testECDSATranscript() throws {
        let shared = sharedSecret(qS: ecQ_S)
        XCTAssertEqual(shared, data(ecK))
        let hash = transcript(vC: ecV_C, vS: ecV_S,
                              iC: ecI_C, iS: ecI_S,
                              kS: ecK_S, qS: ecQ_S,
                              shared: shared)
        XCTAssertEqual(hash, data(ecH))
        let client = SSHClient(host: "127.0.0.1",
                               port: 2223,
                               user: "operator")
        client.sessionID = hash
        XCTAssertEqual(
            client.derive(letter: 67, count: 32,
                          shared: shared, hash: hash),
            data(eckey_c2s))
        XCTAssertEqual(
            SSHClient.fingerprint(of: data(ecK_S)),
            ecFingerprint)
        XCTAssertNoThrow(
            try client.verifyHostSignature(
                algorithm: "ecdsa-sha2-nistp256",
                keyBlob: data(ecK_S),
                sigBlob: data(ecsig_blob),
                hash: hash))
        XCTAssertThrowsError(
            try client.verifyHostSignature(
                algorithm: "ecdsa-sha2-nistp256",
                keyBlob: data(ecK_S),
                sigBlob: data(ecsig_blob),
                hash: Data([9, 9, 9])))
    }

    func testGCMWireVector() throws {
        // The first encrypted packet of the recorded
        // ed25519 session: a userauth service request,
        // zero-padded so the bytes pin exactly.
        let key = SymmetricKey(data: data(edkey_c2s))
        let iv = data(ediv_c2s)
        let fixed = Data(iv.prefix(4))
        var counter: UInt64 = 0
        for byte in iv.suffix(8) {
            counter = counter << 8 | UInt64(byte)
        }
        let payload = data(
            "050000000c7373682d7573657261757468")
        var body = Data([10])
        body.append(payload)
        body.append(Data(repeating: 0, count: 10))
        let head = data("0000001c")
        let sealed = try SSHClient.gcmSeal(
            key: key, fixed: fixed, counter: counter,
            body: body, head: head)
        XCTAssertEqual(head + sealed, data(gcmWire))
        let opened = try SSHClient.gcmOpen(
            key: key, fixed: fixed, counter: counter,
            head: head, sealed: sealed)
        XCTAssertEqual(opened, body)
    }

    func testKexInitRoundTrip() throws {
        let client = SSHClient(host: "h", port: 22,
                               user: "u")
        let built = client.buildKexInit()
        let parsed = try XCTUnwrap(
            client.parseKexInit(built))
        XCTAssertTrue(parsed.kex.contains(
            "curve25519-sha256"))
        XCTAssertTrue(parsed.kex.contains(
            "curve25519-sha256@libssh.org"))
        XCTAssertTrue(parsed.hostKeys.contains(
            "ssh-ed25519"))
        XCTAssertTrue(parsed.hostKeys.contains(
            "ecdsa-sha2-nistp256"))
        XCTAssertTrue(parsed.ciphersToServer.contains(
            "aes256-gcm@openssh.com"))
    }

    func testMpintEdges() {
        XCTAssertEqual(SSHWire.mpint(Data([0x80])),
                       data("0000000200" + "80"))
        XCTAssertEqual(SSHWire.mpint(Data([0x7f])),
                       data("00000001" + "7f"))
        XCTAssertEqual(
            SSHWire.mpint(Data([0x00, 0x40])),
            data("00000001" + "40"))
        XCTAssertEqual(
            SSHWire.mpint(Data([0x00, 0x80])),
            data("00000002" + "0080"))
        XCTAssertEqual(
            SSHWire.mpint(Data([0x00, 0x00, 0x40])),
            data("00000001" + "40"))
    }
}
