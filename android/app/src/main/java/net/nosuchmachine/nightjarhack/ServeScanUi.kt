package net.nosuchmachine.nightjarhack

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

// MARK: - Serve tab

@Composable
fun ServeTab(app: NightjarApp) {
    val prefs = rememberPrefs()
    var tcpPort by prefString(prefs, "serveTcpPort", "9000")
    var udpPort by prefString(prefs, "serveUdpPort", "9001")
    var httpPort by prefString(prefs, "serveHttpPort", "8080")
    var replyMode by prefString(prefs, "serveReplyMode", "static")
    var replyText by prefString(prefs, "serveReplyText", "ack")
    var stealth by prefBool(prefs, "serveStealth", false)
    var fileName by remember { mutableStateOf("") }
    val serve = app.serve
    val running by serve.running.collectAsState()
    val status by serve.status.collectAsState()
    val inbox by serve.inbox.collectAsState()
    val context = LocalContext.current

    val filePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            try {
                val bytes = context.contentResolver.openInputStream(uri)
                    ?.readBytes() ?: ByteArray(0)
                serve.fileReplyBytes = bytes
                fileName = "${bytes.size} bytes loaded"
                app.mouth.toast("Reply file loaded — ${bytes.size} bytes")
            } catch (e: Exception) {
                app.mouth.toast("Could not read that file", error = true)
            }
        }
    }

    fun start() {
        serve.stealthNow = stealth
        serve.start(
            tcpPort.toIntOrNull() ?: 0,
            udpPort.toIntOrNull() ?: 0,
            httpPort.toIntOrNull() ?: 0,
            replyMode, replyText, stealth
        )
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            TabTitle("Serve")
            app.mouth.localIPAddress()?.let { ip ->
                Text(
                    "Reachable at tcp://$ip:${tcpPort.ifEmpty { "9000" }}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = tcpPort, onValueChange = { tcpPort = it },
                            label = { Text("TCP port") }, modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = udpPort, onValueChange = { udpPort = it },
                            label = { Text("UDP port") }, modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = httpPort, onValueChange = { httpPort = it },
                            label = { Text("HTTP port") }, modifier = Modifier.weight(1f)
                        )
                    }
                    PickerRow(
                        "Reply mode", replyMode,
                        listOf("static", "echo", "file")
                    ) { replyMode = it }
                    if (replyMode == "static") {
                        OutlinedTextField(
                            value = replyText, onValueChange = { replyText = it },
                            label = { Text("Static reply") },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    if (replyMode == "file") {
                        OutlinedButton(
                            onClick = { filePicker.launch("*/*") },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                if (fileName.isEmpty()) "Pick the reply file"
                                else "Reply file: $fileName"
                            )
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text("Stealth")
                            Text(
                                "No Bonjour listing, no arrival banners",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Switch(
                            checked = stealth,
                            onCheckedChange = {
                                stealth = it
                                serve.stealthNow = it
                                if (running) start()
                            }
                        )
                    }
                    if (running) {
                        Button(
                            onClick = { serve.stop() },
                            colors = ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.error
                            ),
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Stop serving") }
                    } else {
                        Button(
                            onClick = { start() },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Start serving") }
                    }
                    if (status.isNotEmpty()) {
                        Text(status, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
        item { CanarySection(app) }
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    "Inbox — ${inbox.size} arrival(s)",
                    style = MaterialTheme.typography.titleMedium
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = {
                        val file = File(
                            context.cacheDir, "inbox.jsonl"
                        )
                        file.writeText(serve.inboxJsonl)
                        shareFile(app, file)
                    }) { Text("Share") }
                    OutlinedButton(onClick = { serve.clearInbox() }) {
                        Text("Clear")
                    }
                }
            }
        }
        items(inbox.reversed(), key = { it.atMs }) { arrival ->
            IosPanelCard {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        "${arrival.via} · ${arrival.from} · ${clockTime(arrival.atMs / 1000.0)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    val text = arrival.text
                    if (text != null) {
                        MonoText(text.take(300))
                    } else {
                        MonoText(
                            PayloadKit.hexdump(
                                arrival.data.copyOf(minOf(arrival.data.size, 96))
                            )
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Scan tab

@Composable
fun ScanTab(app: NightjarApp) {
    val prefs = rememberPrefs()
    var host by prefString(prefs, "scanHost", "")
    var portsText by prefString(prefs, "scanPorts", "")
    var results by remember { mutableStateOf<List<PortResult>>(emptyList()) }
    var progress by remember { mutableStateOf("") }
    var scanning by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val ownIP = app.mouth.localIPAddress()
    if (host.isEmpty() && ownIP != null) {
        host = ownIP.substringBeforeLast('.') + ".1"
    }
    var sweptHosts by remember {
        mutableStateOf<List<String>>(emptyList())
    }
    var bonjourFound by remember {
        mutableStateOf<List<BonjourSweeper.Found>>(emptyList())
    }
    var dossier by remember {
        mutableStateOf<Triple<String, String?, List<String>>?>(null)
    }
    val sweepPortNow = prefs.string("sweepPort", "80")
    dossier?.let { picked ->
        DossierView(
            app, picked.first, picked.second, picked.third
        ) { dossier = null }
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            TabTitle("Scan")
            Text(
                "This network: ${ownIP ?: "no address"} · gateway guess ${
                    ownIP?.substringBeforeLast('.')?.plus(".1") ?: "—"
                } · subnet ${ownIP?.substringBeforeLast('.') ?: "—"}.0/24",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text("Port scan", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(
                        value = host, onValueChange = { host = it },
                        label = { Text("Host") }, modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = portsText, onValueChange = { portsText = it },
                        label = { Text("Ports (blank = the usual 28; or 22,80,8000-8100)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    if (scanning) {
                        Button(
                            onClick = { app.scanner.stop() },
                            colors = ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.error
                            ),
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Stop scan — $progress") }
                    } else {
                        Button(
                            onClick = {
                                val ports = ScanKit.parsePorts(portsText, true)
                                results = emptyList()
                                scanning = true
                                progress = "0/${ports.size}"
                                scope.launch {
                                    app.scanner.scan(
                                        host, ports,
                                        onResult = { result ->
                                            results = (results + result)
                                                .sortedBy { it.port }
                                        },
                                        onProgress = { done, total ->
                                            progress = "$done/$total"
                                        }
                                    )
                                    scanning = false
                                    app.mouth.logRecon(
                                        "scan", host,
                                        results.map {
                                            "${it.port} ${it.service} — ${it.banner ?: ""}"
                                        }
                                    )
                                }
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Scan $host") }
                    }
                    for (result in results) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    app.sendHandoff.value =
                                        "tcp://${result.host}:${result.port}"
                                    ScanKit.payloadByPort[result.port]?.let {
                                        app.sendHandoffPayload.value = it
                                    }
                                    app.mouth.toast(
                                        "Target set — Send tab" +
                                            (ScanKit.payloadByPort[result.port]
                                                ?.let { n -> " (probe: $n)" } ?: "")
                                    )
                                }
                                .padding(vertical = 4.dp)
                        ) {
                            Text(
                                "${result.port} · ${result.service}",
                                style = MaterialTheme.typography.bodyMedium.copy(
                                    fontFamily = FontFamily.Monospace
                                )
                            )
                            result.banner?.let {
                                Text(
                                    it,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
        item { TlsSection(app) }
        if (sweptHosts.isNotEmpty() || bonjourFound.isNotEmpty()) {
            item {
                DossiersSection(
                    sweptHosts, sweepPortNow, bonjourFound
                ) { picked -> dossier = picked }
            }
        }
        item { BonjourSection(app) { found -> bonjourFound = found } }
        item { SweepSection(app) { hosts -> sweptHosts = hosts } }
        item { FeedSection(app) }
        item { DnsSection(app) }
        item { PcapSection(app) }
    }
}

@Composable
fun TlsSection(app: NightjarApp) {
    val prefs = rememberPrefs()
    var host by prefString(prefs, "tlsHost", "")
    var port by prefString(prefs, "tlsPort", "443")
    var lines by remember { mutableStateOf<List<String>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    IosPanelCard {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("TLS certificate inspector", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = host, onValueChange = { host = it },
                    label = { Text("Host") }, modifier = Modifier.weight(2f)
                )
                OutlinedTextField(
                    value = port, onValueChange = { port = it },
                    label = { Text("Port") }, modifier = Modifier.weight(1f)
                )
            }
            Button(
                onClick = {
                    busy = true
                    scope.launch {
                        lines = try {
                            withContext(Dispatchers.IO) {
                                TlsInspector.inspect(host, port.toIntOrNull() ?: 443)
                            }
                        } catch (e: Exception) {
                            listOf("inspect failed: ${e.message}")
                        }
                        busy = false
                    }
                },
                enabled = !busy && host.isNotBlank(),
                modifier = Modifier.fillMaxWidth()
            ) { Text(if (busy) "Inspecting…" else "Inspect") }
            for (line in lines) MonoText(line)
        }
    }
}

@Composable
fun BonjourSection(
    app: NightjarApp,
    onFound: (List<BonjourSweeper.Found>) -> Unit = {}
) {
    var found by remember { mutableStateOf<List<BonjourSweeper.Found>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    IosPanelCard {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("Bonjour sweep", style = MaterialTheme.typography.titleMedium)
            Button(
                onClick = {
                    busy = true
                    scope.launch {
                        found = BonjourSweeper(context).sweep()
                        onFound(found)
                        busy = false
                    }
                },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth()
            ) { Text(if (busy) "Sweeping (6 s)…" else "Sweep the ten service types") }
            for (service in found) {
                Column {
                    Text("${service.name} — ${service.label}")
                    Text(
                        "${service.host ?: "?"}:${service.port ?: "?"} · ${service.type}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
fun SweepSection(
    app: NightjarApp,
    onHosts: (List<String>) -> Unit = {}
) {
    val prefs = rememberPrefs()
    var target by prefString(prefs, "sweepTarget", "")
    var port by prefString(prefs, "sweepPort", "80")
    var hosts by remember { mutableStateOf<List<String>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    IosPanelCard {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("Subnet sweep", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = target, onValueChange = { target = it },
                    label = { Text("Subnet (blank = own /24)") },
                    modifier = Modifier.weight(2f)
                )
                OutlinedTextField(
                    value = port, onValueChange = { port = it },
                    label = { Text("Port") }, modifier = Modifier.weight(1f)
                )
            }
            Button(
                onClick = {
                    busy = true
                    hosts = emptyList()
                    progress = "0/254"
                    scope.launch(Dispatchers.IO) {
                        val own = app.mouth.localIPAddress()
                        var base = target.trim().substringBefore('/')
                        if (base.isEmpty() && own != null) {
                            base = own.substringBeforeLast('.')
                        }
                        val prefix = base.split('.').take(3).joinToString(".")
                        val portNumber = port.toIntOrNull() ?: 80
                        val pool = java.util.concurrent.Executors
                            .newFixedThreadPool(32)
                        val gate = java.util.concurrent.Semaphore(32)
                        val foundHosts = java.util.Collections
                            .synchronizedList(mutableListOf<String>())
                        val futures = (1..254).map { last ->
                            pool.submit {
                                gate.acquire()
                                try {
                                    val ip = "$prefix.$last"
                                    if (ip != own) {
                                        try {
                                            Socket().use { s ->
                                                s.connect(
                                                    InetSocketAddress(ip, portNumber),
                                                    1000
                                                )
                                                foundHosts.add(ip)
                                            }
                                        } catch (_: Exception) {
                                        }
                                    }
                                } finally {
                                    gate.release()
                                }
                            }
                        }
                        var done = 0
                        for (future in futures) {
                            try {
                                future.get()
                            } catch (_: Exception) {
                            }
                            done += 1
                            if (done % 32 == 0) {
                                withContext(Dispatchers.Main) {
                                    progress = "$done/254"
                                }
                            }
                        }
                        pool.shutdown()
                        withContext(Dispatchers.Main) {
                            hosts = foundHosts.sorted()
                            onHosts(hosts)
                            busy = false
                            progress = ""
                        }
                    }
                },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth()
            ) { Text(if (busy) "Sweeping… $progress" else "Sweep the /24") }
            for (foundHost in hosts) {
                Text(
                    foundHost,
                    modifier = Modifier
                        .clickable {
                            app.sendHandoff.value = "tcp://$foundHost:${port}"
                            app.mouth.toast("Target set — Send tab")
                        }
                        .padding(vertical = 2.dp),
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontFamily = FontFamily.Monospace
                    )
                )
            }
        }
    }
}

@Composable
fun FeedSection(app: NightjarApp) {
    val prefs = rememberPrefs()
    var host by prefString(prefs, "feedHost", "")
    var watching by remember { mutableStateOf(false) }
    var events by remember { mutableStateOf<List<String>>(emptyList()) }
    val scope = rememberCoroutineScope()
    IosPanelCard {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("Observation feed", style = MaterialTheme.typography.titleMedium)
            Text(
                "Re-scans the host's usual ports every 20 s and timelines " +
                    "what changes: ports appearing, vanishing, banners changing.",
                style = MaterialTheme.typography.bodySmall
            )
            OutlinedTextField(
                value = host, onValueChange = { host = it },
                label = { Text("Host to watch") },
                modifier = Modifier.fillMaxWidth()
            )
            if (watching) {
                Button(
                    onClick = { watching = false },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) { Text("Stop watching") }
            } else {
                Button(
                    onClick = {
                        if (host.isBlank()) return@Button
                        watching = true
                        events = emptyList()
                        scope.launch {
                            var previous = mapOf<Int, String?>()
                            var first = true
                            while (watching) {
                                val snapshot = mutableMapOf<Int, String?>()
                                val scanner = PortScanner()
                                scanner.scan(
                                    host, ScanKit.topPorts.map { it.first },
                                    onResult = { snapshot[it.port] = it.banner },
                                    onProgress = { _, _ -> }
                                )
                                val now = clockTime(ListeningPost.nowSeconds())
                                if (first) {
                                    events = events + "$now — baseline: " +
                                        snapshot.keys.sorted().joinToString(", ")
                                    first = false
                                } else {
                                    for (port in snapshot.keys - previous.keys) {
                                        events = events + "$now — port $port appeared"
                                    }
                                    for (port in previous.keys - snapshot.keys) {
                                        events = events + "$now — port $port vanished"
                                    }
                                    for (port in snapshot.keys intersect previous.keys) {
                                        if (snapshot[port] != previous[port]) {
                                            events = events +
                                                "$now — port $port banner changed: ${snapshot[port] ?: ""}"
                                        }
                                    }
                                }
                                previous = snapshot
                                delay(20_000)
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) { Text("Watch $host") }
            }
            for (event in events.takeLast(40)) MonoText(event)
            if (events.isNotEmpty()) {
                OutlinedButton(onClick = {
                    app.mouth.logRecon("feed", host, events)
                    app.mouth.toast("Feed timeline saved to history")
                }) { Text("Save timeline to history") }
            }
        }
    }
}

@Composable
fun DnsSection(app: NightjarApp) {
    var name by remember { mutableStateOf("example.com") }
    var lines by remember { mutableStateOf<List<String>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    IosPanelCard {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("DNS toolkit", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                value = name, onValueChange = { name = it },
                label = { Text("Name to look up (via 1.1.1.1)") },
                modifier = Modifier.fillMaxWidth()
            )
            Button(
                onClick = {
                    busy = true
                    scope.launch {
                        lines = withContext(Dispatchers.IO) { DnsKit.lookup(name) }
                        busy = false
                    }
                },
                enabled = !busy && name.isNotBlank(),
                modifier = Modifier.fillMaxWidth()
            ) { Text(if (busy) "Looking up…" else "Look up") }
            for (line in lines) MonoText(line)
        }
    }
}

@Composable
fun PcapSection(app: NightjarApp) {
    var lines by remember { mutableStateOf<List<String>>(emptyList()) }
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            try {
                val bytes = context.contentResolver.openInputStream(uri)
                    ?.readBytes() ?: ByteArray(0)
                lines = PcapKit.dissect(bytes)
            } catch (e: Exception) {
                lines = listOf("could not read that file: ${e.message}")
            }
        }
    }
    IosPanelCard {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("pcap dissector", style = MaterialTheme.typography.titleMedium)
            Text(
                "Classic libpcap only (not pcapng). Reads the file here — " +
                    "nothing is transmitted.",
                style = MaterialTheme.typography.bodySmall
            )
            OutlinedButton(
                onClick = { picker.launch("*/*") },
                modifier = Modifier.fillMaxWidth()
            ) { Text("Pick a .pcap file") }
            for (line in lines.take(80)) MonoText(line)
        }
    }
}

/// The Scan tab's dossier index: one page per device the
/// sweep or the discovery heard, every organ's testimony on
/// it — the doorway into DossierView.
@Composable
fun DossiersSection(
    sweptHosts: List<String>, sweepPort: String,
    bonjourFound: List<BonjourSweeper.Found>,
    onPick: (Triple<String, String?, List<String>>) -> Unit
) {
    IosPanelCard {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text("Dossiers", style = MaterialTheme.typography.titleMedium)
            for (ip in sweptHosts) {
                Text(
                    "\uD83D\uDCC1 $ip",
                    modifier = Modifier
                        .clickable {
                            onPick(
                                Triple(
                                    ip, ip,
                                    listOf(
                                        "Answered the sweep on port $sweepPort",
                                        "Census: Scan tab subnet sweep"
                                    )
                                )
                            )
                        }
                        .padding(vertical = 2.dp),
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontFamily = FontFamily.Monospace
                    )
                )
            }
            for (service in bonjourFound) {
                Text(
                    "\uD83D\uDCC1 ${service.name}",
                    modifier = Modifier
                        .clickable {
                            onPick(
                                Triple(
                                    service.name, null,
                                    listOf(
                                        "Announces itself via Bonjour: ${service.label}",
                                        "Census: Scan tab discovery sweep"
                                    )
                                )
                            )
                        }
                        .padding(vertical = 2.dp),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            Text(
                "One page per device, every organ's testimony: " +
                    "what Scan heard, whether Listen has heard " +
                    "the name over Bluetooth, and a Recon knock " +
                    "on demand.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
