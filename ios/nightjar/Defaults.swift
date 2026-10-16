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
enum SaneDefaults {

    /// Every persisted settings key in the app. Clearing a key is
    /// what "restore the default" means: the next read falls back
    /// to the @AppStorage default declared beside the setting.
    static let keys: [String] = [
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
        "stealthMode",
        // Network Trace
        "traceScope", "traceAdaptive", "traceBonjour",
        "traceDiscoveryPorts", "traceProfilePorts", "traceRules",
        // Send-tab section layout
        "sectionOpen.centipede", "sectionOpen.crosstalk",
        "sectionOpen.fanout", "sectionOpen.plant",
        "sectionOpen.snatch", "sectionOpen.timing",
        "sectionOpen.trace",
        // EMCON
        "emconActive", "emconHomeSubnet", "emconVaultCombo",
        "emconVaultAction", "emconEscalation",
        "deadHand.on", "deadHand.hours", "deadHand.last",
        "deadHand.firedAt",
        "knocktalkRetentionHours", "knocktalkSuite",
        "knocktalkRelayEnabled", "knocktalkRelayURL",
        "knocktalkRelayToken", "knocktalkRelayBox",
        "emconCheckName", "emconCheckAirdrop", "emconCheckHotspot",
        "emconCheckWifi", "emconCheckBluetooth",
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
    ///  - EMCON's persisted flag is cleared here; the live EMCON
    ///    model reconciles against it the next time its tab
    ///    appears, standing the tripwire down if it was up.
    static func reset(mouth: Mouth) {
        let defaults = UserDefaults.standard
        for key in keys { defaults.removeObject(forKey: key) }
        if mouth.gattHostOn { mouth.stopGattHost() }
        defaults.removeObject(forKey: "gattArm.on")
        if mouth.beaconOn { mouth.stopBeacon() }
        if mouth.canary.runningPersona != nil { mouth.canary.stop() }
        if mouth.flareOn { mouth.stopFlare() }
        mouth.setStealth(false)
    }
}
