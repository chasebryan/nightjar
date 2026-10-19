import Foundation

// BlacksitePy — the house's small python.
//
// The console's operator writes python, so
// the console learned to run it: a real
// interpreter for a teaching-sized dialect
// of the language — numbers, strings,
// lists, dicts, sets, functions, classes
// with inheritance, generators,
// comprehensions, try/except/finally,
// f-strings, and the math, random, sys
// and house modules. It is honest about
// its edges (the `python3` help says them
// out loud): input() still waits on the
// console line, imports reach only the
// house's own modules, and there are no
// threads — a generator's body walks on
// one of its own, but user code cannot
// start another. Where CPython would
// raise, it raises in CPython's voice,
// with the file and line.

indirect enum PyValue {
    case none
    case bool(Bool)
    case int(Int)
    case float(Double)
    case str(String)
    case list(PyList)
    case dict(PyDict)
    case tuple([PyValue])
    case range(Int, Int, Int)
    case function(PyFunction)
    case builtin(String)
    case bound(PyValue, String)
    case module(String)
    case file(PyFile)
    case set(PySet)
    case cls(PyClass)
    case instance(PyInstance)
    case generator(PyGenerator)
    case seqIter(PySeqIter)
    case superProxy(PyInstance, PyClass)
}

final class PyList {
    var items: [PyValue] = []
    init(_ items: [PyValue] = []) {
        self.items = items
    }
}

final class PyDict {
    // Insertion-ordered pairs; keys are
    // matched through a stable hash string.
    var keys: [String] = []
    var values: [String: PyValue] = [:]
    var display: [String: PyValue] = [:]

    func set(_ key: PyValue, _ value: PyValue) {
        let h = PyFormat.hashKey(key)
        if values[h] == nil {
            keys.append(h)
            display[h] = key
        }
        values[h] = value
    }

    func get(_ key: PyValue) -> PyValue? {
        values[PyFormat.hashKey(key)]
    }

    func remove(_ key: PyValue) {
        let h = PyFormat.hashKey(key)
        values[h] = nil
        display[h] = nil
        keys.removeAll { $0 == h }
    }

    var count: Int { keys.count }
}

final class PyFunction {
    let name: String
    /// Set when the body yields: calling
    /// such a function builds a generator
    /// instead of running it.
    var isGenerator = false
    let params: [String]
    let defaults: [String: PyValue]
    let body: [PyStmt]
    let env: PyEnv
    init(name: String, params: [String],
         defaults: [String: PyValue],
         body: [PyStmt], env: PyEnv) {
        self.name = name
        self.params = params
        self.defaults = defaults
        self.body = body
        self.env = env
    }
}

final class PyFile {
    let path: String
    let mode: String
    var content: String = ""
    var closed = false
    var wrote = false
    init(path: String, mode: String) {
        self.path = path
        self.mode = mode
    }
}

final class PySet {
    // Insertion-ordered, deduped through
    // the same stable hash keys the dict
    // uses, so a set and a dict agree on
    // what "the same value" means.
    var keys: [String] = []
    var values: [String: PyValue] = [:]
    var display: [String: PyValue] = [:]

    func add(_ value: PyValue) {
        let h = PyFormat.hashKey(value)
        if values[h] == nil {
            keys.append(h)
            display[h] = value
        }
        values[h] = value
    }

    func contains(_ value: PyValue) -> Bool {
        values[PyFormat.hashKey(value)] != nil
    }

    func remove(_ value: PyValue) {
        let h = PyFormat.hashKey(value)
        values[h] = nil
        display[h] = nil
        keys.removeAll { $0 == h }
    }

    var items: [PyValue] {
        keys.map { display[$0] ?? .none }
    }

    var count: Int { keys.count }
}

final class PyClass {
    let name: String
    var bases: [PyClass] = []
    var attrs: [String: PyValue] = [:]
    init(name: String) { self.name = name }

    /// The method resolution order: self
    /// first, then bases depth-first,
    /// each class once — python's order
    /// for the single-inheritance chains
    /// this house mostly grows.
    func mro() -> [PyClass] {
        var out: [PyClass] = []
        func walk(_ cls: PyClass) {
            if out.contains(where: {
                $0 === cls }) { return }
            out.append(cls)
            for base in cls.bases {
                walk(base)
            }
        }
        walk(self)
        return out
    }

    /// The first value a name resolves to
    /// down the mro, with the class that
    /// holds it (super() needs the holder).
    func lookupEntry(_ field: String)
        -> (PyValue, PyClass)? {
        for cls in mro() {
            if let value = cls.attrs[field] {
                return (value, cls)
            }
        }
        return nil
    }

    func lookup(_ field: String)
        -> PyValue? {
        lookupEntry(field)?.0
    }
}

final class PyInstance {
    let cls: PyClass
    var attrs: [String: PyValue] = [:]
    init(cls: PyClass) { self.cls = cls }
}

/// A plain iterator over a snapshot of
/// values — what iter() hands back for
/// the house's sequences.
final class PySeqIter {
    let items: [PyValue]
    var index = 0
    init(_ items: [PyValue]) {
        self.items = items
    }
}

final class PyEnv {
    var vars: [String: PyValue] = [:]
    var globals: Set<String> = []
    var nonlocals: Set<String> = []
    let parent: PyEnv?
    init(parent: PyEnv? = nil) {
        self.parent = parent
    }

    var root: PyEnv {
        var env = self
        while let up = env.parent { env = up }
        return env
    }

    func lookup(_ name: String) -> PyValue? {
        if let value = vars[name] {
            return value
        }
        return parent?.lookup(name)
    }

    func assign(_ name: String,
                _ value: PyValue) {
        if parent != nil,
           nonlocals.contains(name) {
            // The nearest enclosing scope
            // that already holds the name
            // takes it; failing that, the
            // immediate parent does.
            var scope = parent
            while let env = scope {
                if env.parent != nil,
                   env.vars[name] != nil {
                    env.vars[name] = value
                    return
                }
                scope = env.parent
            }
            parent?.vars[name] = value
            return
        }
        if parent != nil,
           !globals.contains(name) {
            vars[name] = value
        } else {
            root.vars[name] = value
        }
    }

    func assignLocal(_ name: String,
                     _ value: PyValue) {
        vars[name] = value
    }

    func remove(_ name: String) -> Bool {
        if vars[name] != nil {
            vars[name] = nil
            return true
        }
        return parent?.remove(name) ?? false
    }
}

/// A generator: the function body runs
/// on its own thread, parked at each
/// yield on a pair of semaphores the
/// consumer works like a hand-crank.
/// Exactly one side runs at a time, so
/// the interpreter's shared state (its
/// frames, its step count) is only ever
/// touched by the side awake. A body
/// abandoned mid-yield keeps its thread
/// parked; the house accepts that cost.
final class PyGenerator {
    let id: Int
    let fn: PyFunction
    let args: [PyValue]
    let kwargs: [(String, PyValue)]
    weak var interp: PyInterp?
    private let wakeBody =
        DispatchSemaphore(value: 0)
    private let wakeCaller =
        DispatchSemaphore(value: 0)
    private var yielded: PyValue = .none
    private var sentIn: PyValue = .none
    private var failure: PyError?
    private(set) var finished = false
    private var started = false

    init(fn: PyFunction, args: [PyValue],
         kwargs: [(String, PyValue)],
         interp: PyInterp) {
        self.fn = fn
        self.args = args
        self.kwargs = kwargs
        self.interp = interp
        self.id = interp.mintGeneratorID()
        interp.generatorRegistry[id] = self
    }

    /// close(): the consumer walks away.
    /// A body parked at a yield stays
    /// parked — its thread is the cost —
    /// and the generator reads finished.
    func forceFinish() {
        finished = true
    }

    /// Called once by the interpreter when
    /// the generator is first advanced:
    /// the body thread starts and parks
    /// until that first crank.
    func startIfNeeded() {
        guard !started else { return }
        started = true
        let thread = Thread { [weak self] in
            self?.runBody()
        }
        thread.stackSize = 8 * 1024 * 1024
        thread.name = "py-generator"
        thread.start()
    }

    private func runBody() {
        wakeBody.wait()
        guard let interp = interp else {
            finished = true
            wakeCaller.signal()
            return
        }
        do {
            try interp
                .runGeneratorBody(self)
        } catch let error as PyError {
            failure = error
        } catch {
            failure = PyError(
                "RuntimeError",
                "the generator stumbled",
                line: 0)
        }
        finished = true
        wakeCaller.signal()
    }

    /// The body's side of a yield: hand
    /// the value over, park, and wake with
    /// whatever was sent back in.
    func suspend(_ value: PyValue)
        -> PyValue {
        yielded = value
        wakeCaller.signal()
        wakeBody.wait()
        return sentIn
    }

    /// The consumer's crank: resume the
    /// body and take the next yielded
    /// value, or nil when it has run out
    /// (its errors ride along).
    func advance(sent: PyValue) throws
        -> PyValue? {
        if finished {
            if let failure = failure {
                throw failure
            }
            return nil
        }
        startIfNeeded()
        sentIn = sent
        wakeBody.signal()
        wakeCaller.wait()
        if finished {
            if let failure = failure {
                throw failure
            }
            return nil
        }
        return yielded
    }
}

struct PyError: Error {
    let kind: String
    let message: String
    let line: Int
    init(_ kind: String, _ message: String,
         line: Int = 0) {
        self.kind = kind
        self.message = message
        self.line = line
    }
}

enum PySignal: Error {
    case returned(PyValue)
    case broke
    case continued
}

// MARK: - How values read

enum PyFormat {
    static func typeName(_ value: PyValue)
        -> String {
        switch value {
        case .none: return "NoneType"
        case .bool: return "bool"
        case .int: return "int"
        case .float: return "float"
        case .str: return "str"
        case .list: return "list"
        case .dict: return "dict"
        case .tuple: return "tuple"
        case .range: return "range"
        case .function: return "function"
        case .builtin:
            return "builtin_function_or_method"
        case .bound:
            return "builtin_function_or_method"
        case .module: return "module"
        case .file: return "TextIOWrapper"
        case .set: return "set"
        case .cls: return "type"
        case .instance(let obj):
            return obj.cls.name
        case .generator: return "generator"
        case .seqIter: return "iterator"
        case .superProxy: return "super"
        }
    }

    static func truthy(_ value: PyValue)
        -> Bool {
        switch value {
        case .none: return false
        case .bool(let b): return b
        case .int(let n): return n != 0
        case .float(let d): return d != 0
        case .str(let s): return !s.isEmpty
        case .list(let l): return !l.items.isEmpty
        case .dict(let d): return d.count > 0
        case .tuple(let t): return !t.isEmpty
        case .set(let s): return s.count > 0
        case .range(let a, let b, let s):
            if s > 0 { return a < b }
            if s < 0 { return a > b }
            return false
        default: return true
        }
    }

    static func hashKey(_ value: PyValue)
        -> String {
        switch value {
        case .none: return "n:"
        case .bool(let b): return "b:\(b)"
        case .int(let n): return "i:\(n)"
        case .float(let d): return "f:\(d)"
        case .str(let s): return "s:" + s
        case .tuple(let t):
            return "t:" + t.map { hashKey($0) }
                .joined(separator: ",")
        case .instance(let obj):
            return "obj:"
                + "\(ObjectIdentifier(obj))"
        case .cls(let cls):
            return "cls:"
                + "\(ObjectIdentifier(cls))"
        case .generator(let gen):
            return "gen:"
                + "\(ObjectIdentifier(gen))"
        case .seqIter(let iter):
            return "itr:"
                + "\(ObjectIdentifier(iter))"
        default:
            return "o:\(typeName(value))"
        }
    }

    static func floatText(_ d: Double)
        -> String {
        if d.isNaN { return "nan" }
        if d.isInfinite {
            return d > 0 ? "inf" : "-inf"
        }
        if d == d.rounded(),
           abs(d) < 1e16, d != 0 {
            return String(format: "%.1f", d)
        }
        if d == 0 { return "0.0" }
        var text = "\(d)"
        if !text.contains("."),
           !text.contains("e") {
            text += ".0"
        }
        return text
    }

    static func str(_ value: PyValue)
        -> String {
        switch value {
        case .none: return "None"
        case .bool(let b):
            return b ? "True" : "False"
        case .int(let n): return "\(n)"
        case .float(let d):
            return floatText(d)
        case .str(let s): return s
        case .list(let l):
            let inner = l.items.map {
                repr($0)
            }.joined(separator: ", ")
            return "[" + inner + "]"
        case .dict(let d):
            let inner = d.keys.map { h in
                repr(d.display[h] ?? .none)
                    + ": "
                    + repr(d.values[h] ?? .none)
            }.joined(separator: ", ")
            return "{" + inner + "}"
        case .tuple(let t):
            if t.count == 1 {
                return "(" + repr(t[0]) + ",)"
            }
            let inner = t.map { repr($0) }
                .joined(separator: ", ")
            return "(" + inner + ")"
        case .range(let a, let b, let s):
            if s == 1 {
                return "range(\(a), \(b))"
            }
            return "range(\(a), \(b), \(s))"
        case .function(let f):
            return "<function \(f.name)>"
        case .builtin(let name):
            return "<built-in function "
                + "\(name)>"
        case .bound(_, let method):
            return "<built-in method "
                + "\(method)>"
        case .module(let name):
            return "<module '\(name)'>"
        case .file(let f):
            return "<file \(f.path)>"
        case .set(let set):
            if set.count == 0 {
                return "set()"
            }
            let inner = set.items.map {
                repr($0)
            }.joined(separator: ", ")
            return "{" + inner + "}"
        case .cls(let cls):
            return "<class '\(cls.name)'>"
        case .instance(let obj):
            return "<\(obj.cls.name) object>"
        case .generator(let gen):
            return "<generator \(gen.fn.name)>"
        case .seqIter:
            return "<iterator>"
        case .superProxy(_, let after):
            return "<super: <class '"
                + "\(after.name)'>"
                + ", <object>>"
        }
    }

    static func repr(_ value: PyValue)
        -> String {
        if case .str(let s) = value {
            return quote(s)
        }
        return str(value)
    }

    static func quote(_ s: String) -> String {
        var out = "'"
        for ch in s {
            switch ch {
            case "'": out += "\\'"
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.append(ch)
            }
        }
        return out + "'"
    }

    static func equals(_ a: PyValue,
                       _ b: PyValue) -> Bool {
        switch (a, b) {
        case (.none, .none): return true
        case (.bool(let x), .bool(let y)):
            return x == y
        case (.int(let x), .int(let y)):
            return x == y
        case (.float(let x), .float(let y)):
            return x == y
        case (.int(let x), .float(let y)):
            return Double(x) == y
        case (.float(let x), .int(let y)):
            return x == Double(y)
        case (.bool(let x), .int(let y)):
            return (x ? 1 : 0) == y
        case (.int(let x), .bool(let y)):
            return x == (y ? 1 : 0)
        case (.str(let x), .str(let y)):
            return x == y
        case (.tuple(let x), .tuple(let y)):
            guard x.count == y.count
            else { return false }
            return zip(x, y).allSatisfy {
                equals($0.0, $0.1)
            }
        case (.list(let x), .list(let y)):
            return x === y
        case (.dict(let x), .dict(let y)):
            return x === y
        case (.instance(let x),
              .instance(let y)):
            return x === y
        case (.cls(let x), .cls(let y)):
            return x === y
        case (.set(let x), .set(let y)):
            guard x.count == y.count
            else { return false }
            return x.items.allSatisfy {
                y.contains($0)
            }
        default: return false
        }
    }
}

// MARK: - Tokens

enum PyFPart {
    case text(String)
    case expr(String)
}

enum PyTok {
    case name(String)
    case int(Int)
    case float(Double)
    case string(String)
    case fstring([PyFPart])
    case op(String)
    case newline
    case indent
    case dedent
    case eof
}

struct PyToken {
    let tok: PyTok
    let line: Int
}

// MARK: - The lexer

struct PyLexer {
    let chars: [Character]
    var i = 0
    var line = 1
    var tokens: [PyToken] = []
    var indents: [Int] = [0]
    var depth = 0
    var lineHasTokens = false

    init(_ source: String) {
        let clean = source
            .replacingOccurrences(
                of: "\r\n", with: "\n")
            .replacingOccurrences(
                of: "\r", with: "\n")
        chars = Array(clean)
    }

    var atEnd: Bool { i >= chars.count }

    func peek(_ ahead: Int = 0) -> Character? {
        let at = i + ahead
        guard at < chars.count else {
            return nil
        }
        return chars[at]
    }

    static func isNameStart(_ c: Character)
        -> Bool {
        c.isLetter || c == "_"
    }

    static func isNameChar(_ c: Character)
        -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    mutating func tokenize() throws
        -> [PyToken] {
        while !atEnd {
            try lineStart()
            if atEnd { break }
            try scanLine()
        }
        if lineHasTokens {
            tokens.append(PyToken(
                tok: .newline, line: line))
            lineHasTokens = false
        }
        while indents.count > 1 {
            indents.removeLast()
            tokens.append(PyToken(
                tok: .dedent, line: line))
        }
        tokens.append(PyToken(
            tok: .eof, line: line))
        return tokens
    }

    /// At the start of a physical line with
    /// no open brackets: measure the indent
    /// and speak for it, skipping lines that
    /// hold nothing but air or a comment.
    mutating func lineStart() throws {
        while !atEnd {
            var width = 0
            var j = i
            while j < chars.count,
                  chars[j] == " "
                    || chars[j] == "\t" {
                if chars[j] == "\t" {
                    width += 8 - (width % 8)
                } else {
                    width += 1
                }
                j += 1
            }
            // Blank or comment-only line:
            // it says nothing about indent.
            if j >= chars.count {
                i = j
                return
            }
            if chars[j] == "\n" {
                i = j + 1
                line += 1
                continue
            }
            if chars[j] == "#" {
                while j < chars.count,
                      chars[j] != "\n" {
                    j += 1
                }
                i = j
                continue
            }
            // A real line: settle the stack.
            if width > indents.last! {
                indents.append(width)
                tokens.append(PyToken(
                    tok: .indent, line: line))
            } else if width < indents.last! {
                while indents.count > 1,
                      indents.last! > width {
                    indents.removeLast()
                    tokens.append(PyToken(
                        tok: .dedent, line: line))
                }
                if indents.last! != width {
                    throw PyError(
                        "IndentationError",
                        "unindent does not match "
                            + "any outer level",
                        line: line)
                }
            }
            i = j
            return
        }
    }

    mutating func scanLine() throws {
        while !atEnd {
            let c = chars[i]
            if c == "\n" {
                i += 1
                line += 1
                if depth == 0 {
                    tokens.append(PyToken(
                        tok: .newline, line: line - 1))
                    lineHasTokens = false
                    return
                }
                continue
            }
            if c == " " || c == "\t" {
                i += 1
                continue
            }
            if c == "#" {
                while !atEnd, chars[i] != "\n" {
                    i += 1
                }
                continue
            }
            if c == "\\", peek(1) == "\n" {
                i += 2
                line += 1
                continue
            }
            try scanToken()
            lineHasTokens = true
        }
    }

    mutating func scanToken() throws {
        let c = chars[i]
        let startLine = line
        // Strings, with their f/r prefixes.
        if c == "\"" || c == "'"
            || ((c == "f" || c == "F"
                 || c == "r" || c == "R")
                && stringAhead()) {
            try scanString()
            return
        }
        if Self.isNameStart(c) {
            var text = ""
            while !atEnd,
                  Self.isNameChar(chars[i]) {
                text.append(chars[i])
                i += 1
            }
            tokens.append(PyToken(
                tok: .name(text),
                line: startLine))
            return
        }
        if c.isNumber
            || (c == "."
                && (peek(1)?.isNumber ?? false)) {
            try scanNumber()
            return
        }
        // Operators, longest first.
        let three = String(chars[i...]
            .prefix(3))
        let two = String(chars[i...]
            .prefix(2))
        for op in ["**=", "//="] where three == op {
            i += 3
            emitOp(op, startLine)
            return
        }
        for op in ["==", "!=", "<=", ">=",
                   "+=", "-=", "*=", "/=",
                   "%=", "**", "//", "<<",
                   ">>"] where two == op {
            i += 2
            emitOp(op, startLine)
            return
        }
        if "+-*/%<>=()[]{},:.;&|^~"
            .contains(c) {
            i += 1
            emitOp(String(c), startLine)
            return
        }
        throw PyError("SyntaxError",
                      "unexpected character "
                        + "'\(c)'",
                      line: startLine)
    }

    mutating func emitOp(_ op: String,
                         _ atLine: Int) {
        if op == "(" || op == "["
            || op == "{" {
            depth += 1
        }
        if op == ")" || op == "]"
            || op == "}" {
            depth -= 1
        }
        tokens.append(PyToken(
            tok: .op(op), line: atLine))
    }

    func stringAhead() -> Bool {
        var j = i
        var seen = 0
        while j < chars.count, seen < 2 {
            let c = chars[j]
            if c == "f" || c == "F"
                || c == "r" || c == "R" {
                j += 1
                seen += 1
            } else {
                break
            }
        }
        guard j < chars.count else {
            return false
        }
        return chars[j] == "\""
            || chars[j] == "'"
    }

