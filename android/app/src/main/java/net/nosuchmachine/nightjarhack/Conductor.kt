package net.nosuchmachine.nightjarhack

import org.json.JSONArray
import org.json.JSONObject

/// The conductor — the Kotlin mirror of the iOS Conductor.
/// Reflexes the operator arms once, fired without them.
/// Everything in the instrument already knows how to act —
/// the canary can rise, Serve can open, the bench can load,
/// threads can burn — but until now each waited for a tap.
/// A rule is a trigger on the wire paired with one of those
/// actions; the conductor evaluates rules where the events
/// already flow: the tripwire funnel, the knock vault, and
/// the honeydrop choke.
///
/// Discipline: a master switch, a five-minute rest between
/// firings of the same rule, and every firing journaled —
/// a reflex that acts in the dark and leaves no line in the
/// sealed log would be a second operator, and there is only
/// one operator. Actions that need what the moment doesn't
/// have degrade to the journal line alone. And no reflex
/// ever fires the bench: loading Recon is an action,
/// pulling its trigger stays a human press.
object Conductor {
    data class Rule(
        val id: String, val name: String, val trigger: String,
        val action: String, val enabled: Boolean
    )

    data class Fire(
        val host: String? = null, val port: Int? = null,
        val verdict: String? = null
    )

    val triggers: List<Pair<String, String>> = listOf(
        "fingerprinted" to "A fingerprinted knock",
        "honeydrop" to "A honeydrop is taken",
        "vault" to "The knock vault opens",
        "newSource" to "A new source knocks",
        "anyKnock" to "Any knock"
    )

    val actions: List<Pair<String, String>> = listOf(
        "answerInCharacter" to "Answer in character",
        "pivotRecon" to "Load the bench on them",
        "raiseServe" to "Raise Serve for a minute",
        "tighten" to "Raise the second sense",
        "burnThreads" to "Burn the Knocktalk threads",
        "journalMark" to "Mark it in the journal"
    )

    fun triggerLabel(id: String): String =
        triggers.firstOrNull { it.first == id }?.second ?: id

    fun actionLabel(id: String): String =
        actions.firstOrNull { it.first == id }?.second ?: id

    // MARK: - store

    private const val RULES_KEY = "conductorRules"
    private const val FIRED_KEY = "conductorFired"
    private const val REST_MS = 300_000L

