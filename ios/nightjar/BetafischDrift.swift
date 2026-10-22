// BetafischDrift.swift
//
// Driftnet, the house way: the media
// extraction pass inside betafisch. A
// capture the operator brings is taken
// apart into TCP streams — reassembled
// byte by byte in sequence order — and
// the pictures the streams carried are
// lifted out and pinned up: the ones
// HTTP served, and the ones a signature
// scan finds in any stream at all.
//
// Read-only, like everything betafisch
// does: nothing is transmitted, nothing
// is sniffed live. The wire stays the
// phone's; what arrived in the capture
// is what gets read.

import Foundation
import CryptoKit
import ImageIO

/// One picture lifted off the wire.
struct DriftObject: Identifiable {
    enum Kind: String {
        case jpeg
        case png
        case gif
        case webp
        case bmp

        /// How the kind reads on a tile
        /// and a provenance line.
        var displayName: String {
            switch self {
            case .jpeg: return L("JPEG")
            case .png: return L("PNG")
            case .gif: return L("GIF")
            case .webp: return L("WebP")
            case .bmp: return L("BMP")
            }
        }

        /// The extension the Deliveries
        /// shelf files it under.
        var fileExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .gif: return "gif"
            case .webp: return "webp"
            case .bmp: return "bmp"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let data: Data
    /// Who carried it: the stream's two
    /// ends, "ip:port ↔ ip:port".
    let source: String
    /// The HTTP dressing, when the
    /// object was served rather than
    /// carved: the request's method,
    /// its path, and its Host.
    let method: String?
    let path: String?
    let host: String?
    /// True when an HTTP response body
    /// carried the object; false when
    /// the signature scan carved it.
    var viaHTTP: Bool
    /// The first and last frame whose
    /// bytes the object is made of.
    let firstFrame: Int
    let lastFrame: Int
    /// The stream it came out of had a
    /// hole in it — some bytes never
    /// arrived in the capture.
    let torn: Bool
    /// The full SHA-256, hex.
    let sha256: String
    /// How many times these exact bytes
    /// turned up across the capture.
    var hitCount: Int = 1
    /// A small rendering for the
    /// gallery wall, made once here so
    /// a scrolling grid never re-decodes
    /// the original bytes.
    let thumbnail: Data?

    var byteCount: Int { data.count }

    /// The hash's front door — enough
    /// to tell two objects apart.
    var shortSHA: String {
        String(sha256.prefix(12))
    }
}

/// What one extraction pass found,
/// beyond the objects themselves.
struct DriftStats {
    /// Conversations reassembly saw.
    var flows = 0
    /// Half-streams with a hole in them.
    var tornStreams = 0
    /// Half-streams past the stream cap:
    /// only their first stretch was read.
    var cappedStreams = 0
    /// Objects found before dedupe.
    var occurrences = 0
    /// The 500-object wall was reached.
    var hitObjectCap = false
}

/// The pass's whole answer: the
/// gallery, and the reckoning.
struct DriftExtraction {
    let objects: [DriftObject]
    let stats: DriftStats
}

enum BetafischDrift {

    // MARK: Limits

    /// Nothing smaller is a picture.
    static let minObject = 40
    /// Nothing bigger is lifted.
    static let maxObject = 25_000_000
    /// The gallery's wall.
    static let objectCap = 500
    /// How much of one stream's run is
    /// read before the rest is left.
    static let streamCap = 64_000_000

    // MARK: The stream, reassembled

    /// One placed stretch of stream
    /// bytes, and the frame it rode in
    /// on. The segment map.
    struct Piece {
        let start: Int
        let end: Int
        let frame: Int
    }

    /// One direction of one conversation,
    /// laid out in sequence order.
    struct HalfStream {
        /// Contiguous stretches, ascending,
        /// never overlapping. A gap between
        /// two runs is a hole in the stream.
        var runs: [(start: Int,
                   bytes: [UInt8],
                   pieces: [Piece])] = []
        /// A hole was found — bytes the
        /// capture never held.
        var torn = false
        /// The stream ran past the cap;
        /// only its first stretch is here.
        var capped = false
    }

    /// A conversation: both directions
    /// and their names.
    struct Flow {
        var aToB = HalfStream()
        var bToA = HalfStream()
        var label = ""
        let aLabel: String
        let bLabel: String
    }

    /// The distance from one sequence
    /// number to another, read the
    /// wrap-aware way TCP means it: the
    /// signed shortest walk around the
    /// 2^32 ring.
    static func seqDelta(_ from: Int, _ to: Int) -> Int {
        var delta = (to - from) % 4_294_967_296
        if delta < 0 { delta += 4_294_967_296 }
        if delta >= 2_147_483_648 {
            delta -= 4_294_967_296
        }
        return delta
    }

