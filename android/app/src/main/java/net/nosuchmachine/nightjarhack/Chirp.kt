package net.nosuchmachine.nightjarhack

import android.annotation.SuppressLint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/// Chirp — the Kotlin mirror of the iOS Chirp: messages
/// carried by sound.
///
/// The fourth transport, after wire, radio, and knock
/// order: a payload sung as tones, speaker to microphone.
/// The framing is borrowed from mawkbox — four tones
/// (1200/1600/2000/2400 Hz), two bits per symbol — and the
/// payload is a Knocktalk sealed box, byte for byte, so a
/// chirp is exactly as encrypted as a knock: the pairing
/// key seals it, and only the pairing key opens it. What
/// crosses the air is ciphertext with a haircut.
///
/// Sound is a narrow pipe: 60 ms symbols move about 33 bits
/// a second, so chirps are capped short on purpose. In
/// exchange the channel needs no network, no radio, and no
/// permission from the spectrum — it works in airplane
/// mode, under full EMCON, in a room where everything else
/// is watched.
///
/// Chirp mail is the same song, stored: render it to a .wav
/// and it travels by any carrier that moves audio, and
/// decodes from the file on arrival, through the very same
/// decoder the live listener runs. One modem, two
/// postures: sing it now, or mail it.
object ChirpModem {
    val tones = listOf(1200.0, 1600.0, 2000.0, 2400.0)
    const val SYMBOL_SECONDS = 0.06

    /** Sealed-byte ceiling for one chirp (about 35 s of song). */
    const val MAX_PAYLOAD = 120
    val magic = byteArrayOf(0x4E, 0x4A)
    const val WAV_RATE = 44100.0

    fun etaSeconds(payloadBytes: Int): Int {
        val symbols = 8 + (3 + payloadBytes + 2) * 4
        return (symbols * SYMBOL_SECONDS).toInt() + 1
    }

    /** Frame layout: an alternating preamble for the
     * listener to lock onto, then magic, length, payload,
     * and a CRC-16 (frame sync only — the AEAD tag inside
     * the payload is the real integrity check). */
    fun symbols(forPayload: ByteArray): List<Int> {
        val body = ByteArray(1 + forPayload.size)
        body[0] = forPayload.size.toByte()
        forPayload.copyInto(body, 1)
        val crc = crc16(body)
        val frame = ByteArray(2 + body.size + 2)
        magic.copyInto(frame, 0)
        body.copyInto(frame, 2)
        frame[frame.size - 2] = (crc shr 8).toByte()
        frame[frame.size - 1] = (crc and 0xFF).toByte()
        val out = mutableListOf(0, 3, 0, 3, 0, 3, 0, 3)
        for (byte in frame) {
            val v = byte.toInt() and 0xFF
            out.add((v shr 6) and 3)
            out.add((v shr 4) and 3)
            out.add((v shr 2) and 3)
            out.add(v and 3)
        }
        return out
    }

    fun crc16(bytes: ByteArray): Int {
        var crc = 0xFFFF
        for (byte in bytes) {
            crc = crc xor ((byte.toInt() and 0xFF) shl 8)
            repeat(8) {
                crc = if (crc and 0x8000 != 0) {
                    ((crc shl 1) xor 0x1021) and 0xFFFF
                } else {
                    (crc shl 1) and 0xFFFF
                }
            }
        }
        return crc
    }

    /** The song as samples — 44.1 kHz mono, each symbol a
     * sine with raised-cosine edges so the tones don't
     * click into each other's windows. */
    fun renderSamples(payload: ByteArray): FloatArray {
        val symbols = symbols(payload)
        val symN = (SYMBOL_SECONDS * WAV_RATE).toInt()
        val out = FloatArray(symN * symbols.size)
        val ramp = (0.008 * WAV_RATE).toInt()
        for ((index, symbol) in symbols.withIndex()) {
            val freq = tones[symbol]
            for (i in 0 until symN) {
                val t = i / WAV_RATE
                var amp = 0.5
                if (i < ramp) amp *= i.toDouble() / ramp
                if (i > symN - ramp) {
                    amp *= (symN - i).toDouble() / ramp
                }
                out[index * symN + i] =
                    (sin(2 * PI * freq * t) * amp).toFloat()
            }
        }
        return out
    }

