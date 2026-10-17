package net.nosuchmachine.nightjarhack

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// EMCON tab — the Kotlin mirror of EmconView. The device's
/// own exposure: scored, itemized, and shut down. See
/// Emcon.kt for the engine and the honest limits.
@Composable
fun EmconTab(app: NightjarApp, goToRecon: () -> Unit) {
    val emcon = app.emcon
    val serve = app.serve
    val ble = app.ble
    val prefs = rememberPrefs()
    val context = LocalContext.current

    val active by emcon.active.collectAsState()
    val scanning by emcon.scanning.collectAsState()
    val exposures by emcon.exposures.collectAsState()
    val lastScanAt by emcon.lastScanAt.collectAsState()
    val auditing by emcon.auditing.collectAsState()
    val announcers by emcon.announcers.collectAsState()
    val heardCount by emcon.heardCount.collectAsState()
    val lastAuditAt by emcon.lastAuditAt.collectAsState()
    val drilling by emcon.drilling.collectAsState()
    val drillBefore by emcon.drillBefore.collectAsState()
    val drillAfter by emcon.drillAfter.collectAsState()
    val tripwireOn by emcon.tripwireOn.collectAsState()
    val watched by emcon.watched.collectAsState()
    val watchedUDP by emcon.watchedUDP.collectAsState()
    val unwatched by emcon.unwatched.collectAsState()
    val events by emcon.events.collectAsState()
    val escalation by emcon.escalation.collectAsState()
    val hometurf by emcon.hometurf.collectAsState()
    val hometurfNotes by emcon.hometurfNotes.collectAsState()
    val senseUntil by emcon.senseUntil.collectAsState()
    val senseReason by emcon.senseReason.collectAsState()
    val vaultOpenUntil by emcon.vaultOpenUntil.collectAsState()
    val vaultCombo by emcon.vaultCombo.collectAsState()
    val vaultAction by emcon.vaultAction.collectAsState()
    val serveRunning by serve.running.collectAsState()
    val gattHostOn by ble.hosting.collectAsState()
    val beaconOn by ble.beaconOn.collectAsState()

    var escalationArmed by prefBool(prefs, "emconEscalation", false)
    var checkName by prefBool(prefs, "emconCheckName", false)
    var checkShare by prefBool(prefs, "emconCheckShare", false)
    var checkHotspot by prefBool(prefs, "emconCheckHotspot", false)
    var checkWifi by prefBool(prefs, "emconCheckWifi", false)
    var checkBluetooth by prefBool(prefs, "emconCheckBluetooth", false)
    var deadHandOn by prefBool(prefs, "deadHand.on", false)
    var deadHandHours by prefInt(prefs, "deadHand.hours", 24)

    val spar = remember { Recon(app.mouth) }
    val sparFuzzing by spar.fuzzing.collectAsState()
    val sparLines by spar.fuzzLines.collectAsState()
    val sparDead by spar.fuzzDead.collectAsState()
    var sparWasFuzzing by remember { mutableStateOf(false) }
    var sparSummary by remember { mutableStateOf<String?>(null) }

    var proberSelection by remember {
        mutableStateOf<ProberFile?>(null)
    }
    var conductorOn by prefBool(prefs, "conductorOn", false)
    var rules by remember {
        mutableStateOf<List<Conductor.Rule>>(emptyList())
    }
    var newTrigger by remember { mutableStateOf("fingerprinted") }
    var newAction by remember { mutableStateOf("pivotRecon") }

    LaunchedEffect(Unit) {
        emcon.restoreIfNeeded()
        emcon.deadHandEvaluate()
        Conductor.seedIfNeeded(prefs)
        rules = Conductor.loadRules(prefs)
        app.steward.refresh()
    }
    LaunchedEffect(sparFuzzing) {
        if (!sparFuzzing && sparWasFuzzing) {
            Journal.log(
                "emcon", "spar",
                (sparSummary ?: "sparring run") +
                    " — $sparDead dead connection(s), Serve " +
                    if (serveRunning) "still up" else "down")
        }
        sparWasFuzzing = sparFuzzing
    }

    val score = Emcon.score(
        gattHostOn = gattHostOn, beaconOn = beaconOn,
        serveRunning = serveRunning, stealth = serve.stealthNow,
        deviceName = emcon.deviceName,
        exposureCount = exposures.size,
        announcerCount = announcers.size)
    val scoreColor = when {
        score.value == 0 -> Color(0xFF34C759)
        score.value <= 15 -> Color(0xFF66D2B1)
        score.value <= 40 -> Color(0xFFFFD60A)
        score.value <= 70 -> Color(0xFFFF9F0A)
        else -> IosColors.Error
    }
    val timeFormat = remember { SimpleDateFormat("HH:mm:ss", Locale.US) }
    val serveTCPPort = prefs.string("serveTcpPort", "9000")
        .toIntOrNull() ?: 9000
    val sparSeeds = events.filter {
        it.proto == "TCP" && it.bytesHex != null
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item { TabTitle("EMCON") }

        // MARK: status + score
        item { IosSectionHeader("Posture") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                if (active) "EMCON ACTIVE" else "EMCON OFF",
                                fontWeight = FontWeight.Bold)
                            Text(
                                if (active) {
                                    "Dark. Unlisted, silent, and " +
                                        "listening for probes."
                                } else {
                                    "This device answers the network " +
                                        "under its own name."
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = IosColors.SecondaryLabel)
                        }
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                "${score.value}",
                                style = MaterialTheme.typography
                                    .headlineMedium,
                                fontWeight = FontWeight.Bold,
                                color = scoreColor)
                            Text(
                                score.band,
                                style = MaterialTheme.typography.labelSmall,
                                fontWeight = FontWeight.SemiBold,
                                color = scoreColor)
                        }
                    }
                    Text(
                        "Exposure score — live emissions weigh most, " +
                            "then what the last knock and audit " +
                            "actually found. Run the drill for the " +
                            "full picture.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                    if (score.parts.isNotEmpty()) {
                        Text(
                            "Why ${score.band}:",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold)
                        for (part in score.parts) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement =
                                    Arrangement.SpaceBetween
                            ) {
                                Text(
                                    part.label,
                                    style = MaterialTheme.typography
                                        .bodySmall)
                                Text(
                                    "+${part.points}",
                                    style = MaterialTheme.typography
                                        .bodySmall,
                                    color = scoreColor)
                            }
                        }
                        if (score.capped) {
                            Text(
                                "Parts sum past 100 — the score " +
                                    "stops there.",
                                style = MaterialTheme.typography
                                    .labelSmall,
                                color = IosColors.SecondaryLabel)
                        }
                    }
                    if (emcon.isAway && !active) {
                        Text(
                            "Off home turf — this network is not " +
                                "your marked home. Going dark is " +
                                "advised.",
                            color = Color(0xFFFF9F0A))
                        Button(
                            onClick = { emcon.activate() },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Go dark now") }
                    }
                    if (active) {
                        OutlinedButton(
                            onClick = { emcon.deactivate() },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Stand down EMCON") }
                    } else if (!emcon.isAway) {
                        Button(
                            onClick = { emcon.activate() },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Go dark") }
                    }
                }
            }
        }

        // MARK: the drill
        item { IosSectionHeader("The drill") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Button(
                        onClick = { emcon.runDrill() },
                        enabled = !drilling && !scanning && !auditing,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            if (drilling) "Running the drill…"
                            else "Prove it — scan, go dark, scan again")
                    }
                    val before = drillBefore
                    val after = drillAfter
                    if (!drilling && before != null && after != null) {
                        val gone = Emcon.silenced(before, after)
                        val still = Emcon.stillShowing(after)
                        if (gone.isEmpty() && still.isEmpty()) {
                            Text(
                                "Before and after agree: nothing " +
                                    "was exposed in the first place.",
                                color = IosColors.SecondaryLabel)
                        } else {
                            if (gone.isNotEmpty()) {
                                Text(
                                    "Silenced by going dark:",
                                    fontWeight = FontWeight.SemiBold)
                                for (line in gone) Text("— $line")
                            } else if (still.isNotEmpty()) {
                                Text(
                                    "Nothing went quiet.",
                                    color = IosColors.SecondaryLabel)
                            }
                            if (still.isEmpty()) {
                                Text(
                                    "Nothing survived the drill. The " +
                                        "second scan found a clean " +
                                        "device.",
                                    color = IosColors.SecondaryLabel)
                            } else {
                                Text(
                                    "Still showing:",
                                    fontWeight = FontWeight.SemiBold)
                                for (line in still) Text("— $line")
                                Text(
                                    "These are real listeners on " +
                                        "the device that EMCON does " +
                                        "not own — the OS, other " +
                                        "apps, or Serve ports kept " +
                                        "under stealth. The " +
                                        "hardening list below is " +
                                        "where the OS ones die.",
                                    style = MaterialTheme.typography
                                        .bodySmall,
                                    color = IosColors.SecondaryLabel)
                            }
                        }
                    } else if (!drilling) {
                        Text(
                            "One tap: full knock and announcement " +
                                "audit, then EMCON engages, then " +
                                "both run again and the difference " +
                                "is read out here.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                }
            }
        }

        // MARK: emissions
        item { IosSectionHeader("Emissions") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    EmissionRow(
                        "Serve listeners",
                        if (serveRunning) {
                            if (serve.stealthNow) {
                                "running, unlisted"
                            } else {
                                "RUNNING, LISTED"
                            }
                        } else {
                            "off"
                        },
                        bad = serveRunning && !serve.stealthNow)
                    EmissionRow(
                        "mDNS listing",
                        if (serve.stealthNow) "off (stealth)"
                        else "on when serving",
                        bad = !serve.stealthNow && serveRunning)
                    EmissionRow(
                        "BLE GATT host",
                        if (gattHostOn) "ARMED — ADVERTISING" else "off",
                        bad = gattHostOn)
                    EmissionRow(
                        "BLE beacon",
                        if (beaconOn) "ON — ADVERTISING" else "off",
                        bad = beaconOn)
                    Text(
                        "Going dark forces Serve stealth, disarms " +
                            "the GATT host and stops the beacon. " +
                            "Coming back never re-opens one — " +
                            "re-arm each in its own tab.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }

        // MARK: self-recon
        item { IosSectionHeader("Self-recon — what they see") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Broadcast name")
                        Text(
                            emcon.deviceName,
                            color = IosColors.SecondaryLabel)
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("LAN address")
                        Text(
                            emcon.ownIP ?: "not on Wi-Fi",
                            color = IosColors.SecondaryLabel)
                    }
                    Button(
                        onClick = { emcon.runSelfScan() },
                        enabled = !scanning && !drilling,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(if (scanning) "Knocking…" else "Knock myself")
                    }
                    if (!scanning && lastScanAt != null) {
                        if (exposures.isEmpty()) {
                            Text(
                                "Nothing answered on any probed " +
                                    "port, on loopback or the LAN " +
                                    "address. From out there, this " +
                                    "device is a rumor.",
                                color = IosColors.SecondaryLabel)
                        } else {
                            for (hit in exposures) {
                                Column {
                                    Text(
                                        "${hit.host}:${hit.port} — " +
                                            hit.service +
                                            if (hit.confirmed) " ★" else "",
                                        fontWeight = FontWeight.SemiBold)
                                    if (hit.banner.isNotEmpty()) {
                                        Text(
                                            hit.banner,
                                            style = MaterialTheme
                                                .typography.bodySmall,
                                            color = IosColors.SecondaryLabel)
                                    }
                                }
                            }
                        }
                        Text(
                            "★ = the reply carried the service's own tell.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    } else if (!scanning) {
                        Text(
                            "Runs Recon's own knock against this " +
                                "phone — every registry port, " +
                                "loopback and LAN address, each " +
                                "port spoken to in its own protocol.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                }
            }
        }

        // MARK: announcement audit
        item { IosSectionHeader("Announcements — mDNS audit") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Button(
                        onClick = { emcon.runBonjourAudit() },
                        enabled = !auditing && !drilling,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            if (auditing) "Listening…"
                            else "Audit what this device announces")
                    }
                    if (!auditing && lastAuditAt != null) {
                        if (announcers.isEmpty()) {
                            Text(
                                "Heard $heardCount announcement(s) " +
                                    "on this network — none of them " +
                                    "is this device. mDNS has " +
                                    "nothing of yours.",
                                color = IosColors.SecondaryLabel)
                        } else {
                            for (ad in announcers) {
                                Column {
                                    Text(
                                        "${ad.label} — ${ad.name}",
                                        fontWeight = FontWeight.SemiBold)
                                    Text(
                                        "${ad.why} · ${ad.type}",
                                        style = MaterialTheme.typography
                                            .bodySmall,
                                        color = IosColors.SecondaryLabel)
                                }
                            }
                            Text(
                                "These are the OS's own megaphones " +
                                    "— Cast and friends. EMCON can't " +
                                    "switch them off; the hardening " +
                                    "list is where they die (name, " +
                                    "sharing).",
                                style = MaterialTheme.typography.bodySmall,
                                color = IosColors.SecondaryLabel)
                        }
                    } else if (!auditing) {
                        Text(
                            "Browses the LAN the way the Scan tab " +
                                "does and flags every announcement " +
                                "that is this device — by name, or " +
                                "by resolving to this phone's address.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                }
            }
        }

        // MARK: tripwire
        item { IosSectionHeader("Tripwire") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Listeners")
                        Text(
                            if (tripwireOn) {
                                "${watched.size} TCP + " +
                                    "${watchedUDP.size} UDP watched"
                            } else {
                                "off"
                            },
                            color = IosColors.SecondaryLabel)
                    }
                    if (unwatched.isNotEmpty()) {
                        Text(
                            "Not watched (already in use): " +
                                unwatched.joinToString(", "),
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Answer in character")
                        Switch(
                            checked = escalationArmed,
                            onCheckedChange = { escalationArmed = it })
                    }
                    Text(
                        "When a knock fingerprints as a real " +
                            "protocol — SSH, HTTP, MQTT, SMTP — the " +
                            "tripwire hands that port to the " +
                            "matching canary for ten minutes, " +
                            "honeydrop as configured on the Serve " +
                            "tab, then takes the port back. The " +
                            "prober's first knock meets silence; " +
                            "their second meets an actor. A port " +
                            "cools down for half an hour afterwards.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                    escalation?.let { live ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement =
                                Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "Answering on ${live.port} as " +
                                    live.persona.uppercase(),
                                fontWeight = FontWeight.SemiBold,
                                color = Color(0xFF34C759))
                            TextButton(
                                onClick = { emcon.endEscalation() }) {
                                Text("Stand down")
                            }
                        }
                    }
                    if (events.isEmpty()) {
                        Text(
                            "Nobody has knocked. When someone runs " +
                                "these probes against this phone, " +
                                "it lands here — source, port, and " +
                                "which first words they used. The " +
                                "log persists across launches. The " +
                                "tripwire never replies.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    } else {
                        for (event in events) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.Top
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        "${event.source} → " +
                                            "${event.proto}/${event.port}" +
                                            if (event.repeatCount > 1) {
                                                " ×${event.repeatCount}"
                                            } else {
                                                ""
                                            },
                                        fontWeight = FontWeight.SemiBold)
                                    Text(event.verdict)
                                    Text(
                                        timeFormat.format(
                                            Date(event.whenMs)),
                                        style = MaterialTheme.typography
                                            .bodySmall,
                                        color = IosColors.SecondaryLabel)
                                }
                                val host = event.source
                                    .split(" ").firstOrNull()
                                    ?: event.source
                                if (host != "127.0.0.1") {
                                    TextButton(onClick = {
                                        app.reconHandoff.value = Triple(
                                            host, event.port,
                                            System.nanoTime())
                                        goToRecon()
                                    }) { Text("Knock back") }
                                }
                            }
                        }
                        OutlinedButton(onClick = {
                            val send = Intent(Intent.ACTION_SEND)
                                .setType("text/plain")
                                .putExtra(
                                    Intent.EXTRA_TEXT,
                                    Emcon.tripwireReport(events))
                            context.startActivity(
                                Intent.createChooser(send, "Tripwire log"))
                        }) { Text("Share the log") }
                        Text(
                            "Readable text. The same log is kept " +
                                "as JSON on the device. The " +
                                "tripwire never replies.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                        TextButton(onClick = { emcon.clearEvents() }) {
                            Text(
                                "Clear the log",
                                color = IosColors.Error)
                        }
                    }
                }
            }
        }

        // MARK: prober files
        item { IosSectionHeader("Prober files") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    val files = ProberFiles.build(events)
                    if (files.isEmpty()) {
                        Text(
                            "No probers yet. When something " +
                                "knocks, its file opens here.",
                            color = IosColors.SecondaryLabel)
                    } else {
                        for (file in files) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        proberSelection = file
                                        ProberFiles.markSeen(
                                            file, prefs)
                                    },
                                horizontalArrangement =
                                    Arrangement.SpaceBetween,
                                verticalAlignment =
                                    Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        file.host,
                                        fontWeight = FontWeight.Medium)
                                    Text(
                                        "${file.knocks} knock(s) · " +
                                            "${file.ports.size} port(s)" +
                                            if (file.drops > 0) {
                                                " · took ${file.drops} " +
                                                    "drop(s)"
                                            } else {
                                                ""
                                            } +
                                            " · last " +
                                            timeFormat.format(
                                                Date(file.lastSeenMs)),
                                        style = MaterialTheme.typography
                                            .bodySmall,
                                        color = IosColors.SecondaryLabel)
                                }
                                if (ProberFiles.changed(file, prefs)) {
                                    Text(
                                        "CHANGED",
                                        style = MaterialTheme.typography
                                            .labelSmall,
                                        fontWeight = FontWeight.Bold,
                                        color = Color(0xFFFF9F0A))
                                }
                                Text(
                                    "›",
                                    color = IosColors.TertiaryLabel)
                            }
                        }
                    }
                    Text(
                        "A dossier for everyone who has knocked — " +
                            "assembled from the tripwire log this " +
                            "phone keeps. It covers what the log " +
                            "still holds.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }
        proberSelection?.let { file ->
            item {
                IosPanelCard {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement =
                                Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                "Prober file — ${file.host}",
                                fontWeight = FontWeight.SemiBold)
                            TextButton(onClick = {
                                proberSelection = null
                            }) { Text("Close") }
                        }
                        LabeledRow("Address", file.host)
                        LabeledRow("Knocks", "${file.knocks}")
                        LabeledRow(
                            "First seen",
                            SimpleDateFormat(
                                "MMM d, HH:mm", Locale.US)
                                .format(Date(file.firstSeenMs)))
                        LabeledRow(
                            "Last seen",
                            SimpleDateFormat(
                                "MMM d, HH:mm", Locale.US)
                                .format(Date(file.lastSeenMs)))
                        if (file.drops > 0) {
                            LabeledRow(
                                "Honeydrops taken", "${file.drops}")
                        }
                        Text(
                            "Doors tried",
                            fontWeight = FontWeight.SemiBold)
                        for ((port, count) in file.portsByTraffic) {
                            LabeledRow("Port $port", "×$count")
                        }
                        if (file.verdicts.isNotEmpty()) {
                            Text(
                                "First words heard",
                                fontWeight = FontWeight.SemiBold)
                            for (verdict in file.verdicts) {
                                Text(verdict)
                            }
                        }
                        if (file.links.isNotEmpty()) {
                            Text(
                                "Same hands?",
                                fontWeight = FontWeight.SemiBold)
                            for (link in file.links) {
                                Column {
                                    Text(
                                        link.host,
                                        fontWeight = FontWeight.Medium)
                                    for (shared in link.shared) {
                                        Text(
                                            "· $shared",
                                            style = MaterialTheme
                                                .typography.bodySmall,
                                            color = IosColors
                                                .SecondaryLabel)
                                    }
                                }
                            }
                            Text(
                                "Correlation over this phone's " +
                                    "own tripwire log: shared " +
                                    "habits suggest, they never " +
                                    "prove. Two tenants of one " +
                                    "NAT can share every trait " +
                                    "here and still be strangers.",
                                style = MaterialTheme.typography
                                    .bodySmall,
                                color = IosColors.SecondaryLabel)
                        }
                        val favorite = file.favoritePort
                        if (favorite != null &&
                            !file.host.startsWith("127.")) {
                            Button(
                                onClick = {
                                    app.reconHandoff.value = Triple(
                                        file.host, favorite,
                                        System.nanoTime())
                                    proberSelection = null
                                    goToRecon()
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) { Text("Knock back at port $favorite") }
                        }
                        OutlinedButton(onClick = {
                            val send = Intent(Intent.ACTION_SEND)
                                .setType("text/plain")
                                .putExtra(Intent.EXTRA_TEXT, file.text)
                            context.startActivity(
                                Intent.createChooser(
                                    send, "Prober file"))
                        }) { Text("Share this file") }
                        Text(
                            "An address is a claim about a " +
                                "network, not an identity — " +
                                "addresses are borrowed, shared, " +
                                "and spoofed. The file records " +
                                "what knocked, never who.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                }
            }
        }

        // MARK: home-turf memory
        item { IosSectionHeader("Home-turf memory") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    when {
                        emcon.homeSubnet == null -> Text(
                            "No home subnet is marked, so there " +
                                "is no turf to learn.",
                            color = IosColors.SecondaryLabel)
                        !emcon.hometurfReady -> Text(
                            "Learning the pattern — " +
                                "${hometurf.nights} of 3 nights banked.",
                            color = IosColors.SecondaryLabel)
                        else -> {
                            Text(
                                "Pattern held: ${hometurf.nights} " +
                                    "nights · ${hometurf.sources.size} " +
                                    "sources · ${hometurf.ports.size} " +
                                    "doors · ${hometurf.verdicts.size} " +
                                    "first words.")
                            if (hometurfNotes.isEmpty()) {
                                Text(
                                    "Nothing off-pattern tonight.",
                                    color = IosColors.SecondaryLabel)
                            } else {
                                for (note in hometurfNotes) {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement =
                                            Arrangement.SpaceBetween,
                                        verticalAlignment =
                                            Alignment.CenterVertically
                                    ) {
                                        Text(
                                            note,
                                            modifier = Modifier.weight(1f))
                                        TextButton(onClick = {
                                            emcon.hometurfDismiss(note)
                                        }) { Text("Dismiss") }
                                    }
                                }
                            }
                            TextButton(
                                onClick = { emcon.hometurfReset() }) {
                                Text(
                                    "Forget the pattern",
                                    color = IosColors.Error)
                            }
                        }
                    }
                    Text(
                        "Learned only while EMCON is up on the " +
                            "home subnet — three banked nights " +
                            "hold the pattern, and after that the " +
                            "tab stops reporting events and starts " +
                            "reporting deviations.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }

        // MARK: second sense
        item { IosSectionHeader("Second sense") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    val until = senseUntil
                    if (emcon.senseActive && until != null) {
                        Text(
                            "Heightened until " +
                                timeFormat.format(Date(until)),
                            fontWeight = FontWeight.SemiBold)
                        Text(
                            senseReason,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                        OutlinedButton(
                            onClick = { emcon.senseStandDown() }) {
                            Text("Stand it down")
                        }
                    } else {
                        Text(
                            "At ease. The perimeter is at its " +
                                "ordinary posture.",
                            color = IosColors.SecondaryLabel)
                    }
                    Text(
                        "The perimeter tightens itself for " +
                            "thirty minutes when a foreign " +
                            "nightjar-grade probe speaks to it, " +
                            "or a honeydrop is taken: answer in " +
                            "character arms whether or not its " +
                            "switch is set. Nothing else changes.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }

        // MARK: the conductor
        item { IosSectionHeader("The conductor") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Conductor")
                        Switch(
                            checked = conductorOn,
                            onCheckedChange = { conductorOn = it })
                    }
                    for (rule in rules) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(rule.name)
                                Text(
                                    Conductor.triggerLabel(rule.trigger) +
                                        " → " +
                                        Conductor.actionLabel(rule.action),
                                    style = MaterialTheme.typography
                                        .bodySmall,
                                    color = IosColors.SecondaryLabel)
                            }
                            Switch(
                                checked = rule.enabled,
                                onCheckedChange = { on ->
                                    rules = rules.map {
                                        if (it.id == rule.id) {
                                            it.copy(enabled = on)
                                        } else {
                                            it
                                        }
                                    }
                                    Conductor.saveRules(prefs, rules)
                                })
                            TextButton(onClick = {
                                rules = rules.filter {
                                    it.id != rule.id
                                }
                                Conductor.saveRules(prefs, rules)
                            }) {
                                Text("Delete", color = IosColors.Error)
                            }
                        }
                    }
                    Text(
                        "When",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold)
                    for (row in Conductor.triggers.chunked(2)) {
                        Row(
                            horizontalArrangement =
                                Arrangement.spacedBy(6.dp)
                        ) {
                            for ((id, label) in row) {
                                FilterChip(
                                    selected = newTrigger == id,
                                    onClick = { newTrigger = id },
                                    label = { Text(label) })
                            }
                        }
                    }
                    Text(
                        "Then",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold)
                    for (row in Conductor.actions.chunked(2)) {
                        Row(
                            horizontalArrangement =
                                Arrangement.spacedBy(6.dp)
                        ) {
                            for ((id, label) in row) {
                                FilterChip(
                                    selected = newAction == id,
                                    onClick = { newAction = id },
                                    label = { Text(label) })
                            }
                        }
                    }
                    Button(
                        onClick = {
                            val rule = Conductor.Rule(
                                id = java.util.UUID.randomUUID()
                                    .toString(),
                                name = Conductor.triggerLabel(newTrigger) +
                                    " → " +
                                    Conductor.actionLabel(newAction),
                                trigger = newTrigger,
                                action = newAction,
                                enabled = true)
                            rules = rules + rule
                            Conductor.saveRules(prefs, rules)
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Add the reflex") }
                    Text(
                        "Reflexes you arm once, fired without " +
                            "you: a trigger on the wire, an action " +
                            "the instrument already knows. Each " +
                            "rule rests five minutes between " +
                            "firings, every firing is journaled, " +
                            "and actions needing a mouth or a " +
                            "target degrade to the journal line " +
                            "alone when they have neither. Firing " +
                            "the bench stays your press — a reflex " +
                            "can load Recon, never pull its trigger.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }

        // MARK: the steward
        item {
            StewardSection(
                app = app, prefs = prefs,
                hometurfNotes = hometurfNotes)
        }

        // MARK: self-sparring
        item { IosSectionHeader("Self-sparring") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    when {
                        sparSeeds.isEmpty() -> Text(
                            "No captured bytes yet. When the " +
                                "tripwire catches a knock, its " +
                                "first words are kept — and become " +
                                "ammunition here: replayed, mutated, " +
                                "and fired at your own Serve to see " +
                                "what holds.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                        !serveRunning -> Text(
                            "${sparSeeds.size} captured probe(s) " +
                                "ready. Start Serve (TCP " +
                                ":$serveTCPPort) on the Serve tab — " +
                                "sparring fires mutations of a real " +
                                "capture at your own listener, on " +
                                "loopback, and reads what it answers.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                        else -> {
                            val seed = sparSeeds.first()
                            Text(
                                "Latest capture: ${seed.verdict} — " +
                                    "${seed.byteCount} B from ${seed.source}",
                                style = MaterialTheme.typography.bodySmall)
                            if (sparFuzzing) {
                                Text("Sparring…")
                                OutlinedButton(
                                    onClick = { spar.stopFuzz() }) {
                                    Text("Stop")
                                }
                            } else {
                                Button(onClick = {
                                    val seedData = PayloadKit
                                        .decodeHex(seed.bytesHex ?: "")
                                    sparSummary = "60 mutations of a " +
                                        "captured ${seed.verdict} " +
                                        "probe vs own Serve :$serveTCPPort"
                                    spar.startFuzz(
                                        rawTarget = "tcp://127.0.0.1:" +
                                            serveTCPPort,
                                        seed = seedData, count = 60,
                                        length = seedData.size,
                                        mutations = 2, seedValue = null,
                                        read = true, timeoutMs = 1200)
                                }) {
                                    Text("Spar — 60 mutations vs own " +
                                        "Serve :$serveTCPPort")
                                }
                            }
                        }
                    }
                    for (line in sparLines.takeLast(10)) {
                        MonoText(line)
                    }
                    if (sparLines.isNotEmpty() && !sparFuzzing) {
                        Text(
                            if (sparDead == 0) {
                                "Serve held: no dead connections."
                            } else {
                                "Serve dropped $sparDead " +
                                    "connection(s) under mutation."
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                    Text(
                        "The loop fires only at this device: " +
                            "the target is loopback, and the " +
                            "mutations are of traffic this phone " +
                            "actually received.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }

        // MARK: night maneuvers
        item {
            ManeuversSection(scoreValue = score.value, emcon = emcon,
                serveRunning = serveRunning,
                serveTCPPort = serveTCPPort, sparSeeds = sparSeeds)
        }

        // MARK: knock vault
        item { IosSectionHeader("Knock vault") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        "Speak three protocols, in order, from " +
                            "one other device, inside 20 seconds — " +
                            "each knock's bytes recognized as its " +
                            "protocol:",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                    val digitOptions = listOf(
                        "ssh", "tls", "mqtt", "http", "smtp", "ftp")
                    for (index in 0 until 3) {
                        Text(
                            "Digit ${index + 1}",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold)
                        for (row in digitOptions.chunked(3)) {
                            Row(
                                horizontalArrangement =
                                    Arrangement.spacedBy(6.dp)
                            ) {
                                for (digit in row) {
                                    FilterChip(
                                        selected = vaultCombo
                                            .getOrNull(index) == digit,
                                        onClick = {
                                            emcon.setVaultDigit(
                                                index, digit)
                                        },
                                        label = {
                                            Text(digit.uppercase())
                                        })
                                }
                            }
                        }
                    }
                    Text(
                        "When spoken",
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = FontWeight.SemiBold)
                    for (row in Emcon.vaultActions.chunked(2)) {
                        Row(
                            horizontalArrangement =
                                Arrangement.spacedBy(6.dp)
                        ) {
                            for (action in row) {
                                FilterChip(
                                    selected = vaultAction == action,
                                    onClick = {
                                        emcon.setVaultAction(action)
                                    },
                                    label = {
                                        Text(Emcon.vaultActionLabel(action))
                                    })
                            }
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Vault")
                        if (vaultOpenUntil != null) {
                            Text(
                                "OPEN — seals " + timeFormat.format(
                                    Date(vaultOpenUntil!!)),
                                fontWeight = FontWeight.SemiBold,
                                color = Color(0xFF34C759))
                        } else {
                            Text(
                                "sealed",
                                color = IosColors.SecondaryLabel)
                        }
                    }
                    if (vaultOpenUntil != null) {
                        OutlinedButton(
                            onClick = { emcon.sealVault() },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Seal now") }
                    }
                    Text(
                        "Speak the combination from one other " +
                            "device and the chosen macro fires. " +
                            "Timed macros ride a sixty-second " +
                            "window and stand back down at the " +
                            "seal; anything you already had " +
                            "running stays yours. The ear must be " +
                            "listening — the tripwire, or the " +
                            "relay. The default combination is " +
                            "printed in the app — it is no secret. " +
                            "Change the digits: the combination " +
                            "is the key. Knocks from this device " +
                            "itself never count.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }

        // MARK: dead hand
        item { IosSectionHeader("Dead hand") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Arm the dead hand")
                        Switch(
                            checked = deadHandOn,
                            onCheckedChange = { on ->
                                deadHandOn = on
                                if (on) {
                                    emcon.deadHandArm()
                                } else {
                                    emcon.deadHandDisarm()
                                }
                            })
                    }
                    if (deadHandOn) {
                        Text(
                            "Check in every",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold)
                        Row(
                            horizontalArrangement =
                                Arrangement.spacedBy(6.dp)
                        ) {
                            for (hours in Emcon.deadHandHoursOptions) {
                                FilterChip(
                                    selected = deadHandHours == hours,
                                    onClick = {
                                        deadHandHours = hours
                                        emcon.deadHandReschedule()
                                    },
                                    label = {
                                        Text(
                                            if (hours < 24) {
                                                "$hours hours"
                                            } else {
                                                "${hours / 24} day(s)"
                                            })
                                    })
                            }
                        }
                        if (emcon.deadHandHasFallen) {
                            Text(
                                "THE HAND HAS FALLEN — threads " +
                                    "burned, EMCON raised. Check " +
                                    "in to re-arm it.",
                                fontWeight = FontWeight.SemiBold,
                                color = IosColors.Error)
                        } else {
                            emcon.deadHandDeadlineMs?.let { deadline ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement =
                                        Arrangement.SpaceBetween
                                ) {
                                    Text("Deadline")
                                    Text(
                                        SimpleDateFormat(
                                            "MMM d, HH:mm", Locale.US)
                                            .format(Date(deadline)),
                                        color = IosColors.SecondaryLabel)
                                }
                                if (emcon.deadHandOverdue) {
                                    Text(
                                        "OVERDUE — the hand falls " +
                                            "at the next opening.",
                                        fontWeight = FontWeight.SemiBold,
                                        color = Color(0xFFFF9F0A))
                                }
                            }
                        }
                        Button(
                            onClick = { emcon.deadHandCheckIn() },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Check in — I'm here") }
                    }
                    Text(
                        "Arm it, then check in here — " +
                            "deliberately, with the button — before " +
                            "the interval runs out. If the app is " +
                            "next opened with the check-in overdue, " +
                            "the Knocktalk threads burn and EMCON " +
                            "rises before anything else happens. " +
                            "It falls at the next OPENING, not at " +
                            "the deadline: no app gets a background " +
                            "timer worth trusting. The reminders " +
                            "are courtesies. Merely opening the " +
                            "app never counts as a check-in — " +
                            "that is the point of the hand.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }

        // MARK: hardening
        item { IosSectionHeader("Hardening — the OS half") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("This network")
                        Text(
                            emcon.currentSubnet?.let { "$it.0/24" }
                                ?: "not on Wi-Fi",
                            color = IosColors.SecondaryLabel)
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Home turf")
                        Text(
                            emcon.homeSubnet?.let { "$it.0/24" }
                                ?: "unmarked",
                            color = IosColors.SecondaryLabel)
                    }
                    if (emcon.currentSubnet != null &&
                        emcon.currentSubnet != emcon.homeSubnet) {
                        Button(
                            onClick = {
                                emcon.markHome()
                                app.mouth.toast(
                                    "Marked — EMCON will warn you " +
                                        "off home turf.")
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Mark this network as home") }
                    }
                    if (emcon.homeSubnet != null) {
                        TextButton(onClick = {
                            emcon.unmarkHome()
                            app.mouth.toast("Home turf unmarked.")
                        }) {
                            Text("Unmark home", color = IosColors.Error)
                        }
                    }
                    ChecklistRow(
                        checked = checkName,
                        onCheckedChange = { checkName = it },
                        title = "Rename this device to something generic",
                        detail = "Settings → About phone → Device " +
                            "name. Right now it broadcasts “" +
                            emcon.deviceName + "” — verify the " +
                            "change above after renaming.")
                    ChecklistRow(
                        checked = checkShare,
                        onCheckedChange = { checkShare = it },
                        title = "Quick Share: Contacts only or " +
                            "No one",
                        detail = "Settings → Connected devices → " +
                            "Quick Share — the AirDrop setting, " +
                            "by another name.")
                    ChecklistRow(
                        checked = checkHotspot,
                        onCheckedChange = { checkHotspot = it },
                        title = "Hotspot off",
                        detail = "Settings → Network → Hotspot — " +
                            "off unless you are deliberately sharing.")
                    ChecklistRow(
                        checked = checkWifi,
                        onCheckedChange = { checkWifi = it },
                        title = "Wi-Fi: notify for public networks " +
                            "off, auto-connect off",
                        detail = "Settings → Network → Wi-Fi → " +
                            "preferences — stops the phone asking " +
                            "to join networks by name.")
                    ChecklistRow(
                        checked = checkBluetooth,
                        onCheckedChange = { checkBluetooth = it },
                        title = "Bluetooth off when not in use",
                        detail = "Settings → Connected devices. " +
                            "Trade-off: Listen needs Bluetooth on " +
                            "to hear anything — weigh it per situation.")
                    Text(
                        "EMCON can verify the broadcast name and " +
                            "the app's emissions. These five live " +
                            "in Settings — check them off on your word.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }

        // MARK: limits
        item {
            Text(
                "EMCON cannot hide this device from the access " +
                    "point it is joined to, and the OS's own " +
                    "radios (Find My Device, Quick Share) answer " +
                    "to Settings, not to this app. What EMCON " +
                    "strips is everything that identifies the " +
                    "device — and anyone who probes it announces " +
                    "themselves to the tripwire.",
                style = MaterialTheme.typography.bodySmall,
                color = IosColors.SecondaryLabel,
                modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
}

@Composable
private fun LabeledRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label)
        Text(value, color = IosColors.SecondaryLabel)
    }
}

@Composable
private fun EmissionRow(name: String, state: String, bad: Boolean) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(name)
        Text(
            state,
            color = if (bad) IosColors.Error else IosColors.SecondaryLabel)
    }
}

@Composable
private fun ChecklistRow(
    checked: Boolean, onCheckedChange: (Boolean) -> Unit,
    title: String, detail: String
) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(title, modifier = Modifier.weight(1f))
            Switch(checked = checked, onCheckedChange = onCheckedChange)
        }
        Text(
            detail,
            style = MaterialTheme.typography.bodySmall,
            color = IosColors.SecondaryLabel)
    }
}

// MARK: - night maneuvers

private data class ManeuverLeg(
    val name: String, val outcome: Outcome, val detail: String
) {
    enum class Outcome { PASS, FLAG, SKIP }
}

@Composable
private fun ManeuversSection(
    scoreValue: Int, emcon: Emcon, serveRunning: Boolean,
    serveTCPPort: Int, sparSeeds: List<Emcon.TripEvent>
) {
    val spar = remember { Recon(null) }
    val fuzzing by spar.fuzzing.collectAsState()
    val fuzzDead by spar.fuzzDead.collectAsState()
    var legs by remember { mutableStateOf<List<ManeuverLeg>>(emptyList()) }
    var running by remember { mutableStateOf(false) }
    var wasFuzzing by remember { mutableStateOf(false) }
    var grade by remember { mutableStateOf<String?>(null) }
    val tripwireOn by emcon.tripwireOn.collectAsState()
    val unwatched by emcon.unwatched.collectAsState()

    fun finish(sparDead: Int?) {
        val finalLegs = legs.toMutableList()
        if (sparDead != null) {
            finalLegs.add(
                ManeuverLeg(
                    "Spar",
                    if (sparDead == 0) {
                        ManeuverLeg.Outcome.PASS
                    } else {
                        ManeuverLeg.Outcome.FLAG
                    },
                    if (sparDead == 0) {
                        "Serve held all 60 mutations"
                    } else {
                        "Serve dropped $sparDead connection(s) " +
                            "under mutation"
                    }))
        }
        legs = finalLegs
        val clean = finalLegs.count {
            it.outcome == ManeuverLeg.Outcome.PASS
        }
        val text = "$clean of ${finalLegs.size} legs clean"
        grade = text
        Journal.log(
            "emcon", "maneuvers",
            text + " — " + finalLegs.joinToString(" · ") {
                "${it.name}: ${it.detail}"
            })
        running = false
    }

    LaunchedEffect(fuzzing) {
        if (!fuzzing && wasFuzzing && running) {
            finish(fuzzDead)
        }
        wasFuzzing = fuzzing
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosSectionHeader("Night maneuvers")
        IosPanelCard {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = {
                        legs = emptyList()
                        grade = null
                        running = true
                        val chain = Journal.verifyChain()
                        val first = mutableListOf<ManeuverLeg>()
                        first.add(
                            ManeuverLeg(
                                "Seal chain",
                                if (chain.brokenLine == null) {
                                    ManeuverLeg.Outcome.PASS
                                } else {
                                    ManeuverLeg.Outcome.FLAG
                                },
                                if (chain.brokenLine == null) {
                                    "${chain.sealed} sealed line(s) " +
                                        "hold, ${chain.legacy} legacy " +
                                        "line(s) predate the chain"
                                } else {
                                    "BROKEN at sealed line " +
                                        chain.brokenLine
                                }))
                        val censusDetail =
                            "exposure $scoreValue · tripwire " +
                                (if (tripwireOn) "up" else "DOWN") +
                                if (unwatched.isEmpty()) {
                                    " · every port watched"
                                } else {
                                    " · ${unwatched.size} port(s) " +
                                        "unwatched"
                                }
                        first.add(
                            ManeuverLeg(
                                "Census",
                                if (tripwireOn && unwatched.isEmpty()) {
                                    ManeuverLeg.Outcome.PASS
                                } else {
                                    ManeuverLeg.Outcome.FLAG
                                },
                                censusDetail))
                        legs = first
                        val seed = sparSeeds.firstOrNull()
                        if (!serveRunning) {
                            legs = legs + ManeuverLeg(
                                "Spar", ManeuverLeg.Outcome.SKIP,
                                "Serve is down — no listener to test")
                            finish(null)
                        } else if (seed == null) {
                            legs = legs + ManeuverLeg(
                                "Spar", ManeuverLeg.Outcome.SKIP,
                                "no captured probe to replay yet")
                            finish(null)
                        } else {
                            val seedData = PayloadKit.decodeHex(
                                seed.bytesHex ?: "")
                            spar.startFuzz(
                                rawTarget = "tcp://127.0.0.1:" +
                                    serveTCPPort,
                                seed = seedData, count = 60,
                                length = seedData.size, mutations = 2,
                                seedValue = null, read = true,
                                timeoutMs = 1200)
                        }
                    },
                    enabled = !running,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        if (running) "Running maneuvers…"
                        else "Run night maneuvers")
                }
                for (leg in legs) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.Top
                    ) {
                        Text(
                            when (leg.outcome) {
                                ManeuverLeg.Outcome.PASS -> "✓"
                                ManeuverLeg.Outcome.FLAG -> "!"
                                ManeuverLeg.Outcome.SKIP -> "–"
                            },
                            color = when (leg.outcome) {
                                ManeuverLeg.Outcome.PASS ->
                                    Color(0xFF34C759)
                                ManeuverLeg.Outcome.FLAG ->
                                    Color(0xFFFF9F0A)
                                ManeuverLeg.Outcome.SKIP ->
                                    IosColors.SecondaryLabel
                            },
                            fontWeight = FontWeight.Bold)
                        Column {
                            Text(leg.name, fontWeight = FontWeight.Medium)
                            Text(
                                leg.detail,
                                style = MaterialTheme.typography.bodySmall,
                                color = IosColors.SecondaryLabel)
                        }
                    }
                }
                if (grade != null && !running) {
                    Text(
                        "$grade — graded into the night log.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
                Text(
                    "The instrument reports for duty: the seal " +
                        "chain proves the record, the census " +
                        "reads the posture, the spar fires sixty " +
                        "mutations of a real capture at your own " +
                        "Serve. The grade goes into the sealed " +
                        "log either way.",
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
            }
        }
    }
}

// MARK: - the steward

@Composable
private fun StewardSection(
    app: NightjarApp, prefs: Prefs, hometurfNotes: List<String>
) {
    val steward = app.steward
    val emcon = app.emcon
    var stewardOn by prefBool(prefs, "stewardOn", false)
    var latitude by prefString(prefs, "stewardLatitude", "observe")
    val assessment by steward.assessment.collectAsState()
    val mirrorLine by steward.mirrorLine.collectAsState()
    val proposals by steward.proposals.collectAsState()
    val orders by steward.orders.collectAsState()
    val cases by steward.cases.collectAsState()
    var orderName by remember { mutableStateOf("") }
    var orderHost by remember { mutableStateOf("") }
    var orderPort by remember { mutableStateOf("") }
    var orderVerdict by remember { mutableStateOf("") }
    var orderAction by remember { mutableStateOf("tighten") }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosSectionHeader("The steward")
        IosPanelCard {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("The steward")
                    Switch(
                        checked = stewardOn,
                        onCheckedChange = { stewardOn = it })
                }
                if (stewardOn) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        for ((id, label) in listOf(
                            "observe" to "Observe",
                            "act" to "Act",
                            "full" to "Full")) {
                            FilterChip(
                                selected = latitude == id,
                                onClick = {
                                    latitude = id
                                    steward.refresh()
                                },
                                label = { Text(label) })
                        }
                    }
                    Text(assessment)
                    if (mirrorLine.isNotEmpty()) {
                        Text(
                            mirrorLine,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                    for (proposal in proposals) {
                        Column(
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                proposal.title,
                                fontWeight = FontWeight.Medium)
                            Text(
                                proposal.detail,
                                style = MaterialTheme.typography.bodySmall,
                                color = IosColors.SecondaryLabel)
                            Row(
                                horizontalArrangement =
                                    Arrangement.spacedBy(16.dp)
                            ) {
                                when (proposal.kind) {
                                    "plan" -> TextButton(onClick = {
                                        steward.enact(proposal)
                                    }) { Text("Enact the plan") }
                                    "rule" -> TextButton(onClick = {
                                        steward.enact(proposal)
                                    }) { Text("Approve the reflex") }
                                    "charter" -> TextButton(onClick = {
                                        steward.enact(proposal)
                                    }) { Text("Amend the charter") }
                                    "posture" -> TextButton(onClick = {
                                        steward.enact(proposal)
                                    }) { Text("Raise EMCON") }
                                }
                                TextButton(onClick = {
                                    steward.dismissProposal(proposal)
                                }) {
                                    Text(
                                        "Dismiss",
                                        color = IosColors.Error)
                                }
                            }
                        }
                    }
                    for (note in hometurfNotes) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement =
                                Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                note,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.weight(1f))
                            TextButton(onClick = {
                                emcon.hometurfDismiss(note)
                            }) { Text("Dismiss") }
                        }
                    }
                    Text(
                        "Watch orders — your own situations",
                        fontWeight = FontWeight.Medium)
                    for (order in orders) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(order.name)
                                Text(
                                    orderSummary(order),
                                    style = MaterialTheme.typography
                                        .bodySmall,
                                    color = IosColors.SecondaryLabel)
                            }
                            Switch(
                                checked = order.enabled,
                                onCheckedChange = { on ->
                                    steward.setOrders(
                                        orders.map {
                                            if (it.id == order.id) {
                                                it.copy(enabled = on)
                                            } else {
                                                it
                                            }
                                        })
                                })
                            TextButton(onClick = {
                                steward.setOrders(
                                    orders.filter { it.id != order.id })
                            }) {
                                Text("Delete", color = IosColors.Error)
                            }
                        }
                    }
                    OutlinedTextField(
                        value = orderName,
                        onValueChange = { orderName = it },
                        label = {
                            Text("Order name (e.g. the landlord's box)")
                        },
                        modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(
                        value = orderHost,
                        onValueChange = { orderHost = it },
                        label = { Text("Host contains (blank = any)") },
                        modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(
                        value = orderPort,
                        onValueChange = { orderPort = it },
                        label = { Text("Port (blank = any)") },
                        modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(
                        value = orderVerdict,
                        onValueChange = { orderVerdict = it },
                        label = {
                            Text("First word contains (blank = any)")
                        },
                        modifier = Modifier.fillMaxWidth())
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        for ((id, label) in listOf(
                            "tighten" to "Raise the second sense",
                            "answer" to "Answer in character",
                            "pivot" to "Load the bench on them")) {
                            FilterChip(
                                selected = orderAction == id,
                                onClick = { orderAction = id },
                                label = { Text(label) })
                        }
                    }
                    Button(
                        onClick = {
                            if (orderName.isEmpty()) return@Button
                            steward.setOrders(
                                orders + Steward.WatchOrder(
                                    id = java.util.UUID.randomUUID()
                                        .toString(),
                                    name = orderName, host = orderHost,
                                    port = orderPort,
                                    verdict = orderVerdict,
                                    action = orderAction,
                                    enabled = true))
                            orderName = ""
                            orderHost = ""
                            orderPort = ""
                            orderVerdict = ""
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Post the watch order") }
                    val open = cases.filter { it.open }
                    if (open.isNotEmpty()) {
                        Text("Case files", fontWeight = FontWeight.Medium)
                        for (entry in open) {
                            Column(
                                verticalArrangement =
                                    Arrangement.spacedBy(3.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement =
                                        Arrangement.SpaceBetween,
                                    verticalAlignment =
                                        Alignment.CenterVertically
                                ) {
                                    Text(
                                        entry.hosts.joinToString(", "),
                                        fontWeight = FontWeight.Medium,
                                        modifier = Modifier.weight(1f))
                                    TextButton(onClick = {
                                        steward.closeCase(entry)
                                    }) { Text("Close") }
                                }
                                for (line in entry.entries.takeLast(4)) {
                                    Text(
                                        line,
                                        style = MaterialTheme.typography
                                            .bodySmall,
                                        color = IosColors.SecondaryLabel)
                                }
                            }
                        }
                    }
                    val dismissed = Dismissals.count(prefs)
                    if (dismissed > 0) {
                        TextButton(onClick = {
                            Dismissals.clear(prefs)
                        }) {
                            Text(
                                "Restore $dismissed dismissed " +
                                    "deviation(s)")
                        }
                    }
                }
                Text(
                    "A watch officer under a charter you write. " +
                        "OBSERVE: it assesses and files proposals, " +
                        "and touches nothing. ACT: it runs plans " +
                        "in proportion to confidence — high runs " +
                        "the whole plan, medium its first step, " +
                        "low is journaled and left to you. FULL: " +
                        "it may also approve its own drafted " +
                        "reflexes and raise EMCON at your usual " +
                        "hour. Every judgment is a sealed journal " +
                        "line with its score and its factors; you " +
                        "audit it, you amend the charter. It " +
                        "thinks while the app is open — every " +
                        "opening is a shift change.",
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
            }
        }
    }
}

private fun orderSummary(order: Steward.WatchOrder): String {
    val parts = mutableListOf<String>()
    parts.add(
        if (order.host.isEmpty()) "any host" else "host ∋ ${order.host}")
    parts.add(
        if (order.port.isEmpty()) "any port" else "port ${order.port}")
    parts.add(
        if (order.verdict.isEmpty()) {
            "any first word"
        } else {
            "speaks ∋ ${order.verdict}"
        })
    return parts.joinToString(" · ") + " → " + order.action
}
