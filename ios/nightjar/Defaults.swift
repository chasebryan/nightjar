import Foundation
import Security

/// Sane defaults, and the factory reset.
///
/// Every setting in this app has a default, and the default is the
/// sane one: the safe, legible choice a fresh install should run
/// on until the operator configures otherwise. The defaults
/// themselves live where they always have — in each setting's
/// @AppStorage declaration, one source of truth per setting. This
/// file is the census of every persisted key, and the one act
/// that wipes the slate entirely.
///
/// THE CHARTER (Chase's ruling, 2026-10-22, superseding the
/// preferences-only charter of the same day): the reset button
/// is a FULL factory reset. Everything returns to exactly as it
/// was originally shipped — settings, theme and backdrops,
/// EMCON's condition and every other posture, the App Lock and
/// every seal, the keychain, her memory and heart, sessions,
/// logs, saved files, downloaded weights. Nothing survives:
/// not art, not posture, not seals, not state. A narrower
/// settings-only reset no longer exists.
///
/// The key census below no longer drives the wipe — the wipe
/// takes the whole defaults domain, every keychain class, and
/// every file container, so a key invented tomorrow is wiped
/// even before it is censused. The census remains as the
/// house's accounting of what it persists, and the harness
/// holds it complete: every @AppStorage key in the tree must
/// appear here.
enum SaneDefaults {

    /// Every persisted key in the app — settings, art, posture,
    /// seals' mirrors, and accumulated state alike. Kept complete
    /// by harness check 12; the factory wipe itself is broader
    /// than any list (see reset()).
    static let keys: [String] = [
        // The app itself
        "app.language", "house.haptics", "defaults.insane",
        // This post / listening
        "postName", "keepScreenAwake",
        // Send
        "sendTarget", "sendSource", "sendMethod", "sendFraming",
        "sendReadReply", "beaconName", "recentTargets",
        // Centipede / crosstalk / fanout / timing / plant
        "centipedeMode", "centipedePerDevice", "centipedeReturn",
        "centipedeRoute", "centipedeSmartSeed", "centipedeSweepTarget",
        "talkRounds", "talkTargetA", "talkTargetB",
        "fanoutTargets",
        "timingMode", "timingDelay", "timingInterval", "timingRounds",
        "plantKey", "plantKind", "plantTopic", "plantValue",
        // Serve
        "serveTcpPort", "serveUdpPort", "serveHttpPort",
        "serveUseTCP", "serveUseUDP", "serveUseHTTP",
        "serveReply", "serveReplyMode", "serveFraming",
        "canaryPersona", "canaryPort",
        "canaryHoneydrop", "canaryDrop", "flare.on",
        "conductorOn", "conductorRules",
        "stewardOn", "stewardLatitude",
        "stealthMode",
        // Network Trace
        "traceScope", "traceAdaptive", "traceBonjour",
        "traceDiscoveryPorts", "traceProfilePorts", "traceRules",
        // Send-tab section layout
        "sectionOpen.centipede", "sectionOpen.crosstalk",
        "sectionOpen.fanout", "sectionOpen.plant",
        "sectionOpen.snatch", "sectionOpen.timing",
        "sectionOpen.trace",
        // EMCON — configuration and, under the factory
        // charter, the condition itself.
        "emconHomeSubnet", "emconVaultCombo",
        "emconVaultAction", "emconEscalation",
        "emcon.condition", "emconActive",
        // Onion — the SOCKS road and the wrap switch.
        "onion.socksHost", "onion.socksPort",
        "onion.lastProbe", "onion.wrap",
        "knocktalkRetentionHours",
        "knocktalkRelayEnabled", "knocktalkRelayURL",
        "knocktalkRelayToken", "knocktalkRelayBox",
        "knocktalkSuite",
        "cadence.profiles", "cadenceSealOn",
        "emconCheckName", "emconCheckAirdrop", "emconCheckHotspot",
        "emconCheckWifi", "emconCheckBluetooth",
        // Colours — the art itself: the selected theme,
        // the custom themes, her chat's fold.
        "theme.selected", "theme.customs",
        "skelli.minimalChat",
        // Recon bench, Net-Assault, the war rooms
        "reconHost", "reconPorts", "reconKnockUDP",
        "reconJobs", "reconTimeout",
        "assault.depth", "assault.rest", "assault.maxHours",
        "warRoomBLE",
        "warGamesPeerIP", "warGamesMatchPort",
        "warGamesDecoys",
        // Posture and seals' switches
        "deadHand.on", "deadHand.hours",
        "deadHand.firedAt", "deadHand.last",
        "coin.hash", "coin.lockKnocktalk",
        "voiceThrow.armed",
        // Her switches, the Macros editor, the
        // BTHome v1 ear — and her state: the draft,
        // the weights flag, the season, the counts
        // and learned paths the house accumulated.
        "skelli.mindMode", "skelli.moods", "skelli.agents",
        "macros.editingID",
        "place.enabled", "skelli.schedule",
        "listen.bthomeV1",
        "gattArm.name", "gattArm.payload",
        "headlines.enabled",
        "skelli.weightsModel",
        "skelli.draft", "skelli.weightsDownloaded",
        "season.state", "conductorFiredCounts",
        "canaryLearnedPaths",
    ]

