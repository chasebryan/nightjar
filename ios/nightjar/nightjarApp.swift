import SwiftUI

@main
struct NightjarApp: App {
    @StateObject private var post = ListeningPost()
#if !STORE_BUILD
    @StateObject private var updater = UpdateChecker()
#endif
    @StateObject private var mouth = Mouth()
    @StateObject private var toasts = ToastCenter()
    @StateObject private var emcon = Emcon()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(post)
#if !STORE_BUILD
                .environmentObject(updater)
#endif
                .environmentObject(mouth)
                .environmentObject(toasts)
                .environmentObject(emcon)
                .environmentObject(emcon.chat)
                .onAppear {
                    post.keepScreenAwake = keepScreenAwake
                    mouth.toasts = toasts
                    emcon.mouth = mouth
                    mouth.onHoneydropTaken = { peer in
                        emcon.raiseSense(
                            reason: "a honeydrop was taken "
                                + "by \(peer)")
                        Conductor.onHoneydrop(emcon: emcon,
                                              peer: peer)
                    }
                }
#if !STORE_BUILD
                .task {
                    await updater.checkIfDue()
                }
#endif
                .onChange(of: keepScreenAwake) { value in
                    post.keepScreenAwake = value
                }
                .task {
                    emcon.deadHandEvaluate(mouth: mouth)
                    emcon.steward.shiftChange(emcon: emcon)
                }
                .onChange(of: scenePhase) { phase in
                    post.sceneDidChange(toBackground: phase == .background)
                    if phase == .active {
                        emcon.deadHandEvaluate(mouth: mouth)
                        emcon.steward.shiftChange(emcon: emcon)
                        mouth.appBecameActive()
#if !STORE_BUILD
                        Task { await updater.checkIfDue() }
#endif
                    }
                }
        }
    }
}
