import AppIntents

/// "Send a payload" for Shortcuts and Siri. Network targets only —
/// the BLE mouth needs the app's UI (a device pick, a foreground
/// radio), so those throw a pointer back to the Send tab.
struct SendPayloadIntent: AppIntent {
    static var title: LocalizedStringResource = "Send a payload"
    static var description = IntentDescription("Send a text payload to a tcp://, udp://, or http(s):// target with nightjar.")
    static var openAppWhenRun = false

    @Parameter(title: "Target",
               description: "For example tcp://192.0.2.10:9000")
    var target: String

    @Parameter(title: "Payload")
    var payload: String

    /// The send did not complete — reported honestly instead of a
    /// blanket success for a fire-and-forget send.
    private enum SendError: Error, LocalizedError {
        case sendFailed(String)
        var errorDescription: String? {
            switch self {
            case .sendFailed(let target):
                return "nightjar could not send to \(target)."
            }
        }
    }

    func perform() async throws -> some IntentResult {
        guard let mouth = Mouth.shared else {
            throw Mouth.ShortcutError.appNotRunning
        }
        let parsed = try SendTarget.parse(target)
        switch parsed {
        case .tcp, .udp, .http:
            break
        default:
            // The honest BLE refusal: those targets need the app.
            throw Mouth.ShortcutError.needsTheApp
        }
        // Build the payload the way the Send form does, using its
        // persisted settings (the @AppStorage keys in MouthView):
        // the payload source, and — for the sends below — the
        // framing, HTTP method and read-reply choices. Only the
        // text source substitutes templates against the target;
        // hex/base64 sources go out exactly as given.
        let defaults = UserDefaults.standard
        let source = defaults.string(forKey: "sendSource") ?? "text"
        let framing = defaults.string(forKey: "sendFraming") ?? "raw"
        let method = defaults.string(forKey: "sendMethod") ?? "POST"
        let readReply = defaults.object(forKey: "sendReadReply")
            as? Bool ?? true
        let data = try PayloadKit.build(
            source: source,
            text: PayloadKit.substitute(payload, targetText: target),
            hex: payload, b64: payload,
            xorSpec: "", useGzip: false)
        // Await the send's own completion — success is claimed only
        // when the send actually reports it.
        let sent = await withCheckedContinuation { continuation in
            let report: (Bool) -> Void = { ok in
                continuation.resume(returning: ok)
            }
            switch parsed {
            case .http:
                mouth.sendHTTP(target: parsed, payload: data,
                               framing: framing, method: method,
                               timeout: 10, completion: report)
            case .tcp, .udp:
                mouth.sendNetwork(target: parsed, payload: data,
                                  framing: framing, read: readReply,
                                  timeout: 5, completion: report)
            default:
                report(false)
            }
        }
        guard sent else { throw SendError.sendFailed(target) }
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
