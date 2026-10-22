import Foundation
import CryptoKit

/// Wave ten: files brought to the bench.
/// Every prior wave reads the wire or a
/// host's papers; this one reads what the
/// operator carries in by hand — the files
/// in the console's own tree. A workbench,
/// not an engine room: nothing here is
/// executed, rendered, unpacked onto the
/// disk, or trusted. A parser's job is
/// structure and claims: what the bytes
/// are, what the file SAYS it is, and
/// every place the two disagree, printed
/// as a finding. A file's own words about
/// itself — its headers, its metadata,
/// the names embedded in it — are always
/// reported as claims, never as facts the
/// bench has sworn to.
///
/// Incumbent audit (before a line was
/// written): `enccensus` (Wave 8) already
/// censuses sealed containers — NJCF by
/// the house reader's own layout, LUKS,
/// age, OpenSSL salted, a one-line ZIP
/// count. This wave does not re-census
/// seals: audiofile and filecensus name
/// an NJCF file and hand the operator to
/// enccensus by name, and mawkbox songs
/// and time-locked boxes carry no papers
/// by design (enccensus says so itself),
/// so no verb here pretends to read them.
/// `x509probe` and `keyprobe` (Wave 8)
/// deep-read certificates and keys;
/// certfile is the file-level ledger
/// that rides their cores — every block
/// in the bundle, in the order the file
/// keeps them, with the order itself
/// graded. `hashprobe` (Wave 8) hashes a
/// file on its own; filecensus rides the
/// same battery (`lockDigests`,
/// `lockStats`) as one panel of a wider
/// board. The shell's own `file`,
/// `strings` and `xxd` are one-line
/// utilities; the bench verbs beside them
/// are the deep censuses. Betafisch and
/// driftnet own the capture files — this
/// wave carries NO pcap verbs, on the
/// brief's standing order.
///
/// Verification (before the Swift
/// existed, a Python mirror ran every
/// parser here against fixtures built
/// for the purpose, and the fixtures were
/// cross-checked against the real tools —
/// openssl's certificates, a compiled
/// ELF against readelf, objdump against
/// the hand-built PE, sqlite3's own
/// pragmas against the page walk): a
/// hand-built JPEG whose EXIF carries a
/// GPS fix; a PNG with text chunks and
/// bytes past its IEND; a three-frame
/// GIF; a hand-packed WebP; ZIPs plain,
/// commented, flag-encrypted with an AES
/// extra field, and riding behind 100
/// junk bytes; a hand-written PDF with a
/// JavaScript action, an embedded file,
/// a Launch annotation and a page-count
/// claim its own pages contradict;
/// thin and fat Mach-O built byte by
/// byte; plists in XML and binary, an
/// entitlements sheet and a provisioning
/// profile wrapped in CMS junk; WAV,
/// FLAC and MP3 papers; TTF and WOFF
/// name tables; CSV and JSON shape
/// censuses; three shapes of log; and a
/// directory of known duplicates whose
/// wasted bytes were tallied by hand
/// first. Where a parser rides a house
/// core, the core's own wave carries
/// its verification.
extension BlacksiteBench {

    // MARK: the wave-10 dispatch

    /// One case in netCommand routes
    /// the whole file bench here; the
    /// verb name picks the hand. Every
    /// verb reads a file (or a directory
    /// of them) from the console's own
    /// tree and nothing else.
    static func benchFiles(
        name: String, arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        switch name {
        case "filecensus":
            filecensus(target: arg,
                       emit: emit, done: done)
        case "magicprobe":
            magicprobe(target: arg,
                       emit: emit, done: done)
        case "stringsdeep":
            stringsdeep(target: arg,
                        emit: emit, done: done)
        case "exifprobe":
            exifprobe(target: arg,
                      emit: emit, done: done)
        case "pdfprobe":
            pdfprobe(target: arg,
                     emit: emit, done: done)
        case "zipprobe":
            zipprobe(target: arg,
                     emit: emit, done: done)
        case "machoprobe":
            machoprobe(target: arg,
                       emit: emit, done: done)
        case "elfprobe":
            elfprobe(target: arg,
                     emit: emit, done: done)
        case "peprobe":
            peprobe(target: arg,
                    emit: emit, done: done)
        case "imgdeep":
            imgdeep(target: arg,
                    emit: emit, done: done)
        case "audiofile":
            audiofile(target: arg,
                      emit: emit, done: done)
        case "sqliteprobe":
            sqliteprobe(target: arg,
                        emit: emit, done: done)
        case "plistprobe":
            plistprobe(target: arg,
                       emit: emit, done: done)
        case "scriptprobe":
            scriptprobe(target: arg,
                        emit: emit, done: done)
        case "logprobe":
            logprobe(target: arg,
                     emit: emit, done: done)
        case "dataprobe":
            dataprobe(target: arg,
                      emit: emit, done: done)
        case "fontprobe":
            fontprobe(target: arg,
                      emit: emit, done: done)
        case "certfile":
            certfile(target: arg,
                     emit: emit, done: done)
        case "dupprobe":
            dupprobe(target: arg,
                     emit: emit, done: done)
        case "fileboard":
            fileboard(target: arg,
                      emit: emit, done: done)
        default:
            done()
        }
    }

    // MARK: shared plumbing

    /// What a load of a named file can
    /// come back as. The bench reads
    /// whole files into memory, so the
    /// ceiling is stated, not implied:
    /// 128 MB. Past it, the file is
    /// named and refused, never half-read
    /// in silence.
    enum FileLoad {
        case ok([UInt8], String)
        case missing
        case isDir
        case tooBig(Int)
    }

    static let fileHardCap = 128 * 1024 * 1024

    /// Resolve a typed path the way
    /// Wave 8 taught the bench: as
    /// typed first, then under /home —
    /// the operator's desk.
    static func fileCandidates(
        _ typed: String) -> [String] {
        let trimmed = typed
            .trimmingCharacters(
                in: .whitespaces)
        if trimmed.isEmpty { return [] }
        var out = [trimmed]
        if !trimmed.hasPrefix("/") {
            out.append("/home/" + trimmed)
        }
        return out
    }

    static func fileLoad(
        _ typed: String) -> FileLoad {
        for path in fileCandidates(typed) {
            if BlacksiteFS.isDirectory(path) {
                return .isDir
            }
            guard BlacksiteFS.exists(path)
            else { continue }
            if let size = BlacksiteFS
                .fileSize(path),
               size > fileHardCap {
                return .tooBig(size)
            }
            if let data = BlacksiteFS
                .readData(path) {
                return .ok([UInt8](data), path)
            }
        }
        return .missing
    }

    /// A directory the operator names,
    /// resolved the same way; nothing
    /// (no argument) means the desk.
    static func fileDir(
        _ typed: String) -> String? {
        let trimmed = typed
            .trimmingCharacters(
                in: .whitespaces)
        if trimmed.isEmpty {
            return "/home"
        }
        for path in fileCandidates(trimmed)
        where BlacksiteFS.isDirectory(path) {
            return BlacksiteFS.normalize(
                path, cwd: "/")
        }
        return nil
    }

    /// The shared refusal lines, so all
    /// twenty verbs say no the same way.
    static func fileLoadOrReport(
        _ typed: String, verb: String,
        emit: @escaping BlacksiteEmit)
        -> ([UInt8], String)? {
        switch fileLoad(typed) {
        case .ok(let bytes, let path):
            return (bytes, path)
        case .missing:
            icsSay(emit, String(format: L("%@: nothing readable at that path — files live in the console's own tree (try ls /home)"), verb), .err)
            return nil
        case .isDir:
            icsSay(emit, String(format: L("%@: that path is a directory — fileboard and dupprobe read directories; the other file verbs want one file"), verb), .err)
            return nil
        case .tooBig(let size):
            icsSay(emit, String(format: L("%@: %lld bytes is past the bench's %lld-byte reading ceiling — the file is named, not half-read"), verb, Int64(size), Int64(fileHardCap)), .err)
            return nil
        }
    }

    /// The board header every verb
    /// opens with: the file as found.
    static func fileHeader(
        _ verb: String, path: String,
        bytes: Int,
        emit: @escaping BlacksiteEmit) {
        icsSay(emit, String(format: L("%@ — %@ (%@)"), verb, path, fileHuman(bytes)), .sys)
    }

    static func fileHuman(_ n: Int)
        -> String {
        if n < 1024 {
            return String(format: L("%lld bytes"), Int64(n))
        }
        if n < 1024 * 1024 {
            return String(format: L("%lld bytes (%.1f KB)"), Int64(n), Double(n) / 1024)
        }
        return String(format: L("%lld bytes (%.1f MB)"), Int64(n), Double(n) / 1048576)
    }

    static let fileUTCFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(
            identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat =
            "yyyy-MM-dd HH:mm:ss 'UTC'"
        return f
    }()

    static func fileDateLine(_ epoch: Int)
        -> String {
        fileUTCFormatter.string(
            from: Date(
                timeIntervalSince1970:
                    Double(epoch)))
    }

    // MARK: byte readers (bounds-checked)

    static func fileU16BE(
        _ b: [UInt8], _ o: Int) -> Int? {
        guard o + 2 <= b.count else {
            return nil
        }
        return Int(b[o]) << 8 | Int(b[o + 1])
    }

    static func fileU32BE(
        _ b: [UInt8], _ o: Int) -> Int? {
        guard o + 4 <= b.count else {
            return nil
        }
        return Int(b[o]) << 24
            | Int(b[o + 1]) << 16
            | Int(b[o + 2]) << 8
            | Int(b[o + 3])
    }

    static func fileU16LE(
        _ b: [UInt8], _ o: Int) -> Int? {
        guard o + 2 <= b.count else {
            return nil
        }
        return Int(b[o]) | Int(b[o + 1]) << 8
    }

    static func fileU32LE(
        _ b: [UInt8], _ o: Int) -> Int? {
        guard o + 4 <= b.count else {
            return nil
        }
        return Int(b[o]) | Int(b[o + 1]) << 8
            | Int(b[o + 2]) << 16
            | Int(b[o + 3]) << 24
    }

