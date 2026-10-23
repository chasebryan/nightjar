import Photos
import PhotosUI
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Colours — the app's wardrobe.
///
/// A theme is a handful of colours with judgement: an accent
/// for the controls, a glow for what deserves light, and a
/// tint washed over the backdrop under a measured dim. Six
/// ship with the app; the operator can tailor more and keep
/// them. Backdrops are chosen per tab — the living wallpaper,
/// the Jolly Roger the app was born wearing, the plain theme
/// colour, or the operator's own image or GIF, which never
/// leaves this device.

// MARK: - Hex colours

extension Color {
    init(hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        let value = UInt64(text, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }

    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}

// MARK: - The theme

struct AppTheme: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var accentHex: String
    var glowHex: String
    var tintHex: String
    var tintStrength: Double
    var dim: Double
    var builtIn: Bool

    var accent: Color { Color(hex: accentHex) }
    var glow: Color { Color(hex: glowHex) }
    var tint: Color { Color(hex: tintHex) }

    var onAccent: Color {
        id == "blackglass" ? .black : .white
    }

    static let phosphor = AppTheme(
        id: "phosphor", name: "Phosphor",
        accentHex: "#1DB35A", glowHex: "#B6FFC9",
        tintHex: "#04150A", tintStrength: 0.35, dim: 0.18,
        builtIn: true)
    static let bloodwork = AppTheme(
        id: "bloodwork", name: "Bloodwork",
        accentHex: "#FF3B47", glowHex: "#FF9E97",
        tintHex: "#170405", tintStrength: 0.38, dim: 0.22,
        builtIn: true)
    static let ultraviolet = AppTheme(
        id: "ultraviolet", name: "Ultraviolet",
        accentHex: "#B18CFF", glowHex: "#E3CCFF",
        tintHex: "#0D0618", tintStrength: 0.38, dim: 0.20,
        builtIn: true)
    static let arctic = AppTheme(
        id: "arctic", name: "Arctic Signal",
        accentHex: "#6FE3FF", glowHex: "#C9F4FF",
        tintHex: "#041019", tintStrength: 0.35, dim: 0.18,
        builtIn: true)
    static let amber = AppTheme(
        id: "amber", name: "Amber Deck",
        accentHex: "#FFB340", glowHex: "#FFDFA3",
        tintHex: "#140C02", tintStrength: 0.36, dim: 0.20,
        builtIn: true)
    static let bone = AppTheme(
        id: "bone", name: "Bone",
        accentHex: "#E9E2D0", glowHex: "#FFFFFF",
        tintHex: "#0B0B0C", tintStrength: 0.22, dim: 0.12,
        builtIn: true)
    static let halloween = AppTheme(
        id: "halloween", name: "Halloween",
        accentHex: "#FF7518", glowHex: "#EDEDED",
        tintHex: "#0A0A0A", tintStrength: 0.40,
        dim: 0.22,
        builtIn: true)
    static let christmas = AppTheme(
        id: "christmas", name: "Christmas",
        accentHex: "#E8443A", glowHex: "#FFFBF0",
        tintHex: "#06130B", tintStrength: 0.42,
        dim: 0.20,
        builtIn: true)
    static let blackGlass = AppTheme(
        id: "blackglass", name: "Black Glass",
        accentHex: "#C7CEDA", glowHex: "#FFFFFF",
        tintHex: "#000000", tintStrength: 0.55,
        dim: 0.38,
        builtIn: true)
    static let redteam = AppTheme(
        id: "redteam", name: "Violent Redteam",
        accentHex: "#FF1626", glowHex: "#FF7A66",
        tintHex: "#0F0102", tintStrength: 0.45,
        dim: 0.28,
        builtIn: true)

    static let builtIns: [AppTheme] = [.phosphor, .bloodwork,
                                       .ultraviolet, .arctic,
                                       .amber, .bone,
                                       .halloween, .christmas,
                                       .blackGlass, .redteam]

    static let defaultTheme = redteam
}

// Rest of Themes.swift (backdrop slots, picker, ThemeCenter, etc.)
// is unchanged and continues below in the full source.