    /// Lay one direction's segments out
    /// in sequence order. Segments are
    /// fed in frame order and the first
    /// arrival wins: a retransmit's
    /// bytes are already on the table,
    /// so the copy is set aside and only
    /// its fresh fringe — past the end
    /// of what is placed, or into a hole
    /// — is kept, credited to the frame
    /// that brought it. Nothing past the
    /// stream cap is placed.
    static func assemble(
        _ segments: [(seq: Int, flags: Int,
                      bytes: [UInt8], frame: Int)]
    ) -> HalfStream {
        var half = HalfStream()
        guard !segments.isEmpty else {
            return half
        }
        // The origin: a SYN spends its
        // own number, so the first data
        // byte lives at ISN+1. No SYN in
        // the capture — the conversation
        // was already talking — and the
        // first payload seen anchors the
        // layout instead.
        var origin: Int? = nil
        for segment in segments
        where (segment.flags & 0x02) != 0 {
            origin = segment.seq
            break
        }
        if origin == nil {
            for segment in segments
            where !segment.bytes.isEmpty {
                origin = segment.seq
                break
            }
        }
        guard let base = origin else {
            return half
        }
        // Placed intervals: (start, end,
        // frame) — kept sorted and
        // disjoint by construction; the
        // runs below merge their bytes.
        var placed: [(start: Int, end: Int,
                      frame: Int,
                      bytes: ArraySlice<UInt8>)] = []
        var clipped = false
        for segment in segments {
            guard !segment.bytes.isEmpty else {
                continue
            }
            var offset = seqDelta(base, segment.seq)
            if (segment.flags & 0x02) != 0 {
                offset -= 1
            }
            // The piece is materialised as
            // its own array, so every index
            // below is a plain zero-based
            // one, however it gets trimmed.
            var slice = segment.bytes
            // Bytes from before the origin
            // belong to a part of the
            // conversation the capture
            // opened mid-sentence; they
            // cannot be placed, so they
            // are trimmed off the front.
            if offset < 0 {
                let cut = -offset
                guard cut < slice.count else {
                    continue
                }
                slice = Array(slice.dropFirst(cut))
                offset = 0
            }
            // The cap: nothing is placed
            // past it, and a segment that
            // crosses it is trimmed there.
            if offset >= streamCap {
                clipped = true
                continue
            }
            if offset + slice.count > streamCap {
                slice = Array(slice.prefix(
                    streamCap - offset))
                clipped = true
            }
            // What survives is what the
            // placed intervals do not
            // already cover.
            var fresh: [(start: Int, end: Int,
                         frame: Int,
                         bytes: ArraySlice<UInt8>)] = []
            var cursor = offset
            let segEnd = offset + slice.count
            for interval in placed {
                if interval.end <= cursor {
                    continue
                }
                if interval.start >= segEnd {
                    break
                }
                if interval.start > cursor {
                    let stop = min(interval.start,
                                   segEnd)
                    let sliceLo = cursor - offset
                    let sliceHi = stop - offset
                    fresh.append((
                        start: cursor, end: stop,
                        frame: segment.frame,
                        bytes: slice[sliceLo..<sliceHi]))
                }
                cursor = max(cursor, interval.end)
                if cursor >= segEnd { break }
            }
            if cursor < segEnd {
                let tailLo = cursor - offset
                fresh.append((
                    start: cursor, end: segEnd,
                    frame: segment.frame,
                    bytes: slice[tailLo..<slice.count]))
            }
            if !fresh.isEmpty {
                placed.append(contentsOf: fresh)
                placed.sort {
                    $0.start < $1.start
                }
                // A pathological capture
                // cannot be allowed to grind
                // the pass to a halt.
                if placed.count > 250_000 {
                    clipped = true
                    break
                }
            }
        }
        half.capped = clipped
        // Merge the intervals into runs;
        // a gap between two intervals is
        // a hole, and the stream is torn.
        var index = 0
        while index < placed.count {
            let first = placed[index]
            var bytes: [UInt8] = []
            bytes.append(contentsOf: first.bytes)
            var pieces = [Piece(start: first.start,
                                end: first.end,
                                frame: first.frame)]
            var end = first.end
            index += 1
            while index < placed.count,
                  placed[index].start == end {
                bytes.append(contentsOf:
                                placed[index].bytes)
                pieces.append(Piece(
                    start: placed[index].start,
                    end: placed[index].end,
                    frame: placed[index].frame))
                end = placed[index].end
                index += 1
            }
            if !half.runs.isEmpty {
                half.torn = true
            }
            half.runs.append((start: first.start,
                              bytes: bytes,
                              pieces: pieces))
        }
        return half
    }

    // MARK: Grouping

