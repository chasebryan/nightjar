package net.nosuchmachine.nightjarhack

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/// Build the step-2 payload for a target text — substitution
/// (text source only) + build, the SendView.build path.
fun buildForTarget(
    app: NightjarApp, source: String, payloadText: String,
    xorKey: String, useGzip: Boolean, targetText: String
): ByteArray? {
    val target = try {
        SendTarget.parse(targetText)
    } catch (_: Exception) {
        null
    }
    val text = if (source == "text" && target != null) {
        PayloadKit.substitute(payloadText, target, app.mouth.localIPAddress())
    } else {
        payloadText
    }
    return try {
        PayloadKit.build(
            source = source,
            text = text,
            hex = if (source == "hex") payloadText else "",
            b64 = if (source == "base64") payloadText else "",
            xorSpec = xorKey, useGzip = useGzip
        )
    } catch (_: Exception) {
        null
    }
}

/// The smart seed: a target's port probe from the library,
/// exactly as the iOS probeForTarget resolves it.
fun probeForTarget(app: NightjarApp, targetText: String): Pair<ByteArray, String>? {
    val parsed = try {
        SendTarget.parse(targetText)
    } catch (_: Exception) {
        return null
    }
    val port = when (parsed) {
        is SendTarget.Tcp -> parsed.port
        is SendTarget.Udp -> parsed.port
        else -> return null
    }
    val name = ScanKit.payloadByPort[port] ?: return null
    val item = app.book.items.value.firstOrNull { it.name == name } ?: return null
    val data = try {
        PayloadKit.build(
            source = item.source,
            text = if (item.source == "text") item.text else "",
            hex = if (item.source == "hex") item.text else "",
            b64 = if (item.source == "base64") item.text else "",
            xorSpec = item.xorKey, useGzip = item.useGzip
        )
    } catch (_: Exception) {
        return null
    }
    return data to name
}

