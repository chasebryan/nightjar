package net.nosuchmachine.nightjarhack

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// A dossier for the other side of the wire: everyone who has
/// ever knocked on this phone, assembled from the tripwire
/// log and the canary's journal — the Kotlin mirror of the
/// iOS ProberFiles. The instrument already builds dossiers
/// for devices it finds (Scan tab); prober files are the
/// same courtesy extended to devices that found IT.
///
/// Everything here is testimony the phone itself collected:
/// when they came, which doors they tried, what their first
/// words said they were speaking — and whether they ever
/// took a honeydrop. Nothing is inferred beyond the record.
data class ProberFile(
    val host: String,
    var knocks: Int = 0,
    var firstSeenMs: Long,
    var lastSeenMs: Long,
    /** Port -> folded knock count. */
    var ports: Map<Int, Int> = emptyMap(),
    /** Distinct first-word verdicts, in the order first heard. */
    var verdicts: List<String> = emptyList(),
    /** Honeydrops this source has taken (from the journal). */
    var drops: Int = 0,
    /** First-words byte prefixes (hex), one trait family for
     * the same-hands correlation. */
    var bytePrefixes: Set<String> = emptySet(),
    /** This source is the phone itself — own addresses never
     * take part in correlation. */
    var isSelf: Boolean = false,
    /** Same-hands candidates, with the shared traits spelled
     * out. A labeled suspicion, never an identification. */
    var links: List<Link> = emptyList()
) {
    data class Link(val host: String, val shared: List<String>)

    val id: String get() = host

    /** The habit set correlation runs over. */
    val traits: Set<String>
        get() {
            val out = mutableSetOf<String>()
            out.addAll(ports.keys.map { "port:$it" })
            out.addAll(verdicts.map { "word:$it" })
            out.addAll(bytePrefixes.map { "bytes:$it" })
            return out
        }

    val portsByTraffic: List<Pair<Int, Int>>
        get() = ports.entries
            .sortedByDescending { it.value }
            .map { it.key to it.value }

    /** The port they knock most — the natural knock-back aim. */
    val favoritePort: Int? get() = portsByTraffic.firstOrNull()?.first

    /** The file as shareable text, in the dossier's voice. */
    val text: String
        get() {
            val fmt = SimpleDateFormat(
                "MMM d, yyyy, h:mm a", Locale.US)
            val out = StringBuilder()
            out.append("Prober file — $host\n")
            out.append(
                "First seen ${fmt.format(Date(firstSeenMs))}; " +
                    "last seen ${fmt.format(Date(lastSeenMs))}.\n")
            out.append(
                "$knocks knock(s) across ${ports.size} port(s): ")
            out.append(
                portsByTraffic.joinToString(", ") {
                    "${it.first}×${it.second}"
                })
            out.append("\n")
            if (verdicts.isNotEmpty()) {
                out.append("First words heard:\n")
                for (v in verdicts) out.append("  · $v\n")
            }
            if (drops > 0) {
                out.append("Took $drops honeydrop(s).\n")
            }
            out.append(
                "\nAssembled by nightjar-hack from its own " +
                    "tripwire log and journal — testimony, not " +
                    "attribution: an address is a claim about a " +
                    "network, not an identity.")
            return out.toString()
        }

    companion object {
        fun traitLabel(trait: String): String {
            if (trait.startsWith("port:")) {
                return "knocked port ${trait.drop(5)}"
            }
            if (trait.startsWith("word:")) {
                return "spoke “${trait.drop(5)}”"
            }
            if (trait.startsWith("bytes:")) {
                return "first words began ${trait.drop(6)}…"
            }
            return trait
        }
    }
}

object ProberFiles {
    /** Build every file from the retained tripwire events
     * and the journal's honeydrop lines. The tripwire log
     * is capped (200 events), so a file covers what the
     * log still holds — the copy in the UI says so. */
    fun build(events: List<Emcon.TripEvent>): List<ProberFile> {
        val byHost = mutableMapOf<String, ProberFile>()
        for (event in events) {
            val host = event.source.split(" ").firstOrNull()
                ?: event.source
            if (host.isEmpty()) continue
            val file = byHost[host] ?: ProberFile(
                host = host, firstSeenMs = event.whenMs,
                lastSeenMs = event.whenMs)
            val n = maxOf(1, event.repeatCount)
            file.knocks += n
            file.firstSeenMs = minOf(file.firstSeenMs, event.whenMs)
            file.lastSeenMs = maxOf(file.lastSeenMs, event.whenMs)
            file.ports = file.ports +
                (event.port to ((file.ports[event.port] ?: 0) + n))
            if (event.verdict !in file.verdicts) {
                file.verdicts = file.verdicts + event.verdict
            }
            val hex = event.bytesHex
            if (hex != null && hex.length >= 8) {
                file.bytePrefixes =
                    file.bytePrefixes + hex.substring(0, 8)
            }
            if (event.source.contains("(this device)")) {
                file.isSelf = true
            }
            byHost[host] = file
        }
        // Honeydrop takes are journal lines naming the
        // taker's endpoint as "host:port" — anchor on the
        // colon so a short address can't match inside a
        // longer one.
        for (line in Journal.events(limit = 400)) {
            if (line.module != "canary" || line.kind != "honeydrop") {
                continue
            }
            for (host in byHost.keys.toList()) {
                if (line.text.contains("$host:")) {
                    byHost[host]?.let { it.drops += 1 }
                }
            }
        }
        val files = byHost.values
            .sortedByDescending { it.lastSeenMs }
            .toMutableList()
        correlate(files)
        return files
    }

    /// Same hands: two addresses whose habit sets overlap by
    /// at least half the smaller set, with at least three
    /// shared traits, are linked — in both directions, with
    /// the evidence attached. Own addresses never correlate
    /// (the phone answering itself is not a mystery).
    private fun correlate(files: MutableList<ProberFile>) {
        for (i in files.indices) {
            if (files[i].isSelf) continue
            for (j in files.indices) {
                if (j == i || files[j].isSelf) continue
                val mine = files[i].traits
                val theirs = files[j].traits
                val shared = mine.intersect(theirs)
                val smaller = minOf(mine.size, theirs.size)
                if (smaller <= 0 || shared.size < 3) continue
                if (shared.size.toDouble() / smaller < 0.5) continue
                files[i] = files[i].copy(
                    links = files[i].links + ProberFile.Link(
                        files[j].host,
                        shared.sorted().map {
                            ProberFile.traitLabel(it)
                        }))
            }
        }
    }

    // "Changed since you last looked": the last-seen stamp a
    // file carried when its detail was last opened, per host.
    private fun seenKey(host: String) = "proberFileSeen.$host"

    fun changed(file: ProberFile, prefs: Prefs): Boolean {
        val seen = prefs.string(seenKey(file.host), "0")
            .toLongOrNull() ?: 0
        return file.lastSeenMs > seen
    }

    fun markSeen(file: ProberFile, prefs: Prefs) {
        prefs.put(seenKey(file.host), file.lastSeenMs.toString())
    }
}
