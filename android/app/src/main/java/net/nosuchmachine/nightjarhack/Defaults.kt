package net.nosuchmachine.nightjarhack

/// Sane defaults.
///
/// Every setting in this app has a default, and the default is
/// the sane one: the safe, legible choice a fresh install
/// should run on until the operator configures otherwise. The
/// defaults themselves live where they always have — in each
/// setting's pref declaration, one source of truth per
/// setting. This file is the registry of every settings key,
/// so that a reset can restore all of them at once, and the
/// live-state reconciliation that must accompany it.
///
/// A reset restores CONFIGURATION. It does not touch data:
/// the payload library, saved presets, sessions, the night
/// log, and the EMCON tripwire log are the operator's records,
/// not settings, and they survive a reset untouched.
object SaneDefaults {

    /// Every persisted settings key in the app. Clearing a
    /// key is what "restore the default" means: the next read
    /// falls back to the default declared beside the setting.
    val keys: List<String> = listOf(
        // This post / listening
        "listenLabel",
        // Send
        "sendTarget", "payloadSource", "payloadText",
        "payloadFraming", "payloadXor", "payloadGzip",
        "readReply", "httpMethod", "recentTargets", "njPresets",
        // Centipede / crosstalk / fanout / timing / plant
        "centipedeMode", "centipedePerDevice", "centipedeReturn",
        "centipedeRoute", "centipedeSmartSeed",
        "centipedeSweepTarget", "centipedeHome",
        "talkRounds", "talkTargetA", "talkTargetB",
        "fanoutLines",
        "timingCount", "timingDelay", "timingInterval",
        "plantKey", "plantService", "plantValue", "snatchKnock",
        // Serve
        "serveTcpPort", "serveUdpPort", "serveHttpPort",
        "serveReplyMode", "serveReplyText", "serveStealth",
        "canaryPersona", "canaryPort",
        "canaryHoneydrop", "canaryDrop", "canaryLearnedPaths",
        "conductorOn", "conductorRules", "conductorFired",
        "stewardOn", "stewardLatitude", "stewardProposals",
        "stewardFired", "stewardLastShift", "stewardDismissed",
        "stewardOrders", "stewardWatches", "stewardCases",
        "brushLastAt", "brushLastHash",
        // Scan
        "scanHost", "scanPorts", "tlsHost", "tlsPort",
        "sweepTarget", "sweepPort", "feedHost",
        // Network Trace
        "traceScope", "traceAdaptive", "traceBonjour",
        "traceProfilePorts", "traceRules",
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
        "emconCheckName", "emconCheckShare", "emconCheckHotspot",
        "emconCheckWifi", "emconCheckBluetooth"
    )

    /// Restore every setting to its sane default and
    /// reconcile the live state that settings drive, so
    /// nothing keeps running on a configuration that no
    /// longer exists:
    ///  - the BLE GATT host disarms,
    ///  - the BLE beacon stops,
    ///  - the canary stands down,
    ///  - the flare stops,
    ///  - stealth returns to its default through
    ///    Emcon.setStealth, which also restarts a running
    ///    Serve so its announcement (or lack of one) matches
    ///    the restored default,
    ///  - EMCON's persisted flag is cleared here; the live
    ///    EMCON model reconciles against it the next time its
    ///    tab appears, standing the tripwire down if it was up.
    /// Per-host prober-file sightings (proberFileSeen.*) are
    /// settings-shaped too and clear with the census.
    fun reset(app: NightjarApp) {
        val prefs = Prefs(app)
        for (key in keys) prefs.remove(key)
        for (key in prefs.allKeys()) {
            if (key.startsWith("proberFileSeen.")) {
                prefs.remove(key)
            }
        }
        if (app.ble.hosting.value) app.ble.stopHosting()
        if (app.ble.beaconOn.value) app.ble.stopBeacon()
        if (app.canary.runningPersona != null) app.canary.stop()
        if (app.ble.flareOn.value) app.ble.stopFlare()
        app.emcon.setStealth(false)
    }
}
