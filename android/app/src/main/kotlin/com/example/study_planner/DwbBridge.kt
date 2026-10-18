package com.example.study_planner

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Process
import android.provider.Settings
import android.app.Activity
import android.content.ComponentName
import android.content.pm.ResolveInfo
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

object DwbBridge {
    private const val CHANNEL = "com.dailytracker/dwb"

    fun register(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "hasUsageAccess" -> result.success(hasUsageAccess(activity))
                    "openUsageAccessSettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(true)
                    }
                    "hasOverlayPermission" -> result.success(Settings.canDrawOverlays(activity))
                    "openOverlaySettings" -> {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                            data = android.net.Uri.parse("package:" + activity.packageName)
                        })
                        result.success(true)
                    }
                    "getUsageStats" -> result.success(getUsageStats(activity))
                    "launchApp" -> {
                        val pkg = call.argument<String>("packageName")
                        val launch = pkg?.let { activity.packageManager.getLaunchIntentForPackage(it) }
                        if (launch == null) result.success(false)
                        else {
                            activity.startActivity(launch)
                            result.success(true)
                        }
                    }
                    "configureBlocking" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val selected = call.argument<List<String>>("selectedPackages") ?: emptyList()
                        val gentle = call.argument<List<String>>("gentlePackages") ?: emptyList()
                        val gentleReminder = call.argument<Int>("gentleReminderMinutes") ?: 5
                        val limits = call.argument<Map<String, Int>>("limits") ?: emptyMap()
                        val prefs = activity.getSharedPreferences("dwb_blocking", Context.MODE_PRIVATE)
                        val editor = prefs.edit()
                            .putBoolean("enabled", enabled && selected.isNotEmpty())
                            .putStringSet("selectedPackages", selected.toSet())
                            .putStringSet("gentlePackages", gentle.toSet())
                            .putInt("gentleReminderMinutes", gentleReminder.coerceIn(0, 60))
                        limits.forEach { (pkg, minutes) -> editor.putInt("limit.$pkg", minutes.coerceIn(0, 1440)) }
                        editor.apply()
                        if ((enabled && selected.isNotEmpty()) || gentle.isNotEmpty()) {
                            val intent = Intent(activity, DwbSessionService::class.java).setAction(DwbSessionService.ACTION_CONFIGURE_BLOCKING)
                            if (android.os.Build.VERSION.SDK_INT >= 26) activity.startForegroundService(intent) else activity.startService(intent)
                        } else {
                            activity.stopService(Intent(activity, DwbSessionService::class.java))
                        }
                        result.success(true)
                    }
                    "startSession" -> {
                        val pkg = call.argument<String>("packageName") ?: throw IllegalArgumentException("Missing packageName")
                        val label = call.argument<String>("appName") ?: pkg
                        val limit = call.argument<Int>("limitMinutes") ?: 0
                        val reminder = call.argument<Int>("reminderMinutes") ?: 0
                        val intent = Intent(activity, DwbSessionService::class.java).apply {
                            putExtra(DwbSessionService.EXTRA_PACKAGE, pkg)
                            putExtra(DwbSessionService.EXTRA_LABEL, label)
                            putExtra(DwbSessionService.EXTRA_LIMIT_MINUTES, limit)
                            putExtra(DwbSessionService.EXTRA_REMINDER_MINUTES, reminder)
                            putExtra(DwbSessionService.EXTRA_OVERLAY_ENABLED, call.argument<Boolean>("overlayEnabled") ?: false)
                        }
                        if (android.os.Build.VERSION.SDK_INT >= 26) activity.startForegroundService(intent) else activity.startService(intent)
                        result.success(true)
                    }
                    "stopSession" -> {
                        activity.stopService(Intent(activity, DwbSessionService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("DWB_ERROR", e.message ?: "Digital Wellbeing action failed", null)
            }
        }
    }

    private fun hasUsageAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (android.os.Build.VERSION.SDK_INT >= 29) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun getUsageStats(context: Context): List<Map<String, Any>> {
        if (!hasUsageAccess(context)) return emptyList()
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val todayCalendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val todayStart = todayCalendar.timeInMillis
        val yesterdayStart = (todayCalendar.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, -1) }.timeInMillis
        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, yesterdayStart, now)
            .groupBy { it.packageName }
        // QUERY_ALL_PACKAGES is added to the DWB manifest by the GitHub Actions build.
        // Enumerate installed packages, then keep user-launchable apps so app labels and
        // package IDs (including Facebook/YouTube) are available for selection.
        val apps = if (android.os.Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getInstalledApplications(0)
        }
        val seen = HashSet<String>()
        val rows = ArrayList<Map<String, Any>>()
        for (info in apps) {
            val pkg = info.packageName
            if (pkg == context.packageName || !seen.add(pkg)) continue
            val launchIntent = context.packageManager.getLaunchIntentForPackage(pkg) ?: continue
            val label = runCatching { context.packageManager.getApplicationLabel(info).toString() }.getOrDefault(pkg)
            val entries = stats[pkg].orEmpty()
            val today = entries.filter { it.lastTimeUsed >= todayStart }.sumOf { it.totalTimeInForeground } / 60000L
            val yesterday = entries.filter { it.lastTimeUsed in yesterdayStart until todayStart }.sumOf { it.totalTimeInForeground } / 60000L
            rows.add(mapOf("packageName" to pkg, "label" to label, "todayMinutes" to today.toInt(), "yesterdayMinutes" to yesterday.toInt()))
        }
        return rows.sortedWith(compareByDescending<Map<String, Any>> { it["todayMinutes"] as Int }.thenBy { it["label"].toString().lowercase() })
    }
}