    /// Gather a capture's TCP frames
    /// into conversations, each end named
    /// by its address and port.
    static func flows(of capture: BFCapture)
        -> [Flow] {
        struct Side {
            var segments: [(seq: Int, flags: Int,
                            bytes: [UInt8],
                            frame: Int)] = []
        }
        var order: [String] = []
        var halves: [String: [Side]] = [:]
        var names: [String: (String, String)] = [:]
        for frame in capture.frames {
            guard frame.isTCP,
                  let src = frame.ipSrc,
                  let dst = frame.ipDst,
                  let sport = frame.srcPort,
                  let dport = frame.dstPort,
                  let seq = frame.tcpSeq else {
                continue
            }
            let aLabel = "\(src):\(sport)"
            let bLabel = "\(dst):\(dport)"
            let low = min(aLabel, bLabel)
            let high = max(aLabel, bLabel)
            let key = low + " <> " + high
            if halves[key] == nil {
                halves[key] = [Side(), Side()]
                names[key] = (low, high)
                order.append(key)
            }
            // Direction 0 always runs from
            // the lexicographically lower
            // end to the higher, whichever
            // way this frame was headed.
            let direction = aLabel == low ? 0 : 1
            var payload: [UInt8] = []
            if let range = frame.tcpPayloadRange {
                let loBound = max(0, min(
                    range.lowerBound,
                    frame.bytes.count))
                let hiBound = max(loBound, min(
                    range.upperBound,
                    frame.bytes.count))
                payload = Array(
                    frame.bytes[loBound..<hiBound])
            }
            halves[key]?[direction].segments.append((
                seq: seq, flags: frame.tcpFlags,
                bytes: payload, frame: frame.number))
        }
        var flows: [Flow] = []
        for key in order {
            guard let pair = halves[key],
                  let namePair = names[key] else {
                continue
            }
            var flow = Flow(aLabel: namePair.0,
                            bLabel: namePair.1)
            flow.aToB = assemble(pair[0].segments)
            flow.bToA = assemble(pair[1].segments)
            flow.label = namePair.0 + " ↔ "
                + namePair.1
            flows.append(flow)
        }
        return flows
    }

    // MARK: HTTP

    /// One request read off a client
    /// stream: enough to label what the
    /// server sent back.
    struct DriftRequest {
        let method: String
        let path: String
        let host: String?
    }

    /// One response found on a server
    /// stream, and the stream range its
    /// body covers — the range is how the
    /// carver later knows these bytes
    /// were already claimed.
    struct DriftResponse {
        let bodyRange: Range<Int>
        let body: ArraySlice<UInt8>
        let requestIndex: Int
    }

    /// Read headers off a run: the block
    /// from the stream offset `at` to the
    /// blank line, naming its end — both
    /// in stream coordinates, like every
    /// offset this pass trades in. Both
    /// CRLF and bare-LF endings are
    /// accepted — the wire is not always
    /// polite.
    static func headerBlock(in run: (start: Int,
                                     bytes: [UInt8],
                                     pieces: [Piece]),
                            at offset: Int)
        -> (fields: [String: String],
            end: Int)? {
        let bytes = run.bytes
        var pos = offset - run.start
        var fields: [String: String] = [:]
        var first = true
        while pos < bytes.count {
            var lineEnd = pos
            while lineEnd < bytes.count,
                  bytes[lineEnd] != 0x0a {
                lineEnd += 1
            }
            guard lineEnd < bytes.count else {
                return nil
            }
            var line = bytes[pos..<lineEnd]
            if line.last == 0x0d {
                line = line.dropLast()
            }
            let next = lineEnd + 1
            if line.isEmpty {
                return (fields, run.start + next)
            }
            if !first {
                let text = String(decoding: line,
                                  as: UTF8.self)
                if let colon = text.firstIndex(
                    of: ":") {
                    let namePart = text[..<colon]
                    let name = String(namePart)
                        .trimmingCharacters(
                            in: .whitespaces)
                        .lowercased()
                    let value = text[
                        text.index(after: colon)...]
                        .trimmingCharacters(
                            in: .whitespaces)
                    if fields[name] == nil {
                        fields[name] = value
                    }
                }
            }
            first = false
            pos = next
        }
        return nil
    }

    /// Does a run, at a stream offset,
    /// begin with these bytes?
    static func runStarts(_ run: (start: Int,
                                  bytes: [UInt8],
                                  pieces: [Piece]),
                          at offset: Int,
                          with prefix: [UInt8]) -> Bool {
        let local = offset - run.start
        guard local >= 0,
              local + prefix.count <= run.bytes.count
        else {
            return false
        }
        for (index, byte) in prefix.enumerated() {
            if run.bytes[local + index] != byte {
                return false
            }
        }
        return true
    }

    /// The requests a client stream
    /// holds, in the order it made them.
    static func parseRequests(
        _ half: HalfStream) -> [DriftRequest] {
        let methods = ["GET", "POST", "PUT",
                       "DELETE", "HEAD", "OPTIONS",
                       "PATCH", "TRACE", "CONNECT"]
        var requests: [DriftRequest] = []
        for run in half.runs {
            var pos = run.start
            let runEnd = run.start + run.bytes.count
            while pos < runEnd {
                guard let block = headerBlock(
                    in: run, at: pos) else {
                    break
                }
                let local = pos - run.start
                var lineEnd = local
                while lineEnd < run.bytes.count,
                      run.bytes[lineEnd] != 0x0a {
                    lineEnd += 1
                }
                var lineBytes = run.bytes[
                    local..<lineEnd]
                if lineBytes.last == 0x0d {
                    lineBytes = lineBytes.dropLast()
                }
                let line = String(
                    decoding: lineBytes, as: UTF8.self)
                let words = line.split(separator: " ")
                guard words.count >= 3,
                      methods.contains(String(words[0])),
                      words[2].hasPrefix("HTTP/1.")
                else {
                    break
                }
                requests.append(DriftRequest(
                    method: String(words[0]),
                    path: String(words[1]),
                    host: block.fields["host"]))
                // A request body is stepped
                // over, not read.
                var next = block.end
                if let lengthText = block.fields[
                    "content-length"],
                   let length = Int(lengthText),
                   length >= 0 {
                    next = min(runEnd, next + length)
                }
                pos = next
            }
        }
        return requests
    }