    mutating func scanNumber() throws {
        let startLine = line
        // Radix-prefixed integers.
        if peek() == "0",
           let kind = peek(1),
           kind == "x" || kind == "X"
            || kind == "o" || kind == "O"
            || kind == "b" || kind == "B" {
            var text = ""
            i += 2
            while !atEnd,
                  chars[i].isHexDigit
                    || chars[i] == "_" {
                if chars[i] != "_" {
                    text.append(chars[i])
                }
                i += 1
            }
            let radix = (kind == "x"
                || kind == "X") ? 16
                : (kind == "o" || kind == "O")
                ? 8 : 2
            let value = Int(text, radix: radix)
            guard let value = value else {
                throw PyError("SyntaxError",
                              "bad number",
                              line: startLine)
            }
            tokens.append(PyToken(
                tok: .int(value),
                line: startLine))
            return
        }
        var text = ""
        var isFloat = false
        while !atEnd {
            let c = chars[i]
            if c.isNumber || c == "_" {
                if c != "_" {
                    text.append(c)
                }
                i += 1
            } else if c == "." {
                if isFloat { break }
                isFloat = true
                text.append(c)
                i += 1
            } else if c == "e" || c == "E" {
                isFloat = true
                text.append(c)
                i += 1
                if let sign = peek(),
                   sign == "+"
                    || sign == "-" {
                    text.append(sign)
                    i += 1
                }
            } else {
                break
            }
        }
        if isFloat {
            guard let value = Double(text)
            else {
                throw PyError("SyntaxError",
                              "bad number '\(text)'",
                              line: startLine)
            }
            tokens.append(PyToken(
                tok: .float(value),
                line: startLine))
        } else {
            guard let value = Int(text) else {
                throw PyError("SyntaxError",
                              "bad number '\(text)'",
                              line: startLine)
            }
            tokens.append(PyToken(
                tok: .int(value),
                line: startLine))
        }
    }
}

// MARK: - String scanning

extension PyLexer {
    mutating func scanString() throws {
        let startLine = line
        var raw = false
        var fstring = false
        while !atEnd {
            let c = chars[i]
            if c == "r" || c == "R" {
                raw = true
                i += 1
            } else if c == "f" || c == "F" {
                fstring = true
                i += 1
            } else {
                break
            }
        }
        guard let quote = peek(),
              quote == "\"" || quote == "'"
        else {
            throw PyError("SyntaxError",
                          "expected a string",
                          line: startLine)
        }
        i += 1
        var triple = false
        if peek() == quote, peek(1) == quote {
            triple = true
            i += 2
        }
        if fstring {
            let parts = try scanFString(
                quote: quote, triple: triple,
                raw: raw, startLine: startLine)
            tokens.append(PyToken(
                tok: .fstring(parts),
                line: startLine))
            return
        }
        var text = ""
        while !atEnd {
            let c = chars[i]
            if triple {
                if c == quote, peek() == quote,
                   peek(1) == quote,
                   peek(2) == quote {
                    i += 3
                    tokens.append(PyToken(
                        tok: .string(text),
                        line: startLine))
                    return
                }
            } else if c == quote {
                i += 1
                tokens.append(PyToken(
                    tok: .string(text),
                    line: startLine))
                return
            }
            if c == "\n" {
                if !triple {
                    throw PyError(
                        "SyntaxError",
                        "unterminated string",
                        line: startLine)
                }
                line += 1
                text.append(c)
                i += 1
                continue
            }
            if c == "\\", !raw,
               let next = peek(1) {
                if next == "x" {
                    var hex = ""
                    var k = 0
                    while k < 2,
                          let h = peek(2 + k),
                          h.isHexDigit {
                        hex.append(h)
                        k += 1
                    }
                    if hex.count == 2,
                       let byte = UInt8(
                        hex, radix: 16) {
                        let scalar =
                            UnicodeScalar(byte)
                        text.append(
                            Character(scalar))
                        i += 4
                    } else {
                        text.append("\\x")
                        i += 2
                    }
                    continue
                }
                text.append(
                    Self.escapeValue(next))
                i += 2
                continue
            }
            text.append(c)
            i += 1
        }
        throw PyError("SyntaxError",
                      "unterminated string",
                      line: startLine)
    }

    static func escapeValue(_ c: Character)
        -> String {
        switch c {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "0": return "\0"
        case "\\": return "\\"
        case "'": return "'"
        case "\"": return "\""
        default: return "\\" + String(c)
        }
    }

    /// Inside an f-string: literal runs and
    /// {expression} holes. Doubled braces
    /// are literals, as python says.
    mutating func scanFString(
        quote: Character, triple: Bool,
        raw: Bool, startLine: Int) throws
        -> [PyFPart] {
        var parts: [PyFPart] = []
        var literal = ""
        while !atEnd {
            let c = chars[i]
            if triple {
                if c == quote, peek() == quote,
                   peek(1) == quote,
                   peek(2) == quote {
                    i += 3
                    if !literal.isEmpty {
                        parts.append(
                            .text(literal))
                    }
                    return parts
                }
            } else if c == quote {
                i += 1
                if !literal.isEmpty {
                    parts.append(.text(literal))
                }
                return parts
            }
            if c == "\n" {
                if !triple {
                    throw PyError(
                        "SyntaxError",
                        "unterminated f-string",
                        line: startLine)
                }
                line += 1
                literal.append(c)
                i += 1
                continue
            }
            if c == "{", peek(1) == "{" {
                literal.append("{")
                i += 2
                continue
            }
            if c == "}", peek(1) == "}" {
                literal.append("}")
                i += 2
                continue
            }
            if c == "{" {
                if !literal.isEmpty {
                    parts.append(.text(literal))
                    literal = ""
                }
                i += 1
                let hole = try scanFHole(
                    startLine: startLine)
                parts.append(.expr(hole))
                continue
            }
            if c == "\\", !raw,
               let next = peek(1) {
                literal.append(
                    Self.escapeValue(next))
                i += 2
                continue
            }
            literal.append(c)
            i += 1
        }
        throw PyError("SyntaxError",
                      "unterminated f-string",
                      line: startLine)
    }

    /// One {…} hole: braces may nest (a
    /// dict literal inside), strings inside
    /// are skipped whole.
    mutating func scanFHole(startLine: Int)
        throws -> String {
        var depth = 1
        var hole = ""
        while !atEnd {
            let c = chars[i]
            if c == "{" {
                depth += 1
                hole.append(c)
                i += 1
                continue
            }
            if c == "}" {
                depth -= 1
                if depth == 0 {
                    i += 1
                    return hole
                }
                hole.append(c)
                i += 1
                continue
            }
            if c == "\"" || c == "'" {
                let q = c
                hole.append(c)
                i += 1
                while !atEnd, chars[i] != q {
                    if chars[i] == "\\",
                       let n = peek(1) {
                        hole.append(chars[i])
                        hole.append(n)
                        i += 2
                    } else {
                        if chars[i] == "\n" {
                            line += 1
                        }
                        hole.append(chars[i])
                        i += 1
                    }
                }
                if !atEnd {
                    hole.append(chars[i])
                    i += 1
                }
                continue
            }
            if c == "\n" { line += 1 }
            hole.append(c)
            i += 1
        }
        throw PyError("SyntaxError",
                      "f-string: expecting '}'",
                      line: startLine)
    }
}

// MARK: - The tree it parses to

indirect enum PyExpr {
    case int(Int)
    case float(Double)
    case string(String)
    case fstring([PyFPart])
    case name(String)
    case listOf([PyExpr])
    case dictOf([(PyExpr, PyExpr)])
    case tupleOf([PyExpr])
    case binary(String, PyExpr, PyExpr)
    case unary(String, PyExpr)
    case compare(PyExpr, [(String, PyExpr)])
    case call(PyExpr, [PyExpr],
              [(String, PyExpr)])
    case index(PyExpr, PyExpr)
    case slice(PyExpr, PyExpr?, PyExpr?,
               PyExpr?)
    case attr(PyExpr, String)
    case ternary(PyExpr, PyExpr, PyExpr)
    case setOf([PyExpr])
    case lambda([String], [(String, PyExpr)],
                PyExpr)
    case yieldExpr(PyExpr?)
    /// Comprehension clauses everywhere
    /// below: (target, iterable, filters).
    case listComp(PyExpr,
                  [(PyExpr, PyExpr, [PyExpr])])
    case setComp(PyExpr,
                 [(PyExpr, PyExpr, [PyExpr])])
    case dictComp(PyExpr, PyExpr,
                  [(PyExpr, PyExpr, [PyExpr])])
    case genExp(PyExpr,
                [(PyExpr, PyExpr, [PyExpr])])
}

indirect enum PyStmt {
    case expr(PyExpr, line: Int)
    case assign([PyExpr], PyExpr, line: Int)
    case augAssign(PyExpr, String, PyExpr,
                   line: Int)
    case ifElse([(PyExpr, [PyStmt])],
                [PyStmt], line: Int)
    case whileLoop(PyExpr, [PyStmt],
                   line: Int)
    case forLoop(PyExpr, PyExpr, [PyStmt],
                 line: Int)
    case def(String, [String],
             [(String, PyExpr)], [PyStmt],
             line: Int)
    case returnStmt(PyExpr?, line: Int)
    case breakStmt(line: Int)
    case continueStmt(line: Int)
    case passStmt(line: Int)
    case importStmt([String], line: Int)
    case fromImport(String, [String],
                    line: Int)
    case tryExcept([PyStmt],
                   [(String?, String?,
                     [PyStmt])],
                   [PyStmt], [PyStmt],
                   line: Int)
    case withStmt(PyExpr, PyExpr?, [PyStmt],
                  line: Int)
    case raiseStmt(PyExpr?, line: Int)
    case assertStmt(PyExpr, PyExpr?,
                    line: Int)
    case globalStmt([String], line: Int)
    case delStmt([PyExpr], line: Int)
    case classDef(String, [PyExpr],
                  [PyStmt], line: Int)
    case nonlocalStmt([String], line: Int)
}

// MARK: - The parser

struct PyParser {
    let tokens: [PyToken]
    var pos = 0

    var current: PyToken {
        tokens[min(pos, tokens.count - 1)]
    }

    var atEOF: Bool {
        if case .eof = current.tok {
            return true
        }
        return false
    }

    var atNewline: Bool {
        if case .newline = current.tok {
            return true
        }
        return false
    }

    var atDedent: Bool {
        if case .dedent = current.tok {
            return true
        }
        return false
    }

    func isOp(_ op: String) -> Bool {
        if case .op(let text) = current.tok {
            return text == op
        }
        return false
    }

    func isName(_ name: String) -> Bool {
        if case .name(let text) = current.tok {
            return text == name
        }
        return false
    }

    mutating func advance() {
        if pos < tokens.count - 1 {
            pos += 1
        }
    }

    mutating func expectOp(_ op: String)
        throws {
        guard isOp(op) else {
            throw PyError(
                "SyntaxError",
                "expected '\(op)'",
                line: current.line)
        }
        advance()
    }

    mutating func expectName() throws
        -> String {
        guard case .name(let text) =
            current.tok else {
            throw PyError(
                "SyntaxError",
                "expected a name",
                line: current.line)
        }
        advance()
        return text
    }

    mutating func parseProgram() throws
        -> [PyStmt] {
        var body: [PyStmt] = []
        while !atEOF {
            if case .newline = current.tok {
                advance()
                continue
            }
            body.append(
                contentsOf: try parseStatement())
        }
        return body
    }

    /// One statement, possibly several
    /// simple ones sharing a line.
    mutating func parseStatement() throws
        -> [PyStmt] {
        let line = current.line
        if isName("if") {
            return [try parseIf()]
        }
        if isName("while") {
            advance()
            let cond = try parseExpr()
            try expectOp(":")
            let body = try parseSuite()
            return [.whileLoop(
                cond, body, line: line)]
        }
        if isName("for") {
            advance()
            let target = try parseTargetList()
            guard isName("in") else {
                throw PyError(
                    "SyntaxError",
                    "expected 'in'",
                    line: current.line)
            }
            advance()
            let iterable = try parseExpr()
            try expectOp(":")
            let body = try parseSuite()
            return [.forLoop(
                target, iterable, body,
                line: line)]
        }
        if isName("def") {
            return [try parseDef()]
        }
        if isName("class") {
            return [try parseClass()]
        }
        if isName("try") {
            return [try parseTry()]
        }
        if isName("with") {
            advance()
            let item = try parseExpr()
            var target: PyExpr? = nil
            if isName("as") {
                advance()
                target = try parseTarget()
            }
            try expectOp(":")
            let body = try parseSuite()
            return [.withStmt(
                item, target, body,
                line: line)]
        }
        if isName("import") {
            advance()
            var names = [try expectName()]
            while isOp(",") {
                advance()
                names.append(try expectName())
            }
            try endOfStatement()
            return [.importStmt(
                names, line: line)]
        }
        if isName("from") {
            advance()
            let module = try expectName()
            guard isName("import") else {
                throw PyError(
                    "SyntaxError",
                    "expected 'import'",
                    line: current.line)
            }
            advance()
            var names = [try expectName()]
            while isOp(",") {
                advance()
                names.append(try expectName())
            }
            try endOfStatement()
            return [.fromImport(
                module, names, line: line)]
        }
        return try parseSimpleLine()
    }

    /// The part after a colon: either an
    /// indented block or simple statements
    /// sharing the line.
    mutating func parseSuite() throws
        -> [PyStmt] {
        if case .newline = current.tok {
            advance()
            guard case .indent = current.tok
            else {
                throw PyError(
                    "IndentationError",
                    "expected an indented block",
                    line: current.line)
            }
            advance()
            var body: [PyStmt] = []
            while true {
                if case .dedent = current.tok {
                    advance()
                    break
                }
                if case .newline = current.tok {
                    advance()
                    continue
                }
                if atEOF { break }
                body.append(
                    contentsOf:
                        try parseStatement())
            }
            return body
        }
        return try parseSimpleLine()
    }

    mutating func endOfStatement() throws {
        if isOp(";") {
            advance()
            return
        }
        if case .newline = current.tok {
            advance()
            return
        }
        if atDedent || atEOF {
            return
        }
        throw PyError(
            "SyntaxError",
            "expected the line to end here",
            line: current.line)
    }

    mutating func parseSimpleLine() throws
        -> [PyStmt] {
        var out: [PyStmt] = []
        while true {
            out.append(
                try parseSimpleStatement())
            if isOp(";") {
                advance()
                if case .newline = current.tok {
                    advance()
                    break
                }
                continue
            }
            break
        }
        if case .newline = current.tok {
            advance()
        }
        return out
    }

    mutating func parseSimpleStatement()
        throws -> PyStmt {
        let line = current.line
        if isName("return") {
            advance()
            if atNewline || isOp(";") ||
                atEOF || isOp(",") {
                return .returnStmt(
                    nil, line: line)
            }
            if case .dedent = current.tok {
                return .returnStmt(
                    nil, line: line)
            }
            let value = try parseExprList()
            return .returnStmt(
                value, line: line)
        }
        if isName("break") {
            advance()
            return .breakStmt(line: line)
        }
        if isName("continue") {
            advance()
            return .continueStmt(line: line)
        }
        if isName("pass") {
            advance()
            return .passStmt(line: line)
        }
        if isName("raise") {
            advance()
            if atNewline || isOp(";") {
                return .raiseStmt(
                    nil, line: line)
            }
            let value = try parseExpr()
            return .raiseStmt(
                value, line: line)
        }
        if isName("assert") {
            advance()
            let test = try parseExpr()
            var message: PyExpr? = nil
            if isOp(",") {
                advance()
                message = try parseExpr()
            }
            return .assertStmt(
                test, message, line: line)
        }
        if isName("global") {
            advance()
            var names = [try expectName()]
            while isOp(",") {
                advance()
                names.append(try expectName())
            }
            return .globalStmt(
                names, line: line)
        }
        if isName("nonlocal") {
            advance()
            var names = [try expectName()]
            while isOp(",") {
                advance()
                names.append(try expectName())
            }
            return .nonlocalStmt(
                names, line: line)
        }
        if isName("del") {
            advance()
            var targets = [try parseTarget()]
            while isOp(",") {
                advance()
                targets.append(
                    try parseTarget())
            }
            return .delStmt(
                targets, line: line)
        }
        // Assignment or bare expression.
        let first = try parseExpr()
        if isOp("=") {
            var targets = [first]
            var values: [PyExpr] = []
            while isOp("=") {
                advance()
                values.append(
                    try parseExpr())
            }
            let value = values.removeLast()
            for mid in values {
                targets.append(mid)
            }
            return .assign(
                targets, value, line: line)
        }
        for op in ["+=", "-=", "*=", "/=",
                   "//=", "%=", "**="]
            where isOp(op) {
            advance()
            let value = try parseExpr()
            return .augAssign(
                first, op, value, line: line)
        }
        return .expr(first, line: line)
    }
}

// MARK: - Compound statements

extension PyParser {
    mutating func parseIf() throws -> PyStmt {
        let line = current.line
        advance()
        var arms: [(PyExpr, [PyStmt])] = []
        let cond = try parseExpr()
        try expectOp(":")
        arms.append((cond, try parseSuite()))
        var elseBody: [PyStmt] = []
        while true {
            if isName("elif") {
                advance()
                let next = try parseExpr()
                try expectOp(":")
                arms.append(
                    (next, try parseSuite()))
                continue
            }
            if isName("else") {
                advance()
                try expectOp(":")
                elseBody = try parseSuite()
            }
            break
        }
        return .ifElse(arms, elseBody,
                       line: line)
    }

    mutating func parseDef() throws -> PyStmt {
        let line = current.line
        advance()
        let name = try expectName()
        try expectOp("(")
        var params: [String] = []
        var defaults: [(String, PyExpr)] = []
        if !isOp(")") {
            while true {
                let param = try expectName()
                params.append(param)
                if isOp("=") {
                    advance()
                    let fallback =
                        try parseExpr()
                    defaults.append(
                        (param, fallback))
                }
                if isOp(",") {
                    advance()
                    continue
                }
                break
            }
        }
        try expectOp(")")
        try expectOp(":")
        let body = try parseSuite()
        return .def(name, params, defaults,
                    body, line: line)
    }

    mutating func parseClass() throws
        -> PyStmt {
        let line = current.line
        advance()
        let name = try expectName()
        var bases: [PyExpr] = []
        if isOp("(") {
            advance()
            if !isOp(")") {
                while true {
                    bases.append(
                        try parseExpr())
                    if isOp(",") {
                        advance()
                        if isOp(")") { break }
                        continue
                    }
                    break
                }
            }
            try expectOp(")")
        }
        try expectOp(":")
        let body = try parseSuite()
        return .classDef(name, bases, body,
                         line: line)
    }

    mutating func parseTry() throws -> PyStmt {
        let line = current.line
        advance()
        try expectOp(":")
        let body = try parseSuite()
        var handlers: [(String?, String?,
                        [PyStmt])] = []
        while isName("except") {
            advance()
            var kind: String? = nil
            var alias: String? = nil
            if !isOp(":") {
                kind = try expectName()
                if isName("as") {
                    advance()
                    alias = try expectName()
                }
            }
            try expectOp(":")
            let arm = try parseSuite()
            handlers.append((kind, alias, arm))
        }
        var elseBody: [PyStmt] = []
        if isName("else") {
            advance()
            try expectOp(":")
            elseBody = try parseSuite()
        }
        var finallyBody: [PyStmt] = []
        if isName("finally") {
            advance()
            try expectOp(":")
            finallyBody = try parseSuite()
        }
        guard !handlers.isEmpty
            || !finallyBody.isEmpty else {
            throw PyError(
                "SyntaxError",
                "try needs an except "
                    + "or a finally",
                line: current.line)
        }
        return .tryExcept(body, handlers,
                          elseBody,
                          finallyBody,
                          line: line)
    }

    /// The tail of a comprehension:
    /// for <target> in <expr> [if <expr>]…,
    /// repeated per clause. Entered with
    /// 'for' as the current word. Iterable
    /// and filters parse at or-level: a
    /// comprehension's 'if' is a filter,
    /// never a conditional expression.
    mutating func parseCompClauses() throws
        -> [(PyExpr, PyExpr, [PyExpr])] {
        var clauses: [(PyExpr, PyExpr,
                       [PyExpr])] = []
        while isName("for") {
            advance()
            let target =
                try parseTargetList()
            guard isName("in") else {
                throw PyError(
                    "SyntaxError",
                    "expected 'in'",
                    line: current.line)
            }
            advance()
            let iterable = try parseOr()
            var conds: [PyExpr] = []
            while isName("if") {
                advance()
                conds.append(try parseOr())
            }
            clauses.append(
                (target, iterable, conds))
        }
        return clauses
    }

    /// An assignment target: a name, an
    /// index, or a parenthesised handful.
    mutating func parseTarget() throws
        -> PyExpr {
        if isOp("(") {
            advance()
            var parts = [try parseTarget()]
            while isOp(",") {
                advance()
                if isOp(")") { break }
                parts.append(
                    try parseTarget())
            }
            try expectOp(")")
            return .tupleOf(parts)
        }
        let base = try parseAtom()
        return try parsePostfix(base,
                                targets: true)
    }

    mutating func parseTargetList() throws
        -> PyExpr {
        let first = try parseTarget()
        if isOp(",") {
            var parts = [first]
            while isOp(",") {
                advance()
                parts.append(
                    try parseTarget())
            }
            return .tupleOf(parts)
        }
        return first
    }
}

// MARK: - Expressions

