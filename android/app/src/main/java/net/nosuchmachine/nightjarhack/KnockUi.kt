package net.nosuchmachine.nightjarhack

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.clickable
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// The Knocktalk tab: conversations carried by knock order
/// — the Kotlin mirror of the iOS KnockChatView.
///
/// The tripwire (EMCON's ear) is what makes this a
/// conversation rather than a flare gun — both phones listen
/// while they knock, so delivery confirms itself, holes get
/// named and re-knocked, and a thread reads like a thread.
@Composable
fun KnockTab(app: NightjarApp) {
    val chat = app.knockChat
    val prefs = remember { Prefs(app) }
    val tripwireOn by app.emcon.tripwireOn.collectAsState()
    val threads by chat.threads.collectAsState()
    val sendSuite by chat.sendSuite.collectAsState()
    val retentionHours by chat.retentionHours.collectAsState()
    val relayStatus by chat.relayStatus.collectAsState()
    var keyHex by remember {
        mutableStateOf(KnockKeyStore.keyHex)
    }
    var keyDraft by remember { mutableStateOf("") }
    var newPeer by remember { mutableStateOf("") }
    var openedPeer by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) { chat.purge() }

    val peer = openedPeer
    if (peer != null) {
        ConversationPane(
            app = app, peer = peer,
            onBack = { openedPeer = null })
        return
    }

    LazyColumn(
        modifier = Modifier.padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item { TabTitle("Knocktalk") }
        item {
            IosPanelCard {
                Text(
                    if (tripwireOn) {
                        "Listening — the tripwire is up, so " +
                            "this phone hears knocks, ACKs " +
                            "and replies."
                    } else {
                        "Deaf right now — raise EMCON so the " +
                            "tripwire listens. You can still " +
                            "knock messages out, but nothing " +
                            "can knock back."
                    },
                    modifier = Modifier.padding(12.dp))
            }
        }

        // MARK: pairing key
        item { IosSectionHeader("Pairing key") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    if (keyHex == null) {
                        Text(
                            "No key yet: Knocktalk seals with " +
                                "ChaCha20-Poly1305, and without " +
                                "the shared key nothing here can " +
                                "be sealed or opened.",
                            color = IosColors.SecondaryLabel)
                        Button(
                            onClick = {
                                val hex = KnockKeyStore.generate()
                                KnockKeyStore.keyHex = hex
                                keyHex = hex
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Generate a pairing key") }
                        OutlinedTextField(
                            value = keyDraft,
                            onValueChange = { keyDraft = it },
                            label = {
                                Text("paste a pairing key (64 hex digits)")
                            },
                            modifier = Modifier.fillMaxWidth())
                        val pastedBytes = try {
                            PayloadKit.decodeHex(
                                keyDraft.trim().lowercase()).size
                        } catch (_: Exception) {
                            -1
                        }
                        Button(
                            onClick = {
                                val hex = keyDraft.trim().lowercase()
                                KnockKeyStore.keyHex = hex
                                keyHex = hex
                                keyDraft = ""
                            },
                            enabled = pastedBytes == 32,
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Save the pasted key") }
                        Text(
                            "One 256-bit key, both phones, kept " +
                                "in this app's private store. " +
                                "Generate it on one phone and " +
                                "carry it to the other — or paste " +
                                "the one it made.",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement =
                                Arrangement.SpaceBetween
                        ) {
                            Text("Fingerprint")
                            Text(
                                KnockKeyStore.fingerprint(keyHex!!),
                                fontFamily = FontFamily.Monospace,
                                color = IosColors.SecondaryLabel)
                        }
                        OutlinedButton(onClick = {
                            val hex = KnockKeyStore.generate()
                            KnockKeyStore.keyHex = hex
                            keyHex = hex
                        }) { Text("Replace the pairing key") }
                        OutlinedButton(
                            onClick = {
                                KnockKeyStore.keyHex = null
                                keyHex = null
                            },
                            colors = ButtonDefaults
                                .outlinedButtonColors(
                                    contentColor = IosColors.Error)
                        ) { Text("Forget the pairing key") }
                    }
                }
            }
        }

        // MARK: suite
        item { IosSectionHeader("Sending encryption") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text("Suite for messages I send")
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Knocktalk.suiteNames.forEachIndexed {
                                index, name ->
                            FilterChip(
                                selected = sendSuite == index,
                                onClick = { chat.setSendSuite(index) },
                                label = { Text(name) })
                        }
                    }
                    Text(
                        "Your choice rides inside every fragment " +
                            "you knock. The other phone opens " +
                            "your messages with the suite you " +
                            "picked — its own setting governs " +
                            "only what IT sends. Nothing has to " +
                            "match.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }

        // MARK: relay
        item {
            RelaySection(app = app, prefs = prefs,
                         relayStatus = relayStatus)
        }

        // MARK: carriers
        item { ChirpSection(app = app, hasKey = keyHex != null) }
        item {
            BrushSection(app = app, prefs = prefs,
                         hasKey = keyHex != null)
        }
        item { BlinkSection(app = app, hasKey = keyHex != null) }
        item { FlareSection(app = app, hasKey = keyHex != null) }
        item { CapsuleSection(app = app, hasKey = keyHex != null) }

        // MARK: conversations
        item { IosSectionHeader("Conversations") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = newPeer,
                            onValueChange = { newPeer = it },
                            label = {
                                Text("peer address — IP, or relay:name")
                            },
                            modifier = Modifier.weight(1f))
                        Button(
                            onClick = {
                                openedPeer =
                                    KnockChat.peerKey(newPeer)
                                newPeer = ""
                            },
                            enabled = newPeer.trim().isNotEmpty()
                        ) { Text("Open") }
                    }
                    if (chat.peersByRecency.isEmpty()) {
                        Text(
                            "No conversations yet. Open one by " +
                                "address — the other phone needs " +
                                "the app, the same pairing key, " +
                                "and EMCON up.",
                            color = IosColors.SecondaryLabel)
                    }
                }
            }
        }
        items(chat.peersByRecency) { peerKey ->
            val messages = threads[peerKey] ?: emptyList()
            IosPanelCard {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { openedPeer = peerKey }
                        .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            peerKey,
                            fontWeight = FontWeight.SemiBold)
                        messages.lastOrNull()?.let { last ->
                            Text(
                                (if (last.outgoing) "You: " else "") +
                                    last.text,
                                style = MaterialTheme.typography
                                    .bodySmall,
                                color = IosColors.SecondaryLabel,
                                maxLines = 1)
                        }
                    }
                    when {
                        messages.any {
                            it.outgoing && it.state == "failed"
                        } -> Text(
                            "failed",
                            fontWeight = FontWeight.SemiBold,
                            color = IosColors.Error)
                        messages.any {
                            it.outgoing &&
                                (it.state == "sending" ||
                                    it.state == "awaiting")
                        } -> Text(
                            "awaiting",
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                }
            }
        }

        // MARK: burn timer
        item { IosSectionHeader("Burn timer") }
        item {
            IosPanelCard {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text("Auto-delete messages")
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        for ((hours, label) in listOf(
                            1.0 to "1 hour", 6.0 to "6 hours",
                            24.0 to "24 hours", 168.0 to "7 days",
                            0.0 to "never")) {
                            FilterChip(
                                selected = retentionHours == hours,
                                onClick = { chat.setRetention(hours) },
                                label = { Text(label) })
                        }
                    }
                    Text(
                        "Checked at launch, when this tab opens, " +
                            "and when a message lands — a closed " +
                            "app cannot burn on schedule. The " +
                            "journal never held contents; this " +
                            "is the only copy.",
                        style = MaterialTheme.typography.bodySmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }
        item { Spacer(Modifier.padding(bottom = 24.dp)) }
    }
}

