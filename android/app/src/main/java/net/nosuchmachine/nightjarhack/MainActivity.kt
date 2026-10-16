package net.nosuchmachine.nightjarhack

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Face
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import coil.compose.rememberAsyncImagePainter
import kotlinx.coroutines.delay
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as NightjarApp
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                AppRoot(app)
            }
        }
    }
}

@Composable
fun appBackdrop() {
    val painter = rememberAsyncImagePainter(model = "file:///android_asset/background.jpg")
    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        Image(
            painter = painter, contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop
        )
        Box(
            modifier = Modifier.fillMaxSize()
                .background(Color.Black.copy(alpha = 0.62f))
        )
    }
}

@Composable
fun AppRoot(app: NightjarApp) {
    var tab by remember { mutableIntStateOf(0) }
    var showBoot by remember { mutableStateOf(true) }
    val snackbar = remember { SnackbarHostState() }
    val mouth = app.mouth
    val toast by mouth.toasts.collectAsState()

    LaunchedEffect(toast) {
        toast?.let {
            snackbar.showSnackbar(it.first)
            mouth.clearToast()
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { app.post.refreshBluetoothState() }
    LaunchedEffect(Unit) {
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            permissions += Manifest.permission.BLUETOOTH_SCAN
            permissions += Manifest.permission.BLUETOOTH_CONNECT
            permissions += Manifest.permission.BLUETOOTH_ADVERTISE
        } else {
            permissions += Manifest.permission.ACCESS_FINE_LOCATION
        }
        if (Build.VERSION.SDK_INT >= 33) {
            permissions += Manifest.permission.POST_NOTIFICATIONS
        }
        permissionLauncher.launch(permissions.toTypedArray())
        app.post.refreshBluetoothState()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        appBackdrop()
        Scaffold(
            containerColor = Color.Transparent,
            snackbarHost = { SnackbarHost(snackbar) },
            bottomBar = {
                NavigationBar(containerColor = Color(0xCC121212)) {
                    val items = listOf(
                        Triple("Listen", Icons.Filled.Face, 0),
                        Triple("Send", Icons.Filled.Send, 1),
                        Triple("Serve", Icons.Filled.Email, 2),
                        Triple("Scan", Icons.Filled.Search, 3),
                        Triple("Sessions", Icons.Filled.List, 4),
                        Triple("More", Icons.Filled.MoreVert, 5)
                    )
                    for ((label, icon, index) in items) {
                        NavigationBarItem(
                            selected = tab == index,
                            onClick = { tab = index },
                            icon = { androidx.compose.material3.Icon(icon, label) },
                            label = { Text(label) }
                        )
                    }
                }
            }
        ) { padding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                when (tab) {
                    0 -> ListenTab(app, goToSend = { tab = 1 })
                    1 -> SendTab(app)
                    2 -> ServeTab(app)
                    3 -> ScanTab(app)
                    4 -> SessionsTab(app)
                    else -> AboutTab(app)
                }
            }
        }
        if (showBoot) {
            BootSplash(app) { showBoot = false }
        }
    }
}

/// The OS-style boot splash — Jolly Roger, wordmark, real
/// boot lines, progress, tap to skip. Same theatre as iOS.
@Composable
fun BootSplash(app: NightjarApp, onDone: () -> Unit) {
    var progress by remember { mutableStateOf(0f) }
    LaunchedEffect(Unit) {
        val started = System.currentTimeMillis()
        while (System.currentTimeMillis() - started < 2000) {
            progress = (System.currentTimeMillis() - started) / 2000f
            delay(50)
        }
        onDone()
    }
    val ip = remember { app.mouth.localIPAddress() }
    val bookCount by app.book.items.collectAsState()
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .clickable { onDone() },
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Image(
                painter = painterResource(R.mipmap.ic_launcher),
                contentDescription = "nightjar-hack",
                modifier = Modifier.height(120.dp)
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "nightjar-hack",
                style = MaterialTheme.typography.headlineMedium,
                color = Color.White
            )
            Text(
                "// android",
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = FontFamily.Monospace
                ),
                color = Color(0xFF7FD1C0)
            )
            Spacer(Modifier.height(24.dp))
            Column(modifier = Modifier.padding(horizontal = 48.dp)) {
                MonoText("[ ok ] host ${Build.MANUFACTURER} ${Build.MODEL}")
                MonoText("[ ok ] net ${ip ?: "no address"}")
                MonoText("[ ok ] library ${bookCount.size} payloads loaded")
                MonoText("[ ok ] bluetooth ${if (app.post.bluetoothOn.value) "ready" else "pending"}")
            }
            Spacer(Modifier.height(24.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth(0.6f)
                    .height(3.dp)
                    .background(Color.DarkGray)
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(progress)
                        .height(3.dp)
                        .background(Color(0xFF7FD1C0))
                )
            }
        }
    }
}