    /** A plain 16-bit PCM WAV of the samples. */
    fun wavBytes(samples: FloatArray): ByteArray {
        val dataBytes = samples.size * 2
        val out = java.io.ByteArrayOutputStream()
        fun u32(v: Int) {
            out.write(v and 0xFF)
            out.write((v shr 8) and 0xFF)
            out.write((v shr 16) and 0xFF)
            out.write((v shr 24) and 0xFF)
        }
        fun u16(v: Int) {
            out.write(v and 0xFF)
            out.write((v shr 8) and 0xFF)
        }
        out.write("RIFF".toByteArray(Charsets.US_ASCII))
        u32(36 + dataBytes)
        out.write("WAVE".toByteArray(Charsets.US_ASCII))
        out.write("fmt ".toByteArray(Charsets.US_ASCII))
        u32(16)
        u16(1)                       // PCM
        u16(1)                       // mono
        u32(WAV_RATE.toInt())
        u32(WAV_RATE.toInt() * 2)    // byte rate
        u16(2)                       // block align
        u16(16)                      // bits per sample
        out.write("data".toByteArray(Charsets.US_ASCII))
        u32(dataBytes)
        for (sample in samples) {
            val clamped = sample.coerceIn(-1f, 1f)
            val v = (clamped * 32767).toInt()
            out.write(v and 0xFF)
            out.write((v shr 8) and 0xFF)
        }
        return out.toByteArray()
    }
}

/// The decoder: a preamble hunter and frame assembler fed
/// samples from anywhere — the microphone tap, or a file.
/// Feed it audio; it hands back a payload the moment a
/// whole chirp has been heard, and reports its lock state
/// as it goes.
class ChirpDecoder(private val rate: Double) {
    var onStatus: ((String) -> Unit)? = null

    private val symbolSamples: Int
        get() = (ChirpModem.SYMBOL_SECONDS * rate).toInt()

    private var buffer = FloatArray(1 shl 16)
    private var size = 0

    private enum class State { HUNTING, RECEIVING }
    private var state = State.HUNTING
    private var consumed = 0
    private val symbols = mutableListOf<Int>()
    private var nextWindow = 0
    private var huntTrail: List<Int> = emptyList()

    /** Feed audio; returns the payload when a chirp completes. */
    fun append(new: FloatArray): ByteArray? {
        ensureCapacity(size + new.size)
        new.copyInto(buffer, size)
        size += new.size
        val cap = rate.toInt() * 45
        if (size > cap) {
            val drop = size - cap
            System.arraycopy(buffer, drop, buffer, 0, size - drop)
            size -= drop
            consumed = maxOf(0, consumed - drop)
            nextWindow = maxOf(0, nextWindow - drop)
        }
        return process()
    }

    private fun ensureCapacity(wanted: Int) {
        if (wanted <= buffer.size) return
        var next = buffer.size
        while (next < wanted) next *= 2
        buffer = buffer.copyOf(next)
    }

    private fun process(): ByteArray? {
        val sym = symbolSamples
        return when (state) {
            State.HUNTING -> {
                var i = consumed
                while (i + sym <= size) {
                    val probe = classify(i)
                    if (probe.power <= 0.015) {
                        huntTrail = emptyList()
                    } else if (probe.margin > 1.8) {
                        huntTrail = huntTrail + probe.symbol
                        val tail = huntTrail.takeLast(6)
                        if (tail == listOf(0, 3, 0, 3, 0, 3) ||
                            tail == listOf(3, 0, 3, 0, 3, 0)) {
                            state = State.RECEIVING
                            symbols.clear()
                            nextWindow = i + sym
                            huntTrail = emptyList()
                            onStatus?.invoke("locked — receiving…")
                            consumed = i
                            return processReceiving()
                        }
                    }
                    i += sym / 2
                }
                consumed = i
                null
            }
            State.RECEIVING -> processReceiving()
        }
    }

