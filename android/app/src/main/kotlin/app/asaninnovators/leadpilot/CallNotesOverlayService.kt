package app.asaninnovators.leadpilot

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CallNotesOverlayService : Service() {

    // ── Layout ────────────────────────────────────────────────────────────────
    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var postCallScreenLaunched = false
    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Lead context ──────────────────────────────────────────────────────────
    private var leadId = ""
    private var leadName = ""
    private var phoneNumber = ""
    private var leadScore = 0
    private var temperature = ""
    private var leadIntent = ""
    private var scriptOpeningLine = ""
    private var memoryFacts: List<String> = emptyList()
    private var lastCallTs = ""
    private var lastCallScore = 0
    private var lastCallSummary = ""

    private val notesPreferences by lazy {
        getSharedPreferences(NOTES_PREFERENCES, Context.MODE_PRIVATE)
    }

    // ── Phone-state: auto-return when call ends ────────────────────────────────
    private var wasOffHook = false
    private var phoneListenerActive = false

    @Suppress("DEPRECATION")
    private val phoneStateListener = object : PhoneStateListener() {
        @Deprecated("Deprecated in Java")
        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
            mainHandler.post { handleCallState(state) }
        }
    }

    private fun handleCallState(state: Int) {
        when (state) {
            TelephonyManager.CALL_STATE_OFFHOOK -> wasOffHook = true
            TelephonyManager.CALL_STATE_IDLE -> if (wasOffHook) {
                wasOffHook = false
                showCallEndedBubble()
            }
        }
    }

    private fun hasPhoneStatePermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
                PackageManager.PERMISSION_GRANTED
        else true // granted at install time on pre-Marshmallow

    /// Starts observing call state for auto-return. READ_PHONE_STATE is a
    /// runtime permission — if it isn't granted, calling listen() throws a
    /// SecurityException that would crash the service, so we guard and swallow
    /// it. The overlay still works; only auto-return is disabled.
    @Suppress("DEPRECATION")
    private fun registerPhoneListener() {
        if (phoneListenerActive || !hasPhoneStatePermission()) return
        try {
            val tm = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
            tm.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
            phoneListenerActive = true
        } catch (_: SecurityException) {
            phoneListenerActive = false
        } catch (_: Exception) {
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
            // ignore — nothing we can do on teardown
        }
        phoneListenerActive = false
    }

    // ── Service lifecycle ─────────────────────────────────────────────────────

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        registerPhoneListener()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { stopSelf(); return START_NOT_STICKY }

        // START_STICKY redelivers with a null Intent when the OS restarts
        // this service after the process was killed — with no saved state to
        // restore (Android doesn't retain our custom extras across that),
        // leadId/phoneNumber/etc. would all fall back to "" below and
        // `showCollapsedBubble()` would still fire unconditionally,
        // resurfacing a blank, non-functional bubble bound to no lead. Stop
        // cleanly instead of showing something broken.
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        leadId = intent.getStringExtra(EXTRA_LEAD_ID).orEmpty()
        leadName = intent.getStringExtra(EXTRA_LEAD_NAME).orEmpty()
        phoneNumber = intent.getStringExtra(EXTRA_PHONE_NUMBER).orEmpty()
        leadScore = intent.getIntExtra(EXTRA_LEAD_SCORE, 0)
        temperature = intent.getStringExtra(EXTRA_TEMPERATURE).orEmpty()
        leadIntent = intent.getStringExtra(EXTRA_INTENT).orEmpty()
        scriptOpeningLine = intent.getStringExtra(EXTRA_SCRIPT_OPENING).orEmpty()
        memoryFacts = intent.getStringArrayListExtra(EXTRA_MEMORY_FACTS) ?: emptyList()
        lastCallTs = intent.getStringExtra(EXTRA_LAST_CALL_TS).orEmpty()
        lastCallScore = intent.getIntExtra(EXTRA_LAST_CALL_SCORE, 0)
        lastCallSummary = intent.getStringExtra(EXTRA_LAST_CALL_SUMMARY).orEmpty()

        // Retry in case the phone-state permission was granted after onCreate.
        registerPhoneListener()

        if (overlayView == null) showCollapsedBubble()

        return START_STICKY
    }

    override fun onDestroy() {
        unregisterPhoneListener()
        removeOverlay()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    // ── Collapsed bubble ──────────────────────────────────────────────────────

    private fun showCollapsedBubble(x: Int = dp(18), y: Int = dp(160)) {
        val bubble = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            background = roundedBackground(Color.rgb(37, 99, 235), dp(22).toFloat())
            elevation = dp(8).toFloat()
        }

        val initials = TextView(this).apply {
            text = if (leadName.isBlank()) "TC" else leadName.take(2).uppercase()
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        bubble.addView(initials, LinearLayout.LayoutParams(dp(56), dp(28)))

        if (leadScore > 0) {
            val badge = TextView(this).apply {
                text = "$leadScore"
                textSize = 9f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(scoreColor(leadScore))
                gravity = Gravity.CENTER
                background = roundedBackground(Color.WHITE, dp(4).toFloat())
                setPadding(dp(4), 0, dp(4), 0)
            }
            bubble.addView(badge, LinearLayout.LayoutParams(dp(28), dp(14)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(2)
            })
        }

        val params = baseLayoutParams(dp(56), dp(70)).apply {
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            this.x = x; this.y = y
        }
        attachOverlay(bubble, params)
        makeDraggable(bubble, params) { showExpandedPanel(params.x, params.y) }
    }

    // ── Call-ended bubble (auto-return) ───────────────────────────────────────

    private fun showCallEndedBubble() {
        val curX = layoutParams?.x ?: dp(18)
        val curY = layoutParams?.y ?: dp(160)

        val banner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(10), dp(10), dp(10))
            background = roundedBackground(Color.rgb(22, 163, 74), dp(16).toFloat())
            elevation = dp(10).toFloat()
        }

        val checkText = TextView(this).apply {
            text = "✓ Call ended"
            textSize = 11f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val returnText = TextView(this).apply {
            text = "Tap to return"
            textSize = 9f
            setTextColor(Color.argb(220, 255, 255, 255))
            gravity = Gravity.CENTER
        }
        banner.addView(checkText, linearParams(matchWidth = true))
        banner.addView(returnText, linearParams(matchWidth = true, topMargin = dp(2)))

        val params = baseLayoutParams(dp(110), WindowManager.LayoutParams.WRAP_CONTENT).apply {
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            this.x = curX; this.y = curY
        }
        attachOverlay(banner, params)
        makeDraggable(banner, params)

        banner.setOnClickListener {
            openPostCallScreen()
            stopSelf()
        }

        // Auto-navigate after 4 s if user doesn't tap
        mainHandler.postDelayed({
            if (overlayView != null) {
                openPostCallScreen()
                stopSelf()
            }
        }, 4_000)
    }

    // ── Expanded panel ────────────────────────────────────────────────────────

    private fun showExpandedPanel(anchorX: Int, anchorY: Int) {
        val panelWidth = dp(320)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = roundedBackground(Color.WHITE, dp(16).toFloat(), Color.rgb(220, 225, 240))
            elevation = dp(12).toFloat()
        }

        // ── Header ────────────────────────────────────────────────────────────
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(12), dp(10), dp(10))
            background = roundedTopBackground(Color.rgb(245, 248, 255), dp(16).toFloat())
        }
        val nameCol = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        nameCol.addView(TextView(this).apply {
            text = leadName.ifBlank { "Unknown" }
            textSize = 15f; typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.rgb(15, 23, 42)); maxLines = 1
        }, linearParams())
        nameCol.addView(TextView(this).apply {
            text = phoneNumber
            textSize = 11f; setTextColor(Color.rgb(100, 116, 139)); maxLines = 1
        }, linearParams(topMargin = dp(1)))
        header.addView(nameCol, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        if (leadScore > 0) {
            header.addView(TextView(this).apply {
                text = "$leadScore"
                textSize = 12f; typeface = Typeface.DEFAULT_BOLD
                setTextColor(scoreColor(leadScore))
                gravity = Gravity.CENTER
                setPadding(dp(8), dp(3), dp(8), dp(3))
                background = roundedBackground(scoreBgColor(leadScore), dp(10).toFloat())
            }, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { rightMargin = dp(6) })
        }

        header.addView(iconButton("—") { showCollapsedBubble(anchorX, anchorY) })
        header.addView(iconButton("✕") {
            hideKeyboardGlobal()
            openPostCallScreen()
            stopSelf()
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { leftMargin = dp(4) })
        root.addView(header, linearParams(matchWidth = true))

        // ── Chips ─────────────────────────────────────────────────────────────
        if (leadIntent.isNotBlank() || temperature.isNotBlank()) {
            val chipRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(dp(14), dp(4), dp(14), dp(8))
            }
            if (leadIntent.isNotBlank())
                chipRow.addView(chip(leadIntent, Color.rgb(30, 64, 175), Color.rgb(219, 234, 254)))
            if (temperature.isNotBlank()) {
                val (tc, tBg) = tempColors(temperature)
                chipRow.addView(chip(temperature.replaceFirstChar { it.uppercase() }, tc, tBg)
                    .apply { (layoutParams as? LinearLayout.LayoutParams)?.leftMargin = dp(6) })
            }
            root.addView(chipRow, linearParams(matchWidth = true))
        }

        // ── Tabs ──────────────────────────────────────────────────────────────
        val tabRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(14), 0, dp(14), 0)
        }
        val tabContent = FrameLayout(this)
        val ctxView = buildContextTab()
        val notesView = buildNotesTab()
        tabContent.addView(ctxView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT))
        tabContent.addView(notesView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT))
        notesView.visibility = View.GONE

        val ctxTab = tabButton("Context", true)
        val notesTabBtn = tabButton("Notes", false)
        ctxTab.setOnClickListener {
            ctxView.visibility = View.VISIBLE; notesView.visibility = View.GONE
            setTabActive(ctxTab, true); setTabActive(notesTabBtn, false)
        }
        notesTabBtn.setOnClickListener {
            ctxView.visibility = View.GONE; notesView.visibility = View.VISIBLE
            setTabActive(ctxTab, false); setTabActive(notesTabBtn, true)
        }
        tabRow.addView(ctxTab)
        tabRow.addView(notesTabBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { leftMargin = dp(8) })
        root.addView(tabRow, linearParams(matchWidth = true))
        root.addView(View(this).apply {
            setBackgroundColor(Color.rgb(226, 232, 240))
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)))
        root.addView(tabContent, linearParams(matchWidth = true))

        val params = baseLayoutParams(panelWidth, WindowManager.LayoutParams.WRAP_CONTENT).apply {
            flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
            this.x = anchorX; this.y = anchorY
        }
        attachOverlay(root, params)
        makeDraggable(header, params)
    }

    // ── Context tab ───────────────────────────────────────────────────────────

    private fun buildContextTab(): View {
        val scroll = ScrollView(this).apply { isVerticalScrollBarEnabled = false }
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(14))
        }

        // Last call card
        if (lastCallTs.isNotBlank()) {
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(10), dp(10), dp(10), dp(10))
                background = roundedBackground(Color.rgb(240, 253, 244), dp(10).toFloat(), Color.rgb(187, 247, 208))
            }
            val cardHeader = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            cardHeader.addView(TextView(this).apply {
                text = "LAST CALL"
                textSize = 9f; typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.rgb(22, 101, 52)); letterSpacing = 0.08f
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            if (lastCallScore > 0) {
                cardHeader.addView(TextView(this).apply {
                    text = "Score $lastCallScore"
                    textSize = 10f; typeface = Typeface.DEFAULT_BOLD
                    setTextColor(scoreColor(lastCallScore))
                    setPadding(dp(6), dp(2), dp(6), dp(2))
                    background = roundedBackground(scoreBgColor(lastCallScore), dp(6).toFloat())
                })
            }
            card.addView(cardHeader, linearParams(matchWidth = true))

            val dateStr = formatCallDate(lastCallTs)
            card.addView(TextView(this).apply {
                text = dateStr
                textSize = 11.5f; setTextColor(Color.rgb(20, 83, 45))
                setPadding(0, dp(4), 0, 0)
            }, linearParams(matchWidth = true))

            if (lastCallSummary.isNotBlank()) {
                card.addView(TextView(this).apply {
                    text = lastCallSummary
                    textSize = 12f; setTextColor(Color.rgb(22, 101, 52))
                    setLineSpacing(0f, 1.35f)
                    setPadding(0, dp(3), 0, 0)
                }, linearParams(matchWidth = true))
            }
            col.addView(card, linearParams(matchWidth = true))
        }

        // AI Script
        if (scriptOpeningLine.isNotBlank()) {
            val scriptBox = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(10), dp(10), dp(10), dp(10))
                background = roundedBackground(Color.rgb(238, 242, 255), dp(10).toFloat(), Color.rgb(199, 210, 254))
            }
            scriptBox.addView(TextView(this).apply {
                text = "AI SCRIPT"
                textSize = 9f; typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.rgb(99, 102, 241)); letterSpacing = 0.08f
            }, linearParams(matchWidth = true))
            scriptBox.addView(TextView(this).apply {
                text = "\"$scriptOpeningLine\""
                textSize = 13f; setTextColor(Color.rgb(30, 27, 75))
                setLineSpacing(0f, 1.4f)
            }, linearParams(matchWidth = true, topMargin = dp(4)))
            col.addView(scriptBox, linearParams(matchWidth = true, topMargin = if (lastCallTs.isNotBlank()) dp(10) else 0))
        }

        // Memory facts
        if (memoryFacts.isNotEmpty()) {
            col.addView(TextView(this).apply {
                text = "KEY FACTS"
                textSize = 9f; typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.rgb(100, 116, 139)); letterSpacing = 0.08f
            }, linearParams(matchWidth = true, topMargin = dp(12)))
            for (fact in memoryFacts) {
                val row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL; gravity = Gravity.TOP
                    setPadding(0, dp(5), 0, 0)
                }
                row.addView(TextView(this).apply {
                    text = "•"; textSize = 13f
                    setTextColor(Color.rgb(99, 102, 241)); setPadding(0, 0, dp(6), 0)
                }, linearParams())
                row.addView(TextView(this).apply {
                    text = fact; textSize = 12.5f
                    setTextColor(Color.rgb(30, 41, 59)); setLineSpacing(0f, 1.35f)
                }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                col.addView(row, linearParams(matchWidth = true))
            }
        }

        if (scriptOpeningLine.isBlank() && memoryFacts.isEmpty() && lastCallTs.isBlank()) {
            col.addView(TextView(this).apply {
                text = "Open the lead detail screen before calling\nto load context here."
                textSize = 12.5f; setTextColor(Color.rgb(100, 116, 139))
                gravity = Gravity.CENTER; setPadding(dp(16), dp(20), dp(16), dp(20))
            }, linearParams(matchWidth = true))
        }

        scroll.addView(col, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT))
        return scroll
    }

    // ── Notes tab ─────────────────────────────────────────────────────────────

    private fun buildNotesTab(): View {
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(14))
        }
        val saved = notesPreferences.getString(noteKey(leadId), "").orEmpty()
        val field = EditText(this).apply {
            setText(saved); hint = "Add call notes…"; textSize = 13.5f
            minLines = 4; maxLines = 7; gravity = Gravity.TOP or Gravity.START
            setTextColor(Color.rgb(15, 23, 42)); setHintTextColor(Color.rgb(148, 163, 184))
            background = roundedBackground(Color.rgb(248, 250, 252), dp(10).toFloat(), Color.rgb(203, 213, 225))
            setPadding(dp(12), dp(10), dp(12), dp(10))
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) =
                    saveNotes(s?.toString().orEmpty())
                override fun afterTextChanged(s: Editable?) = Unit
            })
        }
        col.addView(field, linearParams(matchWidth = true))
        col.addView(Button(this).apply {
            text = "Save & Close"; textSize = 13f; isAllCaps = false
            setTextColor(Color.WHITE)
            background = roundedBackground(Color.rgb(37, 99, 235), dp(10).toFloat())
            setPadding(dp(12), dp(10), dp(12), dp(10))
            setOnClickListener {
                saveNotes(field.text?.toString().orEmpty())
                hideKeyboard(field); openPostCallScreen(); stopSelf()
            }
        }, linearParams(matchWidth = true, topMargin = dp(10)))
        return col
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun tabButton(label: String, active: Boolean): TextView =
        TextView(this).apply {
            text = label; textSize = 12.5f; typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER; setPadding(dp(14), dp(7), dp(14), dp(7))
            setTabActive(this, active)
        }

    private fun setTabActive(tab: TextView, active: Boolean) {
        if (active) { tab.setTextColor(Color.rgb(37, 99, 235)); tab.background = roundedBackground(Color.rgb(219, 234, 254), dp(12).toFloat()) }
        else { tab.setTextColor(Color.rgb(100, 116, 139)); tab.background = null }
    }

    private fun chip(label: String, textColor: Int, bgColor: Int): TextView =
        TextView(this).apply {
            text = label; textSize = 10f; typeface = Typeface.DEFAULT_BOLD
            setTextColor(textColor); setPadding(dp(8), dp(3), dp(8), dp(3))
            background = roundedBackground(bgColor, dp(8).toFloat())
        }

    private fun iconButton(symbol: String, onClick: () -> Unit): TextView =
        TextView(this).apply {
            text = symbol; textSize = 14f; setTextColor(Color.rgb(100, 116, 139))
            gravity = Gravity.CENTER; setPadding(dp(8), dp(6), dp(8), dp(6))
            minWidth = dp(36); minimumWidth = dp(36); setOnClickListener { onClick() }
        }

    private fun scoreColor(s: Int) = when { s >= 70 -> Color.rgb(21, 128, 61); s >= 40 -> Color.rgb(180, 83, 9); else -> Color.rgb(185, 28, 28) }
    private fun scoreBgColor(s: Int) = when { s >= 70 -> Color.rgb(220, 252, 231); s >= 40 -> Color.rgb(255, 237, 213); else -> Color.rgb(254, 226, 226) }
    private fun tempColors(t: String): Pair<Int, Int> = when (t.lowercase()) {
        "hot" -> Pair(Color.rgb(185, 28, 28), Color.rgb(254, 226, 226))
        "warm" -> Pair(Color.rgb(180, 83, 9), Color.rgb(255, 237, 213))
        else -> Pair(Color.rgb(30, 64, 175), Color.rgb(219, 234, 254))
    }

    private fun formatCallDate(isoTs: String): String {
        return try {
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
            val date = sdf.parse(isoTs.take(19)) ?: return isoTs
            val now = Date()
            val diffMs = now.time - date.time
            val diffDays = (diffMs / 86_400_000).toInt()
            val timePart = SimpleDateFormat("h:mm a", Locale.getDefault()).format(date)
            when {
                diffDays == 0 -> "Today · $timePart"
                diffDays == 1 -> "Yesterday · $timePart"
                diffDays < 7 -> "$diffDays days ago · $timePart"
                else -> SimpleDateFormat("d MMM · h:mm a", Locale.getDefault()).format(date)
            }
        } catch (_: Exception) { isoTs }
    }

    /// windowManager.addView() can throw even after MainActivity's upfront
    /// permission check passed — the permission can be revoked mid-call (user
    /// toggles it in Settings, OEM battery-saver, an OS update), and this is
    /// called again later for the call-ended bubble / expanded panel, not just
    /// at start. Previously unguarded: any throw here crashed the whole
    /// service silently — the app kept working (the dialer had already been
    /// launched separately), so the only visible symptom was "no overlay,
    /// no error, no idea why." Guard it and tell the user via a Toast, which
    /// (unlike this overlay) doesn't need SYSTEM_ALERT_WINDOW to display.
    private fun attachOverlay(view: View, params: WindowManager.LayoutParams) {
        removeOverlay()
        try {
            windowManager.addView(view, params)
            overlayView = view
            layoutParams = params
        } catch (_: Exception) {
            overlayView = null
            layoutParams = null
            mainHandler.post {
                Toast.makeText(
                    this,
                    "Couldn't show the call notes overlay — check \"Display over other apps\" permission for Asan Telecaller.",
                    Toast.LENGTH_LONG,
                ).show()
            }
            stopSelf()
        }
    }

    private fun removeOverlay() {
        overlayView?.let { try { windowManager.removeView(it) } catch (_: Exception) {} }
        overlayView = null; layoutParams = null
    }

    private fun makeDraggable(handle: View, params: WindowManager.LayoutParams, onClick: (() -> Unit)? = null) {
        var startX = 0; var startY = 0; var startRawX = 0f; var startRawY = 0f; var moved = false
        handle.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> { startX = params.x; startY = params.y; startRawX = event.rawX; startRawY = event.rawY; moved = false; true }
                MotionEvent.ACTION_MOVE -> { val dx = (event.rawX - startRawX).toInt(); val dy = (event.rawY - startRawY).toInt(); if (kotlin.math.abs(dx) > dp(4) || kotlin.math.abs(dy) > dp(4)) moved = true; params.x = startX + dx; params.y = startY + dy; overlayView?.let { try { windowManager.updateViewLayout(it, params) } catch (_: Exception) {} }; true }
                MotionEvent.ACTION_UP -> { if (!moved) { v.performClick(); onClick?.invoke() }; true }
                else -> false
            }
        }
    }

    private fun saveNotes(notes: String) { if (leadId.isBlank()) return; notesPreferences.edit().putString(noteKey(leadId), notes).apply() }
    private fun hideKeyboard(view: View) { (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(view.windowToken, 0) }
    private fun hideKeyboardGlobal() { (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(overlayView?.windowToken, 0) }

    private fun openPostCallScreen() {
        if (leadId.isBlank()) return
        // A manual tap on the "Call ended" banner and its own 4s auto-navigate
        // fallback (see showCallEndedBubble) both call this. stopSelf() from
        // the tap doesn't destroy the service synchronously, so the delayed
        // Handler callback can still fire in that window before overlayView is
        // nulled — without this guard both paths fire the same deep link,
        // double-triggering the "?new=1" auto-capture flow on the Dart side.
        if (postCallScreenLaunched) return
        postCallScreenLaunched = true
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            // `?new=1` tells the router this is "just finished a call" so it
            // triggers auto-capture even on a cold start (Dart `extra` can't
            // survive a URI-only deep link into a killed process).
            data = Uri.parse("leadpilot://app/leads/$leadId/post-call?new=1")
            setPackage(packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        })
    }

    private fun baseLayoutParams(width: Int, height: Int): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE
        return WindowManager.LayoutParams(width, height, type, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
    }

    private fun linearParams(matchWidth: Boolean = false, topMargin: Int = 0, leftMargin: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(if (matchWidth) LinearLayout.LayoutParams.MATCH_PARENT else LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { this.topMargin = topMargin; this.leftMargin = leftMargin }

    private fun roundedBackground(color: Int, radius: Float, strokeColor: Int? = null): GradientDrawable =
        GradientDrawable().apply { setColor(color); cornerRadius = radius; strokeColor?.let { setStroke(dp(1), it) } }

    private fun roundedTopBackground(color: Int, radius: Float): GradientDrawable =
        GradientDrawable().apply { setColor(color); cornerRadii = floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f) }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel(NOTIFICATION_CHANNEL_ID, "Call notes", NotificationManager.IMPORTANCE_LOW))
    }

    private fun createNotification(): Notification {
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        return b.setContentTitle("Telecaller call notes active")
            .setContentText("Use the floating bubble to add notes during the call.")
            .setSmallIcon(android.R.drawable.ic_dialog_info).setOngoing(true).build()
    }

    // ── Constants ─────────────────────────────────────────────────────────────

    companion object {
        const val ACTION_STOP = "app.asaninnovators.leadpilot.STOP_CALL_NOTES_OVERLAY"
        const val EXTRA_LEAD_ID = "leadId"
        const val EXTRA_LEAD_NAME = "leadName"
        const val EXTRA_PHONE_NUMBER = "phoneNumber"
        const val EXTRA_LEAD_SCORE = "leadScore"
        const val EXTRA_TEMPERATURE = "temperature"
        const val EXTRA_INTENT = "intent"
        const val EXTRA_SCRIPT_OPENING = "scriptOpeningLine"
        const val EXTRA_MEMORY_FACTS = "memoryFacts"
        const val EXTRA_LAST_CALL_TS = "lastCallTs"
        const val EXTRA_LAST_CALL_SCORE = "lastCallScore"
        const val EXTRA_LAST_CALL_SUMMARY = "lastCallSummary"
        const val NOTES_PREFERENCES = "lead_pilot_call_notes"
        const val NOTIFICATION_CHANNEL_ID = "lead_pilot_call_notes"
        const val NOTIFICATION_ID = 4307
        fun noteKey(leadId: String) = "notes_$leadId"
    }
}
