package app.asaninnovators.leadpilot

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.CallLog
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager

/**
 * Watches for ANY call ending on this phone — inbound or outbound, placed from
 * the app's own Call button or from the native dialer — and reports the number
 * to Dart, which decides whether it belongs to a lead.
 *
 * Why not a broadcast receiver: `NEW_OUTGOING_CALL` has been restricted to the
 * default dialer since Android 10, so an outbound number can't be read that
 * way. Instead the telephony listener is used only for the state transition
 * (OFFHOOK → IDLE) and the number is read from the OS call log, which the OS
 * writes within about a second of any call ending and which reports inbound and
 * outbound identically. That needs only READ_CALL_LOG + READ_PHONE_STATE, both
 * already granted for the Calls screen.
 *
 * This service knows nothing about leads. Matching, capture and upload all live
 * in Dart (see CallCaptureController) so the two detection paths — this one and
 * the on-open backfill sweep — can't drift apart.
 *
 * Separate from [CallNotesOverlayService] on purpose: that one is per-call and
 * dies with the call, this one runs for as long as the telecaller leaves the
 * setting on. Sharing one service would mean one listener registration and one
 * notification serving two different lifetimes.
 */
class CallDetectionService : Service() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var wasOffHook = false
    private var phoneListenerActive = false

    /** Number seen at RINGING, used as a cross-check for inbound calls. */
    private var ringingNumber: String? = null

    @Suppress("DEPRECATION")
    private val phoneStateListener = object : PhoneStateListener() {
        @Deprecated("Deprecated in Java")
        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
            mainHandler.post { handleCallState(state, phoneNumber) }
        }
    }

    private fun handleCallState(state: Int, phoneNumber: String?) {
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                if (!phoneNumber.isNullOrBlank()) ringingNumber = phoneNumber
            }

            TelephonyManager.CALL_STATE_OFFHOOK -> wasOffHook = true

            TelephonyManager.CALL_STATE_IDLE -> {
                val fallbackNumber = ringingNumber
                ringingNumber = null
                if (!wasOffHook) return
                wasOffHook = false
                readLatestCallWithRetries(fallbackNumber, attempt = 0)
            }
        }
    }

    /**
     * The OS writes the call-log row slightly after the IDLE callback fires, so
     * a single immediate read often misses the call that just ended. Retries a
     * few times before falling back to whatever the RINGING callback gave us
     * (inbound only — an outbound number is never reported there).
     */
    private fun readLatestCallWithRetries(fallbackNumber: String?, attempt: Int) {
        val entry = readLatestCallLogEntry()
        if (entry != null) {
            CallDetectionEventBridge.emit(entry)
            return
        }
        if (attempt < CALL_LOG_READ_ATTEMPTS) {
            mainHandler.postDelayed(
                { readLatestCallWithRetries(fallbackNumber, attempt + 1) },
                CALL_LOG_READ_RETRY_MS,
            )
            return
        }
        // Call log unreadable (permission revoked, OEM quirk) — an inbound
        // number from the RINGING callback is better than nothing. Duration is
        // unknown here, so it's reported as 0 and Dart treats it as unknown.
        if (!fallbackNumber.isNullOrBlank()) {
            CallDetectionEventBridge.emit(
                DetectedCall(
                    number = fallbackNumber,
                    isInbound = true,
                    durationSeconds = 0,
                    timestampMs = System.currentTimeMillis(),
                )
            )
        }
    }

    private fun readLatestCallLogEntry(): DetectedCall? {
        if (!hasPermission(Manifest.permission.READ_CALL_LOG)) return null
        return try {
            contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls.NUMBER,
                    CallLog.Calls.TYPE,
                    CallLog.Calls.DATE,
                    CallLog.Calls.DURATION,
                ),
                null,
                null,
                "${CallLog.Calls.DATE} DESC LIMIT 1",
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val number = cursor.getString(0) ?: return null
                if (number.isBlank()) return null
                val type = cursor.getInt(1)
                DetectedCall(
                    number = number,
                    isInbound = type == CallLog.Calls.INCOMING_TYPE,
                    durationSeconds = cursor.getLong(3),
                    timestampMs = cursor.getLong(2),
                )
            }
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun hasPermission(permission: String): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        else true

    @Suppress("DEPRECATION")
    private fun registerPhoneListener() {
        if (phoneListenerActive || !hasPermission(Manifest.permission.READ_PHONE_STATE)) return
        try {
            val tm = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
            tm.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
            phoneListenerActive = true
        } catch (_: Exception) {
            // Without READ_PHONE_STATE this throws; the backfill sweep still
            // covers every call, just later.
            phoneListenerActive = false
        }
    }

    @Suppress("DEPRECATION")
    private fun unregisterPhoneListener() {
        if (!phoneListenerActive) return
        try {
            val tm = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
            tm.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE)
        } catch (_: Exception) {
            // Nothing to do on teardown.
        }
        phoneListenerActive = false
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        registerPhoneListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        registerPhoneListener()
        // Restart if the OS kills us — the whole point is being there when a
        // call ends, which is not a moment the app can choose.
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterPhoneListener()
        mainHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    // ── Notification ──────────────────────────────────────────────────────────

    /**
     * Android requires a foreground service to be visible. IMPORTANCE_MIN keeps
     * it at the bottom of the shade and silent — this feature is meant to be
     * unremarkable, and it must also be visibly distinct from the per-call
     * notes bubble's own notification.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Lead call detection",
                NotificationManager.IMPORTANCE_MIN,
            )
        )
    }

    private fun createNotification(): Notification {
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            else @Suppress("DEPRECATION") Notification.Builder(this)

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return builder
            .setContentTitle("LeadPilot")
            .setContentText("Watching for lead calls in the background")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_STOP = "app.asaninnovators.leadpilot.STOP_CALL_DETECTION"
        const val NOTIFICATION_CHANNEL_ID = "lead_pilot_call_detection"

        // Distinct from CallNotesOverlayService's 4307 — both can be foreground
        // at once during an app-placed call, and a shared id would have one
        // service's notification replace the other's.
        const val NOTIFICATION_ID = 4308

        private const val CALL_LOG_READ_ATTEMPTS = 4
        private const val CALL_LOG_READ_RETRY_MS = 600L
    }
}

/** One ended call, as read from the OS call log. */
data class DetectedCall(
    val number: String,
    val isInbound: Boolean,
    val durationSeconds: Long,
    val timestampMs: Long,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "number" to number,
        "isInbound" to isInbound,
        "durationSeconds" to durationSeconds,
        "timestampMs" to timestampMs,
    )
}
