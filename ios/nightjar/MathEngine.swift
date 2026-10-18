import Foundation

/// Her arithmetic — exact, on-device, no bench
/// required. A strict recursive-descent evaluator:
/// a message earns a computed answer only when it
/// reduces, completely, to mathematics. Prose that
/// merely contains numbers falls through untouched,
/// and anything she cannot finish exactly, she
/// does not guess at.
///
/// Covers arithmetic with precedence and powers,
/// parentheses, the common functions, percentages,
/// and equations in one unknown up to quadratic —
/// solved by fitting both sides, so any shape of
/// linear or quadratic equation works, not just
/// the tidy ones. Trigonometry reads degrees,
/// unless the question speaks in π, when it reads
/// radians — the way the question was asked
/// decides the language of the answer.
enum MathEngine {

    /// Answer a maths ask in one short line, or nil
    /// when the message is not (only) mathematics.
    static func answer(_ q: String) -> String? {
        var text = q.lowercased()
            .trimmingCharacters(in: .whitespaces)
        for prefix in ["please calculate ",
                       "can you calculate ",
                       "calculate ", "compute ",
                       "evaluate ", "solve ",
                       "what is ", "what's ",
                       "how much is ", "how many is "] {
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }
        if text.hasSuffix("?") || text.hasSuffix("=") {
            text = String(text.dropLast())
                .trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }
        // "15% of 240" — a shape of its own.
        if let shaped = percentOf(text) { return shaped }
        if text.contains("=") {
            return solveEquation(text)
        }
        guard let value = Parser(text).run() else {
            return nil
        }
        return format(value)
    }

    /// Numbers the way a person writes them back:
    /// whole values whole, the rest to ten
    /// significant figures and no false precision.
    static func format(_ v: Double) -> String? {
        guard v.isFinite else { return nil }
        if v == v.rounded() && abs(v) < 1e15 {
            return String(Int(v))
        }
        return String(format: "%.10g", v)
    }

    // MARK: - the percent shape

    private static func percentOf(_ text: String)
        -> String? {
        guard let range = text.range(of: "% of ") else {
            return nil
        }
        let left = String(text[..<range.lowerBound])
        let right = String(text[range.upperBound...])
        guard let p = Parser(left).run(),
              let y = Parser(right).run() else {
            return nil
        }
        return format(p / 100 * y)
    }

    // MARK: - equations

    /// Fit each side at x = 0, 1, 2 — three points
    /// name a quadratic exactly — then solve the
    /// difference. Shapes that are not equations in
    /// one unknown, or not up to quadratic, fall
    /// through rather than guess.
    private static func solveEquation(_ text: String)
        -> String? {
        let sides = text.split(separator: "=",
                                omittingEmptySubsequences: false)
        guard sides.count == 2 else { return nil }
        func fit(_ side: Substring) -> (a: Double,
                                        b: Double,
                                        c: Double)? {
            let parser = { (x: Double) in
                Parser(String(side), x: x).run()
            }
            guard let v0 = parser(0), let v1 = parser(1),
                  let v2 = parser(2) else { return nil }
            let c = v0
            let a = (v2 - 2 * v1 + v0) / 2
            let b = v1 - v0 - a
            return (a, b, c)
        }
        guard let l = fit(sides[0]), let r = fit(sides[1])
        else { return nil }
        let a = l.a - r.a, b = l.b - r.b, c = l.c - r.c
        let eps = 1e-9
        if abs(a) < eps {
            guard abs(b) > eps else { return nil }
            guard let root = format(-c / b) else {
                return nil
            }
            return "x = " + root
        }
        let disc = b * b - 4 * a * c
        if disc < -eps { return "No real solution." }
        let root = sqrt(max(0, disc))
        let x1 = (-b + root) / (2 * a)
        let x2 = (-b - root) / (2 * a)
        if abs(x1 - x2) < eps {
            guard let one = format(x1) else { return nil }
            return "x = " + one
        }
        guard let f1 = format(x1), let f2 = format(x2)
        else { return nil }
        return "x = " + f1 + " or x = " + f2
    }

    // MARK: - the parser

    private final class Parser {
        private let chars: [Character]
        private var pos = 0
        private let x: Double?
        private let radians: Bool

        init(_ text: String, x: Double? = nil) {
            chars = Array(text)
            self.x = x
            radians = text.contains("pi")
                || text.contains("π")
        }

        /// Parse the whole string as one expression.
        /// Any residue — an unknown name, a stray
        /// word, an unbalanced bracket — fails the
        /// whole thing. Strictness is the feature.
        func run() -> Double? {
            guard chars.contains(where: \.isNumber)
            else { return nil }
            guard let value = expression() else {
                return nil
            }
            skipSpaces()
            guard pos == chars.count, value.isFinite
            else { return nil }
            return value
        }

        private func skipSpaces() {
            while pos < chars.count && chars[pos] == " " {
                pos += 1
            }
        }

        private var peek: Character? {
            skipSpaces()
            return pos < chars.count ? chars[pos] : nil
        }