extension PyParser {
    /// An expression list becomes a tuple
    /// when it carries commas (a, b = …).
    mutating func parseExprList() throws
        -> PyExpr {
        let first = try parseExpr()
        if isOp(",") {
            var parts = [first]
            while isOp(",") {
                advance()
                if atNewline || isOp(")") ||
                    atEOF {
                    break
                }
                if case .dedent = current.tok {
                    break
                }
                parts.append(try parseExpr())
            }
            return .tupleOf(parts)
        }
        return first
    }

    mutating func parseExpr() throws
        -> PyExpr {
        if isName("lambda") {
            return try parseLambda()
        }
        if isName("yield") {
            advance()
            if atNewline || atEOF || atDedent
                || isOp(")") || isOp("]")
                || isOp("}") || isOp(",")
                || isOp(":") || isOp(";") {
                return .yieldExpr(nil)
            }
            if case .name(let word) =
                current.tok,
               ["from", "else", "elif",
                "except", "finally", "in",
                "is", "as"].contains(word) {
                return .yieldExpr(nil)
            }
            return .yieldExpr(
                try parseExpr())
        }
        let first = try parseOr()
        if isName("if") {
            advance()
            let cond = try parseOr()
            guard isName("else") else {
                throw PyError(
                    "SyntaxError",
                    "expected 'else' in the "
                        + "conditional",
                    line: current.line)
            }
            advance()
            let other = try parseExpr()
            return .ternary(first, cond, other)
        }
        return first
    }

    /// lambda a, b=2: <expr> — the params
    /// ride the same rails as def's, minus
    /// the parentheses.
    mutating func parseLambda() throws
        -> PyExpr {
        advance()
        var params: [String] = []
        var defaults: [(String, PyExpr)] = []
        if !isOp(":") {
            while true {
                let param = try expectName()
                params.append(param)
                if isOp("=") {
                    advance()
                    let fallback =
                        try parseExpr()
                    defaults.append(
                        (param, fallback))
                }
                if isOp(",") {
                    advance()
                    continue
                }
                break
            }
        }
        try expectOp(":")
        let body = try parseExpr()
        return .lambda(params, defaults, body)
    }

    mutating func parseOr() throws -> PyExpr {
        var left = try parseAnd()
        while isName("or") {
            advance()
            let right = try parseAnd()
            left = .binary("or", left, right)
        }
        return left
    }

    mutating func parseAnd() throws
        -> PyExpr {
        var left = try parseNot()
        while isName("and") {
            advance()
            let right = try parseNot()
            left = .binary("and", left, right)
        }
        return left
    }

    mutating func parseNot() throws
        -> PyExpr {
        if isName("not") {
            advance()
            if isName("in") {
                throw PyError(
                    "SyntaxError",
                    "stray 'not in'",
                    line: current.line)
            }
            let inner = try parseNot()
            return .unary("not", inner)
        }
        return try parseComparison()
    }

    mutating func parseComparison() throws
        -> PyExpr {
        let left = try parseBitOr()
        var chain: [(String, PyExpr)] = []
        while true {
            if isOp("==") || isOp("!=")
                || isOp("<") || isOp("<=")
                || isOp(">") || isOp(">=") {
                guard case .op(let op) =
                    current.tok else { break }
                advance()
                chain.append(
                    (op, try parseBitOr()))
                continue
            }
            if isName("in") {
                advance()
                chain.append(
                    ("in", try parseBitOr()))
                continue
            }
            if isName("not") {
                let save = pos
                advance()
                if isName("in") {
                    advance()
                    chain.append(
                        ("not in",
                         try parseBitOr()))
                    continue
                }
                pos = save
                break
            }
            if isName("is") {
                advance()
                if isName("not") {
                    advance()
                    chain.append(
                        ("is not",
                         try parseBitOr()))
                } else {
                    chain.append(
                        ("is", try parseBitOr()))
                }
                continue
            }
            break
        }
        if chain.isEmpty { return left }
        return .compare(left, chain)
    }

    mutating func parseBitOr() throws
        -> PyExpr {
        var left = try parseBitXor()
        while isOp("|") {
            advance()
            left = .binary(
                "|", left, try parseBitXor())
        }
        return left
    }

    mutating func parseBitXor() throws
        -> PyExpr {
        var left = try parseBitAnd()
        while isOp("^") {
            advance()
            left = .binary(
                "^", left, try parseBitAnd())
        }
        return left
    }

    mutating func parseBitAnd() throws
        -> PyExpr {
        var left = try parseShift()
        while isOp("&") {
            advance()
            left = .binary(
                "&", left, try parseShift())
        }
        return left
    }

    mutating func parseShift() throws
        -> PyExpr {
        var left = try parseAdditive()
        while isOp("<<") || isOp(">>") {
            guard case .op(let op) =
                current.tok else { break }
            advance()
            left = .binary(
                op, left, try parseAdditive())
        }
        return left
    }

    mutating func parseAdditive() throws
        -> PyExpr {
        var left = try parseTerm()
        while isOp("+") || isOp("-") {
            guard case .op(let op) =
                current.tok else { break }
            advance()
            left = .binary(
                op, left, try parseTerm())
        }
        return left
    }

    mutating func parseTerm() throws
        -> PyExpr {
        var left = try parseFactor()
        while isOp("*") || isOp("/")
            || isOp("//") || isOp("%") {
            guard case .op(let op) =
                current.tok else { break }
            advance()
            left = .binary(
                op, left, try parseFactor())
        }
        return left
    }

    mutating func parseFactor() throws
        -> PyExpr {
        if isOp("-") || isOp("+")
            || isOp("~") {
            guard case .op(let op) =
                current.tok else {
                throw PyError(
                    "SyntaxError", "bad sign",
                    line: current.line)
            }
            advance()
            let inner = try parseFactor()
            // -2**2 is -(2**2) in python.
            return .unary(op, inner)
        }
        return try parsePower()
    }

    mutating func parsePower() throws
        -> PyExpr {
        let base = try parsePostfixChain()
        if isOp("**") {
            advance()
            let exponent =
                try parseFactor()
            return .binary("**", base, exponent)
        }
        return base
    }

    mutating func parsePostfixChain() throws
        -> PyExpr {
        let atom = try parseAtom()
        return try parsePostfix(atom)
    }

    mutating func parsePostfix(
        _ base: PyExpr,
        targets: Bool = false) throws
        -> PyExpr {
        var expr = base
        while true {
            if isOp(".") {
                advance()
                let field = try expectName()
                expr = .attr(expr, field)
                continue
            }
            if isOp("[") {
                advance()
                expr = try parseSubscript(expr)
                continue
            }
            if isOp("("), !targets {
                advance()
                var args: [PyExpr] = []
                var kwargs: [(String, PyExpr)]
                    = []
                if !isOp(")") {
                    while true {
                        if case .name(let word) =
                            current.tok,
                           case .op("=") =
                            tokens[
                                min(pos + 1,
                                    tokens.count - 1)
                            ].tok {
                            advance()
                            advance()
                            kwargs.append(
                                (word,
                                 try parseExpr()))
                        } else {
                            args.append(
                                try parseExpr())
                        }
                        if isOp(",") {
                            advance()
                            continue
                        }
                        break
                    }
                }
                try expectOp(")")
                expr = .call(expr, args, kwargs)
                continue
            }
            break
        }
        return expr
    }

    mutating func parseSubscript(
        _ base: PyExpr) throws -> PyExpr {
        var start: PyExpr? = nil
        if !isOp(":") && !isOp("]") {
            start = try parseExpr()
        }
        if isOp(":") {
            advance()
            var stop: PyExpr? = nil
            var step: PyExpr? = nil
            if !isOp(":") && !isOp("]") {
                stop = try parseExpr()
            }
            if isOp(":") {
                advance()
                if !isOp("]") {
                    step = try parseExpr()
                }
            }
            try expectOp("]")
            return .slice(base, start, stop,
                          step)
        }
        try expectOp("]")
        guard let start = start else {
            throw PyError(
                "SyntaxError",
                "empty subscript",
                line: current.line)
        }
        return .index(base, start)
    }

    mutating func parseAtom() throws
        -> PyExpr {
        let token = current
        switch token.tok {
        case .int(let n):
            advance()
            return .int(n)
        case .float(let d):
            advance()
            return .float(d)
        case .string(let s):
            advance()
            var text = s
            // Adjacent literals join, as
            // python joins them.
            while case .string(let more) =
                current.tok {
                text += more
                advance()
            }
            return .string(text)
        case .fstring(let parts):
            advance()
            return .fstring(parts)
        case .name(let word):
            advance()
            return .name(word)
        case .op("("):
            advance()
            if isOp(")") {
                advance()
                return .tupleOf([])
            }
            // A generator expression is one
            // element wearing clauses; spot
            // its 'for' before the commas of
            // a tuple can claim the text.
            let save = pos
            let first = try parseExpr()
            if isName("for") {
                let clauses =
                    try parseCompClauses()
                try expectOp(")")
                return .genExp(first, clauses)
            }
            pos = save
            let inner = try parseExprList()
            try expectOp(")")
            return inner
        case .op("["):
            advance()
            var items: [PyExpr] = []
            if !isOp("]") {
                let first = try parseExpr()
                if isName("for") {
                    let clauses =
                        try parseCompClauses()
                    try expectOp("]")
                    return .listComp(
                        first, clauses)
                }
                items.append(first)
                while isOp(",") {
                    advance()
                    if isOp("]") { break }
                    items.append(
                        try parseExpr())
                }
            }
            try expectOp("]")
            return .listOf(items)
        case .op("{"):
            advance()
            if isOp("}") {
                advance()
                return .dictOf([])
            }
            // One opening expression decides
            // the shape: a colon makes it a
            // dict, a 'for' makes it a
            // comprehension, anything else
            // leaves a set on the table.
            let first = try parseExpr()
            if isOp(":") {
                advance()
                let value = try parseExpr()
                if isName("for") {
                    let clauses =
                        try parseCompClauses()
                    try expectOp("}")
                    return .dictComp(
                        first, value, clauses)
                }
                var pairs = [(first, value)]
                while isOp(",") {
                    advance()
                    if isOp("}") { break }
                    let key = try parseExpr()
                    try expectOp(":")
                    let next = try parseExpr()
                    pairs.append((key, next))
                }
                try expectOp("}")
                return .dictOf(pairs)
            }
            if isName("for") {
                let clauses =
                    try parseCompClauses()
                try expectOp("}")
                return .setComp(first, clauses)
            }
            var elements = [first]
            while isOp(",") {
                advance()
                if isOp("}") { break }
                elements.append(
                    try parseExpr())
            }
            try expectOp("}")
            return .setOf(elements)
        default:
            throw PyError(
                "SyntaxError",
                "unexpected token",
                line: token.line)
        }
    }
}

// MARK: - The interpreter

final class PyInterp {
    let emit: BlacksiteEmit
    let path: String
    let moduleEnv = PyEnv()
    var outBuffer = ""
    var steps = 0
    var callDepth = 0
    var frames: [(name: String, line: Int)] = []
    var rngState: UInt64 = 0x2545F4914F6CDD1D
    let stepLimit = 400_000

    static let builtinNames: Set<String> = [
        "print", "len", "range", "str",
        "int", "float", "bool", "list",
        "dict", "tuple", "abs", "min",
        "max", "sum", "sorted", "reversed",
        "enumerate", "zip", "type", "repr",
        "round", "ord", "chr", "open",
        "input", "set", "frozenset",
        "isinstance", "issubclass",
        "getattr", "setattr", "hasattr",
        "callable", "iter", "next",
        "any", "all", "divmod", "pow",
        "hex", "oct", "bin", "hash",
        "id", "vars", "dir", "super",
    ]

    static let exceptionKinds: Set<String> = [
        "Exception", "ValueError",
        "TypeError", "NameError",
        "KeyError", "IndexError",
        "ZeroDivisionError", "RuntimeError",
        "AssertionError",
        "FileNotFoundError", "ImportError",
        "ModuleNotFoundError",
        "AttributeError", "SyntaxError",
        "IndentationError",
        "StopIteration", "RecursionError",
        "LookupError", "ArithmeticError",
        "OverflowError",
        "NotImplementedError",
    ]

    init(emit: @escaping BlacksiteEmit,
         path: String) {
        self.emit = emit
        self.path = path
    }

    func tick() throws {
        steps += 1
        if steps > stepLimit {
            throw PyError(
                "RuntimeError",
                "the house stopped the "
                    + "program after "
                    + "\(stepLimit) steps — "
                    + "an endless loop?",
                line: frames.last?.line ?? 0)
        }
    }

