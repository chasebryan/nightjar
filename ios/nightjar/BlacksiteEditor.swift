import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// BLACKSITE EDITORS — vim and emacs, in the
/// console (the operator's orders, 2026-10-19:
/// "capable of initiation of vim" and "fully
/// utilize emacs").
///
/// iOS gives no app a process to spawn, so
/// there is no borrowed vim binary and no
/// borrowed emacs binary — these are the
/// house's own editors, written for the
/// room, and they are real: one buffer
/// engine, two faiths. VIM is modal —
/// normal, insert, visual, command — with
/// counts, operators, motions, search and
/// the : ex line. EMACS is the chord church
/// — point and mark, the kill ring, C-x
/// prefixes, buffers, isearch and M-x. Both
/// read and write the console's own file
/// system, both carry undo, and the extra
/// key row above the keyboard carries ESC,
/// CTRL and ALT the way the phone editors
/// do, so every chord is reachable.

enum EditorPersonality: String {
    case vim, emacs, nano
}

enum EditorKey {
    case char(Character)
    case enter, backspace, tab, escape
    case arrow(String)
    case ctrl(Character)
    case alt(Character)
}

final class EditorCore: ObservableObject {
    struct Buffer {
        var path: String?
        var name: String
        var lines: [String] = [""]
        var row: Int = 0
        var col: Int = 0
        var dirty: Bool = false
    }

    @Published private(set) var buffers: [Buffer] = []
    @Published private(set) var current = 0
    @Published var message = ""
    @Published var showNumbers = true
    @Published var ctrlLatch = false
    @Published var altLatch = false
    /// Bumps whenever the display must be
    /// re-rendered from the buffer (command
    /// edits), as opposed to typed edits the
    /// display already shows.
    @Published private(set) var renderTick = 0

    var personality: EditorPersonality
    var onExit: (() -> Void)?

    // vim state
    enum VimMode { case normal, insert, visual }
    @Published private(set) var vimMode: VimMode = .normal
    private var pendingCount = ""
    private var pendingOp: Character?
    private var visualAnchor: (Int, Int)?
    private var searchPattern = ""
    private var searchForward = true

    // emacs state
    private var mark: (Int, Int)?
    private var markActive = false
    private var ctrlXPending = false
    private var quitPending = false
    private var lastKill = false
    private var killPending = false

    // shared state
    private var killRing: [(text: String,
                            lineWise: Bool)] = []
    private var undoStack: [(lines: [String],
                             row: Int, col: Int)] = []
    private var lastUndoPush = Date.distantPast

    // minibuffer
    @Published private(set) var miniPrompt: String?
    private var miniText = ""
    private var miniAction: ((String) -> Void)?
    private var miniOnChange: ((String) -> Void)?
    private var miniSavedPoint: (Int, Int)?

    var miniDisplay: String {
        guard let prompt = miniPrompt else {
            return ""
        }
        return prompt + miniText
    }

    init(personality: EditorPersonality) {
        self.personality = personality
    }

    // MARK: Buffers

    var buffer: Buffer {
        get {
            guard buffers.indices.contains(current)
            else { return Buffer(path: nil,
                                 name: "*scratch*") }
            return buffers[current]
        }
        set {
            guard buffers.indices.contains(current)
            else { return }
            buffers[current] = newValue
        }
    }

    var lines: [String] { buffer.lines }
    var row: Int { buffer.row }
    var col: Int { buffer.col }

    /// Whether the current buffer holds
    /// unwritten work — the view's close
    /// button asks before discarding it.
    var bufferDirty: Bool {
        !buffers.isEmpty && buffer.dirty
    }

    var statusLeft: String {
        let dirtyMark = buffer.dirty ? " ●" : ""
        return buffer.name + dirtyMark
    }

    var statusRight: String {
        switch personality {
        case .vim:
            let mode: String
            switch vimMode {
            case .normal: mode = "NORMAL"
            case .insert: mode = "-- INSERT --"
            case .visual: mode = "-- VISUAL --"
            }
            return "\(mode)  \(row + 1):\(col + 1)"
        case .emacs:
            var flags = "Emacs"
            if ctrlXPending { flags += " C-x-" }
            if markActive { flags += " [mark]" }
            return "\(flags)  \(row + 1):\(col + 1)"
        case .nano:
            return "Nano  \(row + 1):\(col + 1)"
        }
    }

    func open(path: String?,
              personality forced: EditorPersonality?) {
        if let forced = forced {
            personality = forced
        }
        if let path = path {
            let clean = BlacksiteFS.normalize(
                path, cwd: BlacksiteFS.home)
            if let existing = buffers.firstIndex(
                where: { $0.path == clean }) {
                current = existing
                return
            }
            var fresh = Buffer(
                path: clean,
                name: BlacksiteFS.baseName(
                    of: clean))
            if let text = BlacksiteFS.readText(clean) {
                fresh.lines = splitLines(text)
                fresh.dirty = false
            } else {
                message = "\"\(fresh.name)\" "
                    + "[new file]"
            }
            buffers.append(fresh)
            current = buffers.count - 1
        } else if buffers.isEmpty {
            buffers.append(Buffer(
                path: nil, name: "*scratch*"))
            current = 0
        }
        renderTick += 1
    }

    private func splitLines(_ text: String)
        -> [String] {
        var rows = text.components(
            separatedBy: "\n")
        if rows.last == "" { rows.removeLast() }
        return rows.isEmpty ? [""] : rows
    }

    private func joinedText() -> String {
        var text = buffer.lines.joined(
            separator: "\n")
        if !text.isEmpty { text += "\n" }
        return text
    }

    @discardableResult
    func saveBuffer() -> Bool {
        guard let path = buffer.path else {
            miniAsk(prompt: "File: ",
                    seed: "/home/") { [weak self] in
                self?.buffer.path =
                    BlacksiteFS.normalize(
                        $0, cwd: BlacksiteFS.home)
                self?.buffer.name = BlacksiteFS
                    .baseName(of: $0)
                _ = self?.saveBuffer()
            }
            return false
        }
        guard BlacksiteFS.writeText(
            path, text: joinedText()) else {
            message = "could not write \(path)"
            return false
        }
        buffer.dirty = false
        message = "\"\(buffer.name)\" written"
        return true
    }

    private func killCurrentBuffer() {
        guard buffers.count > 1 else {
            message = "one buffer left — "
                + "it stays"
            return
        }
        buffers.remove(at: current)
        current = max(0, current - 1)
        message = "buffer killed — now on "
            + buffer.name
        renderTick += 1
    }

    private func switchBuffer(named name: String) {
        let wanted = name.lowercased()
        if let index = buffers.firstIndex(where: {
            $0.name.lowercased() == wanted
                || ($0.path ?? "").lowercased()
                    == wanted
        }) {
            current = index
            message = buffer.name
            renderTick += 1
        } else {
            message = "no buffer named \(name)"
        }
    }

    private func listBuffers() {
        var text = "buffers:\n"
        for (index, item) in buffers.enumerated() {
            text += (index == current ? "* " : "  ")
                + item.name
                + (item.dirty ? " (unsaved)" : "")
                + " — \(item.lines.count) lines\n"
        }
        openTextBuffer(name: "*buffers*",
                       text: text)
    }

    private func openTextBuffer(name: String,
                                text: String) {
        var fresh = Buffer(path: nil, name: name)
        fresh.lines = splitLines(text)
        fresh.dirty = false
        buffers.append(fresh)
        current = buffers.count - 1
        renderTick += 1
    }

    // MARK: Editing primitives

    private func pushUndo(coalesce: Bool = false) {
        if coalesce,
           Date().timeIntervalSince(lastUndoPush)
            < 0.9 {
            return
        }
        lastUndoPush = Date()
        undoStack.append((lines: buffer.lines,
                          row: row, col: col))
        if undoStack.count > 120 {
            undoStack.removeFirst(
                undoStack.count - 120)
        }
    }

