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
        // No honest question is two thousand
        // characters of mathematics; past that the
        // parse is refused, not attempted — the cap
        // and the parser's depth bound below are
        // what stand between a pasted wall of
        // brackets and the stack.
        guard text.count <= 2_000 else { return nil }
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

    // MARK: - conversions

    /// One unit: its spoken tokens, dimension,
    /// and the exact factor to the dimension's
    /// base (metre, gram, millilitre, byte,
    /// second, metre/second). Temperature is
    /// handled apart — it is a formula, not a
    /// factor.
    private struct Unit {
        let symbol: String
        let dim: String
        let factor: Double
    }

    private static let units: [String: Unit] = {
        var table: [String: Unit] = [:]
        func add(_ tokens: [String], _ symbol: String,
                 _ dim: String, _ factor: Double) {
            for t in tokens {
                table[t] = Unit(symbol: symbol,
                                dim: dim, factor: factor)
            }
        }
        // Length, base metre.
        add(["mm", "millimeter", "millimeters",
             "millimetre", "millimetres"],
            "mm", "length", 0.001)
        add(["cm", "centimeter", "centimeters",
             "centimetre", "centimetres"],
            "cm", "length", 0.01)
        add(["m", "meter", "meters", "metre",
             "metres"], "m", "length", 1)
        add(["km", "kilometer", "kilometers",
             "kilometre", "kilometres"],
            "km", "length", 1000)
        add(["in", "inch", "inches"],
            "in", "length", 0.0254)
        add(["ft", "foot", "feet"],
            "ft", "length", 0.3048)
        add(["yd", "yard", "yards"],
            "yd", "length", 0.9144)
        add(["mi", "mile", "miles"],
            "mi", "length", 1609.344)
        // Mass, base gram.
        add(["g", "gram", "grams"], "g", "mass", 1)
        add(["kg", "kilogram", "kilograms"],
            "kg", "mass", 1000)
        add(["oz", "ounce", "ounces"],
            "oz", "mass", 28.349523125)
        add(["lb", "lbs", "pound", "pounds"],
            "lb", "mass", 453.59237)
        // Volume, base millilitre.
        add(["ml", "milliliter", "milliliters",
             "millilitre", "millilitres"],
            "ml", "volume", 1)
        add(["l", "liter", "liters", "litre",
             "litres"], "l", "volume", 1000)
        add(["floz", "fluidounce", "fluidounces"],
            "fl oz", "volume", 29.5735295625)
        add(["cup", "cups"], "cup", "volume",
            236.5882365)
        add(["pt", "pint", "pints"], "pt",
            "volume", 473.176473)
        add(["qt", "quart", "quarts"], "qt",
            "volume", 946.352946)
        add(["gal", "gallon", "gallons"], "gal",
            "volume", 3785.411784)
        // Data, base byte (1024 steps — the
        // computing house's measure).
        add(["bit", "bits"], "bit", "data", 0.125)
        add(["b", "byte", "bytes"], "B", "data", 1)
        add(["kb", "kib"], "KB", "data", 1024)
        add(["mb", "mib"], "MB", "data",
            1024 * 1024)
        add(["gb", "gib"], "GB", "data",
            1024 * 1024 * 1024)
        add(["tb", "tib"], "TB", "data",
            1024 * 1024 * 1024 * 1024)
        // Time, base second.
        add(["s", "sec", "secs", "second",
             "seconds"], "s", "time", 1)
        add(["min", "mins", "minute", "minutes"],
            "min", "time", 60)
        add(["h", "hr", "hrs", "hour", "hours"],
            "h", "time", 3600)
        add(["day", "days"], "days", "time", 86400)
        add(["wk", "wks", "week", "weeks"],
            "wk", "time", 604800)
        add(["yr", "yrs", "year", "years"],
            "yr", "time", 31557600)
        // Speed, base metre per second.
        add(["m/s", "mps"], "m/s", "speed", 1)
        add(["km/h", "kmh", "kph"], "km/h",
            "speed", 1000.0 / 3600.0)
        add(["mph"], "mph", "speed", 0.44704)
        add(["kn", "knot", "knots"], "kn",
            "speed", 1852.0 / 3600.0)
        return table
    }()

    /// Temperature, apart: the three scales by
    /// token.
    private static func tempUnit(_ token: String)
        -> String? {
        switch token {
        case "c", "celsius", "centigrade": return "°C"
        case "f", "fahrenheit": return "°F"
        case "k", "kelvin", "kelvins": return "K"
        default: return nil
        }
    }

    /// Words with the digits pried apart from
    /// the letters, so "5mi" and "72f" parse
    /// like "5 mi" and "72 f".
    private static func spaced(_ text: String)
        -> [String] {
        var out: [String] = []
        for word in text.split(separator: " ") {
            var current = ""
            var wasDigit: Bool? = nil
            for ch in word {
                let isDigit = ch.isNumber || ch == "."
                if let w = wasDigit, w != isDigit,
                   !current.isEmpty {
                    out.append(current)
                    current = ""
                }
                wasDigit = isDigit
                current.append(ch)
            }
            if !current.isEmpty {
                out.append(current)
            }
        }
        return out
    }

    /// A conversion ask, answered in one exact
    /// line — or nil when the message is not
    /// exactly number + unit + bridge + unit.
    static func conversion(_ q: String)
        -> String? {
        var text = q.lowercased()
            .trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("?") {
            text = String(text.dropLast())
        }
        for prefix in ["please ", "convert ",
                       "what is ", "what's ",
                       "whats "] {
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(
                    prefix.count))
                break
            }
        }
        // "how many km in 5 miles" — the target
        // is named before the bridge.
        var flipped = false
        for prefix in ["how many ", "how much "] {
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(
                    prefix.count))
                flipped = true
                break
            }
        }
        text = text.replacingOccurrences(
            of: "degrees ", with: "")
        text = text.replacingOccurrences(
            of: "degree ", with: "")
        text = text.replacingOccurrences(
            of: "fl oz", with: "floz")
        var tokens = spaced(text)
            .filter { $0 != "please" }
        // A minus sign rides with its number.
        if tokens.count >= 2 {
            var merged: [String] = []
            var i = 0
            while i < tokens.count {
                if tokens[i] == "-",
                   i + 1 < tokens.count,
                   Double(tokens[i + 1]) != nil {
                    merged.append("-" + tokens[i + 1])
                    i += 2
                } else {
                    merged.append(tokens[i])
                    i += 1
                }
            }
            tokens = merged
        }
        // Two shapes, nothing else:
        //   plain:   number unit bridge unit
        //   flipped: unit bridge number unit
        // ("how many km in 5 miles").
        let value: Double
        let source: String
        let targetToken: String
        if flipped {
            guard tokens.count == 4,
                  tokens[1] == "to" || tokens[1] == "in",
                  let v = Double(tokens[2]) else {
                return nil
            }
            value = v
            source = tokens[3]
            targetToken = tokens[0]
        } else {
            guard tokens.count == 4,
                  tokens[2] == "to" || tokens[2] == "in",
                  let v = Double(tokens[0]) else {
                return nil
            }
            value = v
            source = tokens[1]
            targetToken = tokens[3]
        }
        // Temperature?
        if let fromT = tempUnit(source),
           let toT = tempUnit(targetToken) {
            let celsius: Double
            switch fromT {
            case "°F": celsius = (value - 32) * 5 / 9
            case "K": celsius = value - 273.15
            default: celsius = value
            }
            let out: Double
            switch toT {
            case "°F": out = celsius * 9 / 5 + 32
            case "K": out = celsius + 273.15
            default: out = celsius
            }
            guard let f = format(value),
                  let o = format(out) else {
                return nil
            }
            return "\(f) \(fromT) = \(o) \(toT)."
        }
        guard let from = units[source],
              let to = units[targetToken],
              from.dim == to.dim else {
            return nil
        }
        let out = value * from.factor / to.factor
        guard let f = format(value),
              let o = format(out) else { return nil }
        return "\(f) \(from.symbol) = \(o) \(to.symbol)."
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
        private var depth = 0
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
            // Every descent — brackets, signs,
            // powers, nested calls — passes through
            // here once, so this counter bounds the
            // whole recursion: a message built of
            // ten thousand opening brackets fails
            // the parse instead of the stack.
            depth += 1
            defer { depth -= 1 }
            guard depth <= 64 else { return nil }
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
