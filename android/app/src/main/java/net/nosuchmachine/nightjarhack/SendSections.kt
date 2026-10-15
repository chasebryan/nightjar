package net.nosuchmachine.nightjarhack

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp

@Composable
fun CentipedeSection(
    app: NightjarApp, source: String, payloadText: String,
    xorKey: String, useGzip: Boolean, framing: String, method: String,
    onRelease: () -> Unit
) {
    val prefs = rememberPrefs()
    val open = prefBool(prefs, "sectionOpen.centipede", true)
    var route by prefString(prefs, "centipedeRoute", "")
    var sweepTarget by prefString(prefs, "centipedeSweepTarget", "")
    var sweepPorts by prefString(
        prefs, "centipedeSweepPorts", "80,443,22,445,62078,8080"
    )
    var mode by prefString(prefs, "centipedeMode", "chain")
    var returnLeg by prefBool(prefs, "centipedeReturn", true)
    var perDevice by prefBool(prefs, "centipedePerDevice", false)
    var smartSeed by prefBool(prefs, "centipedeSmartSeed", true)
    var homeTarget by prefString(prefs, "centipedeHome", "")
    var rulesText by prefString(prefs, "traceRules", "")
    val crawl = app.crawl
    val busy by crawl.crawlBusy.collectAsState()
    val lines by crawl.crawlLines.collectAsState()
    val findings by crawl.crawlFindings.collectAsState()
    val homecoming by crawl.crawlHomecoming.collectAsState()
    val sweepStatus by crawl.sweepStatus.collectAsState()
    val talkBusy by crawl.talkBusy.collectAsState()

    val routeLines = route.split("\n")
    val hopCount = Crawl.expandJourney(routeLines, perDevice, returnLeg).first
        .take(300).size

    CollapsibleSection("Centipede", open) {
        Text(
            "A route walked hop by hop by this phone. Lines: targets, " +
                "10.0.0.10-25 ranges, host:80,443 trains, bare hosts " +
                "(trains over the usual ports), phone:NAME.",
            style = MaterialTheme.typography.bodySmall
        )
        OutlinedTextField(
            value = route,
            onValueChange = { route = it },
            label = { Text("Route — one stop per line") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 3,
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontFamily = FontFamily.Monospace
            )
        )
        OutlinedTextField(
            value = sweepTarget,
            onValueChange = { sweepTarget = it },
            label = { Text("Sweep subnet (blank = this phone's /24)") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = sweepPorts,
            onValueChange = { sweepPorts = it },
            label = { Text("Discovery ports") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedButton(
            onClick = {
                crawl.discoverSubnet(sweepTarget, sweepPorts) { found ->
                    val existing = routeLines.filter { it.isNotBlank() }
                    route = (existing + found).joinToString("\n")
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Discover the subnet into the route") }
        if (sweepStatus.isNotEmpty()) {
            Text(sweepStatus, style = MaterialTheme.typography.bodySmall)
        }
        OutlinedButton(
            onClick = {
                val ip = app.mouth.localIPAddress()
                val port = prefs.string("serveTcpPort", "9000")
                if (ip != null) {
                    val line = "tcp://$ip:$port"
                    route = (routeLines.filter { it.isNotBlank() } + line)
                        .joinToString("\n")
                    app.mouth.toast("Added this phone — start Serve, then release")
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Add this phone's Serve as a target") }
        PickerRow("Mode", mode, listOf("chain", "seed")) { mode = it }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Return to sender (walk back)")
            Switch(checked = returnLeg, onCheckedChange = { returnLeg = it })
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Every device gets its own walk")
            Switch(checked = perDevice, onCheckedChange = { perDevice = it })
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Smart seed — speak each port's protocol")
            Switch(checked = smartSeed, onCheckedChange = { smartSeed = it })
        }
        OutlinedTextField(
            value = homeTarget,
            onValueChange = { homeTarget = it },
            label = { Text("Deliver homecoming to (optional)") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = rulesText,
            onValueChange = { rulesText = it },
            label = { Text("Adaptive rules — the harvest steers the walk") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 3,
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontFamily = FontFamily.Monospace
            )
        )
        Text(
            "One rule per line; replies are matched as they land. " +
                "Examples:\n" +
                "# contains SSH => tag banner-grabbed\n" +
                "# contains Redis => followup Redis PING (RESP)\n" +
                "# port 9100 => followup Printer test page (TCP 9100)\n" +
                "# contains 401 => stop\n" +
                "followup sends the named library payload to the same " +
                "door (its reply is harvested, never carried); tag " +
                "labels the finding and the logbook; stop drops the " +
                "carry. The same rules drive the Network trace below.",
            style = MaterialTheme.typography.bodySmall
        )
        if (busy) {
            Button(
                onClick = { crawl.stopCrawl() },
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                ),
                modifier = Modifier.fillMaxWidth()
            ) { Text("Stop the centipede") }
        } else {
            Button(
                onClick = {
                    onRelease()
                    crawl.crawl(
                        route = routeLines,
                        mode = mode,
                        returnLeg = returnLeg,
                        perDevice = perDevice,
                        homeTarget = homeTarget,
                        smartSeed = smartSeed,
                        probeFor = { text -> probeForTarget(app, text) },
                        payloadFor = { text ->
                            buildForTarget(app, source, payloadText, xorKey, useGzip, text)
                        },
                        framing = framing, method = method,
                        rules = TraceRule.parse(rulesText),
                        payloadNamed = { name ->
                            val item = app.book.items.value
                                .firstOrNull { it.name == name }
                            if (item == null) {
                                null
                            } else {
                                try {
                                    PayloadKit.build(
                                        source = item.source,
                                        text = if (item.source == "text") {
                                            item.text
                                        } else {
                                            ""
                                        },
                                        hex = if (item.source == "hex") {
                                            item.text
                                        } else {
                                            ""
                                        },
                                        b64 = if (item.source == "base64") {
                                            item.text
                                        } else {
                                            ""
                                        },
                                        xorSpec = item.xorKey,
                                        useGzip = item.useGzip
                                    )
                                } catch (_: Exception) {
                                    null
                                }
                            }
                        }
                    )
                },
                enabled = !talkBusy && hopCount > 0,
                modifier = Modifier.fillMaxWidth()
            ) { Text("Release the centipede ($hopCount hop(s))") }
        }
        for (line in lines) MonoText(line)
        if (findings.isNotEmpty()) {
            Text(
                "Harvest — what the doors said",
                style = MaterialTheme.typography.titleSmall
            )
            for (finding in findings) MonoText(finding)
        }
        homecoming?.let { home ->
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF263238))) {
                Column(modifier = Modifier.padding(10.dp)) {
                    Text(
                        "What it brought home — ${home.size} bytes",
                        style = MaterialTheme.typography.titleSmall
                    )
                    PayloadKit.printableText(home)?.let { MonoText(it.take(400)) }
                    MonoText(
                        PayloadKit.hexdump(home.copyOf(minOf(home.size, 128)))
                    )
                }
            }
        }
    }
}

@Composable
fun NetworkTraceSection(app: NightjarApp) {
    val prefs = rememberPrefs()
    val open = prefBool(prefs, "sectionOpen.trace", false)
    var scopeText by prefString(prefs, "traceScope", "")
    var discoveryPorts by prefString(
        prefs, "traceDiscoveryPorts", "80,443,22,445,1883,8080,8443,9100"
    )
    var profilePorts by prefString(prefs, "traceProfilePorts", "")
    var useBonjour by prefBool(prefs, "traceBonjour", true)
    var adaptive by prefBool(prefs, "traceAdaptive", true)
    var rulesText by prefString(prefs, "traceRules", "")
    val tracer = app.tracer
    val busy by tracer.busy.collectAsState()
    val lines by tracer.lines.collectAsState()
    val status by tracer.status.collectAsState()
    val export by tracer.latestExport.collectAsState()
    val crawlBusy by app.crawl.crawlBusy.collectAsState()
    val talkBusy by app.crawl.talkBusy.collectAsState()

    CollapsibleSection("Network trace", open) {
        Text(
            "Map one /24 end to end: knock every address on the " +
                "discovery ports, profile whatever answers, speak " +
                "each open door's library protocol, and follow the " +
                "in-scope addresses the replies themselves name — " +
                "three hops deep — until the frontier is exhausted " +
                "and the run stops on its own. Anything outside the " +
                "scope is written down, never contacted. Every door " +
                "is remembered in the logbook, and the run files a " +
                "JSON map built for other tools to read.",
            style = MaterialTheme.typography.bodySmall
        )
        OutlinedTextField(
            value = scopeText,
            onValueChange = { scopeText = it },
            label = { Text("Scope (blank = this phone's /24)") },
            modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontFamily = FontFamily.Monospace
            )
        )
        OutlinedTextField(
            value = discoveryPorts,
            onValueChange = { discoveryPorts = it },
            label = { Text("Discovery ports — knocked on all 254 addresses") },
            modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontFamily = FontFamily.Monospace
            )
        )
        OutlinedTextField(
            value = profilePorts,
            onValueChange = { profilePorts = it },
            label = { Text("Profile ports (blank = the Scan tab's usual ports)") },
            modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontFamily = FontFamily.Monospace
            )
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Listen for Bonjour while tracing")
            Switch(checked = useBonjour, onCheckedChange = { useBonjour = it })
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Adaptive rules steer the probes")
            Switch(checked = adaptive, onCheckedChange = { adaptive = it })
        }
        if (adaptive) {
            OutlinedTextField(
                value = rulesText,
                onValueChange = { rulesText = it },
                label = { Text("Adaptive rules (shared with the Centipede)") },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
                textStyle = MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = FontFamily.Monospace
                )
            )
        }
        if (busy) {
            Button(
                onClick = { tracer.stop() },
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                ),
                modifier = Modifier.fillMaxWidth()
            ) { Text("Stop the trace") }
        } else {
            Button(
                onClick = {
                    tracer.start(
                        scopeText = scopeText,
                        discoveryPorts = discoveryPorts,
                        profilePorts = profilePorts,
                        includeBonjour = useBonjour,
                        adaptive = adaptive,
                        rules = TraceRule.parse(rulesText),
                        probeFor = { text -> probeForTarget(app, text) },
                        payloadNamed = { name ->
                            val item = app.book.items.value
                                .firstOrNull { it.name == name }
                            if (item == null) {
                                null
                            } else {
                                try {
                                    PayloadKit.build(
                                        source = item.source,
                                        text = if (item.source == "text") {
                                            item.text
                                        } else {
                                            ""
                                        },
                                        hex = if (item.source == "hex") {
                                            item.text
                                        } else {
                                            ""
                                        },
                                        b64 = if (item.source == "base64") {
                                            item.text
                                        } else {
                                            ""
                                        },
                                        xorSpec = item.xorKey,
                                        useGzip = item.useGzip
                                    )
                                } catch (_: Exception) {
                                    null
                                }
                            }
                        }
                    )
                },
                enabled = !crawlBusy && !talkBusy,
                modifier = Modifier.fillMaxWidth()
            ) { Text("Trace the network") }
        }
        if (status.isNotEmpty()) {
            Text(status, style = MaterialTheme.typography.bodySmall)
        }
        for (line in lines.takeLast(80)) MonoText(line)
        export?.let { file ->
            OutlinedButton(
                onClick = { shareFile(app, file) },
                modifier = Modifier.fillMaxWidth()
            ) { Text("Share the trace map (${file.name})") }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = { shareFile(app, app.traceStore.file) },
                modifier = Modifier.weight(1f)
            ) { Text("Share logbook") }
            OutlinedButton(
                onClick = {
                    app.traceStore.clear()
                    app.mouth.toast("Trace logbook cleared")
                },
                modifier = Modifier.weight(1f)
            ) { Text("Clear logbook") }
        }
    }
}