    private fun processReceiving(): ByteArray? {
        val sym = symbolSamples
        while (nextWindow + sym <= size) {
            val probe = classify(nextWindow)
            if (probe.power <= 0.008 || probe.margin <= 1.5) {
                state = State.HUNTING
                consumed = nextWindow
                symbols.clear()
                onStatus?.invoke("lost that chirp mid-frame")
                return null
            }
            symbols.add(probe.symbol)
            nextWindow += sym
            if (symbols.size % 4 == 0) {
                val attempt = assemble()
                if (attempt.abort) {
                    state = State.HUNTING
                    consumed = nextWindow
                    symbols.clear()
                    onStatus?.invoke("that was not a chirp")
                    return null
                }
                if (attempt.payload != null) {
                    state = State.HUNTING
                    consumed = nextWindow
                    symbols.clear()
                    return attempt.payload
                }
            }
        }
        return null
    }

    private data class Attempt(
        val payload: ByteArray?, val abort: Boolean
    )

    /** Assemble whole bytes; report a finished payload, an
     * invalid frame, or neither yet. */
    private fun assemble(): Attempt {
        val bytes = mutableListOf<Int>()
        var i = 0
        while (i + 3 < symbols.size) {
            bytes.add(
                (symbols[i] shl 6) or (symbols[i + 1] shl 4) or
                    (symbols[i + 2] shl 2) or symbols[i + 3])
            i += 4
        }
        if (bytes.size < 3) return Attempt(null, false)
        if (bytes[0] != (ChirpModem.magic[0].toInt() and 0xFF) ||
            bytes[1] != (ChirpModem.magic[1].toInt() and 0xFF)) {
            return Attempt(null, true)
        }
        val length = bytes[2]
        if (length > ChirpModem.MAX_PAYLOAD) {
            return Attempt(null, true)
        }
        val total = 3 + length + 2
        if (bytes.size < total) return Attempt(null, false)
        val body = ByteArray(1 + length) {
            bytes[2 + it].toByte()
        }
        val carried = (bytes[3 + length] shl 8) or bytes[3 + length + 1]
        if (ChirpModem.crc16(body) != carried) {
            return Attempt(null, true)
        }
        return Attempt(
            ByteArray(length) { bytes[3 + it].toByte() }, false)
    }

    private data class Probe(
        val symbol: Int, val power: Double, val margin: Double
    )

    private fun classify(start: Int): Probe {
        val sym = symbolSamples
        val inset = sym / 6
        val begin = start + inset
        val count = sym - inset * 2
        val powers = ChirpModem.tones.map {
            goertzel(begin, count, it)
        }
        val ranked = powers.sortedDescending()
        val winner = powers.indexOf(ranked[0])
        val normalized = ranked[0] / (count.toDouble() * count)
        val margin = ranked[0] / maxOf(ranked[1], 1e-9)
        return Probe(winner, normalized, margin)
    }

    private fun goertzel(
        start: Int, count: Int, freq: Double
    ): Double {
        val coeff = 2 * cos(2 * PI * freq / rate)
        var s0 = 0.0
        var s1 = 0.0
        var s2 = 0.0
        val end = minOf(start + count, size)
        if (start >= end) return 0.0
        for (i in start until end) {
            s0 = buffer[i] + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        return s1 * s1 + s2 * s2 - coeff * s1 * s2
    }
}

/// Chirp mail: the song as a file, both directions.
object ChirpMail {
    /** Render a sealed payload to a shareable .wav. */
    fun export(payload: ByteArray, dir: File): File? {
        val samples = ChirpModem.renderSamples(payload)
        val file = File(
            dir, "chirp-${System.currentTimeMillis() / 1000}.wav")
        return try {
            file.writeBytes(ChirpModem.wavBytes(samples))
            file
        } catch (_: Exception) {
            null
        }
    }

    /** Decode the first complete chirp in an audio file.
     * A lossless .wav is the honest carrier; compressed
     * files are decoded through the platform codec when
     * they are not WAV. */
    fun decode(file: File): ByteArray? {
        val (samples, rate) = readSamples(file) ?: return null
        val decoder = ChirpDecoder(rate)
        return decoder.append(samples)
    }

    /** (samples, rate) from a WAV file directly, or from
     * any platform-decodable audio through MediaCodec. */
    fun readSamples(file: File): Pair<FloatArray, Double>? {
        val bytes = try {
            file.readBytes()
        } catch (_: Exception) {
            return null
        }
        if (bytes.size >= 12 &&
            String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF") {
            return parseWav(bytes)
        }
        return decodeCompressed(file)
    }