    func undo() {
        guard let prior = undoStack.popLast()
        else {
            message = "nothing to undo"
            return
        }
        buffer.lines = prior.lines
        buffer.row = min(prior.row,
                         prior.lines.count - 1)
        buffer.col = prior.col
        buffer.dirty = true
        clampCursor()
        message = "undone"
        renderTick += 1
    }

    private func clampCursor() {
        buffer.row = max(0, min(row,
                                buffer.lines.count - 1))
        let limit = buffer.lines[buffer.row].count
        let cap = personality == .vim
            && vimMode == .normal
            ? max(0, limit - 1) : limit
        buffer.col = max(0, min(col, cap))
        if personality == .vim
            && vimMode == .visual {
            buffer.col = max(0, min(col, limit))
        }
    }

    private func setCursor(row newRow: Int,
                           col newCol: Int) {
        buffer.row = newRow
        buffer.col = newCol
        clampCursor()
    }

    /// The display owns typed edits: after
    /// one lands in the text view, mirror it
    /// back into the buffer.
    func syncFromDisplay(text: String,
                         cursorOffset: Int) {
        let newLines = splitLines(text)
        if newLines != buffer.lines {
            pushUndo(coalesce: true)
            buffer.lines = newLines
            buffer.dirty = true
        }
        let (r, c) = position(ofOffset:
                                cursorOffset,
                              in: newLines)
        buffer.row = r
        buffer.col = c
    }

    func offset(ofRow r: Int, col c: Int) -> Int {
        var total = 0
        for index in 0..<min(r, buffer.lines.count) {
            total += buffer.lines[index].count + 1
        }
        return total + min(c,
                           buffer.lines[
                            min(r, buffer.lines
                                .count - 1)].count)
    }

    func cursorOffset() -> Int {
        offset(ofRow: row, col: col)
    }

    private func position(ofOffset target: Int,
                          in rows: [String])
        -> (Int, Int) {
        var remaining = target
        for (index, line) in rows.enumerated() {
            if remaining <= line.count {
                return (index, remaining)
            }
            remaining -= line.count + 1
        }
        return (rows.count - 1,
                rows.last?.count ?? 0)
    }

    private func lineText(_ index: Int) -> String {
        guard buffer.lines.indices.contains(index)
        else { return "" }
        return buffer.lines[index]
    }

    private func replaceLine(_ index: Int,
                             with text: String) {
        guard buffer.lines.indices.contains(index)
        else { return }
        buffer.lines[index] = text
        buffer.dirty = true
    }

    private func charAt(_ r: Int, _ c: Int)
        -> Character? {
        let line = lineText(r)
        guard c >= 0, c < line.count else {
            return nil
        }
        return line[line.index(line.startIndex,
                               offsetBy: c)]
    }

    // MARK: The key door

    func handle(_ key: EditorKey) {
        var key = key
        if ctrlLatch {
            ctrlLatch = false
            if case .char(let ch) = key {
                key = .ctrl(ch)
            }
        } else if altLatch {
            altLatch = false
            if case .char(let ch) = key {
                key = .alt(ch)
            }
        }
        if miniPrompt != nil {
            miniKey(key)
            return
        }
        switch personality {
        case .vim: vimKey(key)
        case .emacs: emacsKey(key)
        case .nano: nanoKey(key)
        }
    }

    /// Whether a typed character may go
    /// straight into the display (insert
    /// modes), or the core wants it as a key.
    func typingAllowed() -> Bool {
        if miniPrompt != nil { return false }
        if ctrlLatch || altLatch { return false }
        switch personality {
        case .vim: return vimMode == .insert
        case .emacs: return true
        case .nano: return true
        }
    }

    /// Route a typed character through the
    /// key engine instead of the display.
    func typeAsKey(_ text: String) {
        for ch in text {
            handle(.char(ch))
        }
    }

    func backspaceAsKey() {
        if miniPrompt != nil {
            miniKey(.backspace)
            return
        }
        handle(.backspace)
    }

    // MARK: The minibuffer

    private func miniAsk(
        prompt: String, seed: String = "",
        onChange: ((String) -> Void)? = nil,
        action: @escaping (String) -> Void) {
        miniPrompt = prompt
        miniText = seed
        miniAction = action
        miniOnChange = onChange
        miniSavedPoint = (row, col)
    }

    private func miniKey(_ key: EditorKey) {
        switch key {
        case .char(let ch):
            miniText.append(ch)
            miniOnChange?(miniText)
        case .backspace:
            if !miniText.isEmpty {
                miniText.removeLast()
                miniOnChange?(miniText)
            }
        case .enter:
            let text = miniText
            let action = miniAction
            closeMini()
            action?(text)
        case .escape:
            cancelMini()
        case .ctrl(let ch) where ch == "g":
            cancelMini()
        case .tab:
            miniText.append("\t")
            miniOnChange?(miniText)
        default:
            break
        }
    }

    private func closeMini() {
        miniPrompt = nil
        miniText = ""
        miniAction = nil
        miniOnChange = nil
        miniSavedPoint = nil
    }

    private func cancelMini() {
        if let saved = miniSavedPoint {
            setCursor(row: saved.0, col: saved.1)
            renderTick += 1
        }
        closeMini()
        message = "quit"
    }

    // MARK: Word motions (shared)

    private func isWordChar(_ ch: Character)
        -> Bool {
        ch.isLetter || ch.isNumber || ch == "_"
    }

    /// Word steps used by both editors:
    /// scan the joined text.
    private func wordStep(from r: Int, _ c: Int,
                          forward: Bool) -> (Int, Int) {
        let text = buffer.lines.joined(
            separator: "\n")
        var index = offset(ofRow: r, col: c)
        let chars = Array(text)
        if forward {
            var i = index
            if i < chars.count, isWordChar(chars[i])
                || isPunct(chars[i]) {
                let word = isWordChar(chars[i])
                while i < chars.count,
                      (word ? isWordChar(chars[i])
                       : isPunct(chars[i])) {
                    i += 1
                }
            }
            while i < chars.count,
                  chars[i] == " "
                    || chars[i] == "\t"
                    || chars[i] == "\n" {
                i += 1
            }
            index = i
        } else {
            var i = index - 1
            while i >= 0, chars[i] == " "
                    || chars[i] == "\t"
                    || chars[i] == "\n" {
                i -= 1
            }
            if i >= 0 {
                let word = isWordChar(chars[i])
                while i >= 0,
                      (word ? isWordChar(chars[i])
                       : isPunct(chars[i])) {
                    i -= 1
                }
                i += 1
            }
            index = max(0, i)
        }
        return position(ofOffset: index,
                        in: buffer.lines)
    }

    private func isPunct(_ ch: Character) -> Bool {
        !isWordChar(ch) && ch != " "
            && ch != "\t" && ch != "\n"
    }

    private func wordEnd(from r: Int, _ c: Int)
        -> (Int, Int) {
        let stepped = wordStep(from: r, c,
                                 forward: true)
        var target = offset(ofRow: stepped.0,
                            col: stepped.1)
        target = max(offset(ofRow: r, col: c),
                     target - 1)
        return position(ofOffset: target,
                        in: buffer.lines)
    }

    private func firstNonBlank(_ r: Int) -> Int {
        let line = lineText(r)
        var index = 0
        for ch in line {
            if ch == " " || ch == "\t" {
                index += 1
            } else { break }
        }
        return index
    }
}

// MARK: - Shared range surgery

extension EditorCore {
    func blobText() -> String {
        buffer.lines.joined(separator: "\n")
    }

