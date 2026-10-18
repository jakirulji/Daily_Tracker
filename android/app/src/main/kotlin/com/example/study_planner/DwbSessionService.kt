package com.example.study_planner

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.content.pm.ServiceInfo

class DwbSessionService : Service() {
    companion object {
        const val EXTRA_PACKAGE = "dwb_package"
        const val EXTRA_LABEL = "dwb_label"
        const val EXTRA_LIMIT_MINUTES = "dwb_limit_minutes"
        const val EXTRA_REMINDER_MINUTES = "dwb_reminder_minutes"
        const val EXTRA_OVERLAY_ENABLED = "dwb_overlay_enabled"
        private const val CHANNEL = "dwb_session"
        private const val NOTIFICATION_ID = 7301
    }

    private val handler = Handler(Looper.getMainLooper())
    private var targetPackage = ""
    private var appLabel = "App"
    private var limitMs = 0L
    private var reminderMs = 0L
    private var overlayEnabled = false
    private var startedAt = 0L
    private var nextReminderAt = Long.MAX_VALUE
    private var lastTargetSeenAt = 0L
    private var overlay: android.view.View? = null
    private var windowManager: WindowManager? = null
    private var finished = false

    private val ticker = object : Runnable {
        override fun run() {
            if (finished) return
            val now = System.currentTimeMillis()
            val current = currentForegroundPackage(now)
            if (current == targetPackage) lastTargetSeenAt = now
            if (now - lastTargetSeenAt > 15000L) {
                stopSelf()
                return
            }
            val elapsed = now - startedAt
            if (reminderMs > 0 && now >= nextReminderAt) {
                showNotification("Take a short break", "$appLabel has been open for ${formatTime(elapsed)}.")
                nextReminderAt = now + reminderMs
            }
            if (limitMs > 0 && elapsed >= limitMs) {
                finished = true
                showLimitReached()
                return
            }
            if (limitMs > 0) updateNotification("Time remaining: ${formatTime((limitMs - elapsed).coerceAtLeast(0))}")
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Digital Wellbeing", NotificationManager.IMPORTANCE_HIGH))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        targetPackage = intent?.getStringExtra(EXTRA_PACKAGE).orEmpty()
        appLabel = intent?.getStringExtra(EXTRA_LABEL) ?: targetPackage
        val limit = intent?.getIntExtra(EXTRA_LIMIT_MINUTES, 0) ?: 0
        val reminder = intent?.getIntExtra(EXTRA_REMINDER_MINUTES, 0) ?: 0
        overlayEnabled = intent?.getBooleanExtra(EXTRA_OVERLAY_ENABLED, false) ?: false
        limitMs = limit.coerceAtLeast(0) * 60000L
        reminderMs = reminder.coerceAtLeast(0) * 60000L
        startedAt = System.currentTimeMillis()
        lastTargetSeenAt = startedAt
        nextReminderAt = if (reminderMs > 0) startedAt + reminderMs else Long.MAX_VALUE
        finished = false
        val notification = buildNotification("Session started for $appLabel")
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        handler.removeCallbacks(ticker)
        handler.postDelayed(ticker, 1000L)
        return START_NOT_STICKY
    }

    private fun currentForegroundPackage(now: Long): String? {
        return try {
            val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val events = manager.queryEvents(now - 10000L, now)
            val event = UsageEvents.Event()
            var current: String? = null
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                    (Build.VERSION.SDK_INT >= 29 && event.eventType == UsageEvents.Event.ACTIVITY_RESUMED)) {
                    current = event.packageName
                }
            }
            current
        } catch (_: Exception) { null }
    }

    private fun showLimitReached() {
        showNotification("Time limit reached", "Your $appLabel session has reached its limit. Tap to return to Daily Tracker.")
        if (overlayEnabled && Settings.canDrawOverlays(this)) {
            try {
                val root = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(40, 32, 40, 28)
                    background = GradientDrawable().apply {
                        setColor(0xF01B2030.toInt())
                        cornerRadius = 48f
                        setStroke(2, 0xFF00CEC9.toInt())
                    }
                }
                root.addView(TextView(this).apply {
                    text = "TIME TO PAUSE"
                    setTextColor(0xFF00CEC9.toInt())
                    textSize = 12f
                    letterSpacing = 0.12f
                    typeface = Typeface.DEFAULT_BOLD
                })
                root.addView(TextView(this).apply {
                    text = "$appLabel\nYour planned session is complete. Take a breath before continuing."
                    setTextColor(0xFFFFFFFF.toInt())
                    textSize = 18f
                    setPadding(0, 18, 0, 18)
                })
                root.addView(Button(this).apply {
                    text = "Open Daily Tracker"
                    setOnClickListener {
                        removeOverlay()
                        packageManager.getLaunchIntentForPackage(packageName)?.let {
                            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            startActivity(it)
                        }
                        stopSelf()
                    }
                })
                windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
                val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
                val lp = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    type,
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT
                ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; y = 36 }
                overlay = root
                windowManager?.addView(root, lp)
            } catch (_: Exception) { }
        }
        handler.removeCallbacks(ticker)
        if (!overlayEnabled || !Settings.canDrawOverlays(this)) stopSelf()
    }

    private fun buildNotification(text: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = launch?.let { PendingIntent.getActivity(this, 7301, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Digital Wellbeing").setContentText(text).setOngoing(!finished)
            .apply { if (pi != null) setContentIntent(pi) }.build()
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun showNotification(title: String, text: String) {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = launch?.let { PendingIntent.getActivity(this, 7302, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle(title).setContentText(text)
            .setAutoCancel(true).apply { if (pi != null) setContentIntent(pi) }.build()
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID + 1, notification)
    }

    private fun formatTime(ms: Long): String {
        val minutes = (ms / 60000L).toInt()
        return if (minutes >= 60) "${minutes / 60}h ${minutes % 60}m" else "${minutes}m"
    }

    private fun removeOverlay() {
        try { overlay?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        overlay = null
    }

    override fun onDestroy() {
        handler.removeCallbacks(ticker)
        removeOverlay()
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