    static func fileU64LE(
        _ b: [UInt8], _ o: Int) -> UInt64? {
        guard o + 8 <= b.count else {
            return nil
        }
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(b[o + i]) << UInt64(i * 8)
        }
        return v
    }

    static func fileU64BE(
        _ b: [UInt8], _ o: Int) -> UInt64? {
        guard o + 8 <= b.count else {
            return nil
        }
        var v: UInt64 = 0
        for i in 0..<8 {
            v = v << 8 | UInt64(b[o + i])
        }
        return v
    }

    /// A NUL-terminated string inside a
    /// byte range, read as Latin-1 so it
    /// can never fail.
    static func fileCString(
        _ b: [UInt8], from: Int,
        limit: Int) -> String {
        var end = from
        let hard = min(limit, b.count)
        while end < hard, b[end] != 0 {
            end += 1
        }
        guard end > from else { return "" }
        return String(
            bytes: Array(b[from..<end]),
            encoding: .isoLatin1) ?? ""
    }

    static func fileHexPrefix(
        _ b: [UInt8], count: Int) -> String {
        b.prefix(count).map {
            String(format: "%02x", $0)
        }.joined(separator: " ")
    }

    // MARK: magic — what the bytes say

    struct FileKind {
        var name: String
        var detail: String
        /// A family key the extension
        /// ledger grades against.
        var family: String
    }

    /// Identification by the papers at
    /// the head of the file. Order is
    /// the judgement: the most specific
    /// papers first.
    static func fileKind(
        _ b: [UInt8]) -> FileKind? {
        func has(_ p: [UInt8]) -> Bool {
            b.count >= p.count
                && Array(b.prefix(p.count)) == p
        }
        func hasText(_ s: String) -> Bool {
            has(Array(s.utf8))
        }
        if has([0x89, 0x50, 0x4E, 0x47,
                0x0D, 0x0A, 0x1A, 0x0A]) {
            return FileKind(
                name: L("a PNG image"),
                detail: L("the eight-byte signature"),
                family: "png")
        }
        if has([0xFF, 0xD8, 0xFF]) {
            return FileKind(
                name: L("a JPEG image"),
                detail: L("the SOI marker and a marker after it"),
                family: "jpeg")
        }
        if hasText("GIF87a")
            || hasText("GIF89a") {
            return FileKind(
                name: L("a GIF image"),
                detail: String(format: L("the %@ header"), String(decoding: b.prefix(6), as: UTF8.self)),
                family: "gif")
        }
        if b.count >= 12,
           hasText("RIFF"),
           String(decoding: b[8..<12],
                  as: UTF8.self) == "WEBP" {
            return FileKind(
                name: L("a WebP image"),
                detail: L("a RIFF wrapper naming WEBP"),
                family: "webp")
        }
        if b.count >= 12,
           hasText("RIFF"),
           String(decoding: b[8..<12],
                  as: UTF8.self) == "WAVE" {
            return FileKind(
                name: L("a WAV audio file"),
                detail: L("a RIFF wrapper naming WAVE"),
                family: "wav")
        }
        if hasText("%PDF-") {
            return FileKind(
                name: L("a PDF document"),
                detail: String(format: L("the header claims version %@"), String(decoding: b.dropFirst(5).prefix(3), as: UTF8.self)),
                family: "pdf")
        }
        if has([0x50, 0x4B, 0x03, 0x04])
            || has([0x50, 0x4B, 0x05, 0x06])
            || has([0x50, 0x4B, 0x07, 0x08]) {
            return FileKind(
                name: L("a ZIP archive"),
                detail: L("the PK papers"),
                family: "zip")
        }
        if has([0x50, 0x4B, 0x01, 0x02]) {
            return FileKind(
                name: L("a ZIP archive"),
                detail: L("a central directory first — the local headers were stripped or never written"),
                family: "zip")
        }
        if has([0x1F, 0x8B]) {
            return FileKind(
                name: L("gzip data"),
                detail: L("compressed, not encrypted — anyone may read it"),
                family: "gzip")
        }
        if hasText("BZh") {
            return FileKind(
                name: L("bzip2 data"),
                detail: L("compressed, not encrypted"),
                family: "bzip2")
        }
        if has([0xFD, 0x37, 0x7A, 0x58,
                0x5A, 0x00]) {
            return FileKind(
                name: L("xz data"),
                detail: L("compressed, not encrypted"),
                family: "xz")
        }
        if has([0x28, 0xB5, 0x2F, 0xFD]) {
            return FileKind(
                name: L("zstd data"),
                detail: L("compressed, not encrypted"),
                family: "zstd")
        }
        if has([0x37, 0x7A, 0xBC, 0xAF,
                0x27, 0x1C]) {
            return FileKind(
                name: L("a 7-Zip archive"),
                detail: L("its headers may themselves be sealed"),
                family: "7z")
        }
        if has([0x52, 0x61, 0x72, 0x21,
                0x1A, 0x07]) {
            return FileKind(
                name: L("a RAR archive"),
                detail: "",
                family: "rar")
        }
        if has([0x7F, 0x45, 0x4C, 0x46]) {
            return FileKind(
                name: L("an ELF binary"),
                detail: L("the format of Linux and the BSDs"),
                family: "elf")
        }
        if has([0xFE, 0xED, 0xFA, 0xCE])
            || has([0xCE, 0xFA, 0xED, 0xFE])
            || has([0xFE, 0xED, 0xFA, 0xCF])
            || has([0xCF, 0xFA, 0xED, 0xFE]) {
            return FileKind(
                name: L("a Mach-O binary"),
                detail: L("a thin slice — one architecture"),
                family: "macho")
        }
        if has([0xCA, 0xFE, 0xBA, 0xBE])
            || has([0xCA, 0xFE, 0xBA, 0xBF]) {
            return FileKind(
                name: L("a Mach-O fat binary"),
                detail: L("or a Java class file — the CA FE BA BE papers open both houses, and machoprobe tells them apart"),
                family: "macho")
        }
        if b.count >= 16,
           String(decoding: b.prefix(15),
                  as: UTF8.self)
               == "SQLite format 3",
           b[15] == 0 {
            return FileKind(
                name: L("a SQLite database"),
                detail: L("the sixteen-byte papers"),
                family: "sqlite")
        }
        if hasText("fLaC") {
            return FileKind(
                name: L("a FLAC audio file"),
                detail: L("lossless, with its papers in metadata blocks"),
                family: "flac")
        }
        if hasText("ID3")
            || (b.count >= 2 && b[0] == 0xFF
                && b[1] & 0xE0 == 0xE0) {
            return FileKind(
                name: L("an MP3 audio file"),
                detail: hasText("ID3")
                    ? L("an ID3 tag leads it")
                    : L("bare MPEG frames — no tag"),
                family: "mp3")
        }
        if hasText("OggS") {
            return FileKind(
                name: L("an Ogg container"),
                detail: L("Vorbis, Opus, or another tenant — audiofile reads the first page's claim"),
                family: "ogg")
        }
        if has([0x49, 0x49, 0x2A, 0x00])
            || has([0x4D, 0x4D, 0x00, 0x2A]) {
            return FileKind(
                name: L("a TIFF image"),
                detail: "",
                family: "tiff")
        }
        if hasText("wOFF") {
            return FileKind(
                name: L("a WOFF font"),
                detail: L("a web font — sfnt tables, some compressed"),
                family: "woff")
        }
        if hasText("wOF2") {
            return FileKind(
                name: L("a WOFF2 font"),
                detail: L("a web font with transformed tables"),
                family: "woff2")
        }
        if hasText("ttcf") {
            return FileKind(
                name: L("a TrueType collection"),
                detail: L("several fonts under one cover"),
                family: "ttc")
        }
        if has([0x00, 0x01, 0x00, 0x00])
            || hasText("true")
            || hasText("OTTO") {
            return FileKind(
                name: L("an sfnt font (TTF/OTF)"),
                detail: hasText("OTTO")
                    ? L("OpenType with CFF outlines")
                    : L("TrueType outlines"),
                family: "font")
        }
        if hasText("bplist00") {
            return FileKind(
                name: L("a binary plist"),
                detail: L("Apple's binary property list"),
                family: "plist")
        }
        if hasText("NJCF") {
            return FileKind(
                name: L("an NJCF sealed file"),
                detail: L("the house format — enccensus reads its papers"),
                family: "njcf")
        }
        if has([0x4C, 0x55, 0x4B, 0x53,
                0xBA, 0xBE]) {
            return FileKind(
                name: L("a LUKS header"),
                detail: L("disk encryption — enccensus reads its papers"),
                family: "luks")
        }
        if hasText("Salted__") {
            return FileKind(
                name: L("OpenSSL salted data"),
                detail: L("enccensus reads its papers"),
                family: "salted")
        }
        if hasText("-----BEGIN ") {
            return FileKind(
                name: L("PEM text"),
                detail: L("armored blocks — certfile keeps their ledger"),
                family: "pem")
        }
        if hasText("MZ") {
            return FileKind(
                name: L("a DOS/PE executable family file"),
                detail: L("the MZ papers — peprobe reads the PE header behind them"),
                family: "pe")
        }
        if hasText("BM") && b.count > 26 {
            return FileKind(
                name: L("a BMP image"),
                detail: "",
                family: "bmp")
        }
        if b.count >= 2, b[0] == 0x30 {
            return FileKind(
                name: L("DER-encoded data"),
                detail: L("a certificate, a key, a request — certfile reads the papers"),
                family: "der")
        }
        return nil
    }

    /// The extension ledger: what a
    /// name claims, by family. An
    /// extension not in the book makes
    /// no claim the bench can grade.
    static let fileExtFamily: [String: String] = [
        "png": "png", "jpg": "jpeg",
        "jpeg": "jpeg", "gif": "gif",
        "webp": "webp", "pdf": "pdf",
        "zip": "zip", "gz": "gzip",
        "tgz": "gzip", "bz2": "bzip2",
        "xz": "xz", "zst": "zstd",
        "7z": "7z", "rar": "rar",
        "sqlite": "sqlite", "sqlite3": "sqlite",
        "db": "sqlite", "wav": "wav",
        "flac": "flac", "mp3": "mp3",
        "ogg": "ogg", "oga": "ogg",
        "tif": "tiff", "tiff": "tiff",
        "bmp": "bmp", "ttf": "font",
        "otf": "font", "woff": "woff",
        "woff2": "woff2", "plist": "plist",
        "pem": "pem", "crt": "der",
        "cer": "der", "der": "der",
        "key": "der", "exe": "pe",
        "dll": "pe", "sys": "pe",
        "elf": "elf", "njcf": "njcf",
    ]

    static func fileExtension(
        _ path: String) -> String? {
        let base = BlacksiteFS.baseName(
            of: path)
        guard let dot = base.lastIndex(
            of: "."),
              dot != base.startIndex else {
            return nil
        }
        let ext = String(base[
            base.index(after: dot)...])
            .lowercased()
        return ext.isEmpty ? nil : ext
    }

    /// Is this byte content plausibly
    /// text? Nine in ten printable.
    static func fileLooksText(
        _ b: [UInt8]) -> Bool {
        let sample = b.prefix(8192)
        if sample.isEmpty { return true }
        if sample.contains(0) { return false }
        var printable = 0
        for byte in sample
        where byte == 9 || byte == 10
            || byte == 13
            || (byte >= 32 && byte < 127)
            || byte >= 128 {
            printable += 1
        }
        return printable * 10
            >= sample.count * 9
    }

    // MARK: the strings core

    struct FileStrings {
        var runs = 0
        var bytes = 0
        var utf16Runs = 0
        var urls: [String] = []
        var domains: [String] = []
        var longest: [(Int, String)] = []
    }

    /// Printable-string census over a
    /// bounded prefix: runs of four or
    /// more printable bytes, URL- and
    /// domain-shaped tokens among them
    /// — strings, labelled as strings.
    static func fileStrings(
        _ b: [UInt8], cap: Int)
        -> FileStrings {
        let data = Array(b.prefix(cap))
        var out = FileStrings()
        var runs: [[UInt8]] = []
        var current: [UInt8] = []
        func flush() {
            if current.count >= 4 {
                runs.append(current)
            }
            current = []
        }
        for byte in data {
            if byte >= 0x20 && byte <= 0x7E {
                current.append(byte)
            } else {
                flush()
            }
        }
        flush()
        out.runs = runs.count
        out.bytes = runs.reduce(0) {
            $0 + $1.count
        }
        let domainShape: (String) -> Bool = {
            token in
            let parts = token.split(
                separator: ".")
            guard parts.count >= 2,
                  let last = parts.last,
                  last.count >= 2,
                  last.allSatisfy({
                      $0.isLetter
                  }) else { return false }
            return parts.allSatisfy {
                !$0.isEmpty
                    && $0.allSatisfy {
                        $0.isLetter
                            || $0.isNumber
                            || $0 == "-"
                    }
            }
        }
        var urlSet = Set<String>()
        var domainSet = Set<String>()
        for run in runs {
            let text = String(
                decoding: run, as: UTF8.self)
            let tokens = text.split {
                !($0.isLetter || $0.isNumber
                    || $0 == "." || $0 == "/"
                    || $0 == "_" || $0 == "~"
                    || $0 == "%" || $0 == ":"
                    || $0 == "#" || $0 == "="
                    || $0 == "@" || $0 == "+"
                    || $0 == "-")
            }
            for tokenSlice in tokens {
                let token = String(tokenSlice)
                if token.contains("://"),
                   token.count > 6 {
                    if urlSet.insert(token)
                        .inserted,
                       out.urls.count < 24 {
                        out.urls.append(token)
                    }
                } else if domainShape(token) {
                    if domainSet.insert(token)
                        .inserted,
                       out.domains.count < 24 {
                        out.domains.append(token)
                    }
                }
            }
        }
        let sorted = runs.sorted {
            $0.count > $1.count
        }
        out.longest = sorted.prefix(3).map {
            ($0.count, String(
                decoding: $0.prefix(60),
                as: UTF8.self))
        }
        // The UTF-16LE pass: a printable
        // byte followed by a NUL, four or
        // more in a row on even offsets.
        var u16run = 0
        var i = 0
        while i + 1 < data.count {
            if data[i] >= 0x20
                && data[i] <= 0x7E
                && data[i + 1] == 0 {
                u16run += 1
                i += 2
            } else {
                if u16run >= 4 {
                    out.utf16Runs += 1
                }
                u16run = 0
                i += 1
            }
        }
        if u16run >= 4 {
            out.utf16Runs += 1
        }
        return out
    }

    // MARK: CRC-32 (the PNG check)

    static let fileCRCTable: [UInt32] = {
        (0..<256).map { n -> UInt32 in
            var c = UInt32(n)
            for _ in 0..<8 {
                c = c & 1 != 0
                    ? 0xEDB88320 ^ (c >> 1)
                    : c >> 1
            }
            return c
        }
    }()

    static func fileCRC32(
        _ b: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in b {
            crc = fileCRCTable[
                Int((crc ^ UInt32(byte))
                    & 0xFF)]
                ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

extension BlacksiteBench {

    // MARK: filecensus — the identity board

    /// The first thing the bench does
    /// with a file it has never seen:
    /// its road, its size, what its
    /// bytes say it is against what its
    /// name claims, the digests, its
    /// texture, and a headline from the
    /// family reader, with the deeper
    /// verb named for the operator who
    /// wants more.
    static func filecensus(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "filecensus",
                    emit: emit) else { return }
            fileHeader("filecensus",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            let kind = fileKind(b)
            if let kind = kind {
                icsSay(emit, String(format: L("by its bytes: %@ — %@"), kind.name, kind.detail), .out)
            } else if fileLooksText(b) {
                icsSay(emit, L("by its bytes: no signature at the head, and it reads as text — a script, a log, a letter, data."), .out)
            } else {
                icsSay(emit, L("by its bytes: no signature the bench knows — an unknown format, a fragment, or data with no papers."), .out)
            }
            if let ext = fileExtension(path) {
                if let family =
                    fileExtFamily[ext] {
                    if let kind = kind {
                        if kind.family == family
                            || (family == "der"
                                && kind.family
                                    == "pem") {
                            icsSay(emit, String(format: L("its name claims '.%@' and the bytes agree."), ext), .ok)
                        } else {
                            icsSay(emit, String(format: L("its name claims '.%@' but the bytes are %@ — the extension is a label, and labels lie."), ext, kind.name), .err)
                        }
                    } else {
                        icsSay(emit, String(format: L("its name claims '.%@' but the bytes carry no signature to grade the claim against."), ext), .err)
                    }
                } else {
                    icsSay(emit, String(format: L("its name ends in '.%@' — an extension outside the bench's book; no claim is graded."), ext), .out)
                }
            } else {
                icsSay(emit, L("its name carries no extension — no claim is made, and none is graded."), .out)
            }
            icsSay(emit, L("digests (the whole file):"), .out)
            lockDigests(of: Data(b), emit: emit)
            let stats = lockStats(
                Array(b.prefix(65536)))
            icsSay(emit, String(format: L("texture of the first %lld bytes: entropy %.2f bits/byte, %lld distinct bytes, busiest byte 0x%02x"), Int64(min(b.count, 65536)), stats.entropy, Int64(stats.distinct), Int64(stats.topByte)), .out)
            if let headline =
                fileHeadline(b, kind: kind) {
                icsSay(emit, headline, .out)
            }
            if let kind = kind,
               let deep = fileDeepVerb(
                family: kind.family) {
                icsSay(emit, String(format: L("the deep read is %@ — it takes this file the rest of the way."), deep), .sys)
            } else if kind == nil,
                      fileLooksText(b) {
                icsSay(emit, L("text by shape: scriptprobe, logprobe and dataprobe each read a dialect of it — whichever fits its shape."), .sys)
            }
        }
    }

    /// One-line headlines from the
    /// family cores, shared by
    /// filecensus and fileboard.
    static func fileHeadline(
        _ b: [UInt8], kind: FileKind?)
        -> String? {
        guard let kind = kind else {
            return nil
        }
        switch kind.family {
        case "jpeg":
            if let j = fileJPEGWalk(b),
               let sof = j.sof {
                return String(format: L("a frame of %lld x %lld pixels, %lld markers before the scan, %lld bytes riding past the end marker"), Int64(sof.0), Int64(sof.1), Int64(j.markers.count), Int64(j.trailing))
            }
            return nil
        case "png":
            let chunks = filePNGChunks(b)
            let text = chunks.filter {
                $0.name == "tEXt"
                    || $0.name == "iTXt"
                    || $0.name == "zTXt"
            }.count
            let trailing = chunks.last
                .map { max(0, b.count - $0.end) }
                ?? 0
            return String(format: L("%lld chunks, %lld of them text, %lld bytes riding past IEND"), Int64(chunks.count), Int64(text), Int64(trailing))
        case "gif":
            if let g = fileGIFWalk(b) {
                return String(format: L("a canvas of %lld x %lld, %lld frames counted, %lld bytes past the trailer"), Int64(g.width), Int64(g.height), Int64(g.frames), Int64(g.trailing))
            }
            return nil
        case "zip":
            if let z = fileZIPWalk(b) {
                let encrypted = z.entries
                    .filter {
                        $0.flags & 1 != 0
                    }.count
                return String(format: L("%lld entries in the central directory, %lld of them flagged encrypted"), Int64(z.count), Int64(encrypted))
            }
            return nil
        case "pdf":
            let p = filePDFCore(b)
            if let claim = p.pagesClaim {
                return String(format: L("%lld objects, %lld pages counted against a claim of %lld"), Int64(p.objects), Int64(p.pagesCounted), Int64(claim))
            }
            return String(format: L("%lld objects, %lld pages counted, no page-count claim found"), Int64(p.objects), Int64(p.pagesCounted))
        case "sqlite":
            if let s = fileSQLiteHeader(b) {
                return String(format: L("%lld pages of %lld bytes by its ledger, %lld of them on the freelist"), Int64(s.pages), Int64(s.pageSize), Int64(s.freelist))
            }
            return nil
        case "pem":
            let blocks = lockPEMBlocks(
                String(decoding: b,
                       as: UTF8.self))
            return String(format: L("%lld PEM blocks ride in this file"), Int64(blocks.count))
        case "njcf":
            return L("a sealed house file: enccensus reads its header papers; the payload stays shut here")
        default:
            return nil
        }
    }

    static func fileDeepVerb(
        family: String) -> String? {
        switch family {
        case "jpeg", "png", "gif", "webp":
            return "imgdeep (and exifprobe for its papers)"
        case "pdf":
            return "pdfprobe"
        case "zip":
            return "zipprobe"
        case "macho":
            return "machoprobe"
        case "elf":
            return "elfprobe"
        case "pe":
            return "peprobe"
        case "wav", "flac", "mp3", "ogg":
            return "audiofile"
        case "sqlite":
            return "sqliteprobe"
        case "plist":
            return "plistprobe"
        case "woff", "woff2", "ttc", "font":
            return "fontprobe"
        case "pem", "der":
            return "certfile"
        default:
            return nil
        }
    }

    // MARK: magicprobe — the head of the file

    /// Sixteen bytes and a verdict.
    /// The ledger, the extension's
    /// claim laid against it, and the
    /// one disguise the head alone can
    /// catch: an archive riding behind
    /// something else.
    static func magicprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "magicprobe",
                    emit: emit) else { return }
            fileHeader("magicprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            icsSay(emit, String(format: L("first sixteen bytes: %@"), fileHexPrefix(b, count: 16)), .out)
            if let kind = fileKind(b) {
                icsSay(emit, String(format: L("the ledger says: %@ — %@"), kind.name, kind.detail), .out)
                if let ext = fileExtension(path),
                   let family =
                    fileExtFamily[ext] {
                    if kind.family == family {
                        icsSay(emit, String(format: L("the name's claim ('.%@') and the bytes agree."), ext), .ok)
                    } else {
                        icsSay(emit, String(format: L("the name claims '.%@' and the bytes say %@ — renamed, disguised, or simply wrong; the bench trusts the bytes."), ext, kind.name), .err)
                    }
                }
            } else if fileLooksText(b) {
                icsSay(emit, L("no signature in the ledger — and the head reads as text. Text formats carry their papers in their first lines, not their bytes."), .out)
            } else {
                icsSay(emit, L("no signature in the ledger. That is a fact about the ledger as much as the file: an unknown format, a fragment, headerless data, or a seal — enccensus reads the seals."), .out)
            }
            // The polyglot knock: an
            // end-of-central-directory in
            // the tail of a file whose
            // head is something else.
            if fileKind(b)?.family != "zip" {
                let tail = Array(
                    b.suffix(65557))
                if fileFindEOCD(tail) != nil {
                    icsSay(emit, L("but its tail carries a ZIP end-of-directory: something else in front, an archive behind it — a polyglot. zipprobe reads the archive; the front is whatever it claims to be."), .err)
                }
            }
            if b.count >= 4 {
                let printable = b.prefix(4)
                    .allSatisfy {
                        $0 >= 0x20 && $0 <= 0x7E
                    }
                if printable {
                    icsSay(emit, String(format: L("as text, the head reads '%@'"), String(decoding: b.prefix(4), as: UTF8.self)), .out)
                }
            }
        }
    }

    // MARK: stringsdeep — the strings census

    /// The strings of a file, counted
    /// and sampled — not dumped. What
    /// a binary talks about is a lead,
    /// printed as strings and nothing
    /// more.
    static func stringsdeep(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "stringsdeep",
                    emit: emit) else { return }
            fileHeader("stringsdeep",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            let census = fileStrings(
                b, cap: 4 * 1024 * 1024)
            icsSay(emit, String(format: L("scanned the first %lld bytes: %lld printable runs of four or more (%lld bytes of them), %lld UTF-16LE runs"), Int64(min(b.count, 4 * 1024 * 1024)), Int64(census.runs), Int64(census.bytes), Int64(census.utf16Runs)), .out)
            for (len, text) in census.longest {
                icsSay(emit, String(format: L("longest (%lld): %@"), Int64(len), text), .out)
            }
            if !census.urls.isEmpty {
                icsSay(emit, String(format: L("URL-shaped strings (%lld shown): %@"), Int64(census.urls.count), census.urls.joined(separator: ", ")), .out)
            }
            if !census.domains.isEmpty {
                icsSay(emit, String(format: L("domain-shaped strings (%lld shown): %@"), Int64(census.domains.count), census.domains.joined(separator: ", ")), .out)
            }
            icsSay(emit, L("these are strings — words the file contains. A binary that names a place has not necessarily been there; the bench reports the words, not a journey."), .sys)
        }
    }

    // MARK: exifprobe — the papers pictures carry

    /// Where a picture was made, by
    /// what, and when — as the picture
    /// claims. JPEG walks its EXIF;
    /// PNG reads its text chunks; a PDF
    /// is handed to pdfprobe's core,
    /// since a document's papers are
    /// its info dictionary.
    static func exifprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "exifprobe",
                    emit: emit) else { return }
            fileHeader("exifprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            guard let kind = fileKind(b)
            else {
                icsSay(emit, L("no signature the bench knows — no papers to read."), .err)
                return
            }
            switch kind.family {
            case "jpeg":
                fileEXIFJPEG(b, emit: emit)
            case "png":
                fileEXIFPNG(b, emit: emit)
            case "pdf":
                icsSay(emit, L("a document's papers are its info dictionary — pdfprobe's ground:"), .out)
                filePDFReport(b, emit: emit)
            case "tiff":
                if let tiff = fileTIFF(
                    b, base: 0) {
                    fileTIFFReport(
                        tiff, emit: emit)
                } else {
                    icsSay(emit, L("a TIFF header, but the first directory does not parse."), .err)
                }
            default:
                icsSay(emit, String(format: L("%@ carries no metadata papers this verb reads — imgdeep keeps the image censuses, filecensus the identity board."), kind.name), .err)
            }
        }
    }

    static func fileEXIFJPEG(
        _ b: [UInt8],
        emit: @escaping BlacksiteEmit) {
        guard let walk = fileJPEGWalk(b)
        else {
            icsSay(emit, L("the marker walk fails — this is not a whole JPEG."), .err)
            return
        }
        var exifFound = false
        var xmpTool: String?
        for marker in walk.markers {
            guard marker.name == "APP1",
                  marker.payloadStart
                    + 6 <= marker.payloadEnd
            else { continue }
            let head = Array(b[
                marker.payloadStart..<min(marker.payloadEnd,
                    marker.payloadStart + 30)])
            if head.starts(
                with: Array("Exif\0\0".utf8)) {
                exifFound = true
                let tiffBase =
                    marker.payloadStart + 6
                if let tiff = fileTIFF(
                    b, base: tiffBase) {
                    fileTIFFReport(
                        tiff, emit: emit)
                } else {
                    icsSay(emit, L("an EXIF segment whose TIFF directory does not parse."), .err)
                }
            } else if head.starts(
                with: Array(
                    "http://ns.adobe.com/xap/1.0/\0".utf8)) {
                let text = String(
                    decoding: b[
                        marker.payloadStart..<marker.payloadEnd],
                    as: UTF8.self)
                xmpTool = fileXMLValue(
                    text, tag: "CreatorTool")
                    ?? fileXMLAttr(
                        text, attr: "CreatorTool")
                icsSay(emit, String(format: L("an XMP packet rides in the file (%lld bytes) — its claims print under the same rules as EXIF's"), Int64(marker.payloadEnd - marker.payloadStart)), .out)
            }
        }
        if let tool = xmpTool {
            icsSay(emit, String(format: L("XMP names its tool: %@"), tool), .out)
        }
        if !exifFound {
            icsSay(emit, L("no EXIF segment: this JPEG carries no camera papers. Absence here means the segment was never written or was stripped — the bench cannot tell which."), .out)
        }
    }

    static func fileEXIFPNG(
        _ b: [UInt8],
        emit: @escaping BlacksiteEmit) {
        let chunks = filePNGChunks(b)
        var papers = 0
        for chunk in chunks {
            if chunk.name == "tEXt"
                || chunk.name == "iTXt" {
                papers += 1
                let payload = Array(b[
                    chunk.payloadStart..<chunk.payloadEnd])
                if let nul = payload
                    .firstIndex(of: 0) {
                    let key = String(
                        decoding: payload[..<nul],
                        as: UTF8.self)
                    let value = String(
                        decoding: payload[
                            payload.index(
                                after: nul)...],
                        as: UTF8.self)
                    icsSay(emit, String(format: L("%@ = %@ (the file's claim)"), key, value), .out)
                }
            }
            if chunk.name == "zTXt" {
                papers += 1
                icsSay(emit, L("a zTXt chunk: text papers, compressed — the bench notes them without inflating anything"), .out)
            }
            if chunk.name == "eXIf" {
                papers += 1
                if let tiff = fileTIFF(
                    b, base: chunk.payloadStart) {
                    fileTIFFReport(
                        tiff, emit: emit)
                }
            }
            if chunk.name == "tIME" {
                papers += 1
                let p = chunk.payloadStart
                if let year = fileU16BE(b, p),
                   p + 7 <= chunk.payloadEnd {
                    icsSay(emit, String(format: L("tIME claims the picture was last modified %lld-%02lld-%02lld %02lld:%02lld:%02lld UTC"), Int64(year), Int64(b[p + 2]), Int64(b[p + 3]), Int64(b[p + 4]), Int64(b[p + 5]), Int64(b[p + 6])), .out)
                }
            }
        }
        if papers == 0 {
            icsSay(emit, L("no text, time, or EXIF chunks: this PNG carries no papers beyond its pixels."), .out)
        }
    }

    // MARK: the TIFF core (EXIF's engine)

    struct FileTIFF {
        var fields: [String: String] = [:]
        var gpsPresent = false
        var gpsText = ""
    }

    /// A TIFF directory walk: IFD0,
    /// the EXIF sub-directory, and the
    /// GPS sub-directory, read with
    /// the file's own byte order.
    static func fileTIFF(
        _ b: [UInt8], base: Int)
        -> FileTIFF? {
        guard base + 8 <= b.count else {
            return nil
        }
        let big: Bool
        if b[base] == 0x49
            && b[base + 1] == 0x49 {
            big = false
        } else if b[base] == 0x4D
            && b[base + 1] == 0x4D {
            big = true
        } else {
            return nil
        }
        func u16(_ o: Int) -> Int? {
            big ? fileU16BE(b, o)
                : fileU16LE(b, o)
        }
        func u32(_ o: Int) -> Int? {
            big ? fileU32BE(b, o)
                : fileU32LE(b, o)
        }
        guard u16(base + 2) == 42,
              let ifd0 = u32(base + 4)
        else { return nil }
        var out = FileTIFF()
        let sizeOf: [Int: Int] = [
            1: 1, 2: 1, 3: 2, 4: 4, 5: 8,
            6: 1, 7: 1, 8: 2, 9: 4, 10: 8,
            11: 4, 12: 8,
        ]
        func valueString(
            type: Int, count: Int,
            fieldAt: Int) -> String? {
            let total = (sizeOf[type] ?? 1) *
                count
            let voff: Int
            if total <= 4 {
                voff = fieldAt
            } else {
                guard let rel = u32(fieldAt)
                else { return nil }
                voff = base + rel
            }
            guard voff + total <= b.count,
                  total < 65536 else {
                return nil
            }
            switch type {
            case 2:
                return fileCString(
                    b, from: voff,
                    limit: voff + count)
            case 3:
                guard let v = u16(voff)
                else { return nil }
                return String(v)
            case 4:
                guard let v = u32(voff)
                else { return nil }
                return String(v)
            case 5, 10:
                guard let n = u32(voff),
                      let d = u32(voff + 4),
                      d != 0 else { return nil }
                let v = Double(n) / Double(d)
                return String(format: "%.4f", v)
            default:
                return nil
            }
        }
        func walk(
            ifdRel: Int, prefix: String,
            depth: Int) {
            guard depth < 3 else { return }
            let io = base + ifdRel
            guard let n = u16(io) else {
                return
            }
            for i in 0..<min(n, 64) {
                let entry = io + 2 + i * 12
                guard entry + 12 <= b.count,
                      let tag = u16(entry),
                      let type = u16(entry + 2),
                      let count = u32(entry + 4)
                else { continue }
                if tag == 0x8769
                    || tag == 0x8825 {
                    // sub-directory pointer
                    if let rel = u32(entry + 8) {
                        walk(
                            ifdRel: rel,
                            prefix: tag == 0x8825
                                ? "GPS " : "",
                            depth: depth + 1)
                    }
                    continue
                }
                if prefix == "GPS ",
                   tag == 2 || tag == 4 {
                    if let parts =
                        rationalList(
                            type: type,
                            count: count,
                            fieldAt: entry + 8) {
                        if tag == 2 {
                            latParts = parts
                        } else {
                            lonParts = parts
                        }
                    }
                }
                if let value = valueString(
                    type: type, count: count,
                    fieldAt: entry + 8) {
                    out.fields[
                        prefix
                            + String(tag)] = value
                    if prefix == "GPS " {
                        if tag == 1 {
                            latRef = value
                        }
                        if tag == 3 {
                            lonRef = value
                        }
                    }
                }
            }
        }
        func rationalList(
            type: Int, count: Int,
            fieldAt: Int) -> [Double]? {
            guard type == 5 || type == 10,
                  count >= 1, count <= 8 else {
                return nil
            }
            let total = 8 * count
            guard let rel = u32(fieldAt)
            else { return nil }
            let voff = base + rel
            guard voff + total <= b.count
            else { return nil }
            var parts: [Double] = []
            for i in 0..<count {
                guard let n = u32(
                        voff + i * 8),
                      let d = u32(
                        voff + i * 8 + 4),
                      d != 0 else {
                    return nil
                }
                parts.append(
                    Double(n) / Double(d))
            }
            return parts
        }
        var latParts: [Double]?
        var lonParts: [Double]?
        var latRef = ""
        var lonRef = ""
        walk(ifdRel: ifd0, prefix: "",
             depth: 0)
        // GPS: the decimal fix, computed
        // from the rationals the file
        // claims — degrees, minutes and
        // seconds, signed by the refs.
        if let lat = latParts, lat.count == 3,
           let lon = lonParts, lon.count == 3 {
            var la = lat[0] + lat[1] / 60
                + lat[2] / 3600
            var lo = lon[0] + lon[1] / 60
                + lon[2] / 3600
            if latRef == "S" { la = -la }
            if lonRef == "W" { lo = -lo }
            out.gpsPresent = true
            out.gpsText = String(format: L(" — by its own rationals, about %.4f, %.4f"), la, lo)
        } else if out.fields[
            "GPS " + String(0x0001)] != nil {
            out.gpsPresent = true
        }
        return out
    }

    static func fileTIFFReport(
        _ tiff: FileTIFF,
        emit: @escaping BlacksiteEmit) {
        let known: [(String, String)] = [
            ("271", L("make")), ("272", L("model")),
            ("305", L("software")),
            ("306", L("date/time")),
            ("36867", L("date/time original")),
            ("36868", L("date/time digitized")),
            ("40962", L("pixel width")),
            ("40963", L("pixel height")),
            ("315", L("artist")),
            ("33432", L("copyright")),
            ("270", L("description")),
        ]
        var printed = 0
        for (tag, label) in known {
            if let value = tiff.fields[tag] {
                icsSay(emit, String(format: L("%@: %@ (the file's claim)"), label, value), .out)
                printed += 1
            }
        }
        if printed == 0 {
            icsSay(emit, L("the TIFF directory parses but carries none of the fields the bench reads by name."), .out)
        }
        if tiff.gpsPresent {
            icsSay(emit, String(format: L("GPS papers are present%@ — the picture claims a place. Coordinates in a file are a claim about where a camera said it was; treat them like any other testimony."), tiff.gpsText), .err)
        }
    }

    static func fileXMLValue(
        _ text: String, tag: String)
        -> String? {
        let open = "<" + tag + ">"
        let close = "</" + tag + ">"
        guard let r1 = text.range(of: open),
              let r2 = text.range(
                of: close,
                range: r1.upperBound..<text.endIndex)
        else { return nil }
        let value = String(text[
            r1.upperBound..<r2.lowerBound])
        return value.isEmpty ? nil : value
    }

    static func fileXMLAttr(
        _ text: String, attr: String)
        -> String? {
        let needle = attr + "=\""
        guard let r = text.range(of: needle)
        else { return nil }
        let rest = text[r.upperBound...]
        guard let end = rest.firstIndex(
            of: "\"") else { return nil }
        let value = String(rest[..<end])
        return value.isEmpty ? nil : value
    }
}