    /// Decode a chunked body starting at
    /// a stream offset. The decoded bytes
    /// come back with the offset just past
    /// the trailer; a run that ends
    /// mid-chunk gives back what decoded
    /// whole.
    static func decodeChunked(
        _ run: (start: Int, bytes: [UInt8],
                pieces: [Piece]),
        at offset: Int)
        -> (body: [UInt8], end: Int) {
        let bytes = run.bytes
        var pos = offset - run.start
        var body: [UInt8] = []
        while pos < bytes.count {
            var lineEnd = pos
            while lineEnd < bytes.count,
                  bytes[lineEnd] != 0x0a {
                lineEnd += 1
            }
            guard lineEnd < bytes.count else {
                return (body, run.start + pos)
            }
            var sizeText = String(
                decoding: bytes[pos..<lineEnd],
                as: UTF8.self)
            if sizeText.hasSuffix("\r") {
                sizeText = String(sizeText.dropLast())
            }
            if let semi = sizeText.firstIndex(
                of: ";") {
                sizeText = String(
                    sizeText[..<semi])
            }
            guard let size = Int(
                sizeText.trimmingCharacters(
                    in: .whitespaces),
                radix: 16) else {
                return (body, run.start + pos)
            }
            pos = lineEnd + 1
            if size == 0 {
                // The trailer: header-shaped
                // lines to a blank one.
                while pos < bytes.count {
                    var end = pos
                    while end < bytes.count,
                          bytes[end] != 0x0a {
                        end += 1
                    }
                    guard end < bytes.count else {
                        return (body, run.start + pos)
                    }
                    let empty = end == pos
                        || (end == pos + 1
                            && bytes[pos] == 0x0d)
                    pos = end + 1
                    if empty { break }
                }
                return (body, run.start + pos)
            }
            guard pos + size <= bytes.count else {
                return (body, run.start + pos)
            }
            body.append(contentsOf:
                            bytes[pos..<(pos + size)])
            pos += size
            if pos < bytes.count,
               bytes[pos] == 0x0d {
                pos += 1
            }
            if pos < bytes.count,
               bytes[pos] == 0x0a {
                pos += 1
            }
        }
        return (body, run.start + pos)
    }

    /// The responses a server stream
    /// holds, in the order it sent them,
    /// each paired to its request by
    /// number.
    static func parseResponses(
        _ half: HalfStream,
        requestCount: Int) -> [DriftResponse] {
        var responses: [DriftResponse] = []
        var requestIndex = 0
        for run in half.runs {
            var pos = run.start
            let runEnd = run.start + run.bytes.count
            while pos < runEnd {
                let messageStart = pos
                guard runStarts(run, at: pos,
                                with: [0x48, 0x54,
                                       0x54, 0x50,
                                       0x2f, 0x31,
                                       0x2e])
                else {
                    break
                }
                guard let block = headerBlock(
                    in: run, at: pos) else {
                    break
                }
                let local = pos - run.start
                var lineEnd = local
                while lineEnd < run.bytes.count,
                      run.bytes[lineEnd] != 0x0a {
                    lineEnd += 1
                }
                var statusBytes = run.bytes[
                    local..<lineEnd]
                if statusBytes.last == 0x0d {
                    statusBytes =
                        statusBytes.dropLast()
                }
                let statusLine = String(
                    decoding: statusBytes,
                    as: UTF8.self)
                let words = statusLine.split(
                    separator: " ")
                guard words.count >= 2,
                      let code = Int(words[1]),
                      (100...599).contains(code)
                else {
                    break
                }
                let bodyAt = block.end
                // Statuses that carry no body
                // by the book. A 1xx is an
                // interim word — the real
                // answer still belongs to the
                // same request; 204 and 304
                // ARE the answer, and take
                // their request with them.
                if (100...199).contains(code) {
                    pos = bodyAt
                    continue
                }
                if code == 204 || code == 304 {
                    requestIndex += 1
                    pos = bodyAt
                    continue
                }
                let headers = block.fields
                var body: ArraySlice<UInt8> = []
                var bodyRange = bodyAt..<bodyAt
                var next = runEnd
                let encoding = headers[
                    "transfer-encoding"]?
                    .lowercased() ?? ""
                if encoding.contains("chunked") {
                    let decoded = decodeChunked(
                        run, at: bodyAt)
                    body = ArraySlice(decoded.body)
                    bodyRange = bodyAt..<decoded.end
                    next = decoded.end
                } else if let lengthText = headers[
                    "content-length"],
                          let length = Int(lengthText),
                          length >= 0 {
                    let stop = min(runEnd,
                                   bodyAt + length)
                    let from = bodyAt - run.start
                    let to = stop - run.start
                    body = run.bytes[from..<to]
                    bodyRange = bodyAt..<stop
                    next = stop
                } else {
                    // Nothing declared: the
                    // body runs to the end of
                    // the run, and no further
                    // response can follow it.
                    let from = bodyAt - run.start
                    body = run.bytes[from...]
                    bodyRange = bodyAt..<runEnd
                    next = runEnd
                }
                responses.append(DriftResponse(
                    bodyRange: bodyRange, body: body,
                    requestIndex: requestIndex))
                requestIndex += 1
                pos = next
                if pos <= messageStart { break }
            }
        }
        return responses
    }

