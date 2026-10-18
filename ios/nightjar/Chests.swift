import Foundation

/// The War Chest — a whole-app mission profile. A preset
/// remembers the Trace and the Centipede; a Chest remembers
/// the house's whole posture — Send, Serve, Recon, the
/// walkers and the talkers, stealth included — named, saved,
/// shared as JSON, and recalled in one tap.
///
/// The one rule that governs it, inherited from how presets
/// have always behaved: **apply ≠ arm.** Applying a Chest
/// writes configuration and nothing else. It never starts a
/// listener, a beacon, a GATT host, a walk, or a sweep;
/// starting things stays a deliberate tap, exactly as it
/// was. Stealth is applied as a setting, through the mouth's
/// own gate, so a mid-serve change restarts the listeners
/// the way the toggle itself does.
struct NJChest: Codable, Identifiable {
    var id: String
    var name: String

    // The preset heritage — the Trace and the route.
    var traceScope: String
    var traceDiscoveryPorts: String
    var traceProfilePorts: String
    var traceBonjour: Bool
    var traceAdaptive: Bool
    var traceRules: String
    var centipedeRoute: String

    // Send.
    var sendTarget: String
    var sendSource: String
    var sendFraming: String
    var sendMethod: String
    var sendReadReply: Bool
    var beaconName: String
    var fanoutTargets: String

    // The walkers and the talkers.
    var centipedeMode: String
    var centipedeReturn: Bool
    var centipedePerDevice: Bool
    var centipedeSmartSeed: Bool
    var talkTargetA: String
    var talkTargetB: String
    var talkRounds: Int
    var timingMode: String
    var timingDelay: String
    var timingInterval: String
    var timingRounds: String

    // Serve.
    var serveUseTCP: Bool
    var serveTcpPort: String
    var serveUseUDP: Bool
    var serveUdpPort: String
    var serveUseHTTP: Bool
    var serveHttpPort: String
    var serveReply: String
    var serveReplyMode: String
    var serveFraming: String
    var stealthMode: Bool

    // Recon — persisted since the Chest arrived; the bench
    // keeps its fields under these keys now.
    var reconHost: String
    var reconPorts: String
    var reconKnockUDP: Bool
    var reconJobs: Double
    var reconTimeout: Double
}

/// Capture and apply: a Chest reads and writes the very
/// UserDefaults keys the tabs bind with @AppStorage, with
/// the same declared defaults, so a capture is the house as
/// it stands and an apply is the house re-dressed — the
/// bound views follow the defaults, as they always have.
extension NJChest {

    /// The Trace rules' declared default, mirrored from
    /// SendView's @AppStorage so a capture taken before the
    /// section was ever opened still carries it whole.
    static let defaultTraceRules = """
        # Rules — one per line. They steer the trace and
        # the centipede: followup sends the named library
        # payload to the same door, tag files a label,
        # stop leaves the reply where it lies.
        # contains nginx => tag web
        # contains Redis => followup Redis PING (RESP)
        # port 22 => tag ssh
        """

    static func capture(id: String, name: String) -> NJChest {
        let d = UserDefaults.standard
        func s(_ key: String, _ fallback: String) -> String {
            d.string(forKey: key) ?? fallback
        }
        func b(_ key: String, _ fallback: Bool) -> Bool {
            (d.object(forKey: key) as? Bool) ?? fallback
        }
        func i(_ key: String, _ fallback: Int) -> Int {
            (d.object(forKey: key) as? Int) ?? fallback
        }
        func f(_ key: String, _ fallback: Double) -> Double {
            (d.object(forKey: key) as? Double) ?? fallback
        }
        return NJChest(
            id: id, name: name,
            traceScope: s("traceScope", ""),
            traceDiscoveryPorts: s("traceDiscoveryPorts",
                "80,443,22,445,1883,8080,8443,9100"),
            traceProfilePorts: s("traceProfilePorts", ""),
            traceBonjour: b("traceBonjour", true),
            traceAdaptive: b("traceAdaptive", true),
            traceRules: s("traceRules", defaultTraceRules),
            centipedeRoute: s("centipedeRoute", ""),
            sendTarget: s("sendTarget", "tcp://127.0.0.1:9000"),
            sendSource: s("sendSource", "text"),
            sendFraming: s("sendFraming", "raw"),
            sendMethod: s("sendMethod", "POST"),
            sendReadReply: b("sendReadReply", true),
            beaconName: s("beaconName", "nightjar-post"),
            fanoutTargets: s("fanoutTargets", ""),
            centipedeMode: s("centipedeMode", "chain"),
            centipedeReturn: b("centipedeReturn", true),
            centipedePerDevice: b("centipedePerDevice", false),
            centipedeSmartSeed: b("centipedeSmartSeed", true),
            talkTargetA: s("talkTargetA", ""),
            talkTargetB: s("talkTargetB", ""),
            talkRounds: i("talkRounds", 4),
            timingMode: s("timingMode", "now"),
            timingDelay: s("timingDelay", "30"),
            timingInterval: s("timingInterval", "10"),
            timingRounds: s("timingRounds", "5"),
            serveUseTCP: b("serveUseTCP", true),
            serveTcpPort: s("serveTcpPort", "9000"),
            serveUseUDP: b("serveUseUDP", false),
            serveUdpPort: s("serveUdpPort", "9001"),
            serveUseHTTP: b("serveUseHTTP", false),
            serveHttpPort: s("serveHttpPort", "8080"),
            serveReply: s("serveReply", "ack"),
            serveReplyMode: s("serveReplyMode", "static"),
            serveFraming: s("serveFraming", "raw"),
            stealthMode: b("stealthMode", false),
            reconHost: s("reconHost", ""),
            reconPorts: s("reconPorts", ""),
            reconKnockUDP: b("reconKnockUDP", false),
            reconJobs: f("reconJobs", 24.0),
            reconTimeout: f("reconTimeout", 1.5))
    }

