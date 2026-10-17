package net.nosuchmachine.nightjarhack

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/// KnockChat — the Kotlin mirror of the iOS KnockChat:
/// Knocktalk as an actual conversation.
///
/// Two devices running this app are both always listening
/// (the tripwire never closes), so the channel is two-way by
/// nature: a message is a knock stream one way, its ACK a
/// knock stream back. This model owns the threads and the
/// delivery protocol:
///
///  - send: seal once, fragment, knock the frames. State:
///    sending → awaiting.
///  - The receiver reassembles and knocks an ACK naming the
///    message's hash → state: delivered.
///  - Holes in a reassembly make the receiver knock a NACK
///    listing the missing fragments; the sender re-knocks
///    only those (two repair rounds, then an honest failed).
///  - No answer inside the airtime-plus-margin window →
///    failed, with a manual resend.
///
/// Threads persist as JSON in the private file store.
/// Decoded texts live here and nowhere else — the night
/// log records that messages moved, never what they said.
class KnockChat(
    private val prefs: Prefs,
    private val filesDir: File
) {
    data class ChatMessage(
        val id: String, val peer: String, val outgoing: Boolean,
        val text: String, val whenMs: Long,
        /** sending | awaiting | delivered | failed | received */
        val state: String,
        /** ACK-matching hash nibbles (outgoing only). */
        val hash: List<Int>? = null,
        /** The suite this message was sealed under (outgoing
         * only) — repairs re-knock fragments of the ORIGINAL
         * sealing, in its own suite. */
        val suite: Int? = null
    )

    /** The suite this operator sends with. Receiving needs
     * no matching setting: every fragment names its suite
     * and the open follows it. */
    private val _sendSuite = MutableStateFlow(
        prefs.string("knocktalkSuite", "").toIntOrNull()
            ?: Knocktalk.SUITE_CHACHA)
    val sendSuite: StateFlow<Int> = _sendSuite

    fun setSendSuite(suite: Int) {
        _sendSuite.value = suite
        prefs.put("knocktalkSuite", suite.toString())
    }

    private val _threads =
        MutableStateFlow<Map<String, List<ChatMessage>>>(
            emptyMap())
    val threads: StateFlow<Map<String, List<ChatMessage>>> =
        _threads

    val sender = KnockSender()

    /// The burn timer: hours, 0 = never, default 24.
    private val _retentionHours = MutableStateFlow(
        prefs.string("knocktalkRetentionHours", "")
            .toDoubleOrNull() ?: 24.0)
    val retentionHours: StateFlow<Double> = _retentionHours

    private data class OutboxItem(
        val peer: String, val frames: List<List<Int>>,
        val messageID: String?
    )

    private val outbox = ArrayDeque<OutboxItem>()
    private val outboxLock = Any()
    private val sealedStore = mutableMapOf<String, ByteArray>()
    private val repairRounds = mutableMapOf<String, Int>()
    private val ackJobs = mutableMapOf<String, Job>()
    private val scope =
        CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val ioScope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /// Sequences that arrive through the operator's relay
    /// are replayed into the knock engine through this hook
    /// (wired by the app at launch: source "relay:<mailbox>",
    /// ports in order, the silent-knock verdict).
    var onRelayFrame: ((from: String, ports: List<Int>) -> Unit)? =
        null
    private var relayJob: Job? = null
    @Volatile private var relayDeclaring = false
    private val _relayStatus = MutableStateFlow("")
    val relayStatus: StateFlow<String> = _relayStatus

    init {
        _threads.value = loadThreads()
        purge()
        sender.onQueueEmpty = { pumpOutbox() }
    }

    // MARK: - peers + keys

    companion object {
        /// Thread keys are bare addresses — the tripwire's
        /// source labels (" (this device)") are display
        /// text, and an ACK must find the thread the
        /// operator opened by address.
        fun peerKey(raw: String): String =
            raw.split(" ").firstOrNull() ?: raw
    }

    val peersByRecency: List<String>
        get() = _threads.value.keys.sortedByDescending {
            _threads.value[it]?.lastOrNull()?.whenMs ?: 0
        }

    val totalMessages: Int
        get() = _threads.value.values.sumOf { it.size }

    // MARK: - sending

    /** Seal, fragment, and queue a message. Returns false
     * when the sealed form exceeds the fragment budget —
     * better an honest refusal than a silent truncation. */
    fun send(text: String, to: String, key: ByteArray): Boolean {
        val peer = peerKey(to)
        if (peer.isEmpty()) return false
        val sealed = try {
            Knocktalk.seal(text, key, _sendSuite.value)
        } catch (_: Exception) {
            return false
        }
        if (sealed.size > Knocktalk.maxSealedBytes) return false
        val message = ChatMessage(
            id = java.util.UUID.randomUUID().toString(),
            peer = peer, outgoing = true, text = text,
            whenMs = System.currentTimeMillis(),
            state = "sending",
            hash = Knocktalk.hashNibbles(sealed),
            suite = _sendSuite.value)
        append(message)
        synchronized(outboxLock) {
            sealedStore[message.id] = sealed
            repairRounds[message.id] = 0
            outbox.addLast(
                OutboxItem(
                    peer,
                    Knocktalk.fragmentFrames(
                        sealed, _sendSuite.value),
                    message.id))
        }
        pumpOutbox()
        return true
    }

    /** Manual resend of a failed message: the whole message,
     * fresh rounds. */
    fun resend(messageID: String, key: ByteArray) {
        val message = find(messageID) ?: return
        val sealed = try {
            Knocktalk.seal(message.text, key, _sendSuite.value)
        } catch (_: Exception) {
            return
        }
        synchronized(outboxLock) {
            sealedStore[messageID] = sealed
            repairRounds[messageID] = 0
        }
        update(messageID) {
            it.copy(
                state = "sending", suite = _sendSuite.value,
                hash = Knocktalk.hashNibbles(sealed))
        }
        synchronized(outboxLock) {
            outbox.addLast(
                OutboxItem(
                    message.peer,
                    Knocktalk.fragmentFrames(
                        sealed, _sendSuite.value),
                    messageID))
        }
        pumpOutbox()
    }

    private fun pumpOutbox() {
        if (sender.busy || relayDeclaring) return
        val next = synchronized(outboxLock) {
            if (outbox.isEmpty()) null else outbox.removeFirst()
        } ?: return
        val box = KnockRelay.mailbox(ofPeer = next.peer)
        if (box != null) {
            // A mailbox peer: declare the destination at the
            // operator's relay, then knock the sequence at
            // the relay host — from the wire's point of view
            // the relay IS the other phone's perimeter.
            if (!KnockRelay.configured(prefs)) {
                next.messageID?.let { id ->
                    update(id) { it.copy(state = "failed") }
                }
                pumpOutbox()
                return
            }
            val relayHost = KnockRelay.host(prefs) ?: return
            relayDeclaring = true
            ioScope.launch {
                val ok = KnockRelay.declare(prefs, box)
                relayDeclaring = false
                if (!ok) {
                    next.messageID?.let { id ->
                        update(id) { it.copy(state = "failed") }
                    }
                    pumpOutbox()
                    return@launch
                }
                sender.sendFrames(relayHost, next.frames)
                trackDelivery(next)
            }
            return
        }
        sender.sendFrames(next.peer, next.frames)
        trackDelivery(next)
    }

    private fun trackDelivery(item: OutboxItem) {
        val id = item.messageID ?: return
        // Delivery deadline: airtime plus margin.
        val knocks = item.frames.sumOf { it.size }
        val deadlineMs =
            (Knocktalk.etaSeconds(knocks) + 90) * 1000L
        ackJobs[id]?.cancel()
        ackJobs[id] = scope.launch {
            delay(deadlineMs)
            if (find(id)?.state == "awaiting") {
                update(id) { it.copy(state = "failed") }
            }
        }
        // Flip sending → awaiting as soon as the frames drain.
        scope.launch {
            while (sender.busy) delay(1000)
            if (find(id)?.state == "sending") {
                update(id) { it.copy(state = "awaiting") }
            }
            pumpOutbox()
        }
    }

    // MARK: - receiving (called from engine outputs)

    fun receive(text: String, from: String, ackHash: List<Int>?) {
        val peer = peerKey(from)
        append(
            ChatMessage(
                id = java.util.UUID.randomUUID().toString(),
                peer = peer, outgoing = false, text = text,
                whenMs = System.currentTimeMillis(),
                state = "received"))
        purge()
        if (ackHash != null) {
            synchronized(outboxLock) {
                outbox.addLast(
                    OutboxItem(
                        peer,
                        listOf(Knocktalk.ackFrame(ackHash)),
                        null))
            }
            pumpOutbox()
        }
    }

    fun handleAck(from: String, hash: List<Int>) {
        val peer = peerKey(from)
        val message = _threads.value[peer]?.lastOrNull {
            it.outgoing && it.hash == hash &&
                (it.state == "awaiting" || it.state == "sending")
        } ?: return
        ackJobs.remove(message.id)?.cancel()
        update(message.id) { it.copy(state = "delivered") }
    }

    fun handleNack(from: String, missing: List<Int>) {
        val peer = peerKey(from)
        val message = _threads.value[peer]?.lastOrNull {
            it.outgoing &&
                (it.state == "awaiting" || it.state == "sending")
        } ?: return
        val sealed = synchronized(outboxLock) {
            sealedStore[message.id]
        } ?: return
        val rounds = synchronized(outboxLock) {
            repairRounds[message.id] ?: 0
        }
        if (rounds >= 2) {
            update(message.id) { it.copy(state = "failed") }
            return
        }
        synchronized(outboxLock) {
            repairRounds[message.id] = rounds + 1
        }
        val all = Knocktalk.fragmentFrames(
            sealed, message.suite ?: Knocktalk.SUITE_CHACHA)
        val wanted = missing.filter { it in all.indices }
        if (wanted.isEmpty()) return
        update(message.id) { it.copy(state = "sending") }
        synchronized(outboxLock) {
            outbox.addLast(
                OutboxItem(
                    peer, wanted.map { all[it] }, message.id))
        }
        pumpOutbox()
    }

    /** Our reassembly of the peer's message has holes: knock
     * the list back. */
    fun requestRepair(to: String, missing: List<Int>) {
        val peer = peerKey(to)
        synchronized(outboxLock) {
            outbox.addLast(
                OutboxItem(
                    peer,
                    listOf(Knocktalk.nackFrame(missing)),
                    null))
        }
        pumpOutbox()
    }

    // MARK: - relay

    /** (Re)arm the mailbox poll. Called at launch and
     * whenever the operator edits the relay settings. The
     * poll runs only while a relay is fully configured;
     * five seconds between checks is nothing on a channel
     * whose unit of time is a five-second knock frame. */
    fun refreshRelayPolling() {
        relayJob?.cancel()
        relayJob = null
        if (!KnockRelay.configured(prefs)) {
            _relayStatus.value = ""
            return
        }
        _relayStatus.value = "relay: " +
            (KnockRelay.host(prefs) ?: "") +
            " · mailbox " + KnockRelay.mailbox(prefs)
        relayJob = ioScope.launch {
            while (true) {
                pollRelay()
                delay(5000)
            }
        }
    }

    private suspend fun pollRelay() {
        if (!KnockRelay.configured(prefs)) {
            // Settings were cleared under a running poll:
            // stand down quietly.
            relayJob?.cancel()
            relayJob = null
            _relayStatus.value = ""
            return
        }
        try {
            val frames = withContext(Dispatchers.IO) {
                KnockRelay.fetchInbox(prefs)
            }
            _relayStatus.value = "relay: " +
                (KnockRelay.host(prefs) ?: "") +
                " · mailbox " + KnockRelay.mailbox(prefs)
            for (frame in frames) {
                onRelayFrame?.invoke(frame.from, frame.ports)
            }
        } catch (e: Exception) {
            _relayStatus.value =
                "relay unreachable: ${e.message ?: "error"}"
        }
    }

    /// A message picked up by brush pass (proximity BLE).
    /// Like a chirp, the medium has no acknowledgement.
    fun receiveBrush(text: String) {
        append(
            ChatMessage(
                id = java.util.UUID.randomUUID().toString(),
                peer = "brush", outgoing = false, text = text,
                whenMs = System.currentTimeMillis(),
                state = "received"))
        purge()
    }

    /// A message that arrived by light (Blink). One-way —
    /// no ACK rides a QR frame back.
    fun receiveBlink(text: String) {
        append(
            ChatMessage(
                id = java.util.UUID.randomUUID().toString(),
                peer = "blink", outgoing = false, text = text,
                whenMs = System.currentTimeMillis(),
                state = "received"))
        purge()
    }

    /// A time capsule, ground open. It arrives whenever the
    /// grinding finished — the lock set the schedule.
    fun receiveCapsule(text: String) {
        append(
            ChatMessage(
                id = java.util.UUID.randomUUID().toString(),
                peer = "capsule", outgoing = false, text = text,
                whenMs = System.currentTimeMillis(),
                state = "received"))
        purge()
        Journal.log(
            "knocktalk", "capsule",
            "a time capsule opened and was filed")
    }

    /// A message that arrived by sound (Chirp). That medium
    /// has no way to knock an ACK back, so chirps file as
    /// plain received messages in their own thread.
    fun receiveChirp(text: String) {
        append(
            ChatMessage(
                id = java.util.UUID.randomUUID().toString(),
                peer = "chirp", outgoing = false, text = text,
                whenMs = System.currentTimeMillis(),
                state = "received"))
        purge()
    }

    // MARK: - retention + persistence

    fun setRetention(hours: Double) {
        _retentionHours.value = hours
        prefs.put("knocktalkRetentionHours", hours.toString())
        purge()
    }

    /** Burn every message past the retention line, both
     * directions — a conversation is two copies of a secret. */
    fun purge() {
        val hours = _retentionHours.value
        if (hours <= 0) return
        val cutoff = System.currentTimeMillis() -
            (hours * 3600_000).toLong()
        val current = _threads.value
        var changed = false
        val next = mutableMapOf<String, List<ChatMessage>>()
        for ((peer, list) in current) {
            val kept = list.filter { it.whenMs >= cutoff }
            if (kept.size != list.size) changed = true
            if (kept.isNotEmpty()) next[peer] = kept
        }
        if (changed) {
            _threads.value = next
            save()
        }
    }

    /** Burn everything, right now — every thread, every
     * message, whatever the retention setting says. The
     * knock vault's burn macro lands here. */
    fun burnNow() {
        _threads.value = emptyMap()
        save()
        Journal.log(
            "knocktalk", "burn",
            "all threads burned on command")
    }

    fun clearThread(peer: String) {
        _threads.value = _threads.value - peer
        save()
    }

    private fun append(message: ChatMessage) {
        val current = _threads.value.toMutableMap()
        current[message.peer] =
            (current[message.peer] ?: emptyList()) + message
        _threads.value = current
        save()
    }

    private fun find(id: String): ChatMessage? =
        _threads.value.values.flatten().firstOrNull { it.id == id }

    private fun update(
        id: String, mutate: (ChatMessage) -> ChatMessage
    ) {
        val current = _threads.value.toMutableMap()
        for ((peer, list) in current) {
            val index = list.indexOfFirst { it.id == id }
            if (index < 0) continue
            val next = list.toMutableList()
            next[index] = mutate(next[index])
            current[peer] = next
            _threads.value = current
            save()
            return
        }
    }

    private val threadsFile: File
        get() = File(filesDir, "knocktalk-threads.json")

    private fun loadThreads(): Map<String, List<ChatMessage>> {
        return try {
            val root = JSONObject(threadsFile.readText())
            val out = mutableMapOf<String, List<ChatMessage>>()
            for (peer in root.keys()) {
                val array = root.getJSONArray(peer)
                out[peer] = (0 until array.length()).map { i ->
                    val o = array.getJSONObject(i)
                    ChatMessage(
                        id = o.getString("id"),
                        peer = o.getString("peer"),
                        outgoing = o.getBoolean("outgoing"),
                        text = o.getString("text"),
                        whenMs = o.getLong("when"),
                        state = o.getString("state"),
                        hash = o.optJSONArray("hash")?.let { a ->
                            (0 until a.length()).map {
                                a.getInt(it)
                            }
                        },
                        suite = if (o.has("suite")) {
                            o.getInt("suite")
                        } else {
                            null
                        })
                }
            }
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun save() {
        val snapshot = _threads.value
        ioScope.launch {
            try {
                val root = JSONObject()
                for ((peer, list) in snapshot) {
                    val array = JSONArray()
                    for (message in list) {
                        val o = JSONObject()
                        o.put("id", message.id)
                        o.put("peer", message.peer)
                        o.put("outgoing", message.outgoing)
                        o.put("text", message.text)
                        o.put("when", message.whenMs)
                        o.put("state", message.state)
                        message.hash?.let {
                            o.put("hash", JSONArray(it))
                        }
                        message.suite?.let { o.put("suite", it) }
                        array.put(o)
                    }
                    root.put(peer, array)
                }
                threadsFile.writeText(root.toString())
            } catch (_: Exception) {
            }
        }
    }

    /** One-time migration path if a v1 inbox ever exists:
     * whole-message frames become received messages in
     * per-source threads. */
    fun importLegacy(messages: List<KnockMessage>) {
        for (message in messages) {
            append(
                ChatMessage(
                    id = message.id, peer = peerKey(message.source),
                    outgoing = false, text = message.text,
                    whenMs = message.whenMs, state = "received"))
        }
    }
}