    private fun parseWav(bytes: ByteArray): Pair<FloatArray, Double>? {
        var channels = 1
        var rate = 44100
        var bits = 16
        var dataStart = -1
        var dataLength = 0
        var offset = 12
        fun u32(at: Int): Int =
            (bytes[at].toInt() and 0xFF) or
                ((bytes[at + 1].toInt() and 0xFF) shl 8) or
                ((bytes[at + 2].toInt() and 0xFF) shl 16) or
                ((bytes[at + 3].toInt() and 0xFF) shl 24)
        fun u16(at: Int): Int =
            (bytes[at].toInt() and 0xFF) or
                ((bytes[at + 1].toInt() and 0xFF) shl 8)
        while (offset + 8 <= bytes.size) {
            val id = String(bytes, offset, 4, Charsets.US_ASCII)
            val length = u32(offset + 4)
            when (id) {
                "fmt " -> {
                    channels = u16(offset + 10)
                    rate = u32(offset + 12)
                    bits = u16(offset + 22)
                }
                "data" -> {
                    dataStart = offset + 8
                    dataLength = length
                    break
                }
            }
            offset += 8 + length + (length and 1)
        }
        if (dataStart < 0 || bits != 16) return null
        val frames = minOf(
            dataLength / 2 / channels,
            (bytes.size - dataStart) / 2 / channels)
        val out = FloatArray(frames)
        for (i in 0 until frames) {
            var sum = 0.0
            for (channel in 0 until channels) {
                val at = dataStart + (i * channels + channel) * 2
                val v = (bytes[at].toInt() and 0xFF) or
                    ((bytes[at + 1].toInt()) shl 8)
                sum += v.toShort() / 32768.0
            }
            out[i] = (sum / channels).toFloat()
        }
        return out to rate.toDouble()
    }