    /// THE FACTORY RESET. Everything returns to exactly as it
    /// was originally shipped:
    ///
    ///  1. The live house stands down FIRST — Serve, the GATT
    ///     host, the beacon, the canary, the flare, stealth,
    ///     EMCON to open, the wardrive — because storage is
    ///     never cleared under a standing live model (the F11
    ///     trap), and a factory house transmits nothing.
    ///  2. Her center forgets: conversation, notes, marks,
    ///     her store file (her own resetToDefaults act).
    ///  3. The whole UserDefaults domain is removed — every
    ///     key above and any key the census has not met yet.
    ///     The setup mirror forgets too, or the old
    ///     configuration would restore itself later.
    ///  4. The keychain is emptied, every class: the App
    ///     Lock's seal, the cadence seal, knocktalk's
    ///     identity, SSH keys and hosts, every secret the
    ///     house was ever handed.
    ///  5. The file containers are emptied — Documents,
    ///     Application Support, Caches: sessions, logs,
    ///     the journal, saved files, custom backdrop media,
    ///     downloaded weights. (Shipped content lives in
    ///     the app bundle, which a reset never touches.)
    ///  6. The live theme center reconciles to the shipped
    ///     dress — no customs, the default theme worn — so
    ///     the running house matches its wiped storage.
    ///
    /// The next cold launch is the first launch: the boot,
    /// the welcome, the bird, Violent Redteam, EMCON open.
    static func reset(mouth: Mouth, emcon: Emcon) {
        // 1. Stand the live house down.
        if mouth.serveRunning { mouth.stopServe() }
        if mouth.gattHostOn { mouth.stopGattHost() }
        if mouth.beaconOn { mouth.stopBeacon() }
        if mouth.canary.runningPersona != nil {
            mouth.canary.stop()
        }
        if mouth.flareOn { mouth.stopFlare() }
        mouth.setStealth(false)
        emcon.deactivate()
        WardriveCenter.shared.stop()
        // 2. She forgets.
        SkelliCenter.shared.resetToDefaults()
        // 3. The whole defaults domain.
        let defaults = UserDefaults.standard
        if let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        }
        HouseSetup.forgetMirror()
        // 4. Every keychain item, every class.
        wipeKeychain()
        // 5. Every file container.
        wipeContainers()
        // 6. The running house wears the shipped dress.
        ThemeCenter.shared.factoryReset()
    }

    /// Delete every keychain item this app owns, class by
    /// class. A class-only query is scoped by the sandbox to
    /// the app's own access group — the factory takes its
    /// secrets with everything else.
    private static func wipeKeychain() {
        let classes: [CFString] = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity,
        ]
        for secClass in classes {
            let query: [CFString: Any] = [kSecClass: secClass]
            SecItemDelete(query as CFDictionary)
        }
    }

    /// Empty the app's file containers — every item inside
    /// Documents, Application Support, and Caches goes; the
    /// containers themselves stay, as they were at install.
    /// Each store inside recreates what it needs on first
    /// use, exactly as it did on the first launch.
    private static func wipeContainers() {
        let fm = FileManager.default
        var roots: [URL] = []
        roots += fm.urls(for: .documentDirectory,
                         in: .userDomainMask)
        roots += fm.urls(for: .applicationSupportDirectory,
                         in: .userDomainMask)
        roots += fm.urls(for: .cachesDirectory,
                         in: .userDomainMask)
        for root in roots {
            let items = (try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                try? fm.removeItem(at: item)
            }
        }
    }
}