// MARK: - Listen tab

@Composable
fun ListenTab(app: NightjarApp, goToSend: () -> Unit) {
    val post = app.post
    val rows by post.rows.collectAsState()
    val listening by post.isListening.collectAsState()
    val session by post.session.collectAsState()
    val bluetoothOn by post.bluetoothOn.collectAsState()
    val deviceCount by post.deviceCount.collectAsState()
    val sightingCount by post.sightingCount.collectAsState()
    val error by post.lastError.collectAsState()
    val prefs = rememberPrefs()
    var label by prefString(prefs, "listenLabel", "")
    var selectedId by remember { mutableStateOf<String?>(null) }
    var now by remember { mutableStateOf(ListeningPost.nowSeconds()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(1000)
            now = ListeningPost.nowSeconds()
        }
    }

    val selectedRow = rows.firstOrNull { it.id == selectedId }
    if (selectedRow != null) {
        DeviceDetail(app, selectedRow, now, onBack = { selectedId = null }, goToSend)
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Listen", style = MaterialTheme.typography.headlineSmall)
                Text(
                    when {
                        !bluetoothOn -> "Bluetooth is off"
                        listening -> "Listening — receive-only"
                        else -> "Bluetooth ready"
                    },
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                error?.let {
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
                if (listening) {
                    Text(
                        "${session?.label?.let { l -> "@ $l" } ?: "unlabelled session"} · " +
                            "$deviceCount addresses · $sightingCount sightings",
                        style = MaterialTheme.typography.bodySmall
                    )
                    Button(
                        onClick = { post.stop() },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error
                        ),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Stop and save")
                    }
                } else {
                    OutlinedTextField(
                        value = label,
                        onValueChange = { label = it },
                        label = { Text("Place label (optional, e.g. home)") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Button(
                        onClick = { post.start(label) },
                        enabled = bluetoothOn,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        androidx.compose.material3.Icon(
                            Icons.Filled.PlayArrow, contentDescription = null
                        )
                        Text("Start listening")
                    }
                }
                if (rows.isNotEmpty() || listening) {
                    Text(
                        if (listening) "In earshot" else "Last session",
                        style = MaterialTheme.typography.titleMedium
                    )
                }
            }
        }
        items(rows, key = { it.id }) { row ->
            DeviceRowCard(
                row = row, now = now,
                onClick = { selectedId = row.id },
                onWrite = {
                    app.ble.requestWrite(row.id, row.preferredLabel ?: row.kind)
                    app.mouth.toast("Write target set: ${row.preferredLabel ?: row.kind} — Send tab")
                    goToSend()
                }
            )
        }
        if (rows.isEmpty() && listening) {
            item { Text("Listening… nothing heard yet.") }
        }
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun DeviceRowCard(row: DeviceRow, now: Double, onClick: () -> Unit, onWrite: () -> Unit) {
    val quiet = row.age(now) > 20
    Card(
        colors = CardDefaults.cardColors(
            containerColor = Color(0xD91E1E1E)
        ),
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick, onLongClick = onWrite)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    row.label + if (row.trackerShaped) " 🏷" else "",
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    (row.rssiLast?.let { "$it dBm" } ?: "? dBm") + " " + row.trendArrow,
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontFamily = FontFamily.Monospace
                    )
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    subtitleOf(row),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    ageText(row.age(now).toInt()),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            row.details.firstOrNull()?.let {
                Text(
                    it, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                metaLineOf(row),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                row.id,
                style = MaterialTheme.typography.bodySmall.copy(
                    fontFamily = FontFamily.Monospace
                ),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (quiet) {
                Text("(quiet — dimmed in the iOS list)", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

fun subtitleOf(row: DeviceRow): String {
    val parts = mutableListOf<String>()
    if (row.name != null) parts.add(row.kind)
    parts.add(row.rangeBand)
    row.distanceMeters?.let { d ->
        parts.add(if (d < 10) "≈%.1f m".format(d) else "≈%.0f m".format(d))
    }
    return parts.joinToString(" · ")
}

fun metaLineOf(row: DeviceRow): String {
    val parts = mutableListOf("×${row.sightings} heard")
    row.rssiClosest?.let { parts.add("closest $it dBm") }
    if (row.rotatingAddress) parts.add("rotating address")
    return parts.joinToString(" · ")
}

@Composable
fun DeviceDetail(
    app: NightjarApp, snapshot: DeviceRow, now: Double,
    onBack: () -> Unit, goToSend: () -> Unit
) {
    val rows by app.post.rows.collectAsState()
    val row = rows.firstOrNull { it.id == snapshot.id } ?: snapshot
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            OutlinedButton(onClick = onBack) { Text("‹ In earshot") }
            Spacer(Modifier.height(8.dp))
            Text(row.label, style = MaterialTheme.typography.headlineSmall)
            Text(row.kind, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (row.trackerShaped) {
                Text(
                    "🏷 Tracker-shaped — separated Find My broadcasts",
                    color = Color(0xFFFFA500)
                )
            }
            if (row.rotatingAddress) {
                Text("⟳ Rotating address — a phone-style private address")
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Heard as", style = MaterialTheme.typography.titleMedium)
                    if (row.details.isEmpty()) {
                        Text("No decoded details — the broadcast carried nothing the decoders read.")
                    }
                    for (detail in row.details) Text(detail)
                    if (row.makers.isNotEmpty()) {
                        FactRow("Maker", row.makers.sorted().joinToString(", "))
                    }
                }
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Signal", style = MaterialTheme.typography.titleMedium)
                    FactRow("Last", row.rssiLast?.let { "$it dBm" } ?: "—")
                    FactRow("Smoothed", row.rssiSmooth?.let { "%.0f dBm".format(it) } ?: "—")
                    FactRow("Closest ever", row.rssiClosest?.let { "$it dBm" } ?: "—")
                    FactRow("TX power", row.txPowerLast?.let { "$it dBm" } ?: "not advertised")
                    FactRow(
                        "Estimated range",
                        row.distanceMeters?.let { d ->
                            (if (d < 10) "≈%.1f m".format(d) else "≈%.0f m".format(d)) +
                                " (${row.rangeBand})"
                        } ?: "—"
                    )
                    FactRow("Trend", row.trend ?: "—")
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "RSSI history — last ${row.rssiHistory.size} sightings",
                        style = MaterialTheme.typography.bodySmall
                    )
                    Sparkline(row.rssiHistory)
                }
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Timing", style = MaterialTheme.typography.titleMedium)
                    FactRow("First heard", clockTime(row.firstSeen))
                    FactRow("Last heard", clockTime(row.lastSeen))
                    FactRow("Age", ageText(row.age(now).toInt()))
                    FactRow("Dwell", durationText(row.dwell))
                    FactRow("Sightings", row.sightings.toString())
                    if (row.sightingsPerMinute > 0) {
                        FactRow("Rate", "%.1f / min".format(row.sightingsPerMinute))
                    }
                }
            }
        }
        if (row.serviceUUIDs.isNotEmpty()) {
            item {
                Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Text("Services advertised", style = MaterialTheme.typography.titleMedium)
                        for (uuid in row.serviceUUIDs) MonoText(shortUUID(uuid))
                    }
                }
            }
        }
        item {
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Identifier", style = MaterialTheme.typography.titleMedium)
                    MonoText(row.id)
                    Text(
                        "Android reports the real MAC address. A rotating-address device returns under a new one when its address rolls.",
                        style = MaterialTheme.typography.bodySmall
                    )
                    Spacer(Modifier.height(8.dp))
                    Button(
                        onClick = {
                            app.ble.requestWrite(row.id, row.preferredLabel ?: row.kind)
                            app.mouth.toast("Write target set — Send tab")
                            goToSend()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Write a payload…") }
                }
            }
        }
    }
}