@Composable
private fun RelaySection(
    app: NightjarApp, prefs: Prefs, relayStatus: String
) {
    val chat = app.knockChat
    val scope = rememberCoroutineScope()
    var enabled by prefBool(prefs, "knocktalkRelayEnabled", false)
    var url by prefString(prefs, "knocktalkRelayURL", "")
    var token by prefString(prefs, "knocktalkRelayToken", "")
    var box by prefString(prefs, "knocktalkRelayBox", "")
    var board by remember {
        mutableStateOf<Map<String, String>>(emptyMap())
    }
    var boardChecked by remember { mutableStateOf(false) }

    fun refresh() {
        chat.refreshRelayPolling()
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        IosSectionHeader("Relay server")
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
                    Text("Use my relay server")
                    Switch(
                        checked = enabled,
                        onCheckedChange = {
                            enabled = it
                            refresh()
                        })
                }
                if (enabled) {
                    OutlinedTextField(
                        value = url,
                        onValueChange = {
                            url = it
                            refresh()
                        },
                        label = { Text("server (host:8901 or https://…)") },
                        modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(
                        value = box,
                        onValueChange = {
                            box = it
                            refresh()
                        },
                        label = { Text("this phone's mailbox name") },
                        modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(
                        value = token,
                        onValueChange = {
                            token = it
                            refresh()
                        },
                        label = { Text("relay token") },
                        visualTransformation =
                            PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth())
                    if (relayStatus.isNotEmpty()) {
                        Text(
                            relayStatus,
                            style = MaterialTheme.typography.bodySmall,
                            color = IosColors.SecondaryLabel)
                    }
                    if (KnockRelay.configured(prefs)) {
                        Button(onClick = {
                            boardChecked = true
                            val boxes = mutableSetOf<String>()
                            for (peerKey in chat.peersByRecency) {
                                KnockRelay.mailbox(ofPeer = peerKey)
                                    ?.let { boxes.add(it) }
                            }
                            val own = KnockRelay.mailbox(prefs)
                            if (own.isNotEmpty()) boxes.add(own)
                            scope.launch {
                                val labels =
                                    mutableMapOf<String, String>()
                                for (name in boxes.sorted()) {
                                    val seen = withContext(
                                        Dispatchers.IO) {
                                        KnockRelay.presence(prefs, name)
                                    }
                                    labels[name] = if (seen == null) {
                                        "never seen by the relay"
                                    } else {
                                        "seen " + SimpleDateFormat(
                                            "MMM d, HH:mm", Locale.US)
                                            .format(Date(
                                                (seen * 1000).toLong()))
                                    }
                                }
                                board = labels
                            }
                        }) { Text("Check the board") }
                        for ((name, label) in board) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement =
                                    Arrangement.SpaceBetween
                            ) {
                                Text(
                                    if (name ==
                                        KnockRelay.mailbox(prefs)) {
                                        "$name (this phone)"
                                    } else {
                                        name
                                    })
                                Text(
                                    label,
                                    color = IosColors.SecondaryLabel)
                            }
                        }
                        if (boardChecked && board.isEmpty()) {
                            Text(
                                "—",
                                color = IosColors.SecondaryLabel)
                        }
                    }
                }
                Text(
                    "Without a relay, Knocktalk is " +
                        "perimeter-only: both phones must share " +
                        "a network. Run your own relay (this " +
                        "repo, tools/knocktalk-relay) on any " +
                        "host you control, point both phones at " +
                        "it, and address each other as " +
                        "relay:<mailbox>. The relay forwards " +
                        "knock sequences between mailboxes — it " +
                        "never holds the pairing key and cannot " +
                        "read a word; it sees timing, lengths, " +
                        "and mailbox names. The vault, which is " +
                        "a perimeter ritual, never answers a " +
                        "relay knock.",
                    style = MaterialTheme.typography.bodySmall,
                    color = IosColors.SecondaryLabel)
            }
        }
    }
}