extension BlacksiteBench {

    // MARK: pdfprobe — a document read as claims

    struct FilePDF {
        var version = "?"
        var objects = 0
        var streams = 0
        var pagesCounted = 0
        var pagesClaim: Int?
        var javascript = 0
        var js = 0
        var embeddedFiles = 0
        var filespecs = 0
        var openActions = 0
        var launch = 0
        var addActions = 0
        var acroForm = false
        var xfa = false
        var encrypted = false
        var objStm = false
        var eofs = 0
        var xmp = false
        var info: [(String, String)] = []
    }

    /// The PDF core over the whole
    /// byte body as Latin-1 text:
    /// dictionary tallies, the page
    /// tree's claim against the bodies
    /// counted, the info dictionary's
    /// strings, and every active-content
    /// paper the format can carry. The
    /// document is never rendered, its
    /// streams never inflated.
    static func filePDFCore(
        _ b: [UInt8]) -> FilePDF {
        var p = FilePDF()
        let text = String(
            decoding: b, as: UTF8.self)
        if b.count > 8,
           text.hasPrefix("%PDF-") {
            p.version = String(
                decoding: b[5..<8],
                as: UTF8.self)
        }
        // Object headers: a number, a
        // number, the word obj, at the
        // start of a line — counted once
        // each (a first draft of this
        // census counted every header
        // twice and the mirror caught
        // it against the fixture).
        var objects = 0
        var streams = 0
        var pageBodies = 0
        var cursor = text.startIndex
        func countOccurrences(
            _ needle: String) -> Int {
            var n = 0
            var from = text.startIndex
            while let r = text.range(
                of: needle,
                range: from..<text.endIndex) {
                n += 1
                from = r.upperBound
            }
            return n
        }
        _ = cursor
        let lines = text.split(
            separator: "\n",
            omittingEmptySubsequences: false)
        for line in lines {
            let t = line.trimmingCharacters(
                in: .whitespaces)
            let parts = t.split(
                separator: " ")
            if parts.count >= 3,
               parts[2] == "obj",
               Int(parts[0]) != nil,
               Int(parts[1]) != nil,
               parts[0].allSatisfy({
                   $0.isNumber
               }),
               parts[1].allSatisfy({
                   $0.isNumber
               }) {
                objects += 1
            }
        }
        for line in lines
        where line.contains("stream") {
            let t = line.trimmingCharacters(
                in: .whitespaces)
            if t == "stream"
                || t.hasSuffix(" stream") {
                streams += 1
            }
        }
        _ = pageBodies
        p.objects = objects
        p.streams = streams
        p.javascript = countOccurrences(
            "/JavaScript")
        p.js = countOccurrences("/JS")
        p.embeddedFiles = countOccurrences(
            "/EmbeddedFile")
        p.filespecs = countOccurrences(
            "/Filespec")
        p.openActions = countOccurrences(
            "/OpenAction")
        p.launch = countOccurrences(
            "/Launch")
        p.addActions = countOccurrences(
            "/AA")
        p.acroForm = text.contains(
            "/AcroForm")
        p.xfa = text.contains("/XFA")
        p.encrypted = text.contains(
            "/Encrypt")
        p.objStm = text.contains(
            "/ObjStm")
        p.eofs = countOccurrences("%%EOF")
        p.xmp = text.contains(
            "x:xmpmeta")
            || text.contains("<?xpacket")
        // Page bodies against the tree's
        // claim: /Type /Page that is not
        // /Pages, and the /Pages node's
        // own /Count.
        var from = text.startIndex
        while let r = text.range(
            of: "/Type", range: from..<text.endIndex) {
            let after = text[r.upperBound...]
            let trimmed = after.drop(
                while: { $0 == " " })
            if trimmed.hasPrefix("/Page")
                && !trimmed.hasPrefix(
                    "/Pages") {
                pageBodies += 1
            }
            from = r.upperBound
        }
        p.pagesCounted = pageBodies
        if let r = text.range(
            of: "/Pages") {
            let window = text[r.lowerBound..<text.index(r.lowerBound,
                            offsetBy: 200,
                            limitedBy:
                                text.endIndex)
                    ?? text.endIndex]
            if let cr = window.range(
                of: "/Count") {
                let rest = window[
                    cr.upperBound...]
                let digits = rest.drop(
                    while: { $0 == " " })
                    .prefix(while: {
                        $0.isNumber
                    })
                p.pagesClaim = Int(digits)
            }
        }
        p.info = filePDFInfo(text)
        return p
    }

    /// The Info dictionary's strings:
    /// the object that carries a
    /// /Title, walked for its literal
    /// and hex strings.
    static func filePDFInfo(
        _ text: String)
        -> [(String, String)] {
        guard let r = text.range(
            of: "/Title") else { return [] }
        // The Info object begins at the
        // last '<<' before the title and
        // ends at the next '>>'.
        let before = text[..<r.lowerBound]
        guard let open = before.range(
            of: "<<",
            options: .backwards) else {
            return []
        }
        let from = open.lowerBound
        let window = text[from..<text.index(from, offsetBy: 3000,
                       limitedBy: text.endIndex)
                ?? text.endIndex]
        guard let close = window.range(
            of: ">>") else { return [] }
        let dict = window[..<close.lowerBound]
        var out: [(String, String)] = []
        let keys = ["Title", "Author",
                    "Creator", "Producer",
                    "Subject", "Keywords",
                    "CreationDate", "ModDate"]
        for key in keys {
            let needle = "/" + key
            guard let kr = dict.range(
                of: needle) else { continue }
            let rest = dict[kr.upperBound...]
                .drop(while: { $0 == " " })
            if rest.hasPrefix("(") {
                var value = ""
                var depth = 0
                var escaped = false
                for ch in rest.dropFirst() {
                    if escaped {
                        value.append(ch)
                        escaped = false
                        continue
                    }
                    if ch == "\\" {
                        escaped = true
                        continue
                    }
                    if ch == "(" {
                        depth += 1
                        value.append(ch)
                        continue
                    }
                    if ch == ")" {
                        if depth == 0 {
                            break
                        }
                        depth -= 1
                        value.append(ch)
                        continue
                    }
                    value.append(ch)
                }
                if !value.isEmpty {
                    out.append((key, value))
                }
            } else if rest.hasPrefix("<")
                && !rest.hasPrefix("<<") {
                let hex = rest.dropFirst()
                    .prefix(while: {
                        $0 != ">"
                    })
                var bytes: [UInt8] = []
                var nibble: UInt8?
                for ch in hex {
                    guard let v = ch.hexDigitValue
                    else { continue }
                    if let hi = nibble {
                        bytes.append(
                            hi << 4
                                | UInt8(v))
                        nibble = nil
                    } else {
                        nibble = UInt8(v)
                    }
                }
                let value = String(
                    decoding: bytes,
                    as: UTF8.self)
                if !value.isEmpty {
                    out.append((key, value))
                }
            }
        }
        return out
    }

