package net.nosuchmachine.nightjarhack

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import kotlin.random.Random

/// The canary: a persona service.
///
/// The tripwire listens in silence and learns a prober's
/// first words. A canary goes one better: it ANSWERS, in
/// character — an SSH banner from a plausible Ubuntu box, a
/// web server that serves its little "It works!" page, an
/// MQTT broker that accepts the connection, a mail server
/// that plays along through MAIL FROM. Every byte the prober
/// then commits to the conversation is filed into the Serve
/// inbox as one transcript, through the same arrival funnel
/// as any other payload.
///
/// Deception pointed the defensive way: the persona exists
/// only on this phone, on a port the operator raises, and it
/// speaks only to whoever came knocking on it.
class CanaryHost(context: Context, private val serve: Serve) :
    Emcon.CanaryHook {

    private val prefs = Prefs(context.applicationContext)
    private val filesDir: File = context.applicationContext.filesDir
    private val scope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _runningPersona = MutableStateFlow<String?>(null)
    override val runningPersona: String?
        get() = _runningPersona.value
    val runningPersonaFlow: StateFlow<String?> = _runningPersona
    private val _runningPort = MutableStateFlow<Int?>(null)
    val runningPort: StateFlow<Int?> = _runningPort
    private val _dropArmed = MutableStateFlow(false)
    val dropArmed: StateFlow<Boolean> = _dropArmed
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    @Volatile private var serverSocket: ServerSocket? = null
    private val sessions = ConcurrentHashMap<Socket, Session>()
    @Volatile private var dropText = ""

    /// A taken drop reports here (the conductor's choke).
    var onHoneydropTaken: ((String) -> Unit)? = null

    companion object {
        val personas = listOf("ssh", "http", "mqtt", "smtp")

        fun defaultPort(persona: String): Int = when (persona) {
            "ssh" -> 22
            "http" -> 80
            "mqtt" -> 1883
            else -> 25
        }

        fun label(persona: String): String = when (persona) {
            "ssh" -> "SSH server"
            "http" -> "HTTP server"
            "mqtt" -> "MQTT broker"
            else -> "SMTP server"
        }

        /// The paths web probers reach for first — where the
        /// honeydrop waits when the phase is armed.
        val baitPaths = listOf(
            "/backup.zip", "/backup", "/.env", "/config.json",
            "/admin", "/db.sql", "/.git/config")
    }

    private class Session(val persona: String, val peer: String) {
        val transcript = ByteArrayOutputStream()
        var stage = 0
        var dropTaken = false
        var dropNote = ""
        var idleJob: Job? = null
        val writeLock = Any()

        /// Lessons already billed to this session, so a flow
        /// that re-enters the script per chunk bills once.
        val billedLessons = mutableSetOf<String>()

        fun bytes(): ByteArray = transcript.toByteArray()
    }

    override fun start(persona: String, port: Int,
                       honeydrop: Boolean, drop: String) {
        stop()
        _dropArmed.value = honeydrop
        dropText = drop
        val socket = ServerSocket()
        try {
            socket.reuseAddress = true
            socket.bind(InetSocketAddress(port))
        } catch (e: Exception) {
            _error.value = "the canary could not hold port " +
                "$port — the tripwire or Serve may already be " +
                "on it (${e.message})"
            _runningPersona.value = null
            _runningPort.value = null
            return
        }
        serverSocket = socket
        _runningPersona.value = persona
        _runningPort.value = port
        _error.value = null
        Journal.log(
            "canary", "start",
            "$persona canary up on port $port" +
                (if (honeydrop) " — honeydrop phase armed"
                 else ""))
        scope.launch {
            while (!socket.isClosed) {
                val client = try {
                    socket.accept()
                } catch (e: Exception) {
                    break
                }
                accept(client, persona)
            }
        }
    }

    override fun stop() {
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        for (socket in sessions.keys.toList()) finish(socket)
        if (_runningPersona.value != null) {
            Journal.log("canary", "stop", "canary down")
        }
        _dropArmed.value = false
        _runningPersona.value = null
        _runningPort.value = null
    }

    // MARK: - the honeydrop

    /// The drop a persona hands over when the honeydrop phase
    /// is armed: the operator's own text when they wrote one,
    /// otherwise the persona's stock lure. Every drop is a
    /// decoy — plausible to a prober, worthless in fact, and
    /// unique enough that taking it is unmistakable.
    private fun drop(forPersona: String): ByteArray {
        if (dropText.isNotEmpty()) {
            return dropText.toByteArray(Charsets.UTF_8)
        }
        return when (forPersona) {
            "http" -> ("APP_ENV=production\n" +
                "DB_HOST=db.internal\n" +
                "DB_NAME=app\n" +
                "DB_USER=backup_svc\n" +
                "BACKUP_DIR=/var/backups/nightly\n" +
                "BACKUP_FILE=db_dump_2026-10-15.sql.gz\n")
                .toByteArray(Charsets.UTF_8)
            "mqtt" -> ("{\"site\":\"home\",\"config\":" +
                "\"rev 41\",\"backup\":\"nas.internal:445\"}")
                .toByteArray(Charsets.UTF_8)
            "smtp" -> ("archive copy: https://mail.example.org" +
                "/archive/2026/10/msg-4471")
                .toByteArray(Charsets.UTF_8)
            else -> ByteArray(0)
        }
    }

    /// A taken drop is the loudest signal the canary produces:
    /// journaled as its own event the moment it happens, and
    /// stamped into the transcript when the session files.
    private fun takeDrop(session: Session, note: String) {
        if (session.dropTaken) return
        session.dropTaken = true
        session.dropNote = note
        Journal.log(
            "canary", "honeydrop",
            "drop taken by ${session.peer} — $note")
        onHoneydropTaken?.invoke(session.peer)
    }

    private fun ByteArrayOutputStream.writeIntBE(v: Int) {
        write(v ushr 24); write(v ushr 16); write(v ushr 8)
        write(v)
    }

    /// A correctly-framed SSH KEXINIT packet — the SSH
    /// persona's drop. A prober that parses it and answers
    /// with its own algorithm lists has taken the bait and
    /// told you exactly what it is.
    private fun sshKexInit(): ByteArray {
        fun nameList(names: List<String>): ByteArray {
            val joined = names.joinToString(",")
                .toByteArray(Charsets.UTF_8)
            val out = ByteArrayOutputStream()
            out.writeIntBE(joined.size)
            out.write(joined)
            return out.toByteArray()
        }
        val payload = ByteArrayOutputStream()
        payload.write(20)
        payload.write(ByteArray(16) { Random.nextInt(256).toByte() })
        payload.write(nameList(listOf(
            "curve25519-sha256", "diffie-hellman-group14-sha256")))
        payload.write(nameList(listOf("ssh-ed25519", "rsa-sha2-512")))
        payload.write(nameList(listOf(
            "chacha20-poly1305@openssh.com", "aes128-ctr")))
        payload.write(nameList(listOf(
            "chacha20-poly1305@openssh.com", "aes128-ctr")))
        payload.write(nameList(listOf("hmac-sha2-256", "hmac-sha1")))
        payload.write(nameList(listOf("hmac-sha2-256", "hmac-sha1")))
        payload.write(nameList(listOf("none")))
        payload.write(nameList(listOf("none")))
        payload.write(nameList(emptyList()))
        payload.write(nameList(emptyList()))
        payload.write(0)  // first_kex_packet_follows: false
        payload.writeIntBE(0)
        val payloadBytes = payload.toByteArray()
        var packetLength = payloadBytes.size + 1 + 4
        val remainder = (packetLength + 4) % 8
        if (remainder != 0) packetLength += 8 - remainder
        val padding = packetLength - payloadBytes.size - 1
        val packet = ByteArrayOutputStream()
        packet.writeIntBE(packetLength)
        packet.write(padding)
        packet.write(payloadBytes)
        packet.write(ByteArray(padding))
        return packet.toByteArray()
    }

    private fun accept(socket: Socket, persona: String) {
        val peer = "${socket.inetAddress.hostAddress}:${socket.port}"
        val session = Session(persona, peer)
        sessions[socket] = session
        when (persona) {
            "ssh" -> send(socket, session, (
                "SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.3\r\n")
                .toByteArray(Charsets.UTF_8))
            "smtp" -> send(socket, session, (
                "220 mail.example.org ESMTP Postfix (Ubuntu)\r\n")
                .toByteArray(Charsets.UTF_8))
            else -> {}
        }
        scope.launch { readLoop(socket, session) }
    }

    private fun readLoop(socket: Socket, session: Session) {
        val buffer = ByteArray(16384)
        try {
            val input = socket.getInputStream()
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                val chunk = buffer.copyOf(count)
                synchronized(session.transcript) {
                    session.transcript.write(chunk)
                }
                armIdleFlush(socket, session)
                script(socket, session, chunk)
            }
        } catch (_: Exception) {
        }
        finish(socket)
    }

    /// Paths the operator armed from the lessons — the catch
    /// taught the canary where else the drop should wait.
    private fun learnedPaths(): List<String> =
        prefs.string("canaryLearnedPaths", "")
            .split("\n").filter { it.isNotEmpty() }

    /// Bill a lesson to the catch, once per session per ask.
    private fun learn(session: Session, kind: String,
                      value: String) {
        val key = "$kind|$value"
        if (key in session.billedLessons) return
        session.billedLessons.add(key)
        CanaryLessons.record(filesDir, kind, value)
    }

    private fun ByteArray.u8(index: Int): Int =
        this[index].toInt() and 0xFF

    /// The persona scripts: just enough protocol to keep the
    /// prober talking. Everything they say is already captured;
    /// these replies exist so they keep saying it — and, with
    /// the honeydrop armed, so they reach for the prize.
    private fun script(socket: Socket, session: Session,
                       chunk: ByteArray) {
        when (session.persona) {
            "http" -> {
                if (session.stage != 0) return
                val text = String(session.bytes(), Charsets.UTF_8)
                if (!text.contains("\r\n\r\n")) return
                session.stage = 1
                val requestLine =
                    text.split("\r\n").firstOrNull() ?: ""
                val rawPath = requestLine.split(" ")
                    .drop(1).firstOrNull() ?: "/"
                val path = rawPath.split("?").firstOrNull()
                    ?: rawPath
                if (path != "/") {
                    learn(session, "http path", path)
                }
                if (_dropArmed.value &&
                    (path in baitPaths || path in learnedPaths())) {
                    val lure = drop("http")
                    val head = "HTTP/1.1 200 OK\r\n" +
                        "Server: Apache/2.4.57 (Ubuntu)\r\n" +
                        "Content-Type: text/plain\r\n" +
                        "Content-Length: ${lure.size}\r\n" +
                        "Connection: close\r\n\r\n"
                    send(socket, session,
                         head.toByteArray(Charsets.UTF_8) + lure)
                    takeDrop(session, "http GET $path")
                } else {
                    val body = "<html><body><h1>It works!</h1>" +
                        "</body></html>"
                    val head = "HTTP/1.1 200 OK\r\n" +
                        "Server: Apache/2.4.57 (Ubuntu)\r\n" +
                        "Content-Type: text/html\r\n" +
                        "Content-Length: " +
                        "${body.toByteArray(Charsets.UTF_8).size}\r\n" +
                        "Connection: close\r\n\r\n"
                    send(socket, session,
                         head.toByteArray(Charsets.UTF_8) +
                             body.toByteArray(Charsets.UTF_8))
                }
            }
            "mqtt" -> {
                // A lesson, parse-only: whatever topic they
                // reach for is worth knowing, armed or not.
                if (session.stage == 1 && chunk.isNotEmpty() &&
                    chunk.u8(0) == 0x82 && chunk.size >= 6) {
                    val topicLength =
                        (chunk.u8(4) shl 8) or chunk.u8(5)
                    if (chunk.size >= 6 + topicLength) {
                        val topic = String(
                            chunk.copyOfRange(6, 6 + topicLength),
                            Charsets.UTF_8)
                        learn(session, "mqtt topic", topic)
                    }
                }
                if (session.stage == 0 &&
                    session.bytes().isNotEmpty() &&
                    session.bytes().u8(0) == 0x10) {
                    session.stage = 1
                    send(socket, session,
                         byteArrayOf(0x20, 0x02, 0x00, 0x00))
                } else if (session.stage == 1 && _dropArmed.value &&
                    chunk.isNotEmpty() && chunk.u8(0) == 0x82 &&
                    chunk.size >= 6) {
                    // A SUBSCRIBE: grant it, then publish the
                    // drop on the very topic they asked about.
                    val packetId = chunk.copyOfRange(2, 4)
                    val topicLength =
                        (chunk.u8(4) shl 8) or chunk.u8(5)
                    if (chunk.size < 6 + topicLength) return
                    val topic = chunk.copyOfRange(6, 6 + topicLength)
                    val out = ByteArrayOutputStream()
                    out.write(byteArrayOf(0x90.toByte(), 0x03))
                    out.write(packetId)
                    out.write(0x00)
                    val lure = drop("mqtt")
                    val remaining = 2 + topicLength + lure.size
                    val publish = ByteArrayOutputStream()
                    publish.write(0x30)
                    var value = remaining
                    do {
                        var byte = value % 128
                        value /= 128
                        if (value > 0) byte = byte or 0x80
                        publish.write(byte)
                    } while (value > 0)
                    publish.write(topicLength shr 8)
                    publish.write(topicLength and 0xFF)
                    publish.write(topic)
                    publish.write(lure)
                    out.write(publish.toByteArray())
                    send(socket, session, out.toByteArray())
                    session.stage = 2
                    takeDrop(session, "mqtt subscribe — drop " +
                        "published on their topic")
                }
            }
            "smtp" -> {
                val text = String(chunk, Charsets.UTF_8)
                for (line in text.uppercase().split("\r\n")) {
                    when {
                        line.startsWith("EHLO") ||
                            line.startsWith("HELO") ->
                            send(socket, session, (
                                "250-mail.example.org\r\n" +
                                    "250-PIPELINING\r\n" +
                                    "250 8BITMIME\r\n")
                                .toByteArray(Charsets.UTF_8))
                        line.startsWith("MAIL FROM") ->
                            send(socket, session,
                                 "250 2.1.0 Ok\r\n"
                                     .toByteArray(Charsets.UTF_8))
                        line.startsWith("RCPT TO") ->
                            send(socket, session,
                                 "250 2.1.5 Ok\r\n"
                                     .toByteArray(Charsets.UTF_8))
                        line == "DATA" ->
                            send(socket, session, (
                                "354 End data with " +
                                    "<CR><LF>.<CR><LF>\r\n")
                                .toByteArray(Charsets.UTF_8))
                    }
                }
                // The completed message is the deepest
                // engagement this persona offers: answer it
                // like a real server, carrying the drop in
                // the receipt when armed.
                if (session.stage == 0) {
                    val all = String(session.bytes(), Charsets.UTF_8)
                    if (all.contains("\r\n.\r\n")) {
                        session.stage = 1
                        val subject = all.split("\r\n")
                            .firstOrNull {
                                it.lowercase().startsWith("subject:")
                            }
                        learn(
                            session, "smtp subject",
                            subject?.trim() ?: "a completed message")
                        if (_dropArmed.value) {
                            val receipt = drop("smtp")
                            send(socket, session,
                                 "250 2.0.0 Ok ".toByteArray(
                                     Charsets.UTF_8) + receipt +
                                     "\r\n".toByteArray(Charsets.UTF_8))
                            takeDrop(session, "smtp message " +
                                "completed — drop in the receipt")
                        } else {
                            send(socket, session,
                                 "250 2.0.0 Ok\r\n"
                                     .toByteArray(Charsets.UTF_8))
                        }
                    }
                }
            }
            "ssh" -> {
                // Their banner is the lesson — which client
                // stack bothered to knock — recorded armed
                // or not.
                val text = String(session.bytes(), Charsets.UTF_8)
                val firstLine =
                    text.split("\r\n").firstOrNull() ?: ""
                if (session.stage == 0 &&
                    firstLine.startsWith("SSH-")) {
                    learn(session, "ssh client", firstLine)
                }
                if (session.stage == 0 && _dropArmed.value &&
                    firstLine.startsWith("SSH-")) {
                    // They identified themselves; offer the
                    // prize: a real key-exchange opening.
                    session.stage = 1
                    send(socket, session, sshKexInit())
                } else if (session.stage == 1) {
                    // Any bytes after the KEXINIT are an
                    // answer to it — algorithm lists, a client
                    // speaking its whole stack to a box that
                    // does not exist.
                    takeDrop(session, "ssh prober answered " +
                        "the KEXINIT")
                }
            }
        }
    }

    private fun send(socket: Socket, session: Session,
                     data: ByteArray) {
        try {
            synchronized(session.writeLock) {
                val out = socket.getOutputStream()
                out.write(data)
                out.flush()
            }
        } catch (_: Exception) {
        }
    }

    private fun armIdleFlush(socket: Socket, session: Session) {
        session.idleJob?.cancel()
        session.idleJob = scope.launch {
            delay(20_000)
            finish(socket)
        }
    }

    private fun finish(socket: Socket) {
        val session = sessions.remove(socket) ?: return
        session.idleJob?.cancel()
        try {
            socket.close()
        } catch (_: Exception) {
        }
        var data = session.bytes()
        if (data.isEmpty()) return
        if (session.dropTaken) {
            data = ("[honeydrop taken — ${session.dropNote}]")
                .toByteArray(Charsets.UTF_8) +
                byteArrayOf(0x0A) + data
        }
        serve.injectCanaryArrival(session.persona, session.peer, data)
    }
}

