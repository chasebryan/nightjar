package net.nosuchmachine.nightjarhack

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/// The Knocktalk tab's other carriers — sound, proximity,
/// light, recognition, and time — mirroring the sections of
/// the iOS KnockChatView. Every one of them carries the
/// same sealed box as a knock; only the road differs.

/// One door for chirps, however they arrived — sung live,
/// or decoded from a mailed file.
fun openChirpPayload(chat: KnockChat, data: ByteArray): Boolean {
    val key = KnockKeyStore.key ?: return false
    for (suite in listOf(
        Knocktalk.SUITE_CHACHA, Knocktalk.SUITE_AESGCM)) {
        val text = Knocktalk.open(data, key, suite)
        if (text != null) {
            chat.receiveChirp(text)
            return true
        }
    }
    return false
}

/// A blink names its suite in every frame; open with the
/// carried suite first, the other second.
fun openBlinkPayload(
    chat: KnockChat, data: ByteArray, suite: Int
): Boolean {
    val key = KnockKeyStore.key ?: return false
    val order = if (suite == Knocktalk.SUITE_AESGCM) {
        listOf(Knocktalk.SUITE_AESGCM, Knocktalk.SUITE_CHACHA)
    } else {
        listOf(Knocktalk.SUITE_CHACHA, Knocktalk.SUITE_AESGCM)
    }
    for (candidate in order) {
        val text = Knocktalk.open(data, key, candidate)
        if (text != null) {
            chat.receiveBlink(text)
            return true
        }
    }
    return false
}

