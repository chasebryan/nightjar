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

    init() {
        // The house's setup first: a fresh install
        // restores its configuration from the
        // Keychain mirror before anything reads a
        // setting, and the mirror starts watching.
        HouseSetup.prepare()
#if !STORE_BUILD
        // Before launch finishes, on every launch — the
        // background update checker's handler must be on
        // file with the system before it can ever be woken.
        UpdateChecker.registerBackgroundCheck()
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(
                    KeyboardSwipeInstaller()
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false))
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
                        NeighborhoodStore.shared.discover(
                            source: peer, via: "the honeydrop")
                    }
                    Journal.onEvent = { event in
                        emcon.steward.consume(event)
                    }
                }
#if !STORE_BUILD
                .task {
                    updater.watch()
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
                        updater.watch()
#endif
                    }
                    if phase == .background {
#if !STORE_BUILD
                        updater.unwatch()
                        UpdateChecker.scheduleBackgroundCheck()
#endif
                    }
                }
        }
    }
}
