package com.example.lead_pilot_telecaller

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

class CallNotesOverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    private var leadId = ""
    private var leadName = ""
    private var phoneNumber = ""

    private val notesPreferences by lazy {
        getSharedPreferences(NOTES_PREFERENCES, Context.MODE_PRIVATE)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        leadId = intent?.getStringExtra(EXTRA_LEAD_ID).orEmpty()
        leadName = intent?.getStringExtra(EXTRA_LEAD_NAME).orEmpty()
        phoneNumber = intent?.getStringExtra(EXTRA_PHONE_NUMBER).orEmpty()

        if (overlayView == null) {
            showCollapsedBubble()
        }

        return START_STICKY
    }

    override fun onDestroy() {
        removeOverlay()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun showCollapsedBubble() {
        val bubble = TextView(this).apply {
            text = "LP"
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = roundedBackground(Color.rgb(37, 99, 235), dp(22).toFloat())
            elevation = dp(8).toFloat()
        }

        val params = baseLayoutParams(width = dp(56), height = dp(56)).apply {
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            x = dp(18)
            y = dp(160)
        }

        attachOverlay(bubble, params)
        makeDraggable(bubble, params) { showExpandedPanel(params.x, params.y) }
    }

    private fun showExpandedPanel(x: Int, y: Int) {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = roundedBackground(Color.WHITE, dp(14).toFloat(), Color.rgb(221, 221, 221))
            elevation = dp(10).toFloat()
        }

        val title = TextView(this).apply {
            text = if (leadName.isBlank()) "Call notes" else leadName
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.rgb(31, 31, 31))
            maxLines = 1
        }
        panel.addView(title, linearParams(matchWidth = true))

        val subtitle = TextView(this).apply {
            text = phoneNumber
            textSize = 12f
            setTextColor(Color.rgb(107, 107, 107))
            maxLines = 1
        }
        panel.addView(subtitle, linearParams(matchWidth = true))

        val notesField = EditText(this).apply {
            setText(notesPreferences.getString(noteKey(leadId), "").orEmpty())
            hint = "Add call notes..."
            textSize = 14f
            minLines = 4
            maxLines = 6
            gravity = Gravity.TOP or Gravity.START
            setTextColor(Color.rgb(31, 31, 31))
            setHintTextColor(Color.rgb(150, 150, 150))
            background = roundedBackground(Color.rgb(247, 247, 247), dp(8).toFloat(), Color.rgb(226, 226, 226))
            setPadding(dp(10), dp(8), dp(10), dp(8))
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    saveNotes(s?.toString().orEmpty())
                }

                override fun afterTextChanged(s: Editable?) = Unit
            })
        }
        panel.addView(notesField, linearParams(matchWidth = true, topMargin = dp(10)))

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        val minimize = actionButton("Minimize")
        val close = actionButton("Save & Close")
        actions.addView(minimize)
        actions.addView(close, linearParams(leftMargin = dp(8)))
        panel.addView(actions, linearParams(matchWidth = true, topMargin = dp(10)))

        val params = baseLayoutParams(width = dp(320), height = WindowManager.LayoutParams.WRAP_CONTENT).apply {
            flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
            this.x = x
            this.y = y
        }

        attachOverlay(panel, params)
        makeDraggable(title, params)

        minimize.setOnClickListener {
            saveNotes(notesField.text?.toString().orEmpty())
            hideKeyboard(notesField)
            showCollapsedBubbleAt(params.x, params.y)
        }
        close.setOnClickListener {
            saveNotes(notesField.text?.toString().orEmpty())
            hideKeyboard(notesField)
            openPostCallScreen()
            stopSelf()
        }

        notesField.requestFocus()
        notesField.post {
            val inputMethodManager = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            inputMethodManager.showSoftInput(notesField, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun showCollapsedBubbleAt(x: Int, y: Int) {
        showCollapsedBubble()
        layoutParams?.let {
            it.x = x
            it.y = y
            overlayView?.let { view -> windowManager.updateViewLayout(view, it) }
        }
    }

    private fun attachOverlay(view: View, params: WindowManager.LayoutParams) {
        removeOverlay()
        overlayView = view
        layoutParams = params
        windowManager.addView(view, params)
    }

    private fun removeOverlay() {
        overlayView?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
            }
        }
        overlayView = null
        layoutParams = null
    }

    private fun makeDraggable(view: View, params: WindowManager.LayoutParams, onClick: (() -> Unit)? = null) {
        var startX = 0
        var startY = 0
        var startRawX = 0f
        var startRawY = 0f
        var moved = false

        view.setOnTouchListener { touchedView, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    startRawX = event.rawX
                    startRawY = event.rawY
                    moved = false
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - startRawX).toInt()
                    val dy = (event.rawY - startRawY).toInt()
                    if (kotlin.math.abs(dx) > dp(4) || kotlin.math.abs(dy) > dp(4)) {
                        moved = true
                    }
                    params.x = startX + dx
                    params.y = startY + dy
                    overlayView?.let { windowManager.updateViewLayout(it, params) }
                    true
                }

                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        touchedView.performClick()
                        onClick?.invoke()
                    }
                    true
                }

                else -> false
            }
        }
    }

    private fun baseLayoutParams(width: Int, height: Int): WindowManager.LayoutParams {
        val overlayType =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

        return WindowManager.LayoutParams(
            width,
            height,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
    }

    private fun actionButton(label: String): Button =
        Button(this).apply {
            text = label
            textSize = 12f
            isAllCaps = false
            minHeight = dp(40)
            minimumHeight = dp(40)
        }

    private fun linearParams(
        matchWidth: Boolean = false,
        topMargin: Int = 0,
        leftMargin: Int = 0,
    ): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(
            if (matchWidth) LinearLayout.LayoutParams.MATCH_PARENT else LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply {
            this.topMargin = topMargin
            this.leftMargin = leftMargin
        }

    private fun roundedBackground(color: Int, radius: Float, strokeColor: Int? = null): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
            strokeColor?.let { setStroke(dp(1), it) }
        }

    private fun saveNotes(notes: String) {
        if (leadId.isBlank()) return
        notesPreferences.edit().putString(noteKey(leadId), notes).apply()
    }

    private fun hideKeyboard(view: View) {
        val inputMethodManager = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        inputMethodManager.hideSoftInputFromWindow(view.windowToken, 0)
    }

    private fun openPostCallScreen() {
        if (leadId.isBlank()) return

        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("leadpilot://app/leads/$leadId/post-call")
            setPackage(packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Call notes",
            NotificationManager.IMPORTANCE_LOW,
        )
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.createNotificationChannel(channel)
    }

    private fun createNotification(): Notification {
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

        return builder
            .setContentTitle("LeadPilot call notes active")
            .setContentText("Use the floating bubble to add notes during the call.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val ACTION_STOP = "com.example.lead_pilot_telecaller.STOP_CALL_NOTES_OVERLAY"
        const val EXTRA_LEAD_ID = "leadId"
        const val EXTRA_LEAD_NAME = "leadName"
        const val EXTRA_PHONE_NUMBER = "phoneNumber"
        const val NOTES_PREFERENCES = "lead_pilot_call_notes"
        const val NOTIFICATION_CHANNEL_ID = "lead_pilot_call_notes"
        const val NOTIFICATION_ID = 4307

        fun noteKey(leadId: String): String = "notes_$leadId"
    }
}
