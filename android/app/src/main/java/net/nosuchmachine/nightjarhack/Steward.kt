package net.nosuchmachine.nightjarhack

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Calendar
import java.util.Date
import java.util.Locale

/// The steward — the Kotlin mirror of the iOS Steward: the
/// watch officer above the conductor.
///
/// The conductor fires one reflex per event, faithfully and
/// without judgment. The steward holds the whole night in
/// view at once — posture, pattern, files, sense, the
/// journal's other senses — and thinks in SITUATIONS,
/// graded by confidence: a foreign nightjar-grade probe
/// from a new source is not three events, it is one visitor
/// of a recognizable kind, and how sure the steward is
/// decides how hard it answers.
///
/// It works under a charter the operator writes: a master
/// switch and a latitude. At OBSERVE it watches, assesses,
/// and files proposals. At ACT it may run its plans on the
/// perimeter, proportioned to confidence. At FULL it may
/// also approve its own drafted reflexes. It studies the
/// operator's own rulings and proposes charter amendments
/// to match; it keeps case files on the visitors who
/// matter; it watches the outcomes of its own plans and
/// grades itself in the same sealed log that grades
/// everything else. An autonomy you cannot audit would be
/// a second operator; this one is a subordinate with a
/// memory and a scorecard.
///
/// It thinks while the app is open. Its design center is
/// the shift change — every opening, it catches up on the
/// sealed log, reads the mirror, and leaves the perimeter
/// in the best posture it can justify in writing.
class Steward(
    private val prefs: Prefs,
    private val emcon: Emcon
) {
    data class Proposal(
        val id: String, val whenMs: Long,
        /** plan | rule | charter | posture | note */
        val kind: String, val title: String, val detail: String,
        /** Action ids for a plan: tighten / answer / pivot. */
        val plan: List<String> = emptyList(),
        val host: String? = null, val port: Int? = null,
        val verdict: String? = null,
        val ruleTrigger: String? = null,
        val ruleAction: String? = null,
        val prestagePersona: String? = null
    )

    data class WatchOrder(
        val id: String, val name: String,
        val host: String = "", val port: String = "",
        val verdict: String = "",
        val action: String = "tighten",
        val enabled: Boolean = true
    )

    data class Watch(
        val host: String, val situation: String,
        val whenMs: Long, val resolved: Boolean = false
    )

    data class Case(
        val id: String, val hosts: List<String>,
        val openedMs: Long, val lastActivityMs: Long,
        val entries: List<String> = emptyList(),
        val open: Boolean = true
    )

    private val _assessment = MutableStateFlow(
        "The steward has not taken a shift yet.")
    val assessment: StateFlow<String> = _assessment
    private val _mirrorLine = MutableStateFlow("")
    val mirrorLine: StateFlow<String> = _mirrorLine
    private val _proposals =
        MutableStateFlow<List<Proposal>>(emptyList())
    val proposals: StateFlow<List<Proposal>> = _proposals
    /// The one collection the section edits in place.
    private val _orders =
        MutableStateFlow<List<WatchOrder>>(emptyList())
    val orders: StateFlow<List<WatchOrder>> = _orders
    private val _cases = MutableStateFlow<List<Case>>(emptyList())
    val cases: StateFlow<List<Case>> = _cases

    private var watches: List<Watch> = emptyList()
    private var filesCache: List<ProberFile> = emptyList()
    private var filesCacheAt = 0L
    private var companyUntil = 0L

    init {
        _proposals.value = loadProposals()
        _orders.value = loadOrders()
        watches = loadWatches()
        _cases.value = loadCases()
    }

    // MARK: - charter

    val on: Boolean get() = prefs.bool("stewardOn", false)

    /** observe | act | full — what the charter allows. */
    val latitude: String
        get() = prefs.string("stewardLatitude", "observe")

    private val mayAct: Boolean
        get() = latitude == "act" || latitude == "full"

    // MARK: - persistence

    companion object {
        private const val PROPOSALS_KEY = "stewardProposals"
        private const val ORDERS_KEY = "stewardOrders"
        private const val WATCHES_KEY = "stewardWatches"
        private const val CASES_KEY = "stewardCases"
        private const val FIRED_KEY = "stewardFired"
        private const val SHIFT_KEY = "stewardLastShift"
        private const val REST_MS = 3600_000L

        fun persona(forPort: Int): String? = when (forPort) {
            22 -> "ssh"
            80, 8080 -> "http"
            1883 -> "mqtt"
            25 -> "smtp"
            else -> null
        }

        fun actionLabel(action: String): String = when (action) {
            "tighten" -> "raise the second sense"
            "answer" -> "answer in character"
            "pivot" -> "load the bench on them"
            else -> action
        }
    }

    private fun loadProposals(): List<Proposal> {
        val raw = prefs.string(PROPOSALS_KEY, "")
        if (raw.isBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                Proposal(
                    id = o.getString("id"),
                    whenMs = o.getLong("when"),
                    kind = o.getString("kind"),
                    title = o.getString("title"),
                    detail = o.getString("detail"),
                    plan = o.optJSONArray("plan")?.let { a ->
                        (0 until a.length()).map { a.getString(it) }
                    } ?: emptyList(),
                    host = o.optString("host").ifBlank { null },
                    port = if (o.has("port")) o.getInt("port")
                    else null,
                    verdict = o.optString("verdict")
                        .ifBlank { null },
                    ruleTrigger = o.optString("ruleTrigger")
                        .ifBlank { null },
                    ruleAction = o.optString("ruleAction")
                        .ifBlank { null },
                    prestagePersona = o.optString("prestagePersona")
                        .ifBlank { null })
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveProposals() {
        val array = JSONArray()
        for (p in _proposals.value) {
            val o = JSONObject()
            o.put("id", p.id)
            o.put("when", p.whenMs)
            o.put("kind", p.kind)
            o.put("title", p.title)
            o.put("detail", p.detail)
            o.put("plan", JSONArray(p.plan))
            p.host?.let { o.put("host", it) }
            p.port?.let { o.put("port", it) }
            p.verdict?.let { o.put("verdict", it) }
            p.ruleTrigger?.let { o.put("ruleTrigger", it) }
            p.ruleAction?.let { o.put("ruleAction", it) }
            p.prestagePersona?.let { o.put("prestagePersona", it) }
            array.put(o)
        }
        prefs.put(PROPOSALS_KEY, array.toString())
    }

    private fun loadOrders(): List<WatchOrder> {
        val raw = prefs.string(ORDERS_KEY, "")
        if (raw.isBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                WatchOrder(
                    id = o.getString("id"),
                    name = o.getString("name"),
                    host = o.optString("host", ""),
                    port = o.optString("port", ""),
                    verdict = o.optString("verdict", ""),
                    action = o.optString("action", "tighten"),
                    enabled = o.optBoolean("enabled", true))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveOrders() {
        val array = JSONArray()
        for (order in _orders.value) {
            val o = JSONObject()
            o.put("id", order.id)
            o.put("name", order.name)
            o.put("host", order.host)
            o.put("port", order.port)
            o.put("verdict", order.verdict)
            o.put("action", order.action)
            o.put("enabled", order.enabled)
            array.put(o)
        }
        prefs.put(ORDERS_KEY, array.toString())
    }

    fun setOrders(next: List<WatchOrder>) {
        _orders.value = next
        saveOrders()
    }

    private fun loadWatches(): List<Watch> {
        val raw = prefs.string(WATCHES_KEY, "")
        if (raw.isBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                Watch(
                    host = o.getString("host"),
                    situation = o.getString("situation"),
                    whenMs = o.getLong("when"),
                    resolved = o.optBoolean("resolved", false))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveWatches() {
        val array = JSONArray()
        for (watch in watches) {
            val o = JSONObject()
            o.put("host", watch.host)
            o.put("situation", watch.situation)
            o.put("when", watch.whenMs)
            o.put("resolved", watch.resolved)
            array.put(o)
        }
        prefs.put(WATCHES_KEY, array.toString())
    }

    private fun loadCases(): List<Case> {
        val raw = prefs.string(CASES_KEY, "")
        if (raw.isBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                Case(
                    id = o.getString("id"),
                    hosts = o.getJSONArray("hosts").let { a ->
                        (0 until a.length()).map { a.getString(it) }
                    },
                    openedMs = o.getLong("opened"),
                    lastActivityMs = o.getLong("lastActivity"),
                    entries = o.optJSONArray("entries")?.let { a ->
                        (0 until a.length()).map { a.getString(it) }
                    } ?: emptyList(),
                    open = o.optBoolean("open", true))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveCases() {
        val array = JSONArray()
        for (entry in _cases.value) {
            val o = JSONObject()
            o.put("id", entry.id)
            o.put("hosts", JSONArray(entry.hosts))
            o.put("opened", entry.openedMs)
            o.put("lastActivity", entry.lastActivityMs)
            o.put("entries", JSONArray(entry.entries))
            o.put("open", entry.open)
            array.put(o)
        }
        prefs.put(CASES_KEY, array.toString())
    }

    private fun resting(key: String, restMs: Long = REST_MS): Boolean {
        val raw = prefs.string(FIRED_KEY, "")
        if (raw.isBlank()) return false
        val last = try {
            JSONObject(raw).optLong(key, 0)
        } catch (_: Exception) {
            0L
        }
        if (last <= 0) return false
        return System.currentTimeMillis() - last < restMs
    }

    private fun markFired(key: String) {
        val obj = try {
            JSONObject(prefs.string(FIRED_KEY, "").ifBlank { "{}" })
        } catch (_: Exception) {
            JSONObject()
        }
        obj.put(key, System.currentTimeMillis())
        prefs.put(FIRED_KEY, obj.toString())
    }

    // MARK: - the world in one view

    private fun files(): List<ProberFile> {
        if (System.currentTimeMillis() - filesCacheAt > 60_000) {
            filesCache = ProberFiles.build(emcon.events.value)
            filesCacheAt = System.currentTimeMillis()
        }
        return filesCache
    }

    /// The current read of the night, in sentences an
    /// operator can hold.
    fun refresh() {
        val parts = mutableListOf<String>()
        parts.add(
            if (emcon.active.value) {
                if (emcon.isAway) {
                    "EMCON is up, away from home turf."
                } else {
                    "EMCON is up on home turf."
                }
            } else {
                "EMCON is standing down."
            })
        if (emcon.senseActive) {
            parts.add("The second sense is raised.")
        }
        if (companyUntil > System.currentTimeMillis()) {
            parts.add(
                "Company: a paired operator's flare was in " +
                    "range recently.")
        }
        if (emcon.hometurfReady) {
            val n = emcon.hometurfNotes.value.size
            parts.add(
                if (n == 0) {
                    "The home pattern holds — nothing off it."
                } else {
                    "$n deviation(s) off the home pattern tonight."
                })
        } else if (emcon.homeSubnet != null) {
            parts.add(
                "The home pattern is still learning " +
                    "(${emcon.hometurf.value.nights} of 3 nights).")
        }
        val changed = files().count { ProberFiles.changed(it, prefs) }
        if (changed > 0) {
            parts.add("$changed prober file(s) have unreviewed changes.")
        }
        val openCases = _cases.value.count { it.open }
        if (openCases > 0) {
            parts.add("$openCases case file(s) open.")
        }
        if (_proposals.value.isNotEmpty()) {
            parts.add(
                "${_proposals.value.size} proposal(s) await " +
                    "your judgment.")
        }
        _assessment.value = parts.joinToString(" ")
        _mirrorLine.value = composeMirror()
    }

    /// The wire's-eye view: how the house presents to
    /// whoever is looking at it.
    private fun composeMirror(): String {
        val parts = mutableListOf<String>()
        parts.add(
            if (emcon.active.value) {
                "EMCON is up and the tripwire is listening"
            } else {
                "EMCON is down"
            })
        val doors = emcon.events.value.map { it.port }.toSet().size
        if (doors > 0) {
            parts.add("$doors door(s) have been tried from the wire")
        }
        emcon.canary?.runningPersona?.let { persona ->
            parts.add("the canary is answering as ${persona.uppercase()}")
        }
        return "From the wire: " + parts.joinToString("; ") + "."
    }

    // MARK: - judgment

    private data class Confidence(
        val points: Int, val band: String, val factors: List<String>
    )

    /// Confidence, scored from the evidence itself — every
    /// factor named, so the reasoning can be audited.
    private fun confidence(
        nightjarGrade: Boolean, file: ProberFile?,
        newSource: Boolean, offPattern: Boolean
    ): Confidence {
        var points = 0
        val factors = mutableListOf<String>()
        if (nightjarGrade) {
            points += 40
            factors.add("a nightjar-grade first word")
        }
        if (file != null && file.drops > 0) {
            points += 35
            factors.add("has taken ${file.drops} honeydrop(s) before")
        }
        if (newSource) {
            points += 15
            factors.add("no file history")
        }
        if (offPattern) {
            points += 15
            factors.add("off the learned pattern")
        }
        if (file != null) {
            val total = file.ports.values.sum()
            if (total >= 5) {
                points += 10
                factors.add(
                    "a repeat visitor ($total knocks on file)")
            }
        }
        if (emcon.senseActive) {
            points += 10
            factors.add("the sense is already up")
        }
        val band = when {
            points >= 65 -> "high"
            points >= 35 -> "medium"
            else -> "low"
        }
        return Confidence(points, band, factors)
    }

    // MARK: - situations

    /// Fed every knock the funnel sees, after the conductor.
    fun onKnock(
        source: String, port: Int, proto: String,
        verdict: String, mine: Boolean
    ) {
        if (!on || mine) return
        val host = source.split(" ").firstOrNull() ?: source
        val file = files().firstOrNull { it.host == host }
        if (file?.isSelf == true) return

        // Outcome watch: a visitor a plan was executed
        // against has come back inside the day.
        resolveWatches(host, "returned within the day — still interested")

        // The operator's watch orders.
        for (order in _orders.value) {
            if (!order.enabled) continue
            val hostMatch = order.host.isEmpty() ||
                host.contains(order.host)
            val portMatch = order.port.isEmpty() ||
                order.port.toIntOrNull() == port
            val verdictMatch = order.verdict.isEmpty() ||
                verdict.lowercase()
                    .contains(order.verdict.lowercase())
            if (!hostMatch || !portMatch || !verdictMatch) continue
            if (resting("order:${order.id}", 1800_000)) continue
            markFired("order:${order.id}")
            respond(
                situation = "watch order: ${order.name}",
                evidence = "$host on port $port spoke " +
                    "“$verdict” — the operator's own order " +
                    "covers this",
                plan = listOf(order.action),
                confidence = Confidence(
                    100, "high",
                    listOf("the operator wrote this order")),
                host = host, port = port, verdict = verdict,
                file = file)
        }

        val nightjarGrade = verdict.startsWith("nightjar-hack probe:")
        val rows = emcon.events.value.filter {
            (it.source.split(" ").firstOrNull() ?: it.source) == host
        }
        val newSource = rows.size <= 1
        val offPattern = emcon.hometurfNotes.value.any {
            it.contains(host) || it.contains("port $port")
        }
        val score = confidence(nightjarGrade, file, newSource, offPattern)

        // The taker returns.
        if (file != null && file.drops > 0 && !resting("taker")) {
            markFired("taker")
            respond(
                situation = "the taker returns",
                evidence = "$host has taken ${file.drops} " +
                    "honeydrop(s) before and is knocking again " +
                    "on port $port",
                plan = listOf("pivot"), confidence = score,
                host = host, port = port, verdict = verdict,
                file = file)
        }

        // A colleague-grade prober.
        if (nightjarGrade && proto == "TCP" &&
            (newSource || offPattern) && !resting("colleague")) {
            markFired("colleague")
            respond(
                situation = "a colleague-grade prober",
                evidence = "$host spoke $verdict on port $port " +
                    "— nightjar-grade tooling, " +
                    if (newSource) {
                        "a source never seen before"
                    } else {
                        "at an off-pattern door"
                    },
                plan = listOf("tighten", "answer", "pivot"),
                confidence = score,
                host = host, port = port, verdict = verdict,
                file = file)
            suggestTakerRule()
        }

        // A pattern-break cluster.
        val notes = emcon.hometurfNotes.value
        if (notes.size >= 3 && !resting("cluster")) {
            markFired("cluster")
            val extra = minOf(notes.size - 3, 3)
            respond(
                situation = "a pattern-break cluster",
                evidence = "${notes.size} deviations off the " +
                    "learned home pattern tonight",
                plan = listOf("tighten"),
                confidence = Confidence(
                    35 + extra * 10,
                    if (extra >= 3) "high" else "medium",
                    listOf("${notes.size} deviations tonight")),
                host = null, port = null, verdict = null, file = null)
        }

        anticipate(file, host, port)
        refresh()
    }

    /// Anticipation: a filed visitor's own history is a
    /// sequence. When they knock the door before a door they
    /// favor, pre-stage the canary at the predicted door,
    /// through the same hand-off an answer uses.
    private fun anticipate(
        file: ProberFile?, host: String, knockedPort: Int
    ) {
        if (file == null) return
        val total = file.ports.values.sum()
        if (!(file.drops > 0 || total >= 3)) return
        if (resting("anticipation:$host", 1800_000)) return
        val sequence = file.portsByTraffic.map { it.first }
        val index = sequence.indexOf(knockedPort)
        if (index < 0 || index + 1 >= sequence.size) return
        val next = sequence[index + 1]
        val persona = persona(next) ?: return
        markFired("anticipation:$host")
        val evidence = "$host's own sequence — " +
            sequence.joinToString(" → ") +
            " — says port $next comes after $knockedPort"
        if (mayAct) {
            emcon.prestageCanary(next, persona, host)
            Journal.log(
                "steward", "plan",
                "ANTICIPATION: $evidence. The $persona canary " +
                    "is pre-staged on port $next under " +
                    "latitude $latitude.")
            fileCase("anticipation", host, evidence, file)
        } else {
            _proposals.value = listOf(
                Proposal(
                    id = java.util.UUID.randomUUID().toString(),
                    whenMs = System.currentTimeMillis(),
                    kind = "plan", title = "Anticipation: $host",
                    detail = evidence + ". Proposed: pre-stage " +
                        "the $persona canary on port $next. " +
                        "Held under latitude observe.",
                    host = host, port = next,
                    prestagePersona = persona)) + _proposals.value
            saveProposals()
            Journal.log(
                "steward", "observe",
                "ANTICIPATION: $evidence. Pre-staging the " +
                    "$persona canary on port $next proposed " +
                    "and held for the operator.")
        }
    }

    // MARK: - answering a situation

    /// A situation, answered in proportion to confidence.
    private fun respond(
        situation: String, evidence: String, plan: List<String>,
        confidence: Confidence, host: String?, port: Int?,
        verdict: String?, file: ProberFile?
    ) {
        val scoreText = "confidence ${confidence.band} " +
            "(${confidence.points}): " +
            if (confidence.factors.isEmpty()) {
                "no strong factors"
            } else {
                confidence.factors.joinToString(", ")
            }
        val planText = plan.joinToString(" + ") { actionLabel(it) }
        if (host != null) {
            fileCase(
                situation, host,
                evidence + " [" + scoreText + "]", file)
        }
        if (mayAct) {
            val effective = when (confidence.band) {
                "high" -> plan
                "medium" -> plan.take(1)
                else -> emptyList()
            }
            if (effective.isEmpty()) {
                Journal.log(
                    "steward", "observe",
                    "SITUATION $situation: $evidence. " +
                        "$scoreText. Held from acting on " +
                        "confidence alone — the plan would " +
                        "have been $planText.")
                return
            }
            val done = mutableListOf<String>()
            for (action in effective) {
                if (perform(action, host, port, verdict)) {
                    done.add(actionLabel(action))
                }
            }
            Journal.log(
                "steward", "plan",
                "SITUATION $situation: $evidence. $scoreText. " +
                    "Plan: $planText. Executed under latitude " +
                    "$latitude at this confidence: " +
                    if (done.isEmpty()) {
                        "nothing could be carried out"
                    } else {
                        done.joinToString(", ")
                    } + ".")
            if (host != null) {
                watches = watches + Watch(
                    host, situation, System.currentTimeMillis())
                saveWatches()
            }
        } else {
            _proposals.value = listOf(
                Proposal(
                    id = java.util.UUID.randomUUID().toString(),
                    whenMs = System.currentTimeMillis(),
                    kind = "plan", title = situation,
                    detail = evidence + " " + scoreText +
                        ". Proposed: " + planText +
                        ". Held under latitude observe.",
                    plan = plan, host = host, port = port,
                    verdict = verdict)) + _proposals.value
            saveProposals()
            Journal.log(
                "steward", "observe",
                "SITUATION $situation: $evidence. $scoreText. " +
                    "Plan proposed ($planText) and held for " +
                    "the operator — latitude is observe.")
        }
        refresh()
    }

    /// When a colleague-grade prober appears and no reflex
    /// yet loads the bench on a taken drop, the steward
    /// drafts one. At FULL latitude it approves its own
    /// draft — and journals that it did.
    private fun suggestTakerRule() {
        val covered = Conductor.loadRules(prefs).any {
            it.trigger == "honeydrop" && it.action == "pivotRecon"
        }
        val alreadyFiled = _proposals.value.any {
            it.kind == "rule" && it.ruleTrigger == "honeydrop"
        }
        if (covered || alreadyFiled) return
        val rule = Conductor.Rule(
            id = java.util.UUID.randomUUID().toString(),
            name = "A honeydrop is taken → Load the bench on them",
            trigger = "honeydrop", action = "pivotRecon",
            enabled = true)
        if (latitude == "full") {
            Conductor.saveRules(
                prefs, Conductor.loadRules(prefs) + rule)
            Journal.log(
                "steward", "plan",
                "The steward approved its own drafted reflex " +
                    "under latitude full: honeydrop → load " +
                    "the bench.")
        } else {
            _proposals.value = listOf(
                Proposal(
                    id = java.util.UUID.randomUUID().toString(),
                    whenMs = System.currentTimeMillis(),
                    kind = "rule",
                    title = "Drafted reflex: the taker rule",
                    detail = "Colleague-grade probing has begun " +
                        "and no reflex loads the bench when a " +
                        "honeydrop is taken. Approving adds it " +
                        "to the conductor.",
                    ruleTrigger = "honeydrop",
                    ruleAction = "pivotRecon")) + _proposals.value
            saveProposals()
            Journal.log(
                "steward", "observe",
                "The steward drafted a reflex (honeydrop → " +
                    "load the bench) and filed it for approval.")
        }
        refresh()
    }

    /// Carry out one plan action through the organs. False
    /// when the action had nothing to act on.
    private fun perform(
        action: String, host: String?, port: Int?, verdict: String?
    ): Boolean {
        return when (action) {
            "tighten" -> {
                emcon.raiseSense("the steward's plan")
                true
            }
            "answer" -> {
                if (host == null || port == null ||
                    verdict == null) {
                    false
                } else {
                    emcon.escalateNow(host, port, verdict)
                    true
                }
            }
            "pivot" -> {
                val sink = emcon.pivotSink
                if (sink == null || host == null || port == null) {
                    false
                } else {
                    sink(host, port)
                    true
                }
            }
            else -> false
        }
    }

    // MARK: - case files

    /// Situations accumulate into cases: one file per
    /// visitor — merged across addresses the same-hands
    /// correlation links — holding every situation, plan,
    /// and outcome in the order they happened.
    private fun fileCase(
        situation: String, host: String, evidence: String,
        file: ProberFile?
    ) {
        val hosts = mutableSetOf(host)
        if (file != null) {
            hosts.addAll(file.links.map { it.host })
        }
        val stamp = SimpleDateFormat("HH:mm", Locale.US)
            .format(Date())
        val entry = "$stamp — $situation: $evidence"
        val current = _cases.value.toMutableList()
        val index = current.indexOfFirst {
            it.open && it.hosts.toSet().intersect(hosts).isNotEmpty()
        }
        if (index >= 0) {
            val existing = current[index]
            var entries = existing.entries + entry
            if (entries.size > 50) {
                entries = entries.takeLast(50)
            }
            current[index] = existing.copy(
                hosts = (existing.hosts.toSet() + hosts).sorted(),
                entries = entries,
                lastActivityMs = System.currentTimeMillis())
        } else {
            current.add(
                0, Case(
                    id = java.util.UUID.randomUUID().toString(),
                    hosts = hosts.sorted(),
                    openedMs = System.currentTimeMillis(),
                    lastActivityMs = System.currentTimeMillis(),
                    entries = listOf(entry)))
            Journal.log(
                "steward", "case",
                "case opened on $host — $situation")
            if (current.size > 20) {
                _cases.value = current.take(20)
                saveCases()
                return
            }
        }
        _cases.value = current
        saveCases()
    }

    fun closeCase(entry: Case) {
        val current = _cases.value.toMutableList()
        val index = current.indexOfFirst { it.id == entry.id }
        if (index < 0) return
        current[index] = current[index].copy(open = false)
        _cases.value = current
        saveCases()
        Journal.log(
            "steward", "case",
            "case closed on " +
                (entry.hosts.firstOrNull() ?: "unknown") +
                " by the operator")
    }

    // MARK: - self-grading

    /// Resolve every open outcome watch on a host.
    private fun resolveWatches(host: String, outcome: String) {
        var changed = false
        watches = watches.map { watch ->
            if (!watch.resolved && watch.host == host) {
                changed = true
                Journal.log(
                    "steward", "grade",
                    "plan record — ${watch.situation} on " +
                        "$host: $outcome.")
                watch.copy(resolved = true)
            } else {
                watch
            }
        }
        if (changed) saveWatches()
    }

    // MARK: - all its senses

    /// The journal's event feed: everything the instrument
    /// writes, the steward also hears.
    fun consume(event: NightEvent) {
        if (!on) return
        when (event.module to event.kind) {
            "dossier" to "drift" -> {
                val host = event.text.split(" ").firstOrNull {
                    it.contains(".") && it.all { c ->
                        c.isDigit() || c == '.'
                    }
                } ?: "a watched address"
                val title = "Dossier drift: $host"
                if (_proposals.value.any { it.title == title }) {
                    return
                }
                _proposals.value = listOf(
                    Proposal(
                        id = java.util.UUID.randomUUID().toString(),
                        whenMs = System.currentTimeMillis(),
                        kind = "note", title = title,
                        detail = event.text + " Filed from the " +
                            "journal the moment it was written — " +
                            "re-baseline it in the dossier if " +
                            "the change is explained, or load " +
                            "the bench on it if it is not.")) +
                    _proposals.value
                saveProposals()
                Journal.log(
                    "steward", "observe",
                    "The steward noted dossier drift on $host " +
                        "and filed it.")
            }
            "listen" to "flare" -> {
                companyUntil =
                    System.currentTimeMillis() + 600_000
            }
            "canary" to "honeydrop" -> {
                // "drop taken by host:port — note"
                val peer = event.text
                    .replace("drop taken by ", "")
                    .split(" ").firstOrNull() ?: ""
                val host = if (":" in peer) {
                    peer.substringBeforeLast(":")
                } else {
                    peer
                }
                if (host.isNotEmpty()) {
                    resolveWatches(
                        host,
                        "confirmed — the visitor bit the canary too")
                    val current = _cases.value.toMutableList()
                    val index = current.indexOfFirst {
                        it.open && host in it.hosts
                    }
                    if (index >= 0) {
                        current[index] = current[index].copy(
                            entries = current[index].entries +
                                "took the canary's drop — ${event.text}",
                            lastActivityMs =
                                System.currentTimeMillis())
                        _cases.value = current
                        saveCases()
                    }
                }
            }
            else -> {}
        }
    }

    // MARK: - proposals, in the operator's hands

    fun enact(proposal: Proposal) {
        when (proposal.kind) {
            "rule" -> {
                val trigger = proposal.ruleTrigger
                val action = proposal.ruleAction
                if (trigger != null && action != null) {
                    val rule = Conductor.Rule(
                        id = java.util.UUID.randomUUID().toString(),
                        name = Conductor.triggerLabel(trigger) +
                            " → " + Conductor.actionLabel(action),
                        trigger = trigger, action = action,
                        enabled = true)
                    Conductor.saveRules(
                        prefs, Conductor.loadRules(prefs) + rule)
                    Journal.log(
                        "steward", "plan",
                        "The operator approved the steward's " +
                            "drafted reflex: ${proposal.title}.")
                }
            }
            "charter" -> {
                prefs.put("stewardLatitude", "act")
                Journal.log(
                    "steward", "plan",
                    "The operator amended the charter: " +
                        "${proposal.title}. Latitude is now act.")
            }
            "posture" -> {
                if (!emcon.active.value) emcon.activate()
                Journal.log(
                    "steward", "plan",
                    "The operator enacted a held posture " +
                        "proposal: ${proposal.title}.")
            }
            "plan" -> {
                val persona = proposal.prestagePersona
                val port = proposal.port
                val host = proposal.host
                if (persona != null && port != null && host != null) {
                    emcon.prestageCanary(port, persona, host)
                    Journal.log(
                        "steward", "plan",
                        "The operator enacted an anticipation " +
                            "— the $persona canary is pre-staged " +
                            "on port $port for $host.")
                } else {
                    val done = mutableListOf<String>()
                    for (action in proposal.plan) {
                        if (perform(
                                action, proposal.host,
                                proposal.port, proposal.verdict)) {
                            done.add(actionLabel(action))
                        }
                    }
                    Journal.log(
                        "steward", "plan",
                        "The operator enacted a held plan — " +
                            "${proposal.title}: " +
                            if (done.isEmpty()) {
                                "nothing could be carried out"
                            } else {
                                done.joinToString(", ")
                            } + ".")
                    if (host != null) {
                        watches = watches + Watch(
                            host, proposal.title,
                            System.currentTimeMillis())
                        saveWatches()
                    }
                }
            }
            else -> {}
        }
        _proposals.value = _proposals.value.filter {
            it.id != proposal.id
        }
        saveProposals()
        refresh()
    }

    fun dismissProposal(proposal: Proposal) {
        _proposals.value = _proposals.value.filter {
            it.id != proposal.id
        }
        saveProposals()
        Journal.log(
            "steward", "observe",
            "The operator dismissed a proposal: ${proposal.title}.")
    }

    // MARK: - the shift change

    /// Called at launch and at every return to the
    /// foreground: the catch-up. What accumulated in the
    /// sealed log since the last shift is counted and
    /// reported; open outcome watches past their day are
    /// graded quiet; the operator's own patterns are
    /// studied and returned as charter proposals; the last
    /// maneuvers grade is checked for staleness; and the
    /// mirror is read aloud into the log.
    fun shiftChange() {
        if (!on) return
        val last = prefs.string(SHIFT_KEY, "0").toLongOrNull() ?: 0
        prefs.put(
            SHIFT_KEY, System.currentTimeMillis().toString())
        // Grade the watches whose day has run out.
        var gradedQuiet = false
        watches = watches.map { watch ->
            if (!watch.resolved &&
                System.currentTimeMillis() - watch.whenMs >
                24 * 3600_000) {
                gradedQuiet = true
                Journal.log(
                    "steward", "grade",
                    "plan record — ${watch.situation} on " +
                        "${watch.host}: no return in a day — " +
                        "quiet since the plan.")
                watch.copy(resolved = true)
            } else {
                watch
            }
        }
        if (gradedQuiet) saveWatches()
        if (last > 0) {
            val since = Instant.ofEpochMilli(last)
            val events = Journal.events(limit = 1000).filter {
                eventInstant(it) > since
            }
            fun count(module: String, kind: String): Int =
                events.count {
                    it.module == module && it.kind == kind
                }
            val parts = mutableListOf<String>()
            val knocks = count("emcon", "knock")
            if (knocks > 0) parts.add("$knocks knock(s)")
            val drops = count("canary", "honeydrop")
            if (drops > 0) parts.add("$drops honeydrop(s) TAKEN")
            val deviations = count("emcon", "hometurf")
            if (deviations > 0) parts.add("$deviations deviation(s)")
            val plans = count("steward", "plan")
            if (plans > 0) parts.add("$plans steward action(s)")
            if (parts.isNotEmpty()) {
                val line = "While you were gone: " +
                    parts.joinToString(", ") + "."
                _assessment.value = line
                Journal.log("steward", "shift", line)
            }
            val mirror = composeMirror()
            Journal.log("steward", "mirror", mirror)
            // Maneuvers cadence.
            val all = Journal.events(limit = 1000)
            val lastManeuvers = all
                .filter {
                    it.module == "emcon" && it.kind == "maneuvers"
                }
                .map { eventInstant(it) }
                .maxOrNull()
            val stale = lastManeuvers == null ||
                System.currentTimeMillis() -
                lastManeuvers.toEpochMilli() > 24 * 3600_000
            if (stale && _proposals.value.none {
                    it.kind == "note" &&
                        it.title.startsWith("Night maneuvers")
                }) {
                _proposals.value = listOf(
                    Proposal(
                        id = java.util.UUID.randomUUID().toString(),
                        whenMs = System.currentTimeMillis(),
                        kind = "note",
                        title = "Night maneuvers are stale",
                        detail = "The last graded self-test is " +
                            "over a day old (or never ran). The " +
                            "maneuvers live in the EMCON tab " +
                            "when you want them.")) + _proposals.value
                saveProposals()
            }
            studyOperator(all)
        }
        refresh()
    }

    private fun eventInstant(event: NightEvent): Instant =
        try {
            Instant.parse(event.`when`)
        } catch (_: Exception) {
            Instant.EPOCH
        }

    /// The operator is evidence too. Two studies, both
    /// returned as proposals and never imposed: rulings,
    /// and rhythm — the hour EMCON usually rises.
    private fun studyOperator(all: List<NightEvent>) {
        if (latitude == "observe") {
            val enacted = mutableMapOf<String, Int>()
            val dismissed = mutableMapOf<String, Int>()
            for (event in all) {
                if (event.module != "steward") continue
                if (event.text.startsWith(
                        "The operator enacted a held plan — ")) {
                    val title = event.text
                        .replace(
                            "The operator enacted a held plan — ",
                            "")
                        .split(":").firstOrNull() ?: ""
                    if (title.isNotEmpty()) {
                        enacted[title] = (enacted[title] ?: 0) + 1
                    }
                }
                if (event.text.startsWith(
                        "The operator dismissed a proposal: ")) {
                    val title = event.text
                        .replace(
                            "The operator dismissed a proposal: ",
                            "")
                        .split(".").firstOrNull() ?: ""
                    if (title.isNotEmpty()) {
                        dismissed[title] = (dismissed[title] ?: 0) + 1
                    }
                }
            }
            for ((situation, count) in enacted) {
                if (count < 3) continue
                if ((dismissed[situation] ?: 0) != 0) continue
                val title = "Charter amendment: trust the " +
                    "$situation call"
                if (_proposals.value.any { it.title == title }) {
                    continue
                }
                _proposals.value = listOf(
                    Proposal(
                        id = java.util.UUID.randomUUID().toString(),
                        whenMs = System.currentTimeMillis(),
                        kind = "charter", title = title,
                        detail = "You have enacted the " +
                            "steward's held plan for " +
                            "“$situation” $count times and never " +
                            "dismissed one. Amending the charter " +
                            "to Act lets it run that judgment " +
                            "without waiting on you — every act " +
                            "still journaled, still graded.")) +
                    _proposals.value
                saveProposals()
                Journal.log(
                    "steward", "observe",
                    "The steward studied the rulings and " +
                        "proposed a charter amendment: trust " +
                        "the $situation call.")
            }
        }
        // Rhythm: the usual posture hour.
        val risings = all.filter {
            it.module == "emcon" && it.kind == "posture" &&
                it.text.startsWith("EMCON active")
        }
        if (risings.size < 3 || emcon.active.value) return
        val hours = mutableMapOf<Int, Int>()
        for (event in risings) {
            val calendar = Calendar.getInstance()
            calendar.time = Date.from(eventInstant(event))
            val hour = calendar.get(Calendar.HOUR_OF_DAY)
            hours[hour] = (hours[hour] ?: 0) + 1
        }
        val modal = hours.maxByOrNull { it.value }?.key ?: return
        val nowHour = Calendar.getInstance()
            .get(Calendar.HOUR_OF_DAY)
        if (nowHour != modal) return
        if (_proposals.value.any { it.kind == "posture" }) return
        if (latitude == "full") {
            emcon.activate()
            Journal.log(
                "steward", "plan",
                "The steward raised EMCON at the operator's " +
                    "usual hour ($modal:00) under latitude " +
                    "full — learned from ${risings.size} " +
                    "risings on record.")
        } else if (!resting("postureHour", 12 * 3600_000)) {
            markFired("postureHour")
            _proposals.value = listOf(
                Proposal(
                    id = java.util.UUID.randomUUID().toString(),
                    whenMs = System.currentTimeMillis(),
                    kind = "posture",
                    title = "Your usual hour: raise EMCON",
                    detail = "EMCON has risen at $modal:00 " +
                        "more than any other hour " +
                        "(${risings.size} risings on record) " +
                        "and it is down now. Enacting raises it.")) +
                _proposals.value
            saveProposals()
            Journal.log(
                "steward", "observe",
                "The steward noticed the operator's usual " +
                    "posture hour ($modal:00) and proposed " +
                    "raising EMCON.")
        }
    }
}
