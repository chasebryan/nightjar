import SwiftUI
import UIKit

/// Little in-app banners that say what just happened, then fade —
/// so the app narrates itself instead of silently changing state.
final class ToastCenter: ObservableObject {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    @Published var current: Toast?
    private var generation = 0

    func show(_ message: String, error: Bool = false) {
        generation += 1
        let mine = generation
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            current = Toast(message: message, isError: error)
        }
        let dwell = error ? 4.5 : 2.8
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell) { [weak self] in
            guard let self = self, self.generation == mine else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.current = nil }
        }
    }
}

struct ToastView: View {
    let toast: ToastCenter.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError
                  ? "exclamationmark.triangle.fill"
                  : "checkmark.circle.fill")
            Text(toast.message)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(
            toast.isError ? Color.red.opacity(0.92)
                          : Color(white: 0.16).opacity(0.95)))
        .shadow(radius: 8, y: 3)
        .padding(.horizontal, 16)
    }
}

/// The app's backdrop: the Jolly Roger over near-black, dimmed a
/// touch so text stays readable. The image lives in the asset
/// catalog as "AppBackground" — it is added in Xcode (binaries
/// cannot ride the repo connector, same as the app icon was);
/// until it lands, the app simply wears black.
struct AppBackdrop: View {
    var body: some View {
        // GeometryReader pins the backdrop to exactly the size it
        // is offered. A bare scaledToFill image inside a ZStack
        // reports its natural size (1320x2855!) and blows the
        // whole layout out to match — frame + clip keep it tame.
        GeometryReader { geo in
            ZStack {
                Color(white: 0.03)
                Image("AppBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                Rectangle().fill(Color.black.opacity(0.18))
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The themed-screen recipe, applied per tab: transparent scroll
/// backgrounds AND the backdrop painted behind that very screen.
/// (Painting it only behind the TabView is not enough — on
/// current iOS the tab container fills its own frame opaquely,
/// so an ancestor's backdrop never shows through. Behind each
/// tab's own root, with its list transparent, it does.)
struct AppThemed: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
    }
}

extension View {
    func appThemed() -> some View { modifier(AppThemed()) }
}

/// Boot splash, OS-style: black screen, the Jolly Roger as the
/// machine's emblem, a wordmark, and a boot log that types itself
/// line by line over a progress bar — and every line is true:
/// this device, this network, this library, this stealth state.
/// Fades into the app after ~2 seconds; a tap skips it.
struct BootView: View {
    let onDone: () -> Void

    @StateObject private var book = PayloadBook()
    @AppStorage("stealthMode") private var stealthMode = false
    @State private var shown = 0
    @State private var cursorOn = true

    private struct BootLine {
        let text: String
        let tone: Tone
        enum Tone { case cmd, ok, warn, off }
    }

    private var lines: [BootLine] {
        var out: [BootLine] = [
            BootLine(text: "> nightjar-hack // ios", tone: .cmd),
            BootLine(text: "[ ok ] host      \(UIDevice.current.name)",
                     tone: .ok),
        ]
        if let ip = Mouth.localIPAddress() {
            out.append(BootLine(text: "[ ok ] wlan0     \(ip)/24",
                                tone: .ok))
        } else {
            out.append(BootLine(text: "[ !! ] wlan0     down — no wi-fi",
                                tone: .warn))
        }
        out.append(BootLine(
            text: "[ ok ] library   \(book.items.count) payloads loaded",
            tone: .ok))
        out.append(BootLine(text: "[ ok ] ble       radio standing by",
                            tone: .ok))
        out.append(stealthMode
            ? BootLine(text: "[ ok ] stealth   ON — unlisted, silent",
                       tone: .ok)
            : BootLine(text: "[ -- ] stealth   off", tone: .off))
        out.append(BootLine(text: "[ ok ] backdrop  jolly roger",
                            tone: .ok))
        out.append(BootLine(text: "> systems nominal — welcome back",
                            tone: .cmd))
        return out
    }

    private func color(_ tone: BootLine.Tone) -> Color {
        switch tone {
        case .cmd: return Color(white: 0.92)
        case .ok: return Color(red: 0.35, green: 1.0, blue: 0.45)
        case .warn: return Color(red: 1.0, green: 0.72, blue: 0.25)
        case .off: return Color(white: 0.55)
        }
    }

    private var progress: CGFloat {
        lines.isEmpty ? 0 : CGFloat(shown) / CGFloat(lines.count)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Image("AppBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 216, height: 216)
                    .clipped()
                    .overlay(Rectangle().stroke(
                        Color.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black, radius: 18, y: 8)
                Text("nightjar-hack")
                    .font(.system(.title3, design: .monospaced)
                          .weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.top, 20)
                Text("IOS BUILD · FIELD UNIT")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<min(shown, lines.count), id: \.self) { i in
                        Text(lines[i].text)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(color(lines[i].tone))
                    }
                    Text("▊")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(color(.ok))
                        .opacity(cursorOn ? 1 : 0)
                }
                .frame(width: 300, height: 168, alignment: .topLeading)
                .padding(.top, 30)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3)
                    Rectangle()
                        .fill(color(.ok))
                        .frame(width: 300 * progress, height: 3)
                        .animation(.easeOut(duration: 0.25), value: shown)
                }
                .frame(width: 300)
                .padding(.top, 14)
                Spacer()
                Text("TAP TO SKIP")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
                    .padding(.bottom, 26)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .task {
            let blink = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 420_000_000)
                    cursorOn.toggle()
                }
            }
            for _ in lines.indices {
                try? await Task.sleep(
                    nanoseconds: UInt64.random(in: 110_000_000...210_000_000))
                if Task.isCancelled { blink.cancel(); return }
                shown += 1
                Haptics.tick()
            }
            try? await Task.sleep(nanoseconds: 550_000_000)
            blink.cancel()
            if Task.isCancelled { return }
            Haptics.success()
            onDone()
        }
    }
}

/// One place for every buzz, so buttons *feel* like they did something.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The boot sequence's per-line keystroke.
    static func tick() {
        UIImpactFeedbackGenerator(style: .rigid)
            .impactOccurred(intensity: 0.3)
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