    // MARK: Signatures

    /// Unsigned 16-bit reads, both orders.
    static func u16beAt(_ bytes: [UInt8],
                        _ at: Int) -> Int? {
        guard at >= 0, at + 1 < bytes.count else {
            return nil
        }
        return (Int(bytes[at]) << 8) | Int(bytes[at + 1])
    }

    static func u16leAt(_ bytes: [UInt8],
                        _ at: Int) -> Int? {
        guard at >= 0, at + 1 < bytes.count else {
            return nil
        }
        return Int(bytes[at]) | (Int(bytes[at + 1]) << 8)
    }

    /// Unsigned 32-bit reads, both orders.
    static func u32beAt(_ bytes: [UInt8],
                        _ at: Int) -> Int? {
        guard at >= 0, at + 3 < bytes.count else {
            return nil
        }
        return (Int(bytes[at]) << 24)
            | (Int(bytes[at + 1]) << 16)
            | (Int(bytes[at + 2]) << 8)
            | Int(bytes[at + 3])
    }

    static func u32leAt(_ bytes: [UInt8],
                        _ at: Int) -> Int? {
        guard at >= 0, at + 3 < bytes.count else {
            return nil
        }
        return Int(bytes[at])
            | (Int(bytes[at + 1]) << 8)
            | (Int(bytes[at + 2]) << 16)
            | (Int(bytes[at + 3]) << 24)
    }

    /// Bounds every candidate must meet.
    static func saneLength(_ length: Int) -> Bool {
        length >= minObject && length <= maxObject
    }

    /// A JPEG at `at`: the marker chain
    /// must be sound all the way to the
    /// end-of-image word. Returns the end
    /// offset (exclusive), or nil — a
    /// candidate that fails anywhere is
    /// dropped whole, never shown broken.
    static func carveEndJPEG(_ bytes: [UInt8],
                             at start: Int) -> Int? {
        guard start + 4 <= bytes.count,
              bytes[start] == 0xff,
              bytes[start + 1] == 0xd8,
              bytes[start + 2] == 0xff else {
            return nil
        }
        // The first marker after the
        // start-of-image word must be a
        // real segment (an APPn, a
        // quantisation table, a frame) —
        // never another SOI, never the
        // entropy data itself.
        let first = bytes[start + 3]
        guard first >= 0xc0, first != 0xd8 else {
            return nil
        }
        let limit = min(bytes.count,
                        start + maxObject)
        var pos = start + 2
        while pos + 1 < limit {
            guard bytes[pos] == 0xff else {
                return nil
            }
            let marker = Int(bytes[pos + 1])
            if marker == 0xd9 {
                // End of image before any
                // scan data — not a picture.
                return nil
            }
            if marker == 0xda {
                // Start of scan: step over
                // its own segment, then walk
                // the entropy data to the
                // end-of-image word, hopping
                // stuffed bytes and restarts.
                guard let segLen = u16beAt(bytes,
                                           pos + 2),
                      segLen >= 2 else {
                    return nil
                }
                var scan = pos + 2 + segLen
                while scan + 1 < limit {
                    if bytes[scan] != 0xff {
                        scan += 1
                        continue
                    }
                    let code = Int(bytes[scan + 1])
                    if code == 0x00
                        || (0xd0...0xd7)
                            .contains(code) {
                        scan += 2
                        continue
                    }
                    if code == 0xd9 {
                        let end = scan + 2
                        return saneLength(
                            end - start) ? end : nil
                    }
                    return nil
                }
                return nil
            }
            if marker == 0x01
                || (0xd0...0xd7).contains(marker) {
                pos += 2
                continue
            }
            if marker == 0xd8 {
                return nil
            }
            guard let segLen = u16beAt(bytes,
                                       pos + 2),
                  segLen >= 2 else {
                return nil
            }
            pos += 2 + segLen
        }
        return nil
    }

    /// A PNG at `at`: the signature, an
    /// IHDR first, a sound chunk chain,
    /// at least one IDAT, and the IEND
    /// that ends it.
    static func carveEndPNG(_ bytes: [UInt8],
                            at start: Int) -> Int? {
        let signature: [UInt8] = [0x89, 0x50, 0x4e,
                                  0x47, 0x0d, 0x0a,
                                  0x1a, 0x0a]
        guard start + 8 <= bytes.count else {
            return nil
        }
        for (index, byte) in signature.enumerated() {
            if bytes[start + index] != byte {
                return nil
            }
        }
        let limit = min(bytes.count,
                        start + maxObject)
        var pos = start + 8
        var sawIDAT = false
        var firstChunk = true
        while pos + 8 <= limit {
            guard let length = u32beAt(bytes, pos)
            else {
                return nil
            }
            let typeAt = pos + 4
            var type = ""
            for index in 0..<4 {
                let byte = bytes[typeAt + index]
                let byteValue = Int(byte)
                guard (65...90).contains(byteValue)
                    || (97...122).contains(byteValue)
                else {
                    return nil
                }
                type.append(Character(
                    UnicodeScalar(byte)))
            }
            if firstChunk {
                guard type == "IHDR",
                      length == 13 else {
                    return nil
                }
            }
            let chunkEnd = pos + 8 + length + 4
            guard chunkEnd <= limit else {
                return nil
            }
            if type == "IDAT" { sawIDAT = true }
            if type == "IEND" {
                guard length == 0, sawIDAT else {
                    return nil
                }
                return saneLength(
                    chunkEnd - start) ? chunkEnd : nil
            }
            pos = chunkEnd
            firstChunk = false
        }
        return nil
    }