@Composable
fun Sparkline(history: List<Int>) {
    val accent = Color(0xFF7FD1C0)
    Canvas(
        modifier = Modifier.fillMaxWidth().height(36.dp).padding(top = 4.dp)
    ) {
        if (history.isEmpty()) return@Canvas
        val barWidth = size.width / (history.size * 1.6f)
        history.forEachIndexed { index, value ->
            val h = maxOf(2f, (value + 100) / 60f * size.height)
            drawRect(
                color = accent,
                topLeft = Offset(index * barWidth * 1.6f, size.height - h),
                size = Size(barWidth, h)
            )
        }
    }
}

fun clockTime(epochSeconds: Double): String {
    val format = java.text.SimpleDateFormat("h:mm:ss a", java.util.Locale.US)
    return format.format(java.util.Date((epochSeconds * 1000).toLong()))
}

fun durationText(seconds: Double): String {
    val s = seconds.toInt()
    return when {
        s < 60 -> "${s}s"
        s < 3600 -> "${s / 60}m ${s % 60}s"
        else -> "${s / 3600}h ${s / 60 % 60}m"
    }
}

fun shortUUID(uuid: String): String {
    val suffix = "-0000-1000-8000-00805f9b34fb"
    if (uuid.length == 36 && uuid.startsWith("0000") && uuid.endsWith(suffix)) {
        return "0x" + uuid.substring(4, 8).uppercase()
    }
    return uuid
}