    func setBlob(_ blob: String,
                 cursorOffset off: Int) {
        buffer.lines = blob.isEmpty
            ? [""]
            : blob.components(separatedBy: "\n")
        let target = position(ofOffset: off,
                              in: buffer.lines)
        buffer.row = target.0
        buffer.col = target.1
        buffer.dirty = true
        clampCursor()
    }

    @discardableResult
    func deleteOffsets(_ start: Int, _ end: Int)
        -> String {
        let chars = Array(blobText())
        guard start >= 0, end <= chars.count,
              start < end else { return "" }
        let removed = String(chars[start..<end])
        var kept = chars
        kept.removeSubrange(start..<end)
        setBlob(String(kept), cursorOffset: start)
        return removed
    }

    func yankOffsets(_ start: Int, _ end: Int)
        -> String {
        let chars = Array(blobText())
        guard start >= 0, end <= chars.count,
              start < end else { return "" }
        return String(chars[start..<end])
    }

    func insertAtOffset(_ text: String,
                        offset off: Int) {
        var chars = Array(blobText())
        let at = max(0, min(off, chars.count))
        chars.insert(contentsOf: Array(text),
                     at: at)
        setBlob(String(chars),
                cursorOffset: at + text.count)
    }
}

// MARK: - VIM

extension EditorCore {
    private var count: Int {
        max(1, Int(pendingCount) ?? 1)
    }

    func vimKey(_ key: EditorKey) {
        switch vimMode {
        case .insert:
            vimInsertKey(key)
        case .normal, .visual:
            vimNormalKey(key)
        }
    }

    private func exitInsert() {
        vimMode = .normal
        if col > 0 {
            buffer.col = col - 1
        }
        message = ""
        renderTick += 1
    }

    private func vimInsertKey(_ key: EditorKey) {
        switch key {
        case .escape:
            exitInsert()
        case .ctrl(let ch) where ch == "c":
            exitInsert()
        case .tab:
            pushUndo()
            insertAtOffset("    ",
                           offset: cursorOffset())
            renderTick += 1
        case .arrow(let dir):
            moveArrow(dir)
        default:
            break
        }
    }

    private func moveArrow(_ dir: String) {
        switch dir {
        case "left":
            if col > 0 { buffer.col = col - 1 }
        case "right":
            buffer.col = col + 1
            clampCursor()
        case "up":
            if row > 0 {
                buffer.row = row - 1
                clampCursor()
            }
        case "down":
            if row + 1 < buffer.lines.count {
                buffer.row = row + 1
                clampCursor()
            }
        default:
            break
        }
        renderTick += 1
    }

    private func resetPending() {
        pendingCount = ""
        pendingOp = nil
    }

    private func vimNormalKey(_ key: EditorKey) {
        switch key {
        case .escape:
            vimMode = .normal
            visualAnchor = nil
            resetPending()
            message = ""
            renderTick += 1
        case .arrow(let dir):
            moveArrow(dir)
        case .backspace:
            if col > 0 { buffer.col = col - 1 }
            renderTick += 1
        case .enter:
            let target = min(buffer.lines.count - 1,
                             row + count)
            buffer.row = target
            buffer.col = firstNonBlank(target)
            resetPending()
            renderTick += 1
        case .ctrl(let ch):
            if ch == "d" {
                buffer.row = min(
                    buffer.lines.count - 1,
                    row + 10)
                clampCursor()
            } else if ch == "u" {
                buffer.row = max(0, row - 10)
                clampCursor()
            }
            renderTick += 1
        case .char(let ch):
            vimChar(ch)
        default:
            break
        }
    }

    private func firstNonBlankOf(_ r: Int) -> Int {
        let line = buffer.lines[
            min(r, buffer.lines.count - 1)]
        var index = 0
        for ch in line {
            if ch == " " || ch == "\t" {
                index += 1
            } else { break }
        }
        return index
    }

    private func vimChar(_ ch: Character) {
        // A pending operator waits for its
        // motion (or its own letter again).
        if let op = pendingOp {
            pendingOp = nil
            if ch == op {
                lineOperation(op, times: count)
            } else {
                motionOperation(op, motion: ch,
                                times: count)
            }
            resetPending()
            return
        }
        if ch.isNumber, ch != "0"
            || (ch == "0" && !pendingCount.isEmpty) {
            pendingCount.append(ch)
            return
        }
        let times = count
        switch ch {
        case "h":
            buffer.col = max(0, col - times)
        case "l":
            buffer.col = col + times
            clampCursor()
        case "j":
            buffer.row = min(buffer.lines.count - 1,
                             row + times)
            clampCursor()
        case "k":
            buffer.row = max(0, row - times)
            clampCursor()
        case "0":
            buffer.col = 0
        case "^":
            buffer.col = firstNonBlankOf(row)
        case "$":
            buffer.col = buffer.lines[row].count
            clampCursor()
        case "w":
            var spot = (row, col)
            for _ in 0..<times {
                spot = wordStep(from: spot.0,
                                spot.1,
                                forward: true)
            }
            buffer.row = spot.0
            buffer.col = spot.1
            clampCursor()
        case "b":
            var spot = (row, col)
            for _ in 0..<times {
                spot = wordStep(from: spot.0,
                                spot.1,
                                forward: false)
            }
            buffer.row = spot.0
            buffer.col = spot.1
            clampCursor()
        case "e":
            var spot = (row, col)
            for _ in 0..<times {
                spot = wordEnd(from: spot.0,
                               spot.1)
            }
            buffer.row = spot.0
            buffer.col = spot.1
            clampCursor()
        case "g":
            if pendingCount == "g" {
                pendingCount = ""
                buffer.row = 0
                buffer.col = firstNonBlankOf(0)
            } else {
                pendingCount = "g"
                return
            }
        case "G":
            let target = pendingCount.isEmpty
                ? buffer.lines.count - 1
                : min(buffer.lines.count - 1,
                      times - 1)
            buffer.row = target
            buffer.col = firstNonBlankOf(target)
        case "x":
            pushUndo()
            let start = cursorOffset()
            let removed = deleteOffsets(
                start, min(start + times,
                           blobText().count))
            if !removed.isEmpty {
                killRing.insert((removed, false),
                                at: 0)
            }
            clampCursor()
        case "X":
            pushUndo()
            let end = cursorOffset()
            let start = max(0, end - times)
            if end > start {
                let removed = deleteOffsets(
                    start, end)
                killRing.insert((removed, false),
                                at: 0)
            }
        case "d", "y":
            if vimMode == .visual {
                visualOperation(ch)
            } else {
                pendingOp = ch
                return
            }
        case "D":
            pushUndo()
            let start = cursorOffset()
            let end = offset(ofRow: row,
                             col: buffer.lines[row]
                                .count)
            let removed = deleteOffsets(start, end)
            if !removed.isEmpty {
                killRing.insert((removed, false),
                                at: 0)
            }
        case "C":
            pushUndo()
            let start = cursorOffset()
            let end = offset(ofRow: row,
                             col: buffer.lines[row]
                                .count)
            _ = deleteOffsets(start, end)
            vimMode = .insert
        case "p":
            paste(after: true, times: times)
        case "P":
            paste(after: false, times: times)
        case "u":
            undo()
        case "i":
            vimMode = .insert
        case "a":
            buffer.col = min(
                buffer.lines[row].count, col + 1)
            vimMode = .insert
        case "A":
            buffer.col = buffer.lines[row].count
            vimMode = .insert
        case "I":
            buffer.col = firstNonBlankOf(row)
            vimMode = .insert
        case "o":
            pushUndo()
            buffer.lines.insert(
                "", at: row + 1)
            buffer.row = row + 1
            buffer.col = 0
            buffer.dirty = true
            vimMode = .insert
        case "O":
            pushUndo()
            buffer.lines.insert("", at: row)
            buffer.col = 0
            buffer.dirty = true
            vimMode = .insert
        case "v":
            if vimMode == .visual {
                vimMode = .normal
                visualAnchor = nil
            } else {
                vimMode = .visual
                visualAnchor = (row, col)
            }
        case "/":
            miniAsk(prompt: "/") { [weak self] pat in
                self?.runSearch(pat, forward: true)
            }
            resetPending()
            return
        case "?":
            miniAsk(prompt: "?") { [weak self] pat in
                self?.runSearch(pat, forward: false)
            }
            resetPending()
            return
        case "n":
            runSearch(searchPattern,
                      forward: searchForward,
                      repeatSearch: true)
        case "N":
            runSearch(searchPattern,
                      forward: !searchForward,
                      repeatSearch: true)
        case ":":
            miniAsk(prompt: ":") { [weak self] cmd in
                self?.vimCommand(cmd)
            }
            resetPending()
            return
        case "r":
            pendingOp = "r"
            return
        case "~":
            pushUndo()
            toggleCaseAtCursor()
        default:
            message = ""
        }
        resetPending()
        renderTick += 1
    }

