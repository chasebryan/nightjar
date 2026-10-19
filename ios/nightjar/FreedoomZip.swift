import Foundation

// FreedoomZip — the smallest honest door
// into a .zip: a central-directory scan,
// one entry's bytes, a from-scratch
// DEFLATE decoder (RFC 1951), and a
// CRC-32 check against the directory's
// own record, so a bad extraction can
// never pass for a good one. It exists
// for exactly one job: taking the WAD
// out of Freedoom's official release
// zip the first time the room opens.

enum FreedoomZipError: Error {
    case notAZip
    case entryMissing(String)
    case unsupportedMethod(Int)
    case corrupt(String)
    case sizeMismatch
    case crcMismatch
}

enum FreedoomZip {

    struct Entry {
        let name: String
        let method: Int
        let crc32: UInt32
        let compressedSize: Int
        let size: Int
        let localOffset: Int
    }

    static func entries(in data: Data)
        throws -> [Entry] {
        let bytes = [UInt8](data)
        // The end-of-central-directory
        // record lives in the last 64 KB.
        let floor = max(0, bytes.count - 65_558)
        var eocd = -1
        var at = bytes.count - 22
        while at >= floor {
            if bytes[at] == 0x50,
               bytes[at + 1] == 0x4B,
               bytes[at + 2] == 0x05,
               bytes[at + 3] == 0x06 {
                eocd = at
                break
            }
            at -= 1
        }
        guard eocd >= 0 else {
            throw FreedoomZipError.notAZip
        }
        func u16(_ i: Int) -> Int {
            Int(bytes[i])
                | Int(bytes[i + 1]) << 8
        }
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i])
                | UInt32(bytes[i + 1]) << 8
                | UInt32(bytes[i + 2]) << 16
                | UInt32(bytes[i + 3]) << 24
        }
        let count = u16(eocd + 10)
        var cursor = Int(u32(eocd + 16))
        var found: [Entry] = []
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count,
                  u32(cursor) == 0x0201_4B50
            else {
                throw FreedoomZipError
                    .corrupt("central directory")
            }
            let nameLen = u16(cursor + 28)
            let extraLen = u16(cursor + 30)
            let commentLen = u16(cursor + 32)
            let nameStart = cursor + 46
            let name = String(
                bytes: bytes[
                    nameStart..<(nameStart
                        + nameLen)],
                encoding: .utf8) ?? ""
            found.append(Entry(
                name: name,
                method: u16(cursor + 10),
                crc32: u32(cursor + 16),
                compressedSize: Int(
                    u32(cursor + 20)),
                size: Int(u32(cursor + 24)),
                localOffset: Int(
                    u32(cursor + 42))))
            cursor = nameStart + nameLen
                + extraLen + commentLen
        }
        return found
    }

    static func extract(_ entry: Entry,
                        from data: Data)
        throws -> Data {
        let bytes = [UInt8](data)
        let at = entry.localOffset
        guard at + 30 <= bytes.count,
              bytes[at] == 0x50,
              bytes[at + 1] == 0x4B,
              bytes[at + 2] == 0x03,
              bytes[at + 3] == 0x04
        else {
            throw FreedoomZipError
                .corrupt("local header")
        }
        func u16(_ i: Int) -> Int {
            Int(bytes[i])
                | Int(bytes[i + 1]) << 8
        }
        let start = at + 30
            + u16(at + 26) + u16(at + 28)
        let end = start
            + entry.compressedSize
        guard end <= bytes.count else {
            throw FreedoomZipError
                .corrupt("entry overruns file")
        }
        let raw = Array(bytes[start..<end])
        let plain: [UInt8]
        switch entry.method {
        case 0:
            plain = raw
        case 8:
            plain = try Inflate.decode(raw)
        default:
            throw FreedoomZipError
                .unsupportedMethod(entry.method)
        }
        guard plain.count == entry.size else {
            throw FreedoomZipError.sizeMismatch
        }
        guard CRC32.checksum(plain)
                == entry.crc32 else {
            throw FreedoomZipError.crcMismatch
        }
        return Data(plain)
    }

    /// Undo a gzip member: header off,
    /// deflate through the same decoder
    /// the zip path uses, trailer's CRC
    /// and size checked. The room's
    /// engine rides in the bundle as
    /// base64'd gzip (the repo's doors
    /// are text-shaped); this is its way
    /// back to bytes.
    static func gunzip(_ data: Data)
        throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18,
              bytes[0] == 0x1F,
              bytes[1] == 0x8B,
              bytes[2] == 8
        else {
            throw FreedoomZipError
                .corrupt("gzip header")
        }
        let flags = bytes[3]
        var cursor = 10
        if flags & 0x04 != 0 {
            guard cursor + 2 <= bytes.count
            else {
                throw FreedoomZipError
                    .corrupt("gzip extra")
            }
            let extra = Int(bytes[cursor])
                | Int(bytes[cursor + 1]) << 8
            cursor += 2 + extra
        }
        for bit: UInt8 in [0x08, 0x10]
            where flags & bit != 0 {
            while cursor < bytes.count,
                  bytes[cursor] != 0 {
                cursor += 1
            }
            cursor += 1
        }
        if flags & 0x02 != 0 {
            cursor += 2
        }
        guard cursor < bytes.count - 8
        else {
            throw FreedoomZipError
                .corrupt("gzip body")
        }
        let trailer = bytes.count - 8
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i])
                | UInt32(bytes[i + 1]) << 8
                | UInt32(bytes[i + 2]) << 16
                | UInt32(bytes[i + 3]) << 24
        }
        let plain = try Inflate.decode(
            Array(bytes[cursor..<trailer]))
        guard CRC32.checksum(plain)
                == u32(trailer),
              plain.count
                == Int(u32(trailer + 4))
        else {
            throw FreedoomZipError
                .crcMismatch
        }
        return Data(plain)
    }

    /// Pull one named entry out of a zip
    /// held in memory; the room's whole
    /// use of this file.
    static func entry(named name: String,
                      in data: Data)
        throws -> Data {
        let all = try entries(in: data)
        guard let hit = all.first(
            where: { $0.name == name })
        else {
            throw FreedoomZipError
                .entryMissing(name)
        }
        return try extract(hit, from: data)
    }
}

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { seed -> UInt32 in
            var c = UInt32(seed)
            for _ in 0..<8 {
                c = (c & 1) != 0
                    ? 0xEDB8_8320 ^ (c >> 1)
                    : c >> 1
            }
            return c
        }
    }()

    static func checksum(
        _ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int(
                (crc ^ UInt32(byte)) & 0xFF)]
                ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - DEFLATE

