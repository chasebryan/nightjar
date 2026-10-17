package net.nosuchmachine.nightjarhack

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/// KnockRelay — the Kotlin mirror of the iOS KnockRelay:
/// the client half of an operator-run Knocktalk relay
/// (tools/knocktalk-relay in this repo — a small Python
/// rendezvous the operator hosts wherever they like).
///
/// Without a relay, Knocktalk is perimeter-only: one phone
/// knocks the other's LAN address, both must share a
/// network. With one, both phones knock the RELAY instead:
/// the sender declares the destination mailbox, knocks the
/// sequence at the relay host, and the receiver polls its
/// mailbox and replays the sequence into its own engine.
/// The relay forwards port numbers and nothing else —
/// payloads stay sealed between the phones under the
/// pairing key, which the relay never holds. What the relay
/// can see is rendezvous metadata: mailbox names, timing,
/// and message lengths.
object KnockRelay {
    fun enabled(prefs: Prefs): Boolean =
        prefs.bool("knocktalkRelayEnabled", false)

    fun urlString(prefs: Prefs): String =
        prefs.string("knocktalkRelayURL", "").trim()

    fun token(prefs: Prefs): String =
        prefs.string("knocktalkRelayToken", "")

    fun mailbox(prefs: Prefs): String =
        prefs.string("knocktalkRelayBox", "")
            .trim().lowercase()

    /** A relay peer is addressed as `relay:<mailbox>`. */
    const val PEER_PREFIX = "relay:"

    fun mailbox(ofPeer: String): String? {
        if (!ofPeer.startsWith(PEER_PREFIX)) return null
        return ofPeer.removePrefix(PEER_PREFIX)
    }

    /** Fully configured: switched on, with somewhere to
     * knock and a mailbox of our own to be reached at. */
    fun configured(prefs: Prefs): Boolean =
        enabled(prefs) && baseURL(prefs) != null &&
            token(prefs).isNotEmpty() &&
            mailbox(prefs).isNotEmpty() && host(prefs) != null

    fun baseURL(prefs: Prefs): URL? {
        var raw = urlString(prefs)
        if (raw.isEmpty()) return null
        if (!raw.contains("://")) raw = "http://$raw"
        while (raw.endsWith("/")) raw = raw.dropLast(1)
        return try {
            URL(raw)
        } catch (_: Exception) {
            null
        }
    }

    /** The host the knock stream is aimed at when the peer
     * is a mailbox: the relay itself. */
    fun host(prefs: Prefs): String? = baseURL(prefs)?.host

    data class Frame(val from: String, val ports: List<Int>,
                     val at: Double)

    /** Tell the relay the next knock burst from this device
     * is for `mailbox`. Blocking; call on a worker thread.
     * Returns true on an HTTP 200. */
    fun declare(prefs: Prefs, to: String): Boolean {
        val base = baseURL(prefs) ?: return false
        return try {
            val connection = URL(base, "/declare")
                .openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty(
                "Content-Type", "application/json")
            connection.doOutput = true
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            val body = JSONObject()
            body.put("token", token(prefs))
            body.put("from", mailbox(prefs))
            body.put("to", to)
            connection.outputStream.write(
                body.toString().toByteArray(Charsets.UTF_8))
            connection.responseCode == 200
        } catch (_: Exception) {
            false
        }
    }

    /** The board: when did the relay last see a mailbox?
     * Blocking; call on a worker thread. Epoch seconds, or
     * null when never seen / unreachable. */
    fun presence(prefs: Prefs, box: String): Double? {
        val base = baseURL(prefs) ?: return null
        return try {
            val query = "box=" + URLEncoder.encode(box, "UTF-8") +
                "&token=" + URLEncoder.encode(token(prefs), "UTF-8")
            val connection = URL(base, "/presence?$query")
                .openConnection() as HttpURLConnection
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            val text = connection.inputStream
                .readBytes().toString(Charsets.UTF_8)
            val reply = JSONObject(text)
            if (reply.optBoolean("ok", false)) {
                if (reply.isNull("last_seen")) {
                    null
                } else {
                    reply.optDouble("last_seen", 0.0)
                        .takeIf { it > 0 }
                }
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    /** Fetch and drain this phone's mailbox. Blocking; call
     * on a worker thread. Throws on transport failure so
     * the poll can report the relay unreachable. */
    fun fetchInbox(prefs: Prefs): List<Frame> {
        val base = baseURL(prefs) ?: return emptyList()
        val query = "box=" +
            URLEncoder.encode(mailbox(prefs), "UTF-8") +
            "&token=" + URLEncoder.encode(token(prefs), "UTF-8")
        val connection = URL(base, "/inbox?$query")
            .openConnection() as HttpURLConnection
        connection.connectTimeout = 5000
        connection.readTimeout = 5000
        val text = connection.inputStream
            .readBytes().toString(Charsets.UTF_8)
        val reply = JSONObject(text)
        val frames = reply.optJSONArray("frames") ?: JSONArray()
        return (0 until frames.length()).map { i ->
            val obj = frames.getJSONObject(i)
            val ports = obj.getJSONArray("ports")
            Frame(
                from = obj.getString("from"),
                ports = (0 until ports.length()).map {
                    ports.getInt(it)
                },
                at = obj.optDouble("at", 0.0))
        }
    }
}
