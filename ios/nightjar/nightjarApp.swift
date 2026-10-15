import SwiftUI

@main
struct NightjarApp: App {
    @StateObject private var post = ListeningPost()
    @StateObject private var updater = UpdateChecker()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(post)
                .environmentObject(updater)
                .onAppear {
                    post.keepScreenAwake = keepScreenAwake
                }
                .task {
                    await updater.checkIfDue()
                }
                .onChange(of: keepScreenAwake) { value in
                    post.keepScreenAwake = value
                }
                .onChange(of: scenePhase) { phase in
                    post.sceneDidChange(toBackground: phase == .background)
                    if phase == .active {
                        Task { await updater.checkIfDue() }
                    }
                }
        }
    }
}