/// A from-scratch DEFLATE decoder.
/// The same algorithm, tables and all,
/// was verified byte-exact against the
/// real Freedoom archive before it was
/// written in Swift: a 28 MB WAD out,
/// bit for bit the archive's own.
enum Inflate {

    private struct BitReader {
        let data: [UInt8]
        var pos = 0
        var bitBuffer: UInt32 = 0
        var bitCount = 0

        mutating func bits(_ count: Int)
            throws -> Int {
            while bitCount < count {
                guard pos < data.count else {
                    throw FreedoomZipError
                        .corrupt("deflate overrun")
                }
                bitBuffer |= UInt32(data[pos])
                    << bitCount
                pos += 1
                bitCount += 8
            }
            let mask: UInt32 = count == 32
                ? 0xFFFF_FFFF
                : (1 << count) - 1
            let value = Int(
                bitBuffer & mask)
            bitBuffer >>= count
            bitCount -= count
            return value
        }

        /// Drop bits to the next byte
        /// boundary of the stream.
        mutating func alignToByte() {
            let drop = bitCount & 7
            bitBuffer >>= drop
            bitCount -= drop
        }

        /// Read one whole byte of a stored
        /// block: buffered bytes first,
        /// then the stream's own.
        mutating func storedByte()
            throws -> UInt8 {
            if bitCount >= 8 {
                let value = UInt8(
                    bitBuffer & 0xFF)
                bitBuffer >>= 8
                bitCount -= 8
                return value
            }
            guard pos < data.count else {
                throw FreedoomZipError
                    .corrupt("stored overrun")
            }
            let value = data[pos]
            pos += 1
            return value
        }
    }

    private struct Huffman {
        // Canonical codes, keyed by
        // (length << 20) | code.
        let table: [Int: Int]
        let maxBits: Int

        init(lengths: [Int]) {
            var counts: [Int: Int] = [:]
            var peak = 0
            for length in lengths
                where length > 0 {
                counts[length] =
                    (counts[length] ?? 0) + 1
                peak = max(peak, length)
            }
            var next: [Int: Int] = [:]
            var code = 0
            for bit in 1...max(peak, 1) {
                code = (code
                    + (counts[bit - 1] ?? 0))
                    << 1
                next[bit] = code
            }
            var map: [Int: Int] = [:]
            for (symbol, length)
                in lengths.enumerated()
                where length > 0 {
                let key = (length << 20)
                    | (next[length] ?? 0)
                map[key] = symbol
                next[length] =
                    (next[length] ?? 0) + 1
            }
            table = map
            maxBits = peak
        }

        func decode(
            _ reader: inout BitReader)
            throws -> Int {
            var code = 0
            var length = 0
            while length < maxBits {
                length += 1
                code = (code << 1)
                    | (try reader.bits(1))
                if let symbol = table[
                    (length << 20) | code] {
                    return symbol
                }
            }
            throw FreedoomZipError
                .corrupt("bad huffman code")
        }
    }