        private func expression() -> Double? {
            guard var value = term() else { return nil }
            while let ch = peek, ch == "+" || ch == "-" {
                pos += 1
                guard let next = term() else { return nil }
                value = ch == "+" ? value + next
                                  : value - next
            }
            return value
        }

        private func term() -> Double? {
            guard var value = factor() else { return nil }
            while let ch = peek {
                if ch == "*" || ch == "/" || ch == "×"
                    || ch == "÷" {
                    pos += 1
                    guard let next = factor() else {
                        return nil
                    }
                    value = (ch == "*" || ch == "×")
                        ? value * next : value / next
                } else if ch == "(" || ch == "π"
                            || ch.isLetter {
                    // Implicit multiplication — the
                    // way equations are actually
                    // written: 2x, 3(x + 1). An
                    // unknown name still fails the
                    // whole parse in named().
                    guard let next = factor() else {
                        return nil
                    }
                    value *= next
                } else {
                    break
                }
            }
            return value
        }

        private func factor() -> Double? {
            guard let base = unary() else { return nil }
            if peek == "^" {
                pos += 1
                guard let exponent = factor() else {
                    return nil
                }
                return pow(base, exponent)
            }
            return base
        }

        private func unary() -> Double? {
            if peek == "-" {
                pos += 1
                guard let value = unary() else {
                    return nil
                }
                return -value
            }
            if peek == "+" {
                pos += 1
                return unary()
            }
            return postfix()
        }

        private func postfix() -> Double? {
            guard var value = primary() else { return nil }
            while let ch = peek, ch == "!" || ch == "%" {
                pos += 1
                if ch == "%" {
                    value /= 100
                } else {
                    guard value == value.rounded(),
                          value >= 0, value <= 170 else {
                        return nil
                    }
                    value = (1...max(1, Int(value)))
                        .reduce(1.0) { $0 * Double($1) }
                    if value == 0 { value = 1 }
                }
            }
            return value
        }

        private func primary() -> Double? {
            guard let ch = peek else { return nil }
            if ch == "(" {
                pos += 1
                guard let value = expression(),
                      peek == ")" else { return nil }
                pos += 1
                return value
            }
            if ch.isNumber || ch == "." {
                return number()
            }
            if ch.isLetter || ch == "π" {
                return named()
            }
            return nil
        }

        private func number() -> Double? {
            var text = ""
            var dot = false
            while pos < chars.count {
                let ch = chars[pos]
                if ch.isNumber {
                    text.append(ch)
                    pos += 1
                } else if ch == "." && !dot {
                    dot = true
                    text.append(ch)
                    pos += 1
                } else {
                    break
                }
            }
            return Double(text)
        }

        private func named() -> Double? {
            if peek == "π" {
                pos += 1
                return Double.pi
            }
            var name = ""
            while pos < chars.count
                    && chars[pos].isLetter {
                name.append(chars[pos])
                pos += 1
            }
            switch name {
            case "pi": return Double.pi
            case "tau": return 2 * Double.pi
            case "e": return exp(1)
            case "x":
                guard let x else { return nil }
                return x
            case "sqrt", "cbrt", "abs", "ln", "log",
                 "log2", "exp", "sin", "cos", "tan",
                 "asin", "acos", "atan", "floor",
                 "ceil", "round":
                guard peek == "(" else { return nil }
                pos += 1
                guard let arg = expression(),
                      peek == ")" else { return nil }
                pos += 1
                return apply(name, arg)
            case "min", "max":
                guard peek == "(" else { return nil }
                pos += 1
                guard let a = expression(),
                      peek == "," else { return nil }
                pos += 1
                guard let b = expression(),
                      peek == ")" else { return nil }
                pos += 1
                return name == "min" ? min(a, b) : max(a, b)
            default:
                return nil
            }
        }

        private func apply(_ name: String,
                           _ arg: Double) -> Double? {
            switch name {
            case "sqrt":
                return arg >= 0 ? sqrt(arg) : nil
            case "cbrt": return cbrt(arg)
            case "abs": return abs(arg)
            case "ln":
                return arg > 0 ? log(arg) : nil
            case "log":
                return arg > 0 ? log10(arg) : nil
            case "log2":
                return arg > 0 ? log2(arg) : nil
            case "exp": return exp(arg)
            case "sin":
                return sin(radians ? arg : arg * .pi / 180)
            case "cos":
                return cos(radians ? arg : arg * .pi / 180)
            case "tan":
                return tan(radians ? arg : arg * .pi / 180)
            case "asin":
                guard abs(arg) <= 1 else { return nil }
                let v = asin(arg)
                return radians ? v : v * 180 / .pi
            case "acos":
                guard abs(arg) <= 1 else { return nil }
                let v = acos(arg)
                return radians ? v : v * 180 / .pi
            case "atan":
                let v = atan(arg)
                return radians ? v : v * 180 / .pi
            case "floor": return floor(arg)
            case "ceil": return ceil(arg)
            case "round": return round(arg)
            default: return nil
            }
        }
    }
}
