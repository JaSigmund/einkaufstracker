package at.jakob.einkaufstracker

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Nimmt PDFs entgegen, die andere Apps (z.B. die joe-App) per "Teilen" oder "Oeffnen mit" schicken.
 * Die Bytes liegen hier bereit und werden von Dart per `takeSharedPdf` abgeholt (einmalig).
 * Kommt ein PDF bei laufender App, meldet `sharedPdfAvailable` das an Dart.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: ByteArray? = null
    private var quickChannel: MethodChannel? = null
    private var pendingQuick: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeSharedPdf" -> {
                    result.success(pending)
                    pending = null
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
        readPdf(intent)?.let { pending = it }
        val quick = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QUICK_CHANNEL)
        quick.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeQuickAction" -> {
                    result.success(pendingQuick)
                    pendingQuick = null
                }
                else -> result.notImplemented()
            }
        }
        quickChannel = quick
        readQuickAction(intent)?.let { pendingQuick = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readQuickAction(intent)?.let {
            pendingQuick = it
            quickChannel?.invokeMethod("quickActionAvailable", null)
            return
        }
        val bytes = readPdf(intent) ?: return
        pending = bytes
        channel?.invokeMethod("sharedPdfAvailable", null)
    }

    /** Schnellaktion aus Widget oder App-Symbol. Das Extra wird entfernt, damit ein Neuaufbau der Activity nicht noch ein Glas eintraegt. */
    private fun readQuickAction(intent: Intent?): String? {
        if (intent?.action != QUICK_ACTION) return null
        val action = intent.getStringExtra(QUICK_EXTRA)
        intent.removeExtra(QUICK_EXTRA)
        return action
    }

    private fun readPdf(intent: Intent?): ByteArray? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
        if (uri == null) return null
        return try {
            contentResolver.openInputStream(uri)?.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buf = ByteArray(16 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    if (out.size() > MAX_BYTES) return null // kein Bon, viel zu gross
                }
                out.toByteArray()
            }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        const val CHANNEL = "at.jakob.einkaufstracker/share"
        const val QUICK_CHANNEL = "at.jakob.einkaufstracker/quick"
        const val QUICK_ACTION = "at.jakob.einkaufstracker.QUICK_ACTION"
        const val QUICK_EXTRA = "quick_action"
        const val MAX_BYTES = 10 * 1024 * 1024
    }
}