    /// A GIF sub-block chain at `pos`: a
    /// run of size-prefixed pieces closed
    /// by a zero size. Returns the offset
    /// just past the terminator.
    static func gifBlocks(_ bytes: [UInt8],
                          from pos: Int,
                          limit: Int) -> Int? {
        var cursor = pos
        while cursor < limit {
            let size = Int(bytes[cursor])
            cursor += 1
            if size == 0 { return cursor }
            guard cursor + size <= limit else {
                return nil
            }
            cursor += size
        }
        return nil
    }

    /// A GIF at `at`: header, a sane
    /// logical screen, then a true block
    /// walk — extensions, images, and the
    /// trailer byte that ends it. The
    /// walk, not a search for 0x3B, is
    /// what keeps a stray trailer byte
    /// inside image data from ending the
    /// picture early.
    static func carveEndGIF(_ bytes: [UInt8],
                            at start: Int) -> Int? {
        guard start + 13 <= bytes.count else {
            return nil
        }
        let head = Array(bytes[start..<(start + 6)])
        guard head == [0x47, 0x49, 0x46, 0x38, 0x37,
                       0x61]
            || head == [0x47, 0x49, 0x46, 0x38,
                        0x39, 0x61] else {
            return nil
        }
        guard let width = u16leAt(bytes, start + 6),
              let height = u16leAt(bytes,
                                    start + 8),
              width > 0, height > 0 else {
            return nil
        }
        let packed = bytes[start + 10]
        var pos = start + 13
        if (packed & 0x80) != 0 {
            let tableBytes = 3 * (1 << Int(
                (packed & 0x07) + 1))
            pos += tableBytes
        }
        let limit = min(bytes.count,
                        start + maxObject)
        guard pos <= limit else { return nil }
        var steps = 0
        while pos < limit {
            steps += 1
            if steps > 100_000 { return nil }
            let intro = bytes[pos]
            if intro == 0x3b {
                let end = pos + 1
                return saneLength(
                    end - start) ? end : nil
            }
            if intro == 0x21 {
                guard pos + 2 <= limit else {
                    return nil
                }
                guard let next = gifBlocks(
                    bytes, from: pos + 2,
                    limit: limit) else {
                    return nil
                }
                pos = next
                continue
            }
            if intro == 0x2c {
                guard pos + 10 <= limit else {
                    return nil
                }
                let imagePacked = bytes[pos + 9]
                var cursor = pos + 10
                if (imagePacked & 0x80) != 0 {
                    let tableBytes = 3 * (1 << Int(
                        (imagePacked & 0x07) + 1))
                    cursor += tableBytes
                }
                guard cursor < limit else {
                    return nil
                }
                // The LZW minimum code size.
                cursor += 1
                guard let next = gifBlocks(
                    bytes, from: cursor,
                    limit: limit) else {
                    return nil
                }
                pos = next
                continue
            }
            if intro == 0x01 {
                guard pos + 13 <= limit else {
                    return nil
                }
                guard let next = gifBlocks(
                    bytes, from: pos + 13,
                    limit: limit) else {
                    return nil
                }
                pos = next
                continue
            }
            return nil
        }
        return nil
    }

    /// A WebP at `at`: a RIFF whose size
    /// word measures the file and whose
    /// form and first chunk are the ones
    /// WebP allows — and the platform's
    /// reader must agree it is a picture.
    static func carveEndWebP(_ bytes: [UInt8],
                             at start: Int) -> Int? {
        guard start + 20 <= bytes.count,
              bytes[start] == 0x52,
              bytes[start + 1] == 0x49,
              bytes[start + 2] == 0x46,
              bytes[start + 3] == 0x46,
              bytes[start + 8] == 0x57,
              bytes[start + 9] == 0x45,
              bytes[start + 10] == 0x42,
              bytes[start + 11] == 0x50,
              let riffSize = u32leAt(bytes,
                                     start + 4),
              riffSize >= 12 else {
            return nil
        }
        let length = 8 + riffSize
        guard saneLength(length),
              start + length <= bytes.count else {
            return nil
        }
        let fourcc = Array(bytes[(start + 12)..<(start + 16)])
        let known: [[UInt8]] = [
            [0x56, 0x50, 0x38, 0x20],
            [0x56, 0x50, 0x38, 0x4c],
            [0x56, 0x50, 0x38, 0x58],
        ]
        guard known.contains(fourcc) else {
            return nil
        }
        let data = Data(bytes[start..<(start + length)])
        guard imageSourceAccepts(data) else {
            return nil
        }
        return start + length
    }