@Composable
fun SendTab(app: NightjarApp) {
    val mouth = app.mouth
    val prefs = rememberPrefs()
    var target by prefString(prefs, "sendTarget", "tcp://127.0.0.1:9000")
    var source by prefString(prefs, "payloadSource", "text")
    var payloadText by prefString(prefs, "payloadText", "hello")
    var xorKey by prefString(prefs, "payloadXor", "")
    var useGzip by prefBool(prefs, "payloadGzip", false)
    var framing by prefString(prefs, "payloadFraming", "raw")
    var method by prefString(prefs, "httpMethod", "POST")
    var readReply by prefBool(prefs, "readReply", true)
    val lastReply by mouth.lastReply.collectAsState()
    val sendLines by mouth.sendLines.collectAsState()
    val nearbyPhones by app.serve.nearbyPhones.collectAsState()
    val writeTarget by app.ble.writeTarget.collectAsState()
    val beaconOn by app.ble.beaconOn.collectAsState()
    val hosting by app.ble.hosting.collectAsState()
    var showSplash by remember { mutableStateOf(false) }
    var recents by prefString(prefs, "recentTargets", "")

    // Scan → Send handoff: a tapped scan result lands here.
    val handoff by app.sendHandoff.collectAsState()
    val handoffPayload by app.sendHandoffPayload.collectAsState()
    LaunchedEffect(handoff) {
        handoff?.let {
            target = it
            app.sendHandoff.value = null
        }
    }
    LaunchedEffect(handoffPayload) {
        handoffPayload?.let { name ->
            val item = app.book.items.value.firstOrNull { p -> p.name == name }
            if (item != null) {
                source = item.source
                payloadText = item.text
                xorKey = item.xorKey
                useGzip = item.useGzip
                framing = item.framing
            }
            app.sendHandoffPayload.value = null
        }
    }

    fun builtPayload(): ByteArray? =
        buildForTarget(app, source, payloadText, xorKey, useGzip, target)

    fun noteRecent(text: String) {
        val list = (listOf(text) + recents.split("\n").filter { it.isNotBlank() && it != text })
            .take(6)
        recents = list.joinToString("\n")
    }

    fun doSend() {
        val payload = builtPayload()
        if (payload == null) {
            mouth.toast("Could not build the payload", error = true)
            return
        }
        noteRecent(target)
        when {
            target.startsWith("phone:") -> {
                val phone = app.serve.resolvePhone(target.removePrefix("phone:"))
                if (phone == null) {
                    mouth.toast("That phone isn't in earshot (Serve discovery)", error = true)
                } else {
                    mouth.sendNetwork(
                        SendTarget.Tcp(phone.host, phone.port, false),
                        payload, framing, readReply
                    ) { ok -> if (ok) mouth.toast("Sent to ${phone.name}") }
                }
            }
            target.trim() == "ble://" -> {
                if (beaconOn) app.ble.stopBeacon()
                else if (app.ble.startBeacon(payload)) mouth.toast("Beacon on — FFF0 service data")
            }
            target.trim() == "ble-gatt://" -> {
                if (hosting) app.ble.stopHosting()
                else {
                    app.ble.startHosting(payload)
                    mouth.toast("Hosting FFF0/FFF1 — writes land in the Serve inbox")
                }
            }
            target.startsWith("ble-write://") -> {
                val address = target.removePrefix("ble-write://").substringBefore('/')
                app.ble.writeToDevice(address, payload) { ok ->
                    mouth.toast(if (ok) "Wrote to $address" else "BLE write failed",
                        error = !ok)
                }
            }
            else -> {
                val parsed = try {
                    SendTarget.parse(target)
                } catch (_: Exception) {
                    mouth.toast("Could not parse the target", error = true)
                    return
                }
                when (parsed) {
                    is SendTarget.Http -> mouth.sendHTTP(parsed, payload, framing, method) { ok ->
                        if (ok) mouth.toast("HTTP sent")
                    }
                    is SendTarget.Tcp, is SendTarget.Udp ->
                        mouth.sendNetwork(parsed, payload, framing, readReply) { ok ->
                            if (ok) mouth.toast("Sent ${payload.size} bytes to ${parsed.raw}")
                        }
                    else -> mouth.toast("That target is handled above", error = true)
                }
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Text("Send", style = MaterialTheme.typography.headlineSmall)
            }
            // Step 1 — target
            item {
                Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text("Step 1 · Target", style = MaterialTheme.typography.titleMedium)
                        OutlinedTextField(
                            value = target,
                            onValueChange = { target = it },
                            label = { Text("tcp://host:port, udp://, https://, phone:Name, ble://…") },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = MaterialTheme.typography.bodyMedium.copy(
                                fontFamily = FontFamily.Monospace
                            )
                        )
                        if (nearbyPhones.isNotEmpty()) {
                            Text("Nearby phones", style = MaterialTheme.typography.bodySmall)
                            for (phone in nearbyPhones) {
                                OutlinedButton(
                                    onClick = { target = "phone:${phone.name}" },
                                    modifier = Modifier.fillMaxWidth()
                                ) { Text("📱 ${phone.name} — ${phone.host}:${phone.port}") }
                            }
                        }
                        writeTarget?.let { (address, label) ->
                            OutlinedButton(
                                onClick = { target = "ble-write://$address" },
                                modifier = Modifier.fillMaxWidth()
                            ) { Text("Write target from Listen: $label ($address)") }
                        }
                        val recentList = recents.split("\n").filter { it.isNotBlank() }
                        if (recentList.isNotEmpty()) {
                            Text("Recent", style = MaterialTheme.typography.bodySmall)
                            for (recent in recentList) {
                                Text(
                                    recent,
                                    modifier = Modifier
                                        .clickable { target = recent }
                                        .padding(vertical = 2.dp),
                                    style = MaterialTheme.typography.bodySmall.copy(
                                        fontFamily = FontFamily.Monospace
                                    ),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
            // Step 2 — payload
            item {
                PayloadEditor(
                    app, source = source, onSource = { source = it },
                    payloadText = payloadText, onText = { payloadText = it },
                    xorKey = xorKey, onXor = { xorKey = it },
                    useGzip = useGzip, onGzip = { useGzip = it },
                    framing = framing, onFraming = { framing = it },
                    targetText = target
                )
            }
            // Step 3 — send
            item {
                Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text("Step 3 · Send", style = MaterialTheme.typography.titleMedium)
                        if (target.startsWith("http")) {
                            PickerRow("Method", method, listOf("GET", "POST", "PUT", "DELETE", "HEAD")) {
                                method = it
                            }
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("Read a reply")
                            Switch(checked = readReply, onCheckedChange = { readReply = it })
                        }
                        val preview = builtPayload()
                        Text(
                            preview?.let { "Will send ${it.size} bytes · framing $framing" }
                                ?: "Payload does not build — check the source",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Button(
                            onClick = { doSend() },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                when {
                                    target.trim() == "ble://" && beaconOn -> "Stop beacon"
                                    target.trim() == "ble-gatt://" && hosting -> "Stop hosting"
                                    else -> "Send to $target"
                                }
                            )
                        }
                        lastReply?.let { reply ->
                            Spacer(Modifier.height(4.dp))
                            Text(
                                "Last reply · ${reply.label}",
                                style = MaterialTheme.typography.titleSmall
                            )
                            PayloadKit.printableText(reply.data)?.let {
                                MonoText(it.take(400))
                            }
                            MonoText(
                                PayloadKit.hexdump(reply.data.copyOf(minOf(reply.data.size, 128)))
                            )
                        }
                    }
                }
            }
            // Send to many
            item {
                FanOutSection(app, source, payloadText, xorKey, useGzip, framing, readReply)
            }
            // Timed delivery
            item {
                TimedSection(
                    app,
                    buildPayload = { builtPayload() },
                    target = target, framing = framing,
                    readReply = readReply, method = method
                )
            }
            // Centipede
            item {
                CentipedeSection(app, source, payloadText, xorKey, useGzip,
                    framing, method) { showSplash = true }
            }
            // Network trace
            item { NetworkTraceSection(app) }
            // Crosstalk
            item { CrosstalkSection(app, source, payloadText, xorKey, useGzip) }
            // SnatchSteal
            item { SnatchSection(app, target) { builtPayload() } }
            // PayPlant
            item { PayPlantSection(app, target, payloadText) }
            // Log
            item {
                Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("Log", style = MaterialTheme.typography.titleMedium)
                            OutlinedButton(onClick = { mouth.clearSendLog() }) {
                                Text("Clear")
                            }
                        }
                        for (line in sendLines.takeLast(60)) MonoText(line)
                    }
                }
            }
        }
        if (showSplash) {
            CentipedeSplash { showSplash = false }
        }
    }
}

