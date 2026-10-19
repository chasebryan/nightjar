import Foundation

// BlacksitePy — the house's small python.
//
// The console's operator writes python, so
// the console learned to run it: a real
// interpreter for a teaching-sized subset
// of the language — numbers, strings,
// lists, dicts, functions, loops,
// try/except, f-strings, and the math,
// random and house modules. It is honest
// about its edges (the `python3` help says
// them out loud): no classes yet, no
// input(), no imports past those three.
// Where CPython would raise, it raises in
// CPython's voice, with the file and line.

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

final class PyEnv {
    var vars: [String: PyValue] = [:]
    var globals: Set<String> = []
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
                     [PyStmt])], line: Int)
    case withStmt(PyExpr, PyExpr?, [PyStmt],
                  line: Int)
    case raiseStmt(PyExpr?, line: Int)
    case assertStmt(PyExpr, PyExpr?,
                    line: Int)
    case globalStmt([String], line: Int)
    case delStmt([PyExpr], line: Int)
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
        guard !handlers.isEmpty else {
            throw PyError(
                "SyntaxError",
                "try needs an except",
                line: current.line)
        }
        return .tryExcept(body, handlers,
                          line: line)
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
            let inner = try parseExprList()
            try expectOp(")")
            return inner
        case .op("["):
            advance()
            var items: [PyExpr] = []
            if !isOp("]") {
                while true {
                    items.append(
                        try parseExpr())
                    if isOp(",") {
                        advance()
                        if isOp("]") { break }
                        continue
                    }
                    break
                }
            }
            try expectOp("]")
            return .listOf(items)
        case .op("{"):
            advance()
            var pairs: [(PyExpr, PyExpr)] = []
            if !isOp("}") {
                while true {
                    let key = try parseExpr()
                    try expectOp(":")
                    let value = try parseExpr()
                    pairs.append((key, value))
                    if isOp(",") {
                        advance()
                        if isOp("}") { break }
                        continue
                    }
                    break
                }
            }
            try expectOp("}")
            return .dictOf(pairs)
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
        "input",
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
        case .tryExcept(_, _, let l): line = l
        case .withStmt(_, _, _, let l):
            line = l
        case .raiseStmt(_, let l): line = l
        case .assertStmt(_, _, let l):
            line = l
        case .globalStmt(_, let l): line = l
        case .delStmt(_, let l): line = l
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
                if PyFormat.truthy(
                    try eval(cond, env)) {
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
            while PyFormat.truthy(
                try eval(cond, env)) {
                try tick()
                do {
                    try execBlock(body, env)
                } catch let signal
                    as PySignal {
                    if case .broke = signal {
                        break
                    }
                    if case .continued =
                        signal {
                        continue
                    }
                    throw signal
                }
            }
        case .forLoop(let target,
                      let iterableExpr,
                      let body, _):
            let items = try iterate(
                try eval(iterableExpr, env))
            for item in items {
                try tick()
                try assignTarget(
                    target, item, env)
                do {
                    try execBlock(body, env)
                } catch let signal
                    as PySignal {
                    if case .broke = signal {
                        break
                    }
                    if case .continued =
                        signal {
                        continue
                    }
                    throw signal
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
            env.assign(name, .function(
                PyFunction(
                    name: name,
                    params: params,
                    defaults: defaults,
                    body: body, env: env)))
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
                        let handlers, _):
            do {
                try execBlock(body, env)
            } catch let error as PyError {
                var handled = false
                for (kind, alias, arm)
                    in handlers {
                    if kind == nil
                        || kind == error.kind
                        || kind == "Exception" {
                        if let alias = alias {
                            env.assignLocal(
                                alias,
                                .str(
                                    error.message))
                        }
                        try execBlock(arm, env)
                        handled = true
                        break
                    }
                }
                if !handled { throw error }
            }
        case .withStmt(let itemExpr,
                       let target,
                       let body, _):
            let value = try eval(itemExpr, env)
            if let target = target {
                try assignTarget(
                    target, value, env)
            }
            defer {
                if case .file(let file) =
                    value {
                    closeFile(file)
                }
            }
            try execBlock(body, env)
        case .raiseStmt(let expr, _):
            throw try raiseError(
                expr, env, line)
        case .assertStmt(let test,
                         let messageExpr, _):
            if !PyFormat.truthy(
                try eval(test, env)) {
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
        let value = try eval(expr, env)
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
        default:
            throw PyError(
                "TypeError",
                "that spot cannot hold a "
                    + "value in the house's "
                    + "python",
                line: frames.last?.line ?? 0)
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
                    out += PyFormat.str(value)
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
                    !PyFormat.truthy(value))
            }
            return try evalUnaryNum(
                op, value, line)
        case .binary(let op, let lhs,
                     let rhs):
            if op == "and" {
                let left = try eval(lhs, env)
                if !PyFormat.truthy(left) {
                    return left
                }
                return try eval(rhs, env)
            }
            if op == "or" {
                let left = try eval(lhs, env)
                if PyFormat.truthy(left) {
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
        case .ternary(let value, let cond,
                      let other):
            if PyFormat.truthy(
                try eval(cond, env)) {
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
            return PyFormat.equals(
                left, right)
        case "!=":
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
        case .str, .list, .dict, .file:
            return .bound(base, field)
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

// MARK: - Calls

extension PyInterp {
    func callValue(_ callee: PyValue,
                   _ args: [PyValue],
                   _ kwargs: [(String, PyValue)],
                   _ line: Int) throws
        -> PyValue {
        switch callee {
        case .function(let fn):
            return try callFunction(
                fn, args, kwargs, line)
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
                PyFormat.str($0)
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
            return .str(PyFormat.str(args[0]))
        case "repr":
            try needArgs(name, args, 1, line)
            return .str(PyFormat.repr(
                args[0]))
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
            if args.isEmpty {
                return .dict(PyDict())
            }
            throw PyError(
                "TypeError",
                "dict() from values is not "
                    + "in the house's python "
                    + "yet — write {k: v}",
                line: line)
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
        default:
            throw PyError(
                "AttributeError",
                "'\(PyFormat.typeName(base))' "
                    + "object has no "
                    + "attribute '\(method)'",
                line: line)
        }
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
        "house python 1.0 — a small, "
            + "real python",
        "  numbers, strings, lists, "
            + "dicts, tuples, functions",
        "  if / for / while, try/except, "
            + "f-strings, slices",
        "  modules: math, random, sys "
            + "(argv), house (read/write/"
            + "ls/exists/state/emcon)",
        "  not yet: classes, input(), "
            + "imports past those three",
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