    private func toggleCaseAtCursor() {
        var chars = Array(blobText())
        let at = cursorOffset()
        guard at < chars.count else { return }
        let ch = chars[at]
        if ch.isUppercase {
            chars[at] = Character(
                ch.lowercased())
        } else if ch.isLowercase {
            chars[at] = Character(
                ch.uppercased())
        }
        setBlob(String(chars),
                cursorOffset: min(at + 1,
                                  chars.count))
    }

    private func lineOperation(_ op: Character,
                               times: Int) {
        let startRow = row
        let endRow = min(buffer.lines.count - 1,
                         row + times - 1)
        let yanked = buffer.lines[startRow...endRow]
            .joined(separator: "\n")
        killRing.insert((yanked, true), at: 0)
        if op == "d" {
            pushUndo()
            buffer.lines.removeSubrange(
                startRow...endRow)
            if buffer.lines.isEmpty {
                buffer.lines = [""]
            }
            buffer.row = min(startRow,
                             buffer.lines.count - 1)
            buffer.col = firstNonBlankOf(buffer.row)
            buffer.dirty = true
        }
        renderTick += 1
    }

    private func motionOperation(_ op: Character,
                                 motion: Character,
                                 times: Int) {
        if op == "r" {
            // r{char}: replace the character
            // under the cursor.
            pushUndo()
            var chars = Array(blobText())
            let at = cursorOffset()
            guard at < chars.count else { return }
            chars[at] = motion
            setBlob(String(chars),
                    cursorOffset: at)
            renderTick += 1
            return
        }
        let from = cursorOffset()
        var to = from
        var inclusive = false
        switch motion {
        case "w":
            var spot = (row, col)
            for _ in 0..<times {
                spot = wordStep(from: spot.0,
                                spot.1,
                                forward: true)
            }
            to = offset(ofRow: spot.0, col: spot.1)
        case "e":
            var spot = (row, col)
            for _ in 0..<times {
                spot = wordEnd(from: spot.0,
                               spot.1)
            }
            to = offset(ofRow: spot.0, col: spot.1)
            inclusive = true
        case "$":
            to = offset(ofRow: row,
                        col: buffer.lines[row].count)
            inclusive = false
        case "0", "^":
            let targetCol = motion == "0"
                ? 0 : firstNonBlankOf(row)
            to = offset(ofRow: row, col: targetCol)
        case "l":
            to = min(blobText().count, from + times)
        case "h":
            to = max(0, from - times)
        default:
            message = "no motion \(motion) "
                + "for \(op)"
            return
        }
        let start = min(from, to)
        var end = max(from, to)
        if inclusive { end = min(end + 1,
                                 blobText().count) }
        guard end > start else { return }
        if op == "y" {
            let text = yankOffsets(start, end)
            killRing.insert((text, false), at: 0)
            message = "yanked \(text.count) chars"
        } else {
            pushUndo()
            let removed = deleteOffsets(start, end)
            killRing.insert((removed, false),
                            at: 0)
        }
        renderTick += 1
    }

    private func visualOperation(_ op: Character) {
        guard let anchor = visualAnchor else {
            return
        }
        let a = offset(ofRow: anchor.0,
                       col: anchor.1)
        let b = cursorOffset()
        let start = min(a, b)
        let end = max(a, b) + 1
        if op == "y" {
            let text = yankOffsets(
                start, min(end, blobText().count))
            killRing.insert((text, false), at: 0)
            message = "yanked \(text.count) chars"
        } else {
            pushUndo()
            let removed = deleteOffsets(
                start, min(end, blobText().count))
            killRing.insert((removed, false),
                            at: 0)
        }
        vimMode = .normal
        visualAnchor = nil
        renderTick += 1
    }

    private func paste(after: Bool, times: Int) {
        guard let yank = killRing.first else {
            message = "nothing yanked"
            return
        }
        pushUndo()
        if yank.lineWise {
            let rows = yank.text.components(
                separatedBy: "\n")
            var block: [String] = []
            for _ in 0..<times { block += rows }
            let at = after ? row + 1 : row
            buffer.lines.insert(
                contentsOf: block, at: at)
            buffer.row = at
            buffer.col = firstNonBlankOf(at)
            buffer.dirty = true
        } else {
            let text = String(
                repeating: yank.text, count: times)
            let at = after
                ? min(cursorOffset() + 1,
                      blobText().count)
                : cursorOffset()
            insertAtOffset(text, offset: at)
            buffer.col = max(0, col - 1)
            clampCursor()
        }
        renderTick += 1
    }

    private func runSearch(_ pattern: String,
                           forward: Bool,
                           repeatSearch: Bool = false) {
        guard !pattern.isEmpty else {
            message = "no pattern"
            return
        }
        if !repeatSearch {
            searchPattern = pattern
            searchForward = forward
        }
        let blob = blobText()
        let insensitive = pattern.lowercased()
            == pattern
        let haystack = insensitive
            ? blob.lowercased() : blob
        let needle = insensitive
            ? pattern.lowercased() : pattern
        let here = cursorOffset()
        var found: Int?
        if forward {
            let start = min(here + 1,
                            haystack.count)
            let tail = String(
                haystack.dropFirst(start))
            if let range = tail.range(
                of: needle) {
                found = start + tail.distance(
                    from: tail.startIndex,
                    to: range.lowerBound)
            } else if let range = haystack.range(
                of: needle) {
                found = haystack.distance(
                    from: haystack.startIndex,
                    to: range.lowerBound)
            }
        } else {
            let head = String(haystack.prefix(here))
            if let range = head.range(
                of: needle,
                options: .backwards) {
                found = head.distance(
                    from: head.startIndex,
                    to: range.lowerBound)
            } else if let range = haystack.range(
                of: needle, options: .backwards) {
                found = haystack.distance(
                    from: haystack.startIndex,
                    to: range.lowerBound)
            }
        }
        if let found = found {
            let spot = position(ofOffset: found,
                                in: buffer.lines)
            buffer.row = spot.0
            buffer.col = spot.1
            message = ""
        } else {
            message = "not found: \(pattern)"
        }
        renderTick += 1
    }

