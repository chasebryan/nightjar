package net.nosuchmachine.nightjarhack

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale

/// Drift watch: the baselines dossiers keep.
///
/// A knock testifies about a moment. A baseline is that
/// testimony, kept — so the next knock on the same address can
/// be compared against it and the DIFFERENCE becomes the
/// testimony: a port that opened since, a service that went
/// silent. A device's own story changing is one of the
/// earliest signals that something happened to it; until now
/// nobody was keeping the old story. Baselines are keyed by
/// address and live in filesDir/dossier-baselines.json.
data class DossierBaseline(val whenMs: Long, val lines: List<String>)

object DossierBaselines {
    private fun file(filesDir: File): File =
        File(filesDir, "dossier-baselines.json")

    fun load(filesDir: File): Map<String, DossierBaseline> {
        return try {
            val root = JSONObject(file(filesDir).readText())
            val out = mutableMapOf<String, DossierBaseline>()
            val keys = root.keys()
            while (keys.hasNext()) {
                val ip = keys.next()
                val entry = root.getJSONObject(ip)
                val whenText = entry.getString("when")
                val whenMs = try {
                    Instant.parse(whenText).toEpochMilli()
                } catch (_: Exception) {
                    (whenText.toDoubleOrNull()?.times(1000))?.toLong()
                        ?: 0L
                }
                val linesArray = entry.getJSONArray("lines")
                val lines = (0 until linesArray.length()).map {
                    linesArray.getString(it)
                }
                out[ip] = DossierBaseline(whenMs, lines)
            }
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun baseline(filesDir: File, ip: String): DossierBaseline? =
        load(filesDir)[ip]

    fun set(filesDir: File, baseline: DossierBaseline, ip: String) {
        try {
            val all = load(filesDir).toMutableMap()
            all[ip] = baseline
            val root = JSONObject()
            for ((key, value) in all) {
                val entry = JSONObject()
                entry.put("when",
                          Instant.ofEpochMilli(value.whenMs).toString())
                entry.put("lines", JSONArray(value.lines))
                root.put(key, entry)
            }
            file(filesDir).writeText(root.toString())
        } catch (_: Exception) {
        }
    }

    /// (opened since, closed since) — set differences both ways.
    fun diff(baseline: DossierBaseline,
             current: List<String>): Pair<List<String>, List<String>> {
        val before = baseline.lines.toSet()
        val now = current.toSet()
        return Pair((now - before).sorted(), (before - now).sorted())
    }
}

fun baselineStamp(whenMs: Long): String =
    SimpleDateFormat("MMM d, yyyy 'at' h:mm a", Locale.US)
        .format(Date(whenMs))

/// A device dossier: everything the instrument knows about one
/// device, from every organ that has testified about it.
///
/// Scan testifies about Wi-Fi (it swept the address, or it heard
/// the Bonjour announcement). Listen testifies about Bluetooth —
/// a row whose name matches is a POSSIBLE match by name, labeled
/// as exactly that and no more: a name is not an identity. Recon
/// testifies on demand: knock the address now, with the full
/// probe registry, and the answers join the page.
@Composable
fun DossierView(
    app: NightjarApp,
    title: String,
    ip: String?,
    wifiLines: List<String>,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val filesDir = context.filesDir
    val rows by app.post.rows.collectAsState()
    val recon = remember { Recon(app.mouth) }
    val hits by recon.hits.collectAsState()
    val knocking by recon.knocking.collectAsState()
    val probed by recon.probed.collectAsState()
    val total by recon.total.collectAsState()
    var baseline by remember {
        mutableStateOf(
            ip?.let { DossierBaselines.baseline(filesDir, it) })
    }
    var knockedOnce by remember { mutableStateOf(false) }
    var lastKnockStamp by remember { mutableStateOf("") }
    var driftOpened by remember {
        mutableStateOf<List<String>>(emptyList())
    }
    var driftClosed by remember {
        mutableStateOf<List<String>>(emptyList())
    }
    var wasKnocking by remember { mutableStateOf(false) }

    val bleMatches = rows.filter {
        it.name == title || it.preferredLabel == title
    }
    val openHits = hits.filter { it.isOpen }
    val knockSignature = openHits.map { "${it.label} ${it.service}" }
        .sorted()
    val hasDrift = driftOpened.isNotEmpty() || driftClosed.isNotEmpty()

    /// A knock just finished: if a baseline is kept for this
    /// address, the difference is the story — show it, and put
    /// it in the night log once.
    fun knockFinished() {
        knockedOnce = true
        lastKnockStamp = clockTime(ListeningPost.nowSeconds())
        val address = ip ?: return
        val kept = baseline ?: return
        val (opened, closed) =
            DossierBaselines.diff(kept, knockSignature)
        driftOpened = opened
        driftClosed = closed
        if (opened.isNotEmpty() || closed.isNotEmpty()) {
            val stamp = baselineStamp(kept.whenMs)
            val parts = mutableListOf<String>()
            if (opened.isNotEmpty()) {
                parts.add("opened " + opened.joinToString(", "))
            }
            if (closed.isNotEmpty()) {
                parts.add("closed " + closed.joinToString(", "))
            }
            Journal.log(
                "dossier", "drift",
                "$title ($address) drifted since $stamp: " +
                    parts.joinToString("; "))
        }
    }

    LaunchedEffect(knocking) {
        if (wasKnocking && !knocking) knockFinished()
        wasKnocking = knocking
    }

    fun takeBaseline() {
        val address = ip ?: return
        val fresh = DossierBaseline(
            System.currentTimeMillis(), knockSignature)
        DossierBaselines.set(filesDir, fresh, address)
        baseline = fresh
        driftOpened = emptyList()
        driftClosed = emptyList()
        Journal.log(
            "dossier", "baseline",
            "$title ($address) baselined — ${knockSignature.size} open")
    }

    fun dossierText(): String {
        val lines = mutableListOf("DOSSIER — $title", "")
        lines.add("Wi-Fi (Scan):")
        lines += wifiLines.map { "  $it" }
        lines.add("Bluetooth (Listen):")
        if (bleMatches.isEmpty()) {
            lines.add("  not heard advertising under this name")
        } else {
            for (row in bleMatches) {
                lines.add("  possible match by name — ${row.kind}, " +
                    "${row.sightings} sightings")
            }
        }
        lines.add("Knock (Recon):")
        if (hits.isEmpty()) {
            lines.add("  not knocked from this page")
        } else if (openHits.isEmpty()) {
            lines.add("  knocked $lastKnockStamp — nothing open")
        } else {
            for (hit in openHits) {
                lines.add("  ${hit.label} ${hit.service}" +
                    (if (hit.confirmed) " ★" else "") +
                    (if (hit.banner.isEmpty()) ""
                     else " — ${hit.banner}"))
            }
        }
        val kept = baseline
        if (kept != null) {
            lines.add("Baseline (${baselineStamp(kept.whenMs)}):")
            if (kept.lines.isEmpty()) {
                lines.add("  nothing open")
            } else {
                lines += kept.lines.map { "  $it" }
            }
            if (hasDrift) {
                lines.add("Drift since baseline:")
                lines += driftOpened.map { "  opened: $it" }
                lines += driftClosed.map { "  closed: $it" }
            }
        }
        return lines.joinToString("\n")
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            OutlinedButton(onClick = onBack) { Text("‹ Scan") }
            Spacer(Modifier.height(8.dp))
            TabTitle(title)
        }
        item {
            IosPanelCard {
                Column(modifier = Modifier.padding(12.dp),
                       verticalArrangement =
                           Arrangement.spacedBy(4.dp)) {
                    Text("Wi-Fi — Scan testifies",
                         style = MaterialTheme.typography.titleMedium)
                    for (line in wifiLines) Text(line)
                }
            }
        }
        item {
            IosPanelCard {
                Column(modifier = Modifier.padding(12.dp),
                       verticalArrangement =
                           Arrangement.spacedBy(4.dp)) {
                    Text("Bluetooth — Listen testifies",
                         style = MaterialTheme.typography.titleMedium)
                    if (bleMatches.isEmpty()) {
                        Text(
                            "Not heard advertising under this name. " +
                                "(Listen matches by name only — a " +
                                "name is a claim, not an identity.)",
                            color = MaterialTheme.colorScheme
                                .onSurfaceVariant)
                    } else {
                        for (row in bleMatches) {
                            Column {
                                Text("Possible match by name",
                                     fontWeight = FontWeight.SemiBold)
                                Text(
                                    "${row.kind} · ${row.sightings} " +
                                        "sightings · last RSSI " +
                                        (row.rssiLast?.toString()
                                            ?: "—"),
                                    style = MaterialTheme.typography
                                        .bodySmall,
                                    color = MaterialTheme.colorScheme
                                        .onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
        item {
            IosPanelCard {
                Column(modifier = Modifier.padding(12.dp),
                       verticalArrangement =
                           Arrangement.spacedBy(6.dp)) {
                    Text("Knock — Recon testifies",
                         style = MaterialTheme.typography.titleMedium)
                    if (ip == null) {
                        Text(
                            "No address swept for this device yet — " +
                                "run a sweep on the Scan tab and its " +
                                "dossier gains a knock.",
                            color = MaterialTheme.colorScheme
                                .onSurfaceVariant)
                    } else {
                        if (knocking) {
                            Text("Knocking $ip — $probed/$total")
                            OutlinedButton(
                                onClick = { recon.cancelKnock() }) {
                                Text("Cancel")
                            }
                        } else {
                            Button(
                                onClick = {
                                    recon.knock(
                                        ip,
                                        ReconPayloads.defaultPorts,
                                        udp = false)
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) { Text("Knock $ip — full registry") }
                        }
                        if (hits.isNotEmpty() && openHits.isEmpty()) {
                            Text("Nothing open.",
                                 color = MaterialTheme.colorScheme
                                     .onSurfaceVariant)
                        }
                        for (hit in openHits) {
                            Column {
                                Text(
                                    "${hit.label} ${hit.service}" +
                                        (if (hit.confirmed) " ★"
                                         else ""),
                                    fontWeight = FontWeight.SemiBold)
                                if (hit.banner.isNotEmpty()) {
                                    Text(
                                        hit.banner,
                                        style = MaterialTheme
                                            .typography.bodySmall,
                                        color = MaterialTheme
                                            .colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                        if (knockedOnce) {
                            val kept = baseline
                            if (kept != null) {
                                Text(
                                    "Baseline kept — " +
                                        baselineStamp(kept.whenMs) +
                                        ", ${kept.lines.size} open.",
                                    style = MaterialTheme.typography
                                        .bodySmall,
                                    color = MaterialTheme.colorScheme
                                        .onSurfaceVariant)
                                if (hasDrift) {
                                    for (line in driftOpened) {
                                        Text(
                                            "＋ Opened since: $line",
                                            color = Color(0xFF35C759))
                                    }
                                    for (line in driftClosed) {
                                        Text(
                                            "－ Closed since: $line",
                                            color = Color(0xFFFF453A))
                                    }
                                } else if (hits.isNotEmpty()) {
                                    Text(
                                        "No drift — it answers " +
                                            "exactly as baselined.",
                                        color = MaterialTheme
                                            .colorScheme.onSurfaceVariant)
                                }
                                Button(
                                    onClick = { takeBaseline() },
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Text("Update the baseline to now")
                                }
                            } else {
                                Button(
                                    onClick = { takeBaseline() },
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Text("Keep this knock as the baseline")
                                }
                            }
                        }
                    }
                }
            }
        }
        item {
            OutlinedButton(
                onClick = {
                    val file = File(context.cacheDir, "dossier.txt")
                    file.writeText(dossierText())
                    shareFile(app, file)
                },
                modifier = Modifier.fillMaxWidth()
            ) { Text("Share the dossier") }
        }
    }
}
