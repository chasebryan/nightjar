package net.nosuchmachine.nightjarhack

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/// The recon bench — the Kotlin mirror of ReconBenchView.
/// Knock (speak each port's protocol, ★ when the protocol's
/// own tell confirms), a connect console, a seeded fuzzer,
/// and the probe library with its handoff to Send.
@Composable
fun ReconTab(app: NightjarApp, goToSend: () -> Unit) {
    val recon = app.recon
    var host by remember { mutableStateOf("") }
    var portsText by remember { mutableStateOf("") }
    var knockUDP by remember { mutableStateOf(false) }
    var jobs by remember { mutableFloatStateOf(24f) }
    var timeout by remember { mutableFloatStateOf(1.5f) }
    var connectTarget by remember { mutableStateOf("") }
    var connectLine by remember { mutableStateOf("") }
    var connectCRLF by remember { mutableStateOf(true) }
    var fuzzTarget by remember { mutableStateOf("") }
    var fuzzSeed by remember { mutableStateOf("") }
    var fuzzCount by remember { mutableFloatStateOf(200f) }
    var fuzzMutations by remember { mutableFloatStateOf(1f) }
    var presetFilter by remember { mutableStateOf("") }

    val hits by recon.hits.collectAsState()
    val knocking by recon.knocking.collectAsState()
    val probed by recon.probed.collectAsState()
    val total by recon.total.collectAsState()
    val consoleLines by recon.consoleLines.collectAsState()
    val connected by recon.connected.collectAsState()
    val fuzzing by recon.fuzzing.collectAsState()
    val fuzzLines by recon.fuzzLines.collectAsState()

    val handoff by app.reconHandoff.collectAsState()
    LaunchedEffect(handoff) {
        handoff?.let { (h, p, _) ->
            host = h
            portsText = p.toString()
            app.reconHandoff.value = null
        }
    }

    val scope = rememberCoroutineScope()

    fun parsePorts(text: String): List<Int> {
        if (text.isBlank()) return ReconPayloads.defaultPorts
        val out = mutableListOf<Int>()
        for (token in text.split(",", " ", ";")) {
            val trimmed = token.trim()
            if (trimmed.isEmpty()) continue
            if ("-" in trimmed) {
                val parts = trimmed.split("-")
                val low = parts.getOrNull(0)?.toIntOrNull()
                val high = parts.getOrNull(1)?.toIntOrNull()
                if (low != null && high != null) {
                    for (port in low..high) {
                        if (port in 1..65535) out.add(port)
                    }
                }
            } else {
                trimmed.toIntOrNull()?.let {
                    if (it in 1..65535) out.add(it)
                }
            }
        }
        return out.distinct()
    }

    fun runKnock() {
        val ports = parsePorts(portsText)
        scope.launch {
            recon.knock(
                host, ports, udp = false,
                timeoutMs = (timeout * 1000).toInt(),
                jobs = jobs.toInt()
            )
            recon.knocking.first { !it }
            if (knockUDP) {
                recon.knock(
                    host, ReconPayloads.udpPortMap.keys.sorted(),
                    udp = true, timeoutMs = (timeout * 1000).toInt(),
                    jobs = jobs.toInt(), append = true
                )
            }
        }
    }

    fun handoffHit(hit: Recon.Hit) {
        val scheme = if (hit.udp) "udp" else "tcp"
        app.sendHandoff.value = "$scheme://$host:${hit.port}"
        val name = if (hit.udp) {
            ReconPayloads.udpPortMap[hit.port]
        } else {
            ReconPayloads.portMap[hit.port]
        }
        app.sendHandoffPayload.value = name
        goToSend()
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item { TabTitle("Recon") }

        // MARK: knock
        item { IosSectionHeader("Knock") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = host,
                        onValueChange = { host = it },
                        label = { Text("host or IP (192.168.1.1)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = portsText,
                        onValueChange = { portsText = it },
                        label = {
                            Text("ports — blank for the usual suspects, or 22,80,443 or 1-1024")
                        },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Also knock the UDP service ports")
                        Switch(
                            checked = knockUDP,
                            onCheckedChange = { knockUDP = it }
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("At a time")
                        Text(
                            "${jobs.toInt()}",
                            color = IosColors.SecondaryLabel
                        )
                    }
                    Slider(
                        value = jobs, onValueChange = { jobs = it },
                        valueRange = 1f..64f
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Timeout")
                        Text(
                            "%.1fs".format(timeout),
                            color = IosColors.SecondaryLabel
                        )
                    }
                    Slider(
                        value = timeout, onValueChange = { timeout = it },
                        valueRange = 0.5f..5f
                    )
                    if (knocking) {
                        OutlinedButton(
                            onClick = { recon.cancelKnock() },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Stop — $probed of $total") }
                    } else {
                        Button(
                            onClick = { runKnock() },
                            enabled = host.isNotBlank(),
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Knock") }
                    }
                    Text(
                        "Connects to each port and speaks the protocol " +
                            "that port usually runs. A ★ means the reply " +
                            "carried the protocol's own tell — the " +
                            "service confirmed itself.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel
                    )
                }
            }
        }

        // MARK: results
        val open = hits.filter { it.isOpen }
        if (open.isNotEmpty()) {
            item { IosSectionHeader("Open — ${open.size}") }
            items(open, key = { it.label }) { hit ->
                IosPanelCard {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { handoffHit(hit) }
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            if (hit.confirmed) "★" else "·",
                            fontWeight = FontWeight.Bold
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                hit.label,
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.SemiBold
                            )
                            if (hit.banner.isNotEmpty()) {
                                Text(
                                    hit.banner,
                                    style = MaterialTheme.typography
                                        .bodySmall
                                )
                            }
                        }
                        Text(
                            hit.service,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel
                        )
                    }
                }
            }
        }

        // MARK: connect
        item { IosSectionHeader("Connect") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = connectTarget,
                        onValueChange = { connectTarget = it },
                        label = { Text("tcp://host:port") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Button(onClick = {
                            if (connected) {
                                recon.close()
                            } else {
                                recon.connectTarget = connectTarget
                                recon.open(connectTarget)
                            }
                        }) { Text(if (connected) "Close" else "Open") }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("CRLF")
                            Switch(
                                checked = connectCRLF,
                                onCheckedChange = { connectCRLF = it }
                            )
                        }
                    }
                    if (connected) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            OutlinedTextField(
                                value = connectLine,
                                onValueChange = { connectLine = it },
                                label = { Text("send a line") },
                                modifier = Modifier.weight(1f)
                            )
                            Button(onClick = {
                                recon.sendLine(connectLine, connectCRLF)
                                connectLine = ""
                            }) { Text("Send") }
                        }
                    }
                    for (line in consoleLines.takeLast(60)) {
                        MonoText(line)
                    }
                    if (consoleLines.isNotEmpty()) {
                        OutlinedButton(onClick = { recon.clearConsole() }) {
                            Text("Clear console")
                        }
                    }
                    Text(
                        "A console, not a terminal: open the socket, " +
                            "send lines, read what comes back.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel
                    )
                }
            }
        }

        // MARK: fuzz
        item { IosSectionHeader("Fuzz") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = fuzzTarget,
                        onValueChange = { fuzzTarget = it },
                        label = { Text("target (tcp://host:port or udp://…)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = fuzzSeed,
                        onValueChange = { fuzzSeed = it },
                        label = { Text("seed hex (optional)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Rounds")
                        Text(
                            "${fuzzCount.toInt()}",
                            color = IosColors.SecondaryLabel
                        )
                    }
                    Slider(
                        value = fuzzCount,
                        onValueChange = { fuzzCount = it },
                        valueRange = 10f..1000f
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Mutations")
                        Text(
                            "${fuzzMutations.toInt()}",
                            color = IosColors.SecondaryLabel
                        )
                    }
                    Slider(
                        value = fuzzMutations,
                        onValueChange = { fuzzMutations = it },
                        valueRange = 1f..8f
                    )
                    if (fuzzing) {
                        OutlinedButton(
                            onClick = { recon.stopFuzz() },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Stop") }
                    } else {
                        Button(
                            onClick = {
                                recon.startFuzz(
                                    rawTarget = fuzzTarget,
                                    seed = if (fuzzSeed.isBlank()) {
                                        null
                                    } else {
                                        ReconPayloads.hx(fuzzSeed)
                                    },
                                    count = fuzzCount.toInt(),
                                    length = 64,
                                    mutations = fuzzMutations.toInt(),
                                    seedValue = null,
                                    read = true,
                                    timeoutMs = 1500
                                )
                            },
                            enabled = fuzzTarget.isNotBlank(),
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Fuzz") }
                    }
                    for (line in fuzzLines.takeLast(60)) {
                        Text(
                            line,
                            style = MaterialTheme.typography.bodySmall
                                .copy(fontFamily = FontFamily.Monospace)
                        )
                    }
                }
            }
        }

        // MARK: library
        item { IosSectionHeader("Probe library") }
        item {
            OutlinedTextField(
                value = presetFilter,
                onValueChange = { presetFilter = it },
                label = { Text("filter the library") },
                modifier = Modifier.fillMaxWidth()
            )
        }
        val library = ReconPayloads.names.filter {
            presetFilter.isBlank() ||
                it.contains(presetFilter.lowercase())
        }
        items(library, key = { it }) { name ->
            val found = ReconPayloads.all.getValue(name)
            IosPanelCard {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            app.sendHandoffPayload.value = name
                            goToSend()
                        }
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(name, fontFamily = FontFamily.Monospace)
                        Text(
                            found.summary,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel
                        )
                    }
                    Text(
                        "${if (found.udp) "udp" else "tcp"}/${found.port}",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel
                    )
                }
            }
        }
    }
}