    /// A BMP at `at`: the file-size word
    /// must measure the candidate, the
    /// DIB header must be one of the real
    /// sizes with sane geometry, and the
    /// platform's reader must agree.
    static func carveEndBMP(_ bytes: [UInt8],
                            at start: Int) -> Int? {
        guard start + 26 <= bytes.count,
              bytes[start] == 0x42,
              bytes[start + 1] == 0x4d,
              let fileSize = u32leAt(bytes,
                                     start + 2),
              let dibSize = u32leAt(bytes,
                                    start + 14),
              [12, 40, 52, 56, 108, 124]
                .contains(dibSize),
              let dataOffset = u32leAt(bytes,
                                       start + 10),
              dataOffset < fileSize else {
            return nil
        }
        guard saneLength(fileSize),
              start + fileSize <= bytes.count else {
            return nil
        }
        if dibSize == 12 {
            guard let width = u16leAt(bytes,
                                      start + 18),
                  let height = u16leAt(bytes,
                                       start + 20),
                  width > 0, height > 0 else {
                return nil
            }
        } else {
            guard start + 30 <= bytes.count,
                  let width = u32leAt(bytes,
                                      start + 18),
                  let height = u32leAt(bytes,
                                       start + 22),
                  let planes = u16leAt(bytes,
                                       start + 26),
                  let depth = u16leAt(bytes,
                                      start + 28),
                  width != 0, height != 0,
                  planes == 1,
                  [1, 4, 8, 16, 24, 32]
                    .contains(depth) else {
                return nil
            }
        }
        let data = Data(bytes[start..<(start + fileSize)])
        guard imageSourceAccepts(data) else {
            return nil
        }
        return start + fileSize
    }

    /// The platform's own reader as the
    /// last word on the two formats whose
    /// headers alone cannot be trusted:
    /// does ImageIO see a picture here?
    static func imageSourceAccepts(
        _ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) >= 1
    }

    /// Name the format beginning exactly
    /// at `at`, and validate it whole —
    /// the answer HTTP bodies are judged
    /// by. Returns the kind and the end
    /// offset (exclusive), or nil.
    static func identify(_ bytes: [UInt8],
                         at start: Int)
        -> (kind: DriftObject.Kind, end: Int)? {
        guard start >= 0, start < bytes.count else {
            return nil
        }
        switch bytes[start] {
        case 0xff:
            if let end = carveEndJPEG(bytes,
                                      at: start) {
                return (.jpeg, end)
            }
        case 0x89:
            if let end = carveEndPNG(bytes,
                                     at: start) {
                return (.png, end)
            }
        case 0x47:
            if let end = carveEndGIF(bytes,
                                     at: start) {
                return (.gif, end)
            }
        case 0x52:
            if let end = carveEndWebP(bytes,
                                      at: start) {
                return (.webp, end)
            }
        case 0x42:
            if let end = carveEndBMP(bytes,
                                     at: start) {
                return (.bmp, end)
            }
        default:
            break
        }
        return nil
    }

    /// The frames a stream range came
    /// from: the first and last piece the
    /// range overlaps.
    static func frameRange(
        in run: (start: Int, bytes: [UInt8],
                 pieces: [Piece]),
        covering range: Range<Int>)
        -> (first: Int, last: Int) {
        var first: Int? = nil
        var last = 0
        for piece in run.pieces {
            if piece.end <= range.lowerBound {
                continue
            }
            if piece.start >= range.upperBound {
                break
            }
            if first == nil { first = piece.frame }
            last = piece.frame
        }
        guard let foundFirst = first else {
            // No piece map for this range —
            // cite the run's own edges
            // rather than nothing.
            return (run.pieces.first?.frame ?? 0,
                    run.pieces.last?.frame ?? 0)
        }
        return (foundFirst, last)
    }

    /// A small JPEG rendering of a
    /// picture for the gallery wall,
    /// made through the platform's reader
    /// and writer.
    static func makeThumbnail(
        _ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let destination =
            CGImageDestinationCreateWithData(
                out, "public.jpeg" as CFString,
                1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination,
                                   image, nil)
        guard CGImageDestinationFinalize(destination)
        else {
            return nil
        }
        return out as Data
    }

    // MARK: The pass

    /// Lift a capture's pictures: the
    /// gallery alone. Pure and
    /// synchronous — callers who need it
    /// off the main thread arrange that
    /// themselves.
    static func extract(
        _ capture: BFCapture) -> [DriftObject] {
        extractDetailed(capture).objects
    }

