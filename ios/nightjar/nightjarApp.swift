import SwiftUI

@main
struct NightjarApp: App {
    @StateObject private var post = ListeningPost()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(post)
                .onAppear {
                    post.keepScreenAwake = keepScreenAwake
                }
                .onChange(of: keepScreenAwake) { value in
                    post.keepScreenAwake = value
                }
                .onChange(of: scenePhase) { phase in
                    post.sceneDidChange(toBackground: phase == .background)
                }
        }
    }
}