@Composable
fun ChirpSection(app: NightjarApp, hasKey: Boolean) {
    val chat = app.knockChat
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val sender = remember { ChirpSender() }
    val listener = remember { ChirpListener() }
    val singing by sender.singing.collectAsState()
    val progress by sender.progress.collectAsState()
    val listening by listener.listening.collectAsState()
    val listenerStatus by listener.status.collectAsState()
    var draft by remember { mutableStateOf("") }
    var wavFile by remember { mutableStateOf<File?>(null) }
    var fileNote by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        listener.onPayload = { data ->
            openChirpPayload(chat, data)
        }
    }

    val micLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) listener.start()
    }
    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            fileNote = "decoding…"
            scope.launch {
                val payload = withContext(Dispatchers.IO) {
                    try {
                        val copy = File(
                            context.cacheDir,
                            "chirp-import-${System.currentTimeMillis()}")
                        context.contentResolver
                            .openInputStream(uri)?.use { input ->
                                copy.outputStream().use { output ->
                                    input.copyTo(output)
                                }
                            }
                        ChirpMail.decode(copy)
                    } catch (_: Exception) {
                        null
                    }
                }
                fileNote = if (payload != null) {
                    if (openChirpPayload(chat, payload)) {
                        "decoded — filed in the Chirp thread below"
                    } else {
                        "that file carries a chirp that does " +
                            "not open with your pairing key"
                    }
                } else {
                    "no complete chirp heard in that file"
                }
            }
        }
    }

    val tooLong = draft.toByteArray(Charsets.UTF_8).size + 28 >
        ChirpModem.MAX_PAYLOAD

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosSectionHeader("Chirp — messages by sound")
        IosPanelCard {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (hasKey) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = draft,
                            onValueChange = { draft = it },
                            label = { Text("sing a short message") },
                            modifier = Modifier.weight(1f))
                        Button(
                            onClick = {
                                val key = KnockKeyStore.key
                                if (key != null) {
                                    val sealed = try {
                                        Knocktalk.seal(
                                            draft, key,
                                            chat.sendSuite.value)
                                    } catch (_: Exception) {
                                        null
                                    }
                                    if (sealed != null) {
                                        sender.sing(sealed)
                                        draft = ""
                                    }
                                }
                            },
                            enabled = draft.isNotEmpty() && !tooLong &&
                                !singing
                        ) { Text("Sing") }
                    }
                    if (tooLong) {
                        Text(
                            "Too long for sound — chirps carry " +
                                "about 90 characters.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.Error)
                    }
                    if (singing) {
                        LinearProgressIndicator(
                            progress = { progress.toFloat() },
                            modifier = Modifier.fillMaxWidth())
                        OutlinedButton(onClick = { sender.stop() }) {
                            Text("Stop singing")
                        }
                    }
                    Button(
                        onClick = {
                            if (listening) {
                                listener.stop()
                            } else if (ContextCompat
                                    .checkSelfPermission(
                                        context,
                                        Manifest.permission.RECORD_AUDIO
                                    ) == PackageManager.PERMISSION_GRANTED
                            ) {
                                listener.start()
                            } else {
                                micLauncher.launch(
                                    Manifest.permission.RECORD_AUDIO)
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            if (listening) {
                                "Stop listening"
                            } else {
                                "Listen for a chirp"
                            })
                    }
                    if (listening || listenerStatus != "idle") {
                        Text(
                            listenerStatus,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                    OutlinedButton(
                        onClick = {
                            val key = KnockKeyStore.key
                            if (key != null) {
                                val sealed = try {
                                    Knocktalk.seal(
                                        draft, key,
                                        chat.sendSuite.value)
                                } catch (_: Exception) {
                                    null
                                }
                                if (sealed != null) {
                                    scope.launch {
                                        val file = withContext(
                                            Dispatchers.IO) {
                                            ChirpMail.export(
                                                sealed, context.cacheDir)
                                        }
                                        wavFile = file
                                        fileNote = if (file == null) {
                                            "the .wav would not render"
                                        } else {
                                            "rendered — share it " +
                                                "through anything " +
                                                "that moves audio; " +
                                                "it decodes on arrival"
                                        }
                                        if (file != null) draft = ""
                                    }
                                }
                            }
                        },
                        enabled = draft.isNotEmpty() && !tooLong,
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Sing it to a file instead") }
                    wavFile?.let { file ->
                        OutlinedButton(
                            onClick = {
                                val uri = FileProvider.getUriForFile(
                                    context,
                                    "${context.packageName}.files",
                                    file)
                                val share = Intent(Intent.ACTION_SEND)
                                    .setType("audio/wav")
                                    .putExtra(Intent.EXTRA_STREAM, uri)
                                    .addFlags(
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                context.startActivity(
                                    Intent.createChooser(
                                        share, "Share the chirp"))
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Share the chirp (.wav)") }
                    }
                    OutlinedButton(
                        onClick = {
                            importLauncher.launch(arrayOf("audio/*"))
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Decode a chirp file…") }
                    fileNote?.let { note ->
                        Text(
                            note,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                } else {
                    Text(
                        "Set up a pairing key above — chirps are " +
                            "sealed with it, exactly like knocks.",
                        color = IosColors.SecondaryLabel)
                }
                Text(
                    "The same sealed box as a knock, sung as " +
                        "tones: speaker to microphone, no " +
                        "network, no radio — it works in " +
                        "airplane mode. Short messages only " +
                        "(sound is a narrow pipe), and keep " +
                        "this tab open while listening. Heard " +
                        "chirps land in a thread named chirp.",
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
            }
        }
    }
}

@Composable
fun BrushSection(
    app: NightjarApp, prefs: Prefs, hasKey: Boolean
) {
    val chat = app.knockChat
    val context = LocalContext.current
    val visitor = remember { BrushVisitor(context, prefs) }
    val hunting by visitor.hunting.collectAsState()
    val visitorStatus by visitor.status.collectAsState()
    val hosting by app.ble.hosting.collectAsState()
    var draft by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        visitor.onPayload = { data ->
            val key = KnockKeyStore.key
            var opened = false
            if (key != null) {
                for (suite in listOf(
                    Knocktalk.SUITE_CHACHA,
                    Knocktalk.SUITE_AESGCM)) {
                    val text = Knocktalk.open(data, key, suite)
                    if (text != null) {
                        chat.receiveBrush(text)
                        Journal.log(
                            "brush", "pickup",
                            "drop opened — ${text.length} chars")
                        opened = true
                        break
                    }
                }
            }
            opened
        }
    }

    val tooLong = draft.toByteArray(Charsets.UTF_8).size + 28 >
        Knocktalk.maxSealedBytes

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosSectionHeader("Brush pass — the proximity drop")
        IosPanelCard {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (hasKey) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = draft,
                            onValueChange = { draft = it },
                            label = { Text("leave a short drop") },
                            modifier = Modifier.weight(1f))
                        Button(
                            onClick = {
                                val key = KnockKeyStore.key
                                if (key != null) {
                                    val sealed = try {
                                        Knocktalk.seal(
                                            draft, key,
                                            chat.sendSuite.value)
                                    } catch (_: Exception) {
                                        null
                                    }
                                    if (sealed != null) {
                                        app.ble.startHosting(sealed)
                                        draft = ""
                                    }
                                }
                            },
                            enabled = draft.isNotEmpty() && !tooLong
                        ) { Text("Arm drop") }
                    }
                    if (tooLong) {
                        Text(
                            "Too long for a drop — about 160 " +
                                "characters.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.Error)
                    }
                    if (hosting) {
                        Text(
                            "GATT host is up — a paired phone " +
                                "in range can take the drop. " +
                                "Stop hosting (Send tab) to " +
                                "disarm it.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                    Button(
                        onClick = {
                            if (hunting) {
                                visitor.stop()
                            } else {
                                visitor.start()
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            if (hunting) {
                                "Stop hunting"
                            } else {
                                "Hunt for a drop"
                            })
                    }
                    if (hunting || visitorStatus != "idle") {
                        Text(
                            visitorStatus,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                } else {
                    Text(
                        "Set up a pairing key above — drops are " +
                            "sealed with it, like everything " +
                            "else here.",
                        color = IosColors.SecondaryLabel)
                }
                Text(
                    "Leave a drop: seal a short message and " +
                        "arm this phone's GATT host with it. " +
                        "Anyone in Bluetooth range can read " +
                        "the sealed bytes; only the pairing " +
                        "key opens them. A paired phone that " +
                        "comes hunting files it in a thread " +
                        "named brush — and you never learn it " +
                        "was taken. EMCON stands the GATT host " +
                        "down, so a drop does not survive " +
                        "going dark.",
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
            }
        }
    }
}

@Composable
fun BlinkSection(app: NightjarApp, hasKey: Boolean) {
    val chat = app.knockChat
    var draft by remember { mutableStateOf("") }
    var frames by remember {
        mutableStateOf<List<String>>(emptyList())
    }
    var showSender by remember { mutableStateOf(false) }
    var showReceiver by remember { mutableStateOf(false) }

    val tooLong = draft.toByteArray(Charsets.UTF_8).size + 28 >
        Knocktalk.maxSealedBytes

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosSectionHeader("Blink — messages by light")
        IosPanelCard {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (hasKey) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = draft,
                            onValueChange = { draft = it },
                            label = { Text("blink a short message") },
                            modifier = Modifier.weight(1f))
                        Button(
                            onClick = {
                                val key = KnockKeyStore.key
                                if (key != null) {
                                    val sealed = try {
                                        Knocktalk.seal(
                                            draft, key,
                                            chat.sendSuite.value)
                                    } catch (_: Exception) {
                                        null
                                    }
                                    if (sealed != null) {
                                        frames = BlinkFraming.frames(
                                            sealed, chat.sendSuite.value)
                                        showSender = true
                                        draft = ""
                                    }
                                }
                            },
                            enabled = draft.isNotEmpty() && !tooLong
                        ) { Text("Show") }
                    }
                    if (tooLong) {
                        Text(
                            "Too long for light — about 160 " +
                                "characters.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.Error)
                    }
                    Button(
                        onClick = { showReceiver = true },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Receive a blink") }
                } else {
                    Text(
                        "Set up a pairing key above — blinks " +
                            "are sealed with it, like " +
                            "everything else here.",
                        color = IosColors.SecondaryLabel)
                }
                Text(
                    "The sealed box as a looping sequence of " +
                        "QR frames — for the room where even a " +
                        "chirp is too loud. The camera gathers " +
                        "frames until the set is whole; the " +
                        "loop forgives every miss. One-way, " +
                        "like sound: no acknowledgement rides " +
                        "the light back.",
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
            }
        }
    }

    if (showSender && frames.isNotEmpty()) {
        BlinkSenderDialog(
            frames = frames, onDone = { showSender = false })
    }
    if (showReceiver) {
        BlinkReceiverDialog(
            app = app, onDone = { showReceiver = false })
    }
}

@Composable
private fun BlinkSenderDialog(
    frames: List<String>, onDone: () -> Unit
) {
    var index by remember(frames) { mutableStateOf(0) }
    LaunchedEffect(frames) {
        while (true) {
            kotlinx.coroutines.delay(500)
            index = (index + 1) % frames.size
        }
    }
    val bitmap = remember(frames, index) {
        BlinkFraming.qrBitmap(frames[index])
    }
    androidx.compose.ui.window.Dialog(onDismissRequest = onDone) {
        IosPanelCard {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    "Blink",
                    style = MaterialTheme.typography.titleMedium)
                bitmap?.let {
                    androidx.compose.foundation.Image(
                        bitmap = it.asImageBitmap(),
                        contentDescription = "Blink frame",
                        modifier = Modifier.fillMaxWidth(),
                        filterQuality =
                            androidx.compose.ui.graphics.FilterQuality.None)
                }
                Text(
                    "frame ${index + 1} of ${frames.size} — looping",
                    style = MaterialTheme.typography.bodyMedium)
                Text(
                    "Hold this screen to the other phone's " +
                        "camera. The sequence repeats until " +
                        "every frame is caught — a missed " +
                        "frame is just a later frame.",
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
                Button(
                    onClick = onDone,
                    modifier = Modifier.fillMaxWidth()
                ) { Text("Done") }
            }
        }
    }
}

private class QrAnalyzer(
    private val onText: (String) -> Unit
) : androidx.camera.core.ImageAnalysis.Analyzer {
    private val reader = com.google.zxing.qrcode.QRCodeReader()

    override fun analyze(
        image: androidx.camera.core.ImageProxy
    ) {
        try {
            val plane = image.planes[0]
            val buffer = plane.buffer
            val data = ByteArray(buffer.remaining())
            buffer.get(data)
            val source = com.google.zxing.PlanarYUVLuminanceSource(
                data, plane.rowStride, image.height,
                0, 0, image.width, image.height, false)
            val bitmap = com.google.zxing.BinaryBitmap(
                com.google.zxing.common.HybridBinarizer(source))
            try {
                onText(reader.decode(bitmap).text)
            } catch (_: Exception) {
                // No code in this frame — the loop forgives.
            }
        } catch (_: Exception) {
        } finally {
            image.close()
        }
    }
}

@Composable
private fun BlinkReceiverDialog(
    app: NightjarApp, onDone: () -> Unit
) {
    val chat = app.knockChat
    val context = LocalContext.current
    val lifecycleOwner =
        androidx.lifecycle.compose.LocalLifecycleOwner.current
    val receiver = remember { BlinkReceiver() }
    val status by receiver.status.collectAsState()
    val got by receiver.got.collectAsState()
    val want by receiver.want.collectAsState()
    var granted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED)
    }
    val cameraLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { ok -> granted = ok }

    LaunchedEffect(Unit) {
        receiver.onPayload = { data, suite ->
            openBlinkPayload(chat, data, suite)
        }
        if (!granted) {
            cameraLauncher.launch(Manifest.permission.CAMERA)
        }
    }
    LaunchedEffect(granted) {
        if (granted) receiver.start()
    }
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose { receiver.stop() }
    }

    androidx.compose.ui.window.Dialog(onDismissRequest = onDone) {
        IosPanelCard {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    "Receive a blink",
                    style = MaterialTheme.typography.titleMedium)
                if (granted) {
                    val previewView = remember {
                        androidx.camera.view.PreviewView(context)
                    }
                    LaunchedEffect(previewView) {
                        val providerFuture = androidx.camera
                            .lifecycle.ProcessCameraProvider
                            .getInstance(context)
                        providerFuture.addListener({
                            val provider = providerFuture.get()
                            val preview = androidx.camera.core
                                .Preview.Builder().build()
                            preview.setSurfaceProvider(
                                previewView.surfaceProvider)
                            val analysis = androidx.camera.core
                                .ImageAnalysis.Builder()
                                .setBackpressureStrategy(
                                    androidx.camera.core
                                        .ImageAnalysis
                                        .STRATEGY_KEEP_ONLY_LATEST)
                                .build()
                            analysis.setAnalyzer(
                                java.util.concurrent.Executors
                                    .newSingleThreadExecutor(),
                                QrAnalyzer { text ->
                                    receiver.onQr(text)
                                })
                            provider.unbindAll()
                            provider.bindToLifecycle(
                                lifecycleOwner,
                                androidx.camera.core.CameraSelector
                                    .DEFAULT_BACK_CAMERA,
                                preview, analysis)
                        }, ContextCompat.getMainExecutor(context))
                    }
                    androidx.compose.ui.viewinterop.AndroidView(
                        factory = { previewView },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp))
                }
                if (want > 0) {
                    Text(
                        "frames: $got of $want",
                        style = MaterialTheme.typography.bodyMedium)
                }
                Text(
                    status,
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
                Button(
                    onClick = onDone,
                    modifier = Modifier.fillMaxWidth()
                ) { Text("Done") }
            }
        }
    }
}