    private static let lengthBase =
        [3, 4, 5, 6, 7, 8, 9, 10, 11, 13,
         15, 17, 19, 23, 27, 31, 35, 43, 51,
         59, 67, 83, 99, 115, 131, 163, 195,
         227, 258]
    private static let lengthExtra =
        [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
         2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4,
         5, 5, 5, 5, 0]
    private static let distanceBase =
        [1, 2, 3, 4, 5, 7, 9, 13, 17, 25,
         33, 49, 65, 97, 129, 193, 257, 385,
         513, 769, 1025, 1537, 2049, 3073,
         4097, 6145, 8193, 12289, 16385,
         24577]
    private static let distanceExtra =
        [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4,
         5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10,
         10, 11, 11, 12, 12, 13, 13]
    private static let codeLengthOrder =
        [16, 17, 18, 0, 8, 7, 9, 6, 10, 5,
         11, 4, 12, 3, 13, 2, 14, 1, 15]

    static func decode(_ data: [UInt8])
        throws -> [UInt8] {
        var reader = BitReader(data: data)
        var out: [UInt8] = []
        out.reserveCapacity(
            data.count * 3)
        while true {
            let final = try reader.bits(1)
            let kind = try reader.bits(2)
            switch kind {
            case 0:
                reader.alignToByte()
                var raw: [UInt8] = []
                for _ in 0..<4 {
                    raw.append(
                        try reader
                            .storedByte())
                }
                let length = Int(raw[0])
                    | Int(raw[1]) << 8
                for _ in 0..<length {
                    out.append(
                        try reader
                            .storedByte())
                }
            case 1, 2:
                let litLengths: [Int]
                let distLengths: [Int]
                if kind == 1 {
                    litLengths =
                        [Int](repeating: 8,
                              count: 144)
                        + [Int](repeating: 9,
                                count: 112)
                        + [Int](repeating: 7,
                                count: 24)
                        + [Int](repeating: 8,
                                count: 8)
                    distLengths =
                        [Int](repeating: 5,
                              count: 32)
                } else {
                    let parsed = try dynamicTables(
                        &reader)
                    litLengths = parsed.0
                    distLengths = parsed.1
                }
                try compressedBlock(
                    &reader, into: &out,
                    lit: Huffman(
                        lengths: litLengths),
                    dist: Huffman(
                        lengths: distLengths))
            default:
                throw FreedoomZipError
                    .corrupt("bad block kind")
            }
            if final == 1 {
                return out
            }
        }
    }

    private static func dynamicTables(
        _ reader: inout BitReader)
        throws -> ([Int], [Int]) {
        let litCount = try reader.bits(5)
            + 257
        let distCount = try reader.bits(5)
            + 1
        let codeCount = try reader.bits(4)
            + 4
        var lengths = [Int](
            repeating: 0, count: 19)
        for index in 0..<codeCount {
            lengths[codeLengthOrder[index]] =
                try reader.bits(3)
        }
        let codeHuffman = Huffman(
            lengths: lengths)
        var all: [Int] = []
        while all.count
                < litCount + distCount {
            let symbol = try codeHuffman
                .decode(&reader)
            switch symbol {
            case 0..<16:
                all.append(symbol)
            case 16:
                guard let last = all.last
                else {
                    throw FreedoomZipError
                        .corrupt("repeat w/o last")
                }
                let count = 3
                    + (try reader.bits(2))
                all.append(contentsOf:
                    [Int](repeating: last,
                          count: count))
            case 17:
                let count = 3
                    + (try reader.bits(3))
                all.append(contentsOf:
                    [Int](repeating: 0,
                          count: count))
            default:
                let count = 11
                    + (try reader.bits(7))
                all.append(contentsOf:
                    [Int](repeating: 0,
                          count: count))
            }
        }
        return (Array(all[..<litCount]),
                Array(all[litCount...]))
    }

    private static func compressedBlock(
        _ reader: inout BitReader,
        into out: inout [UInt8],
        lit: Huffman, dist: Huffman)
        throws {
        while true {
            let symbol = try lit
                .decode(&reader)
            if symbol < 256 {
                out.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let index = symbol - 257
                guard index < lengthBase.count
                else {
                    throw FreedoomZipError
                        .corrupt("length symbol")
                }
                let length = lengthBase[index]
                    + (try reader.bits(
                        lengthExtra[index]))
                let distSymbol = try dist
                    .decode(&reader)
                guard distSymbol
                        < distanceBase.count
                else {
                    throw FreedoomZipError
                        .corrupt("distance symbol")
                }
                let distance =
                    distanceBase[distSymbol]
                    + (try reader.bits(
                        distanceExtra[
                            distSymbol]))
                guard distance <= out.count
                else {
                    throw FreedoomZipError
                        .corrupt("distance too far")
                }
                let start = out.count
                    - distance
                for step in 0..<length {
                    out.append(
                        out[start + step])
                }
            }
        }
    }
}