    private fun decodeCompressed(file: File): Pair<FloatArray, Double>? {
        return try {
            val extractor = android.media.MediaExtractor()
            extractor.setDataSource(file.absolutePath)
            var track = -1
            var format: android.media.MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val candidate = extractor.getTrackFormat(i)
                if ((candidate.getString(
                        android.media.MediaFormat.KEY_MIME)
                        ?: "").startsWith("audio/")) {
                    track = i
                    format = candidate
                    break
                }
            }
            if (track < 0 || format == null) {
                extractor.release()
                return null
            }
            extractor.selectTrack(track)
            val mime = format.getString(
                android.media.MediaFormat.KEY_MIME) ?: ""
            val rate = format.getInteger(
                android.media.MediaFormat.KEY_SAMPLE_RATE)
            val codec = android.media.MediaCodec
                .createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()
            val out = mutableListOf<Float>()
            val info = android.media.MediaCodec.BufferInfo()
            var sawInputEnd = false
            var sawOutputEnd = false
            while (!sawOutputEnd) {
                if (!sawInputEnd) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val input = codec.getInputBuffer(inIndex)
                            ?: continue
                        val read = extractor.readSampleData(
                            input, 0)
                        if (read < 0) {
                            codec.queueInputBuffer(
                                inIndex, 0, 0, 0,
                                android.media.MediaCodec
                                    .BUFFER_FLAG_END_OF_STREAM)
                            sawInputEnd = true
                        } else {
                            codec.queueInputBuffer(
                                inIndex, 0, read,
                                extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                if (outIndex >= 0) {
                    val output = codec.getOutputBuffer(outIndex)
                    if (output != null && info.size > 0) {
                        output.position(info.offset)
                        output.limit(info.offset + info.size)
                        while (output.remaining() >= 2) {
                            val v = output.short
                            out.add(v / 32768f)
                        }
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (info.flags and android.media.MediaCodec
                            .BUFFER_FLAG_END_OF_STREAM != 0) {
                        sawOutputEnd = true
                    }
                }
            }
            codec.stop()
            codec.release()
            extractor.release()
            // Stereo folds to mono by averaging pairs when the
            // stream was stereo — the extractor's channel
            // count rides the format.
            val channels = format.getInteger(
                android.media.MediaFormat.KEY_CHANNEL_COUNT)
            val mono = if (channels > 1) {
                FloatArray(out.size / channels) { i ->
                    var sum = 0f
                    for (c in 0 until channels) {
                        sum += out[i * channels + c]
                    }
                    sum / channels
                }
            } else {
                out.toFloatArray()
            }
            mono to rate.toDouble()
        } catch (_: Exception) {
            null
        }
    }
}

/// The singer: plays the rendered song through the speaker.
class ChirpSender {
    private val _singing = MutableStateFlow(false)
    val singing: StateFlow<Boolean> = _singing
    private val _progress = MutableStateFlow(0.0)
    val progress: StateFlow<Double> = _progress

    private val scope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var job: Job? = null
    private var track: AudioTrack? = null

    fun sing(payload: ByteArray) {
        stop()
        val samples = ChirpModem.renderSamples(payload)
        job = scope.launch {
            val audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(ChirpModem.WAV_RATE.toInt())
                        .setChannelMask(
                            AudioFormat.CHANNEL_OUT_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .build())
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            track = audioTrack
            _singing.value = true
            _progress.value = 0.0
            audioTrack.play()
            val started = System.currentTimeMillis()
            val airtime = samples.size /
                ChirpModem.WAV_RATE * 1000
            val progressJob = launch {
                while (isActive) {
                    val done = System.currentTimeMillis() - started
                    _progress.value = minOf(1.0, done / airtime)
                    if (done >= airtime) break
                    delay(200)
                }
            }
            var offset = 0
            val chunk = 4096
            while (offset < samples.size && isActive) {
                val n = minOf(chunk, samples.size - offset)
                audioTrack.write(samples, offset, n)
                offset += n
            }
            progressJob.join()
            finish()
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        try {
            track?.stop()
        } catch (_: Exception) {
        }
        track?.release()
        track = null
        _singing.value = false
        _progress.value = 0.0
    }

    private fun finish() {
        try {
            track?.stop()
        } catch (_: Exception) {
        }
        track?.release()
        track = null
        _singing.value = false
        _progress.value = 0.0
    }
}

/// The live listener: a microphone tap feeding the shared
/// decoder. All the hearing lives in ChirpDecoder; this
/// owns the record session and the status line.
class ChirpListener {
    private val _listening = MutableStateFlow(false)
    val listening: StateFlow<Boolean> = _listening
    private val _status = MutableStateFlow("idle")
    val status: StateFlow<String> = _status

    /** Return true when the payload opened — the listener
     * reports the outcome in its own status line. */
    var onPayload: ((ByteArray) -> Boolean)? = null

    private val scope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var job: Job? = null
    private var record: AudioRecord? = null

    /** @return a failure line, or null when listening. */
    @SuppressLint("MissingPermission")
    fun start(): String? {
        stop()
        val rate = 44100
        val bufferSize = AudioRecord.getMinBufferSize(
            rate, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_FLOAT)
        if (bufferSize <= 0) {
            _status.value = "microphone would not start"
            return _status.value
        }
        val audioRecord = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC, rate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_FLOAT,
                maxOf(bufferSize, 8192))
        } catch (_: SecurityException) {
            _status.value = "microphone permission denied — " +
                "Android Settings is where that changes"
            return _status.value
        } catch (_: Exception) {
            _status.value = "microphone would not start"
            return _status.value
        }
        if (audioRecord.state != AudioRecord.STATE_INITIALIZED) {
            audioRecord.release()
            _status.value = "microphone would not start"
            return _status.value
        }
        record = audioRecord
        val decoder = ChirpDecoder(rate.toDouble())
        decoder.onStatus = { text ->
            _status.value = "$text — still listening"
        }
        _listening.value = true
        _status.value = "listening — hold the phones near each other"
        audioRecord.startRecording()
        job = scope.launch {
            val chunk = FloatArray(2048)
            while (isActive) {
                val read = audioRecord.read(
                    chunk, 0, chunk.size,
                    AudioRecord.READ_BLOCKING)
                if (read <= 0) continue
                val payload = decoder.append(
                    chunk.copyOf(read)) ?: continue
                val opened = onPayload?.invoke(payload) ?: false
                _status.value = if (opened) {
                    "decoded — filed in the Chirp thread below"
                } else {
                    "heard a chirp that does not open with " +
                        "your pairing key"
                }
            }
        }
        return null
    }

    fun stop() {
        job?.cancel()
        job = null
        try {
            record?.stop()
        } catch (_: Exception) {
        }
        record?.release()
        record = null
        _listening.value = false
        _status.value = "idle"
    }
}