    private func vimCommand(_ raw: String) {
        let cmd = raw.trimmingCharacters(
            in: .whitespaces)
        guard !cmd.isEmpty else { return }
        if let number = Int(cmd) {
            let target = min(buffer.lines.count - 1,
                             max(0, number - 1))
            buffer.row = target
            buffer.col = firstNonBlankOf(target)
            renderTick += 1
            return
        }
        let parts = cmd.split(separator: " ",
                              maxSplits: 1)
            .map(String.init)
        let head = parts.first ?? ""
        let rest = parts.count > 1 ? parts[1] : ""
        switch head {
        case "w":
            if !rest.isEmpty {
                buffer.path = BlacksiteFS
                    .normalize(rest,
                               cwd: BlacksiteFS.home)
                buffer.name = BlacksiteFS.baseName(
                    of: rest)
            }
            saveBuffer()
        case "q":
            quitBuffer(force: false)
        case "q!":
            quitBuffer(force: true)
        case "wq", "x":
            if saveBuffer() {
                quitBuffer(force: true)
            }
        case "e":
            if !rest.isEmpty {
                open(path: rest, personality: nil)
            } else {
                message = ":e needs a file"
            }
        case "bn":
            current = (current + 1)
                % buffers.count
            renderTick += 1
        case "bp":
            current = (current + buffers.count - 1)
                % buffers.count
            renderTick += 1
        case "ls", "buffers":
            listBuffers()
        case "set":
            if rest.contains("nonu") {
                showNumbers = false
            } else if rest.contains("nu") {
                showNumbers = true
            }
        case "help":
            openTextBuffer(name: "*help*",
                           text: Self.helpText)
        case "emacs":
            personality = .emacs
            message = "emacs, then. C-x C-s "
                + "saves · C-x C-c leaves · "
                + "M-x vim comes back"
        case "nano":
            personality = .nano
            message = "nano, then. ^O "
                + "saves · ^X leaves · "
                + "^G lists the keys"
        default:
            if head.hasPrefix("%s/")
                || head.hasPrefix("s/") {
                substitute(cmd)
            } else {
                message = "not an editor "
                    + "command: \(head)"
            }
        }
        renderTick += 1
    }

    private func quitBuffer(force: Bool) {
        if buffer.dirty && !force {
            message = "no write since last "
                + "change (add ! to override)"
            return
        }
        if buffers.count > 1 {
            killCurrentBuffer()
        } else {
            onExit?()
        }
    }

    private func substitute(_ cmd: String) {
        let all = cmd.hasPrefix("%s/")
        let body = all
            ? String(cmd.dropFirst(3))
            : String(cmd.dropFirst(2))
        let fields = body.split(
            separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count >= 2 else {
            message = "use :%s/old/new/g"
            return
        }
        let old = fields[0]
        let new = fields.count > 1 ? fields[1] : ""
        let global = fields.count > 2
            && fields[2].contains("g")
        guard !old.isEmpty else { return }
        pushUndo()
        if all {
            var blob = blobText()
            var hits = 0
            if global {
                while let range = blob.range(
                    of: old) {
                    blob.replaceSubrange(
                        range, with: new)
                    hits += 1
                    if hits > 10000 { break }
                }
            } else {
                var rows = buffer.lines
                for index in rows.indices {
                    if let range = rows[
                        index].range(of: old) {
                        rows[index]
                            .replaceSubrange(
                                range, with: new)
                        hits += 1
                    }
                }
                if hits > 0 {
                    buffer.lines = rows
                    buffer.dirty = true
                }
                message = "\(hits) substitutions"
                renderTick += 1
                return
            }
            setBlob(blob, cursorOffset:
                        min(cursorOffset(),
                            blob.count))
            message = "\(hits) substitutions"
        } else {
            var line = buffer.lines[row]
            var hits = 0
            if global {
                while let range = line.range(
                    of: old) {
                    line.replaceSubrange(
                        range, with: new)
                    hits += 1
                    if hits > 10000 { break }
                }
            } else if let range = line.range(
                of: old) {
                line.replaceSubrange(range,
                                     with: new)
                hits = 1
            }
            if hits > 0 {
                replaceLineFromEditor(row,
                                      with: line)
            }
            message = "\(hits) substitutions"
        }
        renderTick += 1
    }

    private func replaceLineFromEditor(
        _ index: Int, with text: String) {
        guard buffer.lines.indices.contains(index)
        else { return }
        buffer.lines[index] = text
        buffer.dirty = true
    }

    static var helpText: String { """
VIM — the modal church
  h j k l move · w b e words · 0 ^ $ line
  i a A I insert · o O open line · v visual
  d y operators: dd yy dw yw d$ y$ · x X
  p P paste · u undo · ~ toggle case
  / ? search · n N next · : the ex line
  :w write · :q quit · :wq both · :q! force
  :e file · :bn :bp buffers · :ls list
  :%s/old/new/g substitute · :42 line 42
  :set nu / nonu · :emacs the other church

EMACS — the chord church (M-x emacs)
  C-a C-e line ends · C-b C-f C-n C-p move
  C-d delete · C-k kill line · C-y yank
  C-SPC mark · C-w kill region · M-w copy
  C-_ undo · C-s search · C-g quit/quit
  C-x C-s save · C-x C-f open · C-x b buffer
  C-x k kill buffer · C-x C-b list buffers
  M-x commands: save-buffer, goto-line,
  replace-string, list-buffers, vim, help
"""
    }
}


// MARK: - EMACS

extension EditorCore {
    /// The display reports a tap-moved
    /// cursor: follow it without editing.
    func syncCursor(offset: Int) {
        let spot = position(ofOffset: offset,
                            in: buffer.lines)
        if spot.0 != row || spot.1 != col {
            buffer.row = spot.0
            buffer.col = spot.1
        }
    }

    /// What the display should select: the
    /// region when a mark or a visual
    /// selection lives, a block in vim
    /// normal mode, else the bare point.
    func selectionRange() -> (start: Int,
                              length: Int) {
        if personality == .emacs, markActive,
           let mark = mark {
            let a = offset(ofRow: mark.0,
                           col: mark.1)
            let b = cursorOffset()
            return (min(a, b), abs(a - b))
        }
        if personality == .vim {
            if vimMode == .visual,
               let anchor = visualAnchor {
                let a = offset(ofRow: anchor.0,
                               col: anchor.1)
                let b = cursorOffset()
                return (min(a, b),
                        abs(a - b) + 1)
            }
            if vimMode == .normal {
                let line = buffer.lines[row]
                return (cursorOffset(),
                        col < line.count ? 1 : 0)
            }
        }
        return (cursorOffset(), 0)
    }

    func emacsKey(_ key: EditorKey) {
        if ctrlXPending {
            ctrlXPending = false
            emacsCtrlX(key)
            return
        }
        switch key {
        case .char(let ch):
            pushUndo(coalesce: true)
            insertAtOffset(String(ch),
                           offset: cursorOffset())
            lastKill = false
            renderTick += 1
        case .enter:
            pushUndo()
            insertAtOffset("\n",
                           offset: cursorOffset())
            lastKill = false
            renderTick += 1
        case .backspace:
            let end = cursorOffset()
            if end > 0 {
                pushUndo(coalesce: true)
                deleteOffsets(end - 1, end)
            }
            lastKill = false
            renderTick += 1
        case .tab:
            pushUndo(coalesce: true)
            insertAtOffset("    ",
                           offset: cursorOffset())
            lastKill = false
            renderTick += 1
        case .escape:
            // ESC is meta in this church.
            altLatch = true
            message = "M-"
        case .arrow(let dir):
            emacsMove(dir)
            lastKill = false
        case .ctrl(let ch):
            emacsCtrl(ch)
        case .alt(let ch):
            emacsAlt(ch)
        }
    }

    private func emacsMove(_ dir: String) {
        switch dir {
        case "left":
            movePoint(byChars: -1)
            return
        case "right":
            movePoint(byChars: 1)
            return
        case "up":
            if row > 0 {
                buffer.row = row - 1
                clampCursor()
            }
        case "down":
            if row + 1 < buffer.lines.count {
                buffer.row = row + 1
                clampCursor()
            }
        default:
            break
        }
        renderTick += 1
    }

    private func movePoint(byChars delta: Int) {
        let target = max(
            0, min(blobText().count,
                   cursorOffset() + delta))
        let spot = position(ofOffset: target,
                            in: buffer.lines)
        buffer.row = spot.0
        buffer.col = spot.1
        renderTick += 1
    }

