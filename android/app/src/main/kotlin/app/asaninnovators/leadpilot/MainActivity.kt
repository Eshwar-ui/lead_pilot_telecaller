package app.asaninnovators.leadpilot

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The system folder picker (pickRecordingsFolder) is the one method-
    // channel call here that can't resolve synchronously — its outcome is
    // only known once the user closes the picker UI, in onActivityResult.
    // Holds the in-flight call's Result until then; null when no pick is
    // pending.
    private var pendingFolderPickResult: MethodChannel.Result? = null
    // Ask at most once, EVER — Android has no permanent-deny for this intent
    // (unlike runtime permissions), so without this guard a user who
    // dismisses it would be re-prompted on every single call. Persisted in
    // SharedPreferences rather than an in-memory var: MainActivity is
    // recreated on every cold start, and the OEM battery managers this
    // permission exists to work around (MIUI's own, in particular) are
    // exactly the ones most likely to kill the app's process between calls —
    // an in-memory-only guard would silently reset and re-nag on almost
    // every call on the very phones this feature targets. See
    // hasAskedBackgroundPermission/markAskedBackgroundPermission below.
    private fun backgroundPermissionPrefs() =
        getSharedPreferences(BACKGROUND_PERMISSION_PREFS, Context.MODE_PRIVATE)

    private fun hasAskedBackgroundPermission(key: String): Boolean =
        backgroundPermissionPrefs().getBoolean(key, false)

    private fun markAskedBackgroundPermission(key: String) {
        backgroundPermissionPrefs().edit().putBoolean(key, true).apply()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCallWithNotesBubble" -> {
                        val leadId = call.argument<String>("leadId").orEmpty()
                        val leadName = call.argument<String>("leadName").orEmpty()
                        val phoneNumber = call.argument<String>("phoneNumber")
                        val leadScore = call.argument<Int>("leadScore") ?: 0
                        val temperature = call.argument<String>("temperature").orEmpty()
                        val intent = call.argument<String>("intent").orEmpty()
                        val scriptOpeningLine = call.argument<String>("scriptOpeningLine").orEmpty()
                        @Suppress("UNCHECKED_CAST")
                        val memoryFacts = (call.argument<List<*>>("memoryFacts") ?: emptyList<String>())
                            .filterIsInstance<String>()
                        val lastCallTs = call.argument<String>("lastCallTs").orEmpty()
                        val lastCallScore = call.argument<Int>("lastCallScore") ?: 0
                        val lastCallSummary = call.argument<String>("lastCallSummary").orEmpty()

                        if (phoneNumber.isNullOrBlank()) {
                            result.success(
                                mapOf(
                                    "launched" to false,
                                    "overlayPermissionGranted" to hasOverlayPermission(),
                                )
                            )
                            return@setMethodCallHandler
                        }

                        result.success(
                            startCallWithNotesBubble(
                                leadId, leadName, phoneNumber,
                                leadScore, temperature, intent,
                                scriptOpeningLine, memoryFacts,
                                lastCallTs, lastCallScore, lastCallSummary,
                            )
                        )
                    }

                    "getCallNotes" -> {
                        val leadId = call.argument<String>("leadId").orEmpty()
                        result.success(getCallNotes(leadId))
                    }

                    "stopCallNotesBubble" -> {
                        stopCallNotesBubble()
                        result.success(true)
                    }

                    "showCallAppChooser" -> {
                        val phoneNumber = call.argument<String>("phoneNumber")

                        if (phoneNumber.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        result.success(showCallAppChooser(phoneNumber))
                    }

                    "startCallDetection" -> {
                        startCallDetection()
                        result.success(true)
                    }

                    "stopCallDetection" -> {
                        stopCallDetection()
                        result.success(true)
                    }

                    "requestBackgroundPermissions" -> {
                        requestBackgroundSurvivalPermissionsExplicitly()
                        result.success(true)
                    }

                    "findRecentAudioRecordings" -> {
                        @Suppress("UNCHECKED_CAST")
                        val hints = (call.argument<List<*>>("relativePathHints") ?: emptyList<String>())
                            .filterIsInstance<String>()
                        val limit = call.argument<Int>("limit") ?: 200
                        result.success(
                            CallRecordingMediaStore.queryRecentAudio(applicationContext, hints, limit)
                        )
                    }

                    "materializeMediaStoreRecording" -> {
                        val contentUri = call.argument<String>("contentUri")
                        if (contentUri.isNullOrBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        result.success(
                            CallRecordingMediaStore.materializeToCache(applicationContext, contentUri)
                        )
                    }

                    "pickRecordingsFolder" -> {
                        if (pendingFolderPickResult != null) {
                            // A pick is already in flight — resolving a second
                            // concurrent call with an error rather than
                            // overwriting pendingFolderPickResult, which would
                            // leave the first call's Future unresolved forever.
                            result.error("PICK_IN_PROGRESS", "A folder pick is already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingFolderPickResult = result
                        launchFolderPicker()
                    }

                    "hasRecordingsFolderAccess" -> {
                        result.success(currentGrantedFolderUri() != null)
                    }

                    "listRecordingsInGrantedFolder" -> {
                        val treeUri = currentGrantedFolderUri()
                        val limit = call.argument<Int>("limit") ?: 200
                        result.success(
                            if (treeUri == null) {
                                emptyList<Map<String, Any?>>()
                            } else {
                                RecordingsFolderAccess.listRecordings(applicationContext, treeUri, limit)
                            }
                        )
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CallDetectionEventBridge.CHANNEL,
        ).setStreamHandler(CallDetectionEventBridge)
    }

    /**
     * Starts the always-on listener for calls placed or received outside the
     * app. Only ever called once the telecaller has switched on "Auto-detect
     * lead calls" in Profile.
     */
    private fun startCallDetection() {
        // Same OEM battery managers that kill the per-call overlay kill this
        // one, and here it's worse: the service has to survive until whenever
        // the next call happens, not just to the end of the current one.
        requestBackgroundSurvivalPermissionsIfNeeded()

        val serviceIntent = Intent(this, CallDetectionService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopCallDetection() {
        stopService(Intent(this, CallDetectionService::class.java))
    }

    private fun startCallWithNotesBubble(
        leadId: String,
        leadName: String,
        phoneNumber: String,
        leadScore: Int = 0,
        temperature: String = "",
        intent: String = "",
        scriptOpeningLine: String = "",
        memoryFacts: List<String> = emptyList(),
        lastCallTs: String = "",
        lastCallScore: Int = 0,
        lastCallSummary: String = "",
    ): Map<String, Any> {
        if (!hasOverlayPermission()) {
            openOverlayPermissionSettings()
            return mapOf(
                "launched" to false,
                "overlayPermissionGranted" to false,
            )
        }

        val serviceIntent = Intent(this, CallNotesOverlayService::class.java).apply {
            putExtra(CallNotesOverlayService.EXTRA_LEAD_ID, leadId)
            putExtra(CallNotesOverlayService.EXTRA_LEAD_NAME, leadName)
            putExtra(CallNotesOverlayService.EXTRA_PHONE_NUMBER, phoneNumber)
            putExtra(CallNotesOverlayService.EXTRA_LEAD_SCORE, leadScore)
            putExtra(CallNotesOverlayService.EXTRA_TEMPERATURE, temperature)
            putExtra(CallNotesOverlayService.EXTRA_INTENT, intent)
            putExtra(CallNotesOverlayService.EXTRA_SCRIPT_OPENING, scriptOpeningLine)
            putStringArrayListExtra(
                CallNotesOverlayService.EXTRA_MEMORY_FACTS,
                ArrayList(memoryFacts),
            )
            putExtra(CallNotesOverlayService.EXTRA_LAST_CALL_TS, lastCallTs)
            putExtra(CallNotesOverlayService.EXTRA_LAST_CALL_SCORE, lastCallScore)
            putExtra(CallNotesOverlayService.EXTRA_LAST_CALL_SUMMARY, lastCallSummary)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        val launched = showCallAppChooser(phoneNumber)
        if (!launched) {
            stopCallNotesBubble()
        }

        // Deliberately AFTER the dial chooser above, not before: this can show
        // a Settings/MIUI screen via its own startActivity(), and firing it
        // first meant it could visually pre-empt or interleave with the dial
        // chooser the telecaller actually tapped "Call" to see. Best-effort,
        // non-blocking either way — this never holds up the call itself.
        requestBackgroundSurvivalPermissionsIfNeeded()

        return mapOf(
            "launched" to launched,
            "overlayPermissionGranted" to true,
        )
    }

    private fun showCallAppChooser(phoneNumber: String): Boolean {
        val dialIntent = Intent(Intent.ACTION_DIAL).apply {
            data = Uri.parse("tel:$phoneNumber")
        }
        val chooser = Intent.createChooser(dialIntent, "Complete action using")

        return try {
            startActivity(chooser)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun getCallNotes(leadId: String): String {
        if (leadId.isBlank()) return ""

        val preferences = getSharedPreferences(
            CallNotesOverlayService.NOTES_PREFERENCES,
            Context.MODE_PRIVATE,
        )
        return preferences.getString(CallNotesOverlayService.noteKey(leadId), "").orEmpty()
    }

    private fun stopCallNotesBubble() {
        val intent = Intent(this, CallNotesOverlayService::class.java).apply {
            action = CallNotesOverlayService.ACTION_STOP
        }
        stopService(intent)
    }

    private fun hasOverlayPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)
    }

    private fun openOverlayPermissionSettings() {
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName"),
                )
            } else {
                Intent(Settings.ACTION_SETTINGS)
            }
        startActivity(intent)
    }

    /**
     * Requests whichever background-survival permission is still missing —
     * at most one system prompt per call, so two don't stack on top of each
     * other in the same launch. The one-shot guards are persisted (see
     * [hasAskedBackgroundPermission]), so this only ever prompts once, ever,
     * per permission — not once per process.
     */
    private fun requestBackgroundSurvivalPermissionsIfNeeded() {
        requestBackgroundSurvivalPermissions(force = false)
    }

    /**
     * Explicit, user-initiated re-ask for both background-survival prompts —
     * reached only from the Recording Check diagnostics screen, where the
     * telecaller has deliberately gone looking for "why does the app keep
     * getting killed mid-call" and asked to fix it. Bypasses the one-shot
     * guards: those exist so the automatic in-call ask can't nag on every
     * call, but an explicit tap on a settings screen is a different context
     * where showing the prompt again is exactly what was asked for.
     */
    private fun requestBackgroundSurvivalPermissionsExplicitly() {
        requestBackgroundSurvivalPermissions(force = true)
    }

    /**
     * Shows the battery-optimization dialog first if it isn't already
     * granted; the MIUI autostart screen (Xiaomi/Redmi/POCO only) either
     * after that, or immediately if battery optimization is already granted
     * — never both at once, so they don't stack in a single tap. When
     * [force] is false (the automatic in-call/auto-detect path), each prompt
     * is skipped once it's already been shown; when true (the explicit
     * Recording-Check re-ask), both guards are bypassed.
     */
    private fun requestBackgroundSurvivalPermissions(force: Boolean) {
        if (requestBatteryOptimizationExemption(force)) return
        requestMiuiAutostart(force)
    }

    /**
     * Xiaomi/Oppo/Vivo-class OEM battery managers routinely kill the call
     * overlay/auto-return foreground service mid-call — silently breaking
     * auto-capture on phones where the OEM recording-folder approach would
     * otherwise have worked. Surfaces the stock "allow to run in background"
     * dialog once, ever; a no-op if already granted. Returns true if a
     * prompt was actually shown, so the caller can avoid stacking a second
     * one (e.g. the MIUI autostart screen) in the same call.
     */
    private fun requestBatteryOptimizationExemption(force: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        if (!force && hasAskedBackgroundPermission(PREF_ASKED_BATTERY_OPTIMIZATION)) return false
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        // Re-checked live (not cached) every time: unlike MIUI autostart below,
        // this has a real OS query, so it self-heals even if the "asked"
        // guard were ever wrong — no reason to prompt again once genuinely granted.
        if (powerManager == null || powerManager.isIgnoringBatteryOptimizations(packageName)) return false

        return try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                )
            )
            // Only mark "asked" once the prompt actually launched — if it
            // threw below, nothing was ever shown, so the MIUI check that
            // follows in requestBackgroundSurvivalPermissions is not "stacking
            // a second prompt", it's the only prompt shown this call.
            markAskedBackgroundPermission(PREF_ASKED_BATTERY_OPTIMIZATION)
            true
        } catch (_: ActivityNotFoundException) {
            // A handful of OEM ROMs strip this action; nothing more we can do.
            false
        }
    }

    /**
     * MIUI/HyperOS gates background execution behind its own "Autostart"
     * permission, entirely separate from stock Android's battery-optimization
     * exemption above — a Xiaomi/Redmi/POCO phone can grant the standard
     * exemption and still have MIUI itself kill the call-overlay/auto-return
     * service, which is exactly the "recording exists on the phone but
     * LeadPilot never finds it" failure mode on this OEM. There's no stock
     * Android API to check whether this was already granted — it's a
     * MIUI-proprietary settings screen with no queryable status — so the
     * persisted "asked" guard is the ONLY thing preventing a re-prompt; it is
     * deliberately best-effort with no follow-up if the screen is missing.
     */
    private fun requestMiuiAutostart(force: Boolean) {
        if (!force && hasAskedBackgroundPermission(PREF_ASKED_MIUI_AUTOSTART)) return
        if (!isXiaomiDevice()) return
        markAskedBackgroundPermission(PREF_ASKED_MIUI_AUTOSTART)
        try {
            startActivity(
                Intent().apply {
                    component = ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity",
                    )
                }
            )
        } catch (_: Exception) {
            // Screen renamed/removed on this MIUI/HyperOS version — no
            // universal successor to fall back to.
        }
    }

    private fun isXiaomiDevice(): Boolean {
        val brand = Build.BRAND.lowercase()
        val manufacturer = Build.MANUFACTURER.lowercase()
        return manufacturer == "xiaomi" || brand == "xiaomi" || brand == "redmi" || brand == "poco"
    }

    /**
     * Launches the system folder picker so the telecaller can grant durable
     * access to their call-recordings folder — the fallback for OEMs (MIUI
     * in particular) whose dialer writes into a `.nomedia`-marked folder,
     * which [CallRecordingMediaStore]'s query can never see: `.nomedia` opts
     * a tree out of the media scanner, not out of the Storage Access
     * Framework, which this reads instead. The result comes back in
     * [onActivityResult], not here — see [pendingFolderPickResult].
     */
    private fun launchFolderPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        // Best-effort nudge toward the known folder on Xiaomi devices so the
        // telecaller doesn't have to hunt for it — OEM document-tree URI
        // formats are undocumented and vary, so any failure here just means
        // the picker opens at its default location instead.
        if (isXiaomiDevice()) {
            try {
                intent.putExtra(
                    DocumentsContract.EXTRA_INITIAL_URI,
                    Uri.parse(
                        "content://com.android.externalstorage.documents/document/" +
                            "primary%3AMIUI%2Fsound_recorder",
                    ),
                )
            } catch (_: Exception) {
                // Fall through with no hint.
            }
        }
        try {
            startActivityForResult(intent, REQUEST_CODE_PICK_RECORDINGS_FOLDER)
        } catch (_: ActivityNotFoundException) {
            val pending = pendingFolderPickResult
            pendingFolderPickResult = null
            pending?.success(null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_CODE_PICK_RECORDINGS_FOLDER) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingFolderPickResult
        pendingFolderPickResult = null

        val treeUri = data?.data
        if (resultCode != RESULT_OK || treeUri == null) {
            pending?.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            recordingsFolderPrefs().edit().putString(PREF_GRANTED_FOLDER_URI, treeUri.toString()).apply()
            pending?.success(treeUri.toString())
        } catch (_: Exception) {
            // A grant we can't persist is worse than useless — it would need
            // re-asking on every launch, defeating the entire point. Treat
            // this as a full failure, not a degraded success.
            pending?.success(null)
        }
    }

    private fun recordingsFolderPrefs() =
        getSharedPreferences(RECORDINGS_FOLDER_PREFS, Context.MODE_PRIVATE)

    /**
     * The persisted tree URI, if the grant is still valid — re-checked
     * against [android.content.ContentResolver.getPersistedUriPermissions]
     * rather than trusted blindly, since a grant can be revoked outside the
     * app (the user clearing storage permissions, a factory-reset-adjacent
     * "reset app preferences", etc.).
     */
    private fun currentGrantedFolderUri(): String? {
        val saved = recordingsFolderPrefs().getString(PREF_GRANTED_FOLDER_URI, null) ?: return null
        val stillValid = contentResolver.persistedUriPermissions.any {
            it.uri.toString() == saved && it.isReadPermission
        }
        if (!stillValid) {
            recordingsFolderPrefs().edit().remove(PREF_GRANTED_FOLDER_URI).apply()
            return null
        }
        return saved
    }

    private companion object {
        const val CHANNEL = "lead_pilot/call_actions"
        const val BACKGROUND_PERMISSION_PREFS = "lead_pilot_background_permissions"
        const val PREF_ASKED_BATTERY_OPTIMIZATION = "asked_battery_optimization_exemption"
        const val PREF_ASKED_MIUI_AUTOSTART = "asked_miui_autostart"
        const val RECORDINGS_FOLDER_PREFS = "lead_pilot_recordings_folder"
        const val PREF_GRANTED_FOLDER_URI = "granted_tree_uri"
        const val REQUEST_CODE_PICK_RECORDINGS_FOLDER = 4201
    }
}