/// Insane defaults — the other pole (Chase's word, 2026-10-22).
///
/// Where the sane defaults are the safe, legible choices, the
/// insane table is every posture, reach and tempo SETTING at
/// its extreme: the extra ear open, the fanout per device, UDP
/// knocked alongside TCP, crosstalk at its round cap, the
/// assault rest at its floor, her agents awake, the timing
/// engine at no delay and its fastest interval. The live
/// posture goes loud with it — EMCON stood down to Open,
/// stealth off — applied through the live centers, exactly
/// as the factory reset applies its stand-down.
///
/// The line the table never crosses: it writes SETTINGS. It
/// starts no organ, fires no transmission, arms no seal and
/// flips no standing emission — those remain the operator's
/// hand-fired acts, in insane mode exactly as in sane.
///
/// Turning the mode off removes the table's keys, and each
/// setting's own sane @AppStorage default stands back up.
/// The factory reset takes the flag with the whole domain.
enum InsaneDefaults {

    /// The mode's own persisted flag — censused in
    /// SaneDefaults.keys like every other key in the house.
    static let flagKey = "defaults.insane"

    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: flagKey)
    }

    /// The table: each key at the extreme end of its own
    /// range or meaning, in the type its reader expects.
    static let table: [(key: String, value: Any)] = [
        // The BTHome v1 ear: open.
        ("listen.bthomeV1", true),
        // Centipede: a payload per device, not per room.
        ("centipedePerDevice", true),
        // Recon: UDP knocked alongside TCP.
        ("reconKnockUDP", true),
        // Crosstalk: the Stepper's own cap.
        ("talkRounds", 12),
        // Net-Assault: the rest at its floor — near-relentless.
        ("assault.rest", 5.0),
        // Her agents: awake.
        ("skelli.agents", true),
        // The timing engine: no delay, the fastest
        // interval, twenty rounds.
        ("timingDelay", "0"),
        ("timingInterval", "1"),
        ("timingRounds", "20"),
    ]

    /// Write the table into a defaults domain.
    static func writeTable(to defaults: UserDefaults) {
        for row in table {
            defaults.set(row.value, forKey: row.key)
        }
    }

    /// Remove the table's keys; the sane defaults return.
    static func clearTable(from defaults: UserDefaults) {
        for row in table {
            defaults.removeObject(forKey: row.key)
        }
    }

    /// Flip the mode on: the table lands, the flag stands,
    /// and the live posture goes loud.
    static func apply(mouth: Mouth, emcon: Emcon) {
        writeTable(to: .standard)
        UserDefaults.standard.set(true, forKey: flagKey)
        emcon.deactivate()
        mouth.setStealth(false)
        Journal.log("defaults", "insane",
                    "insane defaults on — posture, reach "
                    + "and tempo at their extremes")
    }

    /// Flip it off: the table's keys go, the sane defaults
    /// stand back up. The live posture stays where the
    /// operator has it — nothing was silenced to undo.
    static func restore() {
        clearTable(from: .standard)
        UserDefaults.standard.set(false, forKey: flagKey)
        Journal.log("defaults", "insane",
                    "insane defaults off — the sane "
                    + "defaults hold these keys again")
    }
}
