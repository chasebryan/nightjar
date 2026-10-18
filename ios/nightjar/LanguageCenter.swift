import Foundation
import SwiftUI

/// The app's tongue. One setting, chosen in About,
/// applied everywhere instantly and without a
/// relaunch: every localized string in the house is
/// looked up through here, against the .lproj table
/// for the chosen language.
///
/// English is both the key and the fallback: a call
/// site writes L("Sweep the wire"), the table for
/// the chosen language answers in that language,
/// and a string not yet translated shows in English
/// — never blank, never missing — so no language
/// ever loses a feature to an untranslated line.
///
/// Fonts need no bundling: the app draws with the
/// device's system fonts, which carry every script
/// it supports natively — Latin, Cyrillic, Arabic,
/// Devanagari, CJK, Hangul — at every size the
/// system offers, Dynamic Type included.
final class LanguageCenter: ObservableObject {
    static let shared = LanguageCenter()

    struct Language: Identifiable {
        let code: String
        /// The language's own name for itself —
        /// the one list that is never translated.
        let name: String
        var id: String { code }
    }

    static let languages: [Language] = [
        Language(code: "system", name: "System"),
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Español"),
        Language(code: "fr", name: "Français"),
        Language(code: "de", name: "Deutsch"),
        Language(code: "pt", name: "Português"),
        Language(code: "it", name: "Italiano"),
        Language(code: "ru", name: "Русский"),
        Language(code: "ja", name: "日本語"),
        Language(code: "ko", name: "한국어"),
        Language(code: "zh-Hans", name: "简体中文"),
        Language(code: "ar", name: "العربية"),
        Language(code: "hi", name: "हिन्दी"),
    ]

    @Published var code: String {
        didSet {
            UserDefaults.standard.set(code,
                                      forKey: "app.language")
        }
    }

    init() {
        code = UserDefaults.standard.string(
            forKey: "app.language") ?? "system"
    }

    /// The language actually in force: the choice,
    /// or the device's own first language when the
    /// choice is to follow the system.
    var effective: String {
        if code != "system" { return code }
        let preferred = Locale.preferredLanguages
            .first ?? "en"
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        let base = preferred.split(separator: "-")
            .first.map(String.init) ?? "en"
        return Self.languages.contains { $0.code == base }
            ? base : "en"
    }

    // MARK: the one-time welcome

    /// The language choice is offered exactly
    /// once, on a new device's first boot. The
    /// marker is a fact about the device, not a
    /// setting: it stays out of the reset registry
    /// and the setup mirror on purpose, so wiping
    /// preferences never replays the welcome and
    /// only a genuine new install ever sees it.
    static let welcomedKey = "app.languageWelcomed"

    var welcomed: Bool {
        UserDefaults.standard.bool(
            forKey: Self.welcomedKey)
    }

    func markWelcomed() {
        UserDefaults.standard.set(true,
                                  forKey: Self.welcomedKey)
    }

    /// The native name of the language in force —
    /// what the About door and the language room
    /// show as the current tongue.
    var effectiveNativeName: String {
        Self.languages.first { $0.code == effective }?
            .name ?? "English"
    }

    /// A language's English name, by code — shown
    /// beside the native name in the language room,
    /// so a traveller in a foreign-language house
    /// can still find their own tongue.
    static func englishName(for code: String) -> String {
        switch code {
        case "system": return "System"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "pt": return "Portuguese"
        case "it": return "Italian"
        case "ru": return "Russian"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "zh-Hans": return "Chinese (Simplified)"
        case "ar": return "Arabic"
        case "hi": return "Hindi"
        default: return "English"
        }
    }

    var isRTL: Bool { effective == "ar" }

    var locale: Locale { Locale(identifier: effective) }

    /// The chosen language's English name — for
    /// instructing her bench, which takes its
    /// orders in English and speaks in anything.
    var benchLanguageName: String {
        switch effective {
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "pt": return "Portuguese"
        case "it": return "Italian"
        case "ru": return "Russian"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "zh-Hans": return "Simplified Chinese"
        case "ar": return "Arabic"
        case "hi": return "Hindi"
        default: return "English"
        }
    }

    private var bundleCache: [String: Bundle] = [:]

    private func tableBundle() -> Bundle? {
        let code = effective
        if code == "en" { return nil }
        if let cached = bundleCache[code] { return cached }
        guard let path = Bundle.main.path(
                forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        bundleCache[code] = bundle
        return bundle
    }

    /// Look a string up in the chosen language.
    /// The English text is the key; untranslated
    /// falls back to it verbatim.
    func string(_ key: String) -> String {
        guard let bundle = tableBundle() else { return key }
        return bundle.localizedString(
            forKey: key, value: key, table: nil)
    }

    static func t(_ key: String) -> String {
        shared.string(key)
    }
}

/// The one seam every localized call site uses:
/// L("Sweep the wire").
func L(_ key: String) -> String {
    LanguageCenter.t(key)
}

/// The language room: every tongue the house
/// speaks, by its own name, with the tongue in
/// force checked. About's Language section opens
/// it as a sheet, and a new device's first boot
/// raises it once — in welcome form — before the
/// house is ever used, so the first choice is the
/// user's own. Choosing a language re-renders the
/// whole house around the choice; the room closes
/// itself as it lands.
struct LanguageSheet: View {
    var welcome: Bool = false
    @ObservedObject private var center =
        LanguageCenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if welcome {
                    Section {
                        Text(L("One choice, now — the whole house speaks it, Skelli included. Change it any time in About."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(LanguageCenter.languages) {
                        language in
                        Button {
                            center.code = language.code
                            if welcome {
                                center.markWelcomed()
                                dismiss()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading,
                                       spacing: 1) {
                                    Text(language.name)
                                        .foregroundStyle(
                                            .primary)
                                    if language.code != "system" {
                                        Text(LanguageCenter
                                            .englishName(
                                                for: language.code))
                                            .font(.caption)
                                            .foregroundStyle(
                                                .secondary)
                                    } else {
                                        Text(L("Follow the device"))
                                            .font(.caption)
                                            .foregroundStyle(
                                                .secondary)
                                    }
                                }
                                Spacer()
                                if center.code
                                    == language.code {
                                    Image(systemName:
                                            "checkmark")
                                        .foregroundStyle(
                                            .green)
                                }
                            }
                        }
                    }
                }
                Section {
                    LabeledContent(L("Speaking now"),
                                   value: center
                        .effectiveNativeName)
                    LabeledContent(L("Text direction"),
                                   value: center.isRTL
                                   ? L("Right to left")
                                   : L("Left to right"))
                }
                Section {
                    ExplainToggle(
                        text: L("Every tab, setting and switch — and Skelli herself, who answers in it too. Anything not yet translated shows in English, never blank. No fonts to install: the device's own fonts carry every script, at every size. Languages that read right to left turn the whole house with them."))
                }
            }
            .navigationTitle(welcome
                             ? L("Choose your language")
                             : L("Language"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(welcome ? L("Continue")
                           : L("Done")) {
                        if welcome {
                            center.markWelcomed()
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