@Composable
fun CrosstalkSection(
    app: NightjarApp, source: String, payloadText: String,
    xorKey: String, useGzip: Boolean
) {
    val prefs = rememberPrefs()
    val open = prefBool(prefs, "sectionOpen.crosstalk", false)
    var talkA by prefString(prefs, "talkTargetA", "")
    var talkB by prefString(prefs, "talkTargetB", "")
    var rounds by prefInt(prefs, "talkRounds", 4)
    val crawl = app.crawl
    val busy by crawl.talkBusy.collectAsState()
    val crawlBusy by crawl.crawlBusy.collectAsState()
    val lines by crawl.talkLines.collectAsState()
    val lastWord by crawl.talkHomecoming.collectAsState()

    fun serveDoor(a: Boolean) {
        val ip = app.mouth.localIPAddress()
        if (ip == null) {
            app.mouth.toast("No Wi-Fi address on this phone", error = true)
            return
        }
        val text = "tcp://$ip:${prefs.string("serveTcpPort", "9000")}"
        if (a) talkA = text else talkB = text
    }

    CollapsibleSection("Crosstalk", open) {
        Text(
            "Patch two doors together and let them talk: A is knocked " +
                "(its port's probe under smart seed), its reply carried " +
                "verbatim to B, B's back to A — until silence, an echo, " +
                "a repeat, or the rounds run out.",
            style = MaterialTheme.typography.bodySmall
        )
        OutlinedTextField(
            value = talkA, onValueChange = { talkA = it },
            label = { Text("Door A — tcp://host:port, phone:Name, https://…") },
            modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontFamily = FontFamily.Monospace
            )
        )
        OutlinedTextField(
            value = talkB, onValueChange = { talkB = it },
            label = { Text("Door B — the other door") },
            modifier = Modifier.fillMaxWidth(),
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontFamily = FontFamily.Monospace
            )
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { serveDoor(true) }) { Text("Serve as A") }
            OutlinedButton(onClick = { serveDoor(false) }) { Text("Serve as B") }
            OutlinedButton(onClick = {
                val swap = talkA
                talkA = talkB
                talkB = swap
            }) { Text("Swap ⇄") }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Rounds: $rounds")
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedButton(onClick = { if (rounds > 1) rounds -= 1 }) {
                    Text("−")
                }
                OutlinedButton(onClick = { if (rounds < 12) rounds += 1 }) {
                    Text("+")
                }
            }
        }
        if (busy) {
            Button(
                onClick = { crawl.stopTalk() },
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                ),
                modifier = Modifier.fillMaxWidth()
            ) { Text("Hang up") }
        } else {
            Button(
                onClick = {
                    val smartSeed = prefs.bool("centipedeSmartSeed", true)
                    crawl.startTalk(
                        aText = talkA, bText = talkB, rounds = rounds,
                        seed = buildForTarget(
                            app, source, payloadText, xorKey, useGzip, talkA
                        ) ?: ByteArray(0),
                        smartSeed = smartSeed,
                        probeFor = { text -> probeForTarget(app, text) }
                    )
                },
                enabled = !crawlBusy && talkA.isNotBlank() && talkB.isNotBlank(),
                modifier = Modifier.fillMaxWidth()
            ) { Text("Start the conversation") }
        }
        for (line in lines) MonoText(line)
        lastWord?.let { word ->
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF263238))) {
                Column(modifier = Modifier.padding(10.dp)) {
                    Text(
                        "The last word — ${word.size} bytes",
                        style = MaterialTheme.typography.titleSmall
                    )
                    PayloadKit.printableText(word)?.let { MonoText(it.take(400)) }
                    MonoText(
                        PayloadKit.hexdump(word.copyOf(minOf(word.size, 128)))
                    )
                }
            }
        }
    }
}

