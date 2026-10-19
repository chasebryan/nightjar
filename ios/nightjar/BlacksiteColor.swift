import Foundation
import SwiftUI

// BlacksiteColor — the console learns
// colour.
//
// Programs have always been able to SAY
// "\e[31m" — python prints it, echo -e
// builds it, ls and grep and ps now speak
// it — but until now the terminal showed
// the codes as litter. This is the other
// half: an ANSI SGR reader that turns
// escape sequences in a line of text into
// a genuinely coloured AttributedString
// for the transcript, and a stripper that
// takes them back out wherever colour
// cannot go — captured output, pipes and
// files always receive plain text, the
// way --color=auto has always promised.
//
// The palette is the classic xterm one:
// the sixteen, the 6×6×6 cube, the grey
// ramp, and 24-bit colour addressed
// directly. Bold, italic, underline,
// strike and dim ride along.

enum ANSITerm {
    /// A CSI sequence ends at a byte in
    /// the @ through ~ range.
    private static func isFinalByte(
        _ c: Character) -> Bool {
        guard let v = c.unicodeScalars
            .first?.value else {
            return false
        }
        return v >= 64 && v <= 126
    }

    /// xterm's sixteen, as RGB triples.
    private static let palette16: [(Double, Double, Double)] = [
        (0, 0, 0), (205, 49, 49),
        (13, 188, 121), (229, 229, 16),
        (36, 114, 200), (188, 63, 188),
        (17, 168, 205), (229, 229, 229),
        (102, 102, 102), (241, 76, 76),
        (35, 209, 139), (245, 245, 67),
        (59, 142, 234), (214, 112, 214),
        (41, 184, 219), (255, 255, 255),
    ]

    private static func color256(_ n: Int) -> Color {
        if n < 16 {
            let p = palette16[max(0, n)]
            return Color(red: p.0 / 255,
                         green: p.1 / 255,
                         blue: p.2 / 255)
        }
        if n < 232 {
            let v = n - 16
            let levels: [Double] = [0, 95, 135,
                                    175, 215, 255]
            return Color(
                red: levels[v / 36] / 255,
                green: levels[(v / 6) % 6] / 255,
                blue: levels[v % 6] / 255)
        }
        let step = Double(min(23, n - 232))
        let grey = 8.0 + 10.0 * step
        return Color(red: grey / 255,
                     green: grey / 255,
                     blue: grey / 255)
    }

    private static func ansi16(_ n: Int) -> Color {
        color256(n)
    }

