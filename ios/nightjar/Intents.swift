import AppIntents

/// "Send a payload" for Shortcuts and Siri. Network targets only —
/// the BLE mouth needs the app's UI (a device pick, a foreground
/// radio), so those throw a pointer back to the Send tab.
struct SendPayloadIntent: AppIntent {
    static var title: LocalizedStringResource = "Send a payload"
    static var description = IntentDescription("Send a text payload to a tcp://, udp://, or http(s):// target with nightjar-hack.")
    static var openAppWhenRun = false

    @Parameter(title: "Target",
               description: "For example tcp://192.0.2.10:9000")
    var target: String

    @Parameter(title: "Payload")
    var payload: String

    func perform() async throws -> some IntentResult {
        try Mouth.sendFromShortcut(targetText: target, payloadText: payload)
        return .result()
    }
}

struct NightjarHackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SendPayloadIntent(),
                    phrases: ["Send a payload with \(.applicationName)"],
                    shortTitle: "Send payload",
                    systemImageName: "paperplane")
    }
}
