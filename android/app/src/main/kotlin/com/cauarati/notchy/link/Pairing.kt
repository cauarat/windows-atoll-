package com.cauarati.notchy.link

import android.annotation.SuppressLint
import java.net.URI
import java.net.URLDecoder
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.X509TrustManager

/**
 * What the desktop shows as a QR code: notchy://pair?v=1&host=...&port=...&fp=...&token=...&name=...
 * `fp` is the SHA-256 (hex) of the desktop's TLS certificate; `token` is the shared pairing secret.
 */
data class PairingPayload(
    val host: String,
    val port: Int,
    val certSha256: String,
    val token: String,
    val desktopName: String,
) {
    /** Formatted SHA-256 certificate fingerprint for out-of-band confirmation before pairing. */
    fun formattedFingerprint(): String = certSha256.uppercase().chunked(4).joinToString(" ")

    companion object {
        /** Returns null for anything that is not a well-formed v1 pairing link. */
        fun parse(text: String): PairingPayload? {
            val uri = try { URI(text.trim()) } catch (_: Exception) { return null }
            if (uri.scheme != "notchy" || uri.host != "pair") return null
            val q = (uri.rawQuery ?: return null).split("&").mapNotNull {
                val i = it.indexOf('=')
                if (i <= 0) null else it.substring(0, i) to URLDecoder.decode(it.substring(i + 1), "UTF-8")
            }.toMap()
            if (q["v"] != Protocol.VERSION.toString()) return null
            val host = q["host"]?.takeIf { it.isNotBlank() && it.length <= 253 } ?: return null
            val port = q["port"]?.toIntOrNull()?.takeIf { it in 1..65535 } ?: return null
            val fp = q["fp"]?.lowercase()?.takeIf(Wire::isFingerprint) ?: return null
            val token = q["token"]?.takeIf { it.length in 16..128 && it.all { c -> c.isLetterOrDigit() || c == '-' || c == '_' } }
                ?: return null
            return PairingPayload(host, port, fp, token, q["name"].orEmpty().take(64))
        }
    }
}

/** Accepts exactly one certificate, the one whose SHA-256 was in the QR code. No CA, no hostname check. */
@SuppressLint("CustomX509TrustManager") // intentional: certificate pinning to the paired desktop
class PinnedTrustManager(private val pinnedSha256Hex: String) : X509TrustManager {
    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        val leaf = chain?.firstOrNull() ?: throw CertificateException("empty certificate chain")
        val actual = MessageDigest.getInstance("SHA-256").digest(leaf.encoded).joinToString("") { "%02x".format(it) }
        if (!MessageDigest.isEqual(actual.toByteArray(), pinnedSha256Hex.lowercase().toByteArray())) {
            throw CertificateException("certificate does not match the paired desktop")
        }
    }

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        throw CertificateException("client certificates are not used")
    }

    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

/** How a pairing is kept (encrypted by SecureStore): one field per line. */
object PairingCodec {
    fun encode(p: PairingPayload): String = listOf(p.host, p.port.toString(), p.certSha256, p.token, p.desktopName).joinToString("\n")

    /** Null when the text is not a pairing this build can use. */
    fun decode(text: String): PairingPayload? {
        val parts = text.split("\n")
        if (parts.size < 4) return null
        val port = parts[1].toIntOrNull() ?: return null
        return PairingPayload(parts[0], port, parts[2], parts[3], parts.getOrElse(4) { "" })
    }
}