    static func pdfprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "pdfprobe",
                    emit: emit) else { return }
            fileHeader("pdfprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            if fileKind(b)?.family != "pdf" {
                icsSay(emit, L("the header is not a PDF header — whatever this is, it is not read as a document here."), .err)
                return
            }
            filePDFReport(b, emit: emit)
        }
    }

    static func filePDFReport(
        _ b: [UInt8],
        emit: @escaping BlacksiteEmit) {
        let p = filePDFCore(b)
        icsSay(emit, String(format: L("the header claims PDF %@"), p.version), .out)
        icsSay(emit, String(format: L("%lld objects, %lld streams (never inflated), %lld %%EOF marks — more than one means the file was edited by appending, and the newest papers win"), Int64(p.objects), Int64(p.streams), Int64(p.eofs)), .out)
        if let claim = p.pagesClaim {
            if claim == p.pagesCounted {
                icsSay(emit, String(format: L("pages: %lld counted, and the page tree claims %lld — the papers agree"), Int64(p.pagesCounted), Int64(claim)), .ok)
            } else {
                icsSay(emit, String(format: L("pages: %lld counted, but the page tree claims %lld — a claim the bodies do not back. Readers trust the tree; the bench counts bodies."), Int64(p.pagesCounted), Int64(claim)), .err)
            }
        } else {
            icsSay(emit, String(format: L("pages: %lld counted; no /Pages claim was found to grade"), Int64(p.pagesCounted)), .out)
        }
        if p.javascript + p.js > 0
            || p.launch > 0
            || p.openActions > 0 {
            icsSay(emit, String(format: L("active papers: /JavaScript x%lld, /JS x%lld, /OpenAction x%lld, /Launch x%lld, /AA x%lld — a document that acts when opened. The bench reads the papers; it never lets the document perform them."), Int64(p.javascript), Int64(p.js), Int64(p.openActions), Int64(p.launch), Int64(p.addActions)), .err)
        } else {
            icsSay(emit, L("no script, launch, or open-action papers found"), .ok)
        }
        if p.embeddedFiles > 0
            || p.filespecs > 0 {
            icsSay(emit, String(format: L("carried files: /EmbeddedFile x%lld, /Filespec x%lld — something rides inside this document. The bench names the luggage; it does not open it."), Int64(p.embeddedFiles), Int64(p.filespecs)), .err)
        }
        if p.encrypted {
            icsSay(emit, L("an /Encrypt dictionary is present: parts of this document are sealed, by its own papers — the census above covers what stayed readable"), .out)
        }
        if p.acroForm {
            icsSay(emit, L("an /AcroForm is present — a form rides in the document"), .out)
        }
        if p.xfa {
            icsSay(emit, L("an /XFA form is present — a second, XML-shaped document inside the first"), .out)
        }
        if p.xmp {
            icsSay(emit, L("an XMP metadata packet is present"), .out)
        }
        for (key, value) in p.info {
            icsSay(emit, String(format: L("info: %@ = %@ (the file's claim)"), key, value), .out)
        }
        if p.info.isEmpty {
            icsSay(emit, L("no Info dictionary strings found — the document names no author and no maker"), .out)
        }
    }

    // MARK: zipprobe — the archive ledger

    struct FileZIPEntry {
        var name: String
        var flags: Int
        var method: Int
        var compSize: Int
        var rawSize: Int
        var aesStrength: Int?
        var localOffset: Int
    }

    struct FileZIP {
        var entries: [FileZIPEntry] = []
        var count = 0
        var comment = ""
        var prepended = 0
        var cdOffset = 0
    }

    /// Locate the end-of-central-
    /// directory record in a byte
    /// window that ends the file: the
    /// last 64 KB plus the record
    /// itself, scanning backwards.
    static func fileFindEOCD(
        _ b: [UInt8]) -> Int? {
        guard b.count >= 22 else {
            return nil
        }
        var i = b.count - 22
        while i >= 0 {
            if b[i] == 0x50 && b[i + 1] == 0x4B
                && b[i + 2] == 0x05
                && b[i + 3] == 0x06 {
                if let clen = fileU16LE(
                    b, i + 20),
                   i + 22 + clen == b.count {
                    return i
                }
            }
            i -= 1
        }
        return nil
    }

    /// The central-directory walk:
    /// names, methods, flags, the AES
    /// extra field's strength claim,
    /// and how much of the file rides
    /// in front of the archive proper.
    static func fileZIPWalk(
        _ b: [UInt8]) -> FileZIP? {
        let windowStart = max(
            0, b.count - 65557)
        let tail = Array(b[windowStart...])
        guard let rel = fileFindEOCD(tail)
        else { return nil }
        let eocd = windowStart + rel
        var zip = FileZIP()
        var total = fileU16LE(b, eocd + 10)
            ?? 0
        var cdOff = fileU32LE(b, eocd + 16)
            ?? 0
        if total == 0xFFFF
            || cdOff == 0xFFFFFFFF {
            // ZIP64: the locator sits
            // twenty bytes before the
            // classic record.
            let loc = eocd - 20
            if loc >= 0,
               b[loc] == 0x50, b[loc + 1] == 0x4B,
               b[loc + 2] == 0x06,
               b[loc + 3] == 0x07,
               let z64off = fileU64LE(
                b, loc + 8) {
                let z = Int(z64off)
                if let t = fileU64LE(b, z + 32) {
                    total = Int(t)
                }
                if let o = fileU64LE(b, z + 48) {
                    cdOff = Int(o)
                }
            }
        }
        zip.count = total
        zip.cdOffset = cdOff
        zip.comment = fileCString(
            b, from: eocd + 22,
            limit: b.count)
        var pos = cdOff
        var firstLocal: Int?
        var detailed = 0
        while pos + 46 <= b.count,
              b[pos] == 0x50, b[pos + 1] == 0x4B,
              b[pos + 2] == 0x01,
              b[pos + 3] == 0x02 {
            guard let flags = fileU16LE(
                    b, pos + 8),
                  let method = fileU16LE(
                    b, pos + 10),
                  let comp = fileU32LE(
                    b, pos + 20),
                  let raw = fileU32LE(
                    b, pos + 24),
                  let nlen = fileU16LE(
                    b, pos + 28),
                  let elen = fileU16LE(
                    b, pos + 30),
                  let clen = fileU16LE(
                    b, pos + 32),
                  let local = fileU32LE(
                    b, pos + 42)
            else { break }
            let nameStart = pos + 46
            guard nameStart + nlen
                    <= b.count else { break }
            let name = String(
                decoding: b[nameStart..<(nameStart + nlen)],
                as: UTF8.self)
            var aes: Int?
            var xp = nameStart + nlen
            let xEnd = min(b.count, xp + elen)
            while xp + 4 <= xEnd {
                guard let tag = fileU16LE(
                        b, xp),
                      let len = fileU16LE(
                        b, xp + 2)
                else { break }
                if tag == 0x9901,
                   len >= 4,
                   xp + 4 + 4 <= xEnd {
                    aes = Int(b[xp + 4 + 3])
                }
                xp += 4 + len
            }
            if detailed < 1000 {
                zip.entries.append(
                    FileZIPEntry(
                        name: name, flags: flags,
                        method: method,
                        compSize: comp,
                        rawSize: raw,
                        aesStrength: aes,
                        localOffset: local))
                detailed += 1
            }
            if firstLocal == nil {
                firstLocal = local
            }
            pos = xEnd + clen
        }
        zip.prepended = firstLocal ?? 0
        return zip
    }

    static func zipprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "zipprobe",
                    emit: emit) else { return }
            fileHeader("zipprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            guard let zip = fileZIPWalk(b)
            else {
                icsSay(emit, L("no end-of-central-directory at the tail: not a ZIP the bench can read — a truncated archive, a different format wearing the name, or a stream with no directory."), .err)
                return
            }
            icsSay(emit, String(format: L("the directory claims %lld entries; %lld are read in detail below"), Int64(zip.count), Int64(zip.entries.count)), .out)
            if zip.prepended > 0 {
                icsSay(emit, String(format: L("%lld bytes ride in front of the first entry — a self-extracting stub, a picture, or something else wearing an archive behind it"), Int64(zip.prepended)), .err)
            }
            if !zip.comment.isEmpty {
                icsSay(emit, String(format: L("the archive's comment: '%@'"), zip.comment), .out)
            }
            var encrypted = 0
            var traversal: [String] = []
            var nested: [String] = []
            var storedBytes = 0
            let methodName: (Int) -> String = {
                m in
                switch m {
                case 0: return L("stored")
                case 8: return L("deflated")
                case 9: return L("deflate64")
                case 12: return L("bzip2")
                case 14: return L("LZMA")
                case 99: return L("AES-sealed")
                default: return String(format: L("method %lld"), Int64(m))
                }
            }
            for entry in zip.entries {
                var marks: [String] = []
                if entry.flags & 1 != 0 {
                    encrypted += 1
                    marks.append(L("encrypted-flagged"))
                }
                if let strength =
                    entry.aesStrength {
                    let label = [
                        L("AES-128"), L("AES-192"),
                        L("AES-256")][
                            min(2, max(0,
                                strength - 1))]
                    marks.append(label)
                }
                if entry.name.hasPrefix("/")
                    || entry.name.contains(
                        "../")
                    || entry.name.hasPrefix(
                        "..\\")
                    || (entry.name.count > 1
                        && entry.name.dropFirst()
                            .first == ":") {
                    traversal.append(entry.name)
                    marks.append(L("path escapes the archive"))
                }
                let lower = entry.name
                    .lowercased()
                if lower.hasSuffix(".zip")
                    || lower.hasSuffix(".jar")
                    || lower.hasSuffix(".apk")
                    || lower.hasSuffix(".ipa") {
                    nested.append(entry.name)
                    marks.append(L("an archive inside the archive"))
                }
                storedBytes += entry.rawSize
                let markText = marks.isEmpty
                    ? ""
                    : " — " + marks.joined(
                        separator: ", ")
                icsSay(emit, String(format: L("%@ (%@, %lld bytes in %lld) %@"), entry.name, methodName(entry.method), Int64(entry.rawSize), Int64(entry.compSize), markText), .out)
            }
            if zip.count >
                zip.entries.count {
                icsSay(emit, String(format: L("... and %lld more entries past the detail cap — counted, not read"), Int64(zip.count - zip.entries.count)), .out)
            }
            if encrypted > 0 {
                icsSay(emit, String(format: L("%lld entries carry the encryption flag — names stay readable, contents stay shut. The bench lists; it does not pick locks."), Int64(encrypted)), .err)
            }
            if traversal.isEmpty
                && encrypted == 0 {
                icsSay(emit, L("no path escapes, no sealed entries in the detail read — a plain archive, by its papers"), .ok)
            }
            _ = storedBytes
        }
    }

    // MARK: machoprobe — the fat and the thin

    static func machoprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "machoprobe",
                    emit: emit) else { return }
            fileHeader("machoprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            guard b.count >= 4 else {
                icsSay(emit, L("too small to carry a Mach-O header."), .err)
                return
            }
            let magic = Array(b.prefix(4))
            if magic == [0xCA, 0xFE, 0xBA, 0xBE] {
                // Fat — or a Java class
                // file wearing the same
                // papers. A class file's
                // second word is a version,
                // not a slice count.
                if let n = fileU32BE(b, 4) {
                    if n > 20 {
                        icsSay(emit, L("CA FE BA BE with no plausible slice count: these are Java class papers, not a fat binary — the two formats share a magic and part ways here."), .err)
                        return
                    }
                    icsSay(emit, String(format: L("a fat binary: the directory claims %lld slices"), Int64(n)), .out)
                    for i in 0..<min(n, 16) {
                        let off = 8 + i * 20
                        guard let cpu = fileU32BE(
                                b, off),
                              let subtype = fileU32BE(
                                b, off + 4),
                              let sliceOff = fileU32BE(
                                b, off + 8),
                              let sliceSize = fileU32BE(
                                b, off + 12)
                        else { break }
                        let name = fileMachOName(
                            cpu: Int(cpu),
                            subtype: Int(subtype))
                        icsSay(emit, String(format: L("slice %lld: %@ at %lld, %lld bytes (the directory's claim)"), Int64(i), name, Int64(sliceOff), Int64(sliceSize)), .out)
                        fileMachOThin(
                            b, base: Int(sliceOff),
                            emit: emit)
                    }
                }
                return
            }
            if magic == [0xCA, 0xFE, 0xBA, 0xBF] {
                icsSay(emit, L("a 64-bit fat binary (FAT_CIGAM_64): the slice directory uses 64-bit offsets — this reader walks thin files and classic fat files; the fat64 directory is noted, not walked."), .err)
                return
            }
            fileMachOThin(b, base: 0,
                          emit: emit)
        }
    }

    static func fileMachOName(
        cpu: Int, subtype: Int) -> String {
        let family = cpu & 0xFFFFFF
        let ability = cpu & 0x1000000 != 0
        if family == 12 && ability {
            return subtype == 2
                ? "arm64e" : "arm64"
        }
        if family == 12 { return "arm" }
        if family == 7 {
            return ability ? "x86_64" : "i386"
        }
        if family == 18 {
            return ability ? "ppc64" : "ppc"
        }
        return String(format: L("cpu type %lld"), Int64(cpu))
    }

    /// One thin Mach-O, read at its own
    /// base with its own endianness —
    /// the walk the mirror verified
    /// byte for byte.
    static func fileMachOThin(
        _ b: [UInt8], base: Int,
        emit: @escaping BlacksiteEmit) {
        guard base + 4 <= b.count else {
            return
        }
        let m = Array(b[base..<(base + 4)])
        let is64: Bool
        let little: Bool
        if m == [0xFE, 0xED, 0xFA, 0xCF] {
            is64 = true; little = false
        } else if m == [0xCF, 0xFA, 0xED, 0xFE] {
            is64 = true; little = true
        } else if m == [0xFE, 0xED, 0xFA, 0xCE] {
            is64 = false; little = false
        } else if m == [0xCE, 0xFA, 0xED, 0xFE] {
            is64 = false; little = true
        } else {
            icsSay(emit, L("no Mach-O magic at this base — the fat directory's claim does not parse as a slice."), .err)
            return
        }
        func u32(_ o: Int) -> Int? {
            little ? fileU32LE(b, o)
                : fileU32BE(b, o)
        }
        guard let cpuRaw = u32(base + 4),
              let subtype = u32(base + 8),
              let filetype = u32(base + 12),
              let ncmds = u32(base + 16),
              let flags = u32(base + 24)
        else {
            icsSay(emit, L("the header itself is truncated."), .err)
            return
        }
        // cputype arrives as an unsigned
        // word whose high byte carries the
        // capability bit; grade on the raw
        // word, not a signed reading.
        let cpu = cpuRaw
        let typeNames: [Int: String] = [
            1: "OBJECT", 2: "EXECUTE",
            3: "FVMLIB", 4: "CORE",
            5: "PRELOAD", 6: "DYLIB",
            7: "DYLINKER", 8: "BUNDLE",
            9: "DYLIB_STUB", 10: "DSYM",
            11: "KEXT",
        ]
        let typeLine = typeNames[filetype]
            ?? String(format: L("type %lld"), Int64(filetype))
        icsSay(emit, String(format: L("thin Mach-O: %@, %@, %lld load commands, header flags 0x%llx"), fileMachOName(cpu: cpu, subtype: subtype), typeLine, Int64(ncmds), Int64(flags)), .out)
        if flags & 0x200000 != 0 {
            icsSay(emit, L("the header claims MH_PIE — built to load anywhere"), .out)
        }
        if flags & 0x40000 != 0 {
            icsSay(emit, L("the header sets ALLOW_STACK_EXECUTION — a stack that may run code, claimed in its own flags"), .err)
        }
        var cursor = base + (is64 ? 32 : 28)
        var segments = 0
        var libs: [String] = []
        var rpaths: [String] = []
        var cryptid: Int?
        var codeSignature = false
        var buildLine: String?
        // The command words are matched
        // raw, exactly as the verifying
        // mirror matched them: LC_RPATH
        // is 0x1C under LC_REQ_DYLD, the
        // weak/reexport dylib loads carry
        // their full words too.
        let dylibCommands: Set<Int> = [
            0xC, 0xD, 0x80000018, 0x1F,
            0x20, 0x23,
        ]
        for _ in 0..<min(ncmds, 512) {
            guard let cmd = u32(cursor),
                  let size = u32(cursor + 4),
                  size >= 8 else { break }
            if cmd == 0x1 || cmd == 0x19 {
                segments += 1
            }
            if dylibCommands.contains(cmd),
               let off = u32(cursor + 8) {
                let s = fileCString(
                    b, from: cursor + off,
                    limit: cursor + size)
                if !s.isEmpty {
                    libs.append(s)
                }
            }
            if cmd == 0x8000001C,
               let off = u32(cursor + 8) {
                let s = fileCString(
                    b, from: cursor + off,
                    limit: cursor + size)
                if !s.isEmpty {
                    rpaths.append(s)
                }
            }
            if cmd == 0x21 || cmd == 0x2C {
                cryptid = u32(cursor + 16)
            }
            if cmd == 0x1D {
                codeSignature = true
            }
            if cmd == 0x32 {
                if let platform = u32(cursor + 8),
                   let minos = u32(cursor + 12) {
                    let platforms: [Int: String] = [
                        1: "macOS", 2: "iOS",
                        3: "tvOS", 4: "watchOS",
                        5: "bridgeOS", 6: "iOS (Mac Catalyst)",
                        7: "iOS simulator",
                        8: "tvOS simulator",
                        9: "watchOS simulator",
                        10: "driverKit",
                        11: "visionOS",
                        12: "visionOS simulator",
                    ]
                    let plat = platforms[platform]
                        ?? String(format: L("platform %lld"), Int64(platform))
                    buildLine = String(format: L("built for %@, minimum OS %lld.%lld.%lld (its own build papers)"), plat, Int64((minos >> 16) & 0xFFFF), Int64((minos >> 8) & 0xFF), Int64(minos & 0xFF))
                }
            }
            cursor += size
        }
        icsSay(emit, String(format: L("%lld segments walked"), Int64(segments)), .out)
        for lib in libs {
            icsSay(emit, String(format: L("links %@ (a claim — the library is not opened)"), lib), .out)
        }
        for rp in rpaths {
            icsSay(emit, String(format: L("runpath: %@"), rp), .out)
        }
        if let cryptid = cryptid {
            if cryptid == 0 {
                icsSay(emit, L("the encryption info says cryptid 0 — the pages stand unencrypted, by the file's own papers"), .out)
            } else {
                icsSay(emit, String(format: L("the encryption info says cryptid %lld — FairPlay stands over these pages on a device"), Int64(cryptid)), .out)
            }
        }
        if codeSignature {
            icsSay(emit, L("a code signature blob rides with the file — its seals are read by codesign on a Mac, not graded here"), .out)
        }
        if let buildLine = buildLine {
            icsSay(emit, buildLine, .out)
        }
        // The string scan: the canary and
        // the runtime's own telltales,
        // read out of the slice's bytes
        // and labelled as strings — the
        // same evidence stringsdeep
        // would show.
        let region = String(
            decoding: b[base...],
            as: UTF8.self)
        if region.contains(
            "___stack_chk_guard") {
            icsSay(emit, L("the slice's strings name ___stack_chk_guard — stack canaries stand in this binary (a claim read from its strings)"), .out)
        }
        if region.contains(
            "_objc_storeStrong") {
            icsSay(emit, L("the slice's strings name _objc_storeStrong — ARC-managed Objective-C rides here"), .out)
        }
    }

    // MARK: elfprobe — the other executable

    static func elfprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "elfprobe",
                    emit: emit) else { return }
            fileHeader("elfprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            fileELFReport(b, base: 0,
                          emit: emit)
        }
    }

    static func fileELFReport(
        _ b: [UInt8], base: Int,
        emit: @escaping BlacksiteEmit) {
        guard base + 20 <= b.count,
              b[base] == 0x7F,
              b[base + 1] == 0x45,
              b[base + 2] == 0x4C,
              b[base + 3] == 0x46 else {
            icsSay(emit, L("no ELF papers at this base."), .err)
            return
        }
        let is64 = b[base + 4] == 2
        let little = b[base + 5] != 2
        func u16(_ o: Int) -> Int? {
            little ? fileU16LE(b, o)
                : fileU16BE(b, o)
        }
        func u32(_ o: Int) -> Int? {
            little ? fileU32LE(b, o)
                : fileU32BE(b, o)
        }
        func u64(_ o: Int) -> UInt64? {
            little ? fileU64LE(b, o)
                : fileU64BE(b, o)
        }
        guard let etype = u16(base + 16),
              let machine = u16(base + 18)
        else { return }
        let machines: [Int: String] = [
            3: "i386", 20: "PowerPC",
            40: "ARM", 62: "x86-64",
            183: "AArch64", 243: "RISC-V",
            8: "MIPS", 50: "IA-64",
            75: "VAX", 164: "LoongArch",
        ]
        let typeNames: [Int: String] = [
            1: "REL (relocatable)",
            2: "EXEC (fixed-address executable)",
            3: "DYN (shared object / PIE)",
            4: "CORE",
        ]
        let machineName = machines[machine]
            ?? String(format: L("machine %lld"), Int64(machine))
        let typeName = typeNames[etype]
            ?? String(format: L("type %lld"), Int64(etype))
        icsSay(emit, String(format: L("ELF%lld, %@-endian: %@, %@"), Int64(is64 ? 64 : 32), little ? L("little") : L("big"), machineName, typeName), .out)
        // Program headers.
        let phoff: Int
        let phentsize: Int
        let phnum: Int
        if is64 {
            phoff = u64(base + 32).map(Int.init) ?? 0
            phentsize = u16(base + 54) ?? 56
            phnum = u16(base + 56) ?? 0
        } else {
            phoff = u32(base + 28) ?? 0
            phentsize = u16(base + 42) ?? 32
            phnum = u16(base + 44) ?? 0
        }
        var interp: String?
        var stackX = false
        var hasStack = false
        var relro = false
        var dynamicOff: Int?
        var loads: [(Int, Int, Int)] = []
        for i in 0..<min(phnum, 128) {
            let ph = base + phoff
                + i * phentsize
            guard let ptype = u32(ph)
            else { break }
            if is64 {
                guard let off = u64(ph + 8),
                      let vaddr = u64(ph + 16),
                      let filesz = u64(ph + 32)
                else { break }
                switch ptype {
                case 1:
                    loads.append((Int(off),
                                  Int(vaddr),
                                  Int(filesz)))
                case 2:
                    dynamicOff = Int(off)
                case 3:
                    interp = fileCString(
                        b, from: base + Int(off),
                        limit: base + Int(off)
                            + Int(filesz))
                case 0x6474E550:
                    hasStack = true
                    let flags = u32(ph + 4) ?? 0
                    if flags & 1 != 0 {
                        stackX = true
                    }
                case 0x6474E552:
                    relro = true
                default:
                    break
                }
            } else {
                guard let off = u32(ph + 4),
                      let vaddr = u32(ph + 8),
                      let filesz = u32(ph + 16)
                else { break }
                switch ptype {
                case 1:
                    loads.append((off, vaddr,
                                  filesz))
                case 2:
                    dynamicOff = off
                case 3:
                    interp = fileCString(
                        b, from: base + off,
                        limit: base + off
                            + filesz)
                case 0x6474E550:
                    hasStack = true
                    let flags = u32(ph + 24) ?? 0
                    if flags & 1 != 0 {
                        stackX = true
                    }
                case 0x6474E552:
                    relro = true
                default:
                    break
                }
            }
        }
        let isPIE = etype == 3
            && interp != nil
        if isPIE {
            icsSay(emit, L("a DYN that names an interpreter: a PIE executable — it loads anywhere, by design"), .ok)
        }
        if let interp = interp {
            icsSay(emit, String(format: L("interpreter: %@ (the loader it asks the kernel for)"), interp), .out)
        }
        if hasStack {
            if stackX {
                icsSay(emit, L("PT_GNU_STACK asks for an EXECUTABLE stack — a hardening debt, claimed in the file's own program headers"), .err)
            } else {
                icsSay(emit, L("PT_GNU_STACK stands without the execute bit — the stack does not run code"), .ok)
            }
        }
        if relro {
            icsSay(emit, L("PT_GNU_RELRO stands — relocation pages go read-only once resolved"), .ok)
        }
        // The dynamic ledger.
        guard let dynOff = dynamicOff
        else {
            icsSay(emit, L("no PT_DYNAMIC segment — a static binary, or not a linked one"), .out)
            return
        }
        func v2off(_ vaddr: Int) -> Int? {
            for (off, va, sz) in loads
            where vaddr >= va
                && vaddr < va + sz {
                return off + (vaddr - va)
            }
            return nil
        }
        var strtabAddr: Int?
        var entries: [(Int, Int)] = []
        var pos = base + dynOff
        for _ in 0..<512 {
            let tag: Int
            let val: Int
            if is64 {
                guard let t = u64(pos),
                      let v = u64(pos + 8)
                else { break }
                // A tag word past the
                // signed range (a crafted
                // file's idea of a joke)
                // becomes a sentinel the
                // switch never matches —
                // never a trapping cast.
                tag = t >= 0x8000_0000_0000_0000
                    ? -1 : Int(t)
                val = v >= 0x8000_0000_0000_0000
                    ? 0 : Int(v)
            } else {
                guard let t = u32(pos),
                      let v = u32(pos + 4)
                else { break }
                tag = t
                val = v
            }
            if tag == 0 { break }
            entries.append((tag, val))
            if tag == 5 { strtabAddr = val }
            pos += is64 ? 16 : 8
        }
        let strtabOff = strtabAddr.flatMap {
            v2off($0)
        }
        func dynString(_ addr: Int) -> String? {
            guard let st = strtabOff,
                  let off = v2off(addr)
            else { return nil }
            _ = st
            return fileCString(
                b, from: base + off,
                limit: base + off + 4096)
        }
        for (tag, val) in entries {
            switch tag {
            case 1:
                if let s = dynString(val) {
                    icsSay(emit, String(format: L("needs %@ (a claim — the library is not opened)"), s), .out)
                }
            case 14:
                if let s = dynString(val) {
                    icsSay(emit, String(format: L("soname: %@"), s), .out)
                }
            case 15:
                if let s = dynString(val) {
                    icsSay(emit, String(format: L("rpath: %@"), s), .out)
                }
            case 29:
                if let s = dynString(val) {
                    icsSay(emit, String(format: L("runpath: %@"), s), .out)
                }
            case 30:
                if val & 0x8 != 0 {
                    icsSay(emit, L("DT_FLAGS carries BIND_NOW — every symbol resolves before main; the relocation pages can lock"), .ok)
                }
            case 0x6FFFFFFB:
                if val & 0x8000000 != 0 {
                    icsSay(emit, L("DT_FLAGS_1 claims PIE"), .out)
                }
                if val & 0x1 != 0 {
                    icsSay(emit, L("DT_FLAGS_1 carries NOW"), .out)
                }
            case 22:
                icsSay(emit, L("DT_TEXTREL stands — the text segment takes relocations; a position-independent claim it cannot fully back"), .err)
            case 24:
                icsSay(emit, L("DT_BIND_NOW stands — full resolution at load"), .ok)
            default:
                break
            }
        }
    }

    // MARK: peprobe — the Windows papers

    static func peprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "peprobe",
                    emit: emit) else { return }
            fileHeader("peprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            guard b.count > 0x40,
                  b[0] == 0x4D, b[1] == 0x5A,
                  let peOff = fileU32LE(
                    b, 0x3C),
                  peOff + 24 <= b.count,
                  b[peOff] == 0x50,
                  b[peOff + 1] == 0x45,
                  b[peOff + 2] == 0,
                  b[peOff + 3] == 0 else {
                icsSay(emit, L("no PE signature behind the MZ papers — a DOS stub alone, a renamed file, or a truncated executable. The mirror's fixture agrees with objdump here; the papers are the papers."), .err)
                return
            }
            let coff = peOff + 4
            guard let machine = fileU16LE(
                    b, coff),
                  let nsec = fileU16LE(
                    b, coff + 2),
                  let stamp = fileU32LE(
                    b, coff + 4),
                  let optSize = fileU16LE(
                    b, coff + 16)
            else { return }
            let machines: [Int: String] = [
                0x14C: "i386", 0x8664: "x86-64",
                0xAA64: "ARM64", 0x1C0: "ARM",
                0x1C4: "ARMv7",
            ]
            let machineName = machines[machine]
                ?? String(format: L("machine 0x%llx"), Int64(machine))
            icsSay(emit, String(format: L("PE for %@, %lld sections, timestamped %@ by its own COFF header (a claim — timestamps are typed, not witnessed)"), machineName, Int64(nsec), fileDateLine(stamp)), .out)
            let opt = coff + 20
            guard let magic = fileU16LE(b, opt)
            else { return }
            let plus = magic == 0x20B
            guard plus || magic == 0x10B else {
                icsSay(emit, L("the optional header's magic is neither PE32 nor PE32+ — the papers stop here."), .err)
                return
            }
            let subsystem = fileU16LE(
                b, opt + 68) ?? 0
            let dllchars = fileU16LE(
                b, opt + 70) ?? 0
            let subsystems: [Int: String] = [
                2: "Windows GUI",
                3: "Windows console",
                9: "Windows CE GUI",
                10: "EFI application",
                14: "Xbox",
            ]
            icsSay(emit, String(format: L("%@, subsystem %@, DllCharacteristics 0x%04llx"), plus ? "PE32+" : "PE32", subsystems[subsystem] ?? String(subsystem), Int64(dllchars)), .out)
            let dllFlags: [(Int, String, Bool)] = [
                (0x40, "DYNAMIC_BASE — ASLR", true),
                (0x20, "HIGH_ENTROPY_VA", true),
                (0x100, "NX_COMPAT — the stack and heap do not run code", true),
                (0x400, "NO_SEH — no structured exception chain to ride", true),
                (0x4000, "GUARD_CF — control-flow guard stands", true),
                (0x8000, "TERMINAL_SERVER aware", false),
            ]
            var claimed: [String] = []
            for (bit, label, _) in dllFlags
            where dllchars & bit != 0 {
                claimed.append(label)
            }
            if dllchars & 0x40 == 0 {
                icsSay(emit, L("no DYNAMIC_BASE: this binary loads at its preferred address every time — ASLR declined, in its own papers"), .err)
            }
            if dllchars & 0x100 == 0 {
                icsSay(emit, L("no NX_COMPAT: the binary does not swear its data pages never run"), .err)
            }
            if !claimed.isEmpty {
                icsSay(emit, String(format: L("hardening claimed: %@"), claimed.joined(separator: "; ")), .ok)
            }
            // Sections.
            let secStart = opt + optSize
            var lastRawEnd = 0
            var sections: [(String, Int, Int, Int, Int)] = []
            for i in 0..<min(nsec, 96) {
                let s = secStart + i * 40
                guard s + 40 <= b.count,
                      let vsize = fileU32LE(
                        b, s + 8),
                      let rawSize = fileU32LE(
                        b, s + 16),
                      let rawOff = fileU32LE(
                        b, s + 20),
                      let chars = fileU32LE(
                        b, s + 36)
                else { break }
                let name = fileCString(
                    b, from: s, limit: s + 8)
                sections.append((name, vsize,
                                 rawSize, rawOff,
                                 chars))
                lastRawEnd = max(
                    lastRawEnd, rawOff + rawSize)
                var flags: [String] = []
                if chars & 0x20000000 != 0 {
                    flags.append(L("executes"))
                }
                if chars & 0x80000000 != 0 {
                    flags.append(L("writes"))
                }
                if chars & 0x40000000 != 0 {
                    flags.append(L("reads"))
                }
                let flagText = flags.isEmpty
                    ? ""
                    : " (" + flags.joined(
                        separator: ", ") + ")"
                icsSay(emit, String(format: L("section %@: %lld virtual, %lld raw%@"), name, Int64(vsize), Int64(rawSize), flagText), .out)
                if chars & 0x20000000 != 0
                    && chars & 0x80000000 != 0 {
                    icsSay(emit, String(format: L("section %@ is both writable and executable — a standing invitation, claimed in its own header"), name), .err)
                }
            }
            // Imports: the directory at
            // RVA slot 1, walked through
            // the section map.
            let dirOff = opt + (plus ? 112 : 96)
            func rva2off(_ rva: Int) -> Int? {
                for i in 0..<min(nsec, 96) {
                    let s = secStart + i * 40
                    guard let va = fileU32LE(
                            b, s + 12),
                          let span = fileU32LE(
                            b, s + 8),
                          let rawOff = fileU32LE(
                            b, s + 20)
                    else { continue }
                    if rva >= va
                        && rva < va + max(span, 1) {
                        return rawOff + (rva - va)
                    }
                }
                return nil
            }
            if let impRVA = fileU32LE(
                b, dirOff + 8),
               impRVA != 0,
               let impOff = rva2off(impRVA) {
                let thunkSize = plus ? 8 : 4
                var di = impOff
                var dlls = 0
                while di + 20 <= b.count,
                      dlls < 64 {
                    guard let ilt = fileU32LE(
                            b, di),
                          let nameRVA = fileU32LE(
                            b, di + 12),
                          let iat = fileU32LE(
                            b, di + 16)
                    else { break }
                    if ilt == 0 && nameRVA == 0
                        && iat == 0 { break }
                    dlls += 1
                    var dllName = "?"
                    if let nameOff = rva2off(
                        nameRVA) {
                        dllName = fileCString(
                            b, from: nameOff,
                            limit: nameOff + 256)
                    }
                    var funcs = 0
                    if let thunkOff = rva2off(
                        ilt != 0 ? ilt : iat) {
                        var t = thunkOff
                        while t + thunkSize
                                <= b.count,
                              funcs < 10000 {
                            let v: UInt64?
                            if plus {
                                v = fileU64LE(b, t)
                            } else {
                                v = fileU32LE(
                                    b, t).map(
                                        UInt64.init)
                            }
                            guard let v = v,
                                  v != 0 else {
                                break
                            }
                            funcs += 1
                            t += thunkSize
                        }
                    }
                    icsSay(emit, String(format: L("imports %@ — %lld functions on the first thunk walk"), dllName, Int64(funcs)), .out)
                    di += 20
                }
                if dlls == 0 {
                    icsSay(emit, L("an import directory that does not walk — the papers stop at the door"), .out)
                }
            } else {
                icsSay(emit, L("no import directory — a static binary, or one that resolves its company at runtime and says nothing here"), .out)
            }
            if lastRawEnd > 0,
               b.count > lastRawEnd {
                icsSay(emit, String(format: L("%lld bytes ride past the last section's raw end — an overlay: a signature block, an installer's luggage, or something the sections do not claim"), Int64(b.count - lastRawEnd)), .err)
            }
        }
    }
}

extension BlacksiteBench {

    // MARK: imgdeep — the image censuses

    struct FileJPEGMarker {
        var name: String
        var payloadStart: Int
        var payloadEnd: Int
    }

    struct FileJPEG {
        var markers: [FileJPEGMarker] = []
        var sof: (Int, Int)?
        var trailing = 0
        var comment: String?
        var endSeen = false
    }