@Composable
fun SnatchSection(
    app: NightjarApp, target: String, buildPayload: () -> ByteArray?
) {
    val prefs = rememberPrefs()
    val open = prefBool(prefs, "sectionOpen.snatch", false)
    var knock by prefBool(prefs, "snatchKnock", true)
    val busy by app.engines.snatchBusy.collectAsState()
    val bytes by app.engines.snatchBytes.collectAsState()
    val result by app.engines.snatchResult.collectAsState()
    CollapsibleSection("SnatchSteal", open) {
        Text(
            "Knock on the step-1 target, then take everything it sends " +
                "back — full drain, not the scanner's polite banner peek. " +
                "The haul is saved to history.",
            style = MaterialTheme.typography.bodySmall
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Knock first (the step-2 payload)")
            Switch(checked = knock, onCheckedChange = { knock = it })
        }
        Button(
            onClick = {
                val parsed = try {
                    SendTarget.parse(target)
                } catch (_: Exception) {
                    null
                }
                if (parsed == null) {
                    app.mouth.toast("SnatchSteal needs a TCP target", error = true)
                } else {
                    app.engines.snatch(parsed, if (knock) buildPayload() else null)
                }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (busy) "Snatching… $bytes bytes so far" else "Snatch from $target")
        }
        result?.let { (label, data) ->
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF263238))) {
                Column(modifier = Modifier.padding(10.dp)) {
                    Text(
                        "$label — ${data.size} bytes",
                        style = MaterialTheme.typography.titleSmall
                    )
                    PayloadKit.printableText(data)?.let { MonoText(it.take(400)) }
                    MonoText(PayloadKit.hexdump(data.copyOf(minOf(data.size, 128))))
                }
            }
        }
    }
}

