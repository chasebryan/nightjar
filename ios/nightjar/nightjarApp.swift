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
    @StateObject private var language = LanguageCenter.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true

    init() {
        // The house's setup first: a fresh install
        // restores its configuration from the
        // Keychain mirror before anything reads a
        // setting, and the mirror starts watching.
        HouseSetup.prepare()
        // The backup shield (fix205): the
        // sensitive stores stay out of device
        // backups — applied before anything
        // writes, and again on backgrounding.
        BackupShield.shieldSensitiveStores()
        // The developer kit, when armed, stands
        // up before anything else can fall: the
        // crash traps are registered first, then
        // the launch itself joins the flight
        // recorder.
        CrashRecorder.installIfEnabled()
        DevLog.event("app", "launched")
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
                // The chosen tongue, applied to the
                // whole house at the root: locale for
                // dates and numbers, layout direction
                // for right-to-left scripts, and a
                // fresh identity so a switch re-renders
                // every string in place — no relaunch.
                .environment(\.locale, language.locale)
                .environment(\.layoutDirection,
                             language.isRTL
                                ? .rightToLeft : .leftToRight)
                .id(language.effective)
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
                    DevLog.event(
                        "app",
                        phase == .active
                            ? "became active"
                            : (phase == .background
                               ? "went to background"
                               : "inactive"))
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
                        BackupShield
                            .shieldSensitiveStores()
#if !STORE_BUILD
                        updater.unwatch()
                        UpdateChecker.scheduleBackgroundCheck()
#endif
                    }
                }
        }
    }
}