    private func setMarkHere() {
        mark = (row, col)
        markActive = true
        message = "mark set"
    }

    private func regionOffsets() -> (Int, Int)? {
        guard let mark = mark else { return nil }
        let a = offset(ofRow: mark.0, col: mark.1)
        let b = cursorOffset()
        return (min(a, b), max(a, b))
    }

    private func killRange(_ start: Int,
                           _ end: Int,
                           copyOnly: Bool = false) {
        guard end > start else {
            message = "nothing there"
            return
        }
        let text = yankOffsets(start, end)
        if lastKill, !killRing.isEmpty {
            killRing[0] = (killRing[0].text + text,
                           false)
        } else {
            killRing.insert((text, false), at: 0)
        }
        lastKill = true
        if !copyOnly {
            pushUndo()
            deleteOffsets(start, end)
        }
        renderTick += 1
    }

    private func emacsCtrl(_ ch: Character) {
        if ch != "k" && ch != "w" {
            lastKill = false
        }
        switch ch {
        case "a":
            buffer.col = 0
        case "e":
            buffer.col = buffer.lines[row].count
        case "b":
            movePoint(byChars: -1)
            return
        case "f":
            movePoint(byChars: 1)
            return
        case "n":
            if row + 1 < buffer.lines.count {
                buffer.row = row + 1
                clampCursor()
            }
        case "p":
            if row > 0 {
                buffer.row = row - 1
                clampCursor()
            }
        case "d":
            let at = cursorOffset()
            if at < blobText().count {
                pushUndo()
                deleteOffsets(at, at + 1)
            }
        case "k":
            killLine()
            return
        case "y":
            if let yank = killRing.first {
                pushUndo()
                insertAtOffset(
                    yank.text,
                    offset: cursorOffset())
            } else {
                message = "kill ring empty"
            }
        case "w":
            if let region = regionOffsets() {
                killRange(region.0, region.1)
                markActive = false
            } else {
                message = "mark not set — "
                    + "C-SPC sets it"
            }
            return
        case " ", "@":
            setMarkHere()
        case "_", "/":
            undo()
            return
        case "s":
            startIsearch()
            return
        case "g":
            ctrlXPending = false
            markActive = false
            message = "quit"
        case "x":
            ctrlXPending = true
            message = "C-x-"
            return
        case "v":
            buffer.row = min(
                buffer.lines.count - 1, row + 10)
            clampCursor()
        case "l":
            break
        default:
            message = "C-\(ch) is undefined"
        }
        renderTick += 1
    }

    private func killLine() {
        let line = buffer.lines[row]
        if col < line.count {
            let start = cursorOffset()
            killRange(start,
                      start + (line.count - col))
        } else if row + 1 < buffer.lines.count {
            let at = cursorOffset()
            pushUndo()
            if lastKill, !killRing.isEmpty {
                killRing[0] = (killRing[0].text
                               + "\n", false)
            } else {
                killRing.insert(("\n", false),
                                at: 0)
            }
            lastKill = true
            deleteOffsets(at, at + 1)
        } else {
            message = "end of buffer"
        }
        renderTick += 1
    }

    private func startIsearch() {
        let origin = (row, col)
        miniAsk(prompt: "I-search: ",
                onChange: { [weak self] text in
            guard let self = self,
                  !text.isEmpty else { return }
            let blob = self.blobText()
            let from = self.offset(
                ofRow: origin.0, col: origin.1)
            let tail = blob.dropFirst(
                min(from, blob.count))
            if let range = tail.range(of: text) {
                let at = from + tail.distance(
                    from: tail.startIndex,
                    to: range.lowerBound)
                let spot = self.position(
                    ofOffset: at,
                    in: self.buffer.lines)
                self.buffer.row = spot.0
                self.buffer.col = spot.1
                self.renderTick += 1
            }
        }) { _ in }
    }

    private func emacsCtrlX(_ key: EditorKey) {
        switch key {
        case .ctrl(let ch) where ch == "s":
            saveBuffer()
        case .char(let ch) where ch == "s":
            saveBuffer()
        case .ctrl(let ch) where ch == "c":
            emacsQuit()
        case .char(let ch) where ch == "c":
            emacsQuit()
        case .ctrl(let ch) where ch == "f":
            findFile()
        case .char(let ch) where ch == "f":
            findFile()
        case .char(let ch) where ch == "k":
            if buffer.dirty, !killPending {
                killPending = true
                message = "unsaved — C-x k "
                    + "again to kill it anyway"
            } else {
                killPending = false
                killCurrentBuffer()
            }
        case .char(let ch) where ch == "b":
            miniAsk(prompt: "Buffer: "
            ) { [weak self] name in
                self?.switchBuffer(named: name)
            }
        case .ctrl(let ch) where ch == "b":
            listBuffers()
        case .char(let ch) where ch == "u":
            undo()
        default:
            message = "C-x undefined"
        }
        renderTick += 1
    }

    private func findFile() {
        miniAsk(prompt: "Find file: ",
                seed: "/home/"
        ) { [weak self] path in
            self?.open(path: path,
                       personality: nil)
        }
    }

    private func emacsQuit() {
        if buffer.dirty, !quitPending {
            quitPending = true
            message = "unsaved changes — "
                + "C-x C-s saves; C-x C-c "
                + "again leaves anyway"
            return
        }
        quitPending = false
        if buffers.count > 1 {
            killCurrentBuffer()
        } else {
            onExit?()
        }
    }

    private func emacsAlt(_ ch: Character) {
        lastKill = false
        switch ch {
        case "w":
            if let region = regionOffsets() {
                killRange(region.0, region.1,
                          copyOnly: true)
                lastKill = false
                message = "copied"
            } else {
                message = "mark not set"
            }
        case "x":
            miniAsk(prompt: "M-x "
            ) { [weak self] name in
                self?.mxCommand(name)
            }
        case "<":
            buffer.row = 0
            buffer.col = 0
        case ">":
            buffer.row = buffer.lines.count - 1
            buffer.col = buffer.lines[
                buffer.row].count
        case "b":
            let spot = wordStep(from: row, col,
                                forward: false)
            buffer.row = spot.0
            buffer.col = spot.1
        case "f":
            let spot = wordStep(from: row, col,
                                forward: true)
            buffer.row = spot.0
            buffer.col = spot.1
        case "d":
            let spot = wordEnd(from: row, col)
            let end = offset(ofRow: spot.0,
                             col: spot.1)
            killRange(cursorOffset(),
                      min(end + 1,
                          blobText().count))
            return
        case "v":
            buffer.row = max(0, row - 10)
            clampCursor()
        default:
            message = "M-\(ch) is undefined"
        }
        renderTick += 1
    }

