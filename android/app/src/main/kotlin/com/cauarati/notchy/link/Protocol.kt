package com.cauarati.notchy.link

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Wire format of the desktop link (docs/PHONE_LINK.md): newline-delimited JSON over TLS.
 * Pure Kotlin plus org.json, so it runs in JVM unit tests.
 */
object Protocol {
    const val VERSION = 1
    /** One message never exceeds this; a longer line is a protocol error. */
    const val MAX_LINE_BYTES = 64 * 1024
    /** Optional features this app understands; the desktop offers back the ones it has switched on. */
    val CAPABILITIES = listOf("chat")
    const val CAP_CHAT = "chat"
    /** What the desktop accepts for one chat message; longer is refused there, so it is refused here first. */
    const val CHAT_MAX_TEXT = 4000
}

/** A model the user allowed on the computer for the phone. [id] is "provider/model". */
data class ChatModel(val id: String, val provider: String, val label: String)

/**
 * What the computer sends. Anything else on the wire (an older computer may still send `sessions`, `approval` and the like) is not
 * a type here: [Wire.decodeServer] drops it, as the protocol says unknown types are.
 */
sealed interface ServerMsg {
    data class Welcome(val version: Int, val desktopName: String, val os: String, val caps: Set<String> = emptySet()) : ServerMsg
    data object Pong : ServerMsg
    data class ChatModels(val models: List<ChatModel>) : ServerMsg
    /** [text] is appended to the answer being written. */
    data class ChatDelta(val id: String, val text: String) : ServerMsg
    /** [text], when present, is the full answer and replaces what was streamed. */
    data class ChatDone(val id: String, val text: String?) : ServerMsg
    /** [reason] is a fixed code (off, busy, rate, auth...); [message] a fixed sentence written by the computer. */
    data class ChatError(val id: String, val reason: String, val message: String) : ServerMsg
    data class Error(val code: String, val message: String) : ServerMsg
}

sealed interface ClientMsg {
    data class Hello(val version: Int, val token: String, val deviceName: String, val caps: List<String> = emptyList()) : ClientMsg
    data object Ping : ClientMsg
    data object Bye : ClientMsg
    data object ChatModels : ClientMsg
    data class ChatSend(val id: String, val model: String, val text: String) : ClientMsg
    data class ChatCancel(val id: String) : ClientMsg
    /** New chat: the computer forgets its side of the conversation and stops a running answer. */
    data object ChatReset : ClientMsg
}

object Wire {
    fun encode(m: ClientMsg): String {
        val o = JSONObject()
        when (m) {
            is ClientMsg.Hello -> {
                o.put("type", "hello").put("v", m.version).put("token", m.token).put("device", m.deviceName)
                // Only when there is something to say: an app with no optional features sends the v1 hello unchanged.
                if (m.caps.isNotEmpty()) o.put("caps", JSONArray(m.caps))
            }
            ClientMsg.Ping -> o.put("type", "ping")
            ClientMsg.Bye -> o.put("type", "bye")
            ClientMsg.ChatModels -> o.put("type", "chatModels")
            is ClientMsg.ChatSend -> o.put("type", "chatSend").put("id", m.id).put("model", m.model).put("text", m.text)
            is ClientMsg.ChatCancel -> o.put("type", "chatCancel").put("id", m.id)
            ClientMsg.ChatReset -> o.put("type", "chatReset")
        }
        return o.toString()
    }

    /** Returns null for anything malformed or unknown: a bad line never crashes the client. */
    fun decodeServer(line: String): ServerMsg? {
        if (line.length > Protocol.MAX_LINE_BYTES) return null
        return try {
            val o = JSONObject(line)
            when (o.getString("type")) {
                "welcome" -> ServerMsg.Welcome(o.getInt("v"), o.optString("desktop", ""), o.optString("os", ""), strings(o.optJSONArray("caps")))
                "pong" -> ServerMsg.Pong
                "chatModels" -> ServerMsg.ChatModels(o.getJSONArray("models").objects().mapNotNull(::chatModel))
                "chatDelta" -> ServerMsg.ChatDelta(chatId(o), o.getString("text"))
                "chatDone" -> ServerMsg.ChatDone(chatId(o), if (o.has("text")) o.getString("text") else null)
                "chatError" -> ServerMsg.ChatError(chatId(o), o.optString("reason", "internal"), o.optString("message", ""))
                "error" -> ServerMsg.Error(o.optString("code", ""), o.optString("message", ""))
                else -> null
            }
        } catch (_: JSONException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun strings(a: JSONArray?): Set<String> =
        if (a == null) emptySet() else (0 until a.length()).mapNotNull { a.optString(it, "").takeIf { s -> s.isNotEmpty() } }.toSet()

    /** A model without a usable id is dropped; a missing label shows the id. */
    private fun chatModel(o: JSONObject): ChatModel? {
        val id = o.optString("id", "")
        if (id.isBlank() || id.length > 300 || id.indexOf('/') <= 0) return null
        return ChatModel(id, o.optString("provider", id.substringBefore('/')), o.optString("label", "").ifBlank { id })
    }

    private fun chatId(o: JSONObject): String = o.getString("id").also { require(isChatId(it)) }

    private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map { getJSONObject(it) }

    /** The id the phone makes for a chat message and the computer echoes: 1 to 64 of letters, digits, - and _. */
    fun isChatId(s: String) = s.isNotEmpty() && s.length <= 64 && s.all { it.isLetterOrDigit() && it.code < 128 || it == '-' || it == '_' }

    /** A certificate's SHA-256 as the pairing link carries it: 64 lowercase hex characters. */
    fun isFingerprint(s: String) = s.length == 64 && s.all { it in '0'..'9' || it in 'a'..'f' }
}