    /// The marker walk: SOI, length-
    /// prefixed segments, the entropy
    /// data after SOS, and whatever
    /// rides past the final EOI —
    /// counted, never decoded.
    static func fileJPEGWalk(
        _ b: [UInt8]) -> FileJPEG? {
        guard b.count > 4, b[0] == 0xFF,
              b[1] == 0xD8 else { return nil }
        var out = FileJPEG()
        var pos = 2
        let names: [Int: String] = [
            0xC0: "SOF0", 0xC1: "SOF1",
            0xC2: "SOF2", 0xC4: "DHT",
            0xC8: "JPG", 0xCC: "DAC",
            0xD8: "SOI", 0xD9: "EOI",
            0xDA: "SOS", 0xDB: "DQT",
            0xDD: "DRI", 0xFE: "COM",
        ]
        func markerName(_ m: Int) -> String {
            if let n = names[m] { return n }
            if m >= 0xE0 && m <= 0xEF {
                return "APP\(m - 0xE0)"
            }
            if m >= 0xD0 && m <= 0xD7 {
                return "RST\(m - 0xD0)"
            }
            return String(format: "FF%02X", m)
        }
        var guardCount = 0
        while pos + 1 < b.count,
              guardCount < 512 {
            guardCount += 1
            while pos < b.count,
                  b[pos] != 0xFF {
                pos += 1
            }
            while pos + 1 < b.count,
                  b[pos + 1] == 0xFF {
                pos += 1
            }
            guard pos + 1 < b.count else {
                break
            }
            let marker = Int(b[pos + 1])
            pos += 2
            if marker == 0xD9 {
                out.markers.append(
                    FileJPEGMarker(
                        name: "EOI",
                        payloadStart: pos,
                        payloadEnd: pos))
                out.endSeen = true
                out.trailing = b.count - pos
                return out
            }
            if marker == 0x01
                || (marker >= 0xD0
                    && marker <= 0xD8) {
                out.markers.append(
                    FileJPEGMarker(
                        name: markerName(marker),
                        payloadStart: pos,
                        payloadEnd: pos))
                continue
            }
            guard let len = fileU16BE(
                    b, pos), len >= 2,
                  pos + len <= b.count + 2
            else { break }
            let segEnd = min(b.count,
                             pos + len)
            out.markers.append(
                FileJPEGMarker(
                    name: markerName(marker),
                    payloadStart: pos + 2,
                    payloadEnd: segEnd))
            if marker == 0xC0
                || marker == 0xC1
                || marker == 0xC2 {
                if let h = fileU16BE(
                    b, pos + 3),
                   let w = fileU16BE(
                    b, pos + 5) {
                    out.sof = (w, h)
                }
            }
            if marker == 0xFE {
                out.comment = String(
                    decoding: b[(pos + 2)..<segEnd],
                    as: UTF8.self)
            }
            if marker == 0xDA {
                // Entropy-coded data: the
                // scan runs to the LAST
                // EOI in the file, the way
                // the mirror counted it.
                var lastEOI: Int?
                var scan = segEnd
                while scan + 1 < b.count {
                    if b[scan] == 0xFF,
                       b[scan + 1] == 0xD9 {
                        lastEOI = scan
                    }
                    scan += 1
                }
                if let eoi = lastEOI {
                    out.endSeen = true
                    out.trailing =
                        b.count - (eoi + 2)
                }
                return out
            }
            pos += len
        }
        return out
    }

    struct FilePNGChunk {
        var name: String
        var length: Int
        var payloadStart: Int
        var payloadEnd: Int
        var end: Int
        var crcOK: Bool?
    }

    static func filePNGChunks(
        _ b: [UInt8]) -> [FilePNGChunk] {
        var out: [FilePNGChunk] = []
        var pos = 8
        while pos + 12 <= b.count,
              out.count < 512 {
            guard let len = fileU32BE(
                    b, pos) else { break }
            let name = String(
                decoding: b[(pos + 4)..<(pos + 8)],
                as: UTF8.self)
            let payloadStart = pos + 8
            let payloadEnd = payloadStart + len
            guard payloadEnd + 4 <= b.count
            else {
                out.append(FilePNGChunk(
                    name: name, length: len,
                    payloadStart: payloadStart,
                    payloadEnd: b.count,
                    end: b.count, crcOK: nil))
                break
            }
            let stored = fileU32BE(
                b, payloadEnd)
            let computed = fileCRC32(
                b[(pos + 4)..<payloadEnd])
            out.append(FilePNGChunk(
                name: name, length: len,
                payloadStart: payloadStart,
                payloadEnd: payloadEnd,
                end: payloadEnd + 4,
                crcOK: stored.map {
                    UInt32($0) == computed
                }))
            pos = payloadEnd + 4
            if name == "IEND" { break }
        }
        return out
    }

    struct FileGIF {
        var width = 0
        var height = 0
        var frames = 0
        var gce = 0
        var comments = 0
        var netscape = false
        var trailing = 0
        var endSeen = false
    }

    static func fileGIFWalk(
        _ b: [UInt8]) -> FileGIF? {
        guard b.count >= 13 else {
            return nil
        }
        var out = FileGIF()
        out.width = fileU16LE(b, 6) ?? 0
        out.height = fileU16LE(b, 8) ?? 0
        var pos = 13
        if b[10] & 0x80 != 0 {
            pos += 3 * (1 << Int(
                (b[10] & 0x07) + 1))
        }
        func skipSubBlocks(_ from: Int)
            -> Int {
            var p = from
            while p < b.count {
                let n = Int(b[p])
                p += 1
                if n == 0 { return p }
                p += n
            }
            return p
        }
        var guardCount = 0
        while pos < b.count,
              guardCount < 100000 {
            guardCount += 1
            let block = b[pos]
            if block == 0x3B {
                out.endSeen = true
                out.trailing =
                    b.count - (pos + 1)
                return out
            }
            if block == 0x2C {
                out.frames += 1
                guard pos + 10 <= b.count
                else { return out }
                let packed = b[pos + 9]
                var p = pos + 10
                if packed & 0x80 != 0 {
                    p += 3 * (1 << Int(
                        (packed & 0x07) + 1))
                }
                guard p < b.count else {
                    return out
                }
                p += 1 // LZW minimum code
                pos = skipSubBlocks(p)
                continue
            }
            if block == 0x21 {
                guard pos + 2 < b.count
                else { return out }
                let label = b[pos + 1]
                if label == 0xF9 {
                    out.gce += 1
                }
                if label == 0xFE {
                    out.comments += 1
                }
                if label == 0xFF {
                    // Application block: a
                    // fixed 11-byte name,
                    // then sub-blocks.
                    let app = String(
                        decoding: b[
                            min(b.count, pos + 3)..<min(b.count, pos + 14)],
                        as: UTF8.self)
                    if app.hasPrefix(
                        "NETSCAPE") {
                        out.netscape = true
                    }
                    pos = skipSubBlocks(
                        pos + 2 + 1
                            + Int(b[pos + 2]))
                    continue
                }
                pos = skipSubBlocks(pos + 2)
                continue
            }
            return out
        }
        return out
    }

    struct FileWebP {
        var chunks: [(String, Int)] = []
        var trailing = 0
        var canvas: (Int, Int)?
        var flags = 0
        var lossyDims: (Int, Int)?
        var losslessDims: (Int, Int)?
    }

    static func fileWebPWalk(
        _ b: [UInt8]) -> FileWebP? {
        guard b.count >= 20,
              let riffSize = fileU32LE(b, 4)
        else { return nil }
        var out = FileWebP()
        out.trailing = max(
            0, b.count - (8 + riffSize))
        var pos = 12
        while pos + 8 <= b.count,
              out.chunks.count < 256 {
            let fourcc = String(
                decoding: b[pos..<(pos + 4)],
                as: UTF8.self)
            guard let size = fileU32LE(
                    b, pos + 4) else { break }
            out.chunks.append((fourcc, size))
            let payload = pos + 8
            if fourcc == "VP8X",
               payload + 10 <= b.count {
                out.flags = Int(b[payload])
                if let w = fileU24LE(
                    b, payload + 4),
                   let h = fileU24LE(
                    b, payload + 7) {
                    out.canvas = (w + 1, h + 1)
                }
            }
            if fourcc == "VP8 ",
               payload + 10 <= b.count,
               b[payload + 3] == 0x9D,
               b[payload + 4] == 0x01,
               b[payload + 5] == 0x2A,
               let w = fileU16LE(
                b, payload + 6),
               let h = fileU16LE(
                b, payload + 8) {
                out.lossyDims = (
                    w & 0x3FFF, h & 0x3FFF)
            }
            if fourcc == "VP8L",
               payload + 5 <= b.count,
               b[payload] == 0x2F,
               let packed = fileU32LE(
                b, payload + 1) {
                out.losslessDims = (
                    (packed & 0x3FFF) + 1,
                    ((packed >> 14) & 0x3FFF) + 1)
            }
            pos = payload + size
                + (size % 2)
        }
        return out
    }

    static func fileU24LE(
        _ b: [UInt8], _ o: Int) -> Int? {
        guard o + 3 <= b.count else {
            return nil
        }
        return Int(b[o]) | Int(b[o + 1]) << 8
            | Int(b[o + 2]) << 16
    }

    static func imgdeep(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "imgdeep",
                    emit: emit) else { return }
            fileHeader("imgdeep",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            guard let kind = fileKind(b)
            else {
                icsSay(emit, L("no signature the bench knows — not an image ledger this verb keeps. filecensus takes the identity board."), .err)
                return
            }
            switch kind.family {
            case "jpeg":
                guard let j = fileJPEGWalk(b)
                else {
                    icsSay(emit, L("the marker walk fails at the door."), .err)
                    return
                }
                for marker in j.markers {
                    icsSay(emit, String(format: L("marker %@: %lld bytes"), marker.name, Int64(marker.payloadEnd - marker.payloadStart)), .out)
                }
                if let sof = j.sof {
                    icsSay(emit, String(format: L("the frame: %lld x %lld pixels, by its SOF marker"), Int64(sof.0), Int64(sof.1)), .out)
                }
                if let comment = j.comment {
                    icsSay(emit, String(format: L("comment segment: '%@'"), comment), .out)
                }
                fileTrailingReport(
                    seen: j.endSeen,
                    trailing: j.trailing,
                    marker: "FF D9",
                    emit: emit)
            case "png":
                let chunks = filePNGChunks(b)
                var crcBad: [String] = []
                for chunk in chunks {
                    let crcText: String
                    if let ok = chunk.crcOK {
                        crcText = ok
                            ? L("CRC true")
                            : L("CRC FALSE")
                        if !ok {
                            crcBad.append(
                                chunk.name)
                        }
                    } else {
                        crcText = L("CRC unread (the chunk overruns the file)")
                    }
                    icsSay(emit, String(format: L("chunk %@: %lld bytes, %@"), chunk.name, Int64(chunk.length), crcText), .out)
                }
                if !crcBad.isEmpty {
                    icsSay(emit, String(format: L("chunks whose checksums fail: %@ — edited after writing, damaged in transit, or built by a careless hand; a PNG reader will still try to draw them"), crcBad.joined(separator: ", ")), .err)
                }
                if let first = chunks.first,
                   first.name == "IHDR",
                   let w = fileU32BE(
                    b, first.payloadStart),
                   let h = fileU32BE(
                    b, first.payloadStart + 4) {
                    icsSay(emit, String(format: L("the canvas: %lld x %lld, bit depth %lld, colour type %lld"), Int64(w), Int64(h), Int64(b[first.payloadStart + 8]), Int64(b[first.payloadStart + 9])), .out)
                }
                let lastEnd = chunks.last?.end
                    ?? b.count
                fileTrailingReport(
                    seen: chunks.contains {
                        $0.name == "IEND"
                    },
                    trailing: b.count - lastEnd,
                    marker: "IEND",
                    emit: emit)
            case "gif":
                guard let g = fileGIFWalk(b)
                else {
                    icsSay(emit, L("too small to carry a GIF header."), .err)
                    return
                }
                icsSay(emit, String(format: L("canvas %lld x %lld; %lld frames counted, %lld graphic-control blocks"), Int64(g.width), Int64(g.height), Int64(g.frames), Int64(g.gce)), .out)
                if g.netscape {
                    icsSay(emit, L("a NETSCAPE loop block stands — the file asks to play forever"), .out)
                }
                if g.comments > 0 {
                    icsSay(emit, String(format: L("%lld comment extensions ride in the file"), Int64(g.comments)), .out)
                }
                fileTrailingReport(
                    seen: g.endSeen,
                    trailing: g.trailing,
                    marker: "0x3B",
                    emit: emit)
            case "webp":
                guard let w = fileWebPWalk(b)
                else {
                    icsSay(emit, L("the RIFF wrapper does not parse."), .err)
                    return
                }
                for (fourcc, size) in w.chunks {
                    icsSay(emit, String(format: L("chunk %@: %lld bytes"), fourcc, Int64(size)), .out)
                }
                if let canvas = w.canvas {
                    icsSay(emit, String(format: L("VP8X canvas: %lld x %lld, flags 0x%02llx (alpha and metadata bits are claims)"), Int64(canvas.0), Int64(canvas.1), Int64(w.flags)), .out)
                }
                if let dims = w.lossyDims {
                    icsSay(emit, String(format: L("the lossy frame claims %lld x %lld"), Int64(dims.0), Int64(dims.1)), .out)
                }
                if let dims = w.losslessDims {
                    icsSay(emit, String(format: L("the lossless frame claims %lld x %lld"), Int64(dims.0), Int64(dims.1)), .out)
                }
                if w.trailing > 0 {
                    icsSay(emit, String(format: L("%lld bytes ride past the RIFF wrapper's own claimed length"), Int64(w.trailing)), .err)
                }
            default:
                icsSay(emit, String(format: L("%@ — imgdeep keeps the JPEG, PNG, GIF and WebP ledgers; the other formats ride under filecensus and exifprobe."), kind.name), .err)
            }
        }
    }

    /// Trailing bytes, reported the
    /// same way for every image: as
    /// bytes, with the honest menu of
    /// what they could be.
    static func fileTrailingReport(
        seen: Bool, trailing: Int,
        marker: String,
        emit: @escaping BlacksiteEmit) {
        if !seen {
            icsSay(emit, String(format: L("no %@ end marker was found — the file ends mid-sentence: truncated, or never finished"), marker), .err)
            return
        }
        if trailing > 0 {
            icsSay(emit, String(format: L("%lld bytes ride past the %@ end marker. Readers stop at the marker; the bytes past it are invisible to them — a signature block, a thumbnail, an appended archive, luggage. The bench counts them; it does not open them."), Int64(trailing), marker), .err)
        } else {
            icsSay(emit, L("the file ends exactly at its end marker — nothing rides behind it"), .ok)
        }
    }

    // MARK: audiofile — the songs' papers

    static func audiofile(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "audiofile",
                    emit: emit) else { return }
            fileHeader("audiofile",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            guard let kind = fileKind(b)
            else {
                icsSay(emit, L("no signature the bench knows: no papers to read. A mawkbox song or a time-locked box carries none by design — enccensus says so, and this verb does not pretend otherwise."), .err)
                return
            }
            switch kind.family {
            case "njcf":
                icsSay(emit, L("an NJCF seal: enccensus reads its papers — the format, the salt, the wrap. Whether a song rides inside is the payload's business, and audiofile does not open seals."), .sys)
            case "wav":
                fileWAVReport(b, emit: emit)
            case "flac":
                fileFLACReport(b, emit: emit)
            case "mp3":
                fileMP3Report(b, emit: emit)
            case "ogg":
                fileOggReport(b, emit: emit)
            default:
                icsSay(emit, String(format: L("%@ — audiofile reads WAV, FLAC, MP3 and Ogg papers."), kind.name), .err)
            }
        }
    }

    static func fileWAVReport(
        _ b: [UInt8],
        emit: @escaping BlacksiteEmit) {
        var pos = 12
        var fmt: (Int, Int, Int, Int, Int)?
        var dataSize = 0
        var factFrames: Int?
        while pos + 8 <= b.count {
            let name = String(
                decoding: b[pos..<(pos + 4)],
                as: UTF8.self)
            guard let size = fileU32LE(
                    b, pos + 4) else { break }
            let payload = pos + 8
            if name == "fmt ",
               payload + 16 <= b.count {
                fmt = (fileU16LE(b, payload) ?? 0,
                       fileU16LE(b, payload + 2) ?? 0,
                       fileU32LE(b, payload + 4) ?? 0,
                       fileU32LE(b, payload + 8) ?? 0,
                       fileU16LE(b, payload + 14) ?? 0)
            }
            if name == "data" {
                dataSize = min(
                    size, b.count - payload)
            }
            if name == "fact",
               payload + 4 <= b.count {
                factFrames = fileU32LE(
                    b, payload)
            }
            if name != "fmt " && name != "data" {
                icsSay(emit, String(format: L("chunk %@: %lld bytes"), name, Int64(size)), .out)
            }
            pos = payload + size + (size % 2)
        }
        guard let fmt = fmt else {
            icsSay(emit, L("no fmt chunk: the RIFF wrapper names WAVE but the papers are missing."), .err)
            return
        }
        let formats: [Int: String] = [
            1: "PCM", 3: "IEEE float",
            6: "A-law", 7: "µ-law",
            0xFFFE: "extensible",
        ]
        icsSay(emit, String(format: L("%@, %lld channels, %lld Hz, %lld bits per sample, byte rate %lld"), formats[fmt.0] ?? String(format: L("format %lld"), Int64(fmt.0)), Int64(fmt.1), Int64(fmt.2), Int64(fmt.4), Int64(fmt.3)), .out)
        if fmt.3 > 0 {
            let seconds = Double(dataSize)
                / Double(fmt.3)
            icsSay(emit, String(format: L("the data chunk holds %lld bytes — %.2f seconds at the claimed byte rate"), Int64(dataSize), seconds), .out)
        }
        if let fact = factFrames {
            icsSay(emit, String(format: L("a fact chunk claims %lld sample frames"), Int64(fact)), .out)
        }
    }

    static func fileFLACReport(
        _ b: [UInt8],
        emit: @escaping BlacksiteEmit) {
        var pos = 4
        var streaminfo = false
        var guardCount = 0
        while pos + 4 <= b.count,
              guardCount < 128 {
            guardCount += 1
            let header = b[pos]
            let isLast = header & 0x80 != 0
            let type = Int(header & 0x7F)
            guard let len = fileU24BE(
                    b, pos + 1) else { break }
            let payload = pos + 4
            let typeNames: [Int: String] = [
                0: "STREAMINFO", 1: "PADDING",
                2: "APPLICATION", 3: "SEEKTABLE",
                4: "VORBIS_COMMENT",
                5: "CUESHEET", 6: "PICTURE",
            ]
            icsSay(emit, String(format: L("block %@: %lld bytes"), typeNames[type] ?? String(format: L("type %lld"), Int64(type)), Int64(len)), .out)
            if type == 0, len >= 34,
               payload + 34 <= b.count {
                streaminfo = true
                let packed = fileU64BE(
                    b, payload + 10) ?? 0
                let rate = Int(packed >> 44)
                let channels = Int(
                    (packed >> 41) & 0x7) + 1
                let bps = Int(
                    (packed >> 36) & 0x1F) + 1
                let total = packed
                    & 0xFFFFFFFFF
                let md5 = Array(b[
                    (payload + 18)..<(payload + 34)])
                if rate > 0 {
                    icsSay(emit, String(format: L("STREAMINFO claims: %lld Hz, %lld channels, %lld bits per sample, %lld samples — %.2f seconds"), Int64(rate), Int64(channels), Int64(bps), Int64(total), Double(total) / Double(rate)), .out)
                }
                if md5.allSatisfy({ $0 == 0 }) {
                    icsSay(emit, L("the STREAMINFO audio MD5 is all zeros — unset, by the encoder's own admission; the file's integrity rests on its frame CRCs alone"), .out)
                }
            }
            if type == 4 {
                icsSay(emit, L("a Vorbis comment block rides here — its tags are the file's claims about itself; the bench notes the block without transcribing it"), .out)
            }
            if isLast { break }
            pos = payload + len
        }
        if !streaminfo {
            icsSay(emit, L("no STREAMINFO first block — a FLAC by its magic alone, its papers missing."), .err)
        }
    }

    static func fileU24BE(
        _ b: [UInt8], _ o: Int) -> Int? {
        guard o + 3 <= b.count else {
            return nil
        }
        return Int(b[o]) << 16
            | Int(b[o + 1]) << 8
            | Int(b[o + 2])
    }

    static func fileMP3Report(
        _ b: [UInt8],
        emit: @escaping BlacksiteEmit) {
        var audioStart = 0
        if b.count >= 10, b[0] == 0x49,
           b[1] == 0x44, b[2] == 0x33 {
            let major = Int(b[3])
            let flags = Int(b[5])
            let size = (Int(b[6]) & 0x7F) << 21
                | (Int(b[7]) & 0x7F) << 14
                | (Int(b[8]) & 0x7F) << 7
                | (Int(b[9]) & 0x7F)
            var pos = 10
            if flags & 0x10 != 0 { pos += 10 }
            let tagEnd = 10 + size
            icsSay(emit, String(format: L("an ID3v2.%lld tag, %lld bytes"), Int64(major), Int64(size)), .out)
            while pos < tagEnd,
                  pos + 6 <= b.count {
                if major == 2 {
                    let id = String(
                        decoding: b[pos..<(pos + 3)],
                        as: UTF8.self)
                    if id.hasPrefix("\0") {
                        break
                    }
                    let fsize = fileU24BE(
                        b, pos + 3) ?? 0
                    if (id == "TT2"
                        || id == "TP1"
                        || id == "TAL"),
                       let text = fileID3Text(
                        b, from: pos + 6,
                        length: fsize) {
                        icsSay(emit, String(format: L("%@ = %@ (the tag's claim)"), id, text), .out)
                    }
                    if fsize == 0 { break }
                    pos += 6 + fsize
                } else {
                    guard pos + 10 <= b.count
                    else { break }
                    let id = String(
                        decoding: b[pos..<(pos + 4)],
                        as: UTF8.self)
                    if id.hasPrefix("\0") {
                        break
                    }
                    let fsize: Int
                    if major == 4 {
                        fsize = (Int(b[pos + 4]) & 0x7F) << 21
                            | (Int(b[pos + 5]) & 0x7F) << 14
                            | (Int(b[pos + 6]) & 0x7F) << 7
                            | (Int(b[pos + 7]) & 0x7F)
                    } else {
                        fsize = fileU32BE(
                            b, pos + 4) ?? 0
                    }
                    if ["TIT2", "TPE1",
                        "TALB", "TRCK",
                        "TYER", "TCON"]
                        .contains(id),
                       let text = fileID3Text(
                        b, from: pos + 10,
                        length: fsize) {
                        icsSay(emit, String(format: L("%@ = %@ (the tag's claim)"), id, text), .out)
                    }
                    if fsize == 0 { break }
                    pos += 10 + fsize
                }
            }
            audioStart = tagEnd
        }
        // The frame walk: MPEG audio
        // Layer III headers, counted to
        // a duration labelled an estimate.
        let brMPEG1 = [0, 32, 40, 48, 56,
                       64, 80, 96, 112, 128,
                       160, 192, 224, 256,
                       320, 0]
        let brMPEG2 = [0, 8, 16, 24, 32,
                       40, 48, 56, 64, 80,
                       96, 112, 128, 144,
                       160, 0]
        let srTable: [Int: [Int]] = [
            3: [44100, 48000, 32000, 0],
            2: [22050, 24000, 16000, 0],
            0: [11025, 12000, 8000, 0],
        ]
        var pos = audioStart
        var frames = 0
        var firstRate = 0
        var firstSR = 0
        var firstVersion = 3
        while pos + 4 <= b.count,
              frames < 100000 {
            let h0 = b[pos]
            let h1 = b[pos + 1]
            let h2 = b[pos + 2]
            guard h0 == 0xFF,
                  h1 & 0xE0 == 0xE0 else {
                break
            }
            let version = (Int(h1) >> 3) & 3
            let layer = (Int(h1) >> 1) & 3
            guard layer == 1,
                  version != 1,
                  let rates = srTable[version]
            else { break }
            let brIndex = (Int(h2) >> 4) & 0xF
            let srIndex = (Int(h2) >> 2) & 3
            let pad = (Int(h2) >> 1) & 1
            let br = (version == 3
                ? brMPEG1 : brMPEG2)[brIndex]
            let sr = rates[srIndex]
            guard br > 0, sr > 0 else {
                break
            }
            let frameLen = version == 3
                ? 144 * br * 1000 / sr + pad
                : 72 * br * 1000 / sr + pad
            if frames == 0 {
                firstRate = br
                firstSR = sr
                firstVersion = version
            }
            frames += 1
            pos += frameLen
        }
        if frames > 0 {
            let spf = firstVersion == 3
                ? 1152 : 576
            let seconds = Double(frames * spf)
                / Double(max(1, firstSR))
            icsSay(emit, String(format: L("%lld MPEG Layer III frames counted at %lld kbps / %lld Hz — about %.2f seconds (an estimate: the walk trusts each header's length)"), Int64(frames), Int64(firstRate), Int64(firstSR), seconds), .out)
        } else {
            icsSay(emit, L("no MPEG frames walk from where the audio should start — a tag with no song behind it, or a codec the walk does not speak."), .err)
        }
    }

    static func fileID3Text(
        _ b: [UInt8], from: Int,
        length: Int) -> String? {
        guard length >= 1,
              from + length <= b.count
        else { return nil }
        let encoding = b[from]
        let payload = Array(b[
            (from + 1)..<(from + length)])
        let text: String?
        switch encoding {
        case 0:
            text = String(bytes: payload,
                          encoding: .isoLatin1)
        case 1:
            text = String(bytes: payload,
                          encoding: .utf16)
        case 2:
            text = String(bytes: payload,
                          encoding:
                            .utf16BigEndian)
        case 3:
            text = String(bytes: payload,
                          encoding: .utf8)
        default:
            text = nil
        }
        let trimmed = text?
            .trimmingCharacters(
                in: .controlCharacters)
            .trimmingCharacters(
                in: .whitespaces)
        return (trimmed?.isEmpty == false)
            ? trimmed : nil
    }

    /// A plain substring hunt over
    /// bytes — no algorithms package,
    /// no cleverness.
    static func fileBytesContain(
        _ haystack: [UInt8],
        _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty,
              haystack.count >= needle.count
        else { return false }
        var i = 0
        while i + needle.count
                <= haystack.count {
            if haystack[i] == needle[0] {
                var match = true
                for j in 0..<needle.count
                where haystack[i + j]
                    != needle[j] {
                    match = false
                    break
                }
                if match { return true }
            }
            i += 1
        }
        return false
    }

    static func fileOggReport(
        _ b: [UInt8],
        emit: @escaping BlacksiteEmit) {
        guard b.count >= 27 else {
            icsSay(emit, L("too small for an Ogg page."), .err)
            return
        }
        let serial = fileU32LE(b, 14) ?? 0
        icsSay(emit, String(format: L("an Ogg container, stream serial %lld (its own number for itself)"), Int64(serial)), .out)
        let head = Array(b.prefix(8192))
        let claims: [([UInt8], String)] = [
            (Array("\u{01}vorbis".utf8),
             "Vorbis audio"),
            (Array("OpusHead".utf8),
             "Opus audio"),
            (Array("\u{7F}FLAC".utf8),
             "FLAC in Ogg"),
            (Array("Speex".utf8),
             "Speex speech"),
            (Array("\u{80}theora".utf8),
             "Theora video"),
        ]
        var found = false
        for (signature, label) in claims {
            if fileBytesContain(
                head, signature) {
                icsSay(emit, String(format: L("the first pages claim: %@"), label), .out)
                found = true
                break
            }
        }
        if !found {
            icsSay(emit, L("no codec signature the bench knows in the first pages — the tenant does not announce itself here."), .out)
        }
    }
}