    private func mxCommand(_ raw: String) {
        let name = raw.trimmingCharacters(
            in: .whitespaces).lowercased()
        switch name {
        case "save-buffer":
            saveBuffer()
        case "kill-buffer":
            killCurrentBuffer()
        case "list-buffers":
            listBuffers()
        case "goto-line":
            miniAsk(prompt: "Line: "
            ) { [weak self] text in
                guard let self = self,
                      let number = Int(text)
                else { return }
                let target = min(
                    self.buffer.lines.count - 1,
                    max(0, number - 1))
                self.buffer.row = target
                self.buffer.col = 0
                self.renderTick += 1
            }
        case "replace-string":
            miniAsk(prompt: "Replace: "
            ) { [weak self] old in
                guard let self = self,
                      !old.isEmpty else { return }
                self.miniAsk(
                    prompt: "With: "
                ) { [weak self] new in
                    guard let self = self
                    else { return }
                    self.pushUndo()
                    var blob = self.blobText()
                    var hits = 0
                    while let range = blob.range(
                        of: old) {
                        blob.replaceSubrange(
                            range, with: new)
                        hits += 1
                        if hits > 10000 { break }
                    }
                    self.setBlob(
                        blob, cursorOffset: 0)
                    self.message = "\(hits) "
                        + "replacements"
                    self.renderTick += 1
                }
            }
        case "set-mark":
            setMarkHere()
        case "vim":
            personality = .vim
            vimMode = .normal
            message = "vim, then. the modes "
                + "are home here"
        case "nano":
            personality = .nano
            message = "nano, then. ^O "
                + "saves · ^X leaves"
        case "help":
            openTextBuffer(name: "*help*",
                           text: Self.helpText)
        case "":
            break
        default:
            message = "no M-x command "
                + "named \(name)"
        }
        renderTick += 1
    }
}

// MARK: - The editor room

// MARK: - NANO

extension EditorCore {
    /// The third church: no modes at all.
    /// You type, it types. The control
    /// chords do the rest, like the little
    /// editor every server already has.
    func nanoKey(_ key: EditorKey) {
        switch key {
        case .char(let ch):
            pushUndo(coalesce: true)
            insertAtOffset(String(ch),
                           offset: cursorOffset())
            lastKill = false
        case .enter:
            pushUndo()
            insertAtOffset("\n",
                           offset: cursorOffset())
            lastKill = false
        case .backspace:
            let end = cursorOffset()
            if end > 0 {
                pushUndo(coalesce: true)
                deleteOffsets(end - 1, end)
            }
            lastKill = false
        case .tab:
            pushUndo(coalesce: true)
            insertAtOffset("    ",
                           offset: cursorOffset())
            lastKill = false
        case .arrow(let dir):
            moveArrow(dir)
            return
        case .escape:
            message = ""
        case .ctrl(let ch):
            nanoCtrl(ch)
            return
        case .alt:
            break
        }
        renderTick += 1
    }

    private func nanoCtrl(_ ch: Character) {
        switch ch {
        case "o":
            saveBuffer()
        case "x":
            nanoExit()
            return
        case "k":
            pushUndo()
            killLine()
            lastKill = true
        case "u":
            if let top = killRing.first {
                pushUndo()
                insertAtOffset(top.0,
                               offset: cursorOffset())
            }
            lastKill = false
        case "w":
            miniAsk(prompt: "Search: ") {
                [weak self] pat in
                self?.runSearch(pat,
                                forward: true)
            }
            return
        case "g":
            message = "^O write out · ^X "
                + "exit · ^K cut line · "
                + "^U paste · ^W find · "
                + "^C where am I"
        case "c":
            message = "line \(row + 1) of "
                + "\(buffer.lines.count), "
                + "column \(col + 1)"
        case "a":
            buffer.col = 0
        case "e":
            buffer.col = buffer.lines[row]
                .count
        case "y":
            buffer.row = max(0, row - 10)
            clampCursor()
        case "v":
            buffer.row = min(
                buffer.lines.count - 1,
                row + 10)
            clampCursor()
        case "_", "/":
            undo()
        default:
            message = "^\(ch) is undefined "
                + "— ^G lists the keys"
        }
        renderTick += 1
    }

    private func nanoExit() {
        guard buffer.dirty else {
            onExit?()
            return
        }
        guard buffer.path != nil else {
            message = "unsaved — ^O names "
                + "and writes it first"
            return
        }
        miniAsk(prompt: "Save before "
                + "exit? (y/n) ") {
            [weak self] answer in
            guard let self = self else {
                return
            }
            let reply = answer.lowercased()
            if reply.hasPrefix("y") {
                if self.saveBuffer() {
                    self.onExit?()
                }
            } else if reply
                .hasPrefix("n") {
                self.onExit?()
            }
        }
    }
}

struct BlacksiteEditorView: View {
    @StateObject private var core: EditorCore
    private let path: String?
    private let onClose: () -> Void
    @State private var confirmClose = false
    @ObservedObject private var themes =
        ThemeCenter.shared