    /// Dress the house in this Chest. Configuration only —
    /// nothing is started, armed, or sent. Stealth goes
    /// through the mouth's gate so its live state and the
    /// persisted setting never disagree.
    func apply(mouth: Mouth) {
        Haptics.press()
        let d = UserDefaults.standard
        d.set(traceScope, forKey: "traceScope")
        d.set(traceDiscoveryPorts, forKey: "traceDiscoveryPorts")
        d.set(traceProfilePorts, forKey: "traceProfilePorts")
        d.set(traceBonjour, forKey: "traceBonjour")
        d.set(traceAdaptive, forKey: "traceAdaptive")
        d.set(traceRules, forKey: "traceRules")
        d.set(centipedeRoute, forKey: "centipedeRoute")
        d.set(sendTarget, forKey: "sendTarget")
        d.set(sendSource, forKey: "sendSource")
        d.set(sendFraming, forKey: "sendFraming")
        d.set(sendMethod, forKey: "sendMethod")
        d.set(sendReadReply, forKey: "sendReadReply")
        d.set(beaconName, forKey: "beaconName")
        d.set(fanoutTargets, forKey: "fanoutTargets")
        d.set(centipedeMode, forKey: "centipedeMode")
        d.set(centipedeReturn, forKey: "centipedeReturn")
        d.set(centipedePerDevice, forKey: "centipedePerDevice")
        d.set(centipedeSmartSeed, forKey: "centipedeSmartSeed")
        d.set(talkTargetA, forKey: "talkTargetA")
        d.set(talkTargetB, forKey: "talkTargetB")
        d.set(talkRounds, forKey: "talkRounds")
        d.set(timingMode, forKey: "timingMode")
        d.set(timingDelay, forKey: "timingDelay")
        d.set(timingInterval, forKey: "timingInterval")
        d.set(timingRounds, forKey: "timingRounds")
        d.set(serveUseTCP, forKey: "serveUseTCP")
        d.set(serveTcpPort, forKey: "serveTcpPort")
        d.set(serveUseUDP, forKey: "serveUseUDP")
        d.set(serveUdpPort, forKey: "serveUdpPort")
        d.set(serveUseHTTP, forKey: "serveUseHTTP")
        d.set(serveHttpPort, forKey: "serveHttpPort")
        d.set(serveReply, forKey: "serveReply")
        d.set(serveReplyMode, forKey: "serveReplyMode")
        d.set(serveFraming, forKey: "serveFraming")
        d.set(reconHost, forKey: "reconHost")
        d.set(reconPorts, forKey: "reconPorts")
        d.set(reconKnockUDP, forKey: "reconKnockUDP")
        d.set(reconJobs, forKey: "reconJobs")
        d.set(reconTimeout, forKey: "reconTimeout")
        if mouth.stealth != stealthMode {
            mouth.setStealth(stealthMode)
        }
        Journal.log("chest", "applied",
                    "war chest applied — \(name) "
                    + "(configuration only; nothing started)")
    }
}

/// The chest shelf: a JSON array in UserDefaults, plus the
/// temp file the share sheet hands out — the preset shelf's
/// shape, kept.
enum NJChestStore {
    static let key = "njChests.v1"

    static func load() -> [NJChest] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder()
                .decode([NJChest].self, from: data)
        else { return [] }
        return decoded
    }

    static func save(_ chests: [NJChest]) {
        if let data = try? JSONEncoder().encode(chests) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func exportURL(_ chests: [NJChest]) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(chests)
        else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightjar-chests.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func decode(_ data: Data) -> [NJChest]? {
        try? JSONDecoder().decode([NJChest].self, from: data)
    }

    /// One-way, once: every preset on the old shelf becomes
    /// a Chest — its trace and route carried over, the rest
    /// of the posture captured as the house stands at
    /// migration time. The presets themselves are left
    /// exactly where they were.
    static func migratePresetsIfNeeded() {
        let flag = "njChests.migrated.v1"
        guard !UserDefaults.standard.bool(forKey: flag)
        else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let presets = NJPresetStore.load()
        guard !presets.isEmpty, load().isEmpty else { return }
        let migrated = presets.map { preset -> NJChest in
            var chest = NJChest.capture(id: preset.id,
                                        name: preset.name)
            chest.traceScope = preset.traceScope
            chest.traceDiscoveryPorts =
                preset.traceDiscoveryPorts
            chest.traceProfilePorts = preset.traceProfilePorts
            chest.traceBonjour = preset.traceBonjour
            chest.traceAdaptive = preset.traceAdaptive
            chest.traceRules = preset.traceRules
            chest.centipedeRoute = preset.centipedeRoute
            return chest
        }
        save(migrated)
        Journal.log("chest", "migrated",
                    "\(migrated.count) preset(s) grew into "
                    + "war chests; the old shelf stands")
    }
}