extension BlacksiteBench {

    // MARK: sqliteprobe — the database's ledger

    struct FileSQLiteHeader {
        var pageSize = 0
        var pages = 0
        var freelist = 0
        var encoding = 1
        var userVersion = 0
        var schemaFormat = 0
        var appID = 0
    }

    static func fileSQLiteHeader(
        _ b: [UInt8]) -> FileSQLiteHeader? {
        guard b.count >= 100,
              Array(b.prefix(15)) ==
                Array("SQLite format 3".utf8),
              b[15] == 0 else { return nil }
        var h = FileSQLiteHeader()
        h.pageSize = fileU16BE(b, 16) ?? 0
        if h.pageSize == 1 {
            h.pageSize = 65536
        }
        h.pages = fileU32BE(b, 28) ?? 0
        h.freelist = fileU32BE(b, 32) ?? 0
        h.schemaFormat = fileU32BE(b, 44) ?? 0
        h.encoding = fileU32BE(b, 56) ?? 1
        h.userVersion = fileU32BE(b, 60) ?? 0
        h.appID = fileU32BE(b, 68) ?? 0
        return h
    }

    static func fileVarint(
        _ b: [UInt8], _ from: Int)
        -> (UInt64, Int)? {
        var value: UInt64 = 0
        var i = 0
        while i < 9, from + i < b.count {
            let byte = b[from + i]
            if i == 8 {
                value = value << 8
                    | UInt64(byte)
                return (value, 9)
            }
            value = value << 7
                | UInt64(byte & 0x7F)
            if byte & 0x80 == 0 {
                return (value, i + 1)
            }
            i += 1
        }
        return nil
    }

    /// One record decoded by its
    /// serial types — the mirror's
    /// reader, kept to the schema
    /// records it was verified on.
    static func fileSQLiteRecord(
        _ b: [UInt8], payloadFrom: Int)
        -> [String]? {
        guard let (headerLen, used) =
            fileVarint(b, payloadFrom)
        else { return nil }
        let headerEnd = payloadFrom
            + Int(headerLen)
        var serials: [UInt64] = []
        var cursor = payloadFrom + used
        while cursor < headerEnd {
            guard let (serial, step) =
                fileVarint(b, cursor)
            else { return nil }
            serials.append(serial)
            cursor += step
        }
        var values: [String] = []
        var body = headerEnd
        for serial in serials {
            switch serial {
            case 0:
                values.append("NULL")
            case 1, 2, 3, 4, 5, 6:
                let width = [1, 2, 3, 4, 6, 8][
                    Int(serial) - 1]
                guard body + width <= b.count
                else { return nil }
                var v: Int64 = 0
                for i in 0..<width {
                    v = v << 8
                        | Int64(b[body + i])
                }
                // sign-extend
                let shift = 64 - width * 8
                if shift > 0 {
                    v = (v << shift) >> shift
                }
                values.append(String(v))
                body += width
            case 7:
                guard body + 8 <= b.count,
                      let raw = fileU64BE(
                        b, body)
                else { return nil }
                values.append(String(
                    Double(bitPattern: raw)))
                body += 8
            case 8:
                values.append("0")
            case 9:
                values.append("1")
            default:
                if serial >= 13,
                   serial % 2 == 1 {
                    let len = Int(serial - 13) / 2
                    guard body + len <= b.count
                    else { return nil }
                    values.append(String(
                        decoding: b[body..<(body + len)],
                        as: UTF8.self))
                    body += len
                } else if serial >= 12 {
                    let len = Int(serial - 12) / 2
                    body += len
                    values.append(
                        String(format: L("<a blob of %lld bytes>"), Int64(len)))
                } else {
                    values.append("?")
                }
            }
        }
        return values
    }