@Composable
fun FlareSection(app: NightjarApp, hasKey: Boolean) {
    val flareOn by app.ble.flareOn.collectAsState()

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosSectionHeader("Flare — be recognized, by key-holders only")
        IosPanelCard {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (hasKey) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement =
                            Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Raise my flare")
                        Switch(
                            checked = flareOn,
                            onCheckedChange = { on ->
                                val key = KnockKeyStore.key
                                if (on && key != null) {
                                    app.ble.startFlare(key)
                                } else {
                                    app.ble.stopFlare()
                                }
                            })
                    }
                    if (flareOn) {
                        Text(
                            "On the air. Holders of this key, " +
                                "listening now, can see it.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                } else {
                    Text(
                        "Set up a pairing key above — a flare " +
                            "is computed from it.",
                        color = IosColors.SecondaryLabel)
                }
                Text(
                    "With the flare up, this phone's beacon " +
                        "slot carries a token only the " +
                        "pairing key can compute — it turns " +
                        "over every five minutes and names " +
                        "nobody. A paired phone listening sees " +
                        "a flame beside the row in Listen and " +
                        "knows one of ours is near. It outranks " +
                        "a plain payload beacon for the slot " +
                        "while it's up, and EMCON takes it " +
                        "down like any other emission.",
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
            }
        }
    }
}

