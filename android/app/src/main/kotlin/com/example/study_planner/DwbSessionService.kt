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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * On-device focus-session timer and optional strict daily app-limit monitor.
 * No usage data leaves the device. Android Usage Access and overlay access are
 * user-granted special permissions; strict blocking is disabled without both.
 */
class DwbSessionService : Service() {
    companion object {
        const val EXTRA_PACKAGE = "dwb_package"
        const val EXTRA_LABEL = "dwb_label"
        const val EXTRA_LIMIT_MINUTES = "dwb_limit_minutes"
        const val EXTRA_REMINDER_MINUTES = "dwb_reminder_minutes"
        const val EXTRA_OVERLAY_ENABLED = "dwb_overlay_enabled"
        const val ACTION_CONFIGURE_BLOCKING = "com.dailytracker.dwb.CONFIGURE_BLOCKING"
        private const val CHANNEL = "dwb_session"
        private const val REMINDER_CHANNEL = "dwb_reminders"
        private const val NOTIFICATION_ID = 7301
        private const val BLOCKING_NOTIFICATION_ID = 7303
        @Volatile private var liveInstance: DwbSessionService? = null

        fun onAccessibilityPackageChanged(packageName: String) {
            liveInstance?.handleAccessibilityPackageChanged(packageName)
        }
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
    private var overlayPackage = ""
    private var windowManager: WindowManager? = null
    private var finished = false
    private var blockingMonitor = false
    private var foregroundPackage: String? = null
    private var foregroundSince = 0L
    private var foregroundBaseUsageMs = 0L
    @Volatile private var accessibilityForegroundPackage: String? = null
    @Volatile private var accessibilityForegroundAt = 0L
    private val gentleNextReminderAt = HashMap<String, Long>()
    private var lastGentleForeground: String? = null

    private val ticker = object : Runnable {
        override fun run() {
            if (finished) return
            if (blockingMonitor) {
                checkStrictBlocking()
                if (targetPackage.isEmpty()) {
                    handler.postDelayed(this, 1000L)
                    return
                }
            }
            val now = System.currentTimeMillis()
            val current = currentForegroundPackage(now)
            if (current == targetPackage) lastTargetSeenAt = now
            if (now - lastTargetSeenAt > 15000L) {
                if (blockingMonitor) {
                    // A focus session ending must not kill the persistent block monitor.
                    targetPackage = ""
                    appLabel = "App"
                    limitMs = 0L
                    reminderMs = 0L
                    overlayEnabled = false
                    lastTargetSeenAt = 0L
                    handler.postDelayed(this, 1000L)
                } else {
                    stopSelf()
                }
                return
            }
            val elapsed = now - startedAt
            if (reminderMs > 0 && now >= nextReminderAt) {
                showNotification("Take a short break", "$appLabel has been open for ${formatTime(elapsed)}.")
                nextReminderAt = now + reminderMs
            }
            if (limitMs > 0 && elapsed >= limitMs) {
                if (blockingMonitor) {
                    showNotification("Focus session complete", "$appLabel reached its focus-session limit.")
                    targetPackage = ""
                    limitMs = 0L
                    reminderMs = 0L
                    handler.postDelayed(this, 1000L)
                    return
                }
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
        liveInstance = this
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Digital Wellbeing", NotificationManager.IMPORTANCE_LOW))
            nm.createNotificationChannel(NotificationChannel(REMINDER_CHANNEL, "Mindful pause reminders", NotificationManager.IMPORTANCE_HIGH))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        finished = false
        if (intent?.action == ACTION_CONFIGURE_BLOCKING) {
            blockingMonitor = true
            targetPackage = ""
            val notification = buildNotification("Strict app limits are being monitored on this device")
            startAsForeground(notification)
            handler.removeCallbacks(ticker)
            handler.post(ticker)
            return START_STICKY
        }
        val blockingPrefs = getSharedPreferences("dwb_blocking", Context.MODE_PRIVATE)
        blockingMonitor = (blockingPrefs.getBoolean("enabled", false) &&
            !blockingPrefs.getStringSet("selectedPackages", emptySet()).isNullOrEmpty()) ||
            !blockingPrefs.getStringSet("gentlePackages", emptySet()).isNullOrEmpty()
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
        startAsForeground(buildNotification("Session started for $appLabel"))
        handler.removeCallbacks(ticker)
        handler.postDelayed(ticker, 1000L)
        return START_NOT_STICKY
    }

    private fun startAsForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    /** Called directly by AccessibilityService to avoid waiting for the UsageStats polling interval. */
    private fun handleAccessibilityPackageChanged(pkg: String) {
        if (pkg.isBlank() || pkg == packageName) return
        val now = System.currentTimeMillis()
        val old = accessibilityForegroundPackage
        accessibilityForegroundPackage = pkg
        accessibilityForegroundAt = now
        if (old != pkg) {
            if (overlay != null && overlayPackage != pkg) removeOverlay()
            val dayStart = java.util.Calendar.getInstance().apply {
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }.timeInMillis
            foregroundBaseUsageMs = runCatching {
                val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, dayStart, now)
                    .filter { it.packageName == pkg }
                    .maxOfOrNull { it.totalTimeInForeground } ?: 0L
            }.getOrDefault(0L)
            foregroundPackage = pkg
            foregroundSince = now
            if (blockingMonitor) checkStrictBlocking()
        }
    }

    private fun checkStrictBlocking() {
        val prefs = getSharedPreferences("dwb_blocking", Context.MODE_PRIVATE)
        val strictEnabled = prefs.getBoolean("enabled", false)
        val selected = prefs.getStringSet("selectedPackages", emptySet())?.toSet().orEmpty()
        val gentleSelected = prefs.getStringSet("gentlePackages", emptySet())?.toSet().orEmpty()
        val gentleReminderMinutes = prefs.getInt("gentleReminderMinutes", 5).coerceIn(1, 60)
        val gentlePauseEnabled = prefs.getBoolean("gentlePauseEnabled", true)
        val gentlePauseSeconds = prefs.getInt("gentlePauseSeconds", 10).coerceIn(0, 60)
        val gentleOverlayReminders = prefs.getBoolean("gentleOverlayReminders", true)

        if (!hasUsageAccess()) {
            removeOverlay()
            stopSelf()
            return
        }
        if (!strictEnabled && gentleSelected.isEmpty()) {
            removeOverlay()
            stopSelf()
            return
        }
        val canStrictBlock = strictEnabled && selected.isNotEmpty() && Settings.canDrawOverlays(this)
        if (!canStrictBlock) {
            if (overlayPackage !in gentleSelected) removeOverlay()
        }

        val now = System.currentTimeMillis()
        val previousForeground = foregroundPackage
        val current = currentForegroundPackage(now)

        // Gentle mode is independent from Strict: a first-open pause and periodic reminders,
        // but never the daily-limit blocking overlay.
        if (current != lastGentleForeground) {
            lastGentleForeground = current
            if (current != null && current in gentleSelected && gentlePauseEnabled &&
                gentlePauseSeconds > 0 && Settings.canDrawOverlays(this)) {
                showGentlePauseOverlay(current, appLabelFor(current), gentlePauseSeconds)
            }
        }
        if (current != null && current in gentleSelected) {
            val next = gentleNextReminderAt[current] ?: (now + gentleReminderMinutes * 60000L)
            if (now >= next) {
                val label = appLabelFor(current)
                if (gentleOverlayReminders && Settings.canDrawOverlays(this)) {
                    showGentleReminderOverlay(current, label, now - (next - gentleReminderMinutes * 60000L))
                } else {
                    showNotification("Take a mindful pause", "You have been using $label. Pause, then decide whether to continue.")
                }
                gentleNextReminderAt[current] = now + gentleReminderMinutes * 60000L
            } else {
                gentleNextReminderAt.putIfAbsent(current, next)
            }
        }
        // Reset the per-app interval after switching away, as Dragon Launcher does.
        gentleNextReminderAt.keys.toList().filter { it != current || it !in gentleSelected }
            .forEach { gentleNextReminderAt.remove(it) }

        if (!canStrictBlock) return

        val dayStart = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis
        val dayKey = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date(now))
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val stats = runCatching { manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, dayStart, now) }.getOrNull().orEmpty()
        val usedMs = HashMap<String, Long>()
        for (item in stats) {
            if (item.packageName in selected) {
                usedMs[item.packageName] = maxOf(usedMs[item.packageName] ?: 0L, item.totalTimeInForeground)
            }
        }

        if (current != previousForeground) {
            foregroundBaseUsageMs = current?.let { usedMs[it] ?: 0L } ?: 0L
        }
        var lockedPackage: String? = null
        var lockedLabel = "App"
        for (pkg in selected) {
            val limitMinutes = prefs.getInt("limit.$pkg", 30)
            if (limitMinutes <= 0) continue
            val lockKey = "locked.$pkg"
            val isLocked = prefs.getString(lockKey, null) == dayKey
            if (isLocked) {
                if (current == pkg) {
                    lockedPackage = pkg
                    lockedLabel = appLabelFor(pkg)
                    break
                }
                continue
            }
            var used = usedMs[pkg] ?: 0L
            if (current == pkg && foregroundSince > 0L) {
                used = maxOf(used, foregroundBaseUsageMs + (now - foregroundSince).coerceAtLeast(0L))
            }
            if (used >= limitMinutes * 60000L) {
                prefs.edit().putString(lockKey, dayKey).apply()
                if (current == pkg) {
                    lockedPackage = pkg
                    lockedLabel = appLabelFor(pkg)
                }
            }
        }
        if (lockedPackage != null) {
            showBlockingOverlay(lockedPackage, lockedLabel)
            getSystemService(NotificationManager::class.java).notify(
                BLOCKING_NOTIFICATION_ID,
                buildNotification("Daily limit reached for $lockedLabel. The pause screen will appear when it is opened again.")
            )
        } else {
            if (overlayPackage !in gentleSelected) removeOverlay()
        }
    }