    static func sqliteprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "sqliteprobe",
                    emit: emit) else { return }
            fileHeader("sqliteprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            guard let header =
                fileSQLiteHeader(b) else {
                icsSay(emit, L("the hundred-byte header is not a SQLite header — the papers are not a database's."), .err)
                return
            }
            let encodingName = [
                1: "UTF-8", 2: "UTF-16le",
                3: "UTF-16be",
            ][header.encoding]
                ?? String(format: L("encoding %lld"), Int64(header.encoding))
            icsSay(emit, String(format: L("pages of %lld bytes; the header claims %lld pages in the file and %lld trunk pages on the freelist"), Int64(header.pageSize), Int64(header.pages), Int64(header.freelist)), .out)
            let claimedSize = header.pages *
                header.pageSize
            if claimedSize != b.count {
                icsSay(emit, String(format: L("the header's arithmetic claims %lld bytes; the file holds %lld — appended to, truncated, or caught mid-write"), Int64(claimedSize), Int64(b.count)), .err)
            }
            icsSay(emit, String(format: L("text encoding %@, schema format %lld, user version %lld, application id %lld — all as the header claims"), encodingName, Int64(header.schemaFormat), Int64(header.userVersion), Int64(header.appID)), .out)
            if header.freelist > 0 {
                icsSay(emit, String(format: L("%lld freelist pages: room the file once used and now holds empty — deleted rows retire there until a vacuum. The bench counts the pages; it never reads the retired rows out of them."), Int64(header.freelist)), .err)
            }
            // The page-1 schema walk:
            // b-tree pages from the root,
            // records decoded as schema
            // rows — types and names are
            // the database's own papers.
            let pageSize = header.pageSize
            guard pageSize > 0 else { return }
            var visited = Set<Int>()
            var objects: [(String, String, Int)] = []
            var freeblocks = 0
            func walk(page: Int, depth: Int) {
                guard depth < 4,
                      page >= 1,
                      !visited.contains(page),
                      visited.count < 64
                else { return }
                visited.insert(page)
                let pageOff = (page - 1) *
                    pageSize
                guard pageOff < b.count
                else { return }
                let hoff = page == 1
                    ? 100 : 0
                let hbase = pageOff + hoff
                guard hbase + 8 <= b.count
                else { return }
                let pageType = b[hbase]
                let cells = fileU16BE(
                    b, hbase + 3) ?? 0
                if pageType == 0x0D {
                    // freeblocks in this leaf
                    var fb = fileU16BE(
                        b, hbase + 1) ?? 0
                    var chainGuard = 0
                    while fb != 0,
                          chainGuard < 4096 {
                        chainGuard += 1
                        freeblocks += 1
                        let at = pageOff + fb
                        guard at + 2 <= b.count,
                              let next = fileU16BE(
                                b, at)
                        else { break }
                        fb = next
                    }
                    let ptrArray = hbase + 8
                    for i in 0..<min(cells, 4096) {
                        guard let cellOff =
                            fileU16BE(
                                b, ptrArray
                                    + i * 2)
                        else { break }
                        let cellAt = pageOff
                            + cellOff
                        guard let (_, step1) =
                            fileVarint(b, cellAt),
                              let (_, step2) =
                                fileVarint(
                                    b, cellAt + step1)
                        else { continue }
                        if let values =
                            fileSQLiteRecord(
                                b, payloadFrom:
                                    cellAt + step1
                                    + step2),
                           values.count >= 3,
                           objects.count < 200 {
                            objects.append((
                                values[0],
                                values[1],
                                values.count > 3
                                    ? (Int(
                                        values[3])
                                        ?? 0)
                                    : 0))
                        }
                    }
                } else if pageType == 0x05 {
                    let ptrArray = hbase + 12
                    for i in 0..<min(cells, 4096) {
                        guard let cellOff =
                            fileU16LEBE(
                                b, ptrArray
                                    + i * 2)
                        else { break }
                        let cellAt = pageOff
                            + cellOff
                        if let child = fileU32BE(
                            b, cellAt) {
                            walk(page: child,
                                 depth: depth + 1)
                        }
                    }
                    if let right = fileU32BE(
                        b, hbase + 8) {
                        walk(page: right,
                             depth: depth + 1)
                    }
                }
            }
            walk(page: 1, depth: 0)
            if objects.isEmpty {
                icsSay(emit, L("the schema walk found no objects — an empty database, or a first page this reader cannot follow."), .out)
            } else {
                for (type, name, root) in objects {
                    if root > 0 {
                        icsSay(emit, String(format: L("%@ %@ (root page %lld)"), type, name, Int64(root)), .out)
                    } else {
                        icsSay(emit, String(format: L("%@ %@"), type, name), .out)
                    }
                }
            }
            if freeblocks > 0 {
                icsSay(emit, String(format: L("%lld freeblocks sit inside the pages the schema walk visited — deleted records' shells, counted not read"), Int64(freeblocks)), .out)
            }
            icsSay(emit, L("the bench reads the schema and the ledger. It does not run queries, and it does not dump rows."), .sys)
        }
    }

    /// Cell pointers in a page are
    /// big-endian whatever the file's
    /// text encoding; this name keeps
    /// the walk sites honest about it.
    static func fileU16LEBE(
        _ b: [UInt8], _ o: Int) -> Int? {
        fileU16BE(b, o)
    }

    // MARK: plistprobe — property lists and profiles

    static func plistprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "plistprobe",
                    emit: emit) else { return }
            fileHeader("plistprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            var payload = b
            var wrapped = false
            if let start = fileFindSub(
                b, Array("<?xml".utf8)),
               let end = fileFindSub(
                b, Array("</plist>".utf8)),
               !(start == 0
                && end + 8 == b.count) {
                payload = Array(b[start..<(end + 8)])
                wrapped = true
                icsSay(emit, L("a plist wrapped in other bytes — the CMS signature around a provisioning profile, most likely. The bench reads the sheet inside; the wrapper is not verified here."), .out)
            }
            _ = wrapped
            var format =
                PropertyListSerialization
                    .PropertyListFormat.xml
            guard let object = try?
                PropertyListSerialization
                .propertyList(
                    from: Data(payload),
                    options: [],
                    format: &format)
            else {
                icsSay(emit, L("PropertyListSerialization refuses it: not a plist in any of its three dresses (XML, binary, OpenStep)."), .err)
                return
            }
            let formatName: String
            switch format {
            case .binary:
                formatName = L("binary (bplist00)")
            case .xml:
                formatName = L("XML")
            case .openStep:
                formatName = L("OpenStep")
            @unknown default:
                formatName = L("an unnamed format")
            }
            icsSay(emit, String(format: L("format: %@"), formatName), .out)
            filePlistDescribe(
                object, path: path,
                emit: emit)
        }
    }

    static func fileFindSub(
        _ b: [UInt8], _ needle: [UInt8])
        -> Int? {
        guard !needle.isEmpty,
              b.count >= needle.count
        else { return nil }
        var i = 0
        while i + needle.count <= b.count {
            if b[i] == needle[0] {
                var match = true
                for j in 0..<needle.count
                where b[i + j] != needle[j] {
                    match = false
                    break
                }
                if match { return i }
            }
            i += 1
        }
        return nil
    }

    static func filePlistDescribe(
        _ object: Any, path: String,
        emit: @escaping BlacksiteEmit) {
        guard let dict = object
            as? NSDictionary else {
            icsSay(emit, String(format: L("the top of the sheet is %@, not a dictionary"), filePlistTypeName(object)), .out)
            if let array = object as? NSArray {
                icsSay(emit, String(format: L("an array of %lld entries"), Int64(array.count)), .out)
            }
            return
        }
        icsSay(emit, String(format: L("a dictionary of %lld keys"), Int64(dict.count)), .out)
        // Entitlements: the whole sheet,
        // or the sheet under its
        // Entitlements key, read in full
        // — entitlements are powers a
        // file ASKS for, printed as asks.
        var entitlements: NSDictionary?
        if dict["application-identifier"]
            != nil
            || dict["get-task-allow"]
            != nil
            || dict[
                "keychain-access-groups"]
            != nil {
            entitlements = dict
        } else if let nested = dict[
            "Entitlements"] as? NSDictionary {
            entitlements = nested
        }
        let keys = (dict.allKeys
            as? [String] ?? [])
            .sorted()
        for key in keys.prefix(100) {
            guard let value = dict[key]
            else { continue }
            icsSay(emit, String(format: L("%@: %@"), key, filePlistValueLine(value)), .out)
        }
        if keys.count > 100 {
            icsSay(emit, String(format: L("... and %lld more keys past the ledger cap"), Int64(keys.count - 100)), .out)
        }
        if let name = dict["Name"]
            as? String {
            icsSay(emit, String(format: L("profile name: %@ (its claim)"), name), .out)
        }
        if let teams = dict[
            "TeamIdentifier"] as? NSArray {
            let list = teams.compactMap {
                $0 as? String
            }
            if !list.isEmpty {
                icsSay(emit, String(format: L("team identifiers: %@"), list.joined(separator: ", ")), .out)
            }
        }
        if let expiry = dict[
            "ExpirationDate"] as? Date {
            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: "en_US_POSIX")
            formatter.timeZone =
                TimeZone(secondsFromGMT: 0)
            formatter.dateFormat =
                "yyyy-MM-dd"
            icsSay(emit, String(format: L("expires %@ (the sheet's claim)"), formatter.string(from: expiry)), .out)
        }
        if let ents = entitlements {
            icsSay(emit, L("entitlements — powers this sheet ASKS for, every one a claim:"), .out)
            let ekeys = (ents.allKeys
                as? [String] ?? []).sorted()
            for key in ekeys {
                guard let value = ents[key]
                else { continue }
                icsSay(emit, String(format: L("  %@: %@"), key, filePlistValueLine(value)), .out)
            }
            if let gta = ents[
                "get-task-allow"]
                as? NSNumber,
               CFGetTypeID(gta as CFTypeRef)
                == CFBooleanGetTypeID(),
               gta.boolValue {
                icsSay(emit, L("get-task-allow stands TRUE: this sheet asks for a debugger's welcome — development profiles wear it; release profiles should not."), .err)
            }
            if let groups = ents[
                "keychain-access-groups"]
                as? NSArray {
                icsSay(emit, String(format: L("it asks for %lld keychain access groups"), Int64(groups.count)), .out)
            }
        }
    }

    static func filePlistTypeName(
        _ value: Any) -> String {
        switch value {
        case is String:
            return L("a string")
        case is NSNumber:
            if CFGetTypeID(value as CFTypeRef)
                == CFBooleanGetTypeID() {
                return L("a boolean")
            }
            return L("a number")
        case is Date:
            return L("a date")
        case is Data:
            return L("data")
        case is NSArray:
            return L("an array")
        case is NSDictionary:
            return L("a dictionary")
        default:
            return L("an unnamed kind")
        }
    }

    static func filePlistValueLine(
        _ value: Any) -> String {
        switch value {
        case let s as String:
            let shown = s.count > 80
                ? String(s.prefix(80)) + "..."
                : s
            return String(format: L("the string '%@'"), shown)
        case let n as NSNumber:
            if CFGetTypeID(n as CFTypeRef)
                == CFBooleanGetTypeID() {
                return n.boolValue
                    ? L("true")
                    : L("false")
            }
            return String(format: L("the number %@"), n.stringValue)
        case let d as Date:
            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: "en_US_POSIX")
            formatter.timeZone =
                TimeZone(secondsFromGMT: 0)
            formatter.dateFormat =
                "yyyy-MM-dd HH:mm:ss"
            return String(format: L("the date %@"), formatter.string(from: d))
        case let data as Data:
            return String(format: L("%lld bytes of data"), Int64(data.count))
        case let array as NSArray:
            let types = array.prefix(8)
                .map {
                    filePlistTypeName($0)
                }
            let typeText = types.isEmpty
                ? ""
                : " (" + types.joined(
                    separator: ", ") + ")"
            return String(format: L("an array of %lld%@"), Int64(array.count), typeText)
        case let dict as NSDictionary:
            return String(format: L("a dictionary of %lld keys"), Int64(dict.count))
        default:
            return filePlistTypeName(value)
        }
    }

    // MARK: scriptprobe — a script, read and never run

    static func scriptprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "scriptprobe",
                    emit: emit) else { return }
            fileHeader("scriptprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            if !fileLooksText(b) {
                icsSay(emit, L("this does not read as text — scriptprobe reads scripts. filecensus takes the identity board; stringsdeep takes its words."), .err)
                return
            }
            let text = String(
                decoding: b, as: UTF8.self)
            let lines = text.split(
                separator: "\n",
                omittingEmptySubsequences: false)
            let firstLine = lines.first
                .map(String.init) ?? ""
            if firstLine.hasPrefix("#!") {
                icsSay(emit, String(format: L("the shebang claims: %@"), firstLine), .out)
            }
            // Shape scoring, the mirror's
            // marker table: counts of each
            // dialect's fingerprints.
            let markers: [(String, [String])] = [
                ("Python", ["def ", "import ", "print(", "elif ", "__name__"]),
                ("shell", ["#!/bin/sh", "#!/bin/bash", "fi\n", "$(", "echo "]),
                ("JavaScript", ["function ", "const ", "=>", "require(", "console.log"]),
                ("Ruby", ["require ", "puts "]),
                ("Perl", ["use strict", "my $", "sub "]),
                ("PHP", ["<?php", "$this->", "echo $"]),
                ("PowerShell", ["param(", "Write-Host", "$env:"]),
                ("Go", ["package main", "func main", "fmt."]),
                ("Rust", ["fn main", "let mut", "println!"]),
                ("Swift", ["import Foundation", "func ", "let "]),
                ("Lua", ["local function", "print("]),
            ]
            var scored: [(String, Int)] = []
            for (lang, marks) in markers {
                let score = marks.reduce(0) {
                    $0 + text.components(
                        separatedBy: $1).count - 1
                }
                if score > 0 {
                    scored.append((lang, score))
                }
            }
            scored.sort { $0.1 > $1.1 }
            let extLang: [String: String] = [
                "py": "Python", "sh": "shell",
                "bash": "shell", "zsh": "shell",
                "js": "JavaScript",
                "rb": "Ruby", "pl": "Perl",
                "php": "PHP", "ps1": "PowerShell",
                "lua": "Lua", "swift": "Swift",
                "go": "Go", "rs": "Rust",
            ]
            if let ext = fileExtension(path),
               let claimed = extLang[ext] {
                icsSay(emit, String(format: L("its name claims %@ ('.%@')"), claimed, ext), .out)
            }
            if let top = scored.first {
                let rest = scored.dropFirst()
                    .map {
                        String(format: "%@ %lld", $0.0, Int64($0.1))
                    }
                let restText = rest.isEmpty
                    ? ""
                    : " (" + L("then ")
                        + rest.joined(
                            separator: ", ")
                        + ")"
                icsSay(emit, String(format: L("by shape: %@ leads with %lld marker hits%@ — a shape, not a proof; short files wear other languages' fingerprints by accident"), top.0, Int64(top.1), restText), .out)
            } else {
                icsSay(emit, L("no dialect's markers score — prose, data, or a language outside the table."), .out)
            }
            let longestLine = lines.map(
                \.count).max() ?? 0
            icsSay(emit, String(format: L("%lld lines; the longest runs %lld characters"), Int64(lines.count), Int64(longestLine)), .out)
            let census = fileStrings(
                b, cap: 1024 * 1024)
            if !census.urls.isEmpty {
                icsSay(emit, String(format: L("URL-shaped strings: %@"), census.urls.prefix(8).joined(separator: ", ")), .out)
            }
            if !census.domains.isEmpty {
                icsSay(emit, String(format: L("domain-shaped strings: %@"), census.domains.prefix(8).joined(separator: ", ")), .out)
            }
            // Base64-shaped runs: blocks
            // that COULD carry a payload,
            // counted as a shape.
            var b64runs = 0
            var b64longest = 0
            var run = 0
            for byte in b.prefix(1024 * 1024) {
                let isB64 = (byte >= 65
                    && byte <= 90)
                    || (byte >= 97
                        && byte <= 122)
                    || (byte >= 48
                        && byte <= 57)
                    || byte == 43 || byte == 47
                    || byte == 61 || byte == 95
                    || byte == 45
                if isB64 {
                    run += 1
                } else {
                    if run >= 40 {
                        b64runs += 1
                        b64longest = max(
                            b64longest, run)
                    }
                    run = 0
                }
            }
            if run >= 40 {
                b64runs += 1
                b64longest = max(b64longest, run)
            }
            if b64runs > 0 {
                icsSay(emit, String(format: L("%lld base64-shaped runs of forty or more characters (the longest %lld) — a shape consistent with an embedded payload, and equally with embedded anything else"), Int64(b64runs), Int64(b64longest)), .out)
            }
            let calls = ["eval", "exec(",
                         "system(", "popen",
                         "subprocess", "curl ",
                         "wget ",
                         "Invoke-Expression",
                         "os.system",
                         "child_process"]
            var callLines: [String] = []
            for call in calls {
                let n = text.components(
                    separatedBy: call).count - 1
                if n > 0 {
                    callLines.append(
                        String(format: "%@ x%lld", call, Int64(n)))
                }
            }
            if !callLines.isEmpty {
                icsSay(emit, String(format: L("call names that reach outside the script, counted as strings: %@"), callLines.joined(separator: ", ")), .out)
            }
            icsSay(emit, L("the bench has read this script the way it reads everything: as text. It has not run, and it will not be run."), .sys)
        }
    }

    // MARK: logprobe — a log read as a log

    static func fileISOStamp(
        _ line: Substring) -> String? {
        let chars = Array(line.prefix(19))
        guard chars.count >= 19 else {
            return nil
        }
        func digit(_ i: Int) -> Bool {
            chars[i] >= "0" && chars[i] <= "9"
        }
        guard digit(0), digit(1), digit(2),
              digit(3), chars[4] == "-",
              digit(5), digit(6),
              chars[7] == "-", digit(8),
              digit(9),
              chars[10] == "T"
                || chars[10] == " ",
              digit(11), digit(12),
              chars[13] == ":", digit(14),
              digit(15), chars[16] == ":",
              digit(17), digit(18)
        else { return nil }
        return String(line.prefix(19))
    }

    static func fileApacheStamp(
        _ line: Substring) -> String? {
        guard let open = line.firstIndex(
            of: "["),
              let close = line[open...]
                .firstIndex(of: "]")
        else { return nil }
        let inner = line[
            line.index(after: open)..<close]
        if inner.count >= 20,
           inner.contains("/") {
            return String(inner)
        }
        return nil
    }

    static func fileSyslogStamp(
        _ line: Substring) -> String? {
        let months = ["Jan ", "Feb ",
                      "Mar ", "Apr ",
                      "May ", "Jun ",
                      "Jul ", "Aug ",
                      "Sep ", "Oct ",
                      "Nov ", "Dec "]
        for month in months
        where line.hasPrefix(month) {
            let rest = line.dropFirst(4)
            if rest.count >= 11 {
                return String(line.prefix(15))
            }
        }
        return nil
    }

    static func logprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "logprobe",
                    emit: emit) else { return }
            fileHeader("logprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            if b.contains(0) {
                icsSay(emit, L("a NUL byte rides in this file — not a clean text log. The bench reads on, but the claim is noted."), .err)
            }
            let text = String(
                decoding: b, as: UTF8.self)
            let allLines = text.split(
                separator: "\n",
                omittingEmptySubsequences: true)
            let lines = Array(allLines)
            icsSay(emit, String(format: L("%lld non-empty lines"), Int64(lines.count)), .out)
            // Format guess over the first
            // fifty lines.
            var iso = 0, apache = 0
            var syslog = 0, jsonLines = 0
            for line in lines.prefix(50) {
                if fileISOStamp(line) != nil {
                    iso += 1
                }
                if fileApacheStamp(line)
                    != nil {
                    apache += 1
                }
                if fileSyslogStamp(line)
                    != nil {
                    syslog += 1
                }
                if line.hasPrefix("{"),
                   (try? JSONSerialization
                    .jsonObject(
                        with: Data(line.utf8)))
                    != nil {
                    jsonLines += 1
                }
            }
            let guess: String
            let scores = [(iso, "ISO-led"),
                          (apache, "Apache combined"),
                          (jsonLines, "JSON lines"),
                          (syslog, "syslog")]
            let best = scores.max {
                $0.0 < $1.0
            }
            if let best = best, best.0 >= 3 {
                guess = best.1
            } else {
                guess = L("no known shape")
            }
            icsSay(emit, String(format: L("shape guess: %@ (from the first %lld lines — a guess, graded on shape alone)"), guess, Int64(min(50, lines.count))), .out)
            // Span, levels, statuses,
            // tallies over a stated basis.
            let basis = Array(
                lines.prefix(20000))
            var firstStamp: String?
            var lastStamp: String?
            var levels: [String: Int] = [:]
            var statuses: [String: Int] = [:]
            var tallies: [String: Int] = [
                "ERROR": 0, "FATAL": 0,
                "CRITICAL": 0, "WARN": 0,
            ]
            for line in basis {
                var stamp = fileISOStamp(line)
                    ?? fileApacheStamp(line)
                    ?? fileSyslogStamp(line)
                if stamp == nil,
                   line.hasPrefix("{"),
                   let object = try?
                    JSONSerialization
                        .jsonObject(
                            with: Data(
                                line.utf8))
                    as? [String: Any] {
                    for key in ["ts", "time",
                                "timestamp",
                                "@timestamp"] {
                        if let value = object[key]
                            as? String {
                            stamp = value
                            break
                        }
                    }
                    for key in ["level",
                                "severity",
                                "lvl"] {
                        if let value = object[key]
                            as? String {
                            levels[value,
                                   default: 0] += 1
                            break
                        }
                    }
                }
                if let stamp = stamp {
                    if firstStamp == nil {
                        firstStamp = stamp
                    }
                    lastStamp = stamp
                }
                if let q = line.range(
                    of: "\" ") {
                    let after = line[
                        q.upperBound...]
                    let digits = after.prefix(3)
                    if digits.count == 3,
                       digits.allSatisfy({
                           $0.isNumber
                       }),
                       after.dropFirst(3)
                        .hasPrefix(" ") {
                        let klass = String(
                            digits.prefix(1))
                            + "xx"
                        statuses[klass,
                                 default: 0] += 1
                    }
                }
                for word in tallies.keys
                where line.contains(word) {
                    tallies[word, default: 0] += 1
                }
            }
            if let first = firstStamp,
               let last = lastStamp {
                icsSay(emit, String(format: L("the lines claim a span: %@ to %@ (syslog lines carry no year — read as claimed)"), first, last), .out)
            }
            let tallyText = ["ERROR", "FATAL",
                             "CRITICAL", "WARN"]
                .map {
                    String(format: "%@ %lld", $0, Int64(tallies[$0] ?? 0))
                }.joined(separator: ", ")
            icsSay(emit, String(format: L("word tallies across %lld lines: %@"), Int64(basis.count), tallyText), .out)
            if !statuses.isEmpty {
                let parts = statuses.keys
                    .sorted().map {
                        String(format: "%@ %lld", $0, Int64(statuses[$0] ?? 0))
                    }
                icsSay(emit, String(format: L("HTTP status classes: %@"), parts.joined(separator: ", ")), .out)
            }
            if !levels.isEmpty {
                let parts = levels
                    .sorted { $0.value > $1.value }
                    .prefix(8).map {
                        String(format: "%@ %lld", $0.key, Int64($0.value))
                    }
                icsSay(emit, String(format: L("JSON level fields: %@"), parts.joined(separator: ", ")), .out)
            }
            icsSay(emit, L("a log is testimony: every line is what some program said happened. The bench grades the shape; the truth of the lines is the writer's."), .sys)
        }
    }

    // MARK: dataprobe — shape of data

    static func dataprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "dataprobe",
                    emit: emit) else { return }
            fileHeader("dataprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            if let object = try?
                JSONSerialization.jsonObject(
                    with: Data(b)) {
                fileJSONReport(
                    object, emit: emit)
                return
            }
            if !fileLooksText(b) {
                icsSay(emit, L("not JSON, and not text by shape — dataprobe reads JSON and delimited text. filecensus takes the identity board."), .err)
                return
            }
            let text = String(
                decoding: b, as: UTF8.self)
            fileCSVReport(text, emit: emit)
        }
    }

    static func fileJSONTypeName(
        _ value: Any) -> String {
        switch value {
        case is NSNull:
            return "null"
        case let n as NSNumber:
            if CFGetTypeID(n as CFTypeRef)
                == CFBooleanGetTypeID() {
                return "bool"
            }
            return "number"
        case is String:
            return "string"
        case is [Any]:
            return "array"
        case is [String: Any]:
            return "object"
        case is NSArray:
            return "array"
        case is NSDictionary:
            return "object"
        default:
            return "other"
        }
    }

    static func fileJSONDepth(
        _ value: Any, depth: Int) -> Int {
        if depth >= 6 { return depth }
        if let array = value as? [Any] {
            return array.map {
                fileJSONDepth($0,
                              depth: depth + 1)
            }.max() ?? depth + 1
        }
        if let dict = value
            as? [String: Any] {
            return dict.values.map {
                fileJSONDepth($0,
                              depth: depth + 1)
            }.max() ?? depth + 1
        }
        if let array = value as? NSArray {
            return array.map {
                fileJSONDepth($0,
                              depth: depth + 1)
            }.max() ?? depth + 1
        }
        if let dict = value as? NSDictionary {
            return dict.allValues.map {
                fileJSONDepth($0,
                              depth: depth + 1)
            }.max() ?? depth + 1
        }
        return depth + 1
    }

    /// JSONSerialization hands back
    /// Foundation collections; these
    /// two conversions accept either
    /// dress (bridged Swift or NS).
    static func fileJSONDict(
        _ value: Any) -> [String: Any]? {
        if let dict = value
            as? [String: Any] {
            return dict
        }
        if let nd = value as? NSDictionary {
            var out: [String: Any] = [:]
            for key in nd.allKeys {
                if let name = key as? String,
                   let item = nd[key] {
                    out[name] = item
                }
            }
            return out
        }
        return nil
    }

    static func fileJSONArray(
        _ value: Any) -> [Any]? {
        if let array = value as? [Any] {
            return array
        }
        if let na = value as? NSArray {
            return na.compactMap { $0 }
        }
        return nil
    }

    static func fileJSONReport(
        _ object: Any,
        emit: @escaping BlacksiteEmit) {
        icsSay(emit, String(format: L("it parses as JSON; nesting reaches %lld levels (the census stops at six)"), Int64(fileJSONDepth(object, depth: 0))), .out)
        if let dict = fileJSONDict(object) {
            icsSay(emit, String(format: L("a top-level object of %lld keys — the census names keys and kinds, not values"), Int64(dict.count)), .out)
            for key in dict.keys.sorted()
                .prefix(100) {
                if let value = dict[key] {
                    var line = fileJSONTypeName(
                        value)
                    if let a = fileJSONArray(
                        value) {
                        line = String(format: L("an array of %lld"), Int64(a.count))
                    }
                    if let d = fileJSONDict(
                        value) {
                        line = String(format: L("an object of %lld keys"), Int64(d.count))
                    }
                    icsSay(emit, String(format: L("%@: %@"), key, line), .out)
                }
            }
            return
        }
        if let array = fileJSONArray(object) {
            icsSay(emit, String(format: L("a top-level array of %lld entries"), Int64(array.count)), .out)
            // Array-of-objects census:
            // per key, the kinds it takes.
            var keyKinds: [String: (Set<String>, Int, Int)] = [:]
            var rows = 0
            for element in array.prefix(1000) {
                guard let row = fileJSONDict(
                    element) else { continue }
                rows += 1
                for (key, value) in row {
                    var entry = keyKinds[key]
                        ?? (Set<String>(), 0, 0)
                    let kind = fileJSONTypeName(
                        value)
                    entry.0.insert(kind)
                    entry.2 += 1
                    if kind == "null" {
                        entry.1 += 1
                    }
                    keyKinds[key] = entry
                }
            }
            if rows > 0 {
                icsSay(emit, String(format: L("%lld of the first entries are objects; their keys, by kind:"), Int64(rows)), .out)
                for key in keyKinds.keys
                    .sorted().prefix(100) {
                    let entry = keyKinds[key]!
                    let kinds = entry.0
                        .sorted().joined(
                            separator: "/")
                    var line = String(format: L("%@: %@ in %lld rows"), key, kinds, Int64(entry.2))
                    if entry.1 > 0 {
                        line += String(format: L(", %lld of them null"), Int64(entry.1))
                    }
                    icsSay(emit, line, .out)
                }
            }
            return
        }
        icsSay(emit, String(format: L("a top-level %@"), fileJSONTypeName(object)), .out)
    }

    /// A small quote-aware delimited
    /// reader — enough for a census,
    /// honest about its cap.
    static func fileCSVParse(
        _ text: String, delimiter: Character,
        recordCap: Int) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        var i = 0
        func endField() {
            record.append(field)
            field = ""
        }
        func endRecord() {
            endField()
            records.append(record)
            record = []
        }
        while i < chars.count,
              records.count < recordCap {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count,
                       chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.append(ch)
                i += 1
                continue
            }
            if ch == "\"",
               field.isEmpty {
                inQuotes = true
                i += 1
                continue
            }
            if ch == delimiter {
                endField()
                i += 1
                continue
            }
            if ch == "\n" || ch == "\r" {
                if ch == "\r",
                   i + 1 < chars.count,
                   chars[i + 1] == "\n" {
                    i += 1
                }
                endRecord()
                i += 1
                continue
            }
            field.append(ch)
            i += 1
        }
        if !field.isEmpty || !record.isEmpty {
            endRecord()
        }
        return records
    }

    static func fileCSVKind(
        _ value: String) -> String {
        let v = value.trimmingCharacters(
            in: .whitespaces)
        if v.isEmpty { return "empty" }
        if Int(v) != nil { return "int" }
        if Double(v) != nil { return "float" }
        if v.count >= 10 {
            let head = Array(v.prefix(10))
            if head[4] == "-"
                && head[7] == "-"
                && head[0].isNumber
                && head[5].isNumber {
                return "date"
            }
        }
        if v == "true" || v == "false"
            || v == "True" || v == "False" {
            return "bool"
        }
        return "string"
    }

    static func fileCSVReport(
        _ text: String,
        emit: @escaping BlacksiteEmit) {
        let firstLine = text
            .split(separator: "\n",
                   omittingEmptySubsequences: false)
            .first.map(String.init) ?? ""
        let candidates: [Character] = [
            ",", "\t", ";", "|",
        ]
        var delimiter: Character = ","
        var bestCount = -1
        for candidate in candidates {
            let n = firstLine.filter {
                $0 == candidate
            }.count
            if n > bestCount {
                bestCount = n
                delimiter = candidate
            }
        }
        if bestCount == 0 {
            icsSay(emit, L("not JSON, and its first line names no delimiter the census sniffs (comma, tab, semicolon, pipe) — one column of text, most likely. logprobe and scriptprobe read single columns."), .err)
            return
        }
        let records = fileCSVParse(
            text, delimiter: delimiter,
            recordCap: 100000)
        guard records.count >= 1 else {
            icsSay(emit, L("the delimited reader finds no records."), .err)
            return
        }
        let header = records[0]
        let rows = Array(records.dropFirst())
        let delimName = delimiter == "\t"
            ? L("tab")
            : String(delimiter)
        icsSay(emit, String(format: L("delimiter: %@ (sniffed from the first line); %lld columns, %lld records under the 100000-record cap"), delimName, Int64(header.count), Int64(rows.count)), .out)
        icsSay(emit, String(format: L("columns: %@"), header.prefix(64).joined(separator: ", ")), .out)
        let sample = Array(rows.prefix(2000))
        for (index, name) in header
            .prefix(64).enumerated() {
            var kinds: [String: Int] = [:]
            var empties = 0
            for row in sample {
                let value = index < row.count
                    ? row[index] : ""
                let kind = fileCSVKind(value)
                if kind == "empty" {
                    empties += 1
                } else {
                    kinds[kind, default: 0] += 1
                }
            }
            let guess = kinds.max {
                $0.value < $1.value
            }?.key ?? "empty"
            icsSay(emit, String(format: L("%@: reads as %@ (inferred from %lld rows), %lld empty"), name, guess, Int64(sample.count), Int64(empties)), .out)
        }
        icsSay(emit, L("column kinds are inference from shape, not a schema — the file claims no types; the bench guesses and labels the guess."), .sys)
    }
}

extension BlacksiteBench {

    // MARK: fontprobe — a font's papers

    struct FileSFNTTable {
        var tag: String
        var offset: Int
        var length: Int
        var compLength: Int?
    }