@Composable
fun PayPlantSection(app: NightjarApp, target: String, payloadText: String) {
    val prefs = rememberPrefs()
    val open = prefBool(prefs, "sectionOpen.plant", false)
    var service by prefString(prefs, "plantService", "redis")
    var key by prefString(prefs, "plantKey", "nightjar")
    var value by prefString(prefs, "plantValue", "")
    val lastPlant by app.engines.lastPlant.collectAsState()
    CollapsibleSection("PayPlant", open) {
        Text(
            "Store the step-2 payload in a service that keeps it: an " +
                "MQTT retained message, a Redis SET, a memcached set. " +
                "Verify reads it back and compares.",
            style = MaterialTheme.typography.bodySmall
        )
        PickerRow("Service", service, listOf("mqtt", "redis", "memcached")) {
            service = it
        }
        OutlinedTextField(
            value = key, onValueChange = { key = it },
            label = { Text(if (service == "mqtt") "Topic" else "Key") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = value,
            onValueChange = { value = it },
            label = { Text("Value (blank = the step-2 payload text)") },
            modifier = Modifier.fillMaxWidth()
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = {
                    val parsed = try {
                        SendTarget.parse(target)
                    } catch (_: Exception) {
                        null
                    }
                    if (parsed == null) {
                        app.mouth.toast("PayPlant needs a TCP target in step 1", error = true)
                    } else {
                        app.engines.plant(
                            service, parsed, key,
                            value.ifEmpty { payloadText }
                        )
                    }
                },
                modifier = Modifier.weight(1f)
            ) { Text("Plant at $target") }
            OutlinedButton(
                onClick = { app.engines.verifyPlant() },
                enabled = lastPlant != null
            ) { Text("Verify") }
        }
        lastPlant?.let {
            Text(
                "Last plant: ${it.service} · ${it.key} @ ${it.target.raw}",
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}