    init(path: String?,
         personality: EditorPersonality,
         onClose: @escaping () -> Void) {
        self.path = path
        self.onClose = onClose
        _core = StateObject(wrappedValue:
            EditorCore(personality: personality))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                statusBar
#if os(iOS)
                EditorTextView(core: core)
#else
                MacEditorFallback(core: core)
#endif
                miniBar
            }
        }
        .onAppear {
            core.onExit = onClose
            core.open(path: path,
                      personality: nil)
        }
        .confirmationDialog(
            "Unsaved changes",
            isPresented: $confirmClose,
            titleVisibility: .visible) {
            Button("Save and close") {
                if core.saveBuffer() {
                    onClose()
                }
            }
            Button("Discard changes",
                   role: .destructive) {
                onClose()
            }
            Button("Keep editing",
                   role: .cancel) {}
        } message: {
            Text("This buffer holds work that is not written yet.")
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(core.personality == .vim
                 ? "VIM"
                 : core.personality == .emacs
                 ? "EMACS" : "NANO")
                .font(.system(.caption,
                              design: .monospaced)
                    .weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(
                        cornerRadius: 5)
                        .fill(themes.current.accent))
            Text(core.statusLeft)
                .font(.system(.caption,
                              design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Text(core.statusRight)
                .font(.system(.caption,
                              design: .monospaced))
                .foregroundStyle(.secondary)
            if core.bufferDirty {
                Button {
                    Haptics.tap()
                    _ = core.saveBuffer()
                } label: {
                    Text("SAVE")
                        .font(.system(
                            .caption,
                            design: .monospaced)
                            .weight(.bold))
                        .foregroundStyle(
                            themes.current.accent)
                }
            }
            Button {
                Haptics.tap()
                if core.bufferDirty {
                    confirmClose = true
                } else {
                    onClose()
                }
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06))
    }

    private var miniBar: some View {
        HStack {
            Text(core.miniPrompt != nil
                 ? core.miniDisplay
                 : core.message)
                .font(.system(.caption,
                              design: .monospaced))
                .foregroundStyle(
                    core.miniPrompt != nil
                    ? themes.current.accent
                    : Color.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .frame(minHeight: 30)
    }
}

#if os(iOS)
// MARK: - The canvas (UITextView)

private struct EditorTextView:
    UIViewRepresentable {
    @ObservedObject var core: EditorCore

    func makeCoordinator() -> Coordinator {
        Coordinator(core: core)
    }

    func makeUIView(context: Context)
        -> EditorCanvas {
        let canvas = EditorCanvas()
        canvas.core = core
        canvas.delegate = context.coordinator
        canvas.font = UIFont.monospacedSystemFont(
            ofSize: 14, weight: .regular)
        canvas.textColor = .white
        canvas.backgroundColor = .black
        canvas.autocorrectionType = .no
        canvas.autocapitalizationType = .none
        canvas.smartQuotesType = .no
        canvas.smartDashesType = .no
        canvas.spellCheckingType = .no
        canvas.keyboardAppearance = .dark
        canvas.textContainerInset = UIEdgeInsets(
            top: 10, left: 50, bottom: 10,
            right: 8)
        canvas.buildAccessory()
        context.coordinator.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: EditorCanvas,
                      context: Context) {
        canvas.core = core
        let coordinator = context.coordinator
        if coordinator.lastTick != core.renderTick
            || canvas.text != core.blobText() {
            coordinator.syncing = true
            if canvas.text != core.blobText() {
                canvas.text = core.blobText()
            }
            let selection = core.selectionRange()
            canvas.selectedRange = NSRange(
                location: selection.start,
                length: selection.length)
            coordinator.lastTick = core.renderTick
            coordinator.syncing = false
            canvas.setNeedsDisplay()
        }
        canvas.refreshAccessory()
    }

    final class Coordinator: NSObject,
        UITextViewDelegate {
        let core: EditorCore
        weak var canvas: EditorCanvas?
        var lastTick = -1
        var syncing = false

        init(core: EditorCore) {
            self.core = core
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String) -> Bool {
            if core.miniPrompt != nil {
                if text.isEmpty {
                    core.backspaceAsKey()
                } else if text == "\n" {
                    core.handle(.enter)
                } else if text == "\t" {
                    core.handle(.tab)
                } else {
                    core.typeAsKey(text)
                }
                return false
            }
            if core.typingAllowed() {
                return true
            }
            if text.isEmpty {
                core.backspaceAsKey()
            } else if text == "\n" {
                core.handle(.enter)
            } else if text == "\t" {
                core.handle(.tab)
            } else {
                core.typeAsKey(text)
            }
            return false
        }

        func textViewDidChange(
            _ textView: UITextView) {
            guard !syncing else { return }
            core.syncFromDisplay(
                text: textView.text ?? "",
                cursorOffset:
                    textView.selectedRange.location)
            canvas?.setNeedsDisplay()
        }

        func textViewDidChangeSelection(
            _ textView: UITextView) {
            guard !syncing else { return }
            core.syncCursor(
                offset: textView.selectedRange
                    .location)
        }

        func scrollViewDidScroll(
            _ scrollView: UIScrollView) {
            canvas?.setNeedsDisplay()
        }
    }
}

private final class EditorCanvas: UITextView {
    weak var core: EditorCore?
    private var ctrlButton: UIButton?
    private var altButton: UIButton?

    // The extra key row: ESC, the latches,
    // TAB and the arrows, so every chord of
    // both churches is reachable on glass.
    func buildAccessory() {
        let bar = UIView(frame: CGRect(
            x: 0, y: 0, width: 320, height: 46))
        bar.backgroundColor = UIColor(
            white: 0.1, alpha: 1)
        let keys: [(String, Selector)] = [
            ("ESC", #selector(keyEscape)),
            ("CTRL", #selector(keyCtrl)),
            ("ALT", #selector(keyAlt)),
            ("TAB", #selector(keyTab)),
            ("←", #selector(keyLeft)),
            ("↑", #selector(keyUp)),
            ("↓", #selector(keyDown)),
            ("→", #selector(keyRight)),
        ]
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints
            = false
        for (title, action) in keys {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white,
                                 for: .normal)
            button.titleLabel?.font =
                UIFont.monospacedSystemFont(
                    ofSize: 13, weight: .semibold)
            button.backgroundColor = UIColor(
                white: 0.2, alpha: 1)
            button.layer.cornerRadius = 7
            button.addTarget(self, action: action,
                             for: .touchUpInside)
            if title == "CTRL" {
                ctrlButton = button
            }
            if title == "ALT" {
                altButton = button
            }
            stack.addArrangedSubview(button)
        }
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: bar.leadingAnchor,
                constant: 8),
            stack.trailingAnchor.constraint(
                equalTo: bar.trailingAnchor,
                constant: -8),
            stack.topAnchor.constraint(
                equalTo: bar.topAnchor,
                constant: 6),
            stack.bottomAnchor.constraint(
                equalTo: bar.bottomAnchor,
                constant: -6),
        ])
        inputAccessoryView = bar
    }

    func refreshAccessory() {
        ctrlButton?.backgroundColor =
            core?.ctrlLatch == true
            ? UIColor.systemOrange
            : UIColor(white: 0.2, alpha: 1)
        altButton?.backgroundColor =
            core?.altLatch == true
            ? UIColor.systemOrange
            : UIColor(white: 0.2, alpha: 1)
    }

    @objc private func keyEscape() {
        core?.handle(.escape)
    }
    @objc private func keyCtrl() {
        core?.ctrlLatch.toggle()
        refreshAccessory()
    }
    @objc private func keyAlt() {
        core?.altLatch.toggle()
        refreshAccessory()
    }
    @objc private func keyTab() {
        core?.handle(.tab)
    }
    @objc private func keyLeft() {
        core?.handle(.arrow("left"))
    }
    @objc private func keyUp() {
        core?.handle(.arrow("up"))
    }
    @objc private func keyDown() {
        core?.handle(.arrow("down"))
    }
    @objc private func keyRight() {
        core?.handle(.arrow("right"))
    }

    // Hardware keyboards: ESC, the arrows,
    // and the chord letters, both churches.
    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = [
            UIKeyCommand(
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                action: #selector(keyEscape)),
        ]
        let arrows: [(String, Selector)] = [
            (UIKeyCommand.inputUpArrow,
             #selector(keyUp)),
            (UIKeyCommand.inputDownArrow,
             #selector(keyDown)),
            (UIKeyCommand.inputLeftArrow,
             #selector(keyLeft)),
            (UIKeyCommand.inputRightArrow,
             #selector(keyRight)),
        ]
        for (input, action) in arrows {
            commands.append(UIKeyCommand(
                input: input, modifierFlags: [],
                action: action))
        }
        for letter in "abcdefghijklmnopqrstuvwxyz_/" {
            commands.append(UIKeyCommand(
                input: String(letter),
                modifierFlags: .control,
                action: #selector(keyCtrlLetter(_:))))
        }
        commands.append(UIKeyCommand(
            input: " ", modifierFlags: .control,
            action: #selector(keyCtrlLetter(_:))))
        for letter in "wxdfb<>" {
            commands.append(UIKeyCommand(
                input: String(letter),
                modifierFlags: .alternate,
                action: #selector(keyAltLetter(_:))))
        }
        return commands
    }

    @objc private func keyCtrlLetter(
        _ command: UIKeyCommand) {
        guard let input = command.input,
              let ch = input.first else { return }
        core?.handle(.ctrl(ch))
    }

    @objc private func keyAltLetter(
        _ command: UIKeyCommand) {
        guard let input = command.input,
              let ch = input.first else { return }
        core?.handle(.alt(ch))
    }

    // The gutter: line numbers drawn against
    // the layout manager's own fragments, so
    // they ride the scroll for free.
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let core = core, core.showNumbers
        else { return }
        let manager = layoutManager
        let text = self.text ?? ""
        guard !text.isEmpty else { return }
        var lineStarts: [Int] = [0]
        var scan = 0
        let chars = Array(text)
        while scan < chars.count {
            if chars[scan] == "\n" {
                lineStarts.append(scan + 1)
            }
            scan += 1
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(
                ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.gray,
        ]
        let glyphRange = manager.glyphRange(
            for: textContainer)
        manager.enumerateLineFragments(
            forGlyphRange: glyphRange
        ) { fragmentRect, _, _, glyphs, _ in
            let charIndex = manager
                .characterIndexForGlyph(
                    at: glyphs.location)
            var line = 1
            for (index, start)
                in lineStarts.enumerated() {
                if start <= charIndex {
                    line = index + 1
                } else { break }
            }
            // Only the fragment that STARTS a
            // line carries its number.
            guard lineStarts.indices
                .contains(line - 1),
                  lineStarts[line - 1] == charIndex
            else { return }
            let label = "\(line)" as NSString
            let size = label.size(
                withAttributes: attrs)
            let y = fragmentRect.minY
                + self.textContainerInset.top
            label.draw(at: CGPoint(
                x: self.textContainerInset.left
                    - size.width - 10,
                y: y), withAttributes: attrs)
        }
    }
}

#endif

#if os(macOS)
/// The canvas is a UITextView on the phone; its
/// NSTextView twin is the port's polish phase.
/// Until then the Mac editor opens to the organ's
/// note — the console around it is fully live.
private struct MacEditorFallback: View {
    @ObservedObject var core: EditorCore
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.largeTitle)
            Text(L("Phone-only for now — this organ hasn't crossed to the Mac yet."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