@Composable
fun CapsuleSection(app: NightjarApp, hasKey: Boolean) {
    val chat = app.knockChat
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val clipboard =
        androidx.compose.ui.platform.LocalClipboardManager.current
    var draft by remember { mutableStateOf("") }
    var delaySeconds by remember { mutableStateOf(600.0) }
    var busy by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("") }
    var blob by remember { mutableStateOf<String?>(null) }
    var paste by remember { mutableStateOf("") }
    var progress by remember { mutableStateOf<Double?>(null) }
    var note by remember { mutableStateOf("") }
    var grindControl by remember {
        mutableStateOf(TimeCapsule.GrindControl())
    }

    val tooLong = draft.toByteArray(Charsets.UTF_8).size + 28 >
        Knocktalk.maxSealedBytes

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosSectionHeader(
            "Time capsule — sealed until the grinding is done")
        IosPanelCard {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (hasKey) {
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        label = {
                            Text("seal a message into the future")
                        },
                        modifier = Modifier.fillMaxWidth())
                    Text("Hold for")
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        for ((seconds, label) in listOf(
                            30.0 to "30 seconds (test it)",
                            600.0 to "10 minutes",
                            3600.0 to "an hour",
                            21600.0 to "6 hours")) {
                            FilterChip(
                                selected = delaySeconds == seconds,
                                onClick = { delaySeconds = seconds },
                                label = { Text(label) })
                        }
                    }
                    Button(
                        onClick = {
                            val text = draft
                            val hold = delaySeconds
                            val suite = chat.sendSuite.value
                            busy = true
                            status = "Working…"
                            scope.launch {
                                val sealed = withContext(
                                    Dispatchers.IO) {
                                    TimeCapsule.seal(
                                        text, hold, suite) { line ->
                                        scope.launch {
                                            status = line
                                        }
                                    }
                                }
                                busy = false
                                status = ""
                                blob = sealed
                                if (sealed != null) draft = ""
                            }
                        },
                        enabled = draft.isNotEmpty() && !busy &&
                            !tooLong,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(if (busy) "Sealing…" else "Seal the capsule")
                    }
                    if (tooLong) {
                        Text(
                            "Too long — capsules carry what a " +
                                "Knocktalk message carries.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.Error)
                    }
                    if (status.isNotEmpty()) {
                        Text(
                            status,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                    blob?.let { sealed ->
                        Text(
                            sealed,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = androidx.compose.ui.text
                                .font.FontFamily.Monospace,
                            maxLines = 4)
                        Row(
                            horizontalArrangement =
                                Arrangement.spacedBy(8.dp)
                        ) {
                            OutlinedButton(onClick = {
                                val share = Intent(Intent.ACTION_SEND)
                                    .setType("text/plain")
                                    .putExtra(Intent.EXTRA_TEXT, sealed)
                                context.startActivity(
                                    Intent.createChooser(
                                        share, "Share capsule"))
                            }) { Text("Share capsule") }
                            OutlinedButton(onClick = {
                                clipboard.setText(
                                    androidx.compose.ui.text
                                        .AnnotatedString(sealed))
                            }) { Text("Copy") }
                        }
                    }
                    OutlinedTextField(
                        value = paste,
                        onValueChange = { paste = it },
                        label = { Text("paste a capsule to open") },
                        modifier = Modifier.fillMaxWidth())
                    val currentProgress = progress
                    if (currentProgress != null) {
                        LinearProgressIndicator(
                            progress = { currentProgress.toFloat() },
                            modifier = Modifier.fillMaxWidth())
                        OutlinedButton(onClick = {
                            grindControl.cancelled = true
                        }) { Text("Stop grinding") }
                    } else {
                        Button(
                            onClick = {
                                val target = paste
                                val control =
                                    TimeCapsule.GrindControl()
                                grindControl = control
                                progress = 0.0
                                note = "Grinding — the squarings " +
                                    "are sequential; that's the " +
                                    "lock working."
                                scope.launch {
                                    val text = withContext(
                                        Dispatchers.IO) {
                                        TimeCapsule.grind(
                                            target, control) { p ->
                                            scope.launch {
                                                progress = p
                                            }
                                        }
                                    }
                                    progress = null
                                    when {
                                        control.cancelled -> {
                                            note = "Grind stopped. " +
                                                "The capsule keeps " +
                                                "— grind it any " +
                                                "time; the work " +
                                                "restarts from the " +
                                                "first squaring."
                                        }
                                        text != null -> {
                                            chat.receiveCapsule(text)
                                            paste = ""
                                            note = "Opened — filed " +
                                                "in the capsule " +
                                                "thread below."
                                        }
                                        else -> {
                                            note = "That didn't " +
                                                "open — damaged " +
                                                "in transit, or " +
                                                "not a capsule."
                                        }
                                    }
                                }
                            },
                            enabled = paste.isNotEmpty(),
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Grind it open") }
                    }
                    if (note.isNotEmpty()) {
                        Text(
                            note,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                } else {
                    Text(
                        "Set up a pairing key above — capsules " +
                            "seal with the same suites as " +
                            "everything here.",
                        color = IosColors.SecondaryLabel)
                }
                Text(
                    "A message locked by repeated squaring, " +
                        "in the Magic Box manner: the sealer " +
                        "forges two primes, slips through the " +
                        "φ shortcut, and throws the factors " +
                        "away. After that, the only road in is " +
                        "the grind — sequential, " +
                        "unparallelizable, calibrated to this " +
                        "phone's pace. A lock delays; it does " +
                        "not schedule: anyone holding the " +
                        "capsule can start grinding now, and " +
                        "faster hardware finishes sooner. " +
                        "Carry the capsule by any means — the " +
                        "lock travels with it.",
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
            }
        }
    }
}