    /// The full pass: reassemble every
    /// conversation, take what HTTP
    /// served, carve what any stream
    /// hides, and fold the same bytes
    /// into one object wherever they
    /// turn up.
    static func extractDetailed(
        _ capture: BFCapture) -> DriftExtraction {
        var stats = DriftStats()
        var objects: [DriftObject] = []
        var byHash: [String: Int] = [:]

        func record(_ candidate: DriftObject) {
            stats.occurrences += 1
            if let index = byHash[candidate.sha256] {
                objects[index].hitCount += 1
                // An HTTP sighting of bytes
                // the carver found first
                // lends the object its
                // provenance — the picture
                // keeps its first frames,
                // and learns where it was
                // served from.
                if candidate.viaHTTP,
                   !objects[index].viaHTTP {
                    let prior = objects[index]
                    objects[index] = DriftObject(
                        kind: prior.kind,
                        data: prior.data,
                        source: prior.source,
                        method: candidate.method,
                        path: candidate.path,
                        host: candidate.host,
                        viaHTTP: true,
                        firstFrame: prior.firstFrame,
                        lastFrame: prior.lastFrame,
                        torn: prior.torn,
                        sha256: prior.sha256,
                        hitCount: prior.hitCount,
                        thumbnail: prior.thumbnail)
                }
                return
            }
            guard objects.count < objectCap else {
                stats.hitObjectCap = true
                return
            }
            byHash[candidate.sha256] = objects.count
            objects.append(candidate)
        }

        func makeObject(
            kind: DriftObject.Kind,
            bytes: ArraySlice<UInt8>,
            flow: Flow,
            run: (start: Int, bytes: [UInt8],
                  pieces: [Piece]),
            streamRange: Range<Int>,
            torn: Bool,
            method: String?,
            path: String?,
            host: String?,
            viaHTTP: Bool) -> DriftObject {
            let data = Data(bytes)
            let digest = SHA256.hash(data: data)
            let hex = digest.map {
                String(format: "%02x", $0)
            }.joined()
            let frames = frameRange(
                in: run, covering: streamRange)
            return DriftObject(
                kind: kind, data: data,
                source: flow.label,
                method: method, path: path,
                host: host, viaHTTP: viaHTTP,
                firstFrame: frames.first,
                lastFrame: frames.last,
                torn: torn, sha256: hex,
                thumbnail: makeThumbnail(data))
        }

        func run(containing offset: Int,
                 in half: HalfStream)
            -> (start: Int, bytes: [UInt8],
                pieces: [Piece])? {
            half.runs.first {
                offset >= $0.start
                    && offset < $0.start
                        + $0.bytes.count
            }
        }

        /// One direction's HTTP harvest:
        /// every response body that is a
        /// picture becomes an object with
        /// its provenance, and the stream
        /// ranges those bodies covered are
        /// returned as claimed, so the
        /// carver does not lift the same
        /// bytes a second time.
        func httpPass(
            flow: Flow, server: HalfStream,
            requests: [DriftRequest])
            -> [Int: [Range<Int>]] {
            var claims: [Int: [Range<Int>]] = [:]
            let responses = parseResponses(
                server, requestCount: requests.count)
            for response in responses {
                let bodyBytes = Array(response.body)
                guard let found = identify(
                    bodyBytes, at: 0),
                      found.end == bodyBytes.count
                else {
                    continue
                }
                guard let hostRun = run(
                    containing:
                        response.bodyRange.lowerBound,
                    in: server) else {
                    continue
                }
                var request: DriftRequest? = nil
                if response.requestIndex
                    < requests.count {
                    request = requests[
                        response.requestIndex]
                }
                record(makeObject(
                    kind: found.kind,
                    bytes: bodyBytes[...],
                    flow: flow, run: hostRun,
                    streamRange: response.bodyRange,
                    torn: server.torn,
                    method: request?.method,
                    path: request?.path,
                    host: request?.host,
                    viaHTTP: true))
                claims[hostRun.start,
                       default: []].append(
                        response.bodyRange)
            }
            return claims
        }

        /// The signature scan over one
        /// half-stream, skipping the
        /// ranges HTTP already claimed.
        func carve(_ half: HalfStream, of flow: Flow,
                   claims: [Int: [Range<Int>]]) {
            for run in half.runs {
                let runClaims = claims[run.start] ?? []
                var index = 0
                while index < run.bytes.count {
                    let byte = run.bytes[index]
                    guard byte == 0xff
                        || byte == 0x89
                        || byte == 0x47
                        || byte == 0x52
                        || byte == 0x42 else {
                        index += 1
                        continue
                    }
                    guard let found = identify(
                        run.bytes, at: index) else {
                        index += 1
                        continue
                    }
                    let streamRange = (run.start + index)..<(run.start + found.end)
                    if runClaims.contains(
                        streamRange) {
                        index = found.end
                        continue
                    }
                    record(makeObject(
                        kind: found.kind,
                        bytes: run.bytes[
                            index..<found.end],
                        flow: flow, run: run,
                        streamRange: streamRange,
                        torn: half.torn,
                        method: nil, path: nil,
                        host: nil, viaHTTP: false))
                    index = found.end
                }
            }
        }

        let allFlows = flows(of: capture)
        stats.flows = allFlows.count
        for flow in allFlows {
            for half in [flow.aToB, flow.bToA] {
                if half.torn {
                    stats.tornStreams += 1
                }
                if half.capped {
                    stats.cappedStreams += 1
                }
            }
            let claimsOnB = httpPass(
                flow: flow, server: flow.bToA,
                requests: parseRequests(flow.aToB))
            let claimsOnA = httpPass(
                flow: flow, server: flow.aToB,
                requests: parseRequests(flow.bToA))
            carve(flow.bToA, of: flow,
                  claims: claimsOnB)
            carve(flow.aToB, of: flow,
                  claims: claimsOnA)
        }
        return DriftExtraction(objects: objects,
                               stats: stats)
    }
}