    func nextRandom() -> UInt64 {
        // SplitMix64: small, honest dice.
        rngState &+= 0x9E3779B97F4A7C15
        var z = rngState
        z = (z ^ (z >> 30))
            &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27))
            &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    func randomDouble() -> Double {
        Double(nextRandom() >> 11)
            / 9007199254740992.0
    }

    var scriptArgs: [String] = []

    /// The (instance, class that defined
    /// the method) of the method now
    /// running — super()'s footing.
    var methodContext: [(PyInstance,
                         PyClass)] = []
    /// Live generators by id; a body
    /// thread finds its own generator
    /// through its thread dictionary.
    var generatorRegistry:
        [Int: PyGenerator] = [:]
    var nextGenID = 0
    /// Class name to base names, walked
    /// by the except matcher so a user
    /// exception hierarchy behaves like
    /// one. Unlisted kinds hang from
    /// Exception directly.
    var classBases: [String: [String]] = [
        "ModuleNotFoundError":
            ["ImportError"],
    ]

    func mintGeneratorID() -> Int {
        nextGenID += 1
        return nextGenID
    }

    /// A generator's body, run on its own
    /// thread: this thread is where its
    /// yields live.
    func runGeneratorBody(
        _ gen: PyGenerator) throws {
        Thread.current.threadDictionary[
            "pygen"] = NSNumber(
                value: gen.id)
        defer {
            generatorRegistry[gen.id] = nil
        }
        _ = try callFunction(
            gen.fn, gen.args, gen.kwargs, 0)
    }

    /// Does a handler name catch an error
    /// kind? By equality, by the universal
    /// Exception, or by walking the
    /// error's registered bases.
    func errorMatches(_ handler: String?,
                      _ kind: String) -> Bool {
        guard let handler = handler
        else { return true }
        var seen: Set<String> = []
        var queue = [kind]
        while let current = queue.popLast() {
            if current == handler {
                return true
            }
            if !seen.insert(current)
                .inserted { continue }
            if let bases =
                classBases[current] {
                queue += bases
            } else if current != "Exception" {
                queue.append("Exception")
            }
        }
        return false
    }

    /// One pass through a loop body:
    /// true when a break ended it.
    func execLoopBody(_ body: [PyStmt],
                      _ env: PyEnv) throws
        -> Bool {
        do {
            try execBlock(body, env)
            return false
        } catch let signal as PySignal {
            if case .broke = signal {
                return true
            }
            if case .continued = signal {
                return false
            }
            throw signal
        }
    }

    func runProgram(_ body: [PyStmt],
                    args: [String]) {
        scriptArgs = args
        moduleEnv.assignLocal(
            "__name__", .str("__main__"))
        moduleEnv.assignLocal(
            "__file__", .str(path))
        moduleEnv.assignLocal(
            "argv", .list(PyList(
                args.map { PyValue.str($0) })))
        frames = [("<module>", 1)]
        do {
            try execBlock(body, moduleEnv)
        } catch let signal as PySignal {
            switch signal {
            case .returned:
                emitTrace("SyntaxError",
                          "'return' outside "
                            + "a function", 0)
            case .broke:
                emitTrace("SyntaxError",
                          "'break' outside "
                            + "a loop", 0)
            case .continued:
                emitTrace("SyntaxError",
                          "'continue' outside "
                            + "a loop", 0)
            }
        } catch let error as PyError {
            emitTrace(error.kind, error.message,
                      error.line)
        } catch {
            emitTrace("RuntimeError",
                      "the interpreter stumbled",
                      0)
        }
        flushOut()
    }

    func emitTrace(_ kind: String,
                   _ message: String,
                   _ line: Int) {
        flushOut()
        emit("Traceback (most recent "
             + "call last):", .err)
        let shown = Array(frames.suffix(4))
        for frame in shown {
            let at = frame.line > 0
                ? frame.line : max(line, 1)
            emit("  File \"\(path)\", line "
                 + "\(at), in \(frame.name)",
                 .err)
        }
        if frames.isEmpty, line > 0 {
            emit("  File \"\(path)\", line "
                 + "\(line), in <module>",
                 .err)
        }
        emit(message.isEmpty
             ? kind
             : "\(kind): \(message)", .err)
    }

    func flushOut() {
        if !outBuffer.isEmpty {
            emit(outBuffer, .out)
            outBuffer = ""
        }
    }

    func printText(_ text: String) {
        outBuffer += text
        while let cut = outBuffer
            .firstIndex(of: "\n") {
            let line = String(
                outBuffer[..<cut])
            emit(line, .out)
            outBuffer = String(outBuffer[
                outBuffer.index(after: cut)...])
        }
    }

    // MARK: Statements

    func execBlock(_ body: [PyStmt],
                   _ env: PyEnv) throws {
        for stmt in body {
            try execStmt(stmt, env)
        }
    }

    func execStmt(_ stmt: PyStmt,
                  _ env: PyEnv) throws {
        try tick()
        let line: Int
        switch stmt {
        case .expr(_, let l): line = l
        case .assign(_, _, let l): line = l
        case .augAssign(_, _, _, let l):
            line = l
        case .ifElse(_, _, let l): line = l
        case .whileLoop(_, _, let l): line = l
        case .forLoop(_, _, _, let l):
            line = l
        case .def(_, _, _, _, let l): line = l
        case .returnStmt(_, let l): line = l
        case .breakStmt(let l): line = l
        case .continueStmt(let l): line = l
        case .passStmt(let l): line = l
        case .importStmt(_, let l): line = l
        case .fromImport(_, _, let l):
            line = l
        case .tryExcept(_, _, _, _, let l):
            line = l
        case .withStmt(_, _, _, let l):
            line = l
        case .raiseStmt(_, let l): line = l
        case .assertStmt(_, _, let l):
            line = l
        case .globalStmt(_, let l): line = l
        case .delStmt(_, let l): line = l
        case .classDef(_, _, _, let l):
            line = l
        case .nonlocalStmt(_, let l):
            line = l
        }
        if let top = frames.last {
            frames[frames.count - 1] =
                (top.name, line)
        }
        switch stmt {
        case .expr(let expr, _):
            _ = try eval(expr, env)
        case .assign(let targets,
                     let valueExpr, _):
            let value = try eval(
                valueExpr, env)
            for target in targets {
                try assignTarget(
                    target, value, env)
            }
        case .augAssign(let target, let op,
                        let valueExpr, _):
            let current = try eval(
                target, env)
            let addend = try eval(
                valueExpr, env)
            let plain = String(op.dropLast())
            let merged = try evalBinary(
                plain, current, addend)
            try assignTarget(
                target, merged, env)
        case .ifElse(let arms, let fallback,
                     _):
            var done = false
            for (cond, body) in arms {
                if try isTruthy(
                    try eval(cond, env),
                    line) {
                    try execBlock(body, env)
                    done = true
                    break
                }
            }
            if !done {
                try execBlock(fallback, env)
            }
        case .whileLoop(let cond,
                        let body, _):
            while try isTruthy(
                try eval(cond, env), line) {
                try tick()
                if try execLoopBody(
                    body, env) {
                    break
                }
            }
        case .forLoop(let target,
                      let iterableExpr,
                      let body, _):
            let iterable = try eval(
                iterableExpr, env)
            if case .generator(let gen) =
                iterable {
                // A generator is walked one
                // crank at a time, so a
                // break leaves the rest of
                // it unrun.
                while let item = try gen
                    .advance(sent: .none) {
                    try tick()
                    try assignTarget(
                        target, item, env)
                    if try execLoopBody(
                        body, env) {
                        break
                    }
                }
            } else {
                let items = try iterate(
                    iterable)
                for item in items {
                    try tick()
                    try assignTarget(
                        target, item, env)
                    if try execLoopBody(
                        body, env) {
                        break
                    }
                }
            }
        case .def(let name, let params,
                  let defaultExprs,
                  let body, _):
            var defaults: [String: PyValue]
                = [:]
            for (param, expr) in defaultExprs {
                defaults[param] = try eval(
                    expr, env)
            }
            let fn = PyFunction(
                name: name,
                params: params,
                defaults: defaults,
                body: body, env: env)
            fn.isGenerator =
                Self.bodyContainsYield(body)
            env.assign(
                name, .function(fn))
        case .classDef(let name,
                       let baseExprs,
                       let body, _):
            var bases: [PyClass] = []
            for baseExpr in baseExprs {
                let value = try eval(
                    baseExpr, env)
                guard case .cls(let base) =
                    value else {
                    throw PyError(
                        "TypeError",
                        "a base must be a "
                            + "class, not '"
                            + PyFormat
                                .typeName(value)
                            + "'",
                        line: line)
                }
                bases.append(base)
            }
            let cls = PyClass(name: name)
            cls.bases = bases
            // The body runs in its own
            // scope; what it leaves there
            // becomes the class's attrs —
            // methods included.
            let classEnv = PyEnv(
                parent: env)
            try execBlock(body, classEnv)
            for (key, value)
                in classEnv.vars {
                cls.attrs[key] = value
            }
            classBases[name] = bases.map {
                $0.name
            }
            env.assign(name, .cls(cls))
        case .nonlocalStmt(let names, _):
            env.nonlocals.formUnion(names)
        case .returnStmt(let expr, _):
            if let expr = expr {
                throw PySignal.returned(
                    try eval(expr, env))
            }
            throw PySignal.returned(.none)
        case .breakStmt:
            throw PySignal.broke
        case .continueStmt:
            throw PySignal.continued
        case .passStmt:
            break
        case .importStmt(let names, _):
            for name in names {
                guard Self.isModule(name)
                else {
                    throw PyError(
                        "ModuleNotFoundError",
                        "No module named "
                            + "'\(name)' — the "
                            + "house's python "
                            + "carries math, "
                            + "random, sys "
                            + "and house",
                        line: line)
                }
                env.assignLocal(
                    name, .module(name))
            }
        case .fromImport(let module,
                         let names, _):
            guard Self.isModule(module)
            else {
                throw PyError(
                    "ModuleNotFoundError",
                    "No module named "
                        + "'\(module)'",
                    line: line)
            }
            for name in names {
                let value = try moduleAttr(
                    module, name, line)
                env.assignLocal(name, value)
            }
        case .tryExcept(let body,
                        let handlers,
                        let elseBody,
                        let finallyBody, _):
            var failure: Error? = nil
            var bodyOK = false
            do {
                try execBlock(body, env)
                bodyOK = true
            } catch {
                failure = error
            }
            if let pyError = failure
                as? PyError {
                for (kind, alias, arm)
                    in handlers {
                    if errorMatches(
                        kind, pyError.kind) {
                        if let alias = alias {
                            env.assignLocal(
                                alias,
                                .str(pyError
                                    .message))
                        }
                        do {
                            try execBlock(
                                arm, env)
                            failure = nil
                        } catch {
                            failure = error
                        }
                        break
                    }
                }
            }
            if bodyOK, failure == nil,
               !elseBody.isEmpty {
                do {
                    try execBlock(
                        elseBody, env)
                } catch {
                    failure = error
                }
            }
            // Finally runs on every road
            // out — fall, catch, return,
            // break — and its own fall
            // replaces whatever was flying.
            if !finallyBody.isEmpty {
                do {
                    try execBlock(
                        finallyBody, env)
                } catch {
                    failure = error
                }
            }
            if let failure = failure {
                throw failure
            }
        case .withStmt(let itemExpr,
                       let target,
                       let body, _):
            let raw = try eval(itemExpr, env)
            var value = raw
            if case .instance(let obj) =
                raw,
               obj.cls.lookup("__enter__")
                != nil {
                value = try callMethod(
                    raw, "__enter__", [], [],
                    line)
            }
            if let target = target {
                try assignTarget(
                    target, value, env)
            }
            var thrown: Error? = nil
            do {
                try execBlock(body, env)
            } catch {
                thrown = error
            }
            if case .file(let file) = raw {
                closeFile(file)
            }
            if case .instance(let obj) =
                raw,
               obj.cls.lookup("__exit__")
                != nil {
                var exitArgs: [PyValue] =
                    [.none, .none, .none]
                if let pyError = thrown
                    as? PyError {
                    exitArgs = [
                        .str(pyError.kind),
                        .str(pyError
                            .message),
                        .none]
                }
                let verdict = try callMethod(
                    raw, "__exit__",
                    exitArgs, [], line)
                // A truthy __exit__ swallows
                // the error it was shown.
                if thrown != nil,
                   PyFormat.truthy(verdict) {
                    thrown = nil
                }
            }
            if let thrown = thrown {
                throw thrown
            }
        case .raiseStmt(let expr, _):
            throw try raiseError(
                expr, env, line)
        case .assertStmt(let test,
                         let messageExpr, _):
            if try !isTruthy(
                try eval(test, env), line) {
                var text = ""
                if let messageExpr =
                    messageExpr {
                    text = PyFormat.str(
                        try eval(
                            messageExpr, env))
                }
                throw PyError(
                    "AssertionError", text,
                    line: line)
            }
        case .globalStmt(let names, _):
            env.globals.formUnion(names)
        case .delStmt(let targets, _):
            for target in targets {
                try deleteTarget(
                    target, env, line)
            }
        }
    }

    static func isModule(_ name: String)
        -> Bool {
        name == "math" || name == "random"
            || name == "house"
            || name == "sys"
    }

    func raiseError(_ expr: PyExpr?,
                    _ env: PyEnv,
                    _ line: Int) throws
        -> PyError {
        guard let expr = expr else {
            return PyError(
                "RuntimeError",
                "raise with nothing in hand "
                    + "— name the error",
                line: line)
        }
        if case .call(let callee,
                      let args, _) = expr,
           case .name(let kind) = callee,
           Self.exceptionKinds.contains(kind) {
            var text = ""
            if let first = args.first {
                text = PyFormat.str(
                    try eval(first, env))
            }
            return PyError(kind, text,
                           line: line)
        }
        if case .name(let kind) = expr,
           Self.exceptionKinds.contains(kind) {
            return PyError(kind, "",
                           line: line)
        }
        // A user's own exception class
        // raises under its own name, and
        // an instance of one under its
        // class's.
        if case .call(let callee,
                      let args, _) = expr,
           case .name(let word) = callee,
           case .cls(let cls)? =
            env.lookup(word) {
            var text = ""
            if let first = args.first {
                text = textOf(
                    try eval(first, env))
            }
            return PyError(cls.name, text,
                           line: line)
        }
        let value = try eval(expr, env)
        if case .instance(let obj) = value {
            return PyError(
                obj.cls.name, textOf(value),
                line: line)
        }
        return PyError(
            "Exception", PyFormat.str(value),
            line: line)
    }

    func assignTarget(_ target: PyExpr,
                      _ value: PyValue,
                      _ env: PyEnv) throws {
        switch target {
        case .name(let name):
            env.assign(name, value)
        case .tupleOf(let parts):
            let items = try iterate(value)
            guard items.count == parts.count
            else {
                throw PyError(
                    "ValueError",
                    items.count > parts.count
                        ? "too many values "
                            + "to unpack"
                        : "not enough values "
                            + "to unpack",
                    line: frames.last?.line
                        ?? 0)
            }
            for (part, item) in zip(
                parts, items) {
                try assignTarget(
                    part, item, env)
            }
        case .index(let baseExpr,
                    let indexExpr):
            let base = try eval(baseExpr, env)
            let index = try eval(
                indexExpr, env)
            try setItem(base, index, value)
        case .attr(let baseExpr,
                   let field):
            let base = try eval(baseExpr, env)
            try setAttr(base, field, value)
        default:
            throw PyError(
                "TypeError",
                "that spot cannot hold a "
                    + "value in the house's "
                    + "python",
                line: frames.last?.line ?? 0)
        }
    }

    func setAttr(_ base: PyValue,
                 _ field: String,
                 _ value: PyValue) throws {
        let line = frames.last?.line ?? 0
        switch base {
        case .instance(let obj):
            obj.attrs[field] = value
        case .cls(let cls):
            cls.attrs[field] = value
        default:
            throw PyError(
                "TypeError",
                "'\(PyFormat.typeName(base))' "
                    + "object has no "
                    + "settable attribute "
                    + "'\(field)'",
                line: line)
        }
    }

    func deleteTarget(_ target: PyExpr,
                      _ env: PyEnv,
                      _ line: Int) throws {
        switch target {
        case .name(let name):
            if !env.remove(name) {
                throw PyError(
                    "NameError",
                    "name '\(name)' is not "
                        + "defined",
                    line: line)
            }
        case .attr(let baseExpr,
                   let field):
            let base = try eval(baseExpr, env)
            switch base {
            case .instance(let obj):
                guard obj.attrs[field] != nil
                else {
                    throw PyError(
                        "AttributeError",
                        "'\(obj.cls.name)' "
                            + "object has no "
                            + "attribute "
                            + "'\(field)'",
                        line: line)
                }
                obj.attrs[field] = nil
            case .cls(let cls):
                guard cls.attrs[field] != nil
                else {
                    throw PyError(
                        "AttributeError",
                        "type object "
                            + "'\(cls.name)' "
                            + "has no attribute "
                            + "'\(field)'",
                        line: line)
                }
                cls.attrs[field] = nil
            default:
                throw PyError(
                    "TypeError",
                    "cannot delete that "
                        + "attribute",
                    line: line)
            }
        case .index(let baseExpr,
                    let indexExpr):
            let base = try eval(baseExpr, env)
            let index = try eval(
                indexExpr, env)
            switch base {
            case .dict(let dict):
                guard dict.get(index) != nil
                else {
                    throw PyError(
                        "KeyError",
                        PyFormat.repr(index),
                        line: line)
                }
                dict.remove(index)
            case .list(let list):
                let at = try listIndex(
                    index, list.items.count,
                    line)
                list.items.remove(at: at)
            default:
                throw PyError(
                    "TypeError",
                    "cannot delete from a "
                        + PyFormat.typeName(
                            base),
                    line: line)
            }
        default:
            throw PyError(
                "SyntaxError",
                "cannot delete that",
                line: line)
        }
    }

    // MARK: Values in motion

    func iterate(_ value: PyValue) throws
        -> [PyValue] {
        switch value {
        case .list(let list):
            return list.items
        case .tuple(let items):
            return items
        case .str(let text):
            return text.map {
                PyValue.str(String($0))
            }
        case .dict(let dict):
            return dict.keys.map {
                dict.display[$0] ?? .none
            }
        case .set(let set):
            return set.items
        case .generator(let gen):
            var out: [PyValue] = []
            while let item = try gen
                .advance(sent: .none) {
                out.append(item)
            }
            return out
        case .seqIter(let iter):
            var out: [PyValue] = []
            while iter.index < iter.items
                .count {
                out.append(
                    iter.items[iter.index])
                iter.index += 1
            }
            return out
        case .instance(let obj):
            if obj.cls.lookup("__iter__")
                != nil {
                let result = try callMethod(
                    .instance(obj), "__iter__",
                    [], [],
                    frames.last?.line ?? 0)
                return try iterate(result)
            }
            if obj.cls.lookup("__getitem__")
                != nil {
                // The old protocol: walk
                // indices until IndexError.
                var out: [PyValue] = []
                var at = 0
                while at <= 1_000_000 {
                    do {
                        out.append(
                            try callMethod(
                                .instance(obj),
                                "__getitem__",
                                [.int(at)], [],
                                frames.last?
                                    .line ?? 0))
                    } catch let error
                        as PyError
                    where error.kind
                        == "IndexError" {
                        break
                    }
                    at += 1
                }
                return out
            }
            throw PyError(
                "TypeError",
                "'\(obj.cls.name)' object "
                    + "is not iterable",
                line: frames.last?.line ?? 0)
        case .range(let start, let stop,
                    let step):
            guard step != 0 else {
                throw PyError(
                    "ValueError",
                    "range() arg 3 must not "
                        + "be zero",
                    line: frames.last?.line
                        ?? 0)
            }
            var out: [PyValue] = []
            var n = start
            while (step > 0 && n < stop)
                    || (step < 0 && n > stop) {
                out.append(.int(n))
                n += step
                if out.count > 1_000_000 {
                    throw PyError(
                        "RuntimeError",
                        "that range is bigger "
                            + "than the house "
                            + "will walk",
                        line: frames.last?
                            .line ?? 0)
                }
            }
            return out
        default:
            throw PyError(
                "TypeError",
                "'\(PyFormat.typeName(value))' "
                    + "object is not iterable",
                line: frames.last?.line ?? 0)
        }
    }

    func listIndex(_ index: PyValue,
                   _ count: Int,
                   _ line: Int) throws
        -> Int {
        guard case .int(let raw) = index
        else {
            throw PyError(
                "TypeError",
                "indices must be integers",
                line: line)
        }
        let at = raw < 0 ? raw + count : raw
        guard at >= 0, at < count else {
            throw PyError(
                "IndexError",
                "index out of range",
                line: line)
        }
        return at
    }

    func setItem(_ base: PyValue,
                 _ index: PyValue,
                 _ value: PyValue) throws {
        let line = frames.last?.line ?? 0
        switch base {
        case .instance(let obj):
            guard obj.cls.lookup(
                "__setitem__") != nil else {
                throw PyError(
                    "TypeError",
                    "'\(obj.cls.name)' "
                        + "object does not "
                        + "support item "
                        + "assignment",
                    line: line)
            }
            _ = try callMethod(
                .instance(obj), "__setitem__",
                [index, value], [], line)
        case .list(let list):
            let at = try listIndex(
                index, list.items.count,
                line)
            list.items[at] = value
        case .dict(let dict):
            dict.set(index, value)
        case .str:
            throw PyError(
                "TypeError",
                "'str' object does not "
                    + "support item assignment",
                line: line)
        default:
            throw PyError(
                "TypeError",
                "'\(PyFormat.typeName(base))' "
                    + "object does not support "
                    + "item assignment",
                line: line)
        }
    }

    func closeFile(_ file: PyFile) {
        guard !file.closed else { return }
        file.closed = true
        if file.mode != "r", file.wrote {
            _ = BlacksiteFS.writeText(
                file.path, text: file.content)
        }
    }
}

// MARK: - Expressions at work

extension PyInterp {
    func eval(_ expr: PyExpr,
              _ env: PyEnv) throws -> PyValue {
        let line = frames.last?.line ?? 0
        switch expr {
        case .int(let n):
            return .int(n)
        case .float(let d):
            return .float(d)
        case .string(let s):
            return .str(s)
        case .fstring(let parts):
            var out = ""
            for part in parts {
                switch part {
                case .text(let text):
                    out += text
                case .expr(let source):
                    let value = try evalFragment(
                        source, env, line)
                    out += textOf(value)
                }
            }
            return .str(out)
        case .name(let word):
            if word == "True" {
                return .bool(true)
            }
            if word == "False" {
                return .bool(false)
            }
            if word == "None" {
                return .none
            }
            if let value = env.lookup(word) {
                return value
            }
            if Self.builtinNames.contains(word) {
                return .builtin(word)
            }
            throw PyError(
                "NameError",
                "name '\(word)' is not "
                    + "defined",
                line: line)
        case .listOf(let items):
            let list = PyList()
            for item in items {
                list.items.append(
                    try eval(item, env))
            }
            return .list(list)
        case .dictOf(let pairs):
            let dict = PyDict()
            for (keyExpr, valueExpr)
                in pairs {
                let key = try eval(
                    keyExpr, env)
                let value = try eval(
                    valueExpr, env)
                dict.set(key, value)
            }
            return .dict(dict)
        case .tupleOf(let items):
            var values: [PyValue] = []
            for item in items {
                values.append(
                    try eval(item, env))
            }
            return .tuple(values)
        case .unary(let op, let inner):
            let value = try eval(inner, env)
            if op == "not" {
                return .bool(
                    try !isTruthy(
                        value, line))
            }
            return try evalUnaryNum(
                op, value, line)
        case .binary(let op, let lhs,
                     let rhs):
            if op == "and" {
                let left = try eval(lhs, env)
                if try isTruthy(left, line)
                    == false {
                    return left
                }
                return try eval(rhs, env)
            }
            if op == "or" {
                let left = try eval(lhs, env)
                if try isTruthy(left, line) {
                    return left
                }
                return try eval(rhs, env)
            }
            let left = try eval(lhs, env)
            let right = try eval(rhs, env)
            return try evalBinary(
                op, left, right)
        case .compare(let first,
                      let chain):
            var left = try eval(first, env)
            for (op, expr) in chain {
                let right = try eval(
                    expr, env)
                let ok = try evalCompare(
                    op, left, right, line)
                if !ok {
                    return .bool(false)
                }
                left = right
            }
            return .bool(true)
        case .call(let callee, let argExprs,
                   let kwExprs):
            let fn = try eval(callee, env)
            var args: [PyValue] = []
            for argExpr in argExprs {
                args.append(
                    try eval(argExpr, env))
            }
            var kwargs: [(String, PyValue)]
                = []
            for (name, kwExpr) in kwExprs {
                kwargs.append(
                    (name, try eval(
                        kwExpr, env)))
            }
            return try callValue(
                fn, args, kwargs, line)
        case .index(let baseExpr,
                    let indexExpr):
            let base = try eval(baseExpr, env)
            let index = try eval(
                indexExpr, env)
            return try getItem(
                base, index, line)
        case .slice(let baseExpr, let start,
                    let stop, let step):
            let base = try eval(baseExpr, env)
            return try getSlice(
                base,
                start != nil
                    ? try eval(start!, env)
                    : nil,
                stop != nil
                    ? try eval(stop!, env)
                    : nil,
                step != nil
                    ? try eval(step!, env)
                    : nil,
                line)
        case .attr(let baseExpr,
                   let field):
            let base = try eval(baseExpr, env)
            return try getAttr(
                base, field, line)
        case .setOf(let items):
            let set = PySet()
            for item in items {
                set.add(try eval(item, env))
            }
            return .set(set)
        case .lambda(let params,
                     let defaultExprs,
                     let bodyExpr):
            var defaults: [String: PyValue]
                = [:]
            for (param, expr)
                in defaultExprs {
                defaults[param] = try eval(
                    expr, env)
            }
            let fn = PyFunction(
                name: "<lambda>",
                params: params,
                defaults: defaults,
                body: [.returnStmt(
                    bodyExpr, line: line)],
                env: env)
            fn.isGenerator =
                Self.bodyContainsYield(fn.body)
            return .function(fn)
        case .yieldExpr(let inner):
            guard let marker = Thread
                .current.threadDictionary[
                    "pygen"] as? NSNumber,
                  let gen = generatorRegistry[
                    marker.intValue] else {
                throw PyError(
                    "SyntaxError",
                    "'yield' outside a "
                        + "generator",
                    line: line)
            }
            var value = PyValue.none
            if let inner = inner {
                value = try eval(inner, env)
            }
            return gen.suspend(value)
        case .listComp(let elem,
                       let clauses):
            let list = PyList()
            try runCompClauses(
                clauses, env) { scope in
                list.items.append(
                    try self.eval(elem, scope))
            }
            return .list(list)
        case .setComp(let elem,
                      let clauses):
            let set = PySet()
            try runCompClauses(
                clauses, env) { scope in
                set.add(try self.eval(
                    elem, scope))
            }
            return .set(set)
        case .dictComp(let keyExpr,
                       let valueExpr,
                       let clauses):
            let dict = PyDict()
            try runCompClauses(
                clauses, env) { scope in
                let key = try self.eval(
                    keyExpr, scope)
                let value = try self.eval(
                    valueExpr, scope)
                dict.set(key, value)
            }
            return .dict(dict)
        case .genExp(let elem,
                     let clauses):
            // A generator expression is a
            // little generator function the
            // clauses fold into: fors
            // outside-in, filters wrapped
            // around the yield.
            var body: [PyStmt] = [
                .expr(.yieldExpr(elem),
                      line: line)]
            for (target, iterable, conds)
                in clauses.reversed() {
                var inner = body
                for cond in conds.reversed() {
                    inner = [.ifElse(
                        [(cond, inner)], [],
                        line: line)]
                }
                body = [.forLoop(
                    target, iterable, inner,
                    line: line)]
            }
            let fn = PyFunction(
                name: "<genexpr>",
                params: [],
                defaults: [:],
                body: body, env: env)
            fn.isGenerator = true
            return .generator(PyGenerator(
                fn: fn, args: [],
                kwargs: [], interp: self))
        case .ternary(let value, let cond,
                      let other):
            if try isTruthy(
                try eval(cond, env), line) {
                return try eval(value, env)
            }
            return try eval(other, env)
        }
    }

    /// An f-string hole: lex and parse the
    /// little expression all over again.
    func evalFragment(_ source: String,
                      _ env: PyEnv,
                      _ line: Int) throws
        -> PyValue {
        var lexer = PyLexer(source)
        let tokens = try lexer.tokenize()
        var parser = PyParser(
            tokens: tokens)
        let expr = try parser.parseExpr()
        return try eval(expr, env)
    }

    func evalUnaryNum(_ op: String,
                      _ value: PyValue,
                      _ line: Int) throws
        -> PyValue {
        switch value {
        case .int(let n):
            if op == "-" { return .int(-n) }
            if op == "+" { return .int(n) }
            if op == "~" { return .int(~n) }
        case .float(let d):
            if op == "-" {
                return .float(-d)
            }
            if op == "+" {
                return .float(d)
            }
        case .bool(let b):
            if op == "-" {
                return .int(b ? -1 : 0)
            }
            if op == "+" {
                return .int(b ? 1 : 0)
            }
        default:
            break
        }
        throw PyError(
            "TypeError",
            "bad operand type for unary "
                + "\(op): "
                + "'\(PyFormat.typeName(value))'",
            line: line)
    }