    static func fontprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "fontprobe",
                    emit: emit) else { return }
            fileHeader("fontprobe",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            guard b.count >= 12 else {
                icsSay(emit, L("too small to carry a font's papers."), .err)
                return
            }
            let flavor = String(
                decoding: b.prefix(4),
                as: UTF8.self)
            if flavor == "ttcf" {
                let count = fileU32BE(b, 8)
                    ?? 0
                icsSay(emit, String(format: L("a TrueType collection: %lld fonts under one cover (the directory's claim)"), Int64(count)), .out)
                if let first = fileU32BE(
                    b, 12) {
                    fileSFNTReport(
                        b, base: first,
                        emit: emit)
                }
                return
            }
            if flavor == "wOFF" {
                fileWOFFReport(b, emit: emit)
                return
            }
            if flavor == "wOF2" {
                fileWOFF2Report(b, emit: emit)
                return
            }
            if flavor == "OTTO"
                || Array(b.prefix(4))
                    == [0x00, 0x01, 0x00, 0x00]
                || flavor == "true" {
                icsSay(emit, String(format: L("%@ outlines"), flavor == "OTTO" ? "OpenType/CFF" : "TrueType"), .out)
                fileSFNTReport(
                    b, base: 0, emit: emit)
                return
            }
            icsSay(emit, L("the flavour word is none the bench knows — not an sfnt, a collection, or a WOFF wrapper. The papers stop here."), .err)
        }
    }

    /// The sfnt directory at a base:
    /// the table ledger, the name
    /// table's claims, head and maxp.
    static func fileSFNTReport(
        _ b: [UInt8], base: Int,
        emit: @escaping BlacksiteEmit) {
        guard let numTables = fileU16BE(
                b, base + 4) else { return }
        var tables: [FileSFNTTable] = []
        for i in 0..<min(numTables, 64) {
            let rec = base + 12 + i * 16
            guard rec + 16 <= b.count,
                  let off = fileU32BE(
                    b, rec + 8),
                  let len = fileU32BE(
                    b, rec + 12)
            else { break }
            let tag = String(
                decoding: b[rec..<(rec + 4)],
                as: UTF8.self)
            tables.append(FileSFNTTable(
                tag: tag, offset: off,
                length: len, compLength: nil))
        }
        icsSay(emit, String(format: L("%lld tables in the directory: %@"), Int64(tables.count), tables.map(\.tag).joined(separator: ", ")), .out)
        for table in tables {
            if table.tag == "head",
               let upm = fileU16BE(
                b, base + table.offset + 18) {
                icsSay(emit, String(format: L("head claims %lld units per em"), Int64(upm)), .out)
            }
            if table.tag == "maxp",
               let glyphs = fileU16BE(
                b, base + table.offset + 4) {
                icsSay(emit, String(format: L("maxp claims %lld glyphs"), Int64(glyphs)), .out)
            }
            if table.tag == "name" {
                fileFontNames(
                    b, tableAt: base
                        + table.offset,
                    emit: emit)
            }
        }
    }

    /// The name table: identity papers
    /// a font writes about itself, in
    /// whichever platform's dress it
    /// kept them — claims, printed as
    /// claims.
    static func fileFontNames(
        _ b: [UInt8], tableAt: Int,
        emit: @escaping BlacksiteEmit) {
        guard let count = fileU16BE(
                b, tableAt + 2),
              let storage = fileU16BE(
                b, tableAt + 4)
        else { return }
        let labels: [Int: String] = [
            1: "family", 2: "subfamily",
            4: "full name", 6: "PostScript name",
            16: "preferred family",
            17: "preferred subfamily",
        ]
        struct NameHit {
            var score: Int
            var text: String
        }
        var best: [Int: NameHit] = [:]
        for i in 0..<min(count, 512) {
            let rec = tableAt + 6 + i * 12
            guard rec + 12 <= b.count,
                  let platform = fileU16BE(
                    b, rec),
                  let language = fileU16BE(
                    b, rec + 4),
                  let nameID = fileU16BE(
                    b, rec + 6),
                  let len = fileU16BE(
                    b, rec + 8),
                  let off = fileU16BE(
                    b, rec + 10),
                  labels[nameID] != nil
            else { continue }
            let start = tableAt + storage
                + off
            guard start + len <= b.count,
                  len > 0, len < 1024
            else { continue }
            let raw = Array(b[start..<(start + len)])
            let text: String?
            var score = 0
            if platform == 3
                || platform == 0 {
                text = String(
                    bytes: raw,
                    encoding: .utf16BigEndian)
                score = language == 0x409
                    ? 3 : 2
            } else if platform == 1 {
                text = String(
                    bytes: raw,
                    encoding: .isoLatin1)
                score = 1
            } else {
                text = nil
            }
            guard let text = text,
                  !text.isEmpty else {
                continue
            }
            if let existing = best[nameID],
               existing.score >= score {
                continue
            }
            best[nameID] = NameHit(
                score: score, text: text)
        }
        for id in [1, 2, 4, 6, 16, 17] {
            if let hit = best[id],
               let label = labels[id] {
                icsSay(emit, String(format: L("%@: %@ (the font's claim)"), label, hit.text), .out)
            }
        }
        if best.isEmpty {
            icsSay(emit, L("a name table whose records this reader cannot decode — the font keeps its name in a dress the bench does not read."), .out)
        }
    }

    static func fileWOFFReport(
        _ b: [UInt8],
        emit: @escaping BlacksiteEmit) {
        guard let numTables = fileU16BE(
                b, 12),
              let totalSize = fileU32BE(b, 8)
        else { return }
        icsSay(emit, String(format: L("a WOFF wrapper claiming %lld bytes total and %lld tables"), Int64(totalSize), Int64(numTables)), .out)
        for i in 0..<min(numTables, 64) {
            let rec = 44 + i * 20
            guard rec + 20 <= b.count,
                  let off = fileU32BE(b, rec + 4),
                  let comp = fileU32BE(
                    b, rec + 8),
                  let orig = fileU32BE(
                    b, rec + 12)
            else { break }
            let tag = String(
                decoding: b[rec..<(rec + 4)],
                as: UTF8.self)
            _ = off
            if comp < orig {
                icsSay(emit, String(format: L("table %@: %lld bytes compressed from %lld"), tag, Int64(comp), Int64(orig)), .out)
            } else {
                icsSay(emit, String(format: L("table %@: %lld bytes, stored plain"), tag, Int64(orig)), .out)
            }
        }
        icsSay(emit, L("WOFF keeps its name table compressed like the rest — the bench reads the directory and does not inflate tables to go visiting them."), .sys)
    }

    /// WOFF2's directory: tag indices
    /// and base-128 lengths. The name
    /// table rides transformed inside;
    /// the bench states that limit
    /// instead of decoding transforms.
    static func fileWOFF2Report(
        _ b: [UInt8],
        emit: @escaping BlacksiteEmit) {
        guard let numTables = fileU16BE(
                b, 12) else { return }
        let knownTags = [
            "cmap", "head", "hhea", "hmtx",
            "maxp", "name", "OS/2", "post",
            "cvt ", "fpgm", "glyf", "loca",
            "prep", "CFF ", "VORG", "EBDT",
            "EBLC", "gasp", "hdmx", "kern",
            "LTSH", "PCLT", "VDMX", "vhea",
            "vmtx", "BASE", "GDEF", "GPOS",
            "GSUB", "EBSC", "JSTF", "MATH",
            "CBDT", "CBLC", "COLR", "CPAL",
            "SVG ", "sbix", "acnt", "avar",
            "bdat", "bloc", "bsln", "cvar",
            "fdsc", "feat", "fmtx", "fvar",
            "gvar", "hsty", "just", "lcar",
            "mort", "morx", "opbd", "prop",
            "trak", "Zapf", "Silf", "Glat",
            "Gloc", "Feat", "Sill",
        ]
        icsSay(emit, String(format: L("a WOFF2 wrapper claiming %lld tables"), Int64(numTables)), .out)
        var pos = 48
        for _ in 0..<min(numTables, 64) {
            guard pos < b.count else {
                break
            }
            let flags = Int(b[pos])
            pos += 1
            let tagIndex = flags & 0x3F
            let tag: String
            if tagIndex == 0x3F {
                guard pos + 4 <= b.count
                else { break }
                tag = String(
                    decoding: b[pos..<(pos + 4)],
                    as: UTF8.self)
                pos += 4
            } else if tagIndex
                        < knownTags.count {
                tag = knownTags[tagIndex]
            } else {
                tag = String(format: L("tag %lld"), Int64(tagIndex))
            }
            guard let (_, used) =
                fileBase128(b, pos)
            else { break }
            pos += used
            // A transformed length follows
            // only for the glyf/loca pair
            // (and untagged customs with a
            // transform); the directory
            // ledger stops at the tag and
            // its compressed length.
            icsSay(emit, String(format: L("table %@ rides compressed"), tag), .out)
            if tag == "glyf" || tag == "loca" {
                if let (_, used2) =
                    fileBase128(b, pos) {
                    pos += used2
                }
            }
        }
        icsSay(emit, L("WOFF2's tables ride transformed, its name table among them — decoding them is a font engine's work, and the bench states the limit rather than faking a read."), .sys)
    }

    static func fileBase128(
        _ b: [UInt8], _ from: Int)
        -> (Int, Int)? {
        var value = 0
        var i = 0
        while i < 5, from + i < b.count {
            let byte = b[from + i]
            value = value << 7
                | Int(byte & 0x7F)
            i += 1
            if byte & 0x80 == 0 {
                return (value, i)
            }
        }
        return nil
    }

    // MARK: certfile — a bundle's ledger

    /// Not a deep read — x509probe and
    /// keyprobe own those, and this verb
    /// says so. This is the FILE's
    /// census: every block it carries,
    /// in the order it carries them,
    /// one line of identity each, and
    /// the order itself graded.
    static func certfile(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (b, path) =
                fileLoadOrReport(
                    target, verb: "certfile",
                    emit: emit) else { return }
            fileHeader("certfile",
                       path: path,
                       bytes: b.count,
                       emit: emit)
            let text = String(
                decoding: b, as: UTF8.self)
            let blocks = lockPEMBlocks(text)
            if blocks.isEmpty {
                if b.first == 0x30 {
                    icsSay(emit, L("no PEM blocks — a bare DER file. x509probe deep-reads a lone certificate; keyprobe deep-reads a lone key. certfile ledgers bundles, and a bundle this is not."), .err)
                } else {
                    icsSay(emit, L("no PEM blocks ride in this file — nothing for the ledger to keep."), .err)
                }
                return
            }
            icsSay(emit, String(format: L("%lld PEM blocks, in the order the file keeps them:"), Int64(blocks.count)), .out)
            var certs: [(Int, LockCert)] = []
            var keyTravels = false
            for (index, block)
                in blocks.enumerated() {
                let number = index + 1
                let label = block.label
                let der = block.der
                if label == "CERTIFICATE"
                    || label
                        == "TRUSTED CERTIFICATE"
                    || label
                        == "X509 CERTIFICATE" {
                    if let cert =
                        lockCertParse(der) {
                        certs.append(
                            (number, cert))
                        let expiry = cert
                            .notAfter.map {
                                fileUTCFormatter
                                    .string(
                                        from: $0)
                            } ?? L("an unread expiry")
                        icsSay(emit, String(format: L("%lld. certificate — %@; issued by %@; expires %@"), Int64(number), cert.subjectLine, cert.issuerLine, expiry), .out)
                    } else {
                        icsSay(emit, String(format: L("%lld. certificate — %lld DER bytes that do not parse as one"), Int64(number), Int64(der.count)), .err)
                    }
                } else if label
                            == "PUBLIC KEY" {
                    if let info =
                        lockParseSPKI(der) {
                        icsSay(emit, String(format: L("%lld. public key — %@; keyprobe reads it deep"), Int64(number), info.family), .out)
                    } else {
                        icsSay(emit, String(format: L("%lld. public key — %lld DER bytes that do not parse"), Int64(number), Int64(der.count)), .out)
                    }
                } else if label
                            == "PRIVATE KEY" {
                    keyTravels = true
                    icsSay(emit, String(format: L("%lld. PRIVATE key — %lld DER bytes, algorithm %@; its secret bytes are never decoded here"), Int64(number), Int64(der.count), filePKCS8Algorithm(der)), .err)
                } else if label
                            == "ENCRYPTED PRIVATE KEY" {
                    keyTravels = true
                    icsSay(emit, String(format: L("%lld. ENCRYPTED private key — %lld DER bytes, sealed; the bench notes it and moves on"), Int64(number), Int64(der.count)), .out)
                } else if label.contains(
                    "PRIVATE KEY") {
                    keyTravels = true
                    icsSay(emit, String(format: L("%lld. a private key (%@) — %lld DER bytes; keyprobe names its kind"), Int64(number), label, Int64(der.count)), .err)
                } else if label
                            == "CERTIFICATE REQUEST" {
                    icsSay(emit, String(format: L("%lld. a certificate request — %lld DER bytes; x509probe's deep read covers requests"), Int64(number), Int64(der.count)), .out)
                } else {
                    icsSay(emit, String(format: L("%lld. %@ — %lld DER bytes"), Int64(number), label, Int64(der.count)), .out)
                }
            }
            if keyTravels && !certs.isEmpty {
                icsSay(emit, L("a private key travels in the same file as certificates. A key and its papers belong in different rooms — whoever holds this file holds both."), .err)
            }
            if certs.count >= 2 {
                var chained = true
                for i in 1..<certs.count {
                    if certs[i].1.issuerRaw
                        != certs[i - 1].1
                            .subjectRaw {
                        chained = false
                        icsSay(emit, String(format: L("the chain breaks at block %lld: its issuer is not the subject of the certificate before it — a shuffled bundle, a foreign certificate, or an incomplete chain"), Int64(certs[i].0)), .err)
                        break
                    }
                }
                if chained {
                    icsSay(emit, L("the certificates chain in order, each issued by the one after it — a bundle packed by someone who meant it"), .ok)
                }
                if let root = certs.last,
                   root.1.issuerRaw
                    == root.1.subjectRaw {
                    icsSay(emit, L("the last certificate is self-issued — the chain ends at a root, as chains should"), .ok)
                }
            }
            icsSay(emit, L("one line per block is the ledger's whole job. The deep reads — extensions, fingerprints, key strength judged in full — belong to x509probe and keyprobe, by name."), .sys)
        }
    }

    /// A PKCS#8 envelope's algorithm
    /// OID — the envelope's papers,
    /// never the key inside it.
    static func filePKCS8Algorithm(
        _ der: [UInt8]) -> String {
        guard let outer = lockTLV(der, 0),
              outer.tag == 0x30
        else { return L("unread") }
        let fields = lockChildren(
            der, outer.cs, outer.ce)
        guard fields.count >= 2 else {
            return L("unread")
        }
        let alg = fields[1]
        guard alg.tag == 0x30 else {
            return L("unread")
        }
        let parts = lockChildren(
            der, alg.cs, alg.ce)
        guard let first = parts.first,
              first.tag == 0x06
        else { return L("unread") }
        let oid = lockOID(
            der, first.cs, first.ce)
        let names: [String: String] = [
            "1.2.840.113549.1.1.1":
                "RSA",
            "1.2.840.10045.2.1":
                "EC",
            "1.3.101.112": "Ed25519",
            "1.3.101.110": "X25519",
            "1.3.101.111": "Ed448",
        ]
        if let name = names[oid] {
            return name + " (" + oid + ")"
        }
        return oid
    }

    // MARK: dupprobe — the same bytes twice

    /// A directory's duplicates, by
    /// size and then by SHA-256: bytes
    /// the operator pays for more than
    /// once, named with what they cost.
    static func dupprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let dir = fileDir(target)
            else {
                icsSay(emit, L("dupprobe: nothing readable as a directory at that path"), .err)
                return
            }
            icsSay(emit, String(format: L("dupprobe — %@"), dir), .sys)
            let walked = BlacksiteFS.walk(dir)
            let cap = 2000
            let files = Array(
                walked.prefix(cap))
            if walked.count > cap {
                icsSay(emit, String(format: L("the walk holds %lld files; the census takes the first %lld and says so"), Int64(walked.count), Int64(cap)), .out)
            }
            var bySize: [Int: [String]] = [:]
            for file in files {
                if let size = BlacksiteFS
                    .fileSize(file) {
                    bySize[size, default: []]
                        .append(file)
                }
            }
            let hashCap = 64 * 1024 * 1024
            var groups: [(String, Int, [String])] = []
            var skipped = 0
            var hashed = 0
            for (size, paths) in bySize
            where paths.count > 1 {
                if size > hashCap {
                    skipped += paths.count
                    continue
                }
                var byHash: [String: [String]] = [:]
                for file in paths {
                    guard let data =
                        BlacksiteFS.readData(
                            file) else {
                        continue
                    }
                    hashed += 1
                    let hex = SHA256.hash(
                        data: data).map {
                            String(format: "%02x", $0)
                        }.joined()
                    byHash[hex, default: []]
                        .append(file)
                }
                for (hash, same) in byHash
                where same.count > 1 {
                    groups.append(
                        (hash, size, same))
                }
            }
            if skipped > 0 {
                icsSay(emit, String(format: L("%lld same-size files past the %lld-byte hashing ceiling were counted by size alone"), Int64(skipped), Int64(hashCap)), .out)
            }
            if groups.isEmpty {
                icsSay(emit, String(format: L("no duplicates: %lld files walked, every byte paid for once"), Int64(files.count)), .ok)
                return
            }
            groups.sort {
                ($0.2.count - 1) * $0.1
                    > ($1.2.count - 1) * $1.1
            }
            var wastedTotal = 0
            for (hash, size, paths)
                in groups.prefix(32) {
                let wasted = (paths.count - 1) *
                    size
                wastedTotal += wasted
                icsSay(emit, String(format: L("%lld copies of %@ (sha256 %@…) — %lld bytes held twice over"), Int64(paths.count), fileHuman(size), String(hash.prefix(16)), Int64(wasted)), .out)
                for file in paths.prefix(10) {
                    icsSay(emit, "  " + file, .out)
                }
                if paths.count > 10 {
                    icsSay(emit, String(format: L("  ... and %lld more copies"), Int64(paths.count - 10)), .out)
                }
            }
            if groups.count > 32 {
                icsSay(emit, String(format: L("... and %lld more duplicate groups past the ledger cap"), Int64(groups.count - 32)), .out)
            }
            icsSay(emit, String(format: L("total: %lld duplicate groups over %lld files walked (%lld hashed) — %lld bytes paid for more than once"), Int64(groups.count), Int64(files.count), Int64(hashed), Int64(groups.reduce(0) { $0 + ($1.2.count - 1) * $1.1 })), .out)
            _ = wastedTotal
        }
    }

    // MARK: fileboard — a directory's whole board

    /// The room read at once: what
    /// kinds of files live here, how
    /// big the room runs, the largest
    /// tenants, and every mismatch and
    /// stowaway the walk can see.
    static func fileboard(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let dir = fileDir(target)
            else {
                icsSay(emit, L("fileboard: nothing readable as a directory at that path"), .err)
                return
            }
            icsSay(emit, String(format: L("fileboard — %@"), dir), .sys)
            let std = dir
            let walked = BlacksiteFS.walk(
                std)
            let cap = 500
            var considered = 0
            var tooDeep = 0
            let baseDepth = std.split(
                separator: "/").count
            var kindCounts: [String: Int] = [:]
            var kindBytes: [String: Int] = [:]
            var largest: [(Int, String)] = []
            var mismatches: [String] = []
            var trailingImages: [String] = []
            var heavyUnknowns: [String] = []
            var emptyCount = 0
            var hiddenCount = 0
            var totalBytes = 0
            for file in walked {
                let depth = file.split(
                    separator: "/").count
                    - baseDepth
                if depth > 8 {
                    tooDeep += 1
                    continue
                }
                if considered >= cap {
                    break
                }
                considered += 1
                let size = BlacksiteFS
                    .fileSize(file) ?? 0
                totalBytes += size
                let base = BlacksiteFS
                    .baseName(of: file)
                if base.hasPrefix(".") {
                    hiddenCount += 1
                }
                if size == 0 {
                    emptyCount += 1
                }
                largest.append((size, file))
                largest.sort {
                    $0.0 > $1.0
                }
                if largest.count > 5 {
                    largest.removeLast()
                }
                var kindName = L("unread (past the board's per-file reading ceiling)")
                var kind: FileKind?
                if size <= 8 * 1024 * 1024,
                   let data = BlacksiteFS
                    .readData(file) {
                    let bytes = [UInt8](data)
                    kind = fileKind(bytes)
                    if let kind = kind {
                        kindName = kind.name
                        // Family findings.
                        if let ext =
                            fileExtension(file),
                           let family =
                            fileExtFamily[ext],
                           kind.family != family,
                           mismatches.count < 5 {
                            mismatches.append(
                                String(format: L("%@: named .%@, is %@"), base, ext, kind.name))
                        }
                        if kind.family == "jpeg",
                           let j = fileJPEGWalk(
                            bytes),
                           j.trailing > 0,
                           trailingImages.count < 5 {
                            trailingImages.append(
                                String(format: L("%@: %lld bytes past the end marker"), base, Int64(j.trailing)))
                        }
                        if kind.family == "png" {
                            let chunks =
                                filePNGChunks(
                                    bytes)
                            let lastEnd =
                                chunks.last?.end
                                ?? bytes.count
                            if bytes.count
                                > lastEnd,
                               trailingImages
                                .count < 5 {
                                trailingImages.append(
                                    String(format: L("%@: %lld bytes past IEND"), base, Int64(bytes.count - lastEnd)))
                            }
                        }
                    } else if fileLooksText(
                        bytes) {
                        kindName = L("text (no signature)")
                    } else {
                        kindName = L("unknown bytes")
                        if size >= 4096 {
                            let stats =
                                lockStats(
                                    Array(bytes
                                        .prefix(
                                            65536)))
                            if stats.entropy > 7.5,
                               heavyUnknowns
                                .count < 5 {
                                heavyUnknowns
                                    .append(
                                        String(format: L("%@: entropy %.2f over %@"), base, stats.entropy, fileHuman(size)))
                            }
                        }
                    }
                }
                kindCounts[kindName,
                           default: 0] += 1
                kindBytes[kindName,
                          default: 0] += size
            }
            if walked.count > considered {
                icsSay(emit, String(format: L("the walk holds %lld files; the board reads %lld in aggregate (the caps are stated, as always)"), Int64(walked.count), Int64(considered)), .out)
            }
            if tooDeep > 0 {
                icsSay(emit, String(format: L("%lld files sit deeper than eight levels and were skipped"), Int64(tooDeep)), .out)
            }
            icsSay(emit, String(format: L("%lld files, %@ in all"), Int64(considered), fileHuman(totalBytes)), .out)
            let kinds = kindCounts.keys
                .sorted {
                    (kindBytes[$0] ?? 0)
                        > (kindBytes[$1] ?? 0)
                }
            for kindName in kinds {
                icsSay(emit, String(format: L("%@: %lld files, %@"), kindName, Int64(kindCounts[kindName] ?? 0), fileHuman(kindBytes[kindName] ?? 0)), .out)
            }
            if !largest.isEmpty {
                icsSay(emit, L("the largest:"), .out)
                for (size, file) in largest {
                    icsSay(emit, String(format: L("  %@ — %@"), fileHuman(size), BlacksiteFS.baseName(of: file)), .out)
                }
            }
            if emptyCount > 0 {
                icsSay(emit, String(format: L("%lld empty files"), Int64(emptyCount)), .out)
            }
            if hiddenCount > 0 {
                icsSay(emit, String(format: L("%lld hidden files (the name opens with a dot)"), Int64(hiddenCount)), .out)
            }
            for line in mismatches {
                icsSay(emit, line, .err)
            }
            for line in trailingImages {
                icsSay(emit, line, .err)
            }
            for line in heavyUnknowns {
                icsSay(emit, String(format: L("high-entropy unknown: %@ — sealed, compressed, or random; enccensus reads the seals"), line), .out)
            }
            if mismatches.isEmpty
                && trailingImages.isEmpty
                && heavyUnknowns.isEmpty {
                icsSay(emit, L("no mismatches, no stowaways, no heavy unknowns in the read — a tidy room, by its bytes"), .ok)
            }
        }
    }
}