    fun loadRules(prefs: Prefs): List<Rule> {
        val raw = prefs.string(RULES_KEY, "")
        if (raw.isBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                Rule(
                    id = obj.getString("id"),
                    name = obj.getString("name"),
                    trigger = obj.getString("trigger"),
                    action = obj.getString("action"),
                    enabled = obj.optBoolean("enabled", true))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveRules(prefs: Prefs, rules: List<Rule>) {
        val array = JSONArray()
        for (rule in rules) {
            val obj = JSONObject()
            obj.put("id", rule.id)
            obj.put("name", rule.name)
            obj.put("trigger", rule.trigger)
            obj.put("action", rule.action)
            obj.put("enabled", rule.enabled)
            array.put(obj)
        }
        prefs.put(RULES_KEY, array.toString())
    }

    /** Two starter reflexes the first time the section is
     * opened — present but inert until the master switch. */
    fun seedIfNeeded(prefs: Prefs) {
        if (prefs.string(RULES_KEY, "").isNotBlank()) return
        saveRules(
            prefs, listOf(
                Rule(
                    id = java.util.UUID.randomUUID().toString(),
                    name = "A honeydrop is taken → " +
                        "Load the bench on them",
                    trigger = "honeydrop", action = "pivotRecon",
                    enabled = true),
                Rule(
                    id = java.util.UUID.randomUUID().toString(),
                    name = "A new source knocks → " +
                        "Mark it in the journal",
                    trigger = "newSource", action = "journalMark",
                    enabled = true)))
    }

    private fun resting(prefs: Prefs, rule: Rule): Boolean {
        val raw = prefs.string(FIRED_KEY, "")
        if (raw.isBlank()) return false
        val last = try {
            JSONObject(raw).optLong(rule.id, 0)
        } catch (_: Exception) {
            0L
        }
        if (last <= 0) return false
        return System.currentTimeMillis() - last < REST_MS
    }

    private fun markFired(prefs: Prefs, rule: Rule) {
        val obj = try {
            JSONObject(prefs.string(FIRED_KEY, "").ifBlank { "{}" })
        } catch (_: Exception) {
            JSONObject()
        }
        obj.put(rule.id, System.currentTimeMillis())
        prefs.put(FIRED_KEY, obj.toString())
    }

    // MARK: - evaluation

    private fun masterOn(prefs: Prefs): Boolean =
        prefs.bool("conductorOn", false)

    private fun evaluate(
        prefs: Prefs, trigger: String, emcon: Emcon, fire: Fire
    ) {
        if (!masterOn(prefs)) return
        for (rule in loadRules(prefs)) {
            if (!rule.enabled || rule.trigger != trigger) continue
            if (resting(prefs, rule)) continue
            markFired(prefs, rule)
            perform(prefs, rule, emcon, fire)
        }
    }

    /// The tripwire funnel: knocks arrive already recorded,
    /// so a source whose only row in the log is this knock
    /// is, by the log's own evidence, new.
    fun onKnock(
        prefs: Prefs, emcon: Emcon, source: String, port: Int,
        proto: String, verdict: String, mine: Boolean
    ) {
        if (!masterOn(prefs) || mine) return
        val host = source.split(" ").firstOrNull() ?: source
        val fire = Fire(host, port, verdict)
        evaluate(prefs, "anyKnock", emcon, fire)
        if (proto == "TCP" &&
            Emcon.persona(forVerdict = verdict) != null) {
            evaluate(prefs, "fingerprinted", emcon, fire)
        }
        val rows = emcon.events.value.filter {
            (it.source.split(" ").firstOrNull() ?: it.source) == host
        }
        if (rows.size <= 1) {
            evaluate(prefs, "newSource", emcon, fire)
        }
    }

    fun onVault(prefs: Prefs, emcon: Emcon) {
        evaluate(prefs, "vault", emcon, Fire())
    }

    fun onHoneydrop(prefs: Prefs, emcon: Emcon, peer: String) {
        // The peer arrives as "host:port" from the canary.
        var host: String? = peer
        var port: Int? = null
        val index = peer.lastIndexOf(":")
        if (index >= 0) {
            host = peer.substring(0, index)
            port = peer.substring(index + 1).toIntOrNull()
        }
        evaluate(prefs, "honeydrop", emcon, Fire(host, port))
    }

    // MARK: - actions

    private fun perform(
        prefs: Prefs, rule: Rule, emcon: Emcon, fire: Fire
    ) {
        var detail = ""
        when (rule.action) {
            "answerInCharacter" -> {
                val host = fire.host
                val port = fire.port
                val verdict = fire.verdict
                if (host != null && port != null && verdict != null) {
                    emcon.escalateNow(host, port, verdict)
                    detail = "the canary takes port $port " +
                        "in character"
                } else {
                    detail = "no knock to answer — the line alone"
                }
            }
            "pivotRecon" -> {
                val sink = emcon.pivotSink
                val host = fire.host
                val port = fire.port
                if (sink != null && host != null && port != null) {
                    sink(host, port)
                    detail = "the bench is loaded on " +
                        "$host:$port — firing stays yours"
                } else {
                    detail = "no target to load — the line alone"
                }
            }
            "raiseServe" -> {
                detail = emcon.raiseServeTimed()
            }
            "tighten" -> {
                emcon.raiseSense("the conductor's rule: ${rule.name}")
                detail = "the second sense is up for 30 minutes"
            }
            "burnThreads" -> {
                val burn = emcon.burnHook
                if (burn != null) {
                    burn()
                    detail = "the Knocktalk threads are burned"
                } else {
                    detail = "no thread store at hand — the line alone"
                }
            }
            else -> {
                detail = "marked"
            }
        }
        Journal.log(
            "emcon", "conductor",
            "reflex fired — ${rule.name}: $detail")
    }
}