    func asDouble(_ value: PyValue)
        -> Double? {
        switch value {
        case .int(let n): return Double(n)
        case .float(let d): return d
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    func asInt(_ value: PyValue) -> Int? {
        switch value {
        case .int(let n): return n
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    func floorDiv(_ a: Int, _ b: Int)
        -> Int {
        var q = a / b
        if a % b != 0,
           (a < 0) != (b < 0) {
            q -= 1
        }
        return q
    }

    func evalBinary(_ op: String,
                    _ left: PyValue,
                    _ right: PyValue) throws
        -> PyValue {
        let line = frames.last?.line ?? 0
        // An instance holding the dunder
        // speaks first; its mirror on the
        // right speaks second.
        if let names = dunderNames(op) {
            if case .instance(let obj) =
                left,
               let result = try dunder(
                   obj, names.0, [right],
                   line) {
                return result
            }
            if case .instance(let obj) =
                right,
               let result = try dunder(
                   obj, names.1, [left],
                   line) {
                return result
            }
        }
        // String and list shapes first.
        switch (op, left, right) {
        case ("+", .str(let a),
              .str(let b)):
            return .str(a + b)
        case ("+", .list(let a),
              .list(let b)):
            return .list(PyList(
                a.items + b.items))
        case ("*", .str(let a),
              .int(let n)),
             ("*", .int(let n),
              .str(let a)):
            if n <= 0 {
                return .str("")
            }
            return .str(String(
                repeating: a, count: n))
        case ("*", .list(let a),
              .int(let n)),
             ("*", .int(let n),
              .list(let a)):
            if n <= 0 {
                return .list(PyList())
            }
            var items: [PyValue] = []
            for _ in 0..<n {
                items += a.items
            }
            return .list(PyList(items))
        case ("|", .set(let a),
              .set(let b)):
            let out = PySet()
            for item in a.items {
                out.add(item)
            }
            for item in b.items {
                out.add(item)
            }
            return .set(out)
        case ("&", .set(let a),
              .set(let b)):
            let out = PySet()
            for item in a.items
                where b.contains(item) {
                out.add(item)
            }
            return .set(out)
        case ("-", .set(let a),
              .set(let b)):
            let out = PySet()
            for item in a.items
                where !b.contains(item) {
                out.add(item)
            }
            return .set(out)
        case ("^", .set(let a),
              .set(let b)):
            let out = PySet()
            for item in a.items
                where !b.contains(item) {
                out.add(item)
            }
            for item in b.items
                where !a.contains(item) {
                out.add(item)
            }
            return .set(out)
        case ("%", .str(let format), _):
            return .str(try formatString(
                format, right, line))
        default:
            break
        }
        // Integer arithmetic keeps its
        // exactness; floats promote.
        if let a = asInt(left),
           let b = asInt(right) {
            switch op {
            case "+": return .int(a + b)
            case "-": return .int(a - b)
            case "*": return .int(a * b)
            case "/":
                if b == 0 {
                    throw PyError(
                        "ZeroDivisionError",
                        "division by zero",
                        line: line)
                }
                return .float(
                    Double(a) / Double(b))
            case "//":
                if b == 0 {
                    throw PyError(
                        "ZeroDivisionError",
                        "integer division or "
                            + "modulo by zero",
                        line: line)
                }
                return .int(floorDiv(a, b))
            case "%":
                if b == 0 {
                    throw PyError(
                        "ZeroDivisionError",
                        "integer division or "
                            + "modulo by zero",
                        line: line)
                }
                return .int(
                    a - floorDiv(a, b) * b)
            case "**":
                if b >= 0 {
                    var result = 1
                    for _ in 0..<b {
                        result *= a
                    }
                    return .int(result)
                }
                return .float(
                    pow(Double(a),
                        Double(b)))
            case "<<":
                return .int(a << b)
            case ">>":
                return .int(a >> b)
            case "&": return .int(a & b)
            case "|": return .int(a | b)
            case "^": return .int(a ^ b)
            default:
                break
            }
        }
        if let a = asDouble(left),
           let b = asDouble(right) {
            switch op {
            case "+":
                return .float(a + b)
            case "-":
                return .float(a - b)
            case "*":
                return .float(a * b)
            case "/":
                if b == 0 {
                    throw PyError(
                        "ZeroDivisionError",
                        "float division by "
                            + "zero",
                        line: line)
                }
                return .float(a / b)
            case "//":
                if b == 0 {
                    throw PyError(
                        "ZeroDivisionError",
                        "float floor division "
                            + "by zero",
                        line: line)
                }
                return .float(
                    (a / b).rounded(.down))
            case "%":
                if b == 0 {
                    throw PyError(
                        "ZeroDivisionError",
                        "float modulo",
                        line: line)
                }
                var r = a.truncatingRemainder(
                    dividingBy: b)
                if r != 0,
                   (r < 0) != (b < 0) {
                    r += b
                }
                return .float(r)
            case "**":
                return .float(pow(a, b))
            default:
                break
            }
        }
        throw PyError(
            "TypeError",
            "unsupported operand type(s) "
                + "for \(op): "
                + "'\(PyFormat.typeName(left))' "
                + "and "
                + "'\(PyFormat.typeName(right))'",
            line: line)
    }

    /// Printf's little cousin: %d %i %s %f
    /// %.Nf and %% — enough for homework.
    func formatString(_ format: String,
                      _ value: PyValue,
                      _ line: Int) throws
        -> String {
        let values: [PyValue]
        if case .tuple(let items) = value {
            values = items
        } else {
            values = [value]
        }
        var out = ""
        var used = 0
        let chars = Array(format)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c != "%" {
                out.append(c)
                i += 1
                continue
            }
            if i + 1 < chars.count,
               chars[i + 1] == "%" {
                out.append("%")
                i += 2
                continue
            }
            var j = i + 1
            var precision: Int? = nil
            if j < chars.count,
               chars[j] == "." {
                j += 1
                var digits = ""
                while j < chars.count,
                      chars[j].isNumber {
                    digits.append(chars[j])
                    j += 1
                }
                precision = Int(digits)
            }
            guard j < chars.count else {
                throw PyError(
                    "ValueError",
                    "incomplete format",
                    line: line)
            }
            let spec = chars[j]
            guard used < values.count else {
                throw PyError(
                    "TypeError",
                    "not enough arguments "
                        + "for format string",
                    line: line)
            }
            let arg = values[used]
            used += 1
            switch spec {
            case "d", "i":
                if let n = asInt(arg) {
                    out += "\(n)"
                } else if let d = asDouble(
                    arg) {
                    out += "\(Int(d))"
                } else {
                    throw PyError(
                        "TypeError",
                        "%d needs a number",
                        line: line)
                }
            case "s":
                out += PyFormat.str(arg)
            case "f":
                guard let d = asDouble(arg)
                else {
                    throw PyError(
                        "TypeError",
                        "%f needs a number",
                        line: line)
                }
                out += String(
                    format: "%.\(precision ?? 6)f",
                    d)
            default:
                throw PyError(
                    "ValueError",
                    "unsupported format "
                        + "character "
                        + "'\(spec)'",
                    line: line)
            }
            i = j + 1
        }
        return out
    }
}

// MARK: - Comparisons, items, attributes

extension PyInterp {
    /// -1 / 0 / 1 ordering where python
    /// allows one; nil where it refuses.
    func ordering(_ a: PyValue,
                  _ b: PyValue) -> Int? {
        if let x = asDouble(a),
           let y = asDouble(b) {
            if x < y { return -1 }
            if x > y { return 1 }
            return 0
        }
        switch (a, b) {
        case (.str(let x), .str(let y)):
            if x < y { return -1 }
            if x > y { return 1 }
            return 0
        case (.bool(let x), .bool(let y)):
            if x == y { return 0 }
            return x ? 1 : -1
        default:
            return nil
        }
    }

    func evalCompare(_ op: String,
                     _ left: PyValue,
                     _ right: PyValue,
                     _ line: Int) throws
        -> Bool {
        switch op {
        case "==":
            if let verdict = try eqDunder(
                left, right, line) {
                return verdict
            }
            return PyFormat.equals(
                left, right)
        case "!=":
            if let verdict = try eqDunder(
                left, right, line) {
                return !verdict
            }
            return !PyFormat.equals(
                left, right)
        case "is", "is not":
            let same: Bool
            switch (left, right) {
            case (.none, .none):
                same = true
            case (.bool(let a),
                  .bool(let b)):
                same = a == b
            case (.list(let a),
                  .list(let b)):
                same = a === b
            case (.dict(let a),
                  .dict(let b)):
                same = a === b
            case (.instance(let a),
                  .instance(let b)):
                same = a === b
            case (.cls(let a),
                  .cls(let b)):
                same = a === b
            case (.set(let a),
                  .set(let b)):
                same = a === b
            default:
                same = PyFormat.equals(
                    left, right)
            }
            return op == "is" ? same : !same
        case "in", "not in":
            let found = try contains(
                right, left, line)
            return op == "in" ? found
                : !found
        default:
            if let verdict = try orderDunder(
                op, left, right, line) {
                return verdict
            }
            guard let order = ordering(
                left, right) else {
                throw PyError(
                    "TypeError",
                    "'\(op)' not supported "
                        + "between "
                        + "'\(PyFormat.typeName(left))' "
                        + "and "
                        + "'\(PyFormat.typeName(right))'",
                    line: line)
            }
            switch op {
            case "<": return order < 0
            case "<=": return order <= 0
            case ">": return order > 0
            case ">=": return order >= 0
            default:
                throw PyError(
                    "SyntaxError",
                    "bad comparison",
                    line: line)
            }
        }
    }

    func contains(_ container: PyValue,
                  _ needle: PyValue,
                  _ line: Int) throws -> Bool {
        switch container {
        case .str(let text):
            guard case .str(let bit) =
                needle else {
                throw PyError(
                    "TypeError",
                    "'in <string>' needs a "
                        + "string on the left",
                    line: line)
            }
            return text.contains(bit)
        case .list(let list):
            return list.items.contains {
                PyFormat.equals($0, needle)
            }
        case .tuple(let items):
            return items.contains {
                PyFormat.equals($0, needle)
            }
        case .dict(let dict):
            return dict.get(needle) != nil
        case .set(let set):
            return set.contains(needle)
        case .instance(let obj):
            if obj.cls.lookup("__contains__")
                != nil {
                let verdict = try callMethod(
                    container, "__contains__",
                    [needle], [], line)
                return PyFormat.truthy(
                    verdict)
            }
            // No __contains__: walk it.
            return try iterate(container)
                .contains {
                    PyFormat.equals($0, needle)
                }
        case .range(let start, let stop,
                    let step):
            guard let n = asInt(needle)
            else { return false }
            if step > 0 {
                return n >= start && n < stop
                    && (n - start) % step == 0
            }
            if step < 0 {
                return n <= start && n > stop
                    && (start - n) % (-step)
                        == 0
            }
            return false
        default:
            throw PyError(
                "TypeError",
                "argument of type "
                    + "'\(PyFormat.typeName(container))' "
                    + "is not iterable",
                line: line)
        }
    }

    func getItem(_ base: PyValue,
                 _ index: PyValue,
                 _ line: Int) throws
        -> PyValue {
        switch base {
        case .instance(let obj):
            guard obj.cls.lookup(
                "__getitem__") != nil else {
                throw PyError(
                    "TypeError",
                    "'\(obj.cls.name)' "
                        + "object is not "
                        + "subscriptable",
                    line: line)
            }
            return try callMethod(
                base, "__getitem__",
                [index], [], line)
        case .list(let list):
            let at = try listIndexOf(
                index, list.items.count,
                "list", line)
            return list.items[at]
        case .tuple(let items):
            let at = try listIndexOf(
                index, items.count,
                "tuple", line)
            return items[at]
        case .str(let text):
            let chars = Array(text)
            let at = try listIndexOf(
                index, chars.count,
                "string", line)
            return .str(String(chars[at]))
        case .dict(let dict):
            guard let value = dict.get(
                index) else {
                throw PyError(
                    "KeyError",
                    PyFormat.repr(index),
                    line: line)
            }
            return value
        case .range:
            let items = try iterate(base)
            let at = try listIndexOf(
                index, items.count,
                "range", line)
            return items[at]
        default:
            throw PyError(
                "TypeError",
                "'\(PyFormat.typeName(base))' "
                    + "object is not "
                    + "subscriptable",
                line: line)
        }
    }

    func listIndexOf(_ index: PyValue,
                     _ count: Int,
                     _ what: String,
                     _ line: Int) throws
        -> Int {
        guard let raw = asInt(index) else {
            throw PyError(
                "TypeError",
                "\(what) indices must be "
                    + "integers",
                line: line)
        }
        let at = raw < 0 ? raw + count : raw
        guard at >= 0, at < count else {
            throw PyError(
                "IndexError",
                "\(what) index out of range",
                line: line)
        }
        return at
    }

    func sliceParts(_ count: Int,
                    _ start: PyValue?,
                    _ stop: PyValue?,
                    _ step: PyValue?,
                    _ line: Int) throws
        -> [Int] {
        let stride = step.flatMap {
            asInt($0)
        } ?? 1
        guard stride != 0 else {
            throw PyError(
                "ValueError",
                "slice step cannot be zero",
                line: line)
        }
        func clamp(_ value: PyValue?,
                   _ low: Int, _ high: Int,
                   _ fallback: Int) -> Int {
            guard let value = value,
                  let raw = asInt(value)
            else { return fallback }
            var at = raw
            if at < 0 { at += count }
            return max(low, min(at, high))
        }
        var out: [Int] = []
        if stride > 0 {
            let from = clamp(
                start, 0, count, 0)
            let to = clamp(
                stop, 0, count, count)
            var at = from
            while at < to {
                out.append(at)
                at += stride
            }
        } else {
            let from = clamp(
                start, -1, count - 1,
                count - 1)
            let to = clamp(
                stop, -1, count - 1, -1)
            var at = from
            while at > to {
                out.append(at)
                at += stride
            }
        }
        return out
    }

    func getSlice(_ base: PyValue,
                  _ start: PyValue?,
                  _ stop: PyValue?,
                  _ step: PyValue?,
                  _ line: Int) throws
        -> PyValue {
        switch base {
        case .str(let text):
            let chars = Array(text)
            let picks = try sliceParts(
                chars.count, start, stop,
                step, line)
            return .str(String(
                picks.map { chars[$0] }))
        case .list(let list):
            let picks = try sliceParts(
                list.items.count, start,
                stop, step, line)
            return .list(PyList(
                picks.map {
                    list.items[$0]
                }))
        case .tuple(let items):
            let picks = try sliceParts(
                items.count, start, stop,
                step, line)
            return .tuple(
                picks.map { items[$0] })
        default:
            throw PyError(
                "TypeError",
                "'\(PyFormat.typeName(base))' "
                    + "object is not "
                    + "subscriptable",
                line: line)
        }
    }

    func getAttr(_ base: PyValue,
                 _ field: String,
                 _ line: Int) throws
        -> PyValue {
        switch base {
        case .module(let name):
            return try moduleAttr(
                name, field, line)
        case .str, .list, .dict, .file,
             .set, .generator, .seqIter:
            return .bound(base, field)
        case .instance(let obj):
            if let value = obj.attrs[field] {
                return value
            }
            if let (value, _) = obj.cls
                .lookupEntry(field) {
                // A function found on the
                // class binds; a plain class
                // attribute reads as itself.
                if case .function = value {
                    return .bound(base, field)
                }
                return value
            }
            if obj.cls.lookup("__getattr__")
                != nil {
                return try callMethod(
                    base, "__getattr__",
                    [.str(field)], [], line)
            }
            throw PyError(
                "AttributeError",
                "'\(obj.cls.name)' object "
                    + "has no attribute "
                    + "'\(field)'",
                line: line)
        case .cls(let cls):
            if let value = cls.lookup(
                field) {
                return value
            }
            throw PyError(
                "AttributeError",
                "type object '\(cls.name)' "
                    + "has no attribute "
                    + "'\(field)'",
                line: line)
        case .superProxy(let obj,
                         let after):
            let mro = obj.cls.mro()
            if let at = mro.firstIndex(
                where: { $0 === after }) {
                for cls in mro.dropFirst(
                    at + 1) {
                    if let value = cls.attrs[
                        field] {
                        if case .function =
                            value {
                            return .bound(
                                base, field)
                        }
                        return value
                    }
                }
            }
            throw PyError(
                "AttributeError",
                "'super' object has no "
                    + "attribute '\(field)'",
                line: line)
        default:
            throw PyError(
                "AttributeError",
                "'\(PyFormat.typeName(base))' "
                    + "object has no "
                    + "attribute '\(field)'",
                line: line)
        }
    }
}

// MARK: - Instances at work

extension PyInterp {
    /// Truth, python's way: an instance
    /// answers through __bool__, then
    /// __len__; everything else reads
    /// the plain table.
    func isTruthy(_ value: PyValue,
                  _ line: Int) throws -> Bool {
        if case .instance(let obj) = value {
            if let verdict = try dunder(
                obj, "__bool__", [], line) {
                return PyFormat.truthy(
                    verdict)
            }
            if let length = try dunder(
                obj, "__len__", [], line),
               let n = asInt(length) {
                return n != 0
            }
        }
        return PyFormat.truthy(value)
    }

    /// Runs a dunder on an instance when
    /// its class defines one; nil when
    /// the class stays silent.
    func dunder(_ obj: PyInstance,
                _ name: String,
                _ args: [PyValue],
                _ line: Int) throws
        -> PyValue? {
        guard obj.cls.lookup(name) != nil
        else { return nil }
        return try callMethod(
            .instance(obj), name, args, [],
            line)
    }

    /// How a value reads aloud: an
    /// instance with __str__ (else
    /// __repr__) speaks for itself.
    func textOf(_ value: PyValue)
        -> String {
        if case .instance(let obj) = value {
            if let said = try? dunderText(
                obj, "__str__") {
                return said
            }
            if let said = try? dunderText(
                obj, "__repr__") {
                return said
            }
        }
        return PyFormat.str(value)
    }

    /// How a value reads in a listing:
    /// __repr__ first, then __str__.
    func reprOf(_ value: PyValue)
        -> String {
        if case .instance(let obj) = value {
            if let said = try? dunderText(
                obj, "__repr__") {
                return said
            }
            if let said = try? dunderText(
                obj, "__str__") {
                return said
            }
        }
        return PyFormat.repr(value)
    }

    private func dunderText(
        _ obj: PyInstance, _ name: String)
        throws -> String? {
        guard let result = try dunder(
            obj, name, [],
            frames.last?.line ?? 0)
        else { return nil }
        guard case .str(let text) = result
        else { return nil }
        return text
    }

    /// The (forward, reflected) dunder
    /// names for a binary operator.
    func dunderNames(_ op: String)
        -> (String, String)? {
        switch op {
        case "+":
            return ("__add__", "__radd__")
        case "-":
            return ("__sub__", "__rsub__")
        case "*":
            return ("__mul__", "__rmul__")
        case "/":
            return ("__truediv__",
                    "__rtruediv__")
        case "//":
            return ("__floordiv__",
                    "__rfloordiv__")
        case "%":
            return ("__mod__", "__rmod__")
        case "**":
            return ("__pow__", "__rpow__")
        case "&":
            return ("__and__", "__rand__")
        case "|":
            return ("__or__", "__ror__")
        case "^":
            return ("__xor__", "__rxor__")
        case "<<":
            return ("__lshift__",
                    "__rlshift__")
        case ">>":
            return ("__rshift__",
                    "__rrshift__")
        default: return nil
        }
    }

    /// __eq__ when a class offers one.
    func eqDunder(_ left: PyValue,
                  _ right: PyValue,
                  _ line: Int) throws
        -> Bool? {
        if case .instance(let obj) = left,
           let verdict = try dunder(
               obj, "__eq__", [right],
               line) {
            return try isTruthy(
                verdict, line)
        }
        if case .instance(let obj) = right,
           let verdict = try dunder(
               obj, "__eq__", [left],
               line) {
            return try isTruthy(
                verdict, line)
        }
        return nil
    }

    /// The ordering dunders, mirrored.
    func orderDunder(_ op: String,
                     _ left: PyValue,
                     _ right: PyValue,
                     _ line: Int) throws
        -> Bool? {
        let names: [String: String] = [
            "<": "__lt__", "<=": "__le__",
            ">": "__gt__", ">=": "__ge__",
        ]
        let mirrors: [String: String] = [
            "<": "__gt__", "<=": "__ge__",
            ">": "__lt__", ">=": "__le__",
        ]
        if case .instance(let obj) = left,
           let name = names[op],
           let verdict = try dunder(
               obj, name, [right], line) {
            return try isTruthy(
                verdict, line)
        }
        if case .instance(let obj) = right,
           let name = mirrors[op],
           let verdict = try dunder(
               obj, name, [left], line) {
            return try isTruthy(
                verdict, line)
        }
        return nil
    }

    /// Walks a comprehension's clauses in
    /// one fresh scope hanging off the
    /// enclosing one — loop variables
    /// live and die inside it, like
    /// python's own.
    func runCompClauses(
        _ clauses: [(PyExpr, PyExpr,
                     [PyExpr])],
        _ env: PyEnv,
        _ emit: (PyEnv) throws -> Void)
        throws {
        let scope = PyEnv(parent: env)
        try walkCompClause(
            clauses, 0, env, scope, emit)
    }

    private func walkCompClause(
        _ clauses: [(PyExpr, PyExpr,
                     [PyExpr])],
        _ index: Int,
        _ outer: PyEnv,
        _ scope: PyEnv,
        _ emit: (PyEnv) throws -> Void)
        throws {
        if index == clauses.count {
            try emit(scope)
            return
        }
        let (target, iterableExpr, conds) =
            clauses[index]
        let source = try eval(
            iterableExpr,
            index == 0 ? outer : scope)
        func step(_ item: PyValue) throws {
            try assignTarget(
                target, item, scope)
            for cond in conds {
                let pass = try isTruthy(
                    try eval(cond, scope),
                    frames.last?.line ?? 0)
                if !pass { return }
            }
            try walkCompClause(
                clauses, index + 1, outer,
                scope, emit)
        }
        if case .generator(let gen) =
            source {
            while let item = try gen
                .advance(sent: .none) {
                try step(item)
            }
        } else {
            for item in try iterate(
                source) {
                try step(item)
            }
        }
    }

    /// Whether a body yields anywhere of
    /// its own — a nested function's
    /// yields are that function's affair.
    static func bodyContainsYield(
        _ body: [PyStmt]) -> Bool {
        for stmt in body {
            switch stmt {
            case .def, .classDef:
                continue
            case .expr(let expr, _):
                if exprContainsYield(expr) {
                    return true
                }
            case .assign(_, let value, _):
                if exprContainsYield(value) {
                    return true
                }
            case .augAssign(_, _, let v, _):
                if exprContainsYield(v) {
                    return true
                }
            case .ifElse(let arms,
                         let fallback, _):
                for (cond, arm) in arms {
                    if exprContainsYield(cond)
                        || bodyContainsYield(
                            arm) {
                        return true
                    }
                }
                if bodyContainsYield(
                    fallback) {
                    return true
                }
            case .whileLoop(let cond,
                            let inner, _):
                if exprContainsYield(cond)
                    || bodyContainsYield(
                        inner) {
                    return true
                }
            case .forLoop(let target,
                          let iterable,
                          let inner, _):
                if exprContainsYield(target)
                    || exprContainsYield(
                        iterable)
                    || bodyContainsYield(
                        inner) {
                    return true
                }
            case .returnStmt(let expr, _):
                if let expr = expr,
                   exprContainsYield(expr) {
                    return true
                }
            case .tryExcept(let inner,
                            let handlers,
                            let elseBody,
                            let finallyBody,
                            _):
                if bodyContainsYield(inner)
                    || bodyContainsYield(
                        elseBody)
                    || bodyContainsYield(
                        finallyBody) {
                    return true
                }
                for (_, _, arm) in handlers
                where bodyContainsYield(arm) {
                    return true
                }
            case .withStmt(let item, _,
                           let inner, _):
                if exprContainsYield(item)
                    || bodyContainsYield(
                        inner) {
                    return true
                }
            case .raiseStmt(let expr, _):
                if let expr = expr,
                   exprContainsYield(expr) {
                    return true
                }
            case .assertStmt(let test,
                             let message, _):
                if exprContainsYield(test) {
                    return true
                }
                if let message = message,
                   exprContainsYield(
                    message) {
                    return true
                }
            default:
                continue
            }
        }
        return false
    }

    static func exprContainsYield(
        _ expr: PyExpr) -> Bool {
        switch expr {
        case .yieldExpr:
            return true
        case .lambda:
            return false
        case .binary(_, let a, let b):
            return exprContainsYield(a)
                || exprContainsYield(b)
        case .unary(_, let a):
            return exprContainsYield(a)
        case .compare(let first,
                      let chain):
            if exprContainsYield(first) {
                return true
            }
            return chain.contains {
                exprContainsYield($0.1)
            }
        case .call(let callee, let args,
                   let kwargs):
            if exprContainsYield(callee) {
                return true
            }
            if args.contains(
                where: exprContainsYield) {
                return true
            }
            return kwargs.contains {
                exprContainsYield($0.1)
            }
        case .index(let base, let idx):
            return exprContainsYield(base)
                || exprContainsYield(idx)
        case .slice(let base, let a,
                    let b, let c):
            if exprContainsYield(base) {
                return true
            }
            for part in [a, b, c] {
                if let part = part,
                   exprContainsYield(part) {
                    return true
                }
            }
            return false
        case .attr(let base, _):
            return exprContainsYield(base)
        case .ternary(let v, let c, let o):
            return exprContainsYield(v)
                || exprContainsYield(c)
                || exprContainsYield(o)
        case .listOf(let items),
             .setOf(let items),
             .tupleOf(let items):
            return items.contains(
                where: exprContainsYield)
        case .dictOf(let pairs):
            return pairs.contains {
                exprContainsYield($0.0)
                    || exprContainsYield($0.1)
            }
        case .listComp(let elem,
                       let clauses),
             .setComp(let elem,
                       let clauses),
             .genExp(let elem,
                     let clauses):
            if exprContainsYield(elem) {
                return true
            }
            return clauses.contains {
                exprContainsYield($0.1)
                    || $0.2.contains(
                        where: exprContainsYield)
            }
        case .dictComp(let key, let value,
                       let clauses):
            if exprContainsYield(key)
                || exprContainsYield(value) {
                return true
            }
            return clauses.contains {
                exprContainsYield($0.1)
                    || $0.2.contains(
                        where: exprContainsYield)
            }
        default:
            return false
        }
    }
}

// MARK: - Calls

extension PyInterp {
    func callValue(_ callee: PyValue,
                   _ args: [PyValue],
                   _ kwargs: [(String, PyValue)],
                   _ line: Int) throws
        -> PyValue {
        switch callee {
        case .function(let fn):
            if fn.isGenerator {
                return .generator(
                    PyGenerator(
                        fn: fn, args: args,
                        kwargs: kwargs,
                        interp: self))
            }
            return try callFunction(
                fn, args, kwargs, line)
        case .cls(let cls):
            return try instantiate(
                cls, args, kwargs, line)
        case .instance(let obj):
            if obj.cls.lookup("__call__")
                != nil {
                return try callMethod(
                    callee, "__call__",
                    args, kwargs, line)
            }
            throw PyError(
                "TypeError",
                "'\(obj.cls.name)' object "
                    + "is not callable",
                line: line)
        case .builtin(let name):
            return try callBuiltin(
                name, args, kwargs, line)
        case .bound(let base, let method):
            return try callMethod(
                base, method, args, kwargs,
                line)
        default:
            throw PyError(
                "TypeError",
                "'\(PyFormat.typeName(callee))' "
                    + "object is not callable",
                line: line)
        }
    }

    func callFunction(_ fn: PyFunction,
                      _ args: [PyValue],
                      _ kwargs: [(String,
                                    PyValue)],
                      _ line: Int) throws
        -> PyValue {
        guard callDepth < 200 else {
            throw PyError(
                "RecursionError",
                "the house python caps "
                    + "calls 200 deep",
                line: line)
        }
        let local = PyEnv(parent: fn.env)
        for (index, param) in fn.params
            .enumerated() {
            if index < args.count {
                local.assignLocal(
                    param, args[index])
            } else if let fallback =
                fn.defaults[param] {
                local.assignLocal(
                    param, fallback)
            } else {
                throw PyError(
                    "TypeError",
                    "\(fn.name)() missing a "
                        + "required argument: "
                        + "'\(param)'",
                    line: line)
            }
        }
        if args.count > fn.params.count {
            throw PyError(
                "TypeError",
                "\(fn.name)() takes "
                    + "\(fn.params.count) "
                    + "arguments but "
                    + "\(args.count) were "
                    + "given",
                line: line)
        }
        for (name, value) in kwargs {
            guard fn.params.contains(name)
            else {
                throw PyError(
                    "TypeError",
                    "\(fn.name)() got an "
                        + "unexpected keyword "
                        + "argument '\(name)'",
                    line: line)
            }
            local.assignLocal(name, value)
        }
        callDepth += 1
        frames.append((fn.name, line))
        defer {
            callDepth -= 1
            frames.removeLast()
        }
        do {
            try execBlock(fn.body, local)
        } catch let signal as PySignal {
            if case .returned(let value) =
                signal {
                return value
            }
            throw PyError(
                "SyntaxError",
                "'break' or 'continue' "
                    + "outside a loop",
                line: line)
        }
        return .none
    }
}

// MARK: - Builtins

extension PyInterp {
    func needArgs(_ name: String,
                  _ args: [PyValue],
                  _ count: Int,
                  _ line: Int) throws {
        guard args.count == count else {
            throw PyError(
                "TypeError",
                "\(name)() takes exactly "
                    + "\(count) argument(s), "
                    + "\(args.count) given",
                line: line)
        }
    }

    func kwarg(_ kwargs: [(String, PyValue)],
               _ name: String) -> PyValue? {
        for (key, value) in kwargs
            where key == name {
            return value
        }
        return nil
    }

    func callBuiltin(_ name: String,
                     _ args: [PyValue],
                     _ kwargs: [(String,
                                 PyValue)],
                     _ line: Int) throws
        -> PyValue {
        switch name {
        case "print":
            var sep = " "
            var end = "\n"
            if let value = kwarg(
                kwargs, "sep"),
               case .str(let text) = value {
                sep = text
            }
            if let value = kwarg(
                kwargs, "end"),
               case .str(let text) = value {
                end = text
            }
            let text = args.map {
                textOf($0)
            }.joined(separator: sep)
            printText(text + end)
            return .none
        case "len":
            try needArgs(name, args, 1, line)
            return .int(try lengthOf(
                args[0], line))
        case "range":
            guard (1...3).contains(
                args.count) else {
                throw PyError(
                    "TypeError",
                    "range() takes 1 to 3 "
                        + "arguments",
                    line: line)
            }
            var nums: [Int] = []
            for arg in args {
                guard let n = asInt(arg)
                else {
                    throw PyError(
                        "TypeError",
                        "range() needs "
                            + "integers",
                        line: line)
                }
                nums.append(n)
            }
            if nums.count == 1 {
                return .range(0, nums[0], 1)
            }
            if nums.count == 2 {
                return .range(
                    nums[0], nums[1], 1)
            }
            return .range(
                nums[0], nums[1], nums[2])
        case "str":
            if args.isEmpty {
                return .str("")
            }
            try needArgs(name, args, 1, line)
            return .str(textOf(args[0]))
        case "repr":
            try needArgs(name, args, 1, line)
            return .str(reprOf(args[0]))
        case "int":
            return try toInt(args, line)
        case "float":
            return try toFloat(args, line)
        case "bool":
            if args.isEmpty {
                return .bool(false)
            }
            try needArgs(name, args, 1, line)
            return .bool(PyFormat.truthy(
                args[0]))
        case "list":
            if args.isEmpty {
                return .list(PyList())
            }
            try needArgs(name, args, 1, line)
            return .list(PyList(
                try iterate(args[0])))
        case "tuple":
            if args.isEmpty {
                return .tuple([])
            }
            try needArgs(name, args, 1, line)
            return .tuple(
                try iterate(args[0]))
        case "dict":
            if args.isEmpty,
               kwargs.isEmpty {
                return .dict(PyDict())
            }
            try needArgs(name, args,
                         args.isEmpty ? 0 : 1,
                         line)
            let dict = PyDict()
            if let source = args.first {
                if case .dict(let other) =
                    source {
                    for h in other.keys {
                        dict.set(
                            other.display[h]
                                ?? .none,
                            other.values[h]
                                ?? .none)
                    }
                } else {
                    for pair in try iterate(
                        source) {
                        let parts = try iterate(
                            pair)
                        guard parts.count == 2
                        else {
                            throw PyError(
                                "ValueError",
                                "dict() needs "
                                    + "pairs of "
                                    + "two",
                                line: line)
                        }
                        dict.set(parts[0],
                                 parts[1])
                    }
                }
            }
            for (key, value) in kwargs {
                dict.set(.str(key), value)
            }
            return .dict(dict)
        case "abs":
            try needArgs(name, args, 1, line)
            if let n = asInt(args[0]) {
                return .int(abs(n))
            }
            if let d = asDouble(args[0]) {
                return .float(abs(d))
            }
            throw PyError(
                "TypeError",
                "bad operand for abs()",
                line: line)
        case "min", "max":
            return try minMax(
                name, args, kwargs, line)
        case "sum":
            guard !args.isEmpty,
                  args.count <= 2 else {
                throw PyError(
                    "TypeError",
                    "sum() takes 1 or 2 "
                        + "arguments",
                    line: line)
            }
            var total: PyValue = args.count
                == 2 ? args[1] : .int(0)
            for item in try iterate(
                args[0]) {
                total = try evalBinary(
                    "+", total, item)
            }
            return total
        case "sorted":
            guard !args.isEmpty else {
                throw PyError(
                    "TypeError",
                    "sorted() needs an "
                        + "iterable",
                    line: line)
            }
            let items = try iterate(args[0])
            let sortedItems = try sortItems(
                items, kwargs, line)
            return .list(PyList(sortedItems))
        case "reversed":
            try needArgs(name, args, 1, line)
            let items = try iterate(args[0])
            return .list(PyList(
                items.reversed()))
        case "enumerate":
            guard !args.isEmpty else {
                throw PyError(
                    "TypeError",
                    "enumerate() needs an "
                        + "iterable",
                    line: line)
            }
            var start = 0
            if args.count > 1,
               let n = asInt(args[1]) {
                start = n
            }
            let items = try iterate(args[0])
            var out: [PyValue] = []
            for (offset, item) in items
                .enumerated() {
                out.append(.tuple(
                    [.int(start + offset),
                     item]))
            }
            return .list(PyList(out))
        case "zip":
            var columns: [[PyValue]] = []
            for arg in args {
                columns.append(
                    try iterate(arg))
            }
            let shortest = columns.map {
                $0.count
            }.min() ?? 0
            var out: [PyValue] = []
            for row in 0..<shortest {
                out.append(.tuple(
                    columns.map { $0[row] }))
            }
            return .list(PyList(out))
        case "type":
            try needArgs(name, args, 1, line)
            if case .instance(let obj) =
                args[0] {
                return .cls(obj.cls)
            }
            if case .cls = args[0] {
                return .str(
                    "<class 'type'>")
            }
            return .str(
                "<class '\(PyFormat.typeName(args[0]))'>")
        case "round":
            guard !args.isEmpty,
                  let d = asDouble(args[0])
            else {
                throw PyError(
                    "TypeError",
                    "round() needs a number",
                    line: line)
            }
            if args.count > 1,
               let places = asInt(args[1]) {
                let scale = pow(
                    10.0, Double(places))
                return .float(
                    (d * scale).rounded()
                        / scale)
            }
            return .int(Int(d.rounded()))
        case "ord":
            try needArgs(name, args, 1, line)
            guard case .str(let text) =
                args[0], text.count == 1,
                  let scalar = text.unicodeScalars
                    .first else {
                throw PyError(
                    "TypeError",
                    "ord() needs one "
                        + "character",
                    line: line)
            }
            return .int(Int(scalar.value))
        case "chr":
            try needArgs(name, args, 1, line)
            guard let n = asInt(args[0]),
                  let scalar = UnicodeScalar(
                    n) else {
                throw PyError(
                    "ValueError",
                    "chr() arg out of range",
                    line: line)
            }
            return .str(
                String(Character(scalar)))
        case "set", "frozenset":
            if args.isEmpty {
                return .set(PySet())
            }
            try needArgs(name, args, 1, line)
            let set = PySet()
            for item in try iterate(
                args[0]) {
                set.add(item)
            }
            return .set(set)
        case "isinstance":
            try needArgs(name, args, 2, line)
            return .bool(try isInstance(
                args[0], of: args[1], line))
        case "issubclass":
            try needArgs(name, args, 2, line)
            guard case .cls(let sub) =
                args[0] else {
                throw PyError(
                    "TypeError",
                    "issubclass() arg 1 "
                        + "must be a class",
                    line: line)
            }
            return .bool(try isSubclass(
                sub, of: args[1], line))
        case "getattr":
            guard (args.count == 2
                || args.count == 3),
                  case .str(let field) =
                    args[1] else {
                throw PyError(
                    "TypeError",
                    "getattr() takes an "
                        + "object and an "
                        + "attribute name",
                    line: line)
            }
            do {
                return try getAttr(
                    args[0], field, line)
            } catch let error as PyError
                where error.kind
                    == "AttributeError" {
                if args.count == 3 {
                    return args[2]
                }
                throw error
            }
        case "setattr":
            try needArgs(name, args, 3, line)
            guard case .str(let field) =
                args[1] else {
                throw PyError(
                    "TypeError",
                    "setattr() needs an "
                        + "attribute name",
                    line: line)
            }
            try setAttr(args[0], field,
                        args[2])
            return .none
        case "hasattr":
            try needArgs(name, args, 2, line)
            guard case .str(let field) =
                args[1] else {
                throw PyError(
                    "TypeError",
                    "hasattr() needs an "
                        + "attribute name",
                    line: line)
            }
            do {
                _ = try getAttr(
                    args[0], field, line)
                return .bool(true)
            } catch let error as PyError
                where error.kind
                    == "AttributeError" {
                return .bool(false)
            }
        case "callable":
            try needArgs(name, args, 1, line)
            switch args[0] {
            case .function, .builtin,
                 .bound, .cls:
                return .bool(true)
            case .instance(let obj):
                return .bool(
                    obj.cls.lookup("__call__")
                        != nil)
            default:
                return .bool(false)
            }
        case "iter":
            try needArgs(name, args, 1, line)
            switch args[0] {
            case .generator, .seqIter:
                return args[0]
            default:
                return .seqIter(PySeqIter(
                    try iterate(args[0])))
            }
        case "next":
            guard args.count == 1
                || args.count == 2 else {
                throw PyError(
                    "TypeError",
                    "next() takes 1 or 2 "
                        + "arguments",
                    line: line)
            }
            let fallback: PyValue? =
                args.count == 2 ? args[1]
                    : nil
            switch args[0] {
            case .generator(let gen):
                if let item = try gen
                    .advance(sent: .none) {
                    return item
                }
            case .seqIter(let iter):
                if iter.index < iter.items
                    .count {
                    let item = iter.items[
                        iter.index]
                    iter.index += 1
                    return item
                }
            case .instance(let obj):
                guard obj.cls.lookup(
                    "__next__") != nil else {
                    throw PyError(
                        "TypeError",
                        "'\(obj.cls.name)' "
                            + "object is "
                            + "not an "
                            + "iterator",
                        line: line)
                }
                do {
                    return try callMethod(
                        args[0], "__next__",
                        [], [], line)
                } catch let error as PyError
                    where error.kind
                        == "StopIteration" {
                    if let fallback =
                        fallback {
                        return fallback
                    }
                    throw error
                }
            default:
                throw PyError(
                    "TypeError",
                    "'\(PyFormat.typeName(args[0]))' "
                        + "object is not "
                        + "an iterator",
                    line: line)
            }
            if let fallback = fallback {
                return fallback
            }
            throw PyError(
                "StopIteration", "",
                line: line)
        case "any":
            try needArgs(name, args, 1, line)
            for item in try iterate(
                args[0]) {
                if try isTruthy(item, line) {
                    return .bool(true)
                }
            }
            return .bool(false)
        case "all":
            try needArgs(name, args, 1, line)
            for item in try iterate(
                args[0]) {
                if try isTruthy(item, line)
                    == false {
                    return .bool(false)
                }
            }
            return .bool(true)
        case "divmod":
            try needArgs(name, args, 2, line)
            if let a = asInt(args[0]),
               let b = asInt(args[1]) {
                guard b != 0 else {
                    throw PyError(
                        "ZeroDivisionError",
                        "divmod() by zero",
                        line: line)
                }
                let q = floorDiv(a, b)
                return .tuple(
                    [.int(q),
                     .int(a - q * b)])
            }
            if let a = asDouble(args[0]),
               let b = asDouble(args[1]) {
                guard b != 0 else {
                    throw PyError(
                        "ZeroDivisionError",
                        "divmod() by zero",
                        line: line)
                }
                let q = (a / b).rounded(
                    .down)
                return .tuple(
                    [.float(q),
                     .float(a - q * b)])
            }
            throw PyError(
                "TypeError",
                "divmod() needs numbers",
                line: line)
        case "pow":
            guard args.count == 2
                || args.count == 3 else {
                throw PyError(
                    "TypeError",
                    "pow() takes 2 or 3 "
                        + "arguments",
                    line: line)
            }
            if args.count == 2 {
                return try evalBinary(
                    "**", args[0], args[1])
            }
            guard let base = asInt(args[0]),
                  let exp = asInt(args[1]),
                  let mod = asInt(args[2]),
                  mod != 0, exp >= 0 else {
                throw PyError(
                    "ValueError",
                    "pow() with a modulus "
                        + "needs integers, "
                        + "a non-zero "
                        + "modulus and a "
                        + "non-negative "
                        + "exponent here",
                    line: line)
            }
            var result = 1 % mod
            var b = ((base % mod) + mod) % mod
            var e = exp
            while e > 0 {
                if e & 1 == 1 {
                    result = (result * b) % mod
                }
                b = (b * b) % mod
                e >>= 1
            }
            if mod < 0, result > 0 {
                result += mod
            }
            return .int(result)
        case "hex", "oct", "bin":
            try needArgs(name, args, 1, line)
            guard let n = asInt(args[0])
            else {
                throw PyError(
                    "TypeError",
                    "\(name)() needs an "
                        + "integer",
                    line: line)
            }
            let radix = name == "hex"
                ? 16 : name == "oct" ? 8 : 2
            let prefix = name == "hex"
                ? "0x" : name == "oct"
                ? "0o" : "0b"
            return .str(
                (n < 0 ? "-" : "")
                    + prefix
                    + String(abs(n),
                             radix: radix))
        case "hash":
            try needArgs(name, args, 1, line)
            return .int(hashOf(args[0]))
        case "id":
            try needArgs(name, args, 1, line)
            switch args[0] {
            case .list(let box):
                return .int(ObjectIdentifier(
                    box).hashValue)
            case .dict(let box):
                return .int(ObjectIdentifier(
                    box).hashValue)
            case .set(let box):
                return .int(ObjectIdentifier(
                    box).hashValue)
            case .instance(let box):
                return .int(ObjectIdentifier(
                    box).hashValue)
            case .cls(let box):
                return .int(ObjectIdentifier(
                    box).hashValue)
            case .function(let box):
                return .int(ObjectIdentifier(
                    box).hashValue)
            default:
                return .int(hashOf(args[0]))
            }
        case "vars":
            guard args.count == 1 else {
                throw PyError(
                    "TypeError",
                    "vars() takes one "
                        + "object in the "
                        + "house's python",
                    line: line)
            }
            let dict = PyDict()
            switch args[0] {
            case .instance(let obj):
                for (key, value)
                    in obj.attrs {
                    dict.set(.str(key),
                             value)
                }
            case .cls(let cls):
                for (key, value)
                    in cls.attrs {
                    dict.set(.str(key),
                             value)
                }
            default:
                throw PyError(
                    "TypeError",
                    "vars() argument must "
                        + "have a __dict__",
                    line: line)
            }
            return .dict(dict)
        case "dir":
            try needArgs(name, args, 1, line)
            var names: Set<String> = []
            switch args[0] {
            case .instance(let obj):
                names.formUnion(
                    obj.attrs.keys)
                for cls in obj.cls.mro() {
                    names.formUnion(
                        cls.attrs.keys)
                }
            case .cls(let cls):
                for base in cls.mro() {
                    names.formUnion(
                        base.attrs.keys)
                }
            case .module(let module):
                names.formUnion(
                    moduleMembers(module))
            default:
                break
            }
            return .list(PyList(
                names.sorted().map {
                    PyValue.str($0)
                }))
        case "super":
            return try superBuiltin(
                args, line)
        case "open":
            return try openFile(
                args, kwargs, line)
        case "input":
            throw PyError(
                "RuntimeError",
                "input() is not in the "
                    + "house's python yet — "
                    + "feed the program from "
                    + "a file or its "
                    + "arguments (argv)",
                line: line)
        default:
            throw PyError(
                "NameError",
                "name '\(name)' is not "
                    + "defined",
                line: line)
        }
    }

    func lengthOf(_ value: PyValue,
                  _ line: Int) throws -> Int {
        switch value {
        case .str(let s): return s.count
        case .list(let l):
            return l.items.count
        case .dict(let d): return d.count
        case .tuple(let t): return t.count
        case .set(let s): return s.count
        case .instance(let obj):
            if let length = try dunder(
                obj, "__len__", [], line),
               let n = asInt(length) {
                return n
            }
            throw PyError(
                "TypeError",
                "object of type "
                    + "'\(obj.cls.name)' "
                    + "has no len()",
                line: line)
        case .range:
            return try iterate(value).count
        default:
            throw PyError(
                "TypeError",
                "object of type "
                    + "'\(PyFormat.typeName(value))' "
                    + "has no len()",
                line: line)
        }
    }

    func toInt(_ args: [PyValue],
               _ line: Int) throws -> PyValue {
        if args.isEmpty {
            return .int(0)
        }
        switch args[0] {
        case .int(let n):
            return .int(n)
        case .float(let d):
            return .int(Int(d))
        case .bool(let b):
            return .int(b ? 1 : 0)
        case .str(let text):
            let clean = text
                .trimmingCharacters(
                    in: .whitespaces)
            if let n = Int(clean) {
                return .int(n)
            }
            throw PyError(
                "ValueError",
                "invalid literal for int(): "
                    + "'\(text)'",
                line: line)
        default:
            throw PyError(
                "TypeError",
                "int() can't make an "
                    + "integer from a "
                    + PyFormat.typeName(
                        args[0]),
                line: line)
        }
    }

    func toFloat(_ args: [PyValue],
                 _ line: Int) throws
        -> PyValue {
        if args.isEmpty {
            return .float(0)
        }
        if let d = asDouble(args[0]) {
            return .float(d)
        }
        if case .str(let text) = args[0] {
            let clean = text
                .trimmingCharacters(
                    in: .whitespaces)
            if let d = Double(clean) {
                return .float(d)
            }
            throw PyError(
                "ValueError",
                "could not convert string "
                    + "to float: '\(text)'",
                line: line)
        }
        throw PyError(
            "TypeError",
            "float() can't convert a "
                + PyFormat.typeName(args[0]),
            line: line)
    }

    func minMax(_ name: String,
                _ args: [PyValue],
                _ kwargs: [(String, PyValue)],
                _ line: Int) throws
        -> PyValue {
        var pool: [PyValue] = []
        if args.count == 1 {
            pool = try iterate(args[0])
        } else if args.count > 1 {
            pool = args
        }
        guard let first = pool.first else {
            throw PyError(
                "ValueError",
                "\(name)() arg is an empty "
                    + "sequence",
                line: line)
        }
        var best = first
        var bestKey = try sortKey(
            best, kwargs, line)
        for item in pool.dropFirst() {
            let key = try sortKey(
                item, kwargs, line)
            guard let order = ordering(
                key, bestKey) else {
                throw PyError(
                    "TypeError",
                    "'<' not supported "
                        + "between those",
                    line: line)
            }
            if (name == "min" && order < 0)
                || (name == "max"
                    && order > 0) {
                best = item
                bestKey = key
            }
        }
        return best
    }

    func sortKey(_ item: PyValue,
                 _ kwargs: [(String, PyValue)],
                 _ line: Int) throws
        -> PyValue {
        if let keyFn = kwarg(
            kwargs, "key") {
            return try callValue(
                keyFn, [item], [], line)
        }
        return item
    }

    func sortItems(_ items: [PyValue],
                   _ kwargs: [(String,
                               PyValue)],
                   _ line: Int) throws
        -> [PyValue] {
        var decorated: [(PyValue, PyValue)]
            = []
        for item in items {
            decorated.append(
                (try sortKey(
                    item, kwargs, line),
                 item))
        }
        decorated = try decorated.sorted {
            let order = ordering(
                $0.0, $1.0)
            guard let order = order else {
                throw PyError(
                    "TypeError",
                    "'<' not supported "
                        + "between those "
                        + "values",
                    line: line)
            }
            return order < 0
        }
        var result = decorated.map { $0.1 }
        if let flip = kwarg(
            kwargs, "reverse"),
           PyFormat.truthy(flip) {
            result.reverse()
        }
        return result
    }

    func openFile(_ args: [PyValue],
                  _ kwargs: [(String, PyValue)],
                  _ line: Int) throws
        -> PyValue {
        guard let first = args.first,
              case .str(let rawPath) = first
        else {
            throw PyError(
                "TypeError",
                "open() needs a path",
                line: line)
        }
        var mode = "r"
        if args.count > 1,
           case .str(let m) = args[1] {
            mode = m
        }
        let clean = BlacksiteFS.normalize(
            rawPath, cwd: BlacksiteFS.home)
        let file = PyFile(
            path: clean, mode: mode)
        if mode.contains("r")
            || mode.contains("a") {
            if let text = BlacksiteFS
                .readText(clean) {
                file.content = text
            } else if mode.contains("r") {
                throw PyError(
                    "FileNotFoundError",
                    "no such file: "
                        + "'\(rawPath)'",
                    line: line)
            }
        }
        return .file(file)
    }
}

// MARK: - Methods

extension PyInterp {
    func noArgs(_ method: String,
                _ args: [PyValue],
                _ line: Int) throws {
        guard args.isEmpty else {
            throw PyError(
                "TypeError",
                "\(method)() takes no "
                    + "arguments",
                line: line)
        }
    }

    func callMethod(_ base: PyValue,
                    _ method: String,
                    _ args: [PyValue],
                    _ kwargs: [(String,
                                PyValue)],
                    _ line: Int) throws
        -> PyValue {
        if case .module(let name) = base {
            return try moduleFunction(
                name, method, args, line)
        }
        switch base {
        case .str(let text):
            return try strMethod(
                text, method, args, line)
        case .list(let list):
            return try listMethod(
                list, method, args, kwargs,
                line)
        case .dict(let dict):
            return try dictMethod(
                dict, method, args, line)
        case .file(let file):
            return try fileMethod(
                file, method, args, line)
        case .instance(let obj):
            return try instanceMethod(
                obj, method, args, kwargs,
                line)
        case .set(let set):
            return try setMethod(
                set, method, args, line)
        case .generator(let gen):
            switch method {
            case "send":
                if let item = try gen
                    .advance(
                        sent: args.first
                            ?? .none) {
                    return item
                }
                throw PyError(
                    "StopIteration", "",
                    line: line)
            case "__next__":
                if let item = try gen
                    .advance(sent: .none) {
                    return item
                }
                throw PyError(
                    "StopIteration", "",
                    line: line)
            case "close":
                gen.forceFinish()
                return .none
            default:
                throw attrError(
                    "generator", method, line)
            }
        case .seqIter(let iter):
            if method == "__next__" {
                guard iter.index < iter
                    .items.count else {
                    throw PyError(
                        "StopIteration", "",
                        line: line)
                }
                let item = iter.items[
                    iter.index]
                iter.index += 1
                return item
            }
            throw attrError(
                "iterator", method, line)
        case .superProxy(let obj,
                         let after):
            return try superMethod(
                obj, after, method, args,
                kwargs, line)
        default:
            throw PyError(
                "AttributeError",
                "'\(PyFormat.typeName(base))' "
                    + "object has no "
                    + "attribute '\(method)'",
                line: line)
        }
    }

    /// A method call on an instance: the
    /// function is found down the mro and
    /// run with the instance bound as its
    /// first argument.
    func instanceMethod(
        _ obj: PyInstance, _ method: String,
        _ args: [PyValue],
        _ kwargs: [(String, PyValue)],
        _ line: Int) throws -> PyValue {
        guard let (value, owner) = obj.cls
            .lookupEntry(method) else {
            throw attrError(
                obj.cls.name, method, line)
        }
        guard case .function(let fn) =
            value else {
            throw PyError(
                "TypeError",
                "'\(PyFormat.typeName(value))' "
                    + "object is not "
                    + "callable",
                line: line)
        }
        methodContext.append((obj, owner))
        defer {
            methodContext.removeLast()
        }
        return try callFunction(
            fn, [.instance(obj)] + args,
            kwargs, line)
    }

    /// A method call through super: the
    /// search starts after the given
    /// class in the instance's mro, but
    /// the instance stays itself.
    func superMethod(
        _ obj: PyInstance, _ after: PyClass,
        _ method: String,
        _ args: [PyValue],
        _ kwargs: [(String, PyValue)],
        _ line: Int) throws -> PyValue {
        let mro = obj.cls.mro()
        guard let at = mro.firstIndex(
            where: { $0 === after }) else {
            throw attrError(
                "super", method, line)
        }
        for cls in mro.dropFirst(at + 1) {
            if let value = cls.attrs[
                method] {
                guard case .function(
                    let fn) = value else {
                    throw PyError(
                        "TypeError",
                        "'\(PyFormat.typeName(value))' "
                            + "object is not "
                            + "callable",
                        line: line)
                }
                methodContext.append(
                    (obj, cls))
                defer {
                    methodContext
                        .removeLast()
                }
                return try callFunction(
                    fn, [.instance(obj)]
                        + args,
                    kwargs, line)
            }
        }
        throw attrError(
            "super", method, line)
    }

    /// Calling a class: a fresh instance,
    /// then __init__ with it bound, when
    /// the class defines one.
    func instantiate(
        _ cls: PyClass, _ args: [PyValue],
        _ kwargs: [(String, PyValue)],
        _ line: Int) throws -> PyValue {
        let obj = PyInstance(cls: cls)
        let value = PyValue.instance(obj)
        if cls.lookup("__init__") != nil {
            _ = try callMethod(
                value, "__init__", args,
                kwargs, line)
        } else if !args.isEmpty
            || !kwargs.isEmpty {
            throw PyError(
                "TypeError",
                "\(cls.name)() takes no "
                    + "arguments",
                line: line)
        }
        return value
    }

    func setMethod(_ set: PySet,
                   _ method: String,
                   _ args: [PyValue],
                   _ line: Int) throws
        -> PyValue {
        switch method {
        case "add":
            try needArgs("add", args, 1,
                         line)
            set.add(args[0])
            return .none
        case "remove":
            try needArgs("remove", args, 1,
                         line)
            guard set.contains(args[0])
            else {
                throw PyError(
                    "KeyError",
                    PyFormat.repr(args[0]),
                    line: line)
            }
            set.remove(args[0])
            return .none
        case "discard":
            try needArgs("discard", args,
                         1, line)
            set.remove(args[0])
            return .none
        case "pop":
            guard let first = set.items
                .first else {
                throw PyError(
                    "KeyError",
                    "pop from an empty set",
                    line: line)
            }
            set.remove(first)
            return first
        case "clear":
            set.keys = []
            set.values = [:]
            set.display = [:]
            return .none
        case "copy":
            let out = PySet()
            for item in set.items {
                out.add(item)
            }
            return .set(out)
        case "update":
            for arg in args {
                for item in try iterate(
                    arg) {
                    set.add(item)
                }
            }
            return .none
        case "union":
            let out = PySet()
            for item in set.items {
                out.add(item)
            }
            for arg in args {
                for item in try iterate(
                    arg) {
                    out.add(item)
                }
            }
            return .set(out)
        case "intersection":
            let out = PySet()
            for item in set.items {
                var everywhere = true
                for arg in args {
                    if try !iterate(arg)
                        .contains(where: {
                            PyFormat.equals(
                                $0, item)
                        }) {
                        everywhere = false
                    }
                }
                if everywhere {
                    out.add(item)
                }
            }
            return .set(out)
        case "difference":
            let out = PySet()
            for item in set.items {
                var gone = false
                for arg in args {
                    if try iterate(arg)
                        .contains(where: {
                            PyFormat.equals(
                                $0, item)
                        }) {
                        gone = true
                    }
                }
                if !gone {
                    out.add(item)
                }
            }
            return .set(out)
        case "symmetric_difference":
            try needArgs(
                "symmetric_difference",
                args, 1, line)
            let other = try iterate(
                args[0])
            let out = PySet()
            for item in set.items
            where !other.contains(where: {
                PyFormat.equals($0, item)
            }) {
                out.add(item)
            }
            for item in other
            where !set.contains(item) {
                out.add(item)
            }
            return .set(out)
        case "issubset":
            try needArgs("issubset", args,
                         1, line)
            let other = try iterate(
                args[0])
            return .bool(set.items
                .allSatisfy { item in
                    other.contains {
                        PyFormat.equals(
                            $0, item)
                    }
                })
        case "issuperset":
            try needArgs("issuperset",
                         args, 1, line)
            let other = try iterate(
                args[0])
            return .bool(other.allSatisfy {
                set.contains($0)
            })
        case "isdisjoint":
            try needArgs("isdisjoint",
                         args, 1, line)
            let other = try iterate(
                args[0])
            return .bool(!other.contains {
                set.contains($0)
            })
        case "__contains__":
            try needArgs("__contains__",
                         args, 1, line)
            return .bool(
                set.contains(args[0]))
        case "__len__":
            return .int(set.count)
        case "__iter__":
            return .seqIter(
                PySeqIter(set.items))
        default:
            throw attrError(
                "set", method, line)
        }
    }

    /// A stable integer for a value:
    /// FNV-1a over its hash key, the same
    /// string the house's dicts key on.
    func hashOf(_ value: PyValue) -> Int {
        var hash: UInt64 =
            0xcbf29ce484222325
        for byte in PyFormat.hashKey(value)
            .utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return Int(hash & 0x3fff_ffff_ffff_ffff)
    }

    /// The member names of the house's
    /// modules, for dir().
    func moduleMembers(_ module: String)
        -> [String] {
        switch module {
        case "math":
            return ["sqrt", "floor",
                    "ceil", "fabs", "sin",
                    "cos", "tan", "asin",
                    "acos", "atan", "log",
                    "log2", "log10", "pow",
                    "factorial", "gcd",
                    "degrees", "radians",
                    "hypot", "pi", "e",
                    "tau", "inf", "nan"]
        case "random":
            return ["random", "randint",
                    "randrange", "choice",
                    "shuffle", "uniform",
                    "seed"]
        case "house":
            return ["read", "write",
                    "ls", "exists",
                    "state", "emcon"]
        case "sys":
            return ["argv"]
        default:
            return []
        }
    }

    /// Does a builtin type name match a
    /// value? (Bools are ints in python,
    /// as an isinstance(True, int) shows.)
    func kindMatches(_ value: PyValue,
                     _ kind: String) -> Bool {
        switch kind {
        case "object":
            return true
        case "int":
            if case .int = value {
                return true
            }
            if case .bool = value {
                return true
            }
            return false
        case "bool":
            if case .bool = value {
                return true
            }
            return false
        case "float":
            if case .float = value {
                return true
            }
            return false
        case "str":
            if case .str = value {
                return true
            }
            return false
        case "list":
            if case .list = value {
                return true
            }
            return false
        case "dict":
            if case .dict = value {
                return true
            }
            return false
        case "tuple":
            if case .tuple = value {
                return true
            }
            return false
        case "set", "frozenset":
            if case .set = value {
                return true
            }
            return false
        case "function":
            switch value {
            case .function, .builtin,
                 .bound:
                return true
            default:
                return false
            }
        case "type":
            if case .cls = value {
                return true
            }
            return false
        default:
            return false
        }
    }

    func isInstance(_ value: PyValue,
                    of spec: PyValue,
                    _ line: Int) throws
        -> Bool {
        switch spec {
        case .tuple(let specs):
            for sub in specs {
                if try isInstance(
                    value, of: sub, line) {
                    return true
                }
            }
            return false
        case .cls(let cls):
            guard case .instance(
                let obj) = value else {
                return false
            }
            return obj.cls.mro().contains {
                $0 === cls
            }
        case .builtin(let kind):
            return kindMatches(value, kind)
        default:
            throw PyError(
                "TypeError",
                "isinstance() argument 2 "
                    + "must be a type",
                line: line)
        }
    }

    func isSubclass(_ sub: PyClass,
                    of spec: PyValue,
                    _ line: Int) throws
        -> Bool {
        switch spec {
        case .tuple(let specs):
            for part in specs {
                if try isSubclass(
                    sub, of: part, line) {
                    return true
                }
            }
            return false
        case .cls(let cls):
            return sub.mro().contains {
                $0 === cls
            }
        case .builtin(let kind):
            return kind == "object"
        default:
            throw PyError(
                "TypeError",
                "issubclass() argument 2 "
                    + "must be a class",
                line: line)
        }
    }

    /// super(): with no arguments it
    /// reads the method frame the call
    /// layer keeps; with two, it checks
    /// the pair the way python does.
    func superBuiltin(_ args: [PyValue],
                      _ line: Int) throws
        -> PyValue {
        if args.isEmpty {
            guard let (obj, owner) =
                methodContext.last else {
                throw PyError(
                    "RuntimeError",
                    "super() with no "
                        + "arguments needs a "
                        + "method running on "
                        + "an instance — or "
                        + "pass both: "
                        + "super(Base, self)",
                    line: line)
            }
            return .superProxy(obj, owner)
        }
        guard args.count == 2,
              case .cls(let cls) = args[0],
              case .instance(let obj) =
                args[1] else {
            throw PyError(
                "TypeError",
                "super() takes the class "
                    + "and the instance: "
                    + "super(Base, self)",
                line: line)
        }
        guard obj.cls.mro().contains(
            where: { $0 === cls }) else {
            throw PyError(
                "TypeError",
                "super(): the instance "
                    + "is not of the "
                    + "given class",
                line: line)
        }
        return .superProxy(obj, cls)
    }

    func attrError(_ type: String,
                   _ method: String,
                   _ line: Int) -> PyError {
        PyError(
            "AttributeError",
            "'\(type)' object has no "
                + "attribute '\(method)'",
            line: line)
    }

    func strMethod(_ text: String,
                   _ method: String,
                   _ args: [PyValue],
                   _ line: Int) throws
        -> PyValue {
        func argStr(_ at: Int) throws
            -> String {
            guard args.count > at,
                  case .str(let value) =
                    args[at] else {
                throw PyError(
                    "TypeError",
                    "\(method)() needs a "
                        + "string argument",
                    line: line)
            }
            return value
        }
        switch method {
        case "upper":
            return .str(text.uppercased())
        case "lower":
            return .str(text.lowercased())
        case "title":
            return .str(text
                .capitalized)
        case "capitalize":
            guard let first = text.first
            else { return .str(text) }
            return .str(
                first.uppercased()
                    + text.dropFirst()
                        .lowercased())
        case "swapcase":
            return .str(text.map {
                $0.isUppercase
                    ? $0.lowercased()
                    : $0.uppercased()
            }.joined())
        case "strip":
            return .str(text
                .trimmingCharacters(
                    in: .whitespacesAndNewlines))
        case "lstrip":
            var out = text
            while out.first?.isWhitespace
                == true {
                out.removeFirst()
            }
            return .str(out)
        case "rstrip":
            var out = text
            while out.last?.isWhitespace
                == true {
                out.removeLast()
            }
            return .str(out)
        case "split":
            if args.isEmpty {
                return .list(PyList(
                    text.split(
                        whereSeparator: {
                            $0.isWhitespace
                        }).map {
                            PyValue.str(
                                String($0))
                        }))
            }
            let sep = try argStr(0)
            guard !sep.isEmpty else {
                throw PyError(
                    "ValueError",
                    "empty separator",
                    line: line)
            }
            return .list(PyList(
                text.components(
                    separatedBy: sep).map {
                        PyValue.str($0)
                    }))
        case "join":
            guard let first = args.first
            else {
                throw PyError(
                    "TypeError",
                    "join() needs a list",
                    line: line)
            }
            var pieces: [String] = []
            for item in try iterate(first) {
                guard case .str(let piece) =
                    item else {
                    throw PyError(
                        "TypeError",
                        "join() needs strings",
                        line: line)
                }
                pieces.append(piece)
            }
            return .str(pieces.joined(
                separator: text))
        case "replace":
            let old = try argStr(0)
            let new = try argStr(1)
            return .str(text
                .replacingOccurrences(
                    of: old, with: new))
        case "find", "index":
            let bit = try argStr(0)
            if let range = text.range(
                of: bit) {
                let at = text.distance(
                    from: text.startIndex,
                    to: range.lowerBound)
                return .int(at)
            }
            if method == "index" {
                throw PyError(
                    "ValueError",
                    "substring not found",
                    line: line)
            }
            return .int(-1)
        case "rfind":
            let bit = try argStr(0)
            if let range = text.range(
                of: bit,
                options: .backwards) {
                return .int(text.distance(
                    from: text.startIndex,
                    to: range.lowerBound))
            }
            return .int(-1)
        case "count":
            let bit = try argStr(0)
            if bit.isEmpty {
                return .int(text.count + 1)
            }
            return .int(text.components(
                separatedBy: bit).count - 1)
        case "startswith":
            return .bool(text.hasPrefix(
                try argStr(0)))
        case "endswith":
            return .bool(text.hasSuffix(
                try argStr(0)))
        case "isdigit":
            return .bool(
                !text.isEmpty && text
                    .allSatisfy { $0.isNumber })
        case "isalpha":
            return .bool(
                !text.isEmpty && text
                    .allSatisfy { $0.isLetter })
        case "isalnum":
            return .bool(
                !text.isEmpty && text
                    .allSatisfy {
                        $0.isLetter
                            || $0.isNumber
                    })
        case "isspace":
            return .bool(
                !text.isEmpty && text
                    .allSatisfy {
                        $0.isWhitespace
                    })
        case "islower":
            return .bool(text == text
                .lowercased()
                && text.contains {
                    $0.isLetter
                })
        case "isupper":
            return .bool(text == text
                .uppercased()
                && text.contains {
                    $0.isLetter
                })
        case "splitlines":
            if text.isEmpty {
                return .list(PyList())
            }
            var parts = text.components(
                separatedBy: "\n")
            if text.hasSuffix("\n") {
                parts.removeLast()
            }
            return .list(PyList(parts.map {
                part in
                PyValue.str(part.hasSuffix(
                    "\r")
                    ? String(part.dropLast())
                    : part)
            }))
        case "removeprefix":
            let bit = try argStr(0)
            return .str(text.hasPrefix(bit)
                ? String(text.dropFirst(
                    bit.count)) : text)
        case "removesuffix":
            let bit = try argStr(0)
            return .str(text.hasSuffix(bit)
                ? String(text.dropLast(
                    bit.count)) : text)
        case "zfill":
            guard let width = args.first
                .flatMap({ asInt($0) })
            else {
                throw PyError(
                    "TypeError",
                    "zfill() needs a width",
                    line: line)
            }
            if text.count >= width {
                return .str(text)
            }
            let pad = String(
                repeating: "0",
                count: width - text.count)
            if text.hasPrefix("-")
                || text.hasPrefix("+") {
                return .str(
                    String(text.prefix(1))
                        + pad
                        + String(text
                            .dropFirst()))
            }
            return .str(pad + text)
        case "center", "ljust", "rjust":
            guard let width = args.first
                .flatMap({ asInt($0) })
            else {
                throw PyError(
                    "TypeError",
                    "\(method)() needs a "
                        + "width",
                    line: line)
            }
            var fill = " "
            if args.count > 1,
               case .str(let f) = args[1],
               let ch = f.first {
                fill = String(ch)
            }
            if text.count >= width {
                return .str(text)
            }
            let total = width - text.count
            let padding = String(
                repeating: fill,
                count: total)
            switch method {
            case "ljust":
                return .str(text + padding)
            case "rjust":
                return .str(padding + text)
            default:
                let leftCount = total
                    - total / 2
                return .str(
                    String(repeating: fill,
                           count: leftCount)
                        + text
                        + String(
                            repeating: fill,
                            count: total
                                - leftCount))
            }
        case "partition", "rpartition":
            let bit = try argStr(0)
            guard !bit.isEmpty else {
                throw PyError(
                    "ValueError",
                    "empty separator",
                    line: line)
            }
            let range = method
                == "partition"
                ? text.range(of: bit)
                : text.range(
                    of: bit,
                    options: .backwards)
            guard let range = range else {
                return method == "partition"
                    ? .tuple([.str(text),
                              .str(""),
                              .str("")])
                    : .tuple([.str(""),
                              .str(""),
                              .str(text)])
            }
            return .tuple([
                .str(String(
                    text[..<range.lowerBound])),
                .str(bit),
                .str(String(
                    text[range.upperBound...])),
            ])
        case "casefold":
            return .str(text.lowercased())
        case "istitle":
            let words = text.split(
                whereSeparator: {
                    !$0.isLetter
                })
            return .bool(!words.isEmpty
                && words.allSatisfy { word in
                    guard let first = word
                        .first else {
                        return true
                    }
                    return first.isUppercase
                        && word.dropFirst()
                            .allSatisfy {
                                !$0.isUppercase
                            }
                })
        case "isdecimal", "isnumeric":
            return .bool(!text.isEmpty
                && text.allSatisfy {
                    $0.isNumber
                })
        case "expandtabs":
            let size = args.first
                .flatMap({ asInt($0) }) ?? 8
            return .str(text
                .replacingOccurrences(
                    of: "\t",
                    with: String(
                        repeating: " ",
                        count: size)))
        default:
            throw attrError(
                "str", method, line)
        }
    }

    func listMethod(_ list: PyList,
                    _ method: String,
                    _ args: [PyValue],
                    _ kwargs: [(String,
                                PyValue)],
                    _ line: Int) throws
        -> PyValue {
        switch method {
        case "append":
            try needArgs(
                method, args, 1, line)
            list.items.append(args[0])
            return .none
        case "extend":
            try needArgs(
                method, args, 1, line)
            list.items += try iterate(
                args[0])
            return .none
        case "insert":
            try needArgs(
                method, args, 2, line)
            guard let raw = asInt(args[0])
            else {
                throw PyError(
                    "TypeError",
                    "insert() index must be "
                        + "an integer",
                    line: line)
            }
            var at = raw
            if at < 0 {
                at = max(
                    0, at + list.items.count)
            }
            at = min(at, list.items.count)
            list.items.insert(
                args[1], at: at)
            return .none
        case "pop":
            guard !list.items.isEmpty else {
                throw PyError(
                    "IndexError",
                    "pop from empty list",
                    line: line)
            }
            if args.isEmpty {
                return list.items.removeLast()
            }
            let at = try listIndexOf(
                args[0], list.items.count,
                "list", line)
            return list.items.remove(at: at)
        case "remove":
            try needArgs(
                method, args, 1, line)
            guard let at = list.items
                .firstIndex(where: {
                    PyFormat.equals(
                        $0, args[0])
                }) else {
                throw PyError(
                    "ValueError",
                    "list.remove(x): x not "
                        + "in list",
                    line: line)
            }
            list.items.remove(at: at)
            return .none
        case "index":
            try needArgs(
                method, args, 1, line)
            guard let at = list.items
                .firstIndex(where: {
                    PyFormat.equals(
                        $0, args[0])
                }) else {
                throw PyError(
                    "ValueError",
                    "the value is not in "
                        + "the list",
                    line: line)
            }
            return .int(at)
        case "count":
            try needArgs(
                method, args, 1, line)
            return .int(list.items.filter {
                PyFormat.equals($0, args[0])
            }.count)
        case "sort":
            list.items = try sortItems(
                list.items, kwargs, line)
            return .none
        case "reverse":
            list.items.reverse()
            return .none
        case "copy":
            return .list(PyList(list.items))
        case "clear":
            list.items = []
            return .none
        default:
            throw attrError(
                "list", method, line)
        }
    }

    func dictMethod(_ dict: PyDict,
                    _ method: String,
                    _ args: [PyValue],
                    _ line: Int) throws
        -> PyValue {
        switch method {
        case "get":
            guard !args.isEmpty else {
                throw PyError(
                    "TypeError",
                    "get() needs a key",
                    line: line)
            }
            if let value = dict.get(
                args[0]) {
                return value
            }
            return args.count > 1
                ? args[1] : .none
        case "keys":
            return .list(PyList(
                dict.keys.map {
                    dict.display[$0] ?? .none
                }))
        case "values":
            return .list(PyList(
                dict.keys.map {
                    dict.values[$0] ?? .none
                }))
        case "items":
            return .list(PyList(
                dict.keys.map { h in
                    .tuple([
                        dict.display[h]
                            ?? .none,
                        dict.values[h]
                            ?? .none,
                    ])
                }))
        case "pop":
            guard !args.isEmpty else {
                throw PyError(
                    "TypeError",
                    "pop() needs a key",
                    line: line)
            }
            if let value = dict.get(
                args[0]) {
                dict.remove(args[0])
                return value
            }
            if args.count > 1 {
                return args[1]
            }
            throw PyError(
                "KeyError",
                PyFormat.repr(args[0]),
                line: line)
        case "setdefault":
            guard !args.isEmpty else {
                throw PyError(
                    "TypeError",
                    "setdefault() needs a "
                        + "key",
                    line: line)
            }
            if let value = dict.get(
                args[0]) {
                return value
            }
            let fallback = args.count > 1
                ? args[1] : .none
            dict.set(args[0], fallback)
            return fallback
        case "update":
            guard let first = args.first,
                  case .dict(let other) =
                    first else {
                throw PyError(
                    "TypeError",
                    "update() needs a dict",
                    line: line)
            }
            for h in other.keys {
                dict.set(
                    other.display[h] ?? .none,
                    other.values[h] ?? .none)
            }
            return .none
        case "copy":
            let fresh = PyDict()
            for h in dict.keys {
                fresh.set(
                    dict.display[h] ?? .none,
                    dict.values[h] ?? .none)
            }
            return .dict(fresh)
        case "clear":
            dict.keys = []
            dict.values = [:]
            dict.display = [:]
            return .none
        default:
            throw attrError(
                "dict", method, line)
        }
    }

    func fileMethod(_ file: PyFile,
                    _ method: String,
                    _ args: [PyValue],
                    _ line: Int) throws
        -> PyValue {
        switch method {
        case "read":
            return .str(file.content)
        case "readlines":
            let rows = file.content
                .components(
                    separatedBy: "\n")
            var lines = rows
            if lines.last == "" {
                lines.removeLast()
            }
            return .list(PyList(
                lines.map { PyValue.str($0) }))
        case "write":
            guard file.mode != "r" else {
                throw PyError(
                    "OSError",
                    "the file was opened "
                        + "read-only",
                    line: line)
            }
            guard let first = args.first,
                  case .str(let text) = first
            else {
                throw PyError(
                    "TypeError",
                    "write() needs a string",
                    line: line)
            }
            file.content += text
            file.wrote = true
            return .int(text.count)
        case "close":
            closeFile(file)
            return .none
        default:
            throw attrError(
                "file", method, line)
        }
    }
}

// MARK: - Modules

extension PyInterp {
    func moduleAttr(_ module: String,
                    _ field: String,
                    _ line: Int) throws
        -> PyValue {
        if module == "sys" {
            if field == "argv" {
                return .list(PyList(
                    scriptArgs.map {
                        PyValue.str($0)
                    }))
            }
            throw PyError(
                "AttributeError",
                "module 'sys' has no "
                    + "attribute '\(field)' "
                    + "in the house's "
                    + "python",
                line: line)
        }
        if module == "math" {
            switch field {
            case "pi": return .float(.pi)
            case "e": return .float(2.718281828459045)
            case "tau":
                return .float(.pi * 2)
            case "inf":
                return .float(.infinity)
            case "nan": return .float(.nan)
            default:
                break
            }
        }
        let known: [String: Set<String>] = [
            "math": ["sqrt", "floor",
                     "ceil", "fabs", "sin",
                     "cos", "tan", "asin",
                     "acos", "atan", "log",
                     "log2", "log10", "pow",
                     "factorial", "gcd",
                     "degrees", "radians",
                     "hypot"],
            "random": ["random", "randint",
                       "randrange", "choice",
                       "shuffle", "uniform",
                       "seed"],
            "house": ["read", "write",
                      "ls", "exists",
                      "state", "emcon"],
        ]
        if known[module]?.contains(field)
            == true {
            return .bound(
                .module(module), field)
        }
        throw PyError(
            "AttributeError",
            "module '\(module)' has no "
                + "attribute '\(field)'",
            line: line)
    }

    func moduleFunction(_ module: String,
                        _ field: String,
                        _ args: [PyValue],
                        _ line: Int) throws
        -> PyValue {
        func num(_ at: Int) throws
            -> Double {
            guard args.count > at,
                  let d = asDouble(args[at])
            else {
                throw PyError(
                    "TypeError",
                    "\(field)() needs numbers",
                    line: line)
            }
            return d
        }
        switch (module, field) {
        case ("math", "sqrt"):
            let x = try num(0)
            guard x >= 0 else {
                throw PyError(
                    "ValueError",
                    "math domain error",
                    line: line)
            }
            return .float(sqrt(x))
        case ("math", "floor"):
            return .int(Int(
                try num(0).rounded(.down)))
        case ("math", "ceil"):
            return .int(Int(
                try num(0).rounded(.up)))
        case ("math", "fabs"):
            return .float(abs(try num(0)))
        case ("math", "sin"):
            return .float(sin(try num(0)))
        case ("math", "cos"):
            return .float(cos(try num(0)))
        case ("math", "tan"):
            return .float(tan(try num(0)))
        case ("math", "asin"):
            return .float(asin(try num(0)))
        case ("math", "acos"):
            return .float(acos(try num(0)))
        case ("math", "atan"):
            return .float(atan(try num(0)))
        case ("math", "log"):
            let x = try num(0)
            guard x > 0 else {
                throw PyError(
                    "ValueError",
                    "math domain error",
                    line: line)
            }
            if args.count > 1 {
                return .float(
                    log(x) / log(try num(1)))
            }
            return .float(log(x))
        case ("math", "log2"):
            return .float(log2(try num(0)))
        case ("math", "log10"):
            return .float(log10(try num(0)))
        case ("math", "pow"):
            return .float(pow(
                try num(0), try num(1)))
        case ("math", "factorial"):
            guard let n = asInt(
                args.first ?? .none),
                  n >= 0 else {
                throw PyError(
                    "ValueError",
                    "factorial() needs a "
                        + "whole number",
                    line: line)
            }
            var result = 1
            if n > 1 {
                for k in 2...n {
                    result *= k
                }
            }
            return .int(result)
        case ("math", "gcd"):
            guard let a = asInt(
                    args.first ?? .none),
                  let b = asInt(
                    args.count > 1
                        ? args[1] : .none)
            else {
                throw PyError(
                    "TypeError",
                    "gcd() needs integers",
                    line: line)
            }
            var x = abs(a)
            var y = abs(b)
            while y != 0 {
                let r = x % y
                x = y
                y = r
            }
            return .int(x)
        case ("math", "degrees"):
            return .float(
                try num(0) * 180 / .pi)
        case ("math", "radians"):
            return .float(
                try num(0) * .pi / 180)
        case ("math", "hypot"):
            let x = try num(0)
            let y = try num(1)
            return .float(
                sqrt(x * x + y * y))
        case ("random", "random"):
            return .float(randomDouble())
        case ("random", "uniform"):
            let a = try num(0)
            let b = try num(1)
            return .float(
                a + (b - a) * randomDouble())
        case ("random", "randint"):
            guard let a = asInt(
                    args.first ?? .none),
                  let b = asInt(
                    args.count > 1
                        ? args[1] : .none),
                  b >= a else {
                throw PyError(
                    "ValueError",
                    "randint() needs a "
                        + "range, low to high",
                    line: line)
            }
            let span = UInt64(b - a + 1)
            return .int(
                a + Int(nextRandom() % span))
        case ("random", "randrange"):
            guard let stop = asInt(
                args.first ?? .none)
            else {
                throw PyError(
                    "TypeError",
                    "randrange() needs an "
                        + "integer",
                    line: line)
            }
            var low = 0
            var high = stop
            if args.count > 1,
               let second = asInt(args[1]) {
                low = stop
                high = second
            }
            guard high > low else {
                throw PyError(
                    "ValueError",
                    "empty range for "
                        + "randrange()",
                    line: line)
            }
            let span = UInt64(high - low)
            return .int(
                low + Int(nextRandom()
                    % span))
        case ("random", "choice"):
            guard let first = args.first
            else {
                throw PyError(
                    "TypeError",
                    "choice() needs a "
                        + "sequence",
                    line: line)
            }
            let items = try iterate(first)
            guard !items.isEmpty else {
                throw PyError(
                    "IndexError",
                    "cannot choose from an "
                        + "empty sequence",
                    line: line)
            }
            let at = Int(nextRandom()
                % UInt64(items.count))
            return items[at]
        case ("random", "shuffle"):
            guard let first = args.first,
                  case .list(let list) =
                    first else {
                throw PyError(
                    "TypeError",
                    "shuffle() needs a list",
                    line: line)
            }
            if list.items.count > 1 {
                for i in stride(
                    from: list.items.count - 1,
                    through: 1, by: -1) {
                    let j = Int(nextRandom()
                        % UInt64(i + 1))
                    list.items.swapAt(i, j)
                }
            }
            return .none
        case ("random", "seed"):
            if let first = args.first,
               let n = asInt(first) {
                rngState = UInt64(
                    bitPattern: Int64(n))
                    ^ 0x9E3779B97F4A7C15
            }
            return .none
        case ("house", "read"):
            guard let first = args.first,
                  case .str(let raw) = first
            else {
                throw PyError(
                    "TypeError",
                    "house.read() needs a "
                        + "path",
                    line: line)
            }
            let clean = BlacksiteFS
                .normalize(
                    raw, cwd: BlacksiteFS.home)
            guard let text = BlacksiteFS
                .readText(clean) else {
                throw PyError(
                    "FileNotFoundError",
                    "no such file: "
                        + "'\(raw)'",
                    line: line)
            }
            return .str(text)
        case ("house", "write"):
            guard args.count >= 2,
                  case .str(let raw) =
                    args[0],
                  case .str(let text) =
                    args[1] else {
                throw PyError(
                    "TypeError",
                    "house.write() needs a "
                        + "path and a string",
                    line: line)
            }
            let clean = BlacksiteFS
                .normalize(
                    raw, cwd: BlacksiteFS.home)
            guard BlacksiteFS.writeText(
                clean, text: text) else {
                throw PyError(
                    "OSError",
                    "the files would not "
                        + "take it",
                    line: line)
            }
            return .int(text.count)
        case ("house", "ls"):
            var raw = BlacksiteFS.home
            if let first = args.first,
               case .str(let given) = first {
                raw = given
            }
            let clean = BlacksiteFS
                .normalize(
                    raw, cwd: BlacksiteFS.home)
            guard let entries = BlacksiteFS
                .list(clean) else {
                throw PyError(
                    "FileNotFoundError",
                    "no such room: "
                        + "'\(raw)'",
                    line: line)
            }
            return .list(PyList(
                entries.map {
                    PyValue.str($0.name)
                }))
        case ("house", "exists"):
            guard let first = args.first,
                  case .str(let raw) = first
            else {
                throw PyError(
                    "TypeError",
                    "house.exists() needs a "
                        + "path",
                    line: line)
            }
            return .bool(BlacksiteFS.exists(
                BlacksiteFS.normalize(
                    raw,
                    cwd: BlacksiteFS.home)))
        case ("house", "state"):
            return .str(DevKit.houseState())
        case ("house", "emcon"):
            return .str(
                EmconCondition.current.name)
        default:
            throw PyError(
                "AttributeError",
                "module '\(module)' has no "
                    + "attribute '\(field)'",
                line: line)
        }
    }
}

// MARK: - The door

enum BlacksitePy {
    static let helpLines = [
        "house python 2.0 — a small, "
            + "real python",
        "  numbers, strings, lists, "
            + "dicts, tuples, sets",
        "  classes + inheritance, "
            + "super(), dunders, lambda",
        "  generators (yield) and "
            + "comprehensions, nonlocal",
        "  if / for / while, try/except/"
            + "else/finally, f-strings",
        "  modules: math, random, sys "
            + "(argv), house (read/write/"
            + "ls/exists/state/emcon)",
        "  not yet: input(), imports "
            + "past those four, threads",
        "run one: python3 hello.py · "
            + "or: run hello.py",
    ]

    static func runFile(
        _ virtualPath: String,
        args: [String],
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        DispatchQueue.global(
            qos: .userInitiated).async {
            guard let source = BlacksiteFS
                .readText(virtualPath) else {
                emit("python3: cannot read "
                     + virtualPath, .err)
                done()
                return
            }
            run(source: source,
                path: virtualPath,
                args: args, emit: emit)
            done()
        }
    }

    static func run(source: String,
                    path: String,
                    args: [String],
                    emit: @escaping
                    BlacksiteEmit) {
        let interp = PyInterp(
            emit: emit, path: path)
        do {
            var lexer = PyLexer(source)
            let tokens = try lexer
                .tokenize()
            var parser = PyParser(
                tokens: tokens)
            let body = try parser
                .parseProgram()
            interp.runProgram(
                body, args: args)
        } catch let error as PyError {
            interp.emitTrace(
                error.kind, error.message,
                error.line)
        } catch {
            interp.emitTrace(
                "RuntimeError",
                "the interpreter stumbled",
                0)
        }
    }
}