@Composable
fun PickerRow(
    label: String, value: String, options: List<String>,
    onPick: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label)
        Box {
            OutlinedButton(onClick = { expanded = true }) { Text(value) }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                for (option in options) {
                    DropdownMenuItem(
                        text = { Text(option) },
                        onClick = {
                            onPick(option)
                            expanded = false
                        }
                    )
                }
            }
        }
    }
}

@Composable
fun PayloadEditor(
    app: NightjarApp,
    source: String, onSource: (String) -> Unit,
    payloadText: String, onText: (String) -> Unit,
    xorKey: String, onXor: (String) -> Unit,
    useGzip: Boolean, onGzip: (Boolean) -> Unit,
    framing: String, onFraming: (String) -> Unit,
    targetText: String
) {
    val book by app.book.items.collectAsState()
    var libraryOpen by remember { mutableStateOf(false) }
    var saveName by remember { mutableStateOf("") }
    Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("Step 2 · Payload", style = MaterialTheme.typography.titleMedium)
                OutlinedButton(onClick = { libraryOpen = !libraryOpen }) {
                    Text("Library (${book.size})")
                }
            }
            if (libraryOpen) {
                for (item in book) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onSource(item.source)
                                onText(item.text)
                                onXor(item.xorKey)
                                onGzip(item.useGzip)
                                onFraming(item.framing)
                                libraryOpen = false
                            }
                            .padding(vertical = 4.dp),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(item.name)
                        Text(
                            item.source,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = saveName,
                        onValueChange = { saveName = it },
                        label = { Text("Save current as…") },
                        modifier = Modifier.weight(1f)
                    )
                    OutlinedButton(onClick = {
                        if (saveName.isNotBlank()) {
                            app.book.add(
                                SavedPayload(
                                    saveName, source, payloadText,
                                    xorKey, useGzip, framing
                                )
                            )
                            saveName = ""
                        }
                    }) { Text("Save") }
                }
                OutlinedButton(onClick = { app.book.restoreBuiltIns() }) {
                    Text("Restore built-ins")
                }
            }
            PickerRow("Source", source, listOf("text", "hex", "base64"), onSource)
            OutlinedTextField(
                value = payloadText,
                onValueChange = onText,
                label = { Text("Payload ({{host}} {{port}} {{ip}} {{target}} {{scheme}} in text)") },
                modifier = Modifier.fillMaxWidth(),
                minLines = 2
            )
            OutlinedTextField(
                value = xorKey,
                onValueChange = onXor,
                label = { Text("XOR key (optional)") },
                modifier = Modifier.fillMaxWidth()
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text("gzip")
                Switch(checked = useGzip, onCheckedChange = onGzip)
            }
            PickerRow("Framing", framing, listOf("raw", "len", "json"), onFraming)
        }
    }
}