/// One conversation: bubbles, delivery states, a composer.
@Composable
private fun ConversationPane(
    app: NightjarApp, peer: String, onBack: () -> Unit
) {
    val chat = app.knockChat
    val threads by chat.threads.collectAsState()
    val sending by chat.sender.sending.collectAsState()
    val sent by chat.sender.sent.collectAsState()
    val total by chat.sender.total.collectAsState()
    val messages = threads[peer] ?: emptyList()
    var draft by remember { mutableStateOf("") }
    var tooLong by remember { mutableStateOf(false) }
    val timeFormat = remember {
        SimpleDateFormat("HH:mm", Locale.US)
    }

    Column(modifier = Modifier.padding(horizontal = 16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onBack) { Text("‹ Knocktalk") }
            Text(
                peer,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f))
            if (messages.isNotEmpty()) {
                TextButton(onClick = {
                    chat.clearThread(peer)
                    onBack()
                }) {
                    Text("Clear thread", color = IosColors.Error)
                }
            }
        }
        LazyColumn(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (messages.isEmpty()) {
                item {
                    Text(
                        "Nothing yet. The first message knocks " +
                            "the whole conversation open — " +
                            "fragments, about twelve seconds " +
                            "each, and the other phone knocks " +
                            "its ACK back the same way.",
                        color = IosColors.SecondaryLabel)
                }
            }
            items(messages) { message ->
                Row(modifier = Modifier.fillMaxWidth()) {
                    if (message.outgoing) {
                        Spacer(Modifier.weight(1f))
                    }
                    Column(
                        modifier = Modifier.weight(4f, fill = false),
                        horizontalAlignment = if (message.outgoing) {
                            Alignment.End
                        } else {
                            Alignment.Start
                        }
                    ) {
                        IosPanelCard {
                            Column(
                                modifier = Modifier.padding(10.dp)
                            ) {
                                Text(message.text)
                                Text(
                                    captionFor(
                                        message, timeFormat),
                                    style = MaterialTheme.typography
                                        .labelSmall,
                                    color = IosColors.SecondaryLabel)
                            }
                        }
                        if (message.outgoing &&
                            message.state == "failed") {
                            TextButton(onClick = {
                                val key = KnockKeyStore.key
                                if (key != null) {
                                    chat.resend(message.id, key)
                                }
                            }) { Text("Resend") }
                        }
                    }
                    if (!message.outgoing) {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
        Column(
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(vertical = 8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = {
                        draft = it
                        tooLong = false
                    },
                    label = { Text("knock a message") },
                    modifier = Modifier.weight(1f))
                Button(
                    onClick = {
                        val key = KnockKeyStore.key
                        if (key != null) {
                            if (chat.send(draft, peer, key)) {
                                draft = ""
                                tooLong = false
                            } else {
                                tooLong = true
                            }
                        }
                    },
                    enabled = draft.isNotEmpty() &&
                        KnockKeyStore.key != null
                ) { Text("Knock") }
            }
            Row(modifier = Modifier.fillMaxWidth()) {
                val sealedBytes =
                    draft.toByteArray(Charsets.UTF_8).size + 28
                Text(
                    if (sealedBytes <= Knocktalk.maxSealedBytes) {
                        "≈$sealedBytes sealed bytes of " +
                            Knocktalk.maxSealedBytes
                    } else {
                        "too long for one knock stream"
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = if (tooLong) {
                        IosColors.Error
                    } else {
                        IosColors.SecondaryLabel
                    })
                Spacer(Modifier.weight(1f))
                if (sending) {
                    Text(
                        "knocking $sent/$total…",
                        style = MaterialTheme.typography.labelSmall,
                        color = IosColors.SecondaryLabel)
                }
            }
        }
    }
}

private fun captionFor(
    message: KnockChat.ChatMessage,
    timeFormat: SimpleDateFormat
): String {
    val time = timeFormat.format(Date(message.whenMs))
    if (!message.outgoing) return time
    return when (message.state) {
        "sending" -> "$time · knocking…"
        "awaiting" -> "$time · sent, awaiting ACK"
        "delivered" -> "$time · delivered ✓"
        "failed" -> "$time · not confirmed"
        else -> time
    }
}
