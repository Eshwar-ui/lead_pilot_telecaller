package app.asaninnovators.leadpilot

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Hands calls detected by [CallDetectionService] to Dart over an EventChannel.
 *
 * Events are dropped when no Flutter engine is attached (app fully killed).
 * That is deliberate rather than a queue: the phone's own call log already
 * holds every one of those calls, and the backfill sweep reads it on the next
 * app open — a second persistence mechanism here would be another thing to keep
 * in sync for calls that are already covered.
 */
object CallDetectionEventBridge : EventChannel.StreamHandler {

    const val CHANNEL = "lead_pilot/call_events"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun emit(call: DetectedCall) {
        val target = sink ?: return
        // EventSink must be touched on the main thread.
        mainHandler.post {
            try {
                target.success(call.toMap())
            } catch (_: Exception) {
                // Engine detached between the check and the post — the sweep
                // covers this call later.
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}
