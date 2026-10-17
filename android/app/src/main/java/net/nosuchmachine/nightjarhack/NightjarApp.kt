package net.nosuchmachine.nightjarhack

import android.app.Application
import kotlinx.coroutines.flow.MutableStateFlow

/// The app shell: one of each engine, wired the way the iOS
/// app wires its environment objects.
class NightjarApp : Application() {
    lateinit var post: ListeningPost
    lateinit var book: PayloadBook
    lateinit var mouth: Mouth
    lateinit var serve: Serve
    lateinit var crawl: CrawlEngine
    lateinit var ble: BleMouth
    lateinit var engines: Engines
    lateinit var scanner: PortScanner
    lateinit var recon: Recon
    lateinit var emcon: Emcon
    lateinit var steward: Steward
    lateinit var knockEngine: KnockEngine
    lateinit var knockChat: KnockChat
    lateinit var traceStore: TraceBookStore
    lateinit var tracer: NetworkTracer

    /// Scan → Send handoff (a target, and optionally the name
    /// of the library probe that speaks its port's language).
    val sendHandoff = MutableStateFlow<String?>(null)
    val sendHandoffPayload = MutableStateFlow<String?>(null)

    /** A knocked port waiting for the Recon bench: host, port,
     * and a nonce so a repeat handoff on the same door still
     * registers as a change. */
    val reconHandoff =
        MutableStateFlow<Triple<String, Int, Long>?>(null)

    override fun onCreate() {
        super.onCreate()
        Journal.init(this)
        post = ListeningPost(this)
        book = PayloadBook(this)
        mouth = Mouth(this)
        serve = Serve(this, mouth)
        traceStore = TraceBookStore(this)
        crawl = CrawlEngine(mouth, serve, traceStore)
        ble = BleMouth(this, mouth)
        engines = Engines(mouth)
        scanner = PortScanner()
        recon = Recon(mouth)
        emcon = Emcon(this, mouth, serve, ble)
        tracer = NetworkTracer(this, mouth, traceStore) {
            // The trace's radio half: the listening post's
            // current rows, reduced to map facts at finish.
            post.rows.value.map { row ->
                TraceBLEDevice(
                    id = row.id,
                    name = row.label,
                    vendor = row.makers.sorted().joinToString(", "),
                    serviceUuids = row.serviceUUIDs,
                    rotatingAddress = row.rotatingAddress,
                    firstSeenMs = (row.firstSeen * 1000).toLong(),
                    lastSeenMs = (row.lastSeen * 1000).toLong(),
                    sightings = row.sightings,
                    closestRssi = row.rssiClosest,
                    smoothedRssi = row.rssiSmooth
                )
            }
        }
        mouth.bleArrivalHandler = { from, data ->
            serve.injectBleArrival(from, data)
        }
        // The conductor listens where the events already
        // flow: the tripwire funnel and the knock vault.
        val conductorPrefs = Prefs(this)
        emcon.conductorHook = { e, source, port, proto, verdict, mine ->
            Conductor.onKnock(
                conductorPrefs, e, source, port, proto, verdict, mine)
        }
        emcon.vaultHook = { e -> Conductor.onVault(conductorPrefs, e) }
        emcon.pivotSink = { host, port ->
            reconHandoff.value = Triple(host, port, System.nanoTime())
        }
        // The steward stands above the conductor: fed every
        // knock after it, and every line the journal seals.
        steward = Steward(conductorPrefs, emcon)
        emcon.stewardHook = { _, source, port, proto, verdict, mine ->
            steward.onKnock(source, port, proto, verdict, mine)
        }
        Journal.onEvent = { event -> steward.consume(event) }
        steward.shiftChange()
        // Knocktalk: the engine is fed every raw knock the
        // tripwire hears; its outputs land in the chat, the
        // pattern list, and the vault.
        KnockKeyStore.init(filesDir)
        knockEngine = KnockEngine()
        knockChat = KnockChat(conductorPrefs, filesDir)
        emcon.knockSink = { source, port, proto, verdict ->
            knockEngine.note(source, port, proto, verdict)
        }
        emcon.burnHook = { knockChat.burnNow() }
        emcon.comboSink = { combo ->
            knockEngine.vaultCombination = combo
        }
        knockEngine.vaultCombination = emcon.vaultCombo.value
        knockEngine.onOutput = { output ->
            handleKnockOutput(output)
        }
        knockChat.onRelayFrame = { from, ports ->
            for (port in ports) {
                knockEngine.note(
                    "relay:$from", port, "TCP",
                    "silent knock (no bytes sent)")
            }
        }
        knockChat.refreshRelayPolling()
        // The dead hand falls at an opening, before anything
        // else: if a check-in is overdue, this launch burns
        // and goes dark.
        emcon.deadHandEvaluate()
        // Coil with GIF support for the centipede splash.
        coil.Coil.setImageLoader(
            coil.ImageLoader.Builder(this)
                .components {
                    add(coil.decode.GifDecoder.Factory())
                }
                .build()
        )
    }

    /// Where the knock engine's outputs land: messages into
    /// the chat (the journal records that a message moved,
    /// never what it said), patterns into EMCON's knock
    /// traffic, a spoken combination into the vault, and the
    /// delivery protocol into the chat's hands.
    private fun handleKnockOutput(output: KnockEngine.Output) {
        when (output) {
            is KnockEngine.Output.Message -> {
                Journal.log(
                    "knocktalk", "arrival",
                    "message from ${output.message.source} — " +
                        "${output.message.text.length} chars")
                knockChat.receive(
                    output.message.text, output.message.source,
                    output.ackHash)
            }
            is KnockEngine.Output.Pattern -> {
                emcon.noteKnockPattern(output.pattern)
            }
            is KnockEngine.Output.VaultUnlock -> {
                emcon.openVault(output.source)
            }
            is KnockEngine.Output.Ack -> {
                knockChat.handleAck(output.source, output.hash)
            }
            is KnockEngine.Output.Nack -> {
                knockChat.handleNack(output.source, output.missing)
            }
            is KnockEngine.Output.NackNeeded -> {
                knockChat.requestRepair(
                    output.source, output.missing)
            }
        }
    }
}