    /// Remove every escape sequence,
    /// leaving the words. Used wherever
    /// output is captured rather than
    /// shown — a file should never hold
    /// litter meant for a screen.
    static func strip(_ text: String) -> String {
        guard text.contains("\u{1B}") else {
            return text
        }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "\u{1B}" {
                let next = text.index(
                    after: i)
                guard next < text.endIndex
                else { break }
                if text[next] == "[" {
                    var j = text.index(
                        after: next)
                    while j < text.endIndex {
                        let c = text[j]
                        if isFinalByte(c) {
                            break
                        }
                        j = text.index(
                            after: j)
                    }
                    i = j < text.endIndex
                        ? text.index(after: j)
                        : text.endIndex
                    continue
                }
                i = text.index(after: next)
                continue
            }
            out.append(ch)
            i = text.index(after: i)
        }
        return out
    }

    /// The backslash spellings echo -e
    /// honours: \e, \n, \t, \r, \\ and
    /// \xHH for any byte.
    static func unescape(_ text: String) -> String {
        guard text.contains("\\") else {
            return text
        }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch != "\\" {
                out.append(ch)
                i = text.index(after: i)
                continue
            }
            let next = text.index(after: i)
            guard next < text.endIndex else {
                out.append("\\")
                break
            }
            let c = text[next]
            switch c {
            case "e": out.append("\u{1B}")
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "\\": out.append("\\")
            case "x":
                var hex = ""
                var j = text.index(after: next)
                while j < text.endIndex,
                      hex.count < 2,
                      text[j].isHexDigit {
                    hex.append(text[j])
                    j = text.index(after: j)
                }
                if let byte = UInt8(hex,
                                    radix: 16) {
                    out.append(Character(
                        UnicodeScalar(byte)))
                    i = j
                    continue
                }
                out.append("x")
            default:
                out.append(c)
            }
            i = text.index(after: next)
        }
        return out
    }

    /// A line of text with its SGR codes
    /// read: each run carries the colour
    /// and dress the codes asked for,
    /// over the caller's base font and
    /// colour.
    static func attributed(
        _ text: String, baseFont: Font,
        baseColor: Color) -> AttributedString {
        var state = Style(base: baseColor)
        var result = AttributedString()
        var segment = ""

        func flush() {
            guard !segment.isEmpty else { return }
            var run = AttributedString(segment)
            run.foregroundColor = state.dim
                ? state.foreground.opacity(0.65)
                : state.foreground
            if let bg = state.background {
                run.backgroundColor = bg
            }
            var font = baseFont
            if state.bold {
                font = font.bold()
            }
            if state.italic {
                font = font.italic()
            }
            run.font = font
            if state.underline {
                run.underlineStyle = .single
            }
            if state.strike {
                run.strikethroughStyle = .single
            }
            result.append(run)
            segment = ""
        }

        var i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if ch == "\u{1B}" {
                let next = text.index(
                    after: i)
                if next < text.endIndex,
                   text[next] == "[" {
                    var j = text.index(
                        after: next)
                    var params = ""
                    var terminator: Character = " "
                    while j < text.endIndex {
                        let c = text[j]
                        if isFinalByte(c) {
                            terminator = c
                            break
                        }
                        params.append(c)
                        j = text.index(
                            after: j)
                    }
                    if terminator == "m" {
                        flush()
                        apply(params,
                              into: &state,
                              base: baseColor)
                    }
                    i = j < text.endIndex
                        ? text.index(after: j)
                        : text.endIndex
                    continue
                }
                i = next
                continue
            }
            segment.append(ch)
            i = text.index(after: i)
        }
        flush()
        return result
    }

    private struct Style {
        var foreground: Color
        var background: Color?
        var bold = false
        var dim = false
        var italic = false
        var underline = false
        var strike = false

        init(base: Color) {
            foreground = base
        }
    }

    private static func apply(
        _ params: String, into style: inout Style,
        base: Color) {
        let parts = params.split(
            separator: ";",
            omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        let codes = parts.isEmpty ? [0] : parts
        var at = 0
        while at < codes.count {
            let code = codes[at]
            switch code {
            case 0:
                style = Style(base: base)
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 9: style.strike = true
            case 22:
                style.bold = false
                style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 29: style.strike = false
            case 30...37:
                style.foreground = ansi16(
                    code - 30)
            case 38:
                if at + 2 < codes.count,
                   codes[at + 1] == 5 {
                    style.foreground = color256(
                        codes[at + 2])
                    at += 2
                } else if at + 4 < codes.count,
                          codes[at + 1] == 2 {
                    style.foreground = Color(
                        red: Double(
                            codes[at + 2]) / 255,
                        green: Double(
                            codes[at + 3]) / 255,
                        blue: Double(
                            codes[at + 4]) / 255)
                    at += 4
                }
            case 39:
                style.foreground = base
            case 40...47:
                style.background = ansi16(
                    code - 40)
            case 48:
                if at + 2 < codes.count,
                   codes[at + 1] == 5 {
                    style.background = color256(
                        codes[at + 2])
                    at += 2
                } else if at + 4 < codes.count,
                          codes[at + 1] == 2 {
                    style.background = Color(
                        red: Double(
                            codes[at + 2]) / 255,
                        green: Double(
                            codes[at + 3]) / 255,
                        blue: Double(
                            codes[at + 4]) / 255)
                    at += 4
                }
            case 49:
                style.background = nil
            case 90...97:
                style.foreground = ansi16(
                    code - 90 + 8)
            case 100...107:
                style.background = ansi16(
                    code - 100 + 8)
            default:
                break
            }
            at += 1
        }
    }
}
