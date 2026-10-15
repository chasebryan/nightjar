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

/// One place for every buzz, so buttons *feel* like they did something.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
