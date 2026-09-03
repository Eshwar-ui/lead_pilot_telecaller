package app.asaninnovators.leadpilot

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Ask at most once per process lifetime — Android has no permanent-deny
    // for this intent (unlike runtime permissions), so without this guard a
    // user who dismisses it would be re-prompted on every single call.
    private var askedBatteryOptimizationExemption = false

    // Separate one-time guard for the MIUI-specific autostart screen (see
    // requestMiuiAutostartIfNeeded). Staggered a call after the battery-
    // optimization ask so the two system prompts never stack in one go.
    private var askedMiuiAutostart = false

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

        // Best-effort, non-blocking: don't hold up the call for this.
        requestBackgroundSurvivalPermissionsIfNeeded()

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
     * other in the same launch.
     */
    private fun requestBackgroundSurvivalPermissionsIfNeeded() {
        if (requestBatteryOptimizationExemptionIfNeeded()) return
        requestMiuiAutostartIfNeeded()
    }

    /**
     * Xiaomi/Oppo/Vivo-class OEM battery managers routinely kill the call
     * overlay/auto-return foreground service mid-call — silently breaking
     * auto-capture on phones where the OEM recording-folder approach would
     * otherwise have worked. Surfaces the stock "allow to run in background"
     * dialog once per process; a no-op if already granted. Returns true if a
     * prompt was actually launched, so the caller can avoid stacking a second
     * one (e.g. the MIUI autostart screen) in the same call.
     */
    private fun requestBatteryOptimizationExemptionIfNeeded(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        if (askedBatteryOptimizationExemption) return false
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (powerManager == null || powerManager.isIgnoringBatteryOptimizations(packageName)) return false

        askedBatteryOptimizationExemption = true
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                )
            )
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
     * Android API for this; it's a MIUI-proprietary settings screen that
     * varies across MIUI/HyperOS versions and isn't guaranteed to exist, so
     * this is deliberately best-effort with no follow-up if it's missing.
     */
    private fun requestMiuiAutostartIfNeeded() {
        if (askedMiuiAutostart) return
        if (!isXiaomiDevice()) return
        askedMiuiAutostart = true
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

    /**
     * Explicit, user-initiated re-ask for both background-survival prompts —
     * reached only from the Recording Check diagnostics screen, where the
     * telecaller has deliberately gone looking for "why does the app keep
     * getting killed mid-call" and asked to fix it. Deliberately bypasses
     * [askedBatteryOptimizationExemption]/[askedMiuiAutostart]: those guards
     * exist so the automatic in-call ask (see [requestBackgroundSurvivalPermissionsIfNeeded])
     * can't stack a second prompt on top of itself or nag on every call — an
     * explicit tap on a settings screen is a different context where showing
     * the prompt again is exactly what was asked for, not nagging.
     *
     * Shows the battery-optimization dialog first if it isn't already
     * granted; the MIUI autostart screen (Xiaomi/Redmi/POCO only) either
     * after that, or immediately if battery optimization is already granted
     * — never both at once, so they don't stack in a single tap.
     */
    private fun requestBackgroundSurvivalPermissionsExplicitly() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val batteryExemptionNeeded = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            powerManager != null && !powerManager.isIgnoringBatteryOptimizations(packageName)

        if (batteryExemptionNeeded) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName"),
                    )
                )
                askedBatteryOptimizationExemption = true
                return
            } catch (_: ActivityNotFoundException) {
                // Fall through to the MIUI screen below.
            }
        }
        if (!isXiaomiDevice()) return
        askedMiuiAutostart = true
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
            // Screen renamed/removed on this MIUI/HyperOS version.
        }
    }

    private fun isXiaomiDevice(): Boolean {
        val brand = Build.BRAND.lowercase()
        val manufacturer = Build.MANUFACTURER.lowercase()
        return manufacturer == "xiaomi" || brand == "xiaomi" || brand == "redmi" || brand == "poco"
    }

    private companion object {
        const val CHANNEL = "lead_pilot/call_actions"
    }
}