    private fun hasUsageAccess(): Boolean {
        return try {
            val ops = getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= 29) {
                ops.unsafeCheckOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
            }
            mode == android.app.AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) { false }
    }

    @Suppress("DEPRECATION")
    private fun appLabelFor(pkg: String): String = runCatching {
        val info = if (Build.VERSION.SDK_INT >= 33) packageManager.getApplicationInfo(pkg, android.content.pm.PackageManager.ApplicationInfoFlags.of(0L))
                   else packageManager.getApplicationInfo(pkg, 0)
        packageManager.getApplicationLabel(info).toString()
    }.getOrDefault(pkg)

    private fun currentForegroundPackage(now: Long): String? {
        val accessiblePkg = accessibilityForegroundPackage
        if (!accessiblePkg.isNullOrBlank() && now - accessibilityForegroundAt <= 5000L) return accessiblePkg
        return try {
            val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val events = manager.queryEvents(now - 120000L, now)
            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val pkg = event.packageName ?: continue
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                    (Build.VERSION.SDK_INT >= 29 && event.eventType == UsageEvents.Event.ACTIVITY_RESUMED)) {
                    foregroundPackage = pkg
                    foregroundSince = event.timeStamp
                } else if (event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND ||
                    (Build.VERSION.SDK_INT >= 29 && event.eventType == UsageEvents.Event.ACTIVITY_PAUSED)) {
                    if (foregroundPackage == pkg) {
                        foregroundPackage = null
                        foregroundSince = 0L
                    }
                }
            }
            foregroundPackage
        } catch (_: Exception) { foregroundPackage }
    }

    /**
     * Best-effort mindful pause when a Gentle app becomes foreground.
     * Android does not let an ordinary app intercept another launch before it starts;
     * AccessibilityService triggers this as soon as Android reports the foreground app; Usage Access polling remains a fallback.
     */
    private fun showGentlePauseOverlay(pkg: String, label: String, seconds: Int) {
        if (overlay != null || !Settings.canDrawOverlays(this)) return
        try {
            val root = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(48, 64, 48, 64)
                background = GradientDrawable().apply {
                    setColor(0xF51B2030.toInt())
                    cornerRadius = 32f
                    setStroke(2, 0xFF00CEC9.toInt())
                }
            }
            root.addView(TextView(this).apply {
                text = "TAKE A BREATH"
                setTextColor(0xFF68F0D5.toInt())
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
            })
            root.addView(TextView(this).apply {
                text = label
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 26f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setPadding(0, 18, 0, 12)
            })
            val message = TextView(this).apply {
                text = "Pause for a moment before continuing."
                setTextColor(0xFFE2E8F0.toInt())
                textSize = 16f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, 20)
            }
            root.addView(message)
            val continueButton = Button(this).apply {
                text = "Continue"
                isEnabled = false
                setOnClickListener { removeOverlay() }
            }
            root.addView(continueButton)
            root.addView(Button(this).apply {
                text = "Leave app"
                setOnClickListener {
                    removeOverlay()
                    startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            })
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
            val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.CENTER }
            overlay = root
            overlayPackage = pkg
            windowManager?.addView(root, lp)

            var remaining = seconds
            val countdown = object : Runnable {
                override fun run() {
                    if (overlay !== root) return
                    if (remaining <= 0) {
                        message.text = "Take a breath. Continue when you are ready."
                        continueButton.isEnabled = true
                        return
                    }
                    message.text = "Pause for a moment before continuing.\nContinuing in $remaining seconds…"
                    remaining--
                    handler.postDelayed(this, 1000L)
                }
            }
            handler.post(countdown)
        } catch (_: Exception) {
            overlay = null
            overlayPackage = ""
        }
    }

    /** Dragon Launcher-style transient reminder card; Gentle never blocks the app. */
    private fun showGentleReminderOverlay(pkg: String, label: String, elapsedMs: Long) {
        if (overlay != null || !Settings.canDrawOverlays(this)) return
        try {
            val card = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(44, 32, 44, 32)
                background = GradientDrawable().apply {
                    setColor(0xF51B2030.toInt())
                    cornerRadius = 28f
                    setStroke(2, 0xFF6C5CE7.toInt())
                }
                addView(TextView(this@DwbSessionService).apply {
                    text = "Mindful pause · $label"
                    setTextColor(0xFFFFFFFF.toInt())
                    textSize = 18f
                    typeface = Typeface.DEFAULT_BOLD
                })
                addView(TextView(this@DwbSessionService).apply {
                    text = "You have been using this app for ${formatTime(elapsedMs)}. Pause, then decide whether to continue."
                    setTextColor(0xFFE2E8F0.toInt())
                    textSize = 14f
                    setPadding(0, 12, 0, 0)
                })
            }
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
            val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL }
            overlay = card
            overlayPackage = pkg
            windowManager?.addView(card, lp)
            handler.postDelayed({ if (overlay === card) removeOverlay() }, 7000L)
        } catch (_: Exception) {
            overlay = null
            overlayPackage = ""
        }
    }

    private fun showBlockingOverlay(pkg: String, label: String) {
        if (overlay != null && overlayPackage == pkg) return
        removeOverlay()
        try {
            val root = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(52, 64, 52, 64)
                background = GradientDrawable().apply {
                    setColor(0xF51B2030.toInt())
                    cornerRadius = 0f
                    setStroke(2, 0xFF00CEC9.toInt())
                }
                isFocusable = true
                isFocusableInTouchMode = true
            }
            root.addView(TextView(this).apply {
                text = "DAILY LIMIT REACHED"
                setTextColor(0xFF68F0D5.toInt())
                textSize = 13f
                letterSpacing = 0.12f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
            })
            root.addView(TextView(this).apply {
                text = label
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 27f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setPadding(0, 22, 0, 8)
            })
            root.addView(TextView(this).apply {
                text = "You reached today's limit. Take a break and come back tomorrow. Reopening this app will show this pause screen again."
                setTextColor(0xFFE2E8F0.toInt())
                textSize = 16f
                gravity = Gravity.CENTER
                setPadding(0, 8, 0, 30)
            })
            root.addView(Button(this).apply {
                text = "Leave app"
                setOnClickListener {
                    removeOverlay()
                    val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(home)
                }
            })
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
            val type = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.CENTER; softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING }
            overlay = root
            overlayPackage = pkg
            windowManager?.addView(root, lp)
        } catch (_: Exception) {
            overlay = null
            overlayPackage = ""
        }
    }

    private fun showLimitReached() {
        showNotification("Time limit reached", "Your $appLabel session has reached its limit. Tap to return to Daily Tracker.")
        if (overlayEnabled && Settings.canDrawOverlays(this)) {
            showBlockingOverlay(targetPackage, appLabel)
        }
        handler.removeCallbacks(ticker)
        if (!overlayEnabled || !Settings.canDrawOverlays(this)) stopSelf()
    }

    private fun buildNotification(text: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = launch?.let { PendingIntent.getActivity(this, 7301, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Digital Wellbeing").setContentText(text).setOngoing(true)
            .apply { if (pi != null) setContentIntent(pi) }.build()
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun showNotification(title: String, text: String) {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = launch?.let { PendingIntent.getActivity(this, 7302, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, REMINDER_CHANNEL) else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title).setContentText(text).setAutoCancel(true)
            .apply { if (pi != null) setContentIntent(pi) }.build()
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID + 1, notification)
    }

    private fun formatTime(ms: Long): String {
        val minutes = (ms / 60000L).toInt()
        return if (minutes >= 60) "${minutes / 60}h ${minutes % 60}m" else "${minutes}m"
    }

    private fun removeOverlay() {
        try { overlay?.let { windowManager?.removeView(it) } } catch (_: Exception) {}
        overlay = null
        overlayPackage = ""
    }

    override fun onDestroy() {
        if (liveInstance === this) liveInstance = null
        handler.removeCallbacks(ticker)
        removeOverlay()
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
