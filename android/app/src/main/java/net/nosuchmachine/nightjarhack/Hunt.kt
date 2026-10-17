package net.nosuchmachine.nightjarhack

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.sin

/// A short sine beep with a smooth envelope — the hunt's voice.
class HuntTone {
    private var track: AudioTrack? = null
    private var started = false

    private fun ensureTrack(): AudioTrack? {
        if (track == null) {
            val sampleRate = 44100
            val minBuffer = AudioTrack.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_FLOAT)
            if (minBuffer <= 0) return null
            track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(
                            AudioAttributes
                                .USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build())
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build())
                .setBufferSizeInBytes(minBuffer * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        }
        val current = track ?: return null
        if (!started) {
            current.play()
            started = true
        }
        return current
    }

    fun beep(frequency: Double) {
        val current = ensureTrack() ?: return
        val sampleRate = 44100.0
        val duration = 0.07
        val frames = (sampleRate * duration).toInt()
        val data = FloatArray(frames) { i ->
            val t = i / sampleRate
            val envelope = sin(PI * i / frames)
            (sin(2 * PI * frequency * t) * envelope * 0.35).toFloat()
        }
        try {
            current.write(data, 0, frames, AudioTrack.WRITE_BLOCKING)
        } catch (_: Exception) {
        }
    }

    fun stop() {
        try {
            track?.stop()
            track?.release()
        } catch (_: Exception) {
        }
        track = null
        started = false
    }
}

/// Tracker hunt: a Geiger counter for one advertiser.
///
/// Listen hears; this walks you onto the signal. Pick a device
/// — the tag in the car, the unknown regular in the house — and
/// the hunt reads its smoothed RSSI aloud: beeps that quicken
/// and rise as you close in, a haptic thump when you're near,
/// and the honest counters (closest ever, seconds since last
/// heard) underneath. The ears were already there; this is the
/// needle.
@Composable
fun HuntView(app: NightjarApp, targetID: String, onDone: () -> Unit) {
    val post = app.post
    val context = LocalContext.current
    val rows by post.rows.collectAsState()
    val listening by post.isListening.collectAsState()
    val tone = remember { HuntTone() }
    val scope = rememberCoroutineScope()
    var now by remember { mutableStateOf(ListeningPost.nowSeconds()) }
    var lastBeepMs by remember { mutableStateOf(0L) }

    fun thump(strength: Double) {
        try {
            val vibrator: Vibrator? =
                if (Build.VERSION.SDK_INT >= 31) {
                    (context.getSystemService(
                        Context.VIBRATOR_MANAGER_SERVICE)
                        as? VibratorManager)?.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    context.getSystemService(
                        Context.VIBRATOR_SERVICE) as? Vibrator
                }
            val amplitude = (strength * 255).toInt().coerceIn(1, 255)
            vibrator?.vibrate(
                VibrationEffect.createOneShot(60, amplitude))
        } catch (_: Exception) {
        }
    }

    fun step() {
        if (!post.isListening.value) return
        val row = post.rows.value.firstOrNull { it.id == targetID }
            ?: return
        val rssi = row.rssiSmooth ?: row.rssiLast?.toDouble()
            ?: return
        val ageSeconds = ListeningPost.nowSeconds() - row.lastSeen
        if (ageSeconds >= 3) return
        val strength = minOf(1.0, maxOf(0.0, (rssi + 95) / 60))
        val intervalMs = (1300 - strength * 1150).toLong()
        val nowMs = System.currentTimeMillis()
        if (nowMs - lastBeepMs < intervalMs) return
        lastBeepMs = nowMs
        val frequency = 550 + strength * 750
        scope.launch(Dispatchers.IO) { tone.beep(frequency) }
        if (strength > 0.7) thump(strength)
    }

    LaunchedEffect(Unit) {
        while (true) {
            delay(200)
            now = ListeningPost.nowSeconds()
            step()
        }
    }
    DisposableEffect(Unit) {
        onDispose { tone.stop() }
    }

    val row = rows.firstOrNull { it.id == targetID }
    val rssi = row?.rssiSmooth ?: row?.rssiLast?.toDouble()
    val strength = if (rssi == null) 0.0
        else minOf(1.0, maxOf(0.0, (rssi + 95) / 60))
    val age = row?.let { now - it.lastSeen }
    val fresh = age != null && age < 3
    val proximity = when {
        rssi == null -> "NOT HEARD"
        rssi >= -45 -> "ON TOP OF IT"
        rssi >= -60 -> "CLOSE"
        rssi >= -72 -> "NEAR"
        rssi >= -85 -> "FAR"
        else -> "EDGE OF EARSHOT"
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            TabTitle("Hunt")
            OutlinedButton(onClick = onDone) { Text("Done") }
        }
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            Text(
                row?.label ?: "Unknown device",
                style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center)
            Text(
                row?.kind ?: "",
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (!listening) {
            Text(
                "The hunt needs live ears.",
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = { post.start("hunt") }) {
                Text("Start listening")
            }
        } else if (row == null) {
            Text(
                "Not heard in this session yet. It may be asleep, " +
                    "out of range — or, if it rotates its address, " +
                    "gone under a new one.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center)
        } else {
            Text(
                rssi?.let { "%.0f dBm".format(it) } ?: "—",
                style = TextStyle(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold, fontSize = 56.sp))
            Text(
                proximity,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = if (fresh) Color(0xFF35C759)
                    else MaterialTheme.colorScheme.onSurfaceVariant)
            LinearProgressIndicator(
                progress = strength.toFloat(),
                modifier = Modifier.fillMaxWidth(),
                color = if (fresh) Color(0xFF35C759) else Color.Gray)
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                FactRow("Closest ever",
                        row.rssiClosest?.let { "$it dBm" } ?: "—")
                FactRow("Sightings", row.sightings.toString())
                FactRow("Last heard",
                        age?.let { "%.0f s ago".format(it) } ?: "—")
            }
            if (row.rotatingAddress) {
                Text(
                    "This advertiser rotates its address — if it " +
                        "goes quiet mid-hunt, it may have stepped " +
                        "sideways into a new identity rather than away.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color(0xFFFF9F0A),
                    textAlign = TextAlign.Center)
            }
        }
        Spacer(Modifier.height(4.dp))
        Spacer(Modifier.weight(1f))
        Text(
            "Beeps quicken and rise as the signal strengthens; a " +
                "thump means you're near. Walk slow — RSSI is a " +
                "compass that points in loudness, not direction.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center)
    }
}
