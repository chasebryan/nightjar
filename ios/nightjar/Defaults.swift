import Foundation

/// Sane defaults.
///
/// Every setting in this app has a default, and the default is the
/// sane one: the safe, legible choice a fresh install should run
/// on until the operator configures otherwise. The defaults
/// themselves live where they always have — in each setting's
/// @AppStorage declaration, one source of truth per setting. This
/// file is the registry of every settings key, so that a reset can
/// restore all of them at once, and the live-state reconciliation
/// that must accompany it.
///
/// A reset restores CONFIGURATION. It does not touch data: the
/// payload library, saved presets, sessions, the trace logbook,
/// and the EMCON tripwire log are the operator's records, not
/// settings, and they survive a reset untouched.
///
/// THE CHARTER (Chase's ruling, 2026-10-22): a reset restores
/// PREFERENCES — values with a sane shipped default — and
/// stands down live emissions. It never touches:
///  - ART: the selected theme, custom themes, the backdrop
///    choices and their media (absent from this registry
///    entirely — resetting to defaults is not redecorating);
///  - POSTURE: EMCON's condition, the Onion wrap switch, the
///    dead hand, the cadence seal, the knocktalk coin and
///    suite, the voice throw's arm — the house's security
///    stance changes only through its own deliberate
///    controls, never as a side effect of a settings reset;
///  - SEALS: the App Lock above all. Its seal record is the
///    authority and its settings mirror the seal, so no
///    applock key is ever listed here — a reset must never
///    disarm or desync a lock;
///  - STATE: what the house has accumulated — her heart and
///    the facts she was told, the steward's cases, the
///    canary's learned paths, conductor fire counts, the
///    season, wardrive logs (records, like the data above).
/// New systems join this registry by the same rule: their
/// preferences are listed, their posture and their records
/// are not. The Gauntlet pins this charter.
enum SaneDefaults {

    /// Every persisted settings key in the app. Clearing a key is
    /// what "restore the default" means: the next read falls back
    /// to the @AppStorage default declared beside the setting.
    static let keys: [String] = [
        // The app itself
        "app.language", "house.haptics",
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
        // EMCON — its configuration is a preference;
        // the CONDITION is posture, outside the charter,
        // and is not listed.
        "emconHomeSubnet", "emconVaultCombo",
        "emconVaultAction", "emconEscalation",
        // Onion — the SOCKS road is a preference; the
        // wrap switch is posture and is not listed.
        "onion.socksHost", "onion.socksPort",
        "onion.lastProbe",
        "knocktalkRetentionHours",
        "knocktalkRelayEnabled", "knocktalkRelayURL",
        "knocktalkRelayToken", "knocktalkRelayBox",
        "cadence.profiles",
        "emconCheckName", "emconCheckAirdrop", "emconCheckHotspot",
        "emconCheckWifi", "emconCheckBluetooth",
        // Colours — her chat's fold is a preference.
        // The theme, the custom themes, and every
        // backdrop choice are ART, outside the
        // charter, and are not listed.
        "skelli.minimalChat",
        // Recon bench, Net-Assault, the war rooms
        "reconHost", "reconPorts", "reconKnockUDP",
        "reconJobs", "reconTimeout",
        "assault.depth", "assault.rest", "assault.maxHours",
        "warRoomBLE",
        "warGamesPeerIP", "warGamesMatchPort",
        "warGamesDecoys",
        // Her switches, the Macros editor, the
        // BTHome v1 ear. (Her facts, her heart,
        // her draft, and the weights' downloaded
        // flag are state, outside the charter —
        // forgetting those is her own reset's act.)
        "skelli.mindMode", "skelli.moods", "skelli.agents",
        "macros.editingID",
        "place.enabled", "skelli.schedule",
        "listen.bthomeV1",
        "gattArm.name", "gattArm.payload",
        "headlines.enabled",
        "skelli.weightsModel",
    ]

    /// Restore every setting to its sane default and reconcile the
    /// live state that settings drive, so nothing keeps running on
    /// a configuration that no longer exists:
    ///  - the BLE GATT host disarms (its arm is a setting with a
    ///    payload attached; stopGattHost clears both),
    ///  - the BLE beacon stops,
    ///  - stealth returns to its default through setStealth, which
    ///    also restarts a running Serve so its announcement (or
    ///    lack of one) matches the restored default,
    ///  - EMCON does NOT stand down: its condition is
    ///    posture, outside the charter above. The gates
    ///    read the stored condition, so a reset owes it
    ///    no reconciliation — it stays exactly where
    ///    the operator left it. (Before the charter, a
    ///    reset deactivated EMCON on the spot; the
    ///    F11 trap it answered — cleared storage under
    ///    a standing live model — cannot recur while
    ///    the condition is never cleared.)
    static func reset(mouth: Mouth, emcon: Emcon) {
        _ = emcon  // posture is the operator's; untouched here
        let defaults = UserDefaults.standard
        for key in keys { defaults.removeObject(forKey: key) }
        // The setup mirror forgets too, or the
        // old configuration would restore itself
        // into the next fresh install.
        HouseSetup.forgetMirror()
        // Her room unfolds too: the fold is
        // center state now, and a reset that
        // only cleared its key would leave the
        // live room folded over an open store —
        // the same trap EMCON taught (F11).
        SkelliCenter.shared.minimalChat = false
        if mouth.gattHostOn { mouth.stopGattHost() }
        defaults.removeObject(forKey: "gattArm.on")
        if mouth.beaconOn { mouth.stopBeacon() }
        if mouth.canary.runningPersona != nil { mouth.canary.stop() }
        if mouth.flareOn { mouth.stopFlare() }
        mouth.setStealth(false)
    }
}