/// One thing the catch taught the canary: a kind of ask, the
/// ask itself, and how often it has been made.
data class CanaryLesson(
    val kind: String,
    val value: String,
    val count: Int,
    val lastSeen: Double
) {
    val id: String get() = "$kind|$value"
}

/// The canary's notebook, kept at filesDir/canary-lessons.json
/// — small, capped, and erasable from the Serve tab.
object CanaryLessons {
    private fun file(filesDir: File): File =
        File(filesDir, "canary-lessons.json")

    fun record(filesDir: File, kind: String, value: String) {
        var all = load(filesDir).toMutableList()
        val index = all.indexOfFirst {
            it.kind == kind && it.value == value
        }
        if (index >= 0) {
            val old = all[index]
            all[index] = old.copy(
                count = old.count + 1,
                lastSeen = ListeningPost.nowSeconds())
        } else {
            all.add(CanaryLesson(
                kind, value, 1, ListeningPost.nowSeconds()))
        }
        if (all.size > 100) {
            all.sortByDescending { it.count }
            all = all.take(100).toMutableList()
        }
        save(filesDir, all)
    }

    fun all(filesDir: File): List<CanaryLesson> =
        load(filesDir).sortedByDescending { it.count }

    fun clear(filesDir: File) {
        try {
            file(filesDir).delete()
        } catch (_: Exception) {
        }
    }