@Composable
fun FanOutSection(
    app: NightjarApp, source: String, payloadText: String,
    xorKey: String, useGzip: Boolean, framing: String, readReply: Boolean
) {
    val prefs = rememberPrefs()
    val open = prefBool(prefs, "sectionOpen.fanout", false)
    var lines by prefString(prefs, "fanoutLines", "")
    CollapsibleSection("Send to many", open) {
        Text(
            "One payload, every line a target (ranges and trains expand).",
            style = MaterialTheme.typography.bodySmall
        )
        OutlinedTextField(
            value = lines,
            onValueChange = { lines = it },
            label = { Text("Targets, one per line") },
            modifier = Modifier.fillMaxWidth(),
            minLines = 3,
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontFamily = FontFamily.Monospace
            )
        )
        Button(
            onClick = {
                val raw = lines.split("\n")
                val resolved = raw.map { line ->
                    val trimmed = line.trim()
                    if (trimmed.startsWith("phone:")) {
                        val phone = app.serve.resolvePhone(trimmed.removePrefix("phone:"))
                        if (phone != null) "tcp://${phone.host}:${phone.port}" else trimmed
                    } else {
                        trimmed
                    }
                }
                app.mouth.sendToMany(
                    resolved,
                    payloadFor = { text ->
                        buildForTarget(app, source, payloadText, xorKey, useGzip, text)
                    },
                    framing = framing, read = readReply
                )
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Send to all") }
    }
}

@Composable
fun TimedSection(
    app: NightjarApp,
    buildPayload: () -> ByteArray?,
    target: String, framing: String, readReply: Boolean, method: String
) {
    val prefs = rememberPrefs()
    val open = prefBool(prefs, "sectionOpen.timing", false)
    var delayText by prefString(prefs, "timingDelay", "0")
    var intervalText by prefString(prefs, "timingInterval", "10")
    var countText by prefString(prefs, "timingCount", "3")
    val running by app.engines.scheduleRunning.collectAsState()
    CollapsibleSection("Timed delivery", open) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(
                value = delayText, onValueChange = { delayText = it },
                label = { Text("Delay s") }, modifier = Modifier.weight(1f)
            )
            OutlinedTextField(
                value = intervalText, onValueChange = { intervalText = it },
                label = { Text("Every s") }, modifier = Modifier.weight(1f)
            )
            OutlinedTextField(
                value = countText, onValueChange = { countText = it },
                label = { Text("Count") }, modifier = Modifier.weight(1f)
            )
        }
        if (running) {
            Button(
                onClick = { app.engines.stopSchedule() },
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                ),
                modifier = Modifier.fillMaxWidth()
            ) { Text("Cancel timed delivery") }
        } else {
            Button(
                onClick = {
                    val parsed = try {
                        SendTarget.parse(target)
                    } catch (_: Exception) {
                        null
                    }
                    if (parsed == null || parsed is SendTarget.Http && false) {
                        app.mouth.toast("Timed delivery needs a network target", error = true)
                        return@Button
                    }
                    app.engines.startSchedule(
                        delayText.toIntOrNull() ?: 0,
                        intervalText.toIntOrNull() ?: 10,
                        (countText.toIntOrNull() ?: 1).coerceIn(1, 100)
                    ) {
                        val payload = buildPayload()
                            ?: return@startSchedule false
                        suspendCancellableCoroutine { cont ->
                            when (parsed) {
                                is SendTarget.Http -> app.mouth.sendHTTP(
                                    parsed, payload, framing, method
                                ) { ok -> cont.resume(ok) }
                                is SendTarget.Tcp, is SendTarget.Udp ->
                                    app.mouth.sendNetwork(
                                        parsed, payload, framing, readReply
                                    ) { ok -> cont.resume(ok) }
                                else -> cont.resume(false)
                            }
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) { Text("Schedule sends to $target") }
        }
    }
}

@Composable
fun CentipedeSplash(onDone: () -> Unit) {
    LaunchedEffect(Unit) {
        delay(2300)
        onDone()
    }
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .clickable { onDone() }
    ) {
        AsyncImage(
            model = "file:///android_asset/centipede.gif",
            contentDescription = "CENTIPEDE RELEASED",
            modifier = Modifier.fillMaxSize(),
            contentScale = androidx.compose.ui.layout.ContentScale.FillBounds
        )
    }
}