// MARK: - Sessions tab

@Composable
fun SessionsTab(app: NightjarApp) {
    var files by remember { mutableStateOf(listSessionFiles(app)) }
    var history by remember { mutableStateOf(app.mouth.readHistory()) }
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text("Sessions", style = MaterialTheme.typography.headlineSmall)
            Text(
                "Each listening session is a .jsonl file in upstream nightjar's format — feed it to `nightjar report` / `nightjar trackers` on a computer.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (files.isEmpty()) {
            item { Text("No sessions yet. Start one on the Listen tab.") }
        }
        items(files, key = { it.absolutePath }) { file ->
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(file.name, style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "${file.length()} bytes · " +
                            java.text.SimpleDateFormat(
                                "MMM d, h:mm a", java.util.Locale.US
                            ).format(java.util.Date(file.lastModified())),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = {
                            shareFile(app, file)
                        }) { Text("Share") }
                        OutlinedButton(onClick = {
                            file.delete()
                            files = listSessionFiles(app)
                        }) { Text("Delete") }
                    }
                }
            }
        }
        item {
            Spacer(Modifier.height(8.dp))
            Text("Send/serve history", style = MaterialTheme.typography.titleMedium)
            Text(
                "${history.size} exchange(s) in exchanges.jsonl",
                style = MaterialTheme.typography.bodySmall
            )
            OutlinedButton(onClick = {
                app.mouth.clearHistory()
                history = emptyList()
            }) { Text("Clear history") }
        }
        items(history.take(100)) { entry ->
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xD91E1E1E))) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        "${entry.optString("kind")} · ${entry.optString("label")}",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    val replyText = entry.optString("reply_text", "")
                    if (replyText.isNotEmpty()) {
                        MonoText(replyText.take(200))
                    } else if (entry.has("reply_b64")) {
                        Text(
                            "reply: ${entry.optString("reply_b64").length / 4 * 3} bytes (base64 in the file)",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    Text(
                        "sent ${entry.optInt("sent")} B",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

fun listSessionFiles(app: NightjarApp): List<File> {
    val dir = ListeningPost.sessionsDir(app.applicationContext)
    return dir.listFiles { f -> f.extension == "jsonl" }
        ?.sortedByDescending { it.lastModified() } ?: emptyList()
}

fun shareFile(app: NightjarApp, file: File) {
    val context = app.applicationContext
    try {
        val uri = androidx.core.content.FileProvider.getUriForFile(
            context, context.packageName + ".files", file
        )
        val intent = android.content.Intent(android.content.Intent.ACTION_SEND)
            .setType("application/json")
            .putExtra(android.content.Intent.EXTRA_STREAM, uri)
            .addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(
            android.content.Intent.createChooser(intent, "Share session")
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    } catch (e: Exception) {
        app.mouth.toast("Share failed: ${e.message}", error = true)
    }
}

// MARK: - About tab

@Composable
fun AboutTab(app: NightjarApp) {
    val ip = app.mouth.localIPAddress()
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("nightjar-hack", style = MaterialTheme.typography.headlineSmall)
                Text(
                    "Version ${BuildConfig.VERSION_NAME} (Android port)",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    "The unpure build: the nightjar listening post plus a mouth — " +
                        "send and serve payload tooling over TCP, UDP, TLS, HTTP(S) " +
                        "and Bluetooth LE."
                )
                FactRow("This phone", ip?.let { "reachable on the LAN at $it" } ?: "no LAN address")
                FactRow("Package", "net.nosuchmachine.nightjarhack")
                Spacer(Modifier.height(8.dp))
                Text(
                    "Authorized use",
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    "nightjar-hack is for testing networks and devices you own or " +
                        "are authorized to test. Listening is passive; everything " +
                        "the mouth sends goes only where you aim it.",
                    style = MaterialTheme.typography.bodyMedium
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    "One Android difference worth knowing: Android shows real " +
                        "Bluetooth MAC addresses (iOS hides them behind per-host " +
                        "UUIDs), so Listen rows here carry the actual address.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