    private fun load(filesDir: File): List<CanaryLesson> {
        return try {
            val array = JSONArray(file(filesDir).readText())
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                CanaryLesson(
                    obj.getString("kind"),
                    obj.getString("value"),
                    obj.getInt("count"),
                    obj.optDouble("lastSeen", 0.0))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun save(filesDir: File, lessons: List<CanaryLesson>) {
        try {
            val array = JSONArray()
            for (lesson in lessons) {
                array.put(JSONObject()
                    .put("kind", lesson.kind)
                    .put("value", lesson.value)
                    .put("count", lesson.count)
                    .put("lastSeen", lesson.lastSeen))
            }
            file(filesDir).writeText(array.toString())
        } catch (_: Exception) {
        }
    }
}

/// The Serve tab's canary controls.
@Composable
fun CanarySection(app: NightjarApp) {
    val prefs = rememberPrefs()
    val context = LocalContext.current
    var persona by prefString(prefs, "canaryPersona", "ssh")
    var port by prefString(prefs, "canaryPort", "22")
    var honeydrop by prefBool(prefs, "canaryHoneydrop", false)
    var drop by prefString(prefs, "canaryDrop", "")
    val host = app.canary
    val running by host.runningPersonaFlow.collectAsState()
    val runningPort by host.runningPort.collectAsState()
    val dropArmed by host.dropArmed.collectAsState()
    val error by host.error.collectAsState()
    var lessons by remember {
        mutableStateOf(CanaryLessons.all(context.filesDir))
    }
    var armedPaths by remember {
        mutableStateOf(
            prefs.string("canaryLearnedPaths", "")
                .split("\n").filter { it.isNotEmpty() })
    }
    var pickerOpen by remember { mutableStateOf(false) }

    // Keep the port honest: if it still holds another
    // persona's default, follow the persona.
    LaunchedEffect(persona) {
        val current = port.toIntOrNull() ?: -1
        if (CanaryHost.personas
                .map { CanaryHost.defaultPort(it) }
                .contains(current)) {
            port = CanaryHost.defaultPort(persona).toString()
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosPanelCard {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("Canary",
                     style = MaterialTheme.typography.titleMedium)
                Text(
                    "A persona answers whoever knocks, in " +
                        "character, and files everything they say " +
                        "into the inbox as one transcript. One " +
                        "canary at a time, and it cannot share a " +
                        "port with the tripwire or Serve. " +
                        "Honeydrop is the activate phase beyond " +
                        "answering: the persona carries a prize — " +
                        "a bait file, a published message, a " +
                        "receipt, a key exchange — and a prober " +
                        "who takes it is journaled on the spot.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement =
                        Arrangement.SpaceBetween
                ) {
                    Text("Persona")
                    Box {
                        OutlinedButton(
                            onClick = { pickerOpen = true }) {
                            Text(CanaryHost.label(persona))
                        }
                        DropdownMenu(
                            expanded = pickerOpen,
                            onDismissRequest = { pickerOpen = false }
                        ) {
                            for (p in CanaryHost.personas) {
                                DropdownMenuItem(
                                    text = {
                                        Text(CanaryHost.label(p))
                                    },
                                    onClick = {
                                        persona = p
                                        pickerOpen = false
                                    })
                            }
                        }
                    }
                }
                OutlinedTextField(
                    value = port, onValueChange = { port = it },
                    label = { Text("Port") },
                    modifier = Modifier.fillMaxWidth()
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement =
                        Arrangement.SpaceBetween
                ) {
                    Text("Honeydrop phase")
                    Switch(
                        checked = honeydrop,
                        onCheckedChange = { honeydrop = it })
                }
                if (honeydrop) {
                    OutlinedTextField(
                        value = drop, onValueChange = { drop = it },
                        label = {
                            Text("Drop text (blank = stock lure)")
                        },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                error?.let {
                    Text(it,
                         color = MaterialTheme.colorScheme.error,
                         style = MaterialTheme.typography.bodySmall)
                }
                val runningNow = running
                if (runningNow != null) {
                    if (dropArmed) {
                        Text(
                            "Honeydrop armed — the " +
                                "${CanaryHost.label(runningNow).lowercase()} " +
                                "is carrying its drop.",
                            style =
                                MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme
                                .onSurfaceVariant)
                    }
                    Button(
                        onClick = { host.stop() },
                        colors = ButtonDefaults.buttonColors(
                            containerColor =
                                MaterialTheme.colorScheme.error),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Stand the canary down — " +
                            "${CanaryHost.label(runningNow)} on " +
                            "${runningPort ?: 0}")
                    }
                } else {
                    Button(
                        onClick = {
                            host.start(
                                persona,
                                port.toIntOrNull()
                                    ?: CanaryHost.defaultPort(persona),
                                honeydrop, drop)
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Raise the canary") }
                }
            }
        }
        IosPanelCard {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("Lessons from the catch",
                     style = MaterialTheme.typography.titleMedium)
                Text(
                    "Counted from the canary's own sessions: the " +
                        "paths, topics, subjects, and client " +
                        "banners probers brought with them. Arming " +
                        "a path makes it bait — with the honeydrop " +
                        "on, asking for it is taking the drop.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (lessons.isEmpty()) {
                    Text(
                        "No lessons yet — the canary learns from " +
                            "whoever talks to it.",
                        color = MaterialTheme.colorScheme
                            .onSurfaceVariant)
                } else {
                    for (lesson in lessons.take(8)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement =
                                Arrangement.SpaceBetween
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(lesson.value,
                                     maxLines = 1)
                                Text(
                                    "${lesson.kind} · asked " +
                                        "${lesson.count}×",
                                    style = MaterialTheme.typography
                                        .bodySmall,
                                    color = MaterialTheme.colorScheme
                                        .onSurfaceVariant)
                            }
                            if (lesson.kind == "http path") {
                                if (lesson.value in armedPaths ||
                                    lesson.value in
                                        CanaryHost.baitPaths) {
                                    Text(
                                        "BAIT",
                                        style = MaterialTheme
                                            .typography.labelSmall,
                                        color = Color(0xFF35C759))
                                } else {
                                    OutlinedButton(
                                        onClick = {
                                            armedPaths =
                                                armedPaths +
                                                    lesson.value
                                            prefs.put(
                                                "canaryLearnedPaths",
                                                armedPaths.joinToString(
                                                    "\n"))
                                        }) {
                                        Text("Arm as bait")
                                    }
                                }
                            }
                        }
                    }
                    OutlinedButton(
                        onClick = {
                            CanaryLessons.clear(context.filesDir)
                            lessons = emptyList()
                        }) {
                        Text("Forget the lessons")
                    }
                }
            }
        }
    }
    LaunchedEffect(running) {
        lessons = CanaryLessons.all(context.filesDir)
    }
}
